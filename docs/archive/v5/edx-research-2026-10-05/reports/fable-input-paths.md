The Mac stays awake (two `caffeinate` holders, pid 4914 for 24 h and pid 7722 for 2 h; `pmset -g assertions` shows `PreventUserIdleSystemSleep 1`). Nothing was written under the repo; the only scratch activity was reading. Report follows.

# Input paths and data model for EDX in mac4DSTEM — design analysis

**Source marks.** `[repo file:line]` = read by me at HEAD `85920f91`. `[rsciio file:line]` = read by me in the clone at `$S/rsciio` (commit `049e7d70`). `[velox]`, `[gms]`, `[formats]`, `[ownerdata]`, `[repo-report]`, `[validation]`, `[market]` = the sibling reports in the brief, not re-derived. `[scan]` = my own pass over `$S/ownerdata/emd_scan.jsonl` and `dm_scan.jsonl`. `(unverified)` = inference. `$S` = `<scratch>/edx`.

## 0. Bottom line

1. **Two linked signals with an explicit registration record (model M2) is the only model that fits the data the owner actually has**: 104 standalone Velox `.emd` spectrum images on a 2048² raster and GMS 4D `.dm4` cubes on 128²–330² scans, from different sessions and different fields `[ownerdata §3–5]`. A combined 5-axis object (M1) cannot represent a pair whose grids differ, and "EDX as a product of the 4D dataset" (M3) bakes the registration in at import and cannot open a plain SI. M3 survives as a *derived cache* on top of M2.
2. **The Velox stream is decoded once into a sparse per-pixel store on the spectrum's own grid**, never into a dense cube: the owner's largest stream is 1.59 G uint16 words (3.2 GB on disk) for an 1800×1800 SI over 480 frames; dense uint16 would be 26.5 GB, while the event count is about 35 M `[scan]`, so a CSR store is ≤ 0.25 GB. That keeps an 8 GB Mac inside the repo's own tile budget (`physicalMemory/24` ≈ 341 MB per tile `[repo FourDArray.swift:366-412]`).
3. **GMS same-file 4D + EDS is the easy path once it exists**: one `.dm4` document, the EDS SI a dense float32 `[x, y, E]` object served from the same memory mapping as the cube, registration = identity proven by tags (`Experiment ID`, `Spatial Sampling`, `Last pixel`). It is inferred, not seen `[gms §2a, formats §1]`; the owner has never recorded one `[ownerdata §1]`.
4. **Registration is a first-class, composable record against the 4D SOURCE grid**, composed at the moment of use with `LoadView.sourceScanY/X` `[repo LoadSpecification.swift:365-367]` and (for preprocessed `.h5`) with `DataCubeDerivation` `[repo BraggVectorEMDTypes.swift:308-417]`. Two registrations exist, not one: intra-file frame alignment (Velox frames drift; the raw stream is per frame) and the cross-file transform.
5. **Three repo defects to fix before any of this, all in shipped opening**: a Velox `.emd` or an EDS `.hspy` opened today goes to `H5Reader` by extension `[repo AppState+Open.swift:241-248]` and is likely promoted to a one-row "datacube" `[repo-report §1e]`; a DM 3D SI is skipped only by the accident of a global `Scan shape` search `[repo DM4Reader.swift:753,878-881]`; `axisDomain` knows no `eV`/`keV` `[repo DM4Reader.swift:815-830]`.

## 1. The facts the design has to respect

