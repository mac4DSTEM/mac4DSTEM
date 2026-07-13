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
  file-provided qx0/qy0 mean, fitted in-app, or manually moved.
- Known incomplete: ACOM Euler output is `.zero`; ellipse values are read but
  not applied; per-position qx0/qy0 maps are not read; no EMD writer. Two
  standalone harnesses cover calibration import and virtual detectors.

## 3. Completed slices

- H5Reader reads calibration metadata from HDF5 attributes and datasets,
  including UTF-8 strings, bool-enum `QR_flip`, Q/R pixel sizes and units,
  `qx0_mean`/`qy0_mean`, and ellipse `a`/`b`/`theta`.
- `tools/calibration-test/` verifies attribute-form, dataset-form, and
  `real_py4dstem.h5` written by py4DSTEM 0.14.19. It asserts all ten values;
  run result on 2026-07-13: all passed.
- DM4Reader and compute code are clean under the project's approachable
  concurrency settings; pure compute types are explicitly `nonisolated`.
- `AppState.activate` consumes file qx0/qy0 means as the initial aperture
  center. AXIS SWAP occurs only there: app x = py4DSTEM qy0, app y = qx0.
  It does not synthesize per-position `Calibration.origin` maps.
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

## 4. Roadmap order

1. Reliable loading/calibration baseline — complete
2. Virtual-imaging parity against py4DSTEM — complete
3. Origin-map import and ellipse correction — ACTIVE
4. Bragg disk parity and parameter-semantics mapping
5. ACOM completion: Euler angles, symmetry handling, QC/IPF display
6. EMD-compatible result persistence/export
7. Out-of-core execution and Metal/MLX acceleration after parity validation

Near-term slice sequence: virtual-imaging parity → read origin maps →
single-pattern disk parity → peak-overlay refinements → ACOM Euler angles →
disk cancellation → Bragg vectors EMD export.

## 5. Current next slice

Import fitted per-position `qx0`/`qy0` maps from py4DSTEM EMD calibration
bundles and use them as `Calibration.origin` without rerunning calibration.
First verify the exact on-disk array names, shapes and axis order by generating
or inspecting a real py4DSTEM 0.14 fixture; do not infer them from the mean
keys. Extend `PixelCalibration` and H5Reader to return fitted maps only when
both arrays exist, are rank 2, have the scan shape, and contain finite values.

Convert py4DSTEM's detector axes in one documented place: qx0 → app y,
qy0 → app x. Confirm whether the stored real-space array order is already
[Ry,Rx] before flattening. On activation, populate an `OriginMaps` whose fitted
arrays come from file; do not claim measured values exist unless corresponding
`qx0_meas`/`qy0_meas` arrays are actually present. Preserve `.fileMean` for
mean-only files and introduce a distinct file-map provenance label if useful.

Extend the calibration harness with non-square scan maps whose values make both
real-space transposition and detector-axis swaps obvious. Acceptance: all map
values and means verified, app build and both existing harnesses green, and
mean-only fixtures retain their current behavior. Ellipse application remains
a separate follow-up unless this slice exposes a required shared transform.

## 6. Scientific conventions and risks

- Highest risk: py4DSTEM patterns use (qx, qy) with qx on the first/row axis;
  this app stores [Ry, Rx, Qy, Qx]. Thus py4DSTEM qx ↔ app y and qy ↔ app x.
- Ellipse keys `a`/`b`/`theta` were verified against py4DSTEM 0.14.19 and a
  real file. The values are not yet measured or applied by the app.
- Virtual detector annuli use py4DSTEM's strict `rIn² < r² < rOut²`; circles
  use `r² < rOut²` and therefore include a centered pixel.
- ACOM in-plane angle is mod 180° (Friedel); Euler output is placeholder.
- Scalar emdfile metadata may be attributes or datasets; H5Reader supports both.
- Default actor isolation is MainActor; new compute types need `nonisolated`.

## 7. Verification commands

- Build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet`
- Calibration: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/calibration-test/run.sh`
- Virtual detector: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer tools/virtual-detector-test/run.sh`
- No XCTest target exists; standalone harnesses live under `tools/`.

## 8. Preserve unless directly relevant

- Treat `References/`, repo-root dylibs, `project.pbxproj`, and `*.xcuserstate`
  as read-only. Harnesses copy and ad-hoc-sign dylibs rather than modifying them.
- Before finishing: run verification, update completed work and next slice here,
  and use actual reference source for any disputed py4DSTEM behavior.
