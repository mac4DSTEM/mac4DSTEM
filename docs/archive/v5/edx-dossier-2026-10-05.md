# v5.0 EDX suite — the full picture before one implementation is chosen (dossier, 2026-10-05)

**Date** 2026-10-05. **Synthesiser** Fable 5.1. **Scope** v5.0 = "4D-STEM + EDX" (one scan, a diffraction pattern and an EDX spectrum at every probe position; never "5D") plus plain EDX spectrum images, in a seventh room "Spectroscopy", ported from HyperSpy / eXSpy / RosettaSciIO the way py4DSTEM was ported. v4.5 ships first.

**How claims are marked.** `[inputs §n]` = `reports/fable-input-paths.md`, `[methods §n]` = `reports/fable-methods.md`, `[second Cn/§n]` = `reports/second-opinion.md`, `[critic Cn/Pn]` = `reports/completeness-critic.md`; `[velox]`, `[gms]`, `[formats]`, `[market]`, `[ownerdata]`, `[repo]`, `[validation]`, `[v45]` = the same-named file in `reports/` — all under [`edx-research-2026-10-05/`](edx-research-2026-10-05/README.md). `[repo file:line]` = the repo at `85920f91`. `$S` = that folder: the analysis scripts and dated logs are committed there; the vendor manuals carved from the owner's installers, the cloned upstream repos, the Python venv and the owner's full file listings are not (copyright, size, privacy) and live only in the session scratchpad. `(synthesis)` = the synthesiser's own reasoning. `(unverified)` = not confirmed by anyone.

> **The owner's answers since this was written (2026-10-05, ADR 052).** v4.5 ships **as it stands, no drive first**: card V5-9 is answered — the Velox `.emd` behaviour is a v4.5 *release note*, not a refusal (reproduced at the reader on 9 of 10 public Velox files: they open as a one-row cube built from the HAADF image stack, the single-spectrum file is refused — `edx-research-2026-10-05/velox-emd-repro/`); ADR 052 lifts ADR 049's freeze for EDX after v4.5 and makes the suite v5.0; the CI type-check timeout (`DiskCentreLabels.swift:330`) is split in the v4.5 cut (green on CI unproven until pushed). §1 step 0 and §9.1 below read with those answers. Still a v5 blocker: the "Unverified on screen" row (Train Model…, the dataset-as-destination refusal) must be empty before new on-screen surface lands (CLAUDE.md).

---

## 1. Summary

### What v5.0 is
A Spectroscopy room that (a) opens the owner's existing EDX data — 104 Velox `.emd` spectrum images — as plain spectrum images with a count-honest eXSpy-parity baseline, (b) attaches an EDX spectrum image to a 4D cube through a recorded registration, and (c) pools spectra over diffraction-defined objects, phases, groups and regions (approach E) with Poisson intervals and detection limits. Everything else — EDX-arbitrated phase tables (B*), joint clustering (D), diffraction-regularised maps (G), joint factorisation (F) — is staged behind truth datasets and badges. `[inputs §9]`, `[methods §3]`, `[second §6]`

### Fixed by the owner (not re-opened here)
Term, room name and location, GPL basis (HyperSpy/eXSpy/RosettaSciIO; espm MIT, PyMca, DTSA-II may inform), the two file families (`.dm4` from GMS STEMx, `.emd` from Velox), "methods not decided".

### Eight findings that change the picture (all from this pass, none from the original survey)
| # | Finding | Consequence | Source |
|---|---|---|---|
| 1 | **No usable joint pair exists.** The 104 owner EDX files are all plain spectrum images; the closest 4D/EDX pair (190330, 2026-06-03) is ~18 µm and 24° of tilt apart. | A spectrum-only window is the only path to day-one value; E cannot run on existing data; the owner must acquire. | `[ownerdata §1, §5]`, `[second C7]`, `[critic P0-3]` |
| 2 | **Velox already corrects drift during acquisition**: per-frame `ScanTransformation.A13/A23` drift smoothly while HAADF frames register to ≤1 px; a planted (+7, −5) shift was recovered exactly. | Drop the HAADF re-alignment step the inputs design carried; record A13/A23 as provenance; the one remaining intra-file risk is the Super-X G1 "SI can shift relative to the reference image" (Velox UM p.259). | `[second C1]`, `[critic C2]` |
| 3 | **Counts at 4D conditions are ~25–85 per pixel, not 0–10 and not 10²+.** The 4D cube 051 ran at 0.26 nA (spot 7, C2 70 µm, 2.1 mrad); the EDX SIs at 1.78 nA at 48–60 % dead time. Per object area a simultaneous scan at the owner's 4D settings yields **2–180× fewer X-rays** than his existing SIs. | Simultaneous acquisition is not automatically the better route; sequential EDX at the 4D field and tilt may give more signal per object. Per-pixel joint methods become possible only at the top of that range, binned. | `[second C3]`, `[critic C4]` |
| 4 | **Refusing absorption correction on summed Super-X G1 data biases Mg/Si by +3 % (30 nm) to +15–19 % (150 nm)** — the same order as the gap between β″ composition models. Geometry (4 detectors, azimuth 45/135/225/315°, elevation 22°, stage α/β) is in the Velox metadata. | Ship a four-detector geometric correction, badged, with per-quadrant TOA spread and thickness σ propagated; refuse only when geometry is unknown. | `[second C9]`, `[critic C7, C8]` |
| 5 | **No k-factor source exists on day one**: Velox exports none, the owner's notebooks use placeholders. | Primary v5.0 outputs must be k-free (net counts, Mg/Si count ratios, enrichment over the matrix blank, all with intervals); typed k with source optional; theoretical k a later sheet. | `[critic C18, P0-4]`, `[ownerdata §4d]`, `[second §3.4]` |
| 6 | **The shipped v4.x app probably opens any Velox `.emd` as a one-row "datacube"** `[1, 2048, 682, 120]`; `.emd` is a registered Finder type and the owner has 2149 such files. Emulated from `H5Reader.discoverPrimaryDataset`'s ordering, not driven. | A v4.5 decision: named refusal (Gate B) or release note. | `[critic C20]`, `[second C11]`, `[repo §1e]` |
| 7 | **The GMS same-file 4D+EDS path is speculative for this lab**: Super-X under GMS needs a second Esprit install, an `ExternControl` licence, IO-card firmware and a DigiScan DDC swap; public "simultaneous" datasets ship as separate per-signal files. | Treat path (i-a) as conditional on a service answer; the realistic routes are sequential (R4) or a Velox-scan-plus-external-camera route (R3, as Duran 2023 did on a Talos F200X). | `[gms §1a]`, `[critic C11, C13, P0-2]`, `[second §2.7]` |
| 8 | **Metadata-seeded cross-instrument registration works but needs a reflection**: the 190330 Velox HAADF ↔ GMS ADF survey correlates uniquely (peak/std 41.4 vs next 10.4) at mirror + 90°, scale 1.00 from metadata. | The registration record must allow det < 0 or pin per-vendor axis conventions; refine Velox HAADF against the GMS survey ADF and chain through `Spectrum Image Rect`, not against a virtual ADF from the cube. | `[critic C14]`, `[second §2.3–2.4]` |

