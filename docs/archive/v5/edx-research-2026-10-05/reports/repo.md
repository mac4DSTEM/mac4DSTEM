# Repo impact study: v5.0 EDX ("4D-STEM + EDX") in mac4DSTEM

**Scope.** I read the repo at HEAD `85920f91` and wrote nothing to it. I did not build or run anything in the repo.

**How claims are marked.**
- `file:line` is repo-relative under `<repo>` unless it says otherwise.
- **[verified]** means I read the code or the file myself.
- **[sibling]** means the fact comes from another agent's notes under `<scratch>/edx/`. I read those notes but did not re-derive them.
- **[unverified]** means inference or memory.

Before any v5 work can start:
- **The feature freeze has to be lifted by the owner.** ADR 049 lists "EDX correlation" as frozen (`docs/decisions/049-v4.1-is-the-plateau.md:15-17`). ADR 051 says EDX "stays unclaimed until then" (`docs/decisions/051-release-after-the-owners-drive.md:13-14`).
- **The "Unverified on screen" row must be empty.** CLAUDE.md's "drive before more surface" rule blocks new on-screen surface until it is, and today it is not (`docs/status.md:31`).

## 1. Data model for a second signal

### 1a. Which existing abstractions generalise and which need a sibling

| Existing abstraction | Verdict | Why |
|---|---|---|
| `DatasetDescriptor` (`Core/Data/DatasetDescriptor.swift:8-50`) | Needs a sibling | It is 4D only: `is4D`, `ry/rx/qy/qx` and `byteCountAsFloat32` (:37-45). `AppState.hasDataset` is defined as `descriptor?.is4D == true` (`App/AppState.swift:1169`; 29 uses in 13 files). |
| `FourDDataSource` protocol (`Core/Data/FourDDataSource.swift:165-217`) | Pattern generalises, protocol does not | The reads are pattern, scan row and scan tile in Qy×Qx. Keep the shape: an `Actor`, `LoadView`-taking reads, and a declared `loadPushdown`. |
| `AxisCrop` (`Core/Data/LoadSpecification.swift:48`) | Generalises as is | A scan crop is the same type for both signals. |
| `LoadSpecification` / `LoadView` (:71-109, :232) | Needs a sibling | Detector crop and bin, with bin factors fixed at {2,4,8} (:86-89). A spectrum needs an energy range, an energy bin, a spatial bin, frames and a detector-quadrant mask. |
| `LoadView.sourceScanY/X` (:365-367) | Generalises | View→source scan mapping is exactly what composing a registration needs. |
| `FourDArray` (`Core/Data/FourDArray.swift:15-434`) | Needs a sibling | LRU of patterns, tile reads, residency. The tile budget formula (physical RAM/24, :366-412) should be lifted into a free function taking bytes per row. |
| `ResidentCube` / `ResidencyAdmission.shouldAdmit` (`Core/Data/ResidentCube.swift:180-194`) | Needs a sibling | It has a `guard descriptor.is4D` (:185). Leave `measuredWorkingSetFraction` nil (:140; CLAUDE.md). |
| `DataCubeDerivation` (`Core/Data/BraggVectorEMDTypes.swift:308-417`) | Generalises, but is incomplete | It records `scan_offset` and `scan_stride` of a preprocessed `.h5`, which is what composing a registration with a preprocessed file needs. It is **written but never read back**: the attribute is written at `BraggVectorEMDWriter.swift:24,1653` and grep finds no reader. |
| `SessionLineage` (`Core/Data/SessionLineage.swift`) | Generalises | `External` (name + fingerprint, :83-91) already models a file from outside the session; `recordRun(... external:)` exists (:507). |
| `DisplayedProduct` (`Core/Data/DisplayedProduct.swift:77-146`) | Element maps fit; spectra need a sibling | Payload is `.scalar`/`.rgba` only (:33-43); domain is `scan/detector/reconstruction` (:7-11). A new domain would hit the frozen `UI/WorkspaceInspector.swift:648-654` (`frameLabel`). Element maps fit as `.scan` scalar maps; spectra need their own type. |
| `DM4Reader` internals | Partly generalise | It already records every `Data` blob's offset and size (`dataArrays`, `Core/Data/DM4Reader.swift:588,678-679`) and short ushort-array strings (:587,680-684). A Gatan `Meta Data.Signal = X-ray` / `Format = Spectrum image` tag is therefore already in `strings` [sibling: `formats/eds_spectrum_dm3_tags.txt:143-145`, `eels_si_dm4_tags.txt:257-262`]. The mapping and the volume-liveness latch (:53-96, :225-229) are what a spectrum facade should share. |

