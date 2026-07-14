# Agent progress — mac4DSTEM

Persistent handoff between agent sessions. Read this before remapping the repo.
At the end of a session, append completed work and replace the next slice.

## 1. Goal and priorities

Native macOS Swift/SwiftUI/Metal app matching scientifically important
py4DSTEM workflows with a polished, interactive Mac UI. Reference source:
`References/py4DSTEM-dev` (read-only). Priorities are numeric correctness and
py4DSTEM parity, then buildability, workflow coverage, performance, and polish.
Work in small slices that end with a green build and targeted verification.
The v1 release contract is `docs/v1-scope.md`; it freezes the supported lab
workflow, stable versus Advanced tiers, release gates, and scope-change rule.

## 2. Confirmed state (2026-07-14)

- HDF5/EMD (`H5Reader`) and DM3/DM4 (`DM4Reader`) load behind the actor-based
  `FourDDataSource` protocol. The full app builds cleanly with Xcode-beta.
- Working surface: virtual imaging/diffraction, DP statistics, origin and R–Q
  calibration, DPC/iDPC, probe kernel and Bragg disk detection, strain, and
  simplified polar-correlation ACOM.
- The Calibration UI now identifies the aperture center as geometric default,
  file-provided qx0/qy0 mean/maps, fitted in-app, or manually moved.
- The session sidecar stores scalar/RGBA maps plus full supported calibration,
  preserves unrecognized external root objects, and supports explicit validated
  parallax/ptychography control rehydration. It does not author EMD plot nodes
  or serialize transient scientific arrays. A native XCTest bundle covers fast
  production/workflow contracts; twenty-four scientific/interoperability
  harnesses cover the numeric, tiled, cancellation, persistence, reader, and
  packaging boundaries.

## 3. Completed slices

- H5Reader reads calibration metadata from HDF5 attributes and datasets,
  including UTF-8 strings, bool-enum `QR_flip`, Q/R pixel sizes and units,
  `qx0_mean`/`qy0_mean`, and ellipse `a`/`b`/`theta`.
- `tools/calibration-test/` verifies attribute-form, dataset-form, and
  two files written by py4DSTEM 0.14.19. The non-square origin-map fixture
  asserts fitted/measured arrays, means, scan order, and detector-axis swap;
  run result on 2026-07-13: all four fixtures passed.
- DM4Reader and compute code are clean under the project's approachable
  concurrency settings; pure compute types are explicitly `nonisolated`.
- `AppState.activate` consumes file qx0/qy0 means as the initial aperture
  center. AXIS SWAP occurs only there: app x = py4DSTEM qy0, app y = qx0.
  Full file maps use the same conversion in `PixelOriginMaps.appOriginMaps`.
  Paired finite rank-2 maps matching `[Ry,Rx]` populate `Calibration.origin`
  directly; optional measured maps remain absent unless both arrays exist.
- `OriginProvenance` lives in `Core/Data/Calibration.swift`. Dataset activation
  begins `.geometricDefault`; file means set `.fileMean`; successful origin
  fitting sets `.fitted`; moving only the aperture center sets `.manual`;
  radius-only edits preserve provenance. Detector presets now change radii
  without discarding the current center/provenance. `ContentView` shows the
  source in its Calibration section.
- `tools/virtual-detector-test/run.sh` source-locks its standard-library
  reference calculation to py4DSTEM `make_detector`, compiles the production
  shaders and Swift wrappers, and tests a non-square synthetic cube. Annulus
  (including exact inner boundary and near-edge fractional center), circle,
  rectangle, and point all pass with max error 0. The comparison exposed the
  old inclusive inner boundary; production now matches py4DSTEM's strict
  `rIn² < r² < rOut²`. BF is a true circle and includes its center pixel;
  ADF/HAADF remain annuli.
- `tools/disk-detection-test/run.sh` source-locks a dependency-free reference
  to py4DSTEM 0.14.19 and runs the production `ProbeKernel`/`DiskDetector` on a
  non-square 32×64 pattern. Kernel, cross/hybrid correlation, pixel/poly/
  multicorr positions, qx/qy axis conversion, and every peak filter pass.
  It exposed one production diff: poly-refined intensities stayed at the
  integer maximum. They now use py4DSTEM's bilinear refined intensity.
- Live disk detections carry a monotonically increasing request generation,
  so a slow older task cannot replace peaks for a newer scrub or parameter
  change. Detection uses `displayedPattern` (current/mean/max/virtual), and
  mode/request/dataset checks gate result publication. `PeakOverlayGeometry`
  centralizes pixel-center and radius mapping; its non-square/corner/subpixel/
  squeezed-box cases pass in `tools/peak-overlay-test/run.sh`.
- ACOM templates store the exact detector basis used for projection. Matches
  right-compose that basis with the recovered in-plane angle in py4DSTEM's
  column-oriented matrix convention, then transpose and decompose extrinsic
  `zxz` like py4DSTEM's orix export. Euler φ₁/Φ/φ₂ maps and selected-position
  degrees are exposed. `tools/acom-orientation-test/run.sh` source-locks the
  convention and verifies general/singular rotations plus basis composition.
- `AnalysisCancellationToken` is a monotonic lock-protected token shared with
  detached/DispatchQueue workers. AppState owns one active scientific operation
  and exposes Cancel in the performance inspector. Disk, strain, orientation
  plans and ACOM stop at safe CPU boundaries; virtual detector, DP statistics,
  origin/rotation and DPC suppress publication after in-flight Metal completes.
  Dataset activation cancels the token and still advances `datasetEpoch`.
  `tools/cancellation-test/run.sh` cancels production multi-row disk work after
  its first reported row (with in-flight workers draining) and verifies well
  under 128 callbacks, nil partial output, and normal completion.
- `BraggVectorEMDWriter` dynamically binds the HDF5 C API and writes a
  py4DSTEM 0.14 / EMD 1.0 `BraggVectors` tree into a same-directory temporary
  file. It publishes with atomic POSIX rename only after HDF5 close and a final
  cancellation check; failure/cancellation removes the temp and preserves any
  existing destination. The source dataset is never opened by the writer.
- The writer's scan dataset is a 2-D variable-length compound PointListArray
  with float64 `qx`, `qy`, `intensity`. App `[Ry,Rx]` is written directly as
  py4DSTEM `[R_Nx,R_Ny]`; each peak converts app `y(row)→qx` and
  `x(column)→qy`. Shape metadata and Q/R pixel sizes/units plus `QR_flip` are
  included. The UI exposes this as **py4DSTEM BraggVectors Sidecar…**, suggests
  `<source>_braggvectors.h5`, and connects it to shared progress/cancellation.
- `tools/bragg-export-test/run.sh` builds the production writer, checks the
  input bytes remain unchanged, checks mid-export cancellation preserves an
  existing final file and leaves no temp, then reads the completed sidecar with
  checked-in py4DSTEM 0.14.19. Non-square scan/detector shapes, an empty scan
  position, variable peak counts, subpixel coordinates, intensities, axes, and
  calibration all round-trip exactly.
- `ScalarResultMap` extends that atomic sidecar contract with named py4DSTEM
  `RealSlice` siblings directly under `/braggvectors_root`. Deterministic
  `result_<kind>_<hash>` node IDs avoid collisions; a version-2 root manifest
  records ordered node IDs and the current result. Maps store non-square
  float32 pixels, calibrated `Rx`/`Ry` dimension vectors, stable ASCII result
  kind, display name, and value units. Existing supported maps and BraggVectors
  are preserved with `H5Ocopy`, so their payloads are not decoded/re-encoded.
- **File → Export → Save Current Result to Session Sidecar** publishes virtual,
  scalar DPC, strain, or ACOM maps to `<source>.mac4dstem.h5`. Dataset activation
  enumerates that companion, restores the manifest's shape-compatible current
  map, and populates the inspector's read-only sidecar tree. Legacy one-slot
  `/result_map` files remain readable and migrate to the v2 layout on save.
- `tools/sidecar-result-test/run.sh` verifies two-map enumeration/order, exact
  finite and NaN values, deterministic current-map restoration, same-kind
  replacement without changing the other map or BraggVectors, cancellation and
  source-byte safety, calibrated dimensions, whole-file py4DSTEM reading, and
  direct py4DSTEM 0.14.19 reads of both `RealSlice` nodes.
- Session calibration now round-trips Q/R pixel sizes and units, `QR_flip`,
  `QR_rotation` (radians plus degrees), probe radius, ellipse metadata, fitted
  and measured non-square origin maps, means, and shifts in py4DSTEM's native
  qx/qy frame. `ResultExport` performs the app x/y ↔ py4DSTEM qy/qx swap only
  at the save boundary; `PixelOriginMaps.appOriginMaps` performs the inverse.