### Corrections to earlier analyses, stated plainly
"Re-align Velox frames" (inputs) — wrong, see 2. "~10² counts/px at 4D dwell" (methods/ownerdata) — current-corrected to 25–85. "Refuse absorption on summed data" (methods) — costs 3–19 % on the decisive ratio. "LS vs Poisson-ML differ 4 %" (methods, tagged verified) — the ML value was unconverged; converged IRLS gives 2.9 %, and HyperSpy's ML output depends on optimiser and start, so it cannot be a parity pin `[second C4]`. "A second, corrected line table is needed" (methods M1) — for Mg/Al/Si/Cu/O/Zr exspy agrees with Bearden to ≤0.022 % `[second C5]`. "Three repo defects" (inputs) — one plausible and unreproduced, two are hardening `[second C11]`. "82–100 % zero-peak events" (formats) — public test files only; owner files 1–6 % `[second C2]`, `[critic C5]`. "Velox 3.20 broke HyperSpy" (market) — a user environment error `[critic C10]`. "No public GMS EDS SI" (formats) — two exist `[critic C11]`.

### The recommendation path (synthesis)
0. **v4.5 ships**, with the Velox `.emd` refusal landed under Gate B or named as a limit; ADR 049 reopened for v5 by the owner; ADR 007 amended so EDX = 5.0.0.
1. **Owner states the science question** (which Mg-Si-(Cu) phase a needle is? Mg/Si per class? Si segregation at LPBF cell boundaries? solute depletion?) and **asks service** about R1/R2 and their cost. This picks S1 vs S2 and the acquisition route.
2. **Owner acquires** one EDX SI at the 051 field and tilt (α −16.87°, stage already matches), full stream, both currents noted; an EELS low-loss t/λ map at the same field; a STEMx test if service confirms it.
3. **Room mock, including a spectrum-only window**, before any type is written (frozen shell, ADR 035); then the data-model, pin and room ADRs as one sheet.
4. **Plain-EDX baseline** (readers for Velox stream, MSA, `.hspy`; exspy parity P0–P3; statistics layer; k-free outputs; four-detector absorption badged) — usable on the 104 existing files.
5. **Registration record** (with reflections) + mask transport onto the native spectrum grid; **E per phase or region** on the re-acquired pair; per-object E only where the measured residual is below the object half-width or the data are simultaneous.
6. **B\* table** only after per-phase score retention (additive, Gate B) and a separability matrix from the CIFs shows a separable pair; **D** behind an exploratory badge.
7. **G, then F** in v6, synthetic truth first.

---

## 2. What the market does