| Fact | Consequence | Source |
|---|---|---|
| Every 4D abstraction is `is4D`-gated: `DatasetDescriptor.is4D` (`shape.count == 4`), `LoadView.init` throws `notFourDimensional`, `ResidencyAdmission.shouldAdmit` guards `is4D`, `openFileForConfiguration` refuses a non-4D source with `unsupportedRank` | A spectrum signal needs sibling types, not a widened `DatasetDescriptor` | `[repo DatasetDescriptor.swift:37; LoadSpecification.swift init; ResidentCube.swift:185; AppState+Open.swift:36-40]` |
| `FourDDataSource` is an actor protocol with `LoadView`-taking reads and a declared `loadPushdown` | The pattern generalises; the protocol does not | `[repo FourDDataSource.swift:165-217]` |
| `DatasetSession` owns one `reader`, one `fourD`, one `epoch` | The spectrum signal needs its own owner, keyed to the 4D epoch only through the registration | `[repo DatasetSession.swift:19-27]` |
| All HDF5 calls run under one recursive process lock, never across an `await` | A long Velox decode must release the lock between blocks or it stalls 4D tile reads from `.h5` cubes | `[repo HDF5Types.swift:78-128]` |
| `HDF5Library` is `nonisolated private` to `H5Reader.swift`; native types loaded: FLOAT, DOUBLE, INT, C_S1; attributes are opened by name (`H5Aopen`), no iteration | A Velox/DM5 reader either lives in `H5Reader.swift` or the library goes `package`; USHORT/UCHAR/ULLONG and `H5Aiterate2` are new symbols | `[repo H5Reader.swift:81,238-241,995-1055]` |
| DM4 is memory-mapped on local volumes with a held-descriptor liveness latch; `dataArrays` records every `Data` blob; ushort arrays < 1000 B become `strings` (so `Meta Data.Format`, `Signal`, units are already parsed) | A DM spectrum facade shares the mapping and the latch for free | `[repo DM4Reader.swift:39-96,225-229,587,680-684]` |
| Sandbox: `user-selected.read-write` + `bookmarks.app-scope`; recents and the sidecar hold security-scoped bookmarks | A second input file needs its own user selection and bookmark; it travels in the sidecar as name + fingerprint | `[repo mac4DSTEM.entitlements; WorkspaceRecovery.swift:173-190; SessionSidecarLocator.swift:265-288]` |
| `SessionLineage.External` (name + fingerprint) and `recordRun(external:)` exist; unknown kinds must be lineage-only or `ReplayPlanner` refuses | Lineage needs no format change; EDX kinds go into `lineageOnlyKinds` | `[repo SessionLineage.swift:83-91,177-180,507]`, `[repo-report §1d]` |
| Owner's Velox data: 141 stream entries / 104 unique acquisitions; median stream 42 M words, median SI 0.4 M pixels, max 4.2 M pixels (2048²); 11–19 X-ray counts per pixel on Al-Mg-Si, 70 % of them Al Kα | Per-pixel spectra are nearly empty; the store must be sparse and the model must carry per-pixel frame counts | `[scan]`, `[ownerdata §4,7]` |
| Owner's GMS cubes: float32, detector-fastest tags `[1/nm,1/nm,µm,µm]`, 17–29 GB, `DigiScan (hardware-sync)`, no X-ray SI anywhere | The same-file path cannot be tested on his data yet | `[scan 060_STEM SI]`, `[ownerdata §1,3]` |
| Velox stream: uint16 events, 65535 = next pixel, frames implicit, `FrameLocationTable` gives frame start offsets (rsciio does not use it, TODO at :151), metadata JSON in column 0 of a `(60000, nFrames)` uint8 dataset, shape must come from `ScanSize × ScanArea` not from an image (rsciio takes it from the last image read at :335) | The decoder is simple and verifiable; the shape rule and frame handling must deviate from rsciio | `[rsciio _fei_stream_readers.py:264-317; _emd_velox.py:151,335; utils/hdf5.py:170-174]`, `[formats §2.2]` |
| Velox drift compensation is per frame by cross-correlation of the STEM reference frames; the HAADF stack `(1800, 1800, 480)` is in the file; whether the per-frame shifts are stored is **unverified** | Summing raw frames without shifts smears by the drift. The reader needs a frame axis and an intra-file alignment step; `MatrixDFTCorrelation.refinedPeak` + `FFT2D` already exist for it | `[velox §1 drift]`, `[scan]`, `[repo-report §3 Registration]` |
| GMS SI tags carry the linkage: `Meta Data.Experiment keywords.*.Experiment ID`, `Meta Data.Format = Spectrum image`, `Meta Data.Signal`, `SI.Acquisition.Spatial Sampling.{Width,Height}`, `Last pixel`, `Survey Image.Spectrum Image Rect`, energy axis `Dimension.#2` in eV with `Origin −300, Scale 1.0` | Identity registration can be proven from tags, not assumed | `[$S/formats/eels_si_dm4_tags.txt:101-109,258-262,323-332]` |

## 2. The data-model options

### M1 — one combined 5-axis object `[ry, rx, qy, qx, E]`
One descriptor, one reader, one residency rule. It only exists if both signals share one scan grid — the GMS same-file case. It cannot hold the owner's Velox-vs-GMS pairs (1800² vs 330², different fields, different tilts `[ownerdata §5]`), it couples the two memory budgets (a pattern of 65 536 floats plus 4096 channels per position), and every `is4D` site would need a fifth-axis exception. HyperSpy itself returns two signals from a Velox file `[rsciio]`. **Rejected as the model**; the same-file GMS case is represented in M2 as `kind: .identity, method: .sameAcquisition`.