### 1b. Proposed types and files

These are design suggestions, not decided. The owner's rule is "SwiftUI only, Core has no upward imports".

**Core/Data (DSTEMCore)**
- **`EnergyAxis.swift`**:
  - offset, scale and channel count, held in keV, plus where the calibration came from (file or fitted).
  - `energy(ofChannel:)` and `channel(ofEnergy:)`.
  - The original unit string (DM writes eV or keV; HyperSpy writes keV).
- **`SpectrumDescriptor.swift`**, sibling of `DatasetDescriptor`:
  - file path, object path, scan shape `[ry, rx]`, channel count, dtype;
  - storage: dense layout (energy-fastest or planar) or an event stream with a frame count;
  - signal type (`EDS_TEM`, `EDS_SEM`, `EELS`), detectors, scan pixel calibration, companion images (HAADF/ADF on the spectrum grid).
- **`SpectrumDataSource.swift`**: `protocol SpectrumDataSource: Actor` with:
  - `discoverSpectrumImages()`, `loadPushdown(for:)`;
  - `readSpectrum(view, ry, rx)`, `readEnergyPlaneTile(view, channels:)`, `readSpectrumTile(view, yRange:)`;
  - `acquisitionMetadata()`: beam keV, live and real time, elevation, azimuth, stage tilt, MnKα resolution, dwell, frames, probe current;
  - `companionImages()`.
- **`SpectrumLoadSpecification.swift`**: scan crop (reusing `AxisCrop`), spatial bin, energy range, energy bin, frame range, detector mask, plus `SpectrumView`.
- **`SpectrumEventIndex.swift`**: a sparse store (row pointer per scan position, UInt16 channel per count).
  - Low-count data argues for sparse first: at about 10 counts per pixel, a 256² scan is about 655k events [unverified estimate].
- **`ScanRegistration.swift`**, a Codable JSON record with deterministic encoding like `LoadSpecification.jsonString`:
  ```swift
  struct ScanRegistration: Codable, Equatable, Sendable {
    var schema = 1
    var spectrumSource: SignalReference   // file NAME + fingerprint + object path, never a path
    var scanSource: SignalReference       // the 4D source
    var sourceGrid: [Int]; var targetGrid: [Int]   // full-extent grids, not views
    var transform: [Double]               // 2×3 affine, spectrum px -> 4D SOURCE px
    var kind: Kind      // identity | integerBin | similarity | affine
    var method: Method  // sameAcquisition | metadata | imageCorrelation | manual
    var resampling: Resampling  // countConservingFootprint (default) | nearest
    var evidence: [String: String]  // companion image, virtual detector, peak quality, residual
    var recorded: Date
  }
  ```
  - Register against the 4D **source** grid. Compose with the view (`LoadView.sourceScanY/X`) and with `DataCubeDerivation` at the moment of use; never bake the composition in.
  - That way a rehearsal crop that is later promoted, or a preprocessed `.h5`, never needs registering again. It requires H5Reader to read `mac4dstem_derivation` back, which nothing does today.
  - Resampling should never interpolate counts. Summing the spectrum pixels whose centres fall in a 4D pixel's footprint conserves counts; bilinear interpolation breaks Poisson statistics.
