# Repository review 2026-09-09 — deduplicated register

The run as it stopped: **259 records** in `REVIEWINTERIM.md` — 174 defect claims on a
CRITICAL/HIGH/MEDIUM/LOW scale (passes 1 and 3) and 85 engineering-judgment records on a
separate SIGNIFICANT/STRUCTURAL/MODERATE/MINOR/INFO scale (pass 2). The three passes shared
scope, so the same defect was reported up to six times: the gitignored Core ML model spec
appears five times as CRITICAL and once more as a HIGH about the test that skips on it.

This file is the 174 defect claims folded into **156 clusters**, one disposition each.

**Nothing here is verified.** The adversarial pass was still in flight when the run stopped,
so every row except the ones marked *fixed* is a claim with a file and a line, not a defect.
Verify before acting, and Gate D applies to any of them that can move a scientific number.

Evidence and failure scenarios stay in `REVIEWINTERIM.md`; the lines column gives each
record's heading there. Machine-readable: `register.json`.

## Dispositions

| Disposition | Clusters | Meaning |
|---|---|---|
| fixed 2026-09-09 | 11 | fixed, each with a gate and a negative control, in this session |
| partly fixed 2026-09-09 | 0 | a first repair landed; the rest of the cluster is still open |
| repeat of … | 16 | already dispositioned on 2026-08-31. Use that ID; do not review it again |
| possible repeat of … | 8 | overlaps an August finding; someone must decide if it is the same defect |
| tracked in open-items | 8 | the record itself cites an existing `docs/open-items.md` entry |
| new | 113 | in neither the August review nor open-items |

The 16 repeats and 8 possible repeats are the measurable cost of running the passes without
an exclusion list: agents re-derived findings this repo had already dispositioned in August.

## Clusters