### M2 — two linked signals plus a registration record (recommended)
A `SpectrumDataSource` actor family beside `FourDDataSource`, a `SpectrumArray` beside `FourDArray`, a `SpectrumSession` beside `DatasetSession`, and a Codable `ScanRegistration` that maps spectrum pixels onto the 4D **source** grid. Each signal keeps its own reader, mapping, residency and liveness. The registration is recorded (ROADMAP's own requirement: "registered onto the scan grid with the transform recorded" `[repo ROADMAP.md:78-80]`), composed at use, never baked. A plain SI is the same `SpectrumSession` with no registration.

### M3 — EDX as a product of the 4D dataset
Attach → resample onto the 4D grid once → store element maps / pooled spectra in the sidecar as ordinary results; close the spectrum file. Minimal new state and v4.x readers display the maps (scalar `_f32` results read fine `[repo-report §1d]`). But: re-registering means re-importing; the frame axis and the full energy resolution are lost unless the resampled cube itself is stored (≈1 GB per sidecar, and sidecars travel); a later crop/promote of the 4D view changes nothing in the file but makes the product's grid claim implicit; a plain SI is impossible. **Kept as the derived-cache layer of M2**: "the spectrum cube resampled onto the 4D source grid" is a recomputable product, cached, never the source of truth.

### M2′ — primary-signal split (plain SI as a first-class window)
The brief puts plain `(x, y, E)` in scope. Today `AppState.hasDataset == descriptor?.is4D` (29 uses in 13 files) and the content branch is always two 4D panes `[repo-report §5]`. Opening a Velox SI with no cube needs `DatasetSession` to carry `primary: .fourD | .spectra`, which is an owner decision with frozen-shell consequences (ADR 035). M2's types are designed so that split is additive (nothing in `SpectrumSession` requires a cube); the window-level surface for it is its own slot.

## 3. Input path (i): Gatan GMS 4D-STEM + EDS

### (i-a) One `.dm4` document holding the Diffraction SI and the X-ray SI (expected, unverified)
- **What the file looks like.** `NNN_STEM SI.dm4` with ImageList objects: thumbnail, `ADF Image (SI Survey)`, `Diffraction SI` (4D float32, detector-fastest), and by analogy with the owner's EELS documents an `EDS SI` `[x, y, E]` float32 with energy slowest `[gms §2a-b]`, `[scan 134_STEM SI: two 3D objects with units µm, µm, eV]`. Dwell 10–20 ms per pixel on his cubes, so a 330² × 2048-channel SI is 0.9 GB (4096 channels: 1.8 GB) inside a 28 GB file.
- **Reader.** Factor a `DMFile` (parse, object table, mapping, `MappingLiveness`) out of `DM4Reader` and put two facades on it: `DM4Reader: FourDDataSource` (unchanged behaviour) and `DMSpectrumImageReader: SpectrumDataSource`. Selection by `Meta Data.Format`/`Signal` (`Spectrum image` + `X-ray`), never by rank `[formats §2.1]`; `Data Order Swapped` set on an SI → refuse with the reason until measured `[formats]`. A spectrum is a strided gather with stride `nx·ny·elementSize`; an energy-window map is a contiguous sum over planes — `scanFastestGather`'s blocked transpose is the exact tool `[repo DM4Reader.swift:304-398]`. Energy axis `(i − Origin)·Scale`, units eV or keV normalised to keV.
- **Reading strategy.** Memory-mapped (the file already is, on local volumes); no decode step; no residency needed for the SI itself. Full decode is never required: window maps stream over planes, per-pixel spectra gather on demand, a resident dense copy is optional and admitted under one combined budget (§6).
- **Registration.** Identity, *proven*: same `Experiment ID` on both objects, `Spatial Sampling.{Width,Height}` equal to the cube's `[ry, rx]`, pixel calibrations equal. `Last pixel < W×H` marks an aborted scan → the valid region is the first `Last pixel` positions of both signals (the cube's trailing patterns are zeros). `Scan sub-pixel = 1` and `Number of cycles > 1`: GMS sums cycles into the SI (unverified) so the DM SI has no frame axis (`frameCount = nil`). The drift log (`Artefact Correction.Spatial Drift.Drifts`) is informational: GMS corrects by moving the scan during acquisition, so the stored grid is already consistent (unverified; `[gms §2d]`).
- **How the user opens it.** The 4D opener already parses the whole tag tree; when it finds an X-ray SI sibling with the same `Experiment ID`, the Spectroscopy room offers one control: "Use the EDS recorded with this scan". No second file, no panel.
- **Sidecar/lineage.** `spectrum_attach` with `external: [the same file's name + fingerprint]`; the registration record says `sameAcquisition`. The sidecar name is unchanged (keyed to the primary source `[repo HDF5Types.swift:28]`).
- **Failure modes.** Grids differ (an EDS acquired with a different SI rect) → refuse identity, offer the metadata path; binned-average counts in some GMS versions break Poisson statistics `[formats §2.1]` → check integrality, badge; big-endian files are refused today anyway.
- **Effort / risk.** 2–4 days reader + 1–2 days multi-object API `[formats §4]`; risk medium only because no fixture exists until the owner records one.