- Dataset activation loads the companion snapshot before running the initial
  analysis. Present session fields override source calibration, compatible
  origin maps receive `.sessionMaps` provenance, mean-only fallback receives
  `.sessionMean`, and a mismatched map is ignored without losing valid scalar
  fields. **Save Calibration to Session Sidecar** works without a scalar result
  and preserves all named maps plus BraggVectors atomically.
- The calibration and sidecar harnesses cover checked-in py4DSTEM rotation and
  probe metadata, exact native/py4 round trips, partial/mismatched maps,
  calibration-only replacement, cancellation, and supported-object survival.
- ACOM reporting now reduces every matched cubic orientation over all 24 proper
  signed-permutation rotations. The minimum-angle quaternion representative is
  deterministic over a complete symmetry orbit; its reduced Bunge Euler values
  replace the formerly arbitrary representative without changing match scores,
  second scores, or reliability. An explicit identity policy is the fallback
  for future non-cubic point groups; all currently exposed crystals are cubic.
- ACOM exposes an orix-aligned m-3m **IPF · Z** RGBA map for the sample/beam
  normal, a sampled [001]/[101]/[111] legend, and a scalar **Cubic FZ angle**
  diagnostic that follows the existing RealSlice persistence path. Empty
  matches render black and selected-position Euler readout is labeled as cubic
  fundamental-zone output.
- `tools/acom-orientation-test/run.sh` now checks the 24-member group,
  determinant/orthogonality, orbit-invariant reduction, the cubic angular
  bound, IPF symmetry and continuity, and five orix 0.14.2 RGB goldens in
  addition to the existing py4DSTEM matrix/Euler singular cases.
- Scalar real-space results and CBED patterns now have compact numeric
  colormap ramps in their image panes. Labels reflect the exact clipped raw
  value endpoints; log-CBED clipping is inverted back to intensity, diverging
  scalar maps mark zero, and RGBA DPC/IPF modes retain directional legends
  instead of receiving a misleading scalar scale.
- CBED contrast has its own low/high window and inspector histogram, independent
  of the result-map histogram/window. Diffraction PNG export applies that same
  CBED window; switching datasets resets both windows.
- Native File/View command groups now expose Open, scalar/RGBA result PNG,
  diffraction PNG, session result/calibration saves, and tools/inspector/output
  panel toggles with shortcuts. Menu and visible controls call the same
  AppState actions and share data/busy-state enablement.
- The macOS target now embeds the prepared HDF5/AEC/SZIP closure in
  `Contents/Frameworks`, codesigns nested libraries on copy, enables Hardened
  Runtime and App Sandbox, and removes Homebrew search/runtime paths. Both HDF5
  binders prefer the bundle while retaining only an explicit harness override
  and bare-name fallback.
- User-selected files are read/write. The first session-sidecar save uses an
  `NSSavePanel` defaulted beside the source and stores an app-scoped
  security-scoped bookmark; later atomic saves and automatic reopen resolve the
  same grant. This avoids assuming that selecting one dataset grants access to
  arbitrary sibling paths.
- `tools/package-test/run.sh` clean-builds an ad-hoc Release app, verifies the
  relative nested dependency closure, strict signatures, sandbox/read-write/
  bookmark entitlements, absence of `get-task-allow` and local dylib paths, and
  opens a checked-in fixture through bundled HDF5 2.1.1. Credentialed Developer
  ID signing/notarization inputs are documented in `docs/distribution.md` and
  remain an external release step.
- Every whole-scan datacube consumer now uses bounded `[tileRy,Rx,Qy,Qx]`
  reads. HDF5 issues true multi-row hyperslabs, DM4 decodes contiguous row
  ranges, and the tile height is capped from Metal's recommended working set.
  Virtual imaging, DP mean/max, selected-area diffraction, origin measurement,
  CoM/DPC, rotation calibration, and disk detection all report aggregate
  progress and honor cancellation between tiles. The old resident-cube API and
  its size ceiling were removed.
- The virtual-detector harness forces one-row tiles and proves exact resident
  parity for detector masks, origin measurement, CoM, selected diffraction,
  disk detection, and DP statistics; it also verifies no partial result after
  cancellation. H5 calibration fixtures verify multi-row tile reads equal
  concatenated row reads.
- py4DSTEM ellipse calibration is now applied to scientific Bragg coordinates
  in the native qx/qy convention after per-position origin correction. Raw
  detector peaks remain unchanged for overlays and `_v_uncal` export. Bragg
  maps, strain, and ACOM consume the calibrated view; the disk/calibration
  harnesses cover the axis swap and exact transform.
- Strain can use the visible point/rectangle/circle real-space ROI as its
  unstrained reference and accepts manual calibrated g₁/g₂ vectors when
  desired. Automatic mode now clusters repeated reciprocal vectors over the
  peak population, scores bounded basis pairs by integer-indexing consensus,
  and requires at least 50% support plus condition number ≤8. Local indexing
  rejects off-lattice and excessive-index peaks, then performs a MAD-gated
  intensity-weighted refit. Spatial-hashed clustering keeps the population pass
  near-linear even with many unique noise peaks. Reference positions receive a
  second robust gate before py4DSTEM-compatible component medians define g₁/g₂.
- Strain fit support/count/RMS/condition, indexing tolerance, indexed fraction,
  median local RMS, and reference inlier/rejection counts are visible in the UI
  and included in session provenance. Weak or ill-conditioned solutions fail
  with an actionable message instead of publishing a plausible-looking map.
  `tools/strain-test/` source-locks py4DSTEM indexing, weighted fitting, median
  reference, and tensor formulas; its 5×3 fixture covers missing positions,
  short and high-intensity off-lattice peaks, a distorted reference point,
  ill-conditioned manual input, and an incoherent automatic population while
  preserving the original whole-scan/ROI/manual/Q/DPC cases.
- Cubic ACOM templates are sampled directly in the m-3m
  [001]-[101]-[111] fundamental sector with deterministic spherical
  farthest-point coverage. The ACOM harness verifies the requested count,
  canonical vertices, sector bounds, and absence of symmetry duplicates.
- **Calibrate Q from Crystal** robustly estimates Å⁻¹/pixel from the median
  innermost detected shell and the selected crystal's first allowed reflection.
  Disk detection can alternatively build its kernel from the current CBED or
  summed vacuum ROI; raw/synthetic source is visible in the UI.
- DPC magnitude can be displayed and persisted in mrad using relativistic
  electron wavelength plus Q calibration. Input voltages are normalized from
  eV or kV to one kV convention. Both scalar panes now have independent gamma,
  and the Metal shader, numeric colorbars, and PNG exports share that mapping.
- Session schema v3 stores pre-colored DPC/IPF results as lossless uint8
  `[Ry,Rx,RGBA]` EMD `Array` nodes rather than flattening them to scalars.
  Scalar RealSlices, RGBA Arrays, BraggVectors, and calibration survive atomic
  replacement/removal together; py4DSTEM/emdfile reads the complete tree.
  Inspector rows can load any saved result and remove one result atomically.
- Nonzero disk-correlation smoothing is now source-locked and tested at
  `sigma_cc=1.25`; the separable kernel uses SciPy's half-sample `reflect`
  boundaries. The performance panel reports elapsed time, average positions/s,
  ETA, process memory, GPU, and working-set budget.
- `writeCalibratedDataCube` streams a real-space crop through optional integer
  count-preserving Q binning into a chunked float32 `datacube_root/datacube`
  EMD file. It trims incomplete bottom/right Q blocks like py4DSTEM, transforms
  pixel size/probe/origin calibration into the output coordinate frame, and
  atomically publishes without modifying the source. The guided Mac sheet
  previews shape/size/trimming and runs through shared progress/cancellation.
  `tools/preprocessing-export-test/` proves exact one-row bounds, crop/bin
  pixels, chunk shape, cancellation safety, native reopen, and a py4DSTEM
  0.14.19 round trip.
- Disk kernels and correlation now use the detector's exact Q shape. Radix-2
  data retains vDSP's fast 2-D FFT; other shapes use exact separable DFTs with
  a scalar correctness fallback for unsupported small/prime lengths. The disk
  harness adds a wrapped-edge 24×40 native-grid autocorrelation invariant.
- Atomic sidecar rewrites preserve root objects outside mac4DSTEM's mutable
  calibration/Bragg/result manifest with HDF5 object copies. The session test
  injects an external EMD Array, rewrites calibration, and verifies exact reads
  through both py4DSTEM and h5py.
