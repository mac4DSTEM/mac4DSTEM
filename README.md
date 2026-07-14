# mac4DSTEM

A native **macOS Swift / SwiftUI / Metal** application for analyzing **4D-STEM** datasets.

The frozen v1 workflow, stable/advanced feature tiers, and acceptance gates are
defined in [`docs/v1-scope.md`](docs/v1-scope.md).

The goal is feature parity with [py4DSTEM](https://github.com/py4dstem/py4DSTEM) — reused here as the reference implementation — rebuilt on Apple-Silicon-native compute (Metal, and later MLX) for interactive, real-time analysis on lab Macs, with additional features over time.

Algorithms are ported from py4DSTEM and validated against it; deviations are documented inline in the source with a `DEVIATION` note and the reason.

---

## Current state

The app is being built by **migrating features in small, buildable slices** from `References/MigrationSource/` (read-only reference code). Each slice ends green (`⌘B`) and is verified before the next begins.

### Working now

**Data & display (Slice 1)**
- Open HDF5 (`.h5` / `.hdf5` / `.emd`) 4D-STEM files. The datacube is auto-discovered across common py4DSTEM / Gatan (`dm_dataset_root`) / HyperSpy path layouts; a manual dataset-path override is available.
- Open Gatan DM3/DM4 datacubes directly, including dimension and pixel-size metadata where present.
- HDF5 is loaded at runtime via `dlopen`/`dlsym` (no link-time dependency) — see [HDF5 notes](#hdf5).
- Live CBED (diffraction) viewer, GPU-rendered through a Metal display pipeline with colormap LUTs (Viridis / Inferno / Gray / RdBu) and optional log scaling.
- Scan-position scrubbing (X/Y sliders), dataset inspector with shape/dtype/chunking/voltage metadata.

**Virtual detector imaging (Slice 2)**
- Whole-cube virtual-detector imaging on the GPU: bright-field / ADF / HAADF presets plus a draggable annular aperture (analytic fast path) and rectangle / point detectors (general mask kernel).
- Two-pane layout: diffraction on the left, real-space virtual image on the right. Click the real-space image to select a scan position; the diffraction pane follows.

**Calibration (Slice 3)**
- **Origin calibration** (py4DSTEM `get_probe_size` → `get_origin` → `fit_origin`): estimates the probe radius from the max diffraction pattern, measures the unscattered-beam position per scan point on the GPU, and fits a smooth origin map (constant / plane / parabola). Reports probe radius and fit RMS residual.
- The Calibration panel shows whether the aperture center is a geometric default, a py4DSTEM file-provided mean, a fit performed in the app, or a manual override.
- py4DSTEM EMD calibration bundles can provide full fitted `qx0`/`qy0` origin maps (and optional measured maps). They are validated against the scan shape, converted once from py4DSTEM detector-axis order, and used directly by DPC/rotation workflows without rerunning origin calibration.
- The stable session companion round-trips pixel calibration, origin means/maps, rotation/transpose, probe radius, and ellipse metadata. Compatible saved calibration is applied before the initial analysis and identified explicitly as session-derived in the UI.
- **R–Q rotation calibration**: solves for the scan↔detector rotation (and detector transpose) by minimizing the curl of the center-of-mass field. Runs origin calibration first if needed.
- **Diffraction statistics**: max and mean patterns over the whole cube, selectable as CBED display modes.

**DPC / iDPC (Slice 4)**
- Center-of-mass differential phase contrast with four views off one cached CoM field: **magnitude**, **angle**, an **HSV color wheel** (hue = deflection direction, brightness = magnitude, with an on-image legend), and **iDPC** via Fourier integration of the vector field. The calibrated R–Q rotation is applied so the field is in the scan frame.
- iDPC becomes quantitative projected phase in radians only when fitted origin maps, R–Q rotation, real-space sampling, and reciprocal sampling are all available. It applies the calibrated `2π·Q` CoM-to-phase-gradient scale on the anisotropic physical frequency grid. Otherwise it remains explicitly qualitative. Both paths use exact-shape FFTs with a documented centered 2× zero-padded boundary and deterministic zero-mean phase gauge.

**Bragg disk detection (Slice 5)**
- Synthetic probe-kernel generation (logistic disk minus a sine² sigmoid trench, zero-sum), hybrid cross-correlation (`corrPower`), maxima finding with the intensity/spacing/edge/count filter cascade, and sub-pixel refinement (parabolic or DFT-upsampled `multicorr`). Live per-pattern overlay while scrubbing, plus a full-scan pass (parallelized over scan rows) producing a Bragg vector map.
- Detected full-scan peaks export to a companion py4DSTEM 0.14 / EMD 1.0 `BraggVectors` `.h5`. The export carries Q/R pixel calibration and `QR_flip`, converts detector axes at the format boundary, and atomically publishes a sidecar without modifying the source dataset.
- Scalar results (virtual detector, scalar DPC, strain, ACOM, parallax, and ptychography maps) accumulate in a stable `<source>.mac4dstem.h5` session sidecar as named py4DSTEM-readable `RealSlice` nodes with per-map sampling and provenance. Reopening restores the recorded current map, and the inspector inventories shape, storage, units, sampling, and concise provenance for every saved map plus BraggVectors; atomic whole-file replacement preserves the other supported results.

**Strain mapping**
- Strain from detected Bragg vectors (py4DSTEM `process/strain`): a bounded consensus fit selects a well-conditioned reciprocal basis across the peak population, gates off-lattice peaks, robustly fits each local lattice, rejects distorted reference positions, and computes **εxx, εyy, εxy**, and **rotation θ** against a component-median reference lattice. Users can instead supply g₁/g₂ and can choose a point, rectangle, or circle as the unstrained reference. The inspector exposes basis support/RMS/condition, indexed fraction/local RMS, and reference inliers; weak or ill-conditioned solutions are rejected rather than published.

**ACOM — crystal orientation mapping**
- A `Crystal` model (lattice/metric + kinematic structure factors, Lobato scattering factors) with FCC/BCC/diamond presets and named materials, verified against known selection rules.
- Orientation matching via a simplified **polar-correlation** route (the same principle as py4DSTEM's `crystal_ACOM`, without the spherical-harmonic machinery): sample zone axes, project each crystal's excited reflections to a polar (radial × azimuthal) template, and match each pattern's Bragg peaks against the library — recovering the zone axis and in-plane angle in one shot via azimuthal FFT correlation, with an EBSD-style reliability. Cubic results use all 24 proper rotations and an orix-aligned [001]/[101]/[111] IPF-Z key. The magnesium preset exercises non-cubic support with the 12 proper rotations of 6/mmm, a deterministic [0001]/[10-10]/[11-20] sector, and an explicitly native dependency-free IPF key. Both report py4DSTEM-compatible Bunge φ₁/Φ/φ₂ plus a symmetry-FZ angle map.
- *Limitations (v1):* needs a Q-pixel-size scale to map detector pixels → Å⁻¹ (exposed as a slider; qualitative without it); high-symmetry zone axes remain ambiguity-prone and should be judged by reliability; validated point-group presentation currently covers cubic crystals plus HCP magnesium, rather than arbitrary space groups.

### Project structure

```text
mac4DSTEM/                       # Xcode project root (git repo)
  mac4DSTEM/                     # app sources (file-system-synchronized — see below)
    App/                         # entry point + AppState (single source of truth)
    Core/
      Data/                      # H5Reader + BraggVectorEMDWriter, FourDArray,
                                 #   DatasetDescriptor, DiffractionPattern, Calibration
      Compute/                   # MetalEngine, MTLTexture+Float
      Analysis/                  # VirtualDetector, OriginCalibration,
                                 #   RotationCalibration, OrientationResult
    Shaders/                     # .metal kernels (display, virtual detector,
                                 #   DP statistics, origin measure, center of mass)
    UI/                          # ContentView, Diffraction/StemImageView,
                                 #   MetalImageView, ApertureControl, Colormaps, …
    Support/                     # bridging header
  mac4DSTEMTests/                # fast XCTest production contracts
  tools/                         # cross-language goldens, interoperability,
                                 # packaging, aggregate runner, benchmarks
  References/                    # read-only, git-ignored
    MigrationSource/             # prior codebase; port features FROM here
    py4DSTEM-dev/                # algorithm reference
    training_dataset/            # sample .h5 files
  libhdf5.dylib, libaec.0.dylib, libsz.2.dylib   # bundled HDF5 closure
```

The Xcode project uses **synchronized folder groups** (`objectVersion 90`): files placed under `mac4DSTEM/` are added to the target automatically — no manual "target membership" step, and `.metal` files auto-route to the Metal compile phase.

---

## Requirements

- macOS with **Xcode 16 / Xcode 26** (the project uses synchronized folders and the Metal toolchain component).
- No separately installed HDF5 is required; the dependency closure is embedded.

## Build & run

1. Open `mac4DSTEM.xcodeproj` in Xcode.
2. Select the `mac4DSTEM` scheme.
3. Build and run (`⌘R`). Open a `.h5` dataset (e.g. from `References/training_dataset/`).

**Command-line builds** (optional) require pointing at the full Xcode toolchain, since `xcode-select` may target CommandLineTools:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM \
  -destination 'platform=macOS' build
```

The non-gating performance harness runs optimized production CPU and Metal
paths and emits schema-v2 JSON with warm-up/repeat samples, medians, workload
dimensions, checksums, allocation estimates, and observed resident memory:

```sh
tools/performance-baseline/run.sh > before.json
# After an implementation change, on the same machine and power mode:
tools/performance-baseline/run.sh > after.json
tools/performance-baseline/compare.py before.json after.json
```

`MAC4DSTEM_BENCHMARK_REPEATS` and `MAC4DSTEM_BENCHMARK_WARMUPS` control run
length. Wall-clock results are trend evidence, not CI pass thresholds.

---

## <a name="hdf5"></a>HDF5 notes

`H5Reader` and the atomic BraggVectors/RealSlice session writer have **no link-time HDF5 dependency**. They `dlopen` `libhdf5.dylib` and bind every function via `dlsym`. They search, in order:

1. `MAC4DSTEM_HDF5_PATH` when a standalone source harness explicitly supplies it,
2. the app bundle's `Contents/Frameworks/`, then
3. dyld's bare-name lookup for standalone harnesses.

The target embeds and signs all three dylibs, enables Hardened Runtime and App
Sandbox, and grants user-selected read/write plus app-scoped bookmark access.
The first session-sidecar save presents a Save panel and remembers that explicit
grant for later atomic saves/reopen. `tools/package-test/run.sh` performs a clean
Release audit and bundle-only HDF5 smoke test. Developer ID signing and Apple
notarization still require release-owner credentials; see
[`docs/distribution.md`](docs/distribution.md).

---

## Roadmap

Migration slices, in order:

1. ✅ **Metal display** — file I/O, CBED rendering, scan scrubbing.
2. ✅ **Virtual detector** — BF/ADF/HAADF, draggable aperture, real-space pane.
3. ✅ **Calibration** — origin + R–Q rotation, DP max/mean.
4. ✅ **DPC / iDPC** — center-of-mass magnitude/angle, HSV color-wheel vector display, Fourier iDPC integration.
5. ✅ **Disk detection** — synthetic probe kernel, hybrid cross-correlation, sub-pixel Bragg-disk detection (parabolic + `multicorr`), Bragg vector maps.

**The five migration slices plus strain mapping are complete** — the py4DSTEM core-analysis path (I/O → virtual imaging → calibration → DPC → disk detection → strain) is in place.

**Current focus:** the polished-v1 release program. Its workflow and acceptance gates are frozen in [`docs/v1-scope.md`](docs/v1-scope.md). The scientific, reader/interoperability, multi-window/UI/accessibility, checked-in real-data, and credential-free distribution gates are complete. The remaining public-release action is Developer ID signing/notarization by the credential owner; see [`docs/releasing.md`](docs/releasing.md).

**Final repository gate (2026-07-14):** eight XCTest methods, all 22 standalone harnesses, four full real-data goldens, the hardened Release audit, and the checksum-stable performance baseline pass. MIB/EMPAD are clearly labeled Preview until real vendor files are supplied; notarization and a clean-account launch test require the release owner.

Still ahead (each its own focused effort):

- ✅ **ACOM refinements** — cubic fundamental-zone templates, automatic known-crystal Q calibration, cubic result reduction, and IPF-Z coloring are complete. Disk detection also accepts a measured vacuum-ROI probe kernel.
- **Parallax / ptychography** — calibrated parallax preprocessing through alignment, aberration fitting/correction, KDE/position refinement, depth sectioning, and product browsing are complete. The CPU exact-shape, full-batch single-slice engine supports gradient descent and DM/AP with opt-in py4DSTEM transmission, pure-phase, center-of-mass, and normalized support constraints; centered object/probe phase/amplitude diagnostics reuse the retained result. A GPU batch backend remains a post-v1 optimization; [MLX Swift](https://github.com/ml-explore/mlx-swift) is a viable future implementation option once the serial operator is reshaped into batches.
- ✅ **Broader readers** — direct EMPAD XML/RAW (130×128 float32 with footer crop) and regular Merlin MIB U08/U16/U32 (1x1/2x2/2x2G with required ScanX/ScanY companion) are fixture-gated Preview readers. Ambiguous raw inputs fail with conversion/companion guidance. They need release-owner-supplied real vendor acquisitions before promotion to Stable. HDF5/EMD discovery now traverses arbitrary EMD root names after canonical fast paths; DM3/DM4 and py4DSTEM-readable result persistence remain supported.
- ✅ **Distribution packaging** — embedded HDF5 closure, Hardened Runtime, App Sandbox, persistent sidecar grants, and a clean Release audit. Developer ID notarization is credential-dependent.
- ✅ **Polished native workflow** — independent dataset windows, focused commands, bookmark-backed Recents/recovery, transactional opens, a live open→calibrate→analyze→save guide, Advanced labeling, and keyboard/VoiceOver access to image, aperture, histogram, and plot controls.

---

## Direction notes (2026-07-06 evaluation)

- **.h5 calibration**: the py4DSTEM EMD files carry a full calibration bundle
  (`<root>/metadatabundle/calibration/{Q,R}_pixel_size` + units, `QR_flip`) and
  EMD `dim0–dim3` vectors — now read automatically (see Fixed list).
- **DM4 self-calibration (partial)**: when a raw `.dm4` is opened, the app can
  fit origin/rotation and calibrate Q against a selected known crystal. The
  guided preprocess/export sheet now writes that active calibration through a
  bounded crop/Q-bin pass to canonical py4DSTEM `.h5`; ellipse measurement and
  the one-click calibration checklist are complete.
- **Large datasets, decided approach** (ladder): ① real-space crop at load,
  ② detector (Q) binning at load = binned preview, ③ native-dtype residency,
  ④ out-of-core tiled streaming for whole-cube passes, ⑤ streamed
  preprocess/export to a new calibrated `.h5` (complete), ⑥ true sparse
  (electron-counted) formats only when such data exists.
- **Speed vs py4DSTEM+CUDA (assessment)**: whole-cube ops are memory-bandwidth
  bound — we beat py4DSTEM-CPU by orders of magnitude, are competitive with
  mid-range CUDA, won't out-bandwidth a 4090; our win is end-to-end interactive
  latency (no Python, no PCIe copies). Disk detection is the exception (CPU
  FFTs) — moving correlation to the GPU is the big remaining lever.
- **Feature-revision plan**: physical DPC magnitude, measured vacuum ROI probe,
  strain reference/manual basis, cubic ACOM reduction/IPF/FZ templates,
  colorbars/gamma, scalar/RGBA sidecar round-trip, and robust automatic strain
  basis selection are complete. Plot persistence remains.

## Open issues / known limitations

- **Tiles are expanded to float32.** Peak memory is bounded independently of scan height, but native-dtype tile kernels (e.g. uint16) would reduce reader bandwidth and staging memory.
- **Testing is deliberately layered.** Eight native XCTest methods cover fast production/workflow contracts. Twenty-two standalone scientific/interoperability harnesses, four 1–1.7 GB real-data goldens with a 15-second/file budget, and the Release package audit cover py4DSTEM parity, formats, forced tiles, cancellation, and distribution. `tools/run-tests.sh all` is the aggregate gate.
- **`AppState` remains a large workflow facade.** Analysis-operation identity, timing, cancellation replacement, stale completion, and reset are now owned by `AnalysisOperationController`, but file I/O orchestration, calibration, analysis dispatch, and result publication still need incremental extraction as their campaigns touch them.
- **Metal commands cannot be interrupted after submission.** Cancel immediately invalidates their result and keeps the main actor responsive, but the current GPU command finishes in the background. CPU disk/strain/ACOM loops and plan generation stop cooperatively at row/template boundaries.
- ~~**Ellipse fitting is limited to a lightweight conic**~~ is resolved: the conic remains a deterministic initializer and safe fallback, while a bounded 11-parameter central-plus-asymmetric-Gaussian ring refinement supplies the accepted calibration when its physical and residual gates pass.
- **Session result rehydration is pixel/metadata-level.** Named scalar RealSlices and lossless RGBA Arrays plus calibration/BraggVectors restore and are selectable/removable; unrecognized external root objects survive rewrites. The app still does not create/view plot nodes or reconstruct every analysis control behind a saved result.
- **ACOM point-group coverage is deliberate rather than generic.** Cubic presets and HCP magnesium use validated deterministic reduction, fundamental-zone sampling, and IPF-Z. A future arbitrary crystal importer must supply an explicit point-group implementation instead of silently assuming cubic symmetry.
- **Virtual diffraction is an all-scan-position reduction.** Each detector pixel loops over every scan position in the selected mask, so live selected-area diffraction can become expensive for large scans and detectors.
- ~~**Shortest-pair automatic strain basis selection**~~ is resolved: automatic mode clusters repeated reciprocal vectors, scores bounded basis pairs by population consensus, rejects weak/ill-conditioned candidates and off-lattice local peaks, and reports its diagnostics. Manual g₁/g₂ and real-space reference ROIs remain available.
- **Origin coarse search deviates from py4DSTEM.** It uses a binned block-sum argmax instead of Gaussian-blur argmax for GPU efficiency; the fallback path can produce a usable-looking calibration even when py4DSTEM would signal failure.
- ~~**iDPC unit sampling and implicit power-of-two padding**~~ are resolved: calibrated CoM shifts integrate on the physical anisotropic scan grid into radians, while missing prerequisites produce an explicitly qualitative result; periodic and centered 2× zero-padded boundaries are separate tested contracts.
- **No graceful non-Metal fallback.** `MetalEngine` uses fatal initialization failures if no Metal device, command queue, or default library is available.
- ~~**HDF5 discovery is path-list based**~~ is resolved: canonical paths remain the fast path, followed by deterministic HDF5 link traversal for arbitrary EMD roots.
- **Notarization requires the release owner.** The stable bundle ID, macOS 14 floor,
  archive/notary/staple scripts, and credential-free package audit are complete,
  but the repository cannot supply a Developer ID certificate or notary profile.
- **R-Q rotation has an inherent 180° ambiguity.** The curl/divergence metric is unchanged by flipping both CoM components. If iDPC contrast comes out inverted, use the **Flip 180°** button in the Calibration section.
- Bundle identifier is `com.paullobpreis.mac4DSTEM`; changing it after release would break bookmark/container continuity.

### Fixed / completed

- Virtual-detector parity harness (`tools/virtual-detector-test/run.sh`) exercises the production mask builder and Metal kernels on a non-square synthetic cube. Annulus, circle, rectangle, point, edge and exact-boundary cases match source-locked py4DSTEM results with zero error. This exposed and fixed the annulus inner boundary (`rIn² < r² < rOut²`, both strict); BF now uses a true circle so it retains the center pixel.
- Per-position py4DSTEM origin maps are imported from real EMD calibration bundles. `H5Reader` requires paired, finite rank-2 `qx0`/`qy0` arrays matching the non-square scan shape, preserves optional measured maps only as a complete pair, and performs the py4DSTEM qx/qy → app y/x conversion in one tested helper. A fixture written by the checked-in py4DSTEM 0.14.19 validates values, means, shape order, and the mean-only fallback in `tools/calibration-test/run.sh`.
- Single-pattern disk detection has a dependency-free, source-locked parity harness (`tools/disk-detection-test/run.sh`). On a non-square 32×64 pattern it validates the synthetic sigmoid probe kernel, cross and hybrid correlation, pixel/parabolic/`multicorr` localization, detector-axis conversion, and absolute/relative/edge/spacing/count filters. It exposed and fixed refined peaks retaining their integer-pixel intensity instead of py4DSTEM's bilinear intensity.
- The live Bragg overlay now detects the pattern actually shown (current, mean, max, or virtual diffraction), and a request generation prevents older detached detections from overwriting a newer scrub/parameter result. Peak-center and circular-radius geometry is centralized and covered on a non-square detector by `tools/peak-overlay-test/run.sh`.
- ACOM matches now compose the stored detector basis with the recovered in-plane angle and convert py4DSTEM's column-oriented matrix through the same transposed extrinsic-`zxz` convention used for orix export. `tools/acom-orientation-test/run.sh` source-locks that convention and covers identity, general rotations, Φ=0/π gimbal locks, and a synthetic zone-axis/in-plane composition. Euler component maps and selected-position degrees are available in the UI.
- Cubic ACOM results now reduce over all 24 proper cubic rotations to one deterministic minimum-angle representative. The UI adds an orix-matched IPF-Z RGBA map and compact [001]/[101]/[111] key plus a persistable scalar cubic-FZ angle. The ACOM harness covers the group, full symmetry orbits, angular bounds, continuity, and five orix 0.14.2 RGB goldens.
- ACOM matching now stores every template FFT in contiguous `[template,radial,azimuthal]` arrays and uses one vDSP complex multiply per template. On the 2026-07-14 M3 checkpoint, the warmed 48-position/400-template median improved from 210.4 ms to 25.1 ms (8.4×) with identical scalar-reference template/bin/score results. An exact batched Metal spectrum/direct-IDFT backend is retained and parity-tested, but measured 32.9 ms on the same workload, so Automatic correctly selects the faster CPU path. `tools/acom-matching-test/` gates scalar/optimized/Metal choices and score/reliability tolerances; the performance baseline records plan, CPU, and Metal workloads.
- Non-cubic ACOM now includes an HCP magnesium cell and the 12 proper rotations of 6/mmm. Plan sampling, reduction, IPF-Z presentation, export provenance, and the UI key all retain the selected symmetry; changing the crystal/custom cell invalidates stale plans. The orientation harness gates the complete group, orbit invariance, sector uniqueness, and native IPF key, while the matching harness runs a non-cubic plan through the production matcher.
- The v1 vendor-reader checkpoint adds bounded, out-of-core EMPAD and Merlin MIB actors behind the same `FourDDataSource` interface as HDF5/DM4. `tools/vendor-reader-test/` generates byte-exact little-/big-endian fixtures and gates scan order, repeated MIB headers, EMPAD footer removal, and ambiguity failures. EMD discovery uses HDF5 link traversal, so valid 3D/4D `data` nodes no longer need one of six hard-coded root paths.
- Dataset windows now own independent `AppState` graphs, so multiple files can remain open without sharing readers, cancellation, calibration, or results. Command routing follows the focused window. Security-scoped recent-file bookmarks and a lightweight last-session record restore scan position/mode on request; large/transient arrays are never copied into preferences. The welcome screen exposes Open, Reopen Last, and removable Recents, while failed replacement opens preserve the current usable dataset.
- Long-running scientific operations share a thread-safe, single-operation cancellation token and expose **Cancel** in the performance inspector. Disk/strain/ACOM workers and orientation-plan generation exit at safe boundaries; GPU-backed virtual imaging, statistics, origin/rotation, and DPC discard completed work after cancellation. Dataset replacement cancels the token in addition to advancing the existing stale-result epoch. `tools/cancellation-test/run.sh` exercises cancel-before-start, mid-run production disk cancellation, normal completion, and replacement-token isolation.
- Native BraggVectors EMD export is available under **File → Export → py4DSTEM BraggVectors Sidecar…** and suggests `<source>_braggvectors.h5`. `BraggVectorEMDWriter` emits the exact EMD 1.0 custom/PointListArray hierarchy used by py4DSTEM 0.14, including variable-length compound `qx/qy/intensity` records, empty scan positions, shape metadata, and Q/R calibration. It converts app `y→qx`, `x→qy`, writes a same-directory temporary file, and atomically renames only after close and a final cancellation check. `tools/bragg-export-test/run.sh` validates source preservation, cancelled replacement safety/temp cleanup, and an exact checked-in-py4DSTEM round trip on non-square shapes.
- Scalar result session persistence is available under **File → Export → Save Current Result to Session Sidecar**. Each kind gets a deterministic direct-root `RealSlice` node; a versioned manifest records save order and the current result. Whole-file rewrites copy all other supported maps and BraggVectors at the HDF5-object level. Dataset activation restores the compatible current map and fills the inspector's read-only sidecar inventory. `tools/sidecar-result-test/run.sh` verifies two-map enumeration, deterministic restore, same-kind replacement, NaN handling, cancellation/source safety, calibrated dimensions, BraggVectors preservation, and whole-file plus direct-node py4DSTEM 0.14.19 reads.
- **Session schema v4** extends scalar results beyond the scan grid: parallax subpixel BF, corrected phase, selected depth planes, and ptychographic object phase/amplitude retain independent row/column sampling, Å units, and deterministic JSON provenance for source product, depth/factor/filter, engine/method, iteration/error, and update controls. Arbitrary scalar shapes can save, restore, and be selected; RGBA remains scan-shaped. The sidecar harness now covers all five stabilized kinds and exact native/py4DSTEM reads while preserving calibration, prior results, BraggVectors, source bytes, and opaque external nodes.
- **Save Calibration to Session Sidecar** independently publishes pixel sizes/units, origin means plus fitted/measured maps, R–Q rotation/transpose, probe radius, and ellipse metadata in py4DSTEM's native Calibration layout while preserving every supported result. Reopen applies compatible session fields before the initial analysis and labels origin provenance as session mean/maps. Calibration and sidecar harnesses validate non-square axis conversion, partial/mismatched safety, calibration-only replacement, and exact py4DSTEM reads.
- **Preprocess & Export DataCube…** streams the active HDF5/DM3/DM4 source through an optional real-space crop and count-preserving integer Q bin into a chunked float32 py4DSTEM `DataCube`. Pixel sizes, probe radius, origin maps/means, ellipse, rotation, and transpose metadata are transformed/preserved in the output frame; incomplete Q blocks trim at the bottom/right like py4DSTEM. The guided sheet previews shape/size/trimming, reports progress, supports cancellation, and atomically publishes without touching the source. `tools/preprocessing-export-test/run.sh` verifies exact one-row memory bounds and native/py4DSTEM round trips.
- Disk correlation now runs on the detector's exact Q shape. Radix-2 grids keep the fast vDSP 2-D FFT; non-radix grids use exact separable DFTs, with a correctness fallback for Accelerate-unsupported lengths. The disk harness covers wrapped-edge native correlation as well as `sigma_cc` reflect smoothing.
- Session rewrites opaque-copy root EMD objects outside mac4DSTEM's mutable manifest. The sidecar harness injects a third-party Array, replaces calibration, and proves the external node remains exact through py4DSTEM/h5py.
- **Fit Ellipse** ports py4DSTEM's intensity-weighted conic and 11-parameter amorphous-ring profile in native qx/qy convention. The physical `(a,b,theta)` parameterization keeps every profile iteration elliptical; a robust refit handles sparse noise, and an invalid/overlapping profile cannot replace a valid conic calibration. The UI reports the selected model, residual, angular coverage, asymmetric widths, or fallback reason. Session/DataCube persistence retains accepted `a/b/theta`. `tools/ellipse-calibration-test/run.sh` covers non-square rotated, near-circular, background/asymmetric, noisy, overlapping, blank, and angularly degenerate cases.
- **Calibration readiness** is derived in the preprocessing sheet for origin/probe, ellipse, R-Q rotation, Q scale, and R scale. Rows distinguish file import, session restoration, in-app measurement, manual entry, mixed sources, and missing values; launch the applicable measurement or accept manual scales; and name every omitted field in a required uncalibrated-export confirmation. Dataset activation resets provenance, cancelled operations retain prior values, and a manual aperture center now supersedes stale fitted maps at the export boundary. `tools/calibration-readiness-test/run.sh` covers the state model and the preprocessing fixture carries a ready report through an exact py4DSTEM round trip.
- **Parallax preprocessing preview** ports py4DSTEM's default BF-mask threshold, qx/qy detector ordering, reciprocal vectors, electron wavelength/probe angles, sine² edge blend, order-0 normalization, padded virtual-BF stack, and incoherent BF initialization. It requires explicit physical origin/Q/R/rotation/voltage calibration, reads the cube in two bounded tiled passes directly into `[BF,Ry,Rx]`, and retains both py4DSTEM's edge-blended alignment stack and unwindowed KDE source under one 1 GiB ceiling. Ptycho mode exposes the preview and stack/wavelength/angle/error diagnostics. `tools/parallax-preprocessing-test/run.sh` source-locks both stacks on a non-square fixture with forced one-row tiles.
- **Parallax coarse-to-fine alignment** ports py4DSTEM's default alignment-bin schedule, median-centered/radially ordered BF grouping, running reference, k-vector least-squares shift field, Fourier-shifted stack/masks, median recentering, aligned BF, and convergence error. Its shared multicorr helper matches the three-point parabolic seed, half-pixel rounding, factor-8 matrix-DFT patch, final parabolic polish, and wrapped fractional shifts used by `align_images_fourier`; Bragg-disk multicorr now uses the same helper. Each immutable level continues from the last completed stack/masks/shifts, is memory-bounded and cancellable, and the UI exposes **Align Next Level** / **Reset Alignment** with schedule and convergence diagnostics. `tools/parallax-alignment-test/run.sh` covers integer compatibility plus every `[4, 2, 1]` level on asymmetric non-square known fractional shifts, reset, completion, cancellation retention, and input immutability.
- **Parallax low-order aberration fitting** ports py4DSTEM's Å/radian unit conversion, affine least-squares shift transform, 2×2 right polar decomposition, transpose/forced-rotation conventions, and C1/C12a/C12b extraction. The diagnostic result is immutable and deliberately does not overwrite calibration or aligned arrays. **Fit Low-Order Aberrations** appears only after schedule completion and reports rotation, coefficients, and measured-vs-fitted RMS. `tools/parallax-aberration-test/run.sh` source-locks normal, transpose, and forced-rotation branches and rejects incomplete/singular inputs.
- **Parallax higher-order aberration fitting** ports the default `(m,n,a)` term ordering through radial order 3, passive-rotation gradient derivatives, low-order initialization, and global/recursive/recursive-exclusive coefficient increments. The UI's **Fit Aberrations** action uses default recursive fitting and shows all seven Cartesian coefficients plus residual improvement without applying correction. The same aberration harness source-locks terms, every gradient sample, coefficients, fitted shifts, and residuals for all three fit modes.
- **Parallax aberration correction** ports the fitted even/odd CTF surfaces, `sign(sin(χeven))·exp(-iχodd)` transfer, DC removal, optional Butterworth low-pass, exact-shape FFT correction, and padding crop. A high-pass envelope uses py4DSTEM's shared constraint formula (the current parallax signature exposes but does not apply its high-pass argument). **Correct Phase** publishes a separate phase image with Å⁻¹ controls; cancellation retains the fit. The aberration harness covers full-fit, filtered, and C1-only correction on an asymmetric non-square image.
- **Parallax subpixel reconstruction** ports py4DSTEM's BF/DF sampling-limit heuristic, circular bilinear or optional source-compatible Lanczos KDE, Gaussian density normalization, optional sinc low-pass, rounded padding crop, and iterative probe-position correction. Position search supports the default centered-gradient and checkerboard branches with adaptive minimum-bounded steps and only publishes a fully completed iteration. **Upsample BF** exposes factor/kernel/iteration controls and reports Å/px plus convergence while an explicit displayed-product tag keeps BF and corrected-phase export metadata distinct. Work arrays are memory-bounded and cancellation-safe. `tools/parallax-subpixel-test/run.sh` source-locks automatic/explicit factors, Lanczos weights, both position-search branches and every score, exact-shape filtering/cropping, invalid prerequisites, memory rejection, and pre/mid-iteration cancellation.
- **Parallax depth sectioning and result browsing** ports fitted/full-CTF and C1-fallback signed-sine correction, per-probe defocus propagation, optional information-limit envelope, BF averaging, and deterministic scan crop for explicit Å planes. The stack is memory-bounded and publishes atomically after cancellation-safe plane boundaries. Ptycho mode can revisit preprocessed, aligned, subpixel, corrected-phase, and any depth-plane result without recomputation, with product-specific export metadata. `tools/parallax-depth-test/run.sh` source-locks full/fallback/filtered non-square stacks, crop and indexing, memory rejection, and between-plane cancellation.
- **Single-slice iterative ptychography** has an explicit method/options/result boundary around py4DSTEM's complex-object full-batch operators. Gradient descent and retained-exit-wave DM/AP share fractional Fourier-shifted probes, corner-centered periodic patches, amplitude projection, normalized object/probe adjoints, constraints, and intensity-normalized error history. Object/probe phase/amplitude switch without recomputation, and exact completed options—not mutable controls—drive persistence. `tools/singleslice-ptychography-test/run.sh` matches every GD, constrained, and DM/AP iteration error, final complex arrays, diagnostics/crops, immutability, invalid options, memory rejection, and cancellation on a non-square fractional fixture.
- Origin provenance is explicit and visible: geometric default, file-provided `qx0_mean`/`qy0_mean`, fitted in-app, or manually moved aperture center. BF/ADF/HAADF presets change radii without discarding that center.
- DM4 `ByteReader` is now bounds-checked end-to-end — malformed/truncated files throw `truncated` instead of crashing; tag counts are sanity-capped.
- Rank-3 HDF5 datasets now read correctly (hyperslab selection matches the file's real rank).
- Stale-result guard: analyses capture a dataset epoch and drop results if a different dataset was activated mid-run.
- `DiskDetection.detectAll` `failed`-flag data race fixed; disk detection and ACOM matching now use one worker-pooled detector/matcher per core (strided rows) instead of one per scan row.
- Display normalization ignores NaN/Inf (finite min/max; non-finite pixels map to the low end).
- Rotation calibration (and the 180° flip) immediately refresh a displayed DPC/iDPC result; the full objective curves are now plotted in the inspector ("Rotation diagnostics").
- Cube upload no longer double-allocates (`bytesNoCopy` into a page-aligned buffer).
- Normalized display pixels are cached per version counter instead of being recomputed on every SwiftUI render.
- Scattering factors now cover all 103 elements (generated from py4DSTEM's Lobato table); unknown elements fail loudly. ACOM offers a **Custom** cubic crystal (element × FCC/BCC/SC/diamond × lattice constant). Materials Project lookup is a future step.
- Export: result image / diffraction pattern as PNG (rendered as displayed), Bragg peaks as coordinate-explicit CSV, standalone py4DSTEM-compatible BraggVectors, and an atomic scalar-result session `.h5` sidecar (File section).
- DP mean/max picker lives in the tools panel when the CBED pane is active, with a standalone "Compute Mean / Max" pass (no origin calibration required).
- Histogram gained a draggable contrast window (applied in the fragment shader; independent of the log-counts toggle).
- Output log strip below the image panes (toggleable) shows timestamped operation history.
- Arrow keys step the scan position (Shift = 10 px).
- Histogram range slider rewritten: the whole histogram takes the drag and moves the nearest handle (the old per-handle hit areas clipped at the row edge, so the hi handle was ungrabbable).
- Split-view squeeze limits: sidebar capped at 300 pt, detail area has a 480 pt floor, window min width 1080 — panes can no longer be crushed into distorted slivers.
- PNG exports now burn the scale bar into the image (bottom-left, same 1-2-5 quantization and units as on screen); small maps are integer-upscaled (nearest neighbor) to ≥512 px so the label stays legible without altering data pixels.
- **Zoom + calibrated scale bars.** Both panes zoom (pinch; diffraction also pans by dragging the background; double-click resets). Image and overlays share one transformed container so the aperture, peaks, crosshair, and ROI stay pixel-accurate at any zoom (this also fixed the pre-existing overlay misalignment when the real-space view was zoomed). Each pane shows a 1-2-5 scale bar that re-quantizes with zoom — calibrated (nm / 1/nm) when pixel sizes are known, px otherwise. DM4 pixel sizes + units now flow into `Calibration` automatically (and auto-fill the ACOM Å⁻¹/px scale when units are convertible); manual pixel-size fields in the Calibration section cover plain HDF5.

### UI / UX (polish cycle in progress)

Done: toolbar mode switcher (all modes reachable), independently hideable tools + inspector panels, live-drag detector → real-space and real-space marker → diffraction, shape-correct + grid-snapped detector overlays, centered pattern-mode picker, higher-contrast position marker, independent CBED/result histogram contrast, numeric scalar colorbars, DPC/IPF directional keys, and native File/View commands with shortcuts.

Still open:

- ~~**Virtual diffraction** and active-pane tools~~ are done: point scrubbing or grid-snapped rectangle/circle ROIs drive the CBED pane through bounded tiled reductions.
- ~~Per-view histogram draggable contrast and gamma~~ are done independently for real-space and CBED views.
- ~~Scale bars with units~~, ~~numeric scalar colorbars~~, and ~~DPC magnitude in mrad~~ are done. A direct scattering-angle CBED scale remains open.
- ~~**Preprocessing / import**~~ — direct DM3/DM4 reading, in-app ellipse measurement, bounded canonical calibrated `.h5` export, and the five-field calibration-readiness checklist are implemented. The guided sheet supports provenance-aware calibration actions, explicit uncalibrated export, real-space crop, count-preserving integer Q binning, exact calibration transforms, output preview, progress, cancellation, and atomic publication. The verified format notes live in [`docs/dm4-format.md`](docs/dm4-format.md).
- **Results persistence + file tree** — BraggVectors, named scalar RealSlices, lossless RGBA Arrays, full calibration, and opaque external EMD objects coexist in a py4DSTEM-readable companion; the inspector reloads and atomically removes app results, showing shape/sampling/provenance. Retained convergence histories have native interactive plots, and saved parallax/ptychography provenance can explicitly rehydrate validated controls without rerunning analysis. EMD plot-node creation/viewing remains open.

### Remaining program

The durable handoff sequence is:

1. ✅ **Architecture and testing foundation — 2 checkpoints complete**.
2. ✅ **Ptychography completeness — 2 checkpoints complete**.
3. ✅ **Profile-driven Metal/MLX performance — 3 checkpoints complete**.
4. ✅ **Scientific correctness gaps and real-data validation — complete** (quantitative iDPC, strain robustness, fuller ellipse fitting, non-cubic ACOM, four full real-data virtual-image goldens).
5. ✅ **MIB/EMPAD and broader EMD support — implementation complete; vendor readers remain Preview pending a real-file corpus**.
6. ✅ **UI/UX, multi-session workflows, and accessibility — v1 checkpoint complete**.
7. **Distribution/notarization — repository work complete; credential-owner submission remains**.
- ~~**Performance panel**~~ is live with operation/progress/cancel, elapsed time, positions/s, ETA, process memory, GPU, and working-set budget.
- ~~Histogram range slider~~ and ~~DP mean/max in the tools panel~~ — done (see Fixed list below).
- ~~**macOS menu bar**~~ — focused-window File, View, Run Current Analysis, and Cancel Analysis commands have native shortcuts.

---

## Developer notes

- **One `@main`** app type in `App/mac4DSTEMApp.swift`; root UI in `UI/ContentView.swift`.
- **State**: `AppState` is the observable single source of truth (`@Observable`). Views describe UI only; loading/parsing/compute live in `Core`.
- **Concurrency**: the project builds in Swift 5 language mode with *approachable concurrency* and **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**, so types are MainActor-isolated by default. Compute types that run blocking GPU work off the main thread are marked **`nonisolated`** (e.g. `MetalEngine`, and the `VirtualDetector` / `OriginCalibration` / `RotationCalibration` entry points), and `AppState` invokes them via `Task.detached`.
- **Metal parameter structs** in `MetalEngine.swift` must stay byte-for-byte identical to the `struct`s in the matching `.metal` files (all 4-byte fields).
- Treat `References/` as read-only. Bring code over in small batches, convert `@EnvironmentObject`/`@Published` to the Observation framework, and build after each batch. Do not copy old project scaffolding (`.xcodeproj`, `Package.swift`, build folders) into this project.
