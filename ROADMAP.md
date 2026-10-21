# mac4DSTEM roadmap

Rewritten 2026-10-21 after the kit switches. The app owns SwiftUI, app logic, provenance and the study workflow, built on five
released kits (exact pins in `Package.swift`). What is live: `docs/status.md`. Every defect and debt: `docs/open-items.md`
(this file points to it, it does not repeat it). Cross-repo direction: `../ROADMAP.md`.

## What the app owns, and what the kits own

| Owner | Holds |
|---|---|
| **App** (`mac4DSTEM/`) | rooms and SwiftUI, `AppState`, Metal image view and the Metal kernel the kits lack (selected-area sum), lineage/replay/marks, session sidecar writes, calibration orchestration, precipitates, Materials Project fetch glue, 4D x spectroscopy correlation |
| **CuboKit 0.7.1** | virtual imaging, CoM and origins (`OriginFit`, Friedel, beamstop), probe size, disk detection (`CuboBragg`), strain (`CuboStrain`), DPC/iDPC (`CuboPhase`), parallax aberration/depth/position correction, ptychography probe, PCA/k-means, hot-pixel mask, calibration re-reference |
| **DiffractoKit 0.8.1** | cells, CIF, symmetry, structure factors, ring and ellipse fit, vector matching and phase mapping, Euler/orientation symmetry, ACOM library and matcher, Materials Project decode |
| **FormatoKit 0.8.0** | HDF5 reader and libhdf5 frameworks, sidecar reads and the peak-grid EMD read, DM4/DM3 (not the 4D gather), MIB, EMPAD, Velox EMD |
| **SpectroKit 0.7.1** | EDX fit, quantification, proposer and Auto ID, spectrum image, mask transport and pools |
| **ImagoKit 0.5.0** | `FFT2D`, `FFT1D` (ACOM) |

Kept in the app on purpose: the learned detector (training and refine, ADR 071), session lineage and marks records, the `small_datacube` rank-3 reshape in `DM4Reader`, header-less MIB, and thin Float façades over the kits. The kit asks that end
them are in `docs/open-items.md` "Kit asks"; the owner tags kit releases and the app re-pins once per kit minor.

## Study items mac4DSTEM must deliver (`../ROADMAP.md`)

The acceptance target is the owner's correlative TEM study (unpublished: keep its text and data out of this public repo).
1. **Number density N_V with thickness** on the owner's microprobe Al-Mg-Si cube; thickness typed +- sigma until SpectroKit EELS t/lambda.
2. **Talk-quality figures:** apertures drawn on the exported mean pattern, the EDX region box in exported maps, multi-panel layout,
   high-DPI or vector output.
3. **beta'' (monoclinic) orientation maps:** the symmetry is DiffractoKit's; the app needs the map, IPF and export path; then re-measure the needles.
4. **Validation of what the talk shows:** phase and orientation mapping against pyxem, a beta'' truth set, the Euler frame rotation versus py4DSTEM.
5. Smaller: numeric aperture entry or snap to a reflection; the mean pattern without Prepare first; drift-corrected EDX sums (SpectroKit/FormatoKit).

## Open app work, in order (details: `docs/open-items.md` "App work")

