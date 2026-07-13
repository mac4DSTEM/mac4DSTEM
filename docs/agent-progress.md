# Agent progress — mac4DSTEM

Persistent handoff between agent sessions. Read this before remapping the repo.
At the end of a session, append completed work and replace the next slice.

## 1. Goal and priorities

Native macOS Swift/SwiftUI/Metal app matching scientifically important
py4DSTEM workflows with a polished, interactive Mac UI. Reference source:
`References/py4DSTEM-dev` (read-only). Priorities are numeric correctness and
py4DSTEM parity, then buildability, workflow coverage, performance, and polish.
Work in small slices that end with a green build and targeted verification.

## 2. Confirmed state (2026-07-13)

- HDF5/EMD (`H5Reader`) and DM3/DM4 (`DM4Reader`) load behind the actor-based
  `FourDDataSource` protocol. The full app builds cleanly with Xcode-beta.
- Working surface: virtual imaging/diffraction, DP statistics, origin and R–Q
  calibration, DPC/iDPC, probe kernel and Bragg disk detection, strain, and
  simplified polar-correlation ACOM.
- The Calibration UI now identifies the aperture center as geometric default,
  file-provided qx0/qy0 mean/maps, fitted in-app, or manually moved.
- Known incomplete: the session sidecar stores scalar/RGBA maps plus full
  supported calibration and preserves unrecognized external root objects, but
  the app does not yet create/view plot nodes or restore the controls behind a
  saved result. Ten scientific harnesses cover calibration, tiled execution,
  disks, overlays, ACOM, strain, cancellation, EMD/session persistence, and
  calibrated preprocessing export.

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
  automatic shortest-vector selection is unreliable. `tools/strain-test/`
  verifies whole-scan and selected references, manual basis validation,
  known-crystal Q calibration, and DPC physical-unit conversion.
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
   complete; native plot creation/viewing remains
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
EMD-object preservation → in-app ellipse measurement.

## 5. Current next slice

Turn the existing calibration operations into a guided preprocess readiness
checklist. It should show origin/probe, ellipse, R-Q rotation, Q pixel scale,
and R pixel scale as measured/imported/manual/missing; offer the correct next
action for each missing item; and launch the existing bounded DataCube export
only after an explicit warning for any intentionally uncalibrated field. Keep
the individual expert controls. Acceptance: readiness resets per dataset,
imported/session values are distinguished from in-app measurements, no step
silently invents calibration, cancellation leaves prior values intact, and a
fixture can traverse the checklist into an exact py4DSTEM export.

## 6. Scientific conventions and risks

- Highest risk: py4DSTEM patterns use (qx, qy) with qx on the first/row axis;
  this app stores [Ry, Rx, Qy, Qx]. Thus py4DSTEM qx ↔ app y and qy ↔ app x.
- Ellipse keys `a`/`b`/`theta` can be imported or fitted from a broad-coverage
  detector ring. The lightweight 1-D conic fit is not the 11-parameter Janus
  Gaussian amorphous-ring model; broad background/overlapping rings may need
  preprocessing or a future full profile fit.
- Disk parity covers native radix-2 and non-radix-2 circular correlation plus
  nonzero `sigma_cc` and SciPy-reflect smoothing. Unsupported vDSP DFT lengths
  use an exact scalar fallback, which is correct but can be slow for large
  prime detector axes.
- Virtual detector annuli use py4DSTEM's strict `rIn² < r² < rOut²`; circles
  use `r² < rOut²` and therefore include a centered pixel.
- ACOM in-plane angle is mod 180° (Friedel). Current FCC/BCC/SC/diamond choices
  use cubic reduction and IPF-Z; future non-cubic crystals must select the
  explicit identity fallback until their point groups are implemented.
- Scalar emdfile metadata may be attributes or datasets; H5Reader supports both.
- The current session schema preserves supported BraggVectors plus named scalar
  `RealSlice` and RGBA `Array` nodes listed in its manifest and opaque-copies
  other root objects. Restoring a result restores pixels/label/units, not the
  complete analysis controls that produced it.
- Session calibration overrides only fields present in the companion.
- Default actor isolation is MainActor; new compute types need `nonisolated`.

## 7. Verification commands

- Build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet`
- Calibration: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/calibration-test/run.sh`
- Virtual detector: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/virtual-detector-test/run.sh`
- Disk detection: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/disk-detection-test/run.sh`
- Peak overlay: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/peak-overlay-test/run.sh`
- ACOM orientation: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/acom-orientation-test/run.sh`
- Cancellation: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/cancellation-test/run.sh`
- BraggVectors export: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/bragg-export-test/run.sh`
- Scalar result sidecar: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/sidecar-result-test/run.sh`
- Strain/Q/DPC: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/strain-test/run.sh`
- Ellipse calibration: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/ellipse-calibration-test/run.sh`
- Preprocessing export: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/preprocessing-export-test/run.sh`
- Release package: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/package-test/run.sh`
- No XCTest target exists; standalone harnesses live under `tools/`.

## 8. Preserve unless directly relevant

- Treat `References/`, repo-root dylibs, `project.pbxproj`, and `*.xcuserstate`
  as read-only. Harnesses copy and ad-hoc-sign dylibs rather than modifying them.
- Before finishing: run verification, update completed work and next slice here,
  and use actual reference source for any disputed py4DSTEM behavior.