### (i-b) Separate files: K2/K3 IS extracted cube + EDS in the STEM SI document; or a later EELS/EDS run on the same survey
- The K2 IS path extracts the 4D cube later with the Data Manager (ROI crop, real-space sampling interval, diffraction binning) `[gms §1b-6]`; the owner's GIF Continuum path does not hit this `[ownerdata §3]`. Registration kind `integerBin` with offset, seeded from the extraction parameters and verified against `Survey Image.Unique Image ID` + `Spectrum Image Rect` on both documents. Same reader, two files, the attach panel.
- A sequential EELS/EDS run on the same lamella registers through the survey image ids and rects, never by assuming identical grids `[gms §5-7]`.

### (i-c) `.dm5` (HDF5)
GMS ≥ 3.5.0 can write it `[gms §2c]`; the owner has none `[ownerdata]`. Same tag semantics as nested groups with leaf attributes; needs `H5Aiterate2` and attribute-type handling; origin convention unverified `[formats §2.3]`. Conditional on the test acquisition showing GMS writes it; 2–4 days, medium-high risk.

## 4. Input path (ii): Velox `.emd` EDS SpectrumStream (the owner's real data)

- **What the file looks like.** HDF5; `/Version` JSON `{"format":"Velox"}`; `Data/SpectrumStream/<uuid>/Data (N,1) uint16, chunks (8192,1), uncompressed in every public file`; `AcquisitionSettings` JSON (`bincount` 4096, `StreamEncoding`, `RasterScanDefinition`); `FrameLocationTable (nFrames,1) uint64` in v ≥ 6; one stream per detector segment (Super-X G2: 4) `[formats §2.2]`, `[velox §2]`. The owner's files: one stream (`SuperXG1` binary result with 4 analytical detectors G11–G14), a HAADF stack `(1800, 1800, 480)`, three 1-frame element-map images, a `Spectrum (4096,1)` sum, a proprietary `SpectrumImage` cube `[scan]`. SI shape = `ScanSize × (ScanArea right−left, bottom−top)` = 1800×1800 of a 2048 raster `[scan]`, `[formats]`. Dwell 2 µs, 480 frames, `FrameTime` 9.46 s.
- **Reader: `VeloxEMDReader: SpectrumDataSource` + `VeloxStreamDecoder`.** Detect Velox by content (the `/Version` JSON), because `.emd` is also py4DSTEM's EMD and `makeReader` keys on extension `[repo AppState+Open.swift:241-248]`. Read the stream in blocks of 64 M words (`H5Dread` hyperslab; HDF5 converts uint16 → int32 on read if no USHORT symbol is added, which doubles the transient, so add `H5T_NATIVE_USHORT_g`) under `HDF5Serial`, releasing between blocks; a state machine carries `(pixel, frame)` across blocks; accumulate in UInt32 (uint16 wraps `[formats]`); write a CSR store on the SI grid: `rowStart: [UInt64]` (pixels+1), `channel: [UInt16]`, `count: [UInt32]` (or `channel` only with duplicates merged on read, since nearly every pixel-frame event is a single count). Side outputs: per-pixel frame count (partial last frame: 1273 markers against 1280 in a public file `[formats]`), per-pixel zero-peak count (82–100 % of events sit within ±150 eV of 0 `[formats]`), per-detector totals (check per-detector `Dispersion`/`OffsetEnergy` equal before summing; rsciio does not `[rsciio _emd_velox.py:866-881]`).
- **Three reading strategies, compared.**
  - *Full dense decode* (rsciio's): `ny × nx × 4096 × 2 B` = 26.5 GB for the owner's largest; rsciio reads the whole stream into RAM even lazily and its docs admit SIs larger than RAM cannot be read `[formats]`. Out on 8–32 GB; marginal on 64 GB. No.
  - *Lazy frame/stream decode*: `FrameLocationTable[j]` is the stream index of frame j (verified by the formats agent on two files); frames i..j can be read directly. Useful for "first vs last frames" dose checks and for peel-back, but every per-pixel question still walks the whole stream once.
  - *Pre-summed SI*: Velox's own `SpectrumImage` cube is proprietary-compressed and unreadable; "Reduce File Size"/pruned files hold only that and an empty stream `[velox §2]`, `[formats]`. Not available. The `Spectrum (4096,1)` sum is a checksum for the decoder (it matched the stream on 7 of the owner's files, not on ROI-summed ones `[ownerdata §7]`).
  - **Chosen: one-pass decode into the sparse store, I/O-bound (3.2 GB read; a few seconds on the M5 Pro — estimate, unmeasured), optionally frame-ranged through the location table, with an optional on-disk cache of the CSR in the app's `Caches/` container keyed by the file fingerprint so the second open of a 7 GB file is instant** (the cache is per machine, not in the sidecar; sidecars travel and 0.25 GB is too big).