- **`SpectrumArray.swift`**: an actor, sibling of `FourDArray`: an LRU of spectra, tile reads, a cached total spectrum, and an optional resident buffer (CPU arrays; Metal only if fitting goes to the GPU).
- **Readers:**
  - **HSpy SI**, for HyperSpy `.hspy`. The layout is `Experiments/<title>/data` plus `axis-N` attributes (name, units, scale, offset, navigate) and `metadata/Signal.signal_type`. [verified: I opened both exspy fixtures with h5py; both are 1D, see §4.]
  - **DM SI**, a DM "Spectrum image" object sharing the DM4 file mapping. Recommended: factor a `DMFile` (parse, object table, mapping, liveness) out of `DM4Reader` and put two facades on it.
    - In an EELS SI test file the dimensions are #0/#1 = µm and #2 = eV, stored fastest-first [sibling: `formats/eels_si_dm4_tags.txt:101-116`].
    - So energy planes are contiguous (energy-window maps are cheap) and a per-position spectrum is a gather. That is the same problem `scanFastestGather` already solves (`DM4Reader.swift:304`).
  - **Velox EMD**: decode the SpectrumStream into binned dense or sparse form, stream it in chunks under `HDF5Serial`, read companion images, and parse the metadata JSON including `Scan.ScanTransformation.A11…` [sibling: `ownerdata/emd_scan.jsonl` line 1].
  - **Bruker `.bcf`**: defer.
- **Plumbing:** H5Reader's `HDF5Library` is file-private (`Core/Data/H5Reader.swift:81`). A new HDF5 reader must either get it widened to `package` or live in or extend `H5Reader`.
- **Placement:** a new `Core/Spectra/` folder for algorithms. `Package.swift` picks it up automatically (`path: "mac4DSTEM/Core"`, :24). The app target still needs every new file added to the explicit pbxproj exception list (`docs/architecture.md:28-31`), and each new `Core/Data` file needs a `tools/lib/sources.manifest` group (`docs/architecture.md:181-183`).

**Session (DSTEMSession)**
- **`SpectrumSession`**: the attached source (reader, array, descriptors), loading and cancellation state, the energy-calibration override and the active registration. It is tied to `DatasetSession.epoch` (`Session/DatasetSession.swift:27`), so a new 4D activation invalidates or re-validates the attachment.
- **`SpectralMapsProduct`**: element/line selection, integration and background windows, fit settings, retained maps and quantification, and staleness. It mirrors `StrainProduct` / `DiffractionGroupsProduct`.
- **`JointAnalysisProduct`**: pooled spectra per object, phase, group or region of interest, and arbitration results.
- **`DisplayedSpectrum`**: the energy axis, counts, variance, line markers and provenance. Keep it out of `DisplayedProduct` to avoid its seven payload switch sites plus the ones in `ResultsWorkspace`, `ResultExport` and `Session/ResultPresentation`.

### 1c. Residency and memory mapping
- **Same-file GMS case.** A DM X-ray SI is served from the existing mapping at no extra residency cost. Keep the liveness latch rule (`DM4Reader.swift:39-96`).
- **Velox needs aggregation on import.** A sibling scan of one owner file shows a 2048² scan, 480 frames and a stream of 1.59e9 uint16 values (about 3.2 GB) [sibling, `ownerdata/emd_scan.jsonl` line 1]. Dense float32 at 2048²×4096 would be about 64 GB, so it has to be binned or sparse.
  - This is the "never full-read bigger than RAM" rule (the 8 GB-Mac panic lesson).