- `EllipseCalibration.fit1D` ports py4DSTEM's intensity-weighted canonical
  conic residual and `(A,B,C) -> (a,b,theta)` convention in native qx/qy order.
  A damped nonlinear solve returns normalized residual and angular coverage;
  blank, partial-ring, non-physical, high-residual, and non-convergent inputs
  fail without publishing calibration. **Fit Ellipse** uses a user-selected
  annulus on the detector-shaped Bragg map or scan-mean diffraction pattern,
  reports fit quality, refreshes the calibrated Bragg map, and flows through
  existing session/DataCube persistence. `tools/ellipse-calibration-test/`
  source-locks the formulas and covers non-square rotated and near-circular
  rings, detector-axis conversion, blank data, and four-spot degeneracy.
- Scientific-correctness checkpoint 3 adds `fitBestAvailable`: the existing
  conic is the deterministic initializer and safe publication fallback, while
  a bounded Levenberg–Marquardt refinement evaluates py4DSTEM calibration's
  central Gaussian plus asymmetric inner/outer Gaussian ring profile. It uses
  equivalent physical `(a,b,theta)` variables so non-physical `(A,B,C)` steps
  cannot occur, then performs one MAD-gated refit. Model, residual, ring widths,
  and fallback reason are visible; only accepted `a/b/theta` enter calibration.
  The expanded source-locked fixture covers background, asymmetric width,
  deterministic noise/outliers, and an overlapping-ring forced fallback on
  non-square detectors. Focused harness and all six XCTest methods pass.
- V1 ACOM performance checkpoint 1 extends the optimized benchmark with
  400-template plan generation and deterministic 4×3/8×6 non-square matching,
  including backend, dimensions, memory estimate, samples, and scientific
  checksum. The original 48-position matcher measured 210.4 ms on the checkpoint
  M3. Contiguous template FFT storage plus vectorized vDSP complex products
  reduce the warmed median to 25.1 ms (8.4×) without changing the scalar-
  reference template, angle bin, or scores.
- V1 ACOM performance checkpoint 2 adds an exact batched Metal spectrum and
  inverse-angle argmax backend. `tools/acom-matching-test/` proves exact template
  choice and angle modulo Friedel symmetry, with score error below 3e-7 and
  reliability error below 9e-7. The Metal median was 32.9 ms, slower than the
  25.1 ms vector CPU result, so Automatic deliberately selects Accelerate; Metal
  remains explicit experimental evidence until a true batched FFT wins. The app
  reports the backend that actually produced each map. ACOM orientation/matching,
  XCTest, optimized benchmark, and diff hygiene pass.
- The preprocessing sheet now begins with a derived five-item calibration
  readiness guide: origin/probe, ellipse, R-Q rotation, Q scale, and R scale.
  Each item names file/session/in-app/manual provenance, validates finite
  physical values, and offers the existing measurement operation or a manual
  scale field. Missing items trigger a named explicit confirmation before the
  save panel; the app never invents a value. Provenance resets on activation,
  successful operations publish it only after their cancellation boundary,
  and manual aperture recentering now clears superseded origin maps so export
  writes the manual mean. `tools/calibration-readiness-test/` covers empty,
  imported, session, measured, manual, mixed, and invalid partial states; the
  preprocessing fixture traverses a fully ready report into the exact
  py4DSTEM round trip.
- `ParallaxPreprocessor` now source-locks the default non-iterative half of
  py4DSTEM `Parallax.preprocess`: mean-DP 0.8-threshold BF selection,
  row-major qx/qy indices, reciprocal vectors, relativistic wavelength/probe
  angles, sine-squared edge blending, weighted order-0 normalization, padded
  `[BF,Ry,Rx]` stack, and incoherent BF/error initialization. Two scan-tiled
  passes write directly into the final stack layout; a 1 GiB preview ceiling
  rejects unsafe allocations. Physical R/Q units, voltage, origin, rotation,
  and transpose are explicit prerequisites/metadata and are never guessed.
  Ptycho mode exposes only **Prepare Parallax Preview** plus diagnostics; no
  reconstruction is claimed. Calibration changes invalidate the preview,
  while cancellation/dataset epochs suppress partial publication.
  `tools/parallax-preprocessing-test/` source-locks the checked-in formulas
  and matches a non-square fixture under forced one-row tiles, including
  nm/Å/mrad conversions, mid-pass cancellation, and the memory ceiling.
- `MatrixDFTCorrelation` extracts the former disk-only multicorr patch into one
  source-locked helper shared by disk detection and parallax. It implements
  `align_images_fourier`'s circular three-point parabolic seed, ties-to-even
  half-pixel rounding, factor-8 matrix-DFT patch, final parabolic polish, and
  wrapped fractional result. Existing disk multicorr parity remains green.
- `ParallaxAligner.alignNextLevel` continues the default `[4, 2, 1]`
  coarse-to-fine schedule from the prior shifted stack/masks/total shifts/BF
  and convergence history. The new shift estimate is fit against the cumulative
  field before applying only its increment; median recentering and reconstruction
  then match py4DSTEM. Every level is immutable, memory-bounded, cancellable,
  and a cancelled continuation leaves the last completed result unchanged.
  `alignOneLevel` retains its integer compatibility path for regression coverage.
  Ptycho mode now exposes **Align Next Level** / **Reset Alignment**, schedule
  position, factor, and convergence history; export metadata names the general
  aligned preview. `tools/parallax-alignment-test/` source-locks integer levels
  and factor-8 continuation across every default bin on asymmetric non-square
  known fractional circular shifts. Cumulative shifts agree within 0.005 px,
  arrays within 0.002, BF within 0.0002; reset, completion, cancellation
  retention, memory rejection, and preprocessing immutability are covered.
- `ParallaxAberrationFitter.fitLowOrder` ports py4DSTEM's first aberration-fit
  stage without mutating calibration: aligned scan shifts are converted to Å,
  probe angles from mrad to radians, an affine transform is solved, and a true
  2×2 right polar decomposition recovers rotation plus C1/C12a/C12b. Normal,
  transpose, and forced-rotation conventions match SciPy/py4DSTEM within
  2e-5 in `tools/parallax-aberration-test/`; incomplete schedules and singular
  angle fields reject publication. The UI exposes the diagnostic fit only
  after alignment completion and reports its measured-vs-fitted RMS.
- `ParallaxAberrationFitter.fitHigherOrder` adds py4DSTEM's default seven
  `(m,n,a)` terms through radial order 3, passive-rotation gradient samples,
  C1/C12 initialization, and recursive, recursive-exclusive, or global
  incremental least-squares modes. The existing fit action now runs the default
  recursive mode and reports all coefficients plus residual improvement while
  leaving aligned data untouched. The aberration harness source-locks every
  term/gradient plus coefficients and fitted shifts for all three modes.
- `ParallaxAberrationCorrector` applies the fitted even/odd CTF phase surfaces,
  zero-DC signed-sine transfer, optional low-pass and shared high-pass
  Butterworth envelopes, exact-shape FFT, and deterministic padding crop. The
  correction is a separate cancellable result; fit/alignment remain immutable.
  The aberration harness matches full-fit, filtered, and C1-only NumPy arrays
  for χ surfaces, complex transfer, padded phase, and non-square crop.
- `ParallaxPreprocessResult` now retains py4DSTEM's distinct
  `_stack_BF_unshifted` alongside the edge-blended alignment stack. Both are
  filled during the same tiled second pass and counted under the 1 GiB resident
  ceiling; the preprocessing fixture source-locks both arrays. Alignment still
  accounts one input stack through `stackByteCount`, while the UI reports their
  combined resident bytes.
- `ParallaxSubpixelReconstructor` ports the non-position-corrected bilinear path
  from `Parallax.subpixel_alignment`: BF/DF sampling limits and automatic factor,
  ties-to-even output rounding, circular four-neighbor deposition from the
  immutable unwindowed stack, SciPy-reflect Gaussian density normalization,
  optional sinc deconvolution, and py4DSTEM's rounded padded-object crop. Output
  arrays have an explicit working-memory limit and cooperative cancellation.
  **Upsample BF** exposes automatic/explicit factor, sigma, and sinc filtering;
  result metadata uses an explicit displayed-product tag so a retained phase
  correction cannot mislabel a newly published BF image.
- `tools/parallax-subpixel-test/` source-locks the checked-in parallax and KDE
  helper contracts. Its asymmetric non-square fractional-shift fixture matches
  automatic and explicit factors, padded/cropped arrays, and exact-shape sinc
  filtering, and rejects incomplete alignment, invalid factors, memory excess,
  and cancellation. Debug build and all four parallax harnesses passed after
  this checkpoint.