- **Memory budget.** CSR for the largest file ≈ 35 M × 6 B + 3.24 M × 8 B ≈ 0.24 GB; median file ≈ 0.9 M events → a few MB. A dense cube is admitted only on the **4D source grid after registration** (a 256² grid × 4096 × UInt32 = 1.07 GB; 330² = 1.8 GB) and only under the combined budget (§6): on an 8 GB Mac that stays off; on 64 GB it is the fast path for per-pixel fitting.
- **Intra-file frame alignment.** The stream is per frame and Velox's cube was drift-corrected per frame `[velox]`; the shifts' presence in the `.emd` is unverified. The HAADF stack is in the file, one chunk per frame `[formats]`, so the app can re-measure per-frame shifts with `MatrixDFTCorrelation.refinedPeak` and apply integer (or footprint) shifts while binning events into the store. Record them as `FrameAlignment { shifts: [[Double]], method, residual }` in the spectrum source snapshot. Parity mode (rsciio numbers) = no shifts; science mode = shifted. Both named.
- **Cross-file registration (Velox ↔ GMS).** Seed from metadata: Velox pixel size `pix` (m), `fov`, `ScanArea` fractions, `Scan.ScanTransformation.A11…A23` (an affine, semantics unverified `[scan custom_det]`), stage `(x, y, α)`; GMS `rPixelSize`/units, `Spectrum Image Rect`, stage from `Microscope Info.Stage Position`. Both agreed to ~1 µm in the 190330 session `[ownerdata §5]`. Refine by correlating the app's virtual ADF (`VirtualDetector.tiledImage`) against the Velox HAADF (summed, aligned frames); contrast differs, so a manual two-point/affine fallback and a recorded residual are mandatory `[repo-report §3]`. Kinds `similarity` (scale + rotation + shift) first; `affine` for scan-transformation skew.
- **How the user opens it.** "Attach Spectrum Image…" in the Spectroscopy inspector (`.fileImporter`, like CIF import at `[repo PhaseMappingSettings.swift:456]`), which keeps the frozen `ContentView` open panel untouched. If the file holds several signals (4 detector streams, 3 EELS SIs in a v13 file `[formats]`) a picker lists them; default sums the EDS detectors after the calibration check. The spectrum file is read-only, so it is not claimed in `OpenDatasetRegistry` (one dataset per window `[repo OpenDatasetRegistry.swift:29+]`); a Preprocess source is treated the same way today `[repo AppState+Open.swift:21-27]`.
- **Sidecar/lineage.** `/braggvectors_root/spectroscopy/` child group with the registration JSON, frame alignment, the source snapshot (`SignalReference` = name + fingerprint + object path, `EnergyAxis`, detector geometry in degrees with their declared meaning, live/real time with the per-frame-column caveat) and rank-1 spectra; v4.x writers copy unknown root children opaquely `[repo-report §1d]`. Never a rank-2 spectral stack in the result manifest (older builds would read it as a scalar map). Schema 7 → 8 additive; `minimumReaderAttribute` stays. Lineage kinds `spectrum_attach` (external), `spectrum_frames`, `spectrum_registration`, all in `lineageOnlyKinds`. Bookmark for the spectrum file stored like the sidecar's (`UserDefaults`, keyed by the primary's path `[repo SessionSidecarLocator.swift:287-288]`); a stale bookmark on reopen asks the user to locate the file by name, never silently drops the attachment.
- **Failure modes.** Pruned/Reduce-File-Size files (empty stream) → named refusal "re-export without Reduce File Size"; Velox version drift (3.20 broke rsciio `[market GH6]`) → version-gated parser with a named refusal; detector calibration mismatch → refuse to sum; partial frame → dropped by default, shown; zero peak → separate map, excluded from "counts"; numbers stored as JSON strings → POSIX-locale parse (the German-decimal trap); 8 GB Mac dense request → refused before allocation, never attempted (the kernel-panic rule); HDF5 lock held across a 3 GB decode → stalls `.h5` cube reads unless released per block; disk disconnected mid-decode → `H5Dread` fails and throws (no mmap, so no SIGBUS).
- **Effort / risk.** 4–7 days reader `[formats]` + frame alignment 1–2 days + registration lane 2–3 sessions `[repo-report §6]`; medium risk, mitigated by 104 owner streams and 7 public files as fixtures.

## 5. Input path (iii): other formats