- **Budget the two signals together.** "Keep the cube in memory" (ADR 050 #4) plus a resident spectrum cube needs one combined byte budget. `shouldAdmit` is per-cube and 4D-only.
- **Lock contention.** HDF5 calls go through one process-wide lock (`HDF5Types.swift` `HDF5Serial`). A long Velox decode must release it between chunks or it will stall 4D tile reads from H5 files.

### 1d. Sidecar and lineage v2 with a second input
- **Use a child group, not root attributes.** Put `spectroscopy/` under `/braggvectors_root` with the registration JSON, a source snapshot (`SignalReference`, `EnergyAxis`, metadata) and rank-1 spectra as attributes and datasets.
  - v4.x writers copy unknown root children as opaque objects on every rewrite (`BraggVectorEMDWriter.swift:2005-2021`). They drop unknown root attributes (ADR 047 R6).
- **Never put rank-2 spectral stacks in the result manifest.** An unknown `mac4dstem_storage` value falls back to `.scalarFloat32` (`BraggVectorEMDWriter.swift:1172-1173`). The shape check only requires rank 2 (:1347-1348). An older build would display an (objects × energy) stack as a scalar map, which is a misread. Rank-1 spectra are skipped harmlessly.
- **Element maps can be ordinary results.** They are `scalar_f32` results in the manifest (kind `edx_map_<line>`, units counts or at.%, provenance with the registration id and `validation: none`) and read correctly in v4.x.
- **Schema.** `currentSchema` 7→8 as an additive change; the min-reader marker stays put, exactly as with the lineage (`HDF5Types.swift:44-54`).
- **Sidecar naming is unchanged.** It stays keyed to the primary source (`HDF5Types.swift:28`). The spectrum file is a second input and travels as name + fingerprint, never a path.
- **Lineage: no format change needed.**
  - New lineage-only kinds `spectrum_attach` (carries `external: [spectrum file]`), `spectrum_energy_calibration`, `spectrum_registration`, `spectral_maps`, `spectral_fit`, `spectral_quant`, `spectral_pooling`, `joint_*`.
  - New input roles `spectra`, `registration`, `groups`; add `inputPolicy` rows (`SessionLineage.swift:200-217`), `downstreamKinds` rows (:188-191) and `lineageKind(forProductKind:)` cases (:603-614).
  - They **must** go into `lineageOnlyKinds` (:177-180). `ReplayPlanner` refuses any unknown kind by name (`Session/ReplayPlan.swift:853-856`), so a projected EDX step would make older builds refuse the recipe.
  - Unknown kinds are kept as opaque nodes by v4.5 readers (ADR 047 R8), and lineage `version` stays 2.
  - The recording entry point already takes `external:` (`App/AppState+Lineage.swift:28-38`; `Session/SessionReplay.swift:105-117`).
- **Fingerprinting is an owner decision.** CIFs get a full content hash. A 7–29 GB source on an external SSD or NAS makes a full hash cost minutes, so the choice is a full streamed hash or a named "partial fingerprint" (size + header + first/last N MiB).
- **Sandbox.** The spectrum file needs its own user selection plus a stored bookmark, like the sidecar (`Session/SessionSidecarLocator.swift:31-38`). The attach importer can be a `.fileImporter` in the room's inspector, as CIF import is (`UI/PhaseMappingSettings.swift:456`), so the frozen `ContentView.swift:39-42,86-92` stays untouched.

### 1e. Problems found in today's code (eligible for a v4.x polish slot, since they are defects in shipped opening)
1. **Opening an EDX `.hspy` or a Velox `.emd` today likely shows a nonsense one-row "datacube" instead of a refusal.**
   - `describe` promotes any rank-3 array to `[1, N, Qy, Qx]` (`H5Reader.swift:550,558-560`).
   - Canonical paths are honoured first-match even at rank 3, and `/Experiments/__unnamed__/data` (HyperSpy's default) is one of them (`:267-274,308-314`).
   - Otherwise any rank-3 node is promoted (`:361-368`). This is the stated contract (`tools/datacube-discovery-test/main.swift:240-241`).
   - Velox EDX files hold `(h, w, frames)` image stacks, e.g. HAADF `[1800,1800,480]` [sibling: `ownerdata/emd_scan.jsonl`, `edx_unique.tsv`].
   - `datacubeRejection` (`H5Reader.swift:1132-1143`) has no energy-axis or Velox signal.
   - **This is predicted from the code, not reproduced in the app.**
   - Fix: refuse by name on energy units on the last axis, `signal_type` EDS/EELS, the Velox tree, and DM `Format = Spectrum image`. That needs Gate B on the reader and new discovery-test cases.
2. **`DataCubeDerivation` is never read back** (see §1a). Needed to compose a registration with a preprocessed file.
3. **DM `axisDomain` does not recognise `eV`/`keV`** (`DM4Reader.swift:815-830`). The 3D branch relies on a global `Scan shape X/Y` search (:753, :878-881) plus the blob-size check (:780) to skip an SI. That is low risk but implicit.

## 2. The seventh room ("Spectroscopy")

### 2a. Required decision records (next free ADR is 052)
1. The owner reopens the freeze for v5 EDX (ADR 049/051).
2. A room ADR amending ADR 035 and ADR 046, against an accepted mock. ADR 046 notes "Six workspaces, as today, so the window's width budget is unchanged" (:28-29). The mock should follow the `docs/archive/v4/x3-mock-notes-2026-10-01.md` format (rows/pt cost, frozen-file touch points, options), archived under `docs/archive/v5/`.
3. A data-model ADR (§1).
4. An eXSpy pin ADR (§4).

Each goes to the owner as a decision sheet (ADR 050).

### 2b. Code that must change (exhaustive switches mean a new case does not compile without these)

**`App/ProductWorkflow.swift`**
- Enum `WorkspaceArea` (:10), `title` :27, `subtitle` :38, `systemImage` :49, `analysisModes` :60.
- `AnalysisMode` cases :106 (raw values are persisted into provenance and recovery).
- `TaskPrerequisiteFamily` :187 (amend the "deliberately three cases" comment :181 and add `.requiresSpectra`), `prerequisiteFamily` :212, `replayKind` :228 (nil; lineage-only), `workspaceArea` :241, `productTitle` :253, `productSubtitle` :268, `systemImage` :282.
- `ProductWorkflowReadiness` :298 (needs has-spectra, has-registration), `currentReplaySignature` :447, `prerequisiteItems` :501, `guidance` :659, `nextStepHint` :706, `recommendedNextArea` :733.

**Elsewhere**
- `App/AppState.swift`: `changeMode`/`selectWorkspace` :1176/:1191, `hasPrimaryWorkspaceTask` :1207-1232, `canRunPrimaryWorkspaceTask` :1238-1247, `runPrimaryWorkspaceTask` :1253-1299.
- `App/mac4DSTEMApp.swift`: Workspace menu :229-238 and bottom-pane enablement :177.
- `App/AppState+ResultPresentation.swift`: :38 and `presentProductForEnteredMode` :183.
- `UI/WorkspaceSettings.swift:20-39`, which routes to a new `UI/SpectroscopySettings.swift`.
- `UI/WorkspaceSidebar.swift`: rows come from `allCases` automatically (:43); review the badge rule :118-125, the short label :141 and `taskHasProduct` :193.
- `UI/ImagePanes.swift:1333` and `Support/ResultMetadata.swift:92`.
- `UI/WorkspaceRoute.swift` needs no change (it is derived).

**Frozen files**
- **`UI/WorkspaceView.swift` must change:**
  - the content branch :84-100, which today is always `PaneSplit { DiffractionPane() } trailing: { RealSpacePane() }`;
  - `primaryActionTitle` :295-334, `primaryActionHint` :347-368 and `primaryActionEnabled` :371.
  - Because these switches are exhaustive, the accepted picture is needed before the enum change can even compile.
- **`UI/LayoutPolicy.swift`** only if new numeric constants are added. UI contract rule 3 puts every chrome number there, and inventory greps fixed frames outside it except in science files (`tools/run-tests.sh` frame check). Either the constants go into the frozen file or a new `SpectrumPane.swift` joins the exemption regex.
- **`UI/WorkspaceInspector.swift`** only if a `ProductDomain` case is added (:648-654). Avoid it.
- **`App/WorkspaceNavigation.swift`** only if the spectrum goes into the bottom area as a third process pane (`ProcessPane` :71). Avoid it.

**New files:** `UI/SpectrumPane.swift` (Swift Charts would be new to the repo, since nothing imports Charts today; or `Canvas` like `LineageGraphView`), `UI/SpectroscopySettings.swift`, `App/AppState+Spectroscopy.swift`.

### 2c. Keyboard shortcut
The menu comment says "Results is 6: the rooms are ordered by the pipeline, and Results is last" (`App/mac4DSTEMApp.swift:235-237`). ⌘7 is free; the only digit shortcut elsewhere is ⌥⌘0 (`UI/WorkspaceInspector.swift:161`).
- **Option A:** Spectroscopy ⌘6 and Results ⌘7. Keeps "Results is last" but remaps ⌘6.
- **Option B:** Spectroscopy ⌘7 after Results. Breaks the stated rule.

### 2d. Width floor (915 pt)
- **Today:** the floor is 230 + 320 + 4 + (2×180+1) = 915 (`UI/LayoutPolicy.swift:29-32,40,48,81,90`). The sidebar maximum of 270 is derived from that floor (:36-40).
- **Two panes at 180 pt:** the floor is unchanged, and a seventh sidebar row adds height only, not width.
- **A wider spectrum floor raises the floor globally.** The minimum is global, so e.g. a 280-pt spectrum floor makes it about 1015 pt, moves the sidebar-maximum derivation and the 1095-pt navigator line, and breaks `NavigationSeamTests:131-147`.
- **Recommendation:** keep 180 pt, let the user widen the split, and have the mock cost it.

### 2e. Tests
- **Need edits:**
  - `ProductWorkflowTests.swift:113-114` (raw-value list) and :238-241 (titles list).
  - `InspectorWidthBudgetTests.swift:208` expects `AnalysisMode.allCases.count + 2`. That still holds if the room has tasks; it becomes +3 if the room is taskless.
- **Pick up the room automatically:** `ProductWorkflowTests:83-91,228,312,487,520`, `FinalPolishFTests:203`, `OverlayGeometryTests:129`, `NavigationSeamTests:54-96` (add a default-task case).
- **New:** a menu-predicate-mirrors-toolbar test like `FinalPolishFTests:200-212`, plus a drive at 915 and 1470 pt.

## 3. Where joint analysis hooks into existing results

| Approach | Hook | Note |
|---|---|---|
| **E. Pooling** (recommended first) | Precipitate objects: `PrecipitateSegmentation.Object.pixelIndices` (`Core/Analysis/Precipitates/PrecipitateSegmentation.swift:27`), via `PrecipitateClassificationProduct.result` (`Session/PrecipitateClassificationProduct.swift:34`). Phases: `PhaseMap.results[].verdict/phaseIndex` (`Core/Crystal/PhaseVectorMatching.swift:332-397`). Unsupervised groups: `DiffractionEmbedding.Result.groupOf` (`Core/Analysis/DiffractionEmbedding.swift:87-140`). ROI: `VirtualDetector.realSpaceRegion` (`Core/Analysis/VirtualDetector.swift:108`). Matrix reference: `.matrix` verdict pixels. Output: composition columns in `PrecipitateObjectReport.Row`/`ClassSummary` (`Session/PrecipitateObjectReport.swift:35-86`) and its CSV. | All pixel indices are on the 4D view grid, so registration∘view is needed. Report counts with Poisson confidence intervals and label results as "apparent" because thin precipitates are seen through the matrix. Low risk, and fits the 0–10 counts/pixel reality. |
| **B. Arbitrate** | `PhaseVectorResult.score/runnerUpScore/runnerUpPhaseIndex/phaseContrast` (`PhaseVectorMatching.swift:332-362`). | Only the top two are kept. Arbitrating among more needs per-phase best scores kept per position. Changes phase-mapping numbers, so Gate D. |
| **A. Prune** | `classify(... candidateEntryIndices:)` (`PhaseVectorMatching.swift:910-916`) inside `map` (:1515). | Needs a per-position or per-object candidate mask. Gate D. |
| **C. Candidates → index → classify** | Pooled spectrum per object → candidate `PhaseMappingSlot`s (`Session/PhaseMappingProduct.swift:35-60`) → re-run the matcher. | Expected composition per phase comes from `CrystalModel.crystal` `AtomSite(z, occupancy)` (`Core/Crystal/Crystal.swift:37-48`). That also lets the app compute when two candidates are EDX-indistinguishable (Li, Z=3: T1 vs θ′) and refuse to arbitrate by name. |
| **D. Joint clustering** | Concatenate `Result.coordinates` (positions × k, :93-95) with EDX PCA scores, then `DiffractionEmbedding.kMeans` (:810). EDX PCA via `symmetricEigenTop` (:745). | Poisson-weighted PCA is HyperSpy's `decomposition`, not exspy's, so the pin needs HyperSpy too. |
| **ACOM** | `OrientationResult.score/secondScore/phaseID/reliability` (`Core/Analysis/OrientationResult.swift:576-603`). | ACOM runs against one crystal model, so it only gives per-grain pooling (and grain segmentation does not exist yet, ROADMAP theme 4). Phase mapping is the multi-phase hook. |
| **Registration** | Virtual ADF/HAADF via `VirtualDetector.tiledImage` (:322) against the spectrum file's companion HAADF; `MatrixDFTCorrelation.refinedPeak` (`Core/Compute/MatrixDFTCorrelation.swift:25-31`) with `FFT2D` gives translation. | Scale and rotation come from metadata (pixel sizes, Velox ScanTransformation). Contrast differs between a virtual ADF and a true HAADF detector, so a manual fallback and a recorded residual are needed. |
| **F / G** | New Core code, no precedent. | Separate pre-registration and a dataset with truth. Badged unvalidated (CLAUDE.md). |

## 4. Parity and gate plumbing for an eXSpy pin
1. **`tools/lib/fetch-exspy.sh`**, a sibling of `fetch-py4dstem.sh`, pins exspy plus HyperSpy and RosettaSciIO commits into `References/`.
   - Candidate exspy commit: `7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e` (2026-10-02) [sibling clone; I read its `git log`].
   - exspy depends on `hyperspy>=2.4.0`, `rosettasciio>=0.14.0`, pint, pooch and dask (its `pyproject.toml`).
   - `EDSModel` subclasses HyperSpy's `Model1D` (`exspy/models/edsmodel.py:28,97`), so model-fit parity is a tolerance, not bit-identity.
2. **`tools/lib/exspy-constraints.txt`**, frozen from a working env. A sibling venv (Python 3.14.7) ran exspy's EDS tests: 238 passed [sibling: `pytest-eds.log`].
   - EELS GOS files download via pooch from Zenodo [sibling: `pip-install.log`], so the gate must stay EDS-only and work offline.
   - The owner's conda has no exspy env (`~/miniconda3/envs`: py4dstem, thronsen, …).
3. **Python resolver.** `tools/lib/python.sh:5-30` hard-codes the py4dstem env. Add an exspy resolver (`EXSPY_PYTHON`, `envs/exspy`, `.venv-exspy`) that checks `import exspy, hyperspy, rsciio`.
4. **Harness template:** `tools/edx-parity-test/`, shaped like `tools/embedding-pca-parity/run.sh`: Swift `main.swift` from a new `spectra` manifest group (`tools/lib/sources.manifest:102+`; the readers group is :127-137), then `verify_exspy.py`, with a negative-control list.
   - **Fixtures:** `exspy/data/EDS_SEM_TM002.hspy` (31,008 B, 1024 channels, offset −0.1 keV, scale 0.01 keV) and `EDS_TEM_FePt_nanoparticles.hspy` (28,680 B, 992 channels, offset 0.169315, scale 0.020028 keV). Both are 1D spectra, not SIs [verified]. SI parity needs a synthetic SI.
   - **Pins** from the brief (Fe_Ka 3710 / Pt_La 15872; 2754/15090 with background windows) against the exspy entry points:
     - `get_FWHM_at_Energy` (`exspy/utils/eds/_xray_lines.py:138`);
     - `get_lines_intensity` (`signals/_eds.py:549`, `models/edsmodel.py:853`);
     - Cliff-Lorimer (`utils/eds/_quantification.py:36`), zeta (:159), cross-section (:229);
     - TEM quantification with iterative absorption (`signals/_eds_tem.py:297,418-518`);
     - `fit_background` (`edsmodel.py:341`), `calibrate_energy_axis` (:612), `take_off_angle` (`utils/eds/_geometry.py:24`).
   - All exspy paths are in the sibling clone.
5. **`tools/run-tests.sh`:**
   - add harnesses to `scientific` (:114-137);
   - call `fetch-exspy.sh` in the `scientific)`/`all)` lanes (:449-450);
   - classify owner-data probes as `diagnostic` (:150-159);
   - add an inventory check "unvalidated EDX stays labelled", like :204-215.
6. **CI:** a second pinned pip install in the scientific job (`.github/workflows/ci.yml:109-146`).
7. **NOTICE:** add a HyperSpy / eXSpy / RosettaSciIO section beside py4DSTEM (`NOTICE:17-38`). exspy files say GPL-3.0-or-later (`_quantification.py` header).
   - The provenance of the data tables (`exspy/material/xray_lines.json`, 77,870 B; the FFAST mass-absorption table `_misc/eds/ffast_mac.py`) is **unverified** and must be established before porting.
   - Keep fixtures fetched, not tracked (the 1 MiB guard, `tools/large-files.allow`).
8. **DEVIATION convention** extended to cite exspy file:line (an ADR 006 analogue).

## 5. AppState growth risk and where state should live
- **Measured at HEAD** (inventory definition): `AppState.swift` 1536 lines and 134 type-scope declarations; `Support/ResultExport.swift` 1698. `docs/architecture.md:195` still says 1603, which is stale.
- **Other large files:** `AppState+Open.swift` 1542 and `BraggVectorEMDWriter.swift` 3157.
- **Homes:**
  - New `let` owners on `AppState`: `SpectrumSession`, `SpectralMapsProduct`, `JointAnalysisProduct`.
  - Orchestration in `App/AppState+Spectroscopy.swift`.
  - Only an epoch hook in `AppState+Open.swift`.
  - Exports in a new `Support/SpectrumExport.swift`: per-object CSV, and EMSA/MSA for pooled spectra [format support is an unverified recollection].
  - The sidecar group writer in a new `Core/Data/SpectroscopySidecar.swift`, reusing the package-visible `HDF5WriteLibrary` (`BraggVectorEMDWriter.swift:3049`).
- **Optional placement-only prep** (no Gate D trigger): move the room switch tables (`AppState.swift:1207-1299`) into `App/AppState+Workspace.swift` before adding the seventh room.
- **The biggest growth risk is plain-EDX windows** (spectrum image without a 4D cube), which the brief puts in scope. `hasDataset` = `is4D` (:1169, 29 uses in 13 files), `DatasetSession.fourD` and the always-two-panes content branch would need a primary-signal split. That is a separate owner decision.

## 6. Effort estimate by work package (sessions = one gated lane with refuter and docs)

| Work package | Content | Sessions | Gate | Blockers |
|---|---|---|---|---|
| 0 | Reopen ADR, room mock, data-model sheet, pin ADR | 2–3 | Owner | Freeze; empty Unverified row |
| 1 | Discovery refusals (§1e), derivation read-back | 1–2 | B | Can be done in v4.x polish |
| 2 | Core types, array, sparse index, residency sibling, manifest and pbxproj entries | 2–3 | B | — |
| 3 | Readers: hspy 1; GMS DM SI 2; Velox stream 3; bcf deferred (2–3) | 6 (+2–3) | B | A real GMS 4D+EDX file |
| 4 | Registration record, composition, identity/metadata/correlation/manual, footprint resampling, refusals | 2–3 | B + pre-registration | Synthetic truth fixture |
| 5 | Sidecar group, schema 8, lineage kinds, fingerprint, back-compat tests | 2 | B | — |
| 6 | exspy pin plumbing | 1–2 | — | — |
| 7 | EDS port: line DB, FWHM, windows; Cliff-Lorimer + absorption; model fit; maps with Poisson uncertainty; zeta/cross-section | 6–9 | B + parity | Data-table provenance |
| 8 | Room UI and drive | 3–4 | Drive | Mock accepted |
| 9 | Pooling (E) | 2 | B | — |
| 10 | B / A / C, then D | 3–5, then 2 | D | Truth dataset |
| 11 | F / G | 6–10+ | D | No precedent |
| 12 | Validation datasets, owner drives | 2–3 | — | Owner time |

**Rough total:** the minimum-viable set (packages 0–9, without the DM SI and `.bcf` readers) is about 24–34 sessions; B/A/C/D adds about 5–7; F/G adds 6–10 or more. At three parallel lanes (`ROADMAP.md:109`) that is roughly 10–14 slots [estimate].

**Main risks**
- **Data.** The sibling scan of the owner's files shows GMS STEM SI files with ADF survey plus "Diffraction SI" only, and a separate Velox Talos F200X EDX (`CA_DA_170330_EDX.emd`, 7.4 GB) for a sample label that matches `4DSTEM_170330` [sibling]. A true single-scan 4D+EDX file may not exist yet, so cross-instrument registration may come first [inference].
- **Counts and physics.** At 0–10 counts per pixel, per-pixel quantification needs pooling. Li is undetectable, and thin precipitates are projected through the matrix. Ship the quantity with confidence intervals rather than a threshold (CLAUDE.md).
- **Mechanics.** Frozen-shell edits are forced by exhaustive switches. Reader memory on an 8 GB Mac and contention on the single HDF5 lock.
- **Compatibility.** Older-build traps: the unknown-storage fallback and the replay refusal of unknown kinds.
- **Parity and data rights.** Parity is a tolerance because the model rides on HyperSpy's fitting. The provenance of exspy's data tables is not yet established.