- The same subpixel implementation now supports py4DSTEM's optional Lanczos
  deposition, including the current checked-in Cartesian window expression,
  plus iterative probe-position correction. Centered-gradient and checkerboard
  search branches use periodic bilinear scoring, adaptive/minimum steps, padded
  edge-window gating, full KDE recomputation, and per-iteration score history.
  Publication remains atomic after the final iteration; work arrays are included
  in the ceiling and cancellation is checked before and during each iteration.
  The Ptycho controls expose interpolation order, iteration count, and step mode.
- The subpixel fixture now matches order-2 Lanczos KDE and both two-iteration
  position-search branches for final padded/cropped BF, full probe dx/dy fields,
  and every convergence value. It also exercises invalid Lanczos order and
  cancellation after the baseline KDE. Debug build passed after this checkpoint.
- `ParallaxDepthSectioner` ports py4DSTEM `depth_section` for explicit finite Å
  planes. It evaluates the full fitted CTF or C1 fallback, zeroes DC, propagates
  each immutable shifted virtual-BF image using its probe angle, applies the
  optional information-limit envelope, averages probes, and retains a contiguous
  padded float32 depth stack with deterministic cropped-plane access. Output and
  scratch memory are bounded; cancellation is checked within and between planes.
- Ptycho mode now computes depth stacks and exposes a reusable displayed-product
  picker for preprocess, alignment, subpixel BF, corrected phase, and depth.
  Depth plane changes reuse the retained stack, preserve all other products, and
  update result/export metadata without recomputation. `tools/parallax-depth-test/`
  matches full-fit, C1 fallback, and fractional-power filtered non-square golden
  stacks/crops, invalid plane access, memory rejection, and cancellation. Debug
  build passed after this checkpoint.
- `SingleslicePtychography` is the first iterative engine behind an explicit
  prepared-input/options/result boundary. Its CPU reference path ports the
  checked-in single-slice complex-object full-batch GD operators: ties-to-even
  patch centers, fractional Fourier probe shifts, periodic corner-centered
  patches, measured-amplitude projection, probe/object overlap normalizers,
  simultaneous adjoint updates, and total-intensity-normalized error. Inputs are
  immutable and only a completed multi-iteration result is returned.
- `PtychographyPreparer` bridges the active tiled source to that engine with
  bilinear periodic origin recentering, square-root amplitudes, calibrated
  object sampling/scan positions, source-compatible complex aperture-probe
  initialization, and explicit resident memory/cancellation boundaries. Ptycho
  controls expose iteration count, step, normalization minimum, and fixed probe;
  object phase/amplitude reuse the retained complex result and distinct metadata.
- `tools/singleslice-ptychography-test/` source-locks py4DSTEM's forward,
  amplitude, patch, adjoint, normalization, and error contracts. A non-square
  fractional-position fixture matches every error plus final complex object and
  probe arrays and cropped phase/amplitude within 3e-5, and covers immutability,
  invalid options, memory rejection, and cancellation. Debug build passed.
- Session schema v4 allows scalar `RealSlice` results to have independent row
  and column sampling plus units and a sorted-JSON provenance dictionary. These
  values round-trip through group attributes/inventory/native load and drive the
  EMD dimension vectors; legacy maps without them still fall back to session R
  calibration. Scalar selection/reopen no longer incorrectly requires scan shape,
  while RGBA compatibility remains scan-shaped.
- Current-result save now supplies stable provenance for parallax subpixel BF,
  corrected phase, selected depth, and ptychographic phase/amplitude, including
  factor/kernel/position/filter, depth/CTF, or engine/method/iteration/error/update
  controls as applicable. Restored scalar metadata survives re-save. The sidecar
  harness adds all five kinds with asymmetric sampling/shapes and validates native
  inventory/load plus direct py4DSTEM RealSlice reads under preservation and
  cancellation. Debug build and the extended sidecar harness passed.
- `ScientificSeriesGeometry` provides deterministic linear/log plot geometry,
  splits invalid samples into visible gaps, centers single/constant series, and
  maps pointer positions to the nearest valid sample. SwiftUI renders retained
  parallax alignment, KDE position-correction, and ptychography GD histories
  with grids, selection markers, exact sample readout, and no analysis rerun.
- Saved-result inventory rows now expose arbitrary map shape, float32/RGBA8
  storage, value units, per-axis sampling, and a bounded priority summary of
  scientific provenance. `tools/result-presentation-test/` covers empty,
  single, ranged, log, non-finite/gapped, selection, sampling, and provenance
  formatting. The nineteenth standalone harness and Debug build passed.
- `SessionControlRehydration` is a pure typed boundary for schema-v4 provenance.
  It recognizes subpixel KDE/kernel/position controls, phase filters, selected
  depth/CTF/information controls, and single-slice GD iteration/update controls;
  non-finite, malformed, out-of-range, legacy, and unsupported-engine fields are
  ignored independently. **Apply Saved Controls** appears only for a selected
  scalar result with at least one valid setting, changes controls without
  launching work, and explicitly says transient arrays still require a rerun.
  Applying a saved depth plane sets a one-plane start/end/count configuration.
- The result-presentation harness now covers every rehydrated result family plus
  malformed/legacy/unsupported provenance. It and the Debug app build passed at
  the final campaign checkpoint.
- Final cross-slice regression on 2026-07-14 passed parallax preprocessing,
  alignment, aberration fitting/correction, KDE/position correction, depth,
  single-slice ptychography, the native/py4DSTEM sidecar suite, result
  presentation/rehydration, and a clean unsigned Debug build.
- Architecture/testing checkpoint 1 added the `mac4DSTEMTests` unit-test bundle
  to the synchronized Xcode project. Its first three production-level XCTest
  cases cover linear/log/gapped plot geometry, empty/single handling, and valid
  versus malformed saved-control provenance; `xcodebuild test` passes against
  the macOS app host.
- `tools/run-tests.sh` is the discoverable aggregate entry point for `unit`,
  `campaign`, `scientific`, and `all` layers. Shared Python discovery honors an
  explicit `PYTHON`, active environments, a repo `.venv`, and conventional
  py4DSTEM Conda locations, accepting only interpreters that import NumPy. All
  Python-backed harnesses no longer contain a username-specific path. A NumPy
  parallax golden and the full native/py4DSTEM sidecar round-trip passed through
  the resolver.
- Architecture/testing checkpoint 2 extracted active scientific-operation
  identity, deterministic timing, unit-rate/ETA calculation, replacement
  cancellation, stale-finish rejection, and reset into
  `AnalysisOperationController`. `AppState` remains the observable facade and
  clamps published progress, while dataset activation uses the controller's
  cancellation/reset recovery boundary. Direct token reach-throughs in disk
  and ACOM callbacks now use the same identity API.
- Three controller XCTest methods cover replacement/late finish, injected-clock
  metrics and over-complete progress, idempotent cancellation, and reset after
  failure/dataset replacement. The suite now has six tests across two classes.
- `tools/performance-baseline/` compiles optimized production FFT and
  single-slice ptychography sources and emits versioned JSON plus checksums. It
  is deliberately non-gating; compare the same machine/power mode before and
  after performance work.
- Performance checkpoint 1 upgrades that harness to schema 2 and exercises
  representative production workloads: exact/radix-2 FFT, correlation-
  only and Gaussian-smoothed disk detection, selected-area Metal diffraction,
  bounded Float32 tile staging, GD, and retained-exit-wave DM/AP. Each entry
  records repeat samples/median, backend, dimensions, a checksum, a working-set
  estimate, and maximum observed resident memory. `compare.py` emits
  machine-readable ratios without turning noisy wall-clock values into gates.
- On the 2026-07-14 Apple M3 checkpoint baseline (three warmed repeats), 24
  128×128 disk patterns took 11.27 ms without smoothing and 26.75 ms with the
  production σ=2 Gaussian/maxima path. By contrast, selected-area diffraction
  and tile staging on a 24×24×96×96 cube took 0.64 ms and 0.55 ms; five 64-
  position ptychography iterations took 6.79 ms (GD) and 9.59 ms (DM/AP).
  Therefore checkpoint 2 targets the scalable disk path, beginning with the
  scalar allocating separable Gaussian stage while retaining exact reflect-edge
  semantics and scientific goldens. The saved local pre-change report is
  `/tmp/mac4dstem-performance-before.json`; regenerate it for another machine.