| Format | Role | Reader | Days / risk | Source |
|---|---|---|---|---|
| EMSA/MSA (ISO 22029) | Single spectra; pooled-spectrum export; eXSpy fixtures originate as MSA | `MSAReader` (text, POSIX locale, eV→keV) | 0.5–1 / low | `[formats §2.5]` |
| HyperSpy `.hspy` | Parity pins (`EDS_SEM_TM002`, `FePt`), Zenodo joint sets (Kho 2025 simulated, Duran 2023, Mills 2024) | `HSpySpectrumReader` on `H5Reader`'s dlopen; `Experiments/<title>/data`, `axis-k` attrs, `metadata/…` | ~1 / low | `[formats §2.6]`, `[validation §3]` |
| GMS `.dm3/.dm4` EDS single spectrum | Owner's future GMS EDS; `test-EDS_spectrum.dm3` fixture with Bruker XML blob; `EDS.Detector Info.Solid angle` which rsciio misses | same `DMSpectrumImageReader` (rank 1) | in (i) | `[formats §2.1]` |
| GMS `.dm4` EELS SI | Not EDX, but the only real GMS 3D SI on the owner's disk (13 GB TiO₂ files); the layout fixture for (i-a) | same reader, `signalType: .eels` | 0 extra | `[ownerdata §4c]` |
| Oxford `.h5oina` | Owner has 8 SEM files (dense `(N, 1024/2048) int32`); users ask for it in 2026 | dense HDF5, cheap after `.hspy` | 1–2 / low-medium | `[ownerdata §4b]`, `[market §1.1]` |
| Bruker `.bcf` | Others' data; the owner has none; SFS container + packed hypermap, zlib header trap | `BCFReader` | 3–5 / medium-high | `[formats §2.4]` |
| Velox `.emd` pruned `SpectrumImage` | Unreadable (proprietary compression) | refusal only | — | `[velox §2]` |
| AZtec `.oip/.oipx`, `.dat` | Proprietary, no open reader | refusal only | — | `[market]` |

## 6. Memory, residency and the Metal question