1. Notarisation (archive verified 2026-10-20) and the Hardened Runtime load (the release proof for the framework signing).
2. Number density v2: a new registration (study item 1).
3. Phase mapping object bar and the matrix verdict (with the DiffractoKit ask); stays badged unvalidated.
4. Known-crystal Q ring assignment (design pass); origin-fit gate and seed holes; rotation-calibration tests.
5. Lineage, replay and sidecar identity residuals; room-switch defects; the Compute Strain crash hunt.
6. Spectroscopy room drive and the HDF5/DM4 robustness items.
7. Test-run traps, harness gaps, D12 tolerance conversion; then accessibility, Swift 6 (owner's schedule) and the parked refactors.

## Features frozen until reopened

The v4.1 plateau holds: sessions finish or remove, they do not add, apart from the study items above. Parked: amorphous and
nanocrystalline modes, strain where disk detection fails, grain segmentation, detector realism, direct ptychography, live acquisition.

## Task list: kit adoption (drafted 2026-10-21 for the kit tags of that day)

Each line is one Remote Control session on the Mac. Read this repo's `CLAUDE.md` and the line, work against the sibling kit
checkouts (`../CuboKit` etc.), restore exact tag pins at closeout, tests green, a CHANGELOG line if a user sees it, one commit
on `main` with the hand-off. The numerics stay in the kits: a task that finds a number to change files a kit ask in
`docs/open-items.md` instead. Study items (above) decide the order; "study" below means on that path.

Tags: CuboKit 0.8.0, DiffractoKit 0.9.0, FormatoKit 0.9.0, ImagoKit 0.6.0, SpectroKit 0.8.0 (SimulatoKit 0.3.0 has no
consumer here; see the end).

0. **Re-pin to the 2026-10-21 tags** (running; not repeated here). Its fallout lands there: the `CIFImportError` case
   (`.incompleteSymmetryOperationsForSymbol`) in exhaustive switches, and `sameScanAs4DCube` to `sameScanAsCube` (12 uses).
1. **Notarisation and the Hardened Runtime load** (existing App work 1; needs Paul's Apple ID, so Paul is present).
2. **Adopt DiffractoKit 0.9: mirror plane, in-plane refinement, matrix evidence** (study 3 and 4). Goal: the beta'' map is
   right where the 128-bin in-plane step was wrong and the mirror flag was dropped. First target: publish
   `OrientationMapAnalysis.mirroredPlane` beside `acom_in_plane` (or take `patternInPlaneAnglePlane`, which already removes a
   mirrored match's added half turn), then a "refine in-plane angle" switch on the ACOM scan that sets
   `ACOMMatcher(library:refinesInPlaneAngle:)` (default off, the kit's default; CPU scan only, say so beside the switch if the
   Metal path is chosen). Wire `PhaseVectorSettings.minimumMatrixEvidence` as a hidden setting at 0. Out of scope: turning
   either opt-in on by default and the beta'' re-measure (both wait for Paul's one labelled scan; phase mapping stays badged
   unvalidated). Done when: a planted off-grid self-recovery test shows the mirrored plane exported with the map and the
   refined run closer than the unrefined one on the same 200 patterns (the kit's 35 to 14 failures at 1.4 degrees is the
   reference number, `DiffractoKit/docs/open-items.md`), `ACOMKitCallSiteTests` and `PhaseMapAppTests` green, the sidecar
   carries the new plane.
3. **Adopt CuboKit 0.8: Metal selected-area (done 2026-10-21) and the resident cube (open)** (the last app/kit separation item, the kit ask at the top
   of "Kit asks, CuboKit"). Goal: delete the app's compute copy. First target: `VirtualDiffraction.pattern(..., path: .metal)`
   replaces `MetalEngine.virtualDiffraction` and `Shaders/VirtualDiffraction.metal`; check the result against the previous
   app output at 1e-5 before deleting. Second: the kit's `ResidentCube` replaces the app's `ResidentCube`/`FourDArray`
   residency for the Metal reducers (virtual image, mean and max, centre of mass), guarded by `ResidentCube.fits` with the
   existing tiled path as the fallback for larger cubes. Out of scope: `PendingLoad` and `VirtualDetector.tiledDiffraction`
   (load-screen state and tiling policy stay, per the kit's Migration), an automatic "hold the cube when it is read twice"
   policy beyond holding it for the session, centre of mass on Metal (slower than CPU in the kit, stays CPU). Done when: the
   LEFTOVER rows for `PendingLoad`, `VirtualDetector`, `FourDArray`, `ResidentCube` and `VirtualDiffraction.metal` leave
   `tools/kit-boundary.allow` or shrink to what is left, `MetalEngineDispatchTests` and the residency tests are rewritten
   against the kit type, the unit gate is green. Mark any interim `delete at CuboKit <version>`. Split in two sessions if
   the first target alone fills one.
4. **Adopt SpectroKit 0.8: the public quantification API** (study 1, number density with thickness). Goal: no `@testable`
   or `package` reach into SpectroKit and the quantification maps come from one call. First target: move
   `QuantifyPresentation` and `SpectroscopyRoomController` to `EDXQuantification.quantify` / `.quantifyMaps`
   (Cliff-Lorimer with `TypedK`, zeta, cross-section, each with or without the absorption iteration; weight and atomic percent
   maps, mass thickness, atoms) and drop the `PooledQuantificationInput` reach (SpectroKit open item 6). Keep `validation:
   "none"` visible on every result. Out of scope: any EELS thickness (the t/lambda route is SpectroKit's and the owner types
   thickness until then), an EDS fit-accuracy fix (needs Paul's pure-Al standard). Done when: the Velox L4 and golden
   tests (`SpectroscopyVeloxL4Tests`, `SpectroGoldenTests`) pass unchanged against the kit call, one new test pins a
   `quantifyMaps` map against the previous per-pixel path, and the badge test still finds the key.
5. **Adopt CuboKit 0.8: the calibration model and cube edits** (study; the calibration is read in every number). Goal: one
   calibration value, the kit's. First target: replace the app's calibration struct with `Calibration` where they overlap
   (pixel sizes and units, origin per position or one number, ellipse, Q-R rotation and flip), taking the calibrated grids
   from `qxx`/`rxx` and friends. Then `CubeEditing` for binning, thinning, padding and resampling (`binScan`, `thinScan`,
   `padDetector`, `resampleDetector`). Careful, from the kit's open items: binning or resampling the detector changes the pixel
   sizes but not the origin, so the app rescales a stored origin itself. Out of scope: `CalibrationMeasurement` in the Q
   calibration UI (the app's known-crystal path stays), the session sidecar format (an old sidecar must still replay).
   Done when: a binned/cropped cube gives the same virtual image and calibrated axes as before (existing fixtures, no pin
   moved), an old sidecar replays, `delete at CuboKit` markers for the replaced helpers are gone. Slower kit paths (bin_R 4.6x
   slower than NumPy, `CuboKit/docs/open-items.md` 3) are not the app's to fix.
6. **Adopt FormatoKit 0.9: the sniffing loader and Velox single spectra.** Goal: Open routes by content, and a spectrum
   file opens in the Spectroscopy room. First target: `FormatoLoader.sniff(path:)` replaces the extension switch in the open
   path (EMPAD, MIB and HDF5 4D files still go to their dedicated readers, the kit throws `useDedicatedReader`); "DevelopersKit"
   Velox files now open through `VeloxEMDReader.isVeloxFile`. Then `VeloxSpectrumSignals` for a single spectrum (energy axis
   in keV, `EDS_TEM`, beam energy, live and real time where the file has them), and `MSAReader`/`MSAWriter` to read and
   write `.msa` spectra from the Spectroscopy room. Out of scope: GMS EDS geometry and Velox spectrum-image live and real
   times (the kit needs Paul's files first), the app-owned `DM4Reader` 3D-to-4D reshape and header-less MIB (still kept on
   purpose). Done when: a planted `.msa` round-trips through the room's export, a DevelopersKit fixture opens, and the
   sniff-routing has a test for each format family including the dedicated-reader refusal.
7. **ImagoKit 0.6: nothing to adopt.** A search of the app (2026-10-21) finds no filter, window or shift of its own that the
   kit now covers (the Butterworth in `ParallaxAberrationCorrection` is CuboParallax's option); the FFT-room features are
   macTEM's. Revisit when the Image or FFT room is added here.
8. **CuboKit 0.8 Bragg masking** (`BraggMasking.mask`, `localAverage`, `latticeMask`: py4DSTEM's `get_braggmask`,
   `get_local_ave_dp`, `make_bragg_mask`). Unused today and not on a study path; only if a talk figure wants the
   Bragg-masked local average. Parked until asked.

Public kit API with no consumer in this app yet (a name search over the app and its tests, 2026-10-21, approximate: it counts
public types, so new members of a used type are not counted):

| Kit | Public types | Unused here | Study-path unused |
|---|---|---|---|
| CuboKit | 196 | 82 (CuboCore 20, CuboVirtual 11, CuboParallax 11, CuboPtycho 13, CuboStrain 11, CuboBragg 8, CuboEmbedding 3, CuboPhase 5) | `Calibration`/`CubeEditing`/`ResidentCube` (tasks 3, 5); `StrainReference`, `LatticeFit` diagnostics; the mixed-state and multislice ptychography engines are not study |
| DiffractoKit | 132 | 30 (mostly `ConventionalCell`, `ReducedCell`, `SymmetryOperation` and CIF issue types, `PhaseModelLibrary`, `IPFColorKey`) | `mirroredPlane`, `refinesInPlaneAngle`, `minimumMatrixEvidence` (task 2) |
| FormatoKit | 13 | 2 (`LinkKind`, `WalkEntry`); new in 0.9: `FormatoLoader`, `VeloxSpectrumSignals`, `MSAReader`, `MSAWriter` | `FormatoLoader`, Velox spectra (task 6) |
| ImagoKit | 17 | 5 (`FFT2DTransform`, `LabelImage`, `ObjectMoments`, `SegmentationError`, `TidyResultsError`); new in 0.6: `FFTSurface`, filters, `PeakLocalMax`, masked registration | none for this app (macTEM's FFT room); task 7 |
| SpectroKit | 22 | 3 (`MaskTransportError`, `TypedK`, `AbsorptionStatus`); `EDXQuantification` not called yet | `EDXQuantification.quantifyMaps` (task 4) |
| SimulatoKit | 45 | 38 (the app uses none of it) | none; see below |

SimulatoKit 0.3.0: no adoption task. The app's parked list has "detector realism" and the study has no simulation panel. It
becomes a task when a simulated cube is wanted next to a measured one (probe, `STEM.scan`, `CenterOfMassDetector`,
`ScanMeasurement.poissonNoise` give a 4D cube); the kit is ready, the app would only need a room and a writer to the
cube format.

Kit gaps this app needs that no kit task covers yet (candidates for the suite ROADMAP): the radial background of
a pattern (`get_radial_bkgrnd`, `get_radial_bksb_dp`, the `radial_bksb` option of `get_local_ave_dp`) needs a polar data
cube that neither CuboKit (assumes DiffractoKit's) nor DiffractoKit (lists elliptical resampling as "not planned, CuboKit's")
owns, so decide the owner; the ellipse fit that feeds `Calibration.ellipse` (`fit_ellipse_1D`, `fit_ellipse_amorphous_ring`,
`constrain_degenerate_ellipse`); `resample_Q(method="fourier")`; a faster CPU mean pattern (8x slower than NumPy, CuboKit
open item 1) and `binScan` (4.6x); the strain asks (`LatticeStrain.fitRobust` above 1e10, cancel and progress on
`StrainMapping.compute`); a vDSP-backed shifter for padded parallax sizes (about 2x slower than the Float path it replaced);
EELS thickness for study 1 (SpectroKit EELS model fit, deconvolution and zero-loss alignment are missing; t/lambda exists).