- Performance checkpoint 2 replaces `DiskDetector`'s per-pattern temporary
  image and scalar horizontal/vertical tap loops with detector-owned reusable
  scratch and `vDSP_conv`. Padding is still constructed explicitly with
  SciPy's half-sample `reflect` mapping, and Gaussian taps are cached per sigma,
  so the source-locked scientific contract is unchanged. The warmed 24-pattern
  σ=2 median improved from 26.75 ms to 13.70 ms (1.95×); correlation-only stayed
  effectively flat at 11.27→11.22 ms, confirming the gain came from the selected
  stage. All disk goldens (including σ=1.25, exact-shape, measured-probe, and
  calibration cases), all six XCTest methods, and an unsigned Debug build pass.
  `/tmp/mac4dstem-performance-after-disk.json` and the comparison are ephemeral
  local evidence; use the checked-in harness to reproduce on another machine.
- Performance checkpoint 3 removes per-pattern allocation churn from
  `SingleslicePtychography`: fixed-shape shifted-probe, patch, Fourier, index,
  and DM previous-exit buffers now survive across every position/iteration.
  `FractionalShiftPlan` caches separable complex row/column ramps once from the
  immutable positions, changing repeated per-pixel trigonometry into compact
  complex multiplies. Its O(patterns×(Qy+Qx)) storage is included in the
  overflow-checked reconstruction memory ceiling and the benchmark estimate.
- All GD, constrained-GD, DM/AP, diagnostics, invalid-option, memory, and
  cancellation goldens remain green. Against the post-disk baseline, the warmed
  small fixture improved 7.13→6.63 ms for GD (1.08×) and 9.82→9.44 ms for DM/AP
  (1.04×). The harness now also records a 12×12 scan with 48×48 diffraction and
  three iterations: 28.91 ms GD and 38.30 ms DM/AP on the checkpoint M3.
- MLX Swift 0.31.3 was evaluated rather than added reflexively. Its official
  package supplies macOS 14+ `MLXFFT`, but the current reconstruction issues
  serial per-pattern FFTs interleaved with gather/scatter accumulation. A useful
  GPU implementation therefore requires a deliberate batched operator and
  new parity/memory tests; merely wrapping individual transforms would add a
  large C++/Metal resource dependency without demonstrating a gain. Keep the
  exact CPU implementation as reference/fallback and use the checked-in medium
  workload as the acceptance target for that future backend.
- Final performance-phase regression passed all six XCTest methods, all 19
  scientific/interoperability harnesses, native plus direct-py4DSTEM HDF5/EMD
  checks, forced-tile Metal paths, the final ten-workload benchmark, diff
  hygiene, and the hardened/sandboxed Release package audit. No performance
  threshold is a test gate; scientific checksums and goldens remain the gates.
- Scientific-correctness checkpoint 1 makes iDPC quantitative only across a
  strict readiness boundary: fitted per-position origins, R–Q rotation, positive
  real-space sampling, and reciprocal sampling in Å⁻¹/nm⁻¹ (or mrad plus beam
  voltage). Detector-pixel CoM shifts are converted to phase gradient with
  `2π·Q_pixel_size`; FFT frequencies use row/column Å sampling, so the persisted
  scalar is projected phase in radians. Missing prerequisites retain an explicit
  `idpc_qualitative` detector-pixel×scan-pixel result rather than false units.
- `DPC.integrateIDPC` now exposes periodic and centered zero-padded boundary
  contracts. The app uses exact 2× zero padding instead of asymmetric next-
  power-of-two padding, supports non-square/anisotropic grids, scales
  regularization from physical Nyquist frequencies, and fixes the arbitrary
  phase gauge to zero mean. Session provenance records quantitative status,
  boundary, factor, regularization, Q scale, and physical map sampling.
- New `tools/idpc-test` source-locks py4DSTEM's reciprocal CoM scaling, physical
  `fftfreq` sampling, and padding-factor semantics, then checks a 5×7 NumPy
  fixture. It recovers a known periodic phase in radians, independently matches
  centered 2× padding, proves the boundary choices differ, preserves the
  qualitative path, and covers Å/nm/mrad readiness conversions. Focused iDPC,
  strain/DPC, calibration, result-presentation, and native/direct-py4DSTEM
  sidecar suites plus XCTest/Debug build pass.
- Final quantitative-iDPC regression passed all six XCTest methods, all 20
  scientific/interoperability harnesses, native plus direct-py4DSTEM sidecar
  reads, and the hardened/sandboxed Release package audit. An unavailable FFT
  now returns an empty integration result rather than silently substituting the
  scientifically different DPC magnitude image.
- Scientific-correctness checkpoint 2 replaces the shortest-vector strain
  heuristic with the bounded consensus/local/reference pipeline described
  above. `StrainMapping` is explicitly nonisolated pure compute under the
  project's default MainActor policy. The focused source-locked strain fixture,
  all 20 scientific/interoperability harnesses, all six XCTest methods, and the
  hardened/sandboxed Release package audit pass on 2026-07-14.
- Final foundation verification passed all six XCTest methods, the eight-harness
  parallax/ptychography campaign (including native plus py4DSTEM sidecar reads),
  the standalone cancellation suite, benchmark checksum reproduction, diff
  hygiene, and a clean unsigned Debug build.
- Ptychography-completeness checkpoint 1 extends the exact-shape full-batch GD
  options with opt-in complex-object amplitude≤1 or pure-phase projection,
  corner-centered probe center-of-mass correction, and py4DSTEM's normalized
  real-space sigmoid support (relative radius/width). Constraints run after the
  simultaneous adjoint update in py4DSTEM order, do not alter the established
  default golden, are skipped for a fixed probe, and retain atomic cancellation.
- `SingleslicePtychographyResult` now retains its exact options and exposes
  centered probe phase/amplitude without recomputation. Both probe products use
  object-grid Å sampling, have distinct persistence kinds/provenance, and appear
  in the existing result picker. Persisted constraint controls round-trip through
  the validated control-rehydration boundary rather than reading mutable UI state.
- The ptychography Python fixture source-locks object threshold, corner CoM,
  Fourier shift, sigmoid mask, and intensity renormalization contracts. It
  matches constrained iteration errors, final complex object/probe, and centered
  diagnostic pixels within 3e-5, while the result-presentation harness/XCTest
  cover constraint provenance. Harness, XCTest, and Debug build passed.
- Ptychography-completeness checkpoint 2 adds full-batch DM/AP under
  `SingleslicePtychographyMethod`. For α∈[0,1], it uses py4DSTEM's deterministic
  generalized coefficients `a=-α, b=1, c=1+α`, retains complex exit waves for
  every diffraction pattern across iterations, applies the projection Fourier
  branch, and replaces rather than increments object/probe in the normalized
  adjoint. Its two exit-wave arrays are included in overflow-safe memory limits.
- Method/α controls, result status/history labels, scalar provenance summaries,
  and saved-control rehydration distinguish GD from DM/AP. The existing GD
  golden remains unchanged. The extended Python fixture source-locks projection
  coefficient/factor/exit-wave and replacement-adjoint expressions and matches
  every DM/AP error, full complex object/probe, amplitude crop, and stable phase
  crop (excluding undefined near-zero amplitude phase). Invalid α is rejected.
  Ptychography harness, result-presentation harness, XCTest, and Debug build pass.
- Final ptychography-completeness regression passed all six XCTest methods, the
  eight-harness parallax/ptychography campaign, native plus direct-py4DSTEM
  sidecar reads, the optimized benchmark/checksums, diff hygiene, and a clean
  unsigned Debug build. The established GD result remains bitwise within its
  prior tolerances while constrained GD and DM/AP add independent goldens.

- **Outcome-based v1 product redesign (six-checkpoint consolidated pass,
  2026-07-14):**
  1. `App/ProductWorkflow.swift` defines Prepare, Image, Map, Reconstruct, and
     Results; every `AnalysisMode` maps to exactly one user-facing task.
  2. `ContentView` replaces the global mode strip and technical checklist with
     a dataset context card, persistent outcome navigation, contextual tasks,
     and controls that appear only where they are relevant.
  3. Task selection is side-effect free. `runPrimaryWorkspaceTask()` owns the
     explicit primary action, including a guided parallax path through preview,
     alignment, fitting, correction, and subpixel output. Prerequisite messages
     link back to Prepare or Bragg disks; ellipse, ptychography, and detailed
     reconstruction diagnostics use progressive disclosure.
  4. `UI/ProductWorkspaceViews.swift` supplies the redesigned welcome screen,
     contextual header/progress/cancel surface, and first-class Results
     workspace with a large viewer, correct identity/units, PNG/session actions,
     saved-result browsing/removal, and validated control rehydration.
  5. The shell respects system appearance, hides the technical log by default,
     supports Cmd-1…5 workspace navigation and focused-window execution, and
     retains actionable errors, scalable panes, VoiceOver labels/hints, and
     independent dataset windows. Navigation preserves the identity and
     persistence metadata of the still-visible result until a new task
     publishes, preventing stale-result mislabeling or wrong sidecar provenance.
  6. `ProductWorkflowTests` adds five usability/architecture contracts for
     routing, labels/defaults, actionable prerequisites, recommended flow, and
     result identity across navigation. The fast suite is now thirteen methods.
     README and v1 scope describe the shipped product model instead of the
     retired toolbar-mode UI.