- **Two budgets, one rule.** `ResidencyAdmission.shouldAdmit` is per-cube and 4D-only `[repo ResidentCube.swift:180-194]`; "keep the cube in memory" (ADR 050 #4) plus a dense spectrum cube need a combined byte figure. Lift the tile-budget arithmetic into a free function taking bytes per row (as the repo report suggests) and make `DatasetResidency` (Session) the single owner of both signals' resident bytes; the memory strip already shows the footprint `[status]`, so the spectrum store's bytes are visible to the owner.
- **Spectra are not Metal work in v5.0.** Window maps, pooling and Poisson intervals are vDSP over CSR; per-pixel fitting at 4 M pixels × 4096 channels is the only GPU candidate and is a method decision (the other analyst's). `measuredWorkingSetFraction` stays nil.
- **Numbers to design against** (owner's largest Velox file, `[scan]`): stream 3.2 GB on disk; CSR 0.24 GB; dense on its own grid 26.5 GB (never); dense on a 330² 4D grid 1.8 GB (64 GB Mac only); HAADF stack 1800²×480×2 B = 3.1 GB on disk, streamed one frame at a time for alignment. GMS SI (expected): 0.9–1.8 GB mapped, zero resident.

## 7. The registration record (concrete)

```swift
// Core/Data/ScanRegistration.swift — Codable JSON, deterministic keys like LoadSpecification.jsonString
package nonisolated struct SignalReference: Codable, Equatable, Sendable {
    var fileName: String; var fingerprint: String; var objectPath: String   // never a path
}
package nonisolated struct FrameAlignment: Codable, Equatable, Sendable {    // intra-file (Velox frames)
    var shifts: [[Double]]      // per frame (dy, dx) in spectrum px; empty = none applied
    var method: String          // "none" | "haadfCorrelation" | "fileMetadata"
    var residual: Double?
}
package nonisolated struct ScanRegistration: Codable, Equatable, Sendable {
    var schema = 1
    var spectrumSource: SignalReference
    var scanSource: SignalReference
    var sourceGrid: [Int]; var targetGrid: [Int]        // full-extent grids, never views
    var transform: [Double]                             // 2×3 affine, spectrum px -> 4D SOURCE px
    var kind: Kind        // identity | integerBin | similarity | affine
    var method: Method    // sameAcquisition | metadata | imageCorrelation | manual
    var resampling: Resampling   // countConservingFootprint (default) | nearest
    var validRegion: AxisCrop?   // GMS `Last pixel` aborts; Velox partial frame
    var evidence: [String: String]   // companion image, residual px, stage deltas
    var recorded: Date
}
```

Composition at use: spectrum px → 4D source px (this record) → 4D view px (`LoadView.sourceScanY/X` inverse) → preprocessed-file px (`DataCubeDerivation.scanOffset/scanStride`, which is written but has no reader yet `[repo-report §1a]`). Counts are summed over the footprint of each 4D pixel, never interpolated (Poisson). A rehearsal crop promoted to full extent, or a `_bin_4` export, needs no re-registration.

## 8. Comparison

### 8a. Data models

| Criterion | M1 combined 5-axis | **M2 two signals + record** | M3 EDX as a 4D product | M2′ primary split (add-on) |
|---|---|---|---|---|
| Owner's actual pairs (different grids/sessions) | cannot represent | yes | yes, baked at import | yes |
| GMS same-file identity | natural | `identity/sameAcquisition` | yes | yes |
| Plain SI without a cube | no | types allow it | no | yes (frozen-shell work) |
| Re-registration later | n/a | change the record, products go stale | re-import | same as M2 |
| Memory | coupled, worst | per signal, bounded | small after import, loses resolution | per signal |
| Sidecar | new schema for the source | child group + lineage-only kinds | existing manifest only | + spectrum-keyed sidecar |
| Touches `is4D` sites | all 29+ | none | none | 29 uses / 13 files + content branch |
| Effort (sessions) | high, and wrong | 2–3 types + readers | 1–2 | +3–4 incl. mock/ADR |
| Verdict | reject | **adopt** | cache layer of M2 | second slot, owner's call |

### 8b. Input paths

| Path | Reading | Registration | Open as | Risk | Days |
|---|---|---|---|---|---|
| (i-a) GMS same `.dm4` | mmap, plane sums + gather; no decode | identity proven by tags | one file, one click | medium (no fixture) | 3–6 |
| (i-b) GMS two documents / K2 extract | same | `integerBin` + survey ids | pair | medium | +1–2 |
| (i-c) `.dm5` | HDF5 attrs via `H5Aiterate2` | as (i-a) | one file | medium-high | 2–4 (conditional) |
| (ii) Velox `.emd` stream | one-pass → CSR, frame-ranged, cached | frame alignment + metadata-seeded correlation + manual | pair (attach) | medium | 6–10 incl. alignment |
| (iii) MSA / hspy | trivial / `H5Reader` | n/a / per file | single file | low | 1.5–2 |
| (iii) h5oina / bcf | dense / packed | per file | pair | low-med / med-high | 1–2 / 3–5 |

## 9. Recommendation

**Adopt M2 with M3 as its derived cache; decode Velox streams once into a sparse store with a per-machine cache; register against the 4D source grid with a composable record that separates intra-file frame alignment from the cross-file transform; land the GMS same-file facade on the shared `DMFile` so identity is a tag check, not an assumption.** Reasons: it is the only model that matches the owner's data today (two instruments, two sessions `[ownerdata §5]`) and tomorrow (one GMS document), it keeps every memory figure inside the repo's existing tile budget on 8 GB and lets a 64 GB Mac go dense on the 4D grid, it changes no frozen file at the data layer, it records the transform as ROADMAP already requires, and it leaves the analysis-method choice (another analyst's) entirely open: pooling (E), arbitration (B), joint clustering (D) all consume "spectra on the 4D view grid" through one composition point.

**Order of work.** (0) Owner reopens the freeze; the "Unverified on screen" row empties `[repo-report §0]`. (1) Discovery refusals for Velox/`.hspy`/DM SI in the shipped openers (v4.x polish, Gate B) and `DataCubeDerivation` read-back. (2) `EnergyAxis`, `SpectrumDescriptor`, `SpectrumDataSource`, `SparseSpectrumStore`, `SpectrumArray`, combined residency. (3) MSA + hspy readers (parity fixtures). (4) Velox reader + frame alignment. (5) `ScanRegistration` + composition + metadata/correlation/manual + refusals, pre-registered with a synthetic truth (planted offset, bin, drift `[validation §4]`). (6) Sidecar group, schema 8, lineage kinds, fingerprint decision. (7) `DMFile` split + DM SI facade, tested on the EELS SI documents until the owner records one 4D+EDS scan. (8) The Spectroscopy room (mock + ADR first).

**What evidence would change it.**
- The owner's one test acquisition (same scan saved as `.dm4` and `.dm5`): if GMS writes both signals in one `.dm4` with equal grids and the lab makes simultaneous acquisition routine, the same-file facade becomes the main path and the cross-file registration UI shrinks to a check; if it writes `.dm5`, the DM split becomes an HDF5 facade; if the EDS SI carries a frame/cycle axis or per-pixel live time, `SpectrumDescriptor` gains them.
- The per-frame drift shifts found in the Velox per-frame metadata columns → the HAADF re-correlation step is dropped.
- A Velox stream that is compressed, or a `FrameLocationTable` whose meaning changes across versions → the frame-ranged path becomes a full decode with progress.
- A re-acquired EDX at mapping dwell on the 4D field with ≥ 100 counts/px (the 190330 session is one tilt away `[ownerdata §9]`) → dense binned cubes become the default on the owner's 64 GB Mac, sparse stays the 8 GB path.
- The owner wanting to open his 104 Velox SIs without a cube → M2′ moves to the first slot and the room mock must show a spectrum-only window.
- A measured decode slower than ~10 s for the 7 GB file → the CSR cache moves from optional to required in the first increment.

## 10. Concrete Swift types and files

**Core/Data (DSTEMCore; each new file joins the pbxproj exception list and a new `spectra` group in `tools/lib/sources.manifest` beside `readers` `[repo tools/lib/sources.manifest:127-137]`):** `EnergyAxis.swift`; `SpectrumDescriptor.swift` (file, object path, `[ry, rx]`, channels, dtype, storage `.denseEnergySlowest | .denseEnergyFastest | .eventStream(frames:)`, signal type, detectors, scan pixel calibration, companion images); `SpectrumDataSource.swift` (`protocol SpectrumDataSource: Actor` with `discoverSpectrumImages()`, `loadPushdown(for:)`, `readSpectrum(view, ry, rx)`, `readEnergyWindowMap(view, channels:)`, `readSpectrumTile(view, yRange:)`, `frameCountMap()`, `zeroPeakMap()`, `acquisitionMetadata()`, `companionImages()`); `SpectrumLoadSpecification.swift` (reuses `AxisCrop`; spatial bin, energy range/bin, frame range, detector mask; `SpectrumView`); `SparseSpectrumStore.swift` (CSR); `SpectrumArray.swift` (actor: LRU of spectra, tile reads, cached sum, optional resident dense buffer); `ScanRegistration.swift` (above); readers `DMFile.swift` (factored from `DM4Reader.swift`), `DMSpectrumImageReader.swift`, `VeloxEMDReader.swift`, `VeloxStreamDecoder.swift`, `HSpySpectrumReader.swift`, `MSAReader.swift`; `H5Reader.swift`: `HDF5Library` → `package`, add `H5T_NATIVE_USHORT_g/_UCHAR_g/_ULLONG_g`, raw-byte column reads, `H5Aiterate2` (for `.dm5`); `datacubeRejection` gains energy-unit, `signal_type` EDS/EELS and Velox-tree refusals; `DM4Reader.locateDatacube` prefers `Meta Data.Format = Diffraction image` and skips `Spectrum image` by name.

**Session (DSTEMSession):** `SpectrumSession.swift` (reader, array, descriptors, loading/cancel state, energy-calibration override, active `ScanRegistration` + `FrameAlignment`, tied to `DatasetSession.epoch` only through the registration); `DatasetResidency` extended to a combined budget; `SessionLineage` tables: `lineageOnlyKinds` + `inputPolicy` rows for `spectrum_attach`, `spectrum_frames`, `spectrum_registration`; `SessionSidecarLocator`-style bookmark for the spectrum file.

**App:** `AppState+Spectroscopy.swift` (attach flow, same-file offer, registration confirm); `makeReader` unchanged for 4D but a content probe refuses Velox files with a message naming the Spectroscopy room; `Core/Data/SpectroscopySidecar.swift` writer using the package-visible `HDF5WriteLibrary`.

**Harnesses:** `tools/spectrum-reader-test` (Velox public files: shapes 16×16, 16×20, 50×10; the 4-detector sums 865236/913682/867647/916174 `[validation §1g]`; GMS EELS SI layout pin; MSA/hspy pins) and a registration synthetic-truth harness.

## 11. Unverified items to settle first

1. Whether a GMS 4D+EDS scan lands in one `.dm4`, the EDS object's name, dtype, channel/dispersion tags, cycle summation and per-pixel live time — one small test acquisition, saved as `.dm4` and `.dm5` `[gms §6]`, `[formats §5]`.
2. Whether the Velox per-frame drift shifts are stored anywhere in the `.emd` (per-frame metadata columns are the candidate).
3. Velox stream compression and `FrameLocationTable` stability across versions 4–13; the owner's files' Velox version string is unparsed `[ownerdata §10]`.
4. Swift decode throughput for the 3.2 GB stream, and the CSR cache size on disk.
5. The semantics of `Scan.ScanTransformation.A11…A23` and the exact Velox stage units (metres) against GMS (µm) — they agreed to ~1 µm once `[ownerdata §5]`.
6. The fingerprint policy for 7–29 GB inputs (full streamed hash versus size + header + sampled blocks) — owner decision.
7. Whether the owner wants plain-SI windows in v5.0 (M2′) or only attached spectra.