| ID | Sev | × | Subject | Primary file | Lines | Disposition |
|---|---|---|---|---|---|---|
| D001 | CRITICAL | 6 | The shipped learned detector's model spec is gitignored: every fresh clone gets a broken .mlpackage, a different provenance hash, and a red unit gate | `.gitignore` | 16, 32, 40, 48, 56, 312 | fixed 2026-09-09 |
| D002 | CRITICAL | 1 | Ptychography scan positions ignore the calibrated R–Q rotation and transpose | `mac4DSTEM/Core/Analysis/PtychographyPreparation.swift` | 1470 | new |
| D003 | CRITICAL | 1 | H5Reader's three attribute readers read the whole attribute into a fixed-size scalar buffer — a multi-element HDF5 attribute overruns it | `mac4DSTEM/Core/Data/H5Reader.swift` | 24 | new |
| D004 | HIGH | 2 | Learned detector: the edge-exclusion rule is applied to each 256 px model window, so on detectors > 256 px there are blind bands at every window seam where no window will accept a peak | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 64, 344 | new |
| D005 | HIGH | 2 | The parallax aberration fit silently ignores the app's own calibrated detector transpose; the code path that would apply it is unreachable | `mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift` | 232, 1771 | repeat of `core-analysis-physics-02` (2026-08-31) |
| D006 | HIGH | 2 | A multi-`data_` CIF is silently merged into one crystal: cell parameters from the last block, atom sites and symmetry operations concatenated from all of them | `mac4DSTEM/Core/Crystal/CIFImport.swift` | 144, 1561 | possible repeat of `core-crystal-02` — check |
| D007 | HIGH | 2 | The CI `inventory` job cannot pass: on a shallow checkout `HEAD^` does not resolve, so the C5 heavy-file check reports the whole 7 509 lines as growth | `tools/run-tests.sh` | 248, 328 | fixed 2026-09-09 |
| D008 | HIGH | 1 | The shipped detector's public record claims 20 000 training steps; the retained training log shows the 90-minute cap fired at step 6 500 | `Models/DiskDetector/disk-detector-heatmap-256.json` | 320 | new |
| D009 | HIGH | 1 | NOTICE claims the bundled HDF5/libaec licence texts ship inside the app; they are absent from the released v2.5.1 artefact and from the repo entirely | `NOTICE` | 120 | fixed 2026-09-09 |
| D010 | HIGH | 1 | The triage's own port recipe for DiffractionEmbedding omits its build prerequisite, which exists only on the branch | `docs/archive/v3/c8-triage-2026-09-08.md` | 272 | new |
| D011 | HIGH | 1 | The C8 decision to strand the four pure engines rests on a claim the branch's own files and gate rows contradict | `docs/decisions.md` | 264 | new |
| D012 | HIGH | 1 | The accessibility open item's reason for dropping `.accessibilityLabel()` is contradicted by its own data — the one in-body control that reports a label is the one that restates it | `docs/open-items.md` | 96 | tracked in open-items |
| D013 | HIGH | 1 | The accessibility crash — the one finding status.md names as able to block v3.0.0 — rests on two crash reports that do not exist on this machine | `docs/open-items.md` | 128 | new |
| D014 | HIGH | 1 | Three prebuilt Homebrew dylibs are committed and shipped with no recorded provenance, version, hash or rebuild path — and no automated gate ever inspects them | `mac4DSTEM.xcodeproj/project.pbxproj` | 304 | fixed 2026-09-09 |
| D015 | HIGH | 1 | A file- or sidecar-supplied probe radius permanently freezes `minPeakSpacing`: the later measured radius is never adopted, because the "user has not chosen one" guard cannot tell an app-seeded value from a user edit | `mac4DSTEM/App/AppState.swift` | 72 | new |
| D016 | HIGH | 1 | A replayed DPC step reports `.published` while publishing nothing — the promote run's summary attests to a result that was never produced | `mac4DSTEM/App/AppState.swift` | 1540 | new |
| D017 | HIGH | 1 | `publishProduct` takes the product's pixel size from the CURRENT analysis mode, so the scan-domain detector-disagreement map is published and exported with the Bragg map's reciprocal Å⁻¹/px | `mac4DSTEM/App/AppState.swift` | 1547 | possible repeat of `core-data-02` — check |
| D018 | HIGH | 1 | Disk-detection staleness signature and recipe omit the probe kernel's identity, so a Bragg map made with a different kernel is reported as current | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 152 | new |
| D019 | HIGH | 1 | A single non-finite pixel in a diffraction pattern silently returns zero peaks for that whole pattern | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 1491 | new |
| D020 | HIGH | 1 | Hexagonal IPF colour key labels ⟨10-1̄0⟩ and ⟨11-2̄0⟩ the wrong way round — green and blue are swapped against the crystallography | `mac4DSTEM/Core/Analysis/OrientationResult.swift` | 136 | new |
| D021 | HIGH | 1 | Float32 running sum saturates: whole-stack mean collapses on ordinary-sized datasets | `mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift` | 1568 | new |
| D022 | HIGH | 1 | `RotationCalibration` — the R/Q rotation AND transpose solver — has zero gated coverage; its only non-app caller is a diagnostic harness that never runs in any gate | `mac4DSTEM/Core/Analysis/RotationCalibration.swift` | 280 | repeat of `tools-gates-05` (2026-08-31) |
| D023 | HIGH | 1 | Empty scan positions inject Float.greatestFiniteMagnitude into the clustering-scale median | `mac4DSTEM/Core/Analysis/StrainMapping.swift` | 1512 | new |
| D024 | HIGH | 1 | Every full-cube VirtualDetector pass runs on the main actor: AppState never wraps them in Task.detached, and `nonisolated async` inherits the caller's actor under this project's settings | `mac4DSTEM/Core/Analysis/VirtualDetector.swift` | 184 | new |
| D025 | HIGH | 1 | Selected-area diffraction circle mask is half a pixel off-centre from the ROI drawn on screen | `mac4DSTEM/Core/Analysis/VirtualDetector.swift` | 1533 | new |
| D026 | HIGH | 1 | Matrix-DFT upsampling assigns the wrong Fourier frequency to one bin on every odd-length axis, biasing every parallax subpixel shift on odd-sized grids | `mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift` | 224 | repeat of `core-compute-shaders-01` (2026-08-31) |
| D027 | HIGH | 1 | CIF importer applies whatever symmetry-operation list the file happens to contain, with no completeness or consistency check | `mac4DSTEM/Core/Crystal/CIFImport.swift` | 1554 | new |
| D028 | HIGH | 1 | ACOM CPU matching silently returns an unmatched or partially unmatched orientation map when a per-worker matcher cannot be built — no failure flag, unlike its DiskDetection twin | `mac4DSTEM/Core/Crystal/OrientationMatcher.swift` | 192 | new |
| D029 | HIGH | 1 | BraggVectorEMDWriter.readStringAttribute assumes every string attribute is variable-length; a fixed-length one is read as a pointer and then free()d | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 168 | repeat of `core-data-01` (2026-08-31) |
| D030 | HIGH | 1 | Exported dim vectors pair a defaulted step of 1 with a real physical unit, manufacturing a calibration that was never measured | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1498 | new |
| D031 | HIGH | 1 | A session save silently publishes a stripped sidecar when the existing file cannot be opened, destroying BraggVectors, saved results, the replay record and the labels | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1505 | new |
| D032 | HIGH | 1 | `hasEllipse` admits a non-positive semi-axis, so a degenerate ellipse is applied to every Bragg vector while readiness reports "No detector-distortion correction" | `mac4DSTEM/Core/Data/Calibration.swift` | 1526 | new |
| D033 | HIGH | 1 | DM4 parsing has unguarded trapping Int conversions and an unbounded field loop — a corrupt or desynchronised tag tree kills or hangs the process | `mac4DSTEM/Core/Data/DM4Reader.swift` | 176 | new |
| D034 | HIGH | 1 | DM4 tag parser converts file-supplied UInt64/Double counts to Int without validating them: a malformed .dm4 traps or hangs | `mac4DSTEM/Core/Data/DM4Reader.swift` | 1477 | repeat of `core-data-06` (2026-08-31) |
| D035 | HIGH | 1 | Scan-fastest DM4 reads the detector pair in the opposite order from the detector-fastest branch, and the only test covering it is circular | `mac4DSTEM/Core/Data/DM4Reader.swift` | 1484 | possible repeat of `core-data-07` — check |
| D036 | HIGH | 1 | The unit gate's end-to-end fixture and every gated `probeSize` fixture are square and centre-symmetric, so an rx/ry or qx/qy swap is undetectable | `mac4DSTEM/Core/Data/DemoFourDDataSource.swift` | 296 | new |
| D037 | HIGH | 1 | A detector smaller than 256 px whose beam is off-centre is silently truncated by the learned frame — part of the detector is never searched | `mac4DSTEM/Core/ML/LearnedDiskDetector.swift` | 200 | new |
| D038 | HIGH | 1 | A learned-inference failure on the live overlay is silently answered with CLASSICAL rings while the picker still says Neural net | `mac4DSTEM/Core/ML/LearnedDiskDetector.swift` | 208 | new |
| D039 | HIGH | 1 | The tracked >256-px probe-anchor item understates it: nothing gates, warns, or flags a run on a detector larger than 256 px | `mac4DSTEM/Core/ML/LearnedDiskDetector.swift` | 216 | tracked in open-items |
| D040 | HIGH | 1 | Hand-clicked disk-centre labels are written with `frame: "native"` but are captured in the loaded view's frame, so labels clicked on a cropped or binned view name the wrong detector pixels and scan positions | `mac4DSTEM/Session/DiskCentreLabels.swift` | 160 | possible repeat of `support-export-08` — check |
| D041 | HIGH | 1 | CBED PNG export burns a guessed "1/nm" scale-bar label when the file gave a Q pixel size with no units | `mac4DSTEM/Support/ResultExport.swift` | 1519 | repeat of `support-export-04` (2026-08-31) |
| D042 | HIGH | 1 | Candidate views for the AX stack overflow, ranked — the three `.contain` containers that wrap an NSViewRepresentable, and the two labels applied to non-elements | `mac4DSTEM/UI/ImagePanes.swift` | 104 | tracked in open-items |
| D043 | HIGH | 1 | ApertureOverlay's accessibility representation builds a Slider whose ClosedRange can be inverted, trapping the process | `mac4DSTEM/UI/PaneOverlays.swift` | 88 | new |
| D044 | HIGH | 1 | Pan clamp is still the dead Metal shader's rule, so a zoomed pane can only pan 1/zoom of the way to the image edge | `mac4DSTEM/UI/ZoomPan.swift` | 80 | new |
| D045 | HIGH | 1 | A DPC unit test turns a total DPC failure into a skip, on the always-available in-memory demo fixture | `mac4DSTEMTests/SessionCalibrationTranslationTests.swift` | 288 | new |
| D046 | HIGH | 1 | The ACOM Metal-vs-CPU parity gate compares in-plane angles modulo π, so a 180° divergence in the user-selectable "Metal GPU" backend passes while printing "Metal choices exact" | `tools/acom-matching-test/main.swift` | 240 | possible repeat of `core-crystal-03` — check |
| D047 | HIGH | 1 | `run-tests.sh inventory` exits 1 on the current clean tree — tripped by status.md's own "Nothing is uncommitted" sentence — while status.md's gate table claims exit 0 | `tools/run-tests.sh` | 112 | fixed 2026-09-09 |
| D048 | HIGH | 1 | The "AppState never net positive" rule measures two file paths, so AppState growth in any additional `extension AppState` file is invisible — and 630 such lines already exist on ml/disk-detector | `tools/run-tests.sh` | 256 | new |
| D049 | HIGH | 1 | `strain-frame-test` generates its golden from whichever py4DSTEM is installed (0.14.17 here) while asserting source-locks against the 0.14.19 pin; its own error text claims a PYTHONPATH that run.sh never sets | `tools/strain-frame-test/run.sh` | 336 | new |
| D050 | MEDIUM | 2 | The AGPL yolov8n weights are still distributed by the public repository — reachable from `main` — while NOTICE says no third-party weights are distributed | `NOTICE` | 480, 608 | tracked in open-items |
| D051 | MEDIUM | 2 | Most of the retained logs and screenshot sets status.md cites as its evidence no longer exist; one row's "screenshots retained in scratchpad/c4c-drive/" is demonstrably false | `docs/status.md` | 376, 616 | fixed 2026-09-09 |
| D052 | MEDIUM | 2 | `ProbeKernel.synthetic` and the trench in `ProbeKernel.measured` use `y < py/2` for the wrapped (fftfreq) coordinate, where the flat route and NumPy use `(py+1)/2` — one row and one column carry the wrong radius on odd-sized detectors | `mac4DSTEM/Core/Analysis/ProbeKernel.swift` | 352, 1799 | new |
| D053 | MEDIUM | 2 | BraggVectorEMDWriter's scalar dataset readers use H5S_ALL into a single stack value with no dataspace check | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 440, 1610 | repeat of `core-data-01` (2026-08-31) |
| D054 | MEDIUM | 2 | Disk-centre labels written by a branch build are silently erased by any main build, and vice versa — the two designs use different sidecar attribute names | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 576, 1617 | new |
| D055 | MEDIUM | 2 | There is no HDF5 serialisation anywhere, and H5Reader.deinit closes the file off the actor's executor — an entry point the tracked crash item does not name | `mac4DSTEM/Core/Data/H5Reader.swift` | 448, 712 | tracked in open-items |
| D056 | MEDIUM | 2 | The CoM kernels clamp negative intensities to zero — an undocumented py4DSTEM deviation that moves every DPC/iDPC and origin number on background-subtracted data | `mac4DSTEM/Shaders/CenterOfMass.metal` | 504, 528 | repeat of `core-compute-shaders-02` (2026-08-31) |
| D057 | MEDIUM | 1 | `ml/disk-detector` is 26 commits BEHIND main as well as 27 ahead; its `tools/` tree would resurrect three harnesses main deleted and a 105-line-stale `sources.manifest` | `(none)` | 648 | new |
| D058 | MEDIUM | 1 | `.github/workflows/ci.yml`'s own description of the inventory job states the opposite of what the script now does — a reader triaging the red job is told size cannot be the cause | `.github/workflows/ci.yml` | 536 | fixed 2026-09-09 |
| D059 | MEDIUM | 1 | CONTRIBUTING.md tells public contributors every Core/ change needs a parity fixture; CLAUDE.md explicitly says the opposite, and recent Core/ sessions followed CLAUDE.md | `CONTRIBUTING.md` | 384 | new |
| D060 | MEDIUM | 1 | `Package.swift`'s header says the app target still compiles Core/ and Session/ directly; the project file says it does not, and the 78-path exception list that makes that true is hand-maintained and ungated | `Package.swift` | 544 | new |
| D061 | MEDIUM | 1 | Consolidation gate C3 is marked CLOSED but its stated exit criterion fails again on the current status.md, so `/pickup` with no target would re-take a closed gate | `docs/consolidation-plan.md` | 392 | new |
| D062 | MEDIUM | 1 | The crash reports that are the sole evidence for the repo's top open item are not on this machine | `docs/open-items.md` | 368 | new |
| D063 | MEDIUM | 1 | The tracked entry "Two diagnostic harnesses gate nothing" is wrong: nine harnesses gate nothing, and one of them is the sole non-app exerciser of a science port | `docs/open-items.md` | 600 | tracked in open-items |
| D064 | MEDIUM | 1 | arm64-only HDF5 with no ARCHS pin: the prescribed Archive release path can produce an x86_64 slice that launches and then fails on every data file | `mac4DSTEM.xcodeproj/project.pbxproj` | 624 | fixed 2026-09-09 |
| D065 | MEDIUM | 1 | A promote-and-replay from a detector-cropped or binned rehearsal refuses its own strain/ACOM steps: the executor writes re-referenced disk parameters, the staleness check compares them against the un-re-referenced recipe | `mac4DSTEM/App/AppState.swift` | 1722 | new |
| D066 | MEDIUM | 1 | iDPC integration and the Bragg-vector-map histogram run on the MainActor, the same shape as the P1 freeze this repo already diagnosed one layer up | `mac4DSTEM/App/AppState.swift` | 1729 | new |
| D067 | MEDIUM | 1 | CIF import runs the whole parse, symmetry expansion and O(n²) family verification synchronously on the main actor, with no cancellation | `mac4DSTEM/App/AppState.swift` | 1736 | new |
| D068 | MEDIUM | 1 | No staleness signature carries any calibration value, so a re-fitted origin (or a rotation/Q edit) never marks a displayed map stale — the C4(b) plan required exactly this | `mac4DSTEM/App/ProductWorkflow.swift` | 432 | tracked in open-items |
| D069 | MEDIUM | 1 | A signature that cannot be built is reported as "not stale", the same verdict as "matches on every key" | `mac4DSTEM/App/ProductWorkflow.swift` | 1659 | new |
| D070 | MEDIUM | 1 | DPC colour-wheel traps (hard crash) on a single non-finite centre-of-mass value | `mac4DSTEM/Core/Analysis/DPC.swift` | 1715 | new |
| D071 | MEDIUM | 1 | Learned-detector runs record min_absolute_intensity, subpixel and upsample_factor in provenance although refine() applies none of them | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 1596 | new |
| D072 | MEDIUM | 1 | Parabolic subpixel refinement runs in Float32 where py4DSTEM explicitly upcasts to float64, with no DEVIATION note | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 1603 | new |
| D073 | MEDIUM | 1 | fit1D reports didNotConverge when the seed is already at (or reaches) the optimum | `mac4DSTEM/Core/Analysis/EllipseCalibration.swift` | 1631 | new |
| D074 | MEDIUM | 1 | Ellipse calibration cannot be cancelled; the cancellation token only discards the finished result | `mac4DSTEM/Core/Analysis/EllipseCalibration.swift` | 1645 | new |
| D075 | MEDIUM | 1 | normalizedResidual carries two incommensurable definitions in one field, gated by near-identical thresholds | `mac4DSTEM/Core/Analysis/EllipseCalibration.swift` | 1652 | new |
| D076 | MEDIUM | 1 | Higher-order aberration gradients are sampled at a different angular origin than py4DSTEM | `mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift` | 1757 | repeat of `core-analysis-physics-06` (2026-08-31) |
| D077 | MEDIUM | 1 | Default alignment schedule drops py4DSTEM's repeat pass at the smallest bin | `mac4DSTEM/Core/Analysis/ParallaxAlignment.swift` | 1764 | new |
| D078 | MEDIUM | 1 | Alignment working-memory guard counts three stacks; six are live | `mac4DSTEM/Core/Analysis/ParallaxAlignment.swift` | 1778 | new |
| D079 | MEDIUM | 1 | Parallax and ptychography use the raw aperture centre as the diffraction origin, bypassing `Calibration.referenceOrigin` — the one derivation the type says every caller must use | `mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift` | 408 | new |
| D080 | MEDIUM | 1 | Parallax and ptychography refuse to run without an R–Q rotation calibration that neither pipeline ever reads | `mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift` | 496 | possible repeat of `core-analysis-physics-02` — check |
| D081 | MEDIUM | 1 | `docs/q-calibration-design.md` documents a probe-radius shell check as the replacement guard, but `KnownCrystalQCalibration.estimate` takes `probeRadiusPixels` and never reads it | `mac4DSTEM/Core/Analysis/QCalibration.swift` | 400 | repeat of `core-analysis-detect-02` (2026-08-31) |
| D082 | MEDIUM | 1 | probeRadiusPixels is a required argument that no code reads, while its doc comment claims it gates a check | `mac4DSTEM/Core/Analysis/QCalibration.swift` | 1638 | repeat of `core-analysis-detect-02` (2026-08-31) |
| D083 | MEDIUM | 1 | `StrainMapping.compute` scores a manual basis over a different observation population than an automatic one (`minRadius: 0` vs the default 2), so the exported `basis_support_fraction` means two different things | `mac4DSTEM/Core/Analysis/StrainMapping.swift` | 360 | new |
| D084 | MEDIUM | 1 | `MetalEngine`'s six compute pipelines are unsynchronized `lazy var`s on a nonisolated process-wide singleton | `mac4DSTEM/Core/Compute/MetalEngine.swift` | 464 | new |
| D085 | MEDIUM | 1 | The azimuthal blur width is a plan-generation parameter but a hard-coded literal in the matcher, so template and experimental images can be built with different kernels | `mac4DSTEM/Core/Crystal/OrientationMatcher.swift` | 1743 | new |
| D086 | MEDIUM | 1 | Polar deposition converts a radius to an Int bin index with no finiteness or magnitude guard — a runtime trap on a bad Q calibration | `mac4DSTEM/Core/Crystal/OrientationPlan.swift` | 1750 | new |
| D087 | MEDIUM | 1 | writeCalibration silently discards per-position origin maps that fail its validity test, while the export path refuses on the same condition | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1624 | new |
| D088 | MEDIUM | 1 | Re-referencing wipes `originProvenance` to `.geometricDefault` while a valid recorded mean origin survives and silently becomes the reference origin | `mac4DSTEM/Core/Data/CalibrationReReference.swift` | 1708 | new |
| D089 | MEDIUM | 1 | DM4 scan shape and voltage are chosen by unscoped substring match over a Dictionary, so which tag wins varies between runs | `mac4DSTEM/Core/Data/DM4Reader.swift` | 1589 | repeat of `core-data-07` (2026-08-31) |
| D090 | MEDIUM | 1 | The demo fixture is square on every axis and declares a symmetric origin, so nothing built on it can catch a scan- or detector-axis transposition | `mac4DSTEM/Core/Data/DemoFourDDataSource.swift` | 1687 | new |
| D091 | MEDIUM | 1 | Synthetic demo calibration is stamped .importedFile, so fabricated numbers are labelled as read from a file | `mac4DSTEM/Core/Data/DemoFourDDataSource.swift` | 1694 | new |
| D092 | MEDIUM | 1 | Log-scale contrast turns non-finite pixels into a real intensity of 0, breaking the file's own "no data stays distinguishable" invariant | `mac4DSTEM/Core/Data/DiffractionPattern.swift` | 1666 | repeat of `core-data-09` (2026-08-31) |
| D093 | MEDIUM | 1 | The whole resident-cube path in FourDArray/ResidentCube is unreachable in the shipping app — no caller ever requests .resident | `mac4DSTEM/Core/Data/FourDArray.swift` | 1673 | new |
| D094 | MEDIUM | 1 | The diffraction-pattern LRU is bounded by pattern COUNT, not bytes, and nothing in the app ever clears it | `mac4DSTEM/Core/Data/FourDArray.swift` | 1680 | new |
| D095 | MEDIUM | 1 | H5Reader.readProbe materialises the entire probe dataset from file-declared dims, then discards all but slice 0 | `mac4DSTEM/Core/Data/H5Reader.swift` | 1575 | new |
| D096 | MEDIUM | 1 | Rehydrated upsample_factor from a sidecar has no upper bound and reaches an Int(Double) conversion that traps | `mac4DSTEM/Core/Data/ResultPresentation.swift` | 1701 | new |
| D097 | MEDIUM | 1 | EMPAD and MIB whole-cube reads open, seek, read and close a fresh FileHandle for every single diffraction pattern | `mac4DSTEM/Core/Data/VendorRawReaders.swift` | 1582 | new |
| D098 | MEDIUM | 1 | `to_counts` is applied to the cropped window in Swift and to the whole native pattern in Python — an unmarked deviation that gives each >256-px window its own dose scale | `mac4DSTEM/Core/ML/LearnedDiskDetector.swift` | 472 | new |
| D099 | MEDIUM | 1 | Strain staleness ignores the manual g-vector basis, which is an input to the computation | `mac4DSTEM/Session/StrainProduct.swift` | 424 | new |
| D100 | MEDIUM | 1 | The GPU threadgroup argmax and the CPU argmax break ties in different directions, contradicting the shader's own "identical to the reference path" claim | `mac4DSTEM/Shaders/ACOMMatching.metal` | 520 | new |
| D101 | MEDIUM | 1 | The app's CoM component order is transposed relative to py4DSTEM, so the R–Q rotation it reports and exports is the negative of py4DSTEM's — and of its own parallax-fitted rotation | `mac4DSTEM/Shaders/CenterOfMass.metal` | 512 | possible repeat of `core-analysis-physics-06` — check |
| D102 | MEDIUM | 1 | Exported figures burn a scale bar with a fabricated unit when the calibration carries a size but no units — the on-screen bar was fixed for this case, the exported one was not | `mac4DSTEM/Support/ResultExport.swift` | 416 | repeat of `support-export-04` (2026-08-31) |
| D103 | MEDIUM | 1 | The main-thread regression guard exists only for the learned detector; the classical full-scan path — the shipped default and the one that actually froze the app — has none, and the build cannot catch a lost `nonisolated` | `mac4DSTEMTests/LearnedDiskDetectionScanTests.swift` | 456 | new |
| D104 | MEDIUM | 1 | The learned parity gate skips rather than fails on any Core ML load error, and falls back to the repo copy of the asset so a bundle-packaging regression is invisible | `mac4DSTEMTests/LearnedDiskDetectorTests.swift` | 488 | new |
| D105 | MEDIUM | 1 | Every learned-detector parity test silently XCTSkips when the asset cannot load, because the guard tests only that the .mlpackage DIRECTORY exists | `mac4DSTEMTests/LearnedDiskDetectorTests.swift` | 568 | new |
| D106 | MEDIUM | 1 | The frozen hand-labelled test set that is the sole evidence for the shipped 0.7 threshold exists only in a `/private/tmp` worktree | `tools/disk-detector/overnight-256.sh` | 640 | new |
| D107 | MEDIUM | 1 | The py4DSTEM source lock is verified by HEAD only — a dirty or de-gitted `References/py4DSTEM-dev` is accepted as "lock present" | `tools/lib/fetch-py4dstem.sh` | 584 | new |
| D108 | MEDIUM | 1 | `fetch-py4dstem.sh` verifies nothing once the checkout exists: no content check without `.git`, and no check at all when HEAD already equals the lock | `tools/lib/fetch-py4dstem.sh` | 632 | new |
| D109 | MEDIUM | 1 | The inventory's "AppState stored properties" metric counts function-local `let`/`var` and computed properties — it reports 491 where the type declares ~123, and status.md quotes the number as evidence of progress | `tools/run-tests.sh` | 552 | fixed 2026-09-09 |
| D110 | MEDIUM | 1 | Merging ml/disk-detector today red-lines main's own inventory gate, and taking the branch's tools/run-tests.sh would silently delete three of its checks | `tools/run-tests.sh` | 560 | new |
| D111 | MEDIUM | 1 | The C5 AppState/ResultExport growth gate is blind whenever HEAD is a docs-only commit, which is this repo's normal closeout shape | `tools/run-tests.sh` | 592 | new |
| D112 | LOW | 2 | Three stale pointers in live docs: an owed push that already happened, a line reference three lines off, and a file path from before the Session/ split | `docs/status.md` | 664, 768 | fixed 2026-09-09 |
| D113 | LOW | 2 | `LearnedDiskDetector.heatmaps` reads the Core ML output as densely packed and never checks its strides or channel count | `mac4DSTEM/Core/ML/LearnedDiskDetector.swift` | 704, 720 | new |
| D114 | LOW | 1 | docs/releasing.md claims the embedded libraries are "free of Homebrew paths"; libhdf5.dylib carries a compiled-in /opt/homebrew plugin search path that the audit does not look for | `docs/releasing.md` | 784 | fixed 2026-09-09 |
| D115 | LOW | 1 | The shaders are compiled with -fmetal-math-mode=fast, which voids the NaN reasoning written into OriginMeasure.metal and the NaN robustness OriginCalibration claims for the statistics it consumes | `mac4DSTEM.xcodeproj/project.pbxproj` | 728 | new |
| D116 | LOW | 1 | ActivityLog's two drop rules are textual heuristics that can silently discard a real event | `mac4DSTEM/App/ActivityLog.swift` | 1890 | new |
| D117 | LOW | 1 | `AppState.sessionInventory` carries an orphaned doc comment describing a property that was deleted, contradicting the comment directly below it | `mac4DSTEM/App/AppState.swift` | 760 | new |
| D118 | LOW | 1 | productWorkflowReadiness probes the app bundle on the filesystem every time a view body reads it | `mac4DSTEM/App/AppState.swift` | 1904 | new |
| D119 | LOW | 1 | `calibrateEllipse` still hand-rolls the origin fallback that the v2 S13 comment says was eliminated, and centres the fit annulus on the aperture unconditionally | `mac4DSTEM/App/AppState.swift` | 1960 | repeat of `app-appstate-05` (2026-08-31) |
| D120 | LOW | 1 | `publishRestoredProduct` is the one publish site that does not bump `resultVersion`, and every display cache is keyed on it | `mac4DSTEM/App/AppState.swift` | 1967 | new |
| D121 | LOW | 1 | `applyDPCDisplay` returns nil for two different facts — "the display was published" and "this did not run" | `mac4DSTEM/App/AppState.swift` | 1974 | new |
| D122 | LOW | 1 | Colormaps.lutRGBA traps (not returns garbage) for count <= 1 | `mac4DSTEM/App/Colormaps.swift` | 1883 | new |
| D123 | LOW | 1 | PendingLoad owns a security-scoped URL and a live read Task but has no deinit; release depends entirely on two AppState call sites | `mac4DSTEM/App/PendingLoad.swift` | 1897 | new |
| D124 | LOW | 1 | Quantitative iDPC forces a square scan step even when the two scan axes are sampled differently | `mac4DSTEM/Core/Analysis/DPC.swift` | 1953 | new |
| D125 | LOW | 1 | The sampled-preview label the file's own invariant I4 calls load-bearing prints "every 32th position" | `mac4DSTEM/Core/Analysis/DatasetPreview.swift` | 1806 | new |
| D126 | LOW | 1 | DatasetPreview.make reports two non-allocation failures as FourDError.allocationFailed | `mac4DSTEM/Core/Analysis/DatasetPreview.swift` | 1813 | new |
| D127 | LOW | 1 | Full-scan progress fractions can be delivered out of order, and the tile coalescer admits the regression | `mac4DSTEM/Core/Analysis/DiskDetection.swift` | 1820 | new |
| D128 | LOW | 1 | fit2D and fitOrigin(included:) index by width*height without checking the array actually has that many elements | `mac4DSTEM/Core/Analysis/OriginCalibration.swift` | 1855 | new |
| D129 | LOW | 1 | OriginCalibration.run is dead in the app and duplicates tiledRun's calibration logic | `mac4DSTEM/Core/Analysis/OriginCalibration.swift` | 1869 | new |
| D130 | LOW | 1 | Q high-pass envelope is applied although py4DSTEM's aberration_correct ignores it | `mac4DSTEM/Core/Analysis/ParallaxAberrationCorrection.swift` | 1995 | new |
| D131 | LOW | 1 | ProbeKernel.measured traps on a non-finite origin where its sibling .flat returns nil | `mac4DSTEM/Core/Analysis/ProbeKernel.swift` | 1827 | new |
| D132 | LOW | 1 | RotationCalibration.solve reads 2*width*height floats from com without checking its length | `mac4DSTEM/Core/Analysis/RotationCalibration.swift` | 1862 | new |
| D133 | LOW | 1 | Analytic aperture kernel and the mask path disagree on the exact-centre detector pixel when inner radius is 0 | `mac4DSTEM/Core/Analysis/VirtualDetector.swift` | 1946 | new |
| D134 | LOW | 1 | Blocking whole-cube compute and the on-screen MTKView renders share one MTLCommandQueue, so a long dispatch serialises ahead of the display command buffers | `mac4DSTEM/Core/Compute/MetalEngine.swift` | 736 | new |
| D135 | LOW | 1 | The CIF importer's family-classification tolerance is 1000× looser than the model validation it feeds, so a band of cells is rejected with a generic message that hides the real reason | `mac4DSTEM/Core/Crystal/CIFImport.swift` | 1981 | new |
| D136 | LOW | 1 | A singular metric tensor silently yields latInv = latReal — a reciprocal lattice in Å instead of Å⁻¹, with no error | `mac4DSTEM/Core/Crystal/Crystal.swift` | 1988 | new |
| D137 | LOW | 1 | ACOM's radial coordinate is the projected radius on a continuous kMax/nRadial axis where py4DSTEM uses discrete \|g\| shells — a second un-DEVIATION-noted port difference in the same function | `mac4DSTEM/Core/Crystal/OrientationPlan.swift` | 672 | repeat of `core-crystal-05` (2026-08-31) |
| D138 | LOW | 1 | Restoring an RGBA result map computes width*height*4 after a guard that only bounds width*height | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 688 | new |
| D139 | LOW | 1 | Preserved results are re-keyed by kind, so two saved results whose kind attribute is missing collapse into one and the second is dropped without a word | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1834 | new |
| D140 | LOW | 1 | An orphaned result_* node is copied as an opaque 'external object' and then collides with a new result of the same kind, wedging every future save | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1841 | new |
| D141 | LOW | 1 | Result and calibration array sizes are taken from the file with no upper bound, so a damaged sidecar traps on allocation instead of erroring | `mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift` | 1848 | new |
| D142 | LOW | 1 | `originFitIsSane` passes vacuously when no probe radius is set, and the reciprocal-metrology gate does not require one | `mac4DSTEM/Core/Data/Calibration.swift` | 1939 | new |
| D143 | LOW | 1 | `CalibrationInvalidation.Field.probeRadius` and `.ellipse` are never produced, so two session-restore guards can never fire | `mac4DSTEM/Core/Data/CalibrationReReference.swift` | 1925 | new |
| D144 | LOW | 1 | DM4Error.unsupportedDataType is never thrown; an unsupported pixel type is reported to the user as "no datacube found" | `mac4DSTEM/Core/Data/DM4Reader.swift` | 1785 | new |
| D145 | LOW | 1 | FourDArray.scanTile validates only the tile's element count and row range, not its declared scan/detector extents | `mac4DSTEM/Core/Data/FourDArray.swift` | 1911 | new |
| D146 | LOW | 1 | H5 EMD dim-vector calibration infers pixel size from the first two samples only, with no uniformity check and a silent drop for descending axes | `mac4DSTEM/Core/Data/H5Reader.swift` | 1792 | new |
| D147 | LOW | 1 | A sidecar with no recorded ptychography method is rehydrated as gradient-descent and reported as an applied setting | `mac4DSTEM/Core/Data/ResultPresentation.swift` | 1918 | new |
| D148 | LOW | 1 | cancelCurrent() cannot distinguish "already cancelling" from "nothing was running", and the controller keeps reporting a live operation after cancel | `mac4DSTEM/Core/Workflow/AnalysisOperationController.swift` | 1876 | new |
| D149 | LOW | 1 | `LearnedDetectionSession.prepare` has a check-then-await gap that can load and compile the Core ML model twice | `mac4DSTEM/Session/LearnedDetection.swift` | 696 | new |
| D150 | LOW | 1 | A session with no recorded origin makes `apply` invent an aperture centre in the wrong frame and can emit a false "beam is not inside this diffraction crop" refusal | `mac4DSTEM/Session/SessionCalibrationFramePolicy.swift` | 1932 | new |
| D151 | LOW | 1 | The Bragg-peak CSV export carries no units, no calibration and no frame, so a CSV from a cropped or binned view is indistinguishable from a full-extent one | `mac4DSTEM/Support/ResultExport.swift` | 680 | possible repeat of `support-export-08` — check |
| D152 | LOW | 1 | Region-radius Slider forms an inverted range on a scan whose larger axis is a single pixel | `mac4DSTEM/UI/ImagingSettings.swift` | 656 | new |
| D153 | LOW | 1 | A full-pattern log10 transform runs on the main thread inside a SwiftUI view body, for a histogram that is inside a DisclosureGroup collapsed by default | `mac4DSTEM/UI/WorkspaceInspector.swift` | 752 | new |
| D154 | LOW | 1 | TB1StallProbeTests is inert everywhere: every test in the file skips on a hard-coded absolute path inside the owner's home directory | `mac4DSTEMTests/TB1StallProbeTests.swift` | 776 | new |
| D155 | LOW | 1 | `tools/lib/python.sh`'s last-resort fallback accepts a `python3` with numpy but no scipy, contradicting the candidate loop it comments | `tools/lib/python.sh` | 792 | new |
| D156 | LOW | 1 | A Metal parameter struct governed by the byte-identity hard rule is duplicated in a tools/ harness, outside the one file the rule names | `tools/origin-fit-diagnostics/coarse-cost.swift` | 744 | tracked in open-items |

## The 85 engineering-judgment records (pass 2)

Not folded in. They are opinions about design and debt on their own severity scale, not
defect claims; merging two scales would invent a severity nobody assigned. They stay in
`REVIEWINTERIM.md` under `## Pass 2`, as input to `docs/v3-plan.md`.