- **Hands-on Release workflow audit (product-hardening checkpoint 1,
  2026-07-14):**
  - Granted Accessibility and Screen Recording control was used to launch a
    separate Release app, open the real ignored `058` fixture through the native
    importer, and operate the visible Prepare/Image/Map/Reconstruct/Results flow.
    The user's Debug session and source dataset were not modified.
  - Measured M3 wall-clock baselines were roughly 5 s for open plus the initial
    330×330 virtual image, 15 s for 725,401 parabolic Bragg peaks, 5–7 s for
    R–Q rotation, 3 s for DPC, 2 s for robust strain, and 94 s for the full
    108,900-position/400-template Accelerate ACOM match. Release ACOM averaged
    about 1,150 positions/s versus the reported 9.8 positions/s under Xcode's
    `-Onone` Debug build.
  - The audit reproduced the main UX defects instead of inferring them from
    code: task actions remain enabled under global "complete calibration"
    warnings; ACOM has no preview, quality choice, backend label, or preflight
    ETA; progress is duplicated and visibly stale; stale inputs/results dominate
    the canvas while work runs; the technical inspector/output consume first-run
    space; sidebar subtitles clip; and selecting strain changes the CBED pane to
    the result's RdBu colormap.
  - The file importer accepts unrelated PNG files because `.data` is included in
    its allowed types. A raw `CODE_SIGNING_ALLOWED=NO` Release app is also killed
    when it first `dlopen`s HDF5 on the checkpoint macOS build; an ad-hoc-signed
    audit copy works, matching the repository package audit's signed-library
    contract. These are developer/product workflow findings, not scientific
    failures.

- **Optimized execution and task-readiness remediation (product-hardening
  checkpoint 2, 2026-07-14):**
  - The application target now compiles with `-O` in Debug, eliminating the
    roughly 100× interactive ACOM penalty observed under `-Onone`; the project
    and test target retain normal Debug settings so tests and supporting code
    remain inspectable.
  - ACOM exposes Automatic / Accelerate CPU / Metal choices and states the
    effective backend before execution. Automatic intentionally resolves to the
    measured CPU path until the real-dataset Metal comparison proves otherwise.
  - Workspace gating is task-specific: DPC remains available with explicit
    qualitative-output guidance, strain and ACOM require detected Bragg vectors,
    ACOM treats missing Q calibration as quality guidance, and ptychography lists
    its actual origin/rotation/Q/R/voltage requirements. Actions and warnings no
    longer contradict one another.
  - Diffraction and scalar-result colormaps are independent, so selecting strain
    no longer recolors CBED. The native importer no longer advertises the generic
    `.data` type and therefore cannot route unrelated PNGs into the HDF5 reader.
  - The thirteen fast XCTest methods pass after this checkpoint, including the
    updated workflow-readiness contracts.

- **Bounded ACOM interaction model (product-hardening checkpoint 3,
  2026-07-14):**
  - Orientation no longer starts as an all-or-nothing whole-scan operation.
    Preview samples at most 32×32 representative scan positions and expands
    coarse blocks across the native scan geometry; Selected Region matches the
    visible square around the chosen scan point at full spatial resolution; Full
    Scan remains the explicit production path.
  - Fast / Balanced / Best quality presets request 96 / 200 / 400 orientation
    templates. Balanced is the product default. Changing future settings only
    invalidates the cached plan and no longer silently discards or relabels the
    still-visible previous result.
  - The tools panel reports positions × templates and a preflight estimate from
    the measured M3 Release baseline, then learns backend- and template-adjusted
    throughput from the completed run. Preview and region products carry
    distinct display names plus scope, quality, backend, template count, and
    matched-position provenance in the session sidecar.
  - Duplicate progress/cancel controls were removed from the technical
    inspector; the task header is now the one canonical operation surface, while
    the inspector retains elapsed time, throughput, ETA, memory, and GPU budget.
  - Three new selection/quality XCTests cover preview bounds and expansion,
    edge-clipped regions, and increasing template budgets. All sixteen fast
    methods pass.

- **Real-data ACOM backend and scheduler checkpoint (product-hardening
  checkpoint 4, 2026-07-14):**
  - `tools/real-acom-benchmark/` compiles the production dynamic HDF5 reader,
    tiled origin calibration, Bragg detector, known-crystal Q calibration,
    template generator, and CPU/Metal matchers around the ignored real `058`
    dataset. It defaults to the bounded product preview and supports full scope
    plus configurable template/preview budgets through environment variables.
  - On the checkpoint M3, 900 real positions × 200 templates measured 0.317 s
    CPU and 0.270 s Metal. Sustained full-scan work measured 50.8 s on the
    optimized CPU path and 59.2 s on Metal. All 108,900 template choices and
    recovered angle bins agreed exactly; maximum score and reliability errors
    were 2.84e-7 and 3.46e-6.
  - Full CPU work is now flattened across workers instead of assigning complete
    scan rows, and progress locks are aggregated in batches. On the same heated
    full-scan sequence this reduced the former 65.6 s row-scheduled path by
    about 23%. Automatic remains the verified CPU backend, while Metal remains
    explicit and parity-tested.
  - Preview and region runs now apply origin/ellipse vector transforms only to
    selected positions. Best-quality numerical matching is unchanged; Fast and
    Balanced reduce the explicit template budget rather than silently changing
    the Best algorithm.

- **Deterministic native workflow gate (product-hardening checkpoint 5,
  2026-07-14):**
  - `DemoFourDDataSource` is a calibrated, deterministic 12×12×64×64 in-memory
    fixture available only behind the `--demo-fixture` launch argument. It
    performs no source-file or session-sidecar I/O and gives UI automation a
    repeatable scientific workflow.
  - Stable accessibility identifiers cover the dataset card, workspaces,
    tasks, primary action, ACOM scope, status, result title, and result viewer.
    `tools/ui-smoke-test/run.sh` builds/ad-hoc-signs an isolated app and drives
    Demo → Map → Bragg disks → ACOM preview → Results with native Accessibility,
    then captures `/tmp/mac4dstem-ui-smoke.png` for visual inspection.
  - The smoke passes under the granted permissions. A production-level XCTest
    independently checks that the fixture produces multiple detected peaks,
    valid matched orientations, and nonzero scores. The fast suite is now
    eighteen methods.
  - Final verification: all eighteen XCTest methods and all 22 portable
    scientific/interoperability harnesses pass; the standalone hardened Release
    package audit passes; the native UI smoke passes. Locally available real
    fixtures `058` and `060` pass in 2.03 s and 2.07 s. The aggregate real-data
    command intentionally stops at its four-file manifest check because ignored
    `056` and `057` HDF5 inputs are absent; the gate was not weakened to hide
    missing acceptance data.

## 4. Roadmap order

1. Reliable loading/calibration baseline — complete
2. Virtual-imaging parity against py4DSTEM — complete
3. Origin-map import and ellipse correction — complete
4. Single-pattern Bragg disk parity and parameter semantics — complete
5. Live peak-overlay correctness and refinement — complete
6. ACOM Euler matrix/angle output plus cubic symmetry/IPF — complete
7. Cooperative cancellation for long-running analyses — complete
8. EMD-compatible result persistence/export — BraggVectors, named scalar
   RealSlices, RGBA Arrays, full supported calibration, deterministic reopen,
   selection/removal, external-object preservation, and inspector inventory
   complete; retained-history plots are native, while EMD plot-node creation
   remains
9. Out-of-core execution — complete for current whole-scan workflows; further
   Metal/MLX acceleration remains

Completed parity sequence: virtual-imaging parity → read origin maps →
single-pattern disk parity → peak-overlay refinements → ACOM Euler angles →
cooperative cancellation → BraggVectors EMD export → scalar RealSlice session
save/reopen → named multi-map manifest and inspector inventory → session
calibration round-trip → cubic ACOM symmetry and IPF-Z coloring → bounded
out-of-core execution → ellipse-corrected vectors → controlled strain
reference/basis → cubic FZ templates/Q calibration/measured probe → physical
DPC and per-view gamma → RGBA session arrays/result management → Gaussian disk
parity → calibrated preprocessing export/UI → native-shape disk DFT → external
EMD-object preservation → in-app ellipse measurement → guided calibration
readiness → parallax preprocessing foundation → integer coarse alignment →
factor-8 coarse-to-fine continuation → low-order aberration fit → default
higher-order recursive fit → aberration-corrected phase → bilinear/Lanczos KDE
subpixel reconstruction → iterative probe-position correction → depth sectioning
and reusable parallax product selection → single-slice ptychographic GD →
schema-v4 stabilized-result persistence → ptychographic object/probe constraints
and diagnostics → retained-exit-wave DM/AP reconstruction → quantitative iDPC
with explicit boundary/fallback provenance → consensus and robust-reference
strain fitting with persisted diagnostics → bounded asymmetric-Gaussian ellipse
profile refinement with safe conic fallback.