### 2.1 Per product (how, not just what)
| Product | Co-acquires 4D+EDX | Joint analysis | Quantification | Low counts | Uncertainty | Lock-in / platform | Source |
|---|---|---|---|---|---|---|---|
| **TESCAN TENSOR / Explore** | Yes: precession 4D-STEM + 2 SDDs, Dectris Quadro | **The only joint product**: EDX weights candidate phases inside template matching; rule not public; demo at 1 nA, 10 ms, warns misidentification at low counts | ? | "needs counts" | ? | HDF5 export; ExpertPI proprietary API; price not public | `[market X1–X8]` |
| **Oxford AZtecTEM** | No (ePSIC home-built via REST API) | None | Modified Cliff-Lorimer, theoretical/user k, PPC, FLS; M2T thickness from a Si₃N₄ standard; Li "by difference" | bin, smooth, σ-threshold; AutoPhaseMap on element maps (blind to unselected elements) | σ column per wt% | `.oip` closed, H5OINA export-only; AZtecFlex $699–1,399/yr, Windows only | `[market O1–O7, GH1]` |
| **Bruker ESPRIT (QUANTAX TEM)** | No | None | theoretical/experimental CL, ζ with polynomial interpolation, absorption built in, three background models | MaximumPixelSpectrum, filters; AutoPhase = PCA | σ level selectable | `.bcf` closed (reverse-engineered reader, open gaps); dongle; Windows | `[market B1–B5, GH2–5]` |
| **Thermo Velox** | Yes (Ceta-2, EMPAD G2) | None; correlation "left to the user" | CL with Brown-Powell / Bote-Salvat / Schreiber-Wims k; 20 % k rule; absorption with Super-X geometry + holder shadowing; no fluorescence; ML fit with non-negativity | pre-filter (count-conserving), post-filter; frame peel-back | fit errors in Experiment Log | `.emd` HDF5 readable; pruned `SpectrumImage` unreadable; Windows | `[velox §1–3]`, `[market T1–T3]` |
| **Gatan GMS / eaSI (owner's platform)** | Yes: simultaneous 4D+EDS, sequential 4D+EELS | **Masking only**: orientation map masked by an element map | MLLS peak-family fit, "full background modelling"; CL/ζ/absorption unverified (help not public) | ? | ? | `.dm4` readable; `.dm5` (≥3.5.0) unreadable by rsciio; free offline licence; Windows | `[gms §1–3]`, `[market G1–G5]` |
| **JEOL (JED-2300T, Phase Analysis 2, FEMTUS)** | claimed (FEMTUS) | None | k or ζ; frame playback | cluster/VCA maps (SEM product) | ? | `.pts` readable | `[market J1–J3]` |
| **NanoMegas ASTAR/TopSpin** | multi-signal | None in indexing | — | — | — | `.blo/.app5` readable | `[market N1]` |
| **Thermo ChemiPhase (SEM)** | — | — | probabilistic phase per pixel from ~10 counts/px | the clearest low-count UX, SEM only | — | — | `[market T5]` |
| **eXSpy / HyperSpy** | — | None | CL, ζ, cross-section; iterative absorption; Poisson-scaled PCA | binning | **none** from `quantification` | GPL; line-table errors up to 9.6 % (Ce Mβ; not the owner's lines) | `[market L1, GH9]`, `[validation §1]`, `[second C5]` |
| **NIST DTSA-II / NeXL** | — | — | SEM bulk; uncertainty budgets | — | **yes** | public domain / Unlicense | `[market P6, P7]` |

Literature: Duran 2023 (CBED + EDS on a **Talos F200X + Super-X + Merlin Quad**, triggered from the STEM scan, 2–25 ms dwell; concat + PCA + fuzzy c-means; no truth) `[critic C13]`, `[validation §3]`; Parish 2022 (SEM EBSD+EDS SVD clustering); Schwartz/Hovden fused tomography (HAADF ∝ ΣZ^γx coupling — no analogue for diffraction); Teurtrie espm physics-guided Poisson NMF (MIT); PSNMF, Potapov-Lubk (details unread); Kumar & Rakita CNN (needs training truth that does not exist) `[methods §2.1]`.

### 2.2 Baseline matrix (condensed from `[market §3]`)
Everyone: CL with some k source; window and fitted maps; per-pixel quant maps; Windows only; algorithm not inspectable. Some: ζ (Bruker, JEOL, Oxford via M2T), thin-film absorption (Oxford, Bruker, Velox), time-resolved frames (Velox, JEOL), per-detector channels (Velox). Nobody: a joint algorithm on the owner's platform, Poisson modelling of the 4D-STEM count regime, per-pixel or per-object uncertainty, flagging what EDX cannot see, macOS.

### 2.3 Gaps the app can own (synthesis from `[market §4–5]`, `[methods §2]`)
1. An **open, inspectable joint layer** on GMS and Velox data (TESCAN's is closed and TENSOR-only; Gatan's is a mask).
2. **Count-honest chemistry per diffraction-defined object**: pooled spectra with exact Poisson intervals and Currie detection limits — no vendor does this.
3. **The diffraction-defined matrix pool as an empirical blank** — absorbs the Al Kα tail under Mg Kα and the Si-detector internal-fluorescence peak that sits on Si Kα; the strongest idea in either analysis `[second §3]`, `[critic C9]`.
4. **Explicit limits**: Li not measurable; T1/θ′ indistinguishable by construction; apparent-vs-projected composition; channelling angle from the app's own orientation map (I).
5. **Validated port with named deviations**, free, no dongle, Apple Silicon offline reanalysis with the replay record as provenance.
Do not compete on acquisition, SEM bulk ZAF, mineral databases.

---

## 3. What Velox and GMS do (from the owner's installers)

### 3.1 Velox 3.15 (owner's acquisition PC runs **2.15.0.45**, writing EMD v9 and v11) `[critic C1]`, `[velox §0–3]`
- **Acquisition**: View/Acquire presets; spectra always 4096 channels; Super-X G1 segments toggled in the Detector Layout (G2 writes one stream per segment, G1 one summed stream — the owner's files are G1, one stream) `[velox §1]`, `[ownerdata §4]`. SI: STEM + EDS per pixel, multi-frame, **drift compensation per frame by cross-correlation** of the reference frames or a separate drift area; "Optimize for periodic images"; dwell ≥20 µs recommended (the owner uses 2–8 µs).
- **Analysis**: Auto-ID; four-state periodic table incl. "deconvolution only"; backgrounds "Empirical" (3-parameter Bethe-Heitler) or multi-polynomial in windows; ML fit with non-negativity, family-as-whole (the manual also says "least square" for the default SI fit — contradictory); k from Brown-Powell (default) / Bote-Salvat / Schreiber-Wims, 20 % k rule; absorption with Super-X geometry, segment selection and Double-Tilt holder shadowing, no fluorescence; maps int/net/wt%/at%; count-conserving pre-filter with a recommended kernel; frame trimming; "Reduce File Size" flattens and drops the stream `[velox §1]`.
- **Files**: `.emd` HDF5, undocumented by Thermo; the stream is uint16 events with 65535 = next pixel; `FrameLocationTable` gives frame starts; metadata JSON per frame carries `Optics.ScreenCurrent`, `Scan.ScanTransformation.A11…A23`, detector geometry, stage in metres, `ScanRotation` `[formats §2.2]`, `[second C1, C8]`, `[critic C3, C7]`. Pruned files hold only the proprietary `SpectrumImage` `[velox §2]`.
- **4D-STEM in Velox**: licensed; needs Ceta-2 + sync; patterns go to an **MRC2014 stack** (FEI1/FEI2 headers, raster/serpentine flag), EDS to a single-frame SI in the `.emd`; "correlation is left to the user" `[velox §3]`. The owner has never recorded one; no `.mrc` on his disks `[critic C15]`.

### 3.2 GMS 3.6.1 (DM help not obtained — it sits inside the InstallShield `GMS.msi`; two ways to get it are the owner's call) `[gms §0]`
- **STEMx**: DigiScan and camera synced in hardware; CBED is one STEM-SI signal; EDS can ride along, EELS cannot ("only one signal that intercepts the beam"); OneView IS/GIF cubes land directly as DM 4D, K2/K3 IS as raw on capture PCs extracted later `[gms §1b–c]`. The owner's cubes: GIF Continuum as camera, `DigiScan (hardware-sync)`, 10–20 ms, float32 detector-fastest, 17–29 GB `[ownerdata §3]`.
- **EDS under GMS**: needs licence 700.LS.707 and the EDS Remote Server; **Super-X needs a second Esprit 1.9.4 on the FEI PC, `ExternControl`, Bruker IO firmware 6.0.1 and a replacement DigiScan DDC**; hardware-synced SI needs licence 700.LS.777 + a clock cable `[gms §1a]`. Whether this works on a Velox-2.15 Talos G1 is unverified.
- **Files**: one `NNN_STEM SI.dm4` per SI holding survey, ADF, "Diffraction SI" and (for EELS) the 3D SIs with energy slowest; linkage tags `Experiment ID`, `Spatial Sampling`, `Last pixel`, `Survey Image.Unique Image ID` + `Spectrum Image Rect`, drift log, `Pixel iterator`; energy axis `(i − Origin)·Scale`; EDS `Meta Data.Signal = X-ray` (rsciio-mapped, not seen in owner data); `Probe Current = "0.0"` in every owner object `[gms §2d]`, `[critic C3]`. `.dm5` since 3.5.0. **Public "simultaneous" sets ship per-signal files** (YAlO₃: `EDS Spectrum Image.dm4` separate; Mills 2024: diffraction `.dm4` + EDX `.hspy`) `[critic C11]`.
- **Joint step**: masking an orientation map by an element map; "linked" EELS extraction from 4D-found crystallites; nothing in indexing `[gms §3]`.

---

## 4. Input paths and data model

### 4.1 Options
| Model | What it is | Fits owner's data | Plain SI | Memory | Touches `is4D` sites | Verdict |
|---|---|---|---|---|---|---|
| **M1** one 5-axis object | `[ry, rx, qy, qx, E]` | No — different grids/sessions | No | coupled, worst | all 29+ | reject |
| **M2** two signals + registration record | `SpectrumDataSource`/`SpectrumArray`/`SpectrumSession` beside the 4D family; Codable `ScanRegistration` against the 4D **source** grid, composed at use with `LoadView` and `DataCubeDerivation` | Yes | types allow it | per signal, bounded | none | **adopt** |
| **M3** EDX as a 4D product | resample at import, store maps in the sidecar | baked, loses resolution | No | small | none | derived cache of M2 at most |
| **M2′** primary-signal split | a window whose primary is a spectrum image | Yes | **Yes** | per signal | 29 uses / 13 files + the content branch | **decide at the room mock, now** |
`[inputs §2, §8a]`, `[second §2, §6]`, `[critic P0-3]`

**Where the analyses disagree.** Inputs: M2′ "owner's call, later slot". Second opinion and critic: M2′ is required for day-one value because every owner file is a plain SI and "attach" would mean opening a 1–29 GB cube to look at a spectrum; and the window structure belongs in the mock because ADR 035 makes frozen-shell decisions expensive to revisit. Inputs: M3 as a dense cache on the 4D grid (1.07–1.8 GB on 64 GB). Second opinion: **transport the pool masks to the spectrum's native grid instead** (inverse transform, area-majority) and sum integer events there — exact Poisson, no 1.8 GB cube; resample counts toward the coarser grid only for per-pixel joint methods. I side with the second opinion on both (synthesis): the mask-transport path is simpler and count-exact, and the dense cube is deferred until a per-pixel joint method ships.

### 4.2 Input paths
| Path | File | Reading | Registration | Fixture | Days / risk | Status |
|---|---|---|---|---|---|---|
| (i-a) GMS same `.dm4`, 4D + EDS SI | one `STEM SI.dm4` | shared mmap via a factored `DMFile`; energy-slowest planes → window maps are plane sums, spectra a strided gather (`scanFastestGather` pattern) | identity by `Experiment ID` + `Spatial Sampling` + `Last pixel`; **also** correlate the X-ray total map with a virtual image at sub-pixel precision (EDS/camera pixel lag possible; ePSIC shows flyback columns) | none until a test acquisition; YAlO₃ `.dm4` (39.5 MB, CC BY) settles tags/dtype/units | 3–6 / medium | **conditional on a licence and service answer** |
| (i-b) GMS separate documents (public sets; K2 extract; later EELS run) | two `.dm4` | same | `integerBin` + survey `Unique Image ID` + `Spectrum Image Rect` | YAlO₃, Mills 2024 | +1–2 / medium | more likely than (i-a) |
| (i-c) `.dm5` | HDF5 | `H5Aiterate2`, attribute types; origin convention unverified | as (i-a) | none public | 2–4 / med-high | only if the test shows GMS writes it |
| **(ii) Velox `.emd` stream** | the owner's 104 files (EMD v9/v11, uncompressed, chunks (8192,1), `FrameLocationTable` present except 3 single-spectrum files) | one-pass block decode under `HDF5Serial` released per block → **CSR store** (≤35 M events, ~0.24 GB for the 3.2 GB stream vs 26.5 GB dense); shape from `ScanSize × ScanArea`, never from an image; UInt32 accumulation; per-pixel frame count; zero-peak side output; per-detector calibration check before summing; `H5T_NATIVE_USHORT` added; fingerprint hashed during the same pass | drift provenance from A13/A23 + residual check (no re-alignment); cross-file: metadata seed (pixel size, `ScanArea`, stage, `ScanRotation`) → correlate Velox HAADF ↔ **GMS survey ADF** → chain via `Spectrum Image Rect`; reflection allowed; manual two-point fallback with residual | 7 public rsciio files (4-detector sums 865236/913682/867647/916174) + owner's 107 streams | 4–7 reader + 2–3 sessions registration / medium | **first** |
| (iii) MSA, `.hspy` | parity fixtures (TM002, FePt), Zenodo joint sets | trivial / `H5Reader` | n/a | exspy data files < 1 MiB | 1.5–2 / low | with (ii) |
| (iii) `.h5oina` | owner's 8 SEM files, 2026 user demand | dense `(N, 1024/2048) int32` | n/a | owner files | 1–2 / low-med | later |
| (iii) `.bcf` | others' data | SFS + packed hypermap, zlib-header trap | n/a | rsciio files | 3–5 / med-high | deferred |
| Velox-native 4D (MRC stack + SI) | not on the owner's disks | no MRC reader in the repo | — | — | — | noted gap |
`[inputs §3–5, §8b]`, `[formats §2]`, `[second §2]`, `[critic C1, C6, C14, C15]`

**Decode cost measured**: h5py read 469 MB/s from the external SSD, numpy decode 0.22 s per 134 MB block → ~10 s for the 3.2 GB stream, exactly on the inputs analysis' "cache becomes required" threshold `[critic C6]`. The CSR cache decision (per-machine `Caches/`, ~0.25 GB, purge policy, lean-app directive) is therefore live.

### 4.3 The registration record (amended)
```
ScanRegistration { schema; spectrumSource, scanSource: SignalReference (name + fingerprint + object path);
  sourceGrid, targetGrid: full-extent grids; transform: 2×3 affine, spectrum px → 4D SOURCE px, det < 0 allowed;
  kind: identity | integerBin | similarity | affine (reflection permitted in each);
  method: sameAcquisition | metadata | imageCorrelation | manual;
  resampling: countConservingFootprint | nearest;  validRegion: AxisCrop? (GMS Last pixel; partial frame);
  evidence: companion image, residual px, stage deltas, handedness tested; recorded: Date }
DriftProvenance { a13a23PerFrame: [[Double]], units: unverified, residualCheckPx: Double?, compensationFlag: unknown }
```
Composition at use: spectrum px → 4D source px → 4D view px (`LoadView.sourceScanY/X` inverse) → preprocessed px (`DataCubeDerivation`, which is written but has no reader yet `[repo §1a]`). Counts are summed over footprints, never interpolated. Replaces inputs' `FrameAlignment` per `[second C1]`, `[critic C2]`.

### 4.4 Memory, residency, lock
Combined budget for both signals under one owner (`DatasetResidency`); `shouldAdmit` today checks only `maximumBufferLength`, not RAM `[second §2]`; tile budget formula lifted to a free function; the 8 GB Mac never attempts a dense request; `measuredWorkingSetFraction` stays nil; HDF5 lock released between blocks or `.h5` cube reads stall `[inputs §6]`, `[repo §1c]`.

### 4.5 Sidecar and lineage
`/braggvectors_root/spectroscopy/` child group (v4.x writers copy unknown root children opaquely; unknown root attributes are dropped); rank-1 spectra only (a rank-2 stack would be misread as a scalar map by older builds); schema 7→8 additive; lineage kinds `spectrum_attach` (external: name + fingerprint), `spectrum_registration`, `spectral_*` in `lineageOnlyKinds` or `ReplayPlanner` refuses; element maps as ordinary `scalar_f32` results with `validation: none`; the spectrum file's bookmark stored like the sidecar's; a stale bookmark asks, never drops `[repo §1d]`, `[inputs §4]`.

---

## 5. Analysis methods

### 5.1 Plain-EDX baseline: layer by layer
| Layer | eXSpy (parity target) | Science default (badged, inline `DEVIATION` naming the exspy line) | Where the analyses disagree |
|---|---|---|---|
| Energy calibration | file offset/scale; `calibrate_energy_axis` refits on chosen lines | run only on the pooled spectrum; show file vs fitted | — |
| Line table + FWHM | `xray_lines.json` (Chantler 2005 energies, EPQ weights); FWHM(E)=√(2.5·(E−E_MnKα)·1000+FWHM²)/1000 keV | **exspy verbatim**; exclude H/He rows; refuse Li/Be with the reason; per-line DEVIATION only for a used line shown wrong | methods M1 wanted a second corrected table; second opinion: not needed for Mg/Al/Si/Cu/O/Zr (≤0.022 % vs Bearden); **data-rights question now covers Chantler too** `[critic C17]` |
| Line ID | manual | manual-first; Poisson-significant peak finder *proposes*; Velox's "fit but exclude from at%" state; flag escape (E−1.74) and sum (2E) positions | — |
| Window intensities | E ± w·FWHM/2, w=2; background scale (i5−i4)/((i1−i0)+(i3−i2)) on rounded indices; overlapping windows merged | port exactly (3710/15872; 2754/15090 on FePt); the per-pixel map engine on CSR = one scatter-add | pins belong to FePt, not TM002 `[validation §6]` |
| Model fit | Gaussian per line, centre/width fixed, family weights tied, poly-6 background, LS | **Poisson-ML via IRLS/EM on the fixed design**, non-negative; parity on LS only | methods pinned "4 % LS vs ML"; converged gap is 2.9 % and ML is not pinnable `[second C4]` |
| Background | poly-6 / windows | espm's 2-column physical continuum (MIT code, own line table — no espm tables bundled); SNIP only for the proposer | — |
| Peak shape / response | Gaussian; none | escape peaks as tied Gaussians; **Al Kα tail under Mg Kα has no Gaussian model → the matrix pool is the empirical blank**; pile-up flagged not fitted | — |
| Quantification | CL (first two lines above 0.1; single line ⇒ 100 %), ζ, cross-section | **k-free outputs primary** (net counts, Mg/Si ratios, enrichment over blank); typed k with source and date; refuse single-line "100 %"; theoretical k a separate sheet | methods put theoretical k out and assumed a user k-file; critic C18: none exists |
| Absorption | thin-film x/(1−e^−x), iterate <0.5, ≤30, MACs ×0.1, log-log interpolation, strip (0,0) sentinel | **four-detector geometric average from Velox azimuth/elevation/stage**, badged, per-quadrant TOA spread and thickness σ propagated; refuse only when geometry unknown; MAC source EPQ `FFastMAC.csv` | methods: refuse on summed streams; second/critic: 3–19 % Mg/Si bias |
| Decomposition | Poisson-scaled PCA (X_ij/√(a_i b_j)) | espm-style NMF-GKL + Laplacian with G from our own table | — |
| Denoising | binning | count-conserving pre-filter with kernel shown; PCA reconstruction labelled; **quantification never reads a denoised cube** | — |
`[methods §1.1]`, `[validation §1c–1d]`, `[second §3, §6]`, `[critic C8, C17]`

**Modes.** Methods proposed two user-visible modes (Parity/Science). The second opinion objects: the repo has 69 `DEVIATION` notes and no user-visible py4DSTEM toggle; "no filler". Resolution (synthesis): Core functions take explicit parameters; the parity harness passes exspy's values; the app ships one science default with inline DEVIATIONs; **provenance names the estimator**. No switch.

### 5.2 Statistics layer (Swift-native; what no vendor ships)
Net N = G − s·B, Var = G + s²·B; Fisher covariance for fitted amplitudes; CL ratio variance with counting and k terms **reported separately**; Garwood exact intervals below ~20 counts; **Currie with the window scale**: σ₀² = sB + s²B, L_C = z·σ₀ (the 2.33/2.71+4.65 constants assume s = 1 `[second C16]`); planning quantity λ_X from the matrix pool and k only ("this object needs 4× the dose"); **coverage test on the synthetic cube with a band (e.g. 68–80 % at nominal 68 %)**, because exact intervals over-cover discrete Poisson by construction `[second §3.8]`; break the test by shrinking the CI 2× `[methods §1.2]`.

### 5.3 Port order
P0 tables/FWHM/axis + MSA/hspy readers + `fetch-exspy.sh` pin (exspy `7185a4d1`, hyperspy 2.4.0, rsciio 0.14.0; 238 EDS tests pass) → P1 windows → P2 CL + absorption + MACs → P3 statistics → P4 Velox decoder + DM SI reader → P5 model (LS parity, then IRLS Poisson-ML) → P6 Poisson-PCA → P7 ζ/cross-section → P8 continuum + escape → P9 NMF `[methods §1.3]`, `[validation §1a]`. Owner's 107 streams run as *diagnostics*, never gates.

### 5.4 Joint approaches
Common substrate: joint grid = the 4D source grid; pools = precipitate objects (`Object.pixelIndices`), phase verdicts (`PhaseVectorResult.phaseIndex`), groups (`groupOf`), ROIs, **matrix pool as blank**; projection model C_app ≈ f·C_ppt + (1−f)·C_matrix with f from a **footprint ⊗ beam-broadening forward model** (~4 nm in 100 nm Al, comparable to needle width), not h/t alone `[second §3.5]`; pools inherit their source's badge (phase mapping is unvalidated, so phase-verdict pools are) `[second §5]`.

| Approach | What it computes | Needs per px | Gate | Truth now | Verdict for v5.0 |
|---|---|---|---|---|---|
| **E pooling** | live-time-weighted pooled spectrum per pool; net/L_D per line; k-free ratios; blank-subtracted difference spectrum; f shown; registration erosion shown; channelling angle | none | B + pre-registration (new science number, ROADMAP:134-140) | synthetic; YAlO₃ (1:1:3); re-acquired 190330 pair | **yes — per phase/region first; per object only on simultaneous or sub-object-registered data** (in-session Velox drift alone ≈5 nm vs 4 nm needles, units unverified) |
| **B\* arbitration table** | per candidate: diffraction evidence beside EDX profile log-likelihood and pairwise LLR; "would have seen" flag (A); no restricted matcher (C would move numbers → Gate D) | none | B for the table; **D** if combined into a posterior | synthetic Al/β″/β′/Q + θ′/T1 (LLR must be 0); Kho 2025 (labels must be regenerated) | **table only, after** per-phase score retention (`PhaseVectorResult` keeps winner + one runner-up; score is a distance `[second C6]`) **and a separability matrix** from the CIFs with k ± 20 % and stoichiometry-model spread (β″ Mg₅Si₆ vs Mg₅Al₂Si₄/Mg₄Al₃Si₄; Al in a needle is unmeasurable through Al; so β″/U2/B′ probably inseparable, β′ (Mg:Si ≈ 1.8) and Q (Cu) probably separable — literature from memory, unverified) |
| **D joint clustering** | [embedding ‖ EDX Poisson-PCA], block scale shown, `kMeans` existing, ARI vs single-modality | ~10² binned (2×2 at 30–85/px is not pure noise `[second §3.7]`) | B, exploratory badge | Duran (no truth), Kho, synthetic ARI | cheap (~2 sessions); badge |
| **H masks both ways**, **I channelling angle**, **J reverse pooling**, **K ζ thickness into N_V** | display / tiny Core | none | B | synthetic | include H, I; J if `VirtualDetector` exposes a region-mean pattern (unverified); K needs probe current (Velox `ScreenCurrent` labelled uncalibrated; GMS writes 0.0) |
| **G diffraction-regularised maps** | Poisson MAP with diffraction-weighted Laplacian; "effective counts" | ~10 | D + pre-reg | synthetic with a planted segregation line | v6 |
| **F shared-abundance factorisation** | espm half + diffraction half with shared H; no honest linear mixing for patterns | ~10² | D + pre-reg | synthetic | research after G |
`[methods §2]`, `[second §3, §6]`, `[repo §3]`

### 5.5 Strategies
- **S1 count-honest companion** (baseline + readers + registration + E + H/I/K + indistinguishability refusal): 24–34 sessions `[repo §6]`.
- **S2** = S1 + B* table + Al-Mg-Si CIFs + synthetic cube: +3–5 sessions. Bears on "which phase is this needle" only if pools reach ~10² counts and the separability matrix shows a separable pair.
- **S3** = S1 + D (+2) then G/F (6–10+).
**Recommended (re-sequenced per `[second §6]`):** (1) plain-SI baseline, k-free; (2) owner acquires the first joint field; (3) registration, E per phase/region; (4) per-object E on simultaneous or well-registered data; (5) B* table if separable; (6) D exploratory; v6 G then F.

---

## 6. Physics limits and how the app tells the user
| Limit | Fact | What the app does | Source |
|---|---|---|---|
| Li and light elements | no Li line in exspy/espm (Velox's table lists Li K-L3 at 54 eV, UI unverified); T1 and θ′ renormalise to identical 66.7/33.3 Al/Cu | element picker refuses Li/Be/H/He with the reason; result footer "at% renormalised over detected elements"; **indistinguishability check** from each CIF's `AtomSite(z, occupancy)` over detectable elements, T1/θ′ the unit test | `[validation §5]`, `[second C10]`, `[methods §2.0]` |
| Al-containing variants | Al inside a precipitate trades off against projected matrix Al | only Mg/Si (and Cu) ratios are robust; Al at% never claimed for a needle | `[critic P1-8]` |
| Projection through matrix | f = h/t; beam broadening ~4 nm in 100 nm Al | "apparent" label; f shown and editable; inversion error blow-up shown, never hidden; thickness typed ± σ or from an EELS t/λ map | `[methods §2.0]`, `[second §3.5]`, `[critic P1-11]` |
| Channelling | end-on needles are imaged on-zone, so joint EDX is channelled by design; matrix-relative quantities cancel only partly | I: misorientation from nearest low-index zone axis per pool, Al Kα rate vs orientation plot, no threshold | `[second §3.9]`, `[validation §5]` |
| Absorption and geometry | summed 4-detector stream; holder shadowing at tilt (−16.9°) unverified; Mg/Si bias 3–19 % uncorrected | four-detector model badged; TOA and source ("file"/"typed") shown; refuse when geometry unknown; NIST flags high uncertainty below 1 keV (O K, C K, Cu L) → badge | `[critic C7, C8]`, `[validation §5]` |
| Counts | owner's SIs 10.8–18.7 counts/px, 70 % Al Kα, net Mg/Si ≪ 1 per px; 4D conditions 25–85/px; per-pixel CL at 10 counts scatters ±22–28 wt%, pooled within 0.1–1.7 | counts-per-pixel histogram; per-pixel maps are display; pooled numbers with intervals and L_D; the planning quantity | `[ownerdata §7]`, `[critic C4]`, `[second C14]` |
| Spurious peaks | **Al Kα sum 2.973 keV vs Ar Kα 2.958 keV (15 eV apart, FWHM ≈ 98 eV) — inseparable; the owner's 190330 element list includes Ar, possibly a misattribution**; Al+Mg sum 2.740, Al+Si 3.226; Si internal fluorescence from the detector dead layer adds spurious Si; Cu grid peaks; escape at E−1.74 | flag positions; fit-but-exclude state; the matrix blank absorbs the Si internal-fluorescence peak; two SIs at different currents to test the Al-sum vs Ar question | `[critic C9]` |
| Zero peak | 1–6 % of events in owner files (82–100 % in public test files) | separate map, excluded from "counts"; no warning on his data | `[second C2]`, `[critic C5]` |
| Dataset-property defaults | vacuum mask 1.0 count masks 74–100 % of pixels below 10 counts; `min_intensity` 0.1; dead time 48–60 % | refuse-and-show, never port blind | `[validation §1d]`, `[methods M4]` |
| Loss function | LS vs converged Poisson-ML differ 2.9 % on FePt | provenance names the estimator | `[second C4]` |
| Damage / dose | Li loss, C/O build-up unverified for these alloys; a 4D scan at 10–20 ms precedes a sequential EDX | dose per pixel for both signals; first-vs-last-frame comparison through `FrameLocationTable` | `[validation §5]`, `[second §3.5]` |
| Unvalidated layers | phase map failed one T4 metric; B* on top of it | badges propagate from pool source to pooled result; "validation: none" until a dataset with truth passes | CLAUDE.md, `[critic P1-13]` |

---

## 7. Validation plan
**Parity pins (exspy `7185a4d1` + hyperspy 2.4.0 + rsciio 0.14.0, all confirmed by running, logs in `$S/*-2026-10-05.log`)** `[validation §1b]`: FWHM Al Kα 0.07661266 @130 eV; take-off angles 40.0 / 73.1578838 / 28.8659712; FePt windows Fe Kα 3710 / Pt Lα 15872 and 2754 / 15090 with background windows; TM002 [84163, 89063, 96117, 96700, 99075], Mn Kα 53597 / 46716; CL on FePt 15.409297 at% (windows); MACs Al@3.5 keV 506.0153, Zn Lα in Zn 1413.2911, Al-Zn 2587.4162; Al-Zn image CL 22.70779, +absorption 22.743013 / 31.816908, ζ 80.962288 / 2.7125736e-3, cross-section 49.4889, mass thickness 6.1317741e-4; closed-loop fit [0.5, 0.2, 0.3] within 1e-4; Velox 4-detector sums. **Not pins**: doctests (never run; three mislabelled), ML-poisson outputs, `test_eds_tem.py:336/646`, the demo's k = 5.75602 `[validation §1e]`, `[second C4]`.

**Data rights** `[validation §2]`, `[critic C17]`: exspy code and JSON GPL-3.0 (compatible with the repo's GPL-3.0-or-later); **FFAST MACs and Chantler line energies are NIST SRD data with a copyright notice and unclear terms** → source both from NIST EPQ's public-domain distribution (`FFastMAC.csv`, `LineWeights.csv`) keeping its notice, or xraylib (BSD-3); espm tables not bundled (CC BY-SA submodule); espm code MIT fine.

**Truth datasets**: ePSIC YAlO₃ (Zenodo 10609594, CC BY, `EDS Spectrum Image.dm4` 39.5 MB; truth = 1:1:3; also the dm4 EDS-SI reader fixture; powder thickness unknown); NIST SRM 2063a (SEM physics); Mills 2024 (Zenodo 8000141, dm4 "Diffraction SI" 5.3 GB + EDX `.hspy`, no truth); Duran 2023 (Figshare, cluster agreement only); **Kho 2025 ships no truth file — labels must be regenerated from its notebooks** `[critic C12]`; espm generators (particles N=500; grain boundary N=15); FePt core-shell published values; Thronsen SPED has truth but no EDX. **Downloads need the owner's permission**: YAlO₃ (39.5 MB), a ranged head/tail read of the Mills `.dm4`, Duran EDS `.hspy` (1.3 MB) `[critic §C]`.

**Synthetic truth** `[validation §4]`: extend `tools/demo-dataset/make_demo.py`; two tiers (parity: exspy `xray_lines_model`, k = 1; science: espm forward model with its linear FWHM law — the gap is measured, not hidden); `truth.json` records areal densities incl. Li, projected fraction, thickness, expected counts, seed, nuisances (Cu grid peak, escape/sum, channelling multiplier, wedge, scan offset/bin/drift/**reflection**, per-quadrant efficiency), dose ladder N ∈ {0.3, 1, 3, 10, 30, 100}; metrics: composition error with CI coverage in a band, spectral angle, ARI, registration error in px; commit generator + seed + hash, not the cube. θ′/T1 planted so any EDX-only separation fails.

**Gates**: exspy parity harness `tools/edx-parity-test` (Swift main + `verify_exspy.py`, negative controls); reader harness on the 7 public Velox files + GMS EELS SI layout pin; registration synthetic-truth harness; `inventory` check "unvalidated EDX stays labelled"; CI second pinned pip install, EDS-only and offline (EELS GOS files download from Zenodo) `[repo §4]`.

---

## 8. The owner's own data

### 8.1 Inventory `[ownerdata §3–4]`, `[critic C1, C15]`
- **4D**: 8 GMS cubes (Talos F200X, GIF Continuum camera, hardware-sync, 10–50 ms, 17–42 GB): 036 (2023), Ni65Cu35 (2024), **051 (190330, 2026-06-03, 128², 10 nm, α −16.87°)**, 055–060 (170330, 2026-06-30, 256²–334², 0.5–1.9 nm); binned `.h5` derivatives exist (`060 … bin_4` is the app's training cube).
- **EDX**: 2149 `.emd`; 142 with a stream, 104 unique acquisitions (66.7 GB), Velox 2.15.0.45, EMD v9/v11, Super-X G1 summed single stream, 4 SDDs, 20 eV/ch, 0.225 sr each, elevation 22°. Al-Mg-Si family: 190330 (3 SIs 06-03 at α +7.3°, 2048×682, 6.25 µs × 120), 170330 (05-08/05-12/06-05, incl. the 7.45 GB 2048² × 480-frame file), 140330. Counts 10.8–18.7/px. Also NiCu HPT, Au, FeO, Rh/SiO₂, HP087 (~545/px), rock wool (~470/px), 8 Oxford `.h5oina` SEM maps, one `.msa`.
- **No** simultaneous 4D+EDX, no `.mrc`, `.dm5`, `.bcf`, `.pts`, `.rpl`; EELS SIs (13 GB TiO₂) are the only GMS 3D-SI layout examples.
- **Earlier HyperSpy work**: notebooks with placeholder k-factors (1.0 for Al/Mg/Si); pipeline reference only.

### 8.2 Pairing `[ownerdata §5]`, `[critic C14]`
Only 190330 on 2026-06-03 has same-day 4D and EDX: the Velox HAADF at 18:41 (−385.0, −125.7, −16.87°) matches cube 051 at 18:51 to ~1 µm and correlates uniquely with its ADF survey at mirror + 90°; the three EDX SIs sit ~18 µm away at +7.3°. 170330's EDX (May/June 5) and 4D (June 30) are different holder sessions (stage differs by ~235 µm).

### 8.3 Fixtures (read-only copies) `[ownerdata §6]`
Rh/SiO₂ 1456 (54 MB, 6.2 counts/px), FeO 1610 (143 MB), Al-Mg-Si 1606 (169 MB) / 1623 (214 MB) / 140330 1339 (261 MB), `CA_DA_170330_EDX_2.emd` (441 MB, notebook baseline), the three single-spectrum `.emd`, the `.msa`, one `.h5oina` (46 MB); 4D side `051 … bin_4` (268 MB).

### 8.4 What to acquire next, concretely (synthesis from `[critic §C]`, `[second §6]`, `[ownerdata §9]`, `[gms §6]`, `[formats §5]`, `[inputs §11]`)
**A. Sequential pair at the 4D field (possible today, highest value per hour).**
1. On the 190330 lamella, go to the 051 field at α −16.87° (stage already matches the 18:41 HAADF). Record a fresh Velox HAADF reference first.
2. Velox EDX SI over a rectangle that contains the 4D field with margin, at the README settings (spot 5, C2 100 µm, CL 125 mm) but with the **frame count raised until ≥100 net counts per pixel on the binned 4D grid** is plausible — at 9.5–9.8 counts/(ms·nA) that is ~5–10 ms total dwell per Velox pixel region `[critic C4]` (estimate; thickness differs). Drift compensation on; **no Reduce File Size, no pruning**; keep all frames.
3. Note the screen current and the 4D optics (spot, C2, convergence) in the session log — GMS records 0.0.
4. Order: the 4D scan was already taken (dose/contamination precedes the EDX); for a new field, 4D first, then EDX, and say so in the file names.
5. Same session: an EELS low-loss t/λ map on the Continuum over the same field (thickness for absorption, f, and N_V).
6. Two short SIs at two beam currents on the same field (Al-sum vs Ar question) `[critic C9]`.
7. Both Velox and GMS stage positions, `ScanRotation`, and the GMS survey `Spectrum Image Rect` are what the registration seed needs; nothing else is required.

**B. STEMx 4D + EDS test (only if service confirms R1 on this Talos).**
1. Before the microscope: ask Thermo/Gatan/Bruker whether GMS can drive the Super-X (Esprit `ExternControl`, IO firmware, DDC), whether the lab holds 700.LS.707 and 700.LS.777, and the cost; ask whether the Talos has a speed-enhanced Ceta-2 with the 4D option (R2) `[critic P0-2, P2-16]`.
2. Small scan (64×64 or 128×128), hardware sync, **no sub-pixel scan, one cycle, no DM binning of the EDS** (some GMS versions store averages), EDS channels/dispersion noted, survey image kept; include a sharp edge (lamella edge or a hole) in the field for the EDS-vs-camera pixel-lag test and a flyback-column check `[formats §2.1]`, `[second §2.5]`, `[market E1]`.
3. Save **once as `.dm4` and once as `.dm5`**; export the DM Help pages for STEM SI, Diffraction Imaging and EDS Quantification from the GMS PC `[gms §0, §6]`.
4. Use the higher-current optics the EDX needs only if the 4D disks still separate; otherwise accept 25–50 counts/px and plan on pooling — the 2–180× per-area deficit `[critic C4]` means this run is for the **file layout and the identity/lag check**, not for the science number.

**C. A k-factor reference** (owner decision V5-5): theoretical k from NIST EPQ data; or a homogeneous solution-treated sample of the same alloy with known bulk composition (unverified that one exists; as-built LPBF is not homogeneous); or a thin-film standard; or ship ratios only.

---

## 9. Repo impact and staged plan

### 9.1 Blockers before any v5 code `[repo §0]`, `[critic C19, P0-6]`
ADR 049 lists EDX as frozen and ADR 051 keeps it "unclaimed" — the owner reopens; the "Unverified on screen" row (`docs/status.md:31`) is non-empty — a drive empties it; **CI on `main` is red** (`DiskCentreLabels.swift:330` type-check timeout; mechanical split, no Gate D) `[v45 §2.1]`; ADR 051 says EDX "v5 or v6" — an ADR 007 amendment fixes 5.0.0.

### 9.2 What changes in the frozen shell `[repo §2b–2e]`
`UI/WorkspaceView.swift` must change (exhaustive switches on `WorkspaceArea`: content branch :84-100, `primaryActionTitle/Hint/Enabled`); `UI/LayoutPolicy.swift` only if new constants; avoid a new `ProductDomain` case (frozen `WorkspaceInspector`) and a third process pane (`WorkspaceNavigation`). `App/ProductWorkflow.swift` gains the enum case, `AnalysisMode` cases (persisted raw values), `.requiresSpectra` prerequisite family, readiness, guidance; `AppState` room tables (optionally moved to `AppState+Workspace.swift` first, placement only); menu ⌘6/⌘7 choice; width floor stays 915 pt if the spectrum pane accepts 180 pt; tests `ProductWorkflowTests:113-114, 238-241`, `InspectorWidthBudgetTests:208`. **New**: `SpectrumPane` (Swift Charts would be new to the repo; or `Canvas`), `SpectroscopySettings`, `AppState+Spectroscopy`. The mock (format of `docs/archive/v4/x3-mock-notes-2026-10-01.md`: rows/pt, frozen touch points, options) must show **both** the attached-spectrum window and the spectrum-only window `[second §2.6]`.

### 9.3 Work packages (sessions = one gated lane with refuter and docs) `[repo §6]`, amended
| WP | Content | Sessions | Gate | Blocker |
|---|---|---|---|---|
| 0 | Reopen ADR; **room mock incl. spectrum-only window**; data-model, pin and ADR 007 sheets | 2–3 | owner | freeze; Unverified row; CI |
| 1 | Reproduce the Velox `.emd` open on the public v11 file; discovery refusals (Velox tree, `signal_type` EDS/EELS, energy units, DM `Format = Spectrum image`); `DataCubeDerivation` read-back | 1–2 | B | can land in v4.5 |
| 2 | `EnergyAxis`, `SpectrumDescriptor`, `SpectrumDataSource`, `SparseSpectrumStore` (CSR), `SpectrumArray`, combined residency; pbxproj exception list + `sources.manifest` `spectra` group | 2–3 | B | — |
| 3 | Readers: MSA + `.hspy` (1), **Velox stream + drift provenance + fingerprint-in-pass + optional CSR cache** (3), DM SI facade on a factored `DMFile` tested on the EELS SIs and YAlO₃ (2); `.bcf` deferred | 6 | B | YAlO₃ download permission |
| 4 | `ScanRegistration` with reflections; mask transport; metadata seed → survey-ADF correlation → manual; identity lag check; refusals; synthetic truth (offset, bin, drift, **mirror**) | 2–3 | B + pre-reg | — |
| 5 | Sidecar child group, schema 8, lineage kinds, bookmark, back-compat tests | 2 | B | — |
| 6 | `fetch-exspy.sh`, constraints, python resolver, CI job, NOTICE section, DEVIATION convention citing exspy file:line | 1–2 | — | data-rights answer |
| 7 | EDS port P0–P3, then P5–P7: windows, CL/ζ/cross-section, four-detector absorption badged, statistics layer, LS parity + IRLS Poisson-ML, Poisson-PCA | 6–9 | B + parity | — |
| 8 | Room UI + spectrum-only window + drive | 3–4 (+1–2 for M2′) | drive | mock accepted |
| 9 | E (per phase/region, matrix blank, f model), H, I, K (ζ with labelled current) | 2–3 | B + pre-reg | the re-acquired pair |
| 10 | Per-phase score retention (additive), separability matrix, B* table; then D exploratory | 3–5, then 2 | B; D if posterior | CIFs; synthetic cube |
| 11 | G, then F | 6–10+ | D | v6 |
| 12 | Validation datasets, owner drives, acquisitions | 2–3 + microscope time | — | owner |
Minimum viable (0–9, no `.bcf`, with M2′): ~27–38 sessions; at three parallel lanes ~10–14 slots (estimate). Token cost against the conservation directive is not priced `[critic P1-15]`.

### 9.4 Risks
Data (no joint file; the GMS path may not exist for this lab); physics (counts, Li, projection, absorption bias, sum peaks); mechanics (frozen-shell edits forced by exhaustive switches; 8 GB Mac memory — minimum supported Mac for EDX unstated `[critic P2-19]`; the single HDF5 lock); compatibility (unknown-storage fallback, replay refusal of unknown kinds); parity (fit parity is a tolerance; ML unpinnable); data rights (NIST SRD for both MACs and line energies); the owner's token budget.

---

## 10. Open questions and the decisions owed

**Still unverified (settle by the named action)**
1. GMS 4D+EDS on this Talos: licences, service path, file layout (one `.dm4` or per-signal), EDS object name/dtype/channel tags, cycle summation, per-pixel live time, `.dm5` — the STEMx test + service enquiry.
2. Super-X G1 EDS-vs-STEM shift (Velox UM p.259) — decode early/late frame ranges, bin 8–16×, correlate total-count maps `[critic P1-7]`.
3. Units of A13/A23; whether drift compensation was on for every owner file `[second §7]`.
4. `ScreenCurrent` as probe current; whether 051 used the 18:41 optics; holder shadowing at −16.9° `[second §7]`.
5. Velox `ScanTransformation` semantics; app readers' own axis conventions (interacts with `docs/open-items.md:183`) `[critic C14]`.
6. β″ composition literature (recalled from memory) `[second §7]`.
7. Whether the Velox `.emd` open defect reproduces in the app (emulated only) `[critic C20]`.
8. Ceta-2 / 4D option on the Talos; GMS 3.62 plans; EDS/Hi-Speed licences `[critic P2-16]`.
9. YAlO₃ contents; Mills 2024 methods (PDF unread) `[critic P2-17]`.
10. Swift decode throughput and CSR cache size (Python: ~10 s) `[critic C6]`.
11. Whether `VirtualDetector` exposes a region-mean pattern (J) `[methods §5]`.
12. Third-party rights inside EPQ (Henke, Salvat) `[validation §2]`.

**Decisions owed** (each with the ADR 050 second opinion; the cards below are the sheet's source): the science question; the acquisition route and first acquisition; plain-SI window + room mock; data model and cache; k-factor source; absorption on summed data; parity/data-rights policy (M1/M2/M3/D1 + Chantler); joint scope for v5.0 (E only / + B* table / + D); v4.5 remainder (Velox refusal, reopen ADR 049, ADR 007 amendment); thickness input and whether "Spectroscopy" brings EELS into scope; CIF set (M5); probe current (M6); first truth dataset (M8); fingerprint policy (largely dissolved by hashing in the decode pass `[second §2.8]`); minimum supported Mac; CSR cache policy.

---

## 11. Sources
**Sibling reports** (this brief): inputs, methods, second opinion, completeness critic, velox, gms, formats, market, ownerdata, repo, validation, v45. Their scratch files under `$S/`: `critic/` (`velox_meta.py`, `velox_series.py`, `velox_drift.py`, `stream_census.py`, `h5pick.py`, `xreg.py`, `velox212.txt`, `talos_preinstall.txt`), `critic2/` (`velox_owner_checks-2026-10-05.log`, `ml_converge-…`, `ml_irls-…`, `absorb-…`), `ownerdata/` (`emd_scan.jsonl`, `dm_scan.jsonl`, `edx_unique.tsv`, `dm_summary.txt`, `cmp_*.png`), `formats/` (`dmdump.py`, `velox_*.py`, `eds_spectrum_dm3_tags.txt`, `eels_si_dm4_tags.txt`), `velox/` (carved installer docs: `Velox 3.15 User Manual.pdf`, release notes, Tips, `EdgeEnergies_v1.csv`, `K_Custom.csv`, `Mac_Nist_LL.dat`), `gms/txt/` (STEMx manual, EDS Acquisition Installation Guide, ReleaseNotes, Python, Elite T, DigiScan 3, K2 IS), `market2/`, `exspy` (clone `7185a4d1`), `espm` (clone `e882ed6b`), `rsciio` (clone `049e7d70`), `venv`, the dated logs `pytest-eds.log`, `verify_doctests-`, `checks2-`, `reimpl_windows-`, `fept_quant-`, `lowcount-`, `li-`, `checks3-ffast-`, `espm_data-2026-10-05.log`, `v45-inventory.log`.
**Repo** (HEAD `85920f91`): `Core/Data/{DM4Reader,H5Reader,HDF5Types,FourDDataSource,DatasetDescriptor,LoadSpecification,FourDArray,ResidentCube,BraggVectorEMDTypes,BraggVectorEMDWriter,SessionLineage,DisplayedProduct}.swift`, `Core/Crystal/{PhaseVectorMatching,Crystal}.swift`, `Core/Analysis/{Precipitates/PrecipitateSegmentation,DiffractionEmbedding,VirtualDetector,OrientationResult}.swift`, `Core/Compute/MatrixDFTCorrelation.swift`, `Session/{DatasetSession,SessionSidecarLocator,ReplayPlan,PrecipitateObjectReport}.swift`, `App/{AppState,AppState+Open,ProductWorkflow,mac4DSTEMApp,WorkspaceNavigation}.swift`, `UI/{ContentView,WorkspaceView,WorkspaceInspector,LayoutPolicy,PhaseMappingSettings}.swift`, `tools/{run-tests.sh,lib/sources.manifest,lib/python.sh,datacube-discovery-test,package-test,release/*}`, `docs/{status.md,open-items.md,architecture.md,dm4-format.md,releasing.md,decisions/007,035,046,047,049,050,051}`, `ROADMAP.md:78-80,109-140`, `CLAUDE.md`, `CITATION.cff`, `NOTICE`, `Info.plist`.
**Web**: Zenodo 10609594, 8000141, 14859606, 8403583, 7521571, 12699952; Figshare 10.48420/21610977; arXiv 2504.19762, 2304.12259, 2404.17496, 2405.14649, 1910.06781, 2508.20657, 1708.04565; Duran 2023 Comput. Mater. Sci. 228:112336; Parish 2022 Microsc. Microanal. 28:371; Gatan Warwick talk (Gorji); TESCAN MMC 2023 abstract (Hooley); Oxford AZtec docs (O1–O7); Bruker QUANTAX manual (B4); Velox datasheet; UF Themis Z SOP; ChemiPhase AN0227; ePSIC 4DSTEM-EDX manual; OSTI 644310; Wenner 2017; NTNU theses; Niigata Si internal fluorescence; NIST FFAST and licence pages; usnistgov/EPQ; xraylib; rsciio #97, #17, #239, #255, #315, #343, #484, #516, #541; hyperspy #1850, #2362, #2534, #2899; exspy #100, #112, #116, #117, #170, PR #126.