## 5. Current next slice

Post-v1 Roadmap Phases 1–6 are locally complete as of 2026-07-14. The frozen
`docs/v1-scope.md` contract is unchanged. The implementation adds the shared Prepare
readiness path, explicit invalid strain, an immutable displayed-product contract,
cursor/quality inspection, fitted scientific overlays, persistent scan navigation,
action-to-publication ACOM timing, semantic saved-product comparison, publication PNG,
and atomic coherent strain/orientation EMD bundles. Phase 7 remains a demand gate.

Verification added/extended here covers typed masks/domains/units/quality/cursor,
compatible and rejected differences, residual/indexed strain, canonical `Å⁻¹`
reconstruction calibration, native uncalibrated and all-workspace demo paths,
fit-overlay perturbations, atomic bundle cancellation, and direct py4DSTEM RealSlice
readback. The closing `tools/run-tests.sh all` command exited zero: all 25 XCTest
methods, all 24 standalone scientific/interoperability harnesses, all seven locally
available HDF5 goldens, and the isolated hardened Release package audit passed. The
real-data timings were 5.69/0.36/1.39/1.36/0.89/0.33/1.14 s, each below the 15 s/file
gate. The simulated-Au reader prints diagnostics while its canonical-path probes miss,
then succeeds through deterministic dataset discovery and passes its golden.

Checkpoint M3 end-to-end evidence: native demo readiness 11 s; Image 5 s, DPC 4 s,
Bragg 4 s, strain 5 s, ACOM 5 s, reconstruction 6 s. On real `058`, balanced ACOM
Preview was 0.73 s action-to-result; balanced full scan was 64.79 s CPU and 91.26 s
Metal for 108,900 positions, with exact template/angle parity and <3.5×10⁻⁶ maximum
score/reliability drift. The recorded evidence revises the provisional full-scan budget
from 60 to 70 s and retains Accelerate CPU as Automatic.

The completed native pass also published a non-empty first session sidecar and left
the scan navigator and export-bundle controls visible in the captured Results screen.
A publication-figure XCTest independently gates exact pixel dimensions, title/caption
ink, the calibrated scale bar, and colorbar diversity. It caught `NSImage.lockFocus()`
using the active display's 2× Retina backing scale; export now renders through an
explicit one-point-per-pixel bitmap and is display-independent.
A closing repeat after adding explicit accessibility waits built successfully but was
blocked before `dataset.card`: the Codex desktop host retained foreground ownership,
the app remained healthy in `NSApplication.run` but had zero windows/no CoreGraphics
connection, and Finder, System Events, and direct AppKit activation were all refused.
That repeat is not claimed as passed. `tools/ui-smoke-test/run.sh` now clears only its
disposable bundle's saved window frame and preserves the calibration-launch log on
failure; rerun it from a normal Accessibility-authorized Terminal GUI session.

The next repository work must come from demonstrated demand or an observed failure.
External follow-ups are: 3–5 microscopist usability sessions at the Phase 1/3/5
observation gates; real vendor MIB/EMPAD acquisitions beyond synthetic fixtures;
Developer ID/notarization credentials and a clean-account notarized-app smoke; and
performance confirmation on additional Mac classes. The native smoke repeat above is
also a hands-on environment check, not an implementation item. Preserve the CPU
scientific reference and require numeric plus failure parity before changing Automatic
to an accelerated backend.

### Prior checkpoint log

No repository-owned v1 implementation slice remains after the final aggregate gate.
The release owner must install/select a Developer ID Application certificate and
notarytool profile, run the documented scripts in `docs/releasing.md`, preserve the
submission log/hash, and smoke-test the notarized ZIP on a clean macOS 14+ account.

Product-redesign verification on 2026-07-14: all eighteen XCTest methods and all
22 standalone scientific/interoperability harnesses pass; the hardened Release
package audit passes; and the 14-workload schema-v2 benchmark reproduces valid
checksums. The two currently present ignored real-data files (`058`, `060`) pass
their 330×330×64×64 goldens in 1.47/1.12 seconds. The aggregate runner then reports
2 versus 4 expected files because `056` and `057` are absent from
`References/training_dataset/`; restore those local files to rerun the complete
four-file acceptance campaign. This is an input-corpus absence, not a numeric
failure. The pre-existing modified Xcode user-interface-state file is user-owned
and must remain excluded from implementation edits.

For the next agent: preserve `WorkspaceArea` as the product navigation boundary,
keep whole-scan work behind `runPrimaryWorkspaceTask()`, and keep Preview as the
safe ACOM default. Do not restore the global analysis-mode strip or task-switch
auto-run. The five-checkpoint hands-on hardening sequence is complete; future UX
work should start from a new observed real-user failure, especially in the
Advanced reconstruction workflow, and extend the deterministic demo/native smoke
instead of returning to a broad control inventory.

Hands-on hardening checkpoint 6 — Debug HDF5 signing repair — is complete.
`tools/run-tests.sh unit` previously wrote an unsigned test product into Xcode's
normal DerivedData. That could replace the app or one of its lazily loaded dylibs
beneath an interactive run. A clean reproduction also exposed the underlying
configuration gap: without a selected development team, Xcode ad-hoc-signed the
app and HDF5 closure separately while Debug still requested Hardened Runtime
library validation. macOS then rejected `libhdf5.dylib` with “mapping process and
mapped file have different Team IDs.” Debug now leaves Hardened Runtime off for
credential-free local launches; Release remains hardened. The unit runner uses a
disposable DerivedData directory and redirects LLVM profile output there.

Verification used the ordinary Xcode Debug product, not a package-test copy. A
clean build passed deep signature verification and imported
`058_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5` through the native file
panel. The XCTest suite then passed while that app remained open; SHA-256
hashes for the app executable and bundled `libhdf5.dylib` were identical before
and after the run, no `default.profraw` appeared in the repository, and the same
real dataset reopened successfully. `tools/ui-smoke-test/import-real.applescript`
is the reusable Accessibility probe for this exact launch/import boundary.

For the next agent: never use `CODE_SIGNING_ALLOWED=NO` for an app product that a
person will launch, and never point unsigned tests at normal DerivedData. Use the
aggregate runner, which now owns an isolated test build. Preserve the Debug-off /
Release-on Hardened Runtime split unless the project gains a mandatory configured
development team and a test proves the nested HDF5 identities match.

Hands-on hardening checkpoint 7 — first session save and ACOM region canvas —
is complete. The first Save-panel selection used to call
`bookmarkData(.withSecurityScope)` before the selected sidecar existed, so the
save aborted with Cocoa “no such file.” The selected URL is now kept under its
live security scope, the writer atomically publishes the sidecar, and only then
does the app persist/refresh the bookmark. A post-publication bookmark failure
is reported accurately as a future-relaunch warning rather than claiming the
already-written scientific result was not saved.

ACOM selected-region setup no longer draws a scan ROI over the reciprocal-space
Bragg-vector histogram. The app retains that 256×256 (or detector-sized) Bragg
map as the scientific result while the Map canvas temporarily presents the last
scan-sized virtual image; recovered sessions with no cached navigation image
form a quiet ADF reference on demand. The orange rectangle, crosshair, click
mapping, real-space scale, and summed-region CBED now share that scan coordinate
system. Results/export/session persistence still see the retained Bragg map,
whose scale metadata is reciprocal rather than nanometres.

The product suite is now 18 XCTest methods; the new contract verifies a
153×106 region canvas can coexist with a retained 256×256 Bragg map. The native
Accessibility smoke now gives its isolated build a distinct bundle identity,
publishes and verifies a non-empty brand-new session sidecar before continuing through
Bragg detection, ACOM preview, and Results. That smoke and all sidecar
round-trip/atomic-replacement/py4DSTEM interoperability cases pass.

The outcome-based UI/accessibility checkpoint is complete. Ptychography/parallax is
the Advanced **Reconstruct** workspace rather than a peer in a global mode strip.
Prepare/Image/Map/Reconstruct/Results navigation, focused-window Run/Cancel and
Cmd-1…5 commands, actionable Copy Details/Open Another errors, correct result
identity, cubic/hexagonal in-canvas IPF keys, labeled image panes, accessible
histogram controls, and adjustable histories cover the primary keyboard/VoiceOver
workflow. The macOS 14 deployment floor compiles and all eighteen XCTest methods pass.

Real-data acceptance is complete across all four checked-in 1–1.7 GB HDF5 datasets.
`tools/real-data-acceptance` performs dynamic discovery, samples first/middle/last
patterns, and runs a complete one-row-tiled production Metal virtual image. Shapes,
finite fraction, min/max/mean/checksum goldens, and a 15-second/file ceiling are
checked; the 2026-07-14 M3 run took 1.1–1.4 seconds per file.

Credential-free distribution hardening is complete. The app now uses stable bundle
ID `com.paullobpreis.mac4DSTEM`, version/build 1.0/1, macOS 14 minimum, copyright,
hardened runtime, sandbox/bookmarks, and an app icon. The Release audit verifies all
of these plus nested signatures, entitlements, bundled HDF5 closure, and absence of
machine-local dylib paths. `tools/release` contains Developer ID archive and
notarytool/staple/Gatekeeper scripts; only certificate/profile-backed execution is
external.

The pre-redesign final repository gate passed on 2026-07-14: all eight then-current
XCTest methods, all 22
scientific/interoperability harnesses, the four full real-data goldens, and the
hardened Release package audit completed through `tools/run-tests.sh all`.
The follow-up performance baseline reproduced every checksum; representative M3
medians were 24.27 ms for 48-position/400-template ACOM CPU matching, 14.02 ms
for 24-pattern disk detection, 29.08/37.99 ms for medium GD/DM-AP ptychography,
and 0.87 ms for selected-area diffraction. Automatic ACOM remains Accelerate CPU;
the direct-IDFT Metal median was 59.16 ms in this final run.

The dataset-session foundation is complete. `DatasetWindow` owns one `AppState`
inside each `WindowGroup` instance, while focused-scene command routing targets the
active window and Command-N creates an independent dataset window. The recent/
recovery store persists security-scoped bookmarks, selected scan position, and task
only; scientific products stay in source/session files. The welcome screen offers
Open, Reopen Last, and removable Recents. Replacement opening is transactional:
the prior security scope/session remains alive until the new reader and descriptor
are valid, and failed opens preserve the current dataset. The earlier four-step
checklist is replaced by the five outcome workspaces described above. Two
recovery-model XCTests remain part of the eighteen-method suite; all pass with the
Debug build on 2026-07-14.

The direct-reader/interoperability checkpoint is complete for its frozen subsets.
`EMPADReader` accepts vendor XML plus little-endian 130×128 float32 raw frames,
crops the two footer rows, validates exact file size, and permits raw-only input
only for an unambiguous square scan. `MIBReader` accepts regular per-frame U08,
U16, and U32 big-endian MIB for 1x1/2x2/2x2G assemblies and requires a companion
`.hdr` with positive ScanX/ScanY; packed R64 is rejected with conversion guidance.
Both stream rows/tiles through `FourDDataSource`. The byte-level harness gates
endianness, frame headers/footer, scan order, and ambiguity errors. H5Reader now
falls back to HDF5 link traversal and deterministically discovers arbitrary EMD
root names; the calibration harness covers that route. Debug build and focused
format/calibration regressions pass on 2026-07-14.

Non-cubic ACOM correctness is complete. `Crystal.magnesium` supplies a conventional
HCP cell, `HexagonalOrientationSymmetry` implements the 12 proper rotations of
6/mmm, and plan sampling/reduction/IPF-Z use a deterministic upper 0…30° sector.
The UI and persistence record the symmetry and use a native dependency-free
[0001]/[10-10]/[11-20] key (explicitly not claimed as an orix color golden).
Changing a crystal or custom-cell parameter invalidates stale plans/maps, and the
matcher now derives symmetry from the immutable plan so callers cannot mismatch
them. Full-group, full-orbit, sector, color-invariance, non-cubic plan/matching,
the then-current XCTest suite, and Debug compilation gates pass on 2026-07-14.

Polished-v1 checkpoint 1 is complete: `docs/v1-scope.md` defines the core
open→calibrate→analyze→save/reopen workflow, stable and Advanced feature tiers,
post-v1 exclusions, and correctness/performance/reliability/interoperability/
accessibility/distribution gates. Parallax and ptychography remain available
but are explicitly Advanced rather than expanding the stable-core release gate.

All repository-owned polished-v1 phases are complete: architecture/testing,
ptychography completeness, measured performance, the four scientific-correctness
checkpoints, selected readers/EMD discovery, multi-window UI/accessibility, the
checked-in HDF5 real-data corpus, and credential-free distribution hardening.
MIB/EMPAD remain explicitly fixture-validated Preview readers until the release
owner supplies redistributable/locally testable real vendor acquisitions. Public
distribution still requires the credential owner to execute Developer ID signing,
notarization/stapling, and a clean-account smoke test.

## 6. Scientific conventions and risks

- Highest risk: py4DSTEM patterns use (qx, qy) with qx on the first/row axis;
  this app stores [Ry, Rx, Qy, Qx]. Thus py4DSTEM qx ↔ app y and qy ↔ app x.
- Parallax is complete through depth sectioning/product selection. Single-slice
  complex-object GD and DM/AP, object/probe constraints, diagnostics, persistence,
  browsing, and control rehydration are integrated with explicit memory and
  cancellation boundaries. Further methods and GPU batching remain.
- Ellipse keys `a`/`b`/`theta` can be imported or fitted from a broad-coverage
  detector ring. The bounded 11-parameter asymmetric-Gaussian/Janus profile uses
  the conic as an initializer and retains a residual-gated conic fallback.
- Disk parity covers native radix-2 and non-radix-2 circular correlation plus
  nonzero `sigma_cc` and SciPy-reflect smoothing. Unsupported vDSP DFT lengths
  use an exact scalar fallback, which is correct but can be slow for large
  prime detector axes.
- Virtual detector annuli use py4DSTEM's strict `rIn² < r² < rOut²`; circles
  use `r² < rOut²` and therefore include a centered pixel.
- ACOM in-plane angle is mod 180° (Friedel). FCC/BCC/SC/diamond choices use
  cubic reduction/IPF-Z and HCP magnesium uses the proper 6/mmm rotational
  subgroup plus the documented native key. Further crystal families need an
  explicit symmetry implementation rather than an implicit identity fallback.
- Scalar emdfile metadata may be attributes or datasets; H5Reader supports both.
- The current session schema preserves supported BraggVectors plus named scalar
  `RealSlice` and RGBA `Array` nodes listed in its manifest and opaque-copies
  other root objects. Restoring a result restores pixels/label/units; an explicit
  action can additionally apply validated controls, but transient scientific
  arrays and complex reconstructions are deliberately not serialized.
- Session calibration overrides only fields present in the companion.
- Default actor isolation is MainActor; new compute types need `nonisolated`.

## 7. Verification commands

- Launchable Debug build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -configuration Debug -destination 'platform=macOS' build -quiet`
- Calibration: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/calibration-test/run.sh`
- Virtual detector: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/virtual-detector-test/run.sh`
- Disk detection: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/disk-detection-test/run.sh`
- Peak overlay: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/peak-overlay-test/run.sh`
- ACOM orientation: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/acom-orientation-test/run.sh`
- Cancellation: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/cancellation-test/run.sh`
- BraggVectors export: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/bragg-export-test/run.sh`
- Scalar result sidecar: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/sidecar-result-test/run.sh`
- Result presentation: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/result-presentation-test/run.sh`
- Scientific bundle: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/scientific-bundle-test/run.sh`
- Performance baseline: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/run-tests.sh benchmark`
- Real ACOM CPU/Metal: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/real-acom-benchmark/run.sh`
- Native UI smoke (Accessibility permission): `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/ui-smoke-test/run.sh`
- Strain/Q/DPC: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/strain-test/run.sh`
- Quantitative iDPC: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/idpc-test/run.sh`
- Ellipse calibration: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/ellipse-calibration-test/run.sh`
- Preprocessing export: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/preprocessing-export-test/run.sh`
- Release package: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/package-test/run.sh`
- Fast tests: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/run-tests.sh unit`
- All layers: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/run-tests.sh all`
- XCTest complements rather than replaces the cross-language harnesses under `tools/`.

## 8. Preserve unless directly relevant

- Treat `References/`, repo-root dylibs, `project.pbxproj`, and `*.xcuserstate`
  as read-only. Harnesses copy and ad-hoc-sign dylibs rather than modifying them.
- Before finishing: run verification, update completed work and next slice here,
  and use actual reference source for any disputed py4DSTEM behavior.
