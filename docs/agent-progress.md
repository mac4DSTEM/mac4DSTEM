# Agent progress — mac4DSTEM

Persistent handoff between agent sessions. Read this INSTEAD of re-mapping the
repository. Update it at the end of every session (append to "Completed
slices", update "Current next slice"). Keep it concise.

## 1. Project goal

Native macOS Swift/SwiftUI/Metal app for 4D-STEM analysis. Scientific
reference: py4DSTEM (source checkout in `References/py4DSTEM-dev`). Work
proceeds in small, buildable, scientifically safe slices. Priorities:
correctness/py4DSTEM parity > buildability > loading/calibration > virtual
imaging > disk detection > ACOM > Metal/MLX performance > SwiftUI polish.

## 2. Current confirmed state (2026-07-09)

- Loads HDF5/EMD (`Core/Data/H5Reader.swift`, dlopen'd bundled libhdf5) and
  Gatan DM4/DM3 (`Core/Data/DM4Reader.swift`), behind the `FourDDataSource`
  actor protocol.
- Working analysis surface (see `App/AppState.swift` func list): virtual
  imaging/diffraction (Metal, `Shaders/*.metal`), DP statistics, origin +
  rotation calibration, DPC, probe kernel, Bragg disk detection (CPU,
  multi-worker), strain mapping, template-matching ACOM.
- Known incomplete: ACOM `OrientationResult.euler` is a `.zero` placeholder;
  ellipse calibration is read but never measured/applied; per-position origin
  maps (`qx0`/`qy0` arrays) not read; no EMD writing; only one test
  (calibration harness).
- Build is clean: zero Swift warnings on a full clean build (Swift 6
  concurrency issues resolved).

## 3. Completed slices

- H5Reader reads py4DSTEM/EMD calibration metadata from both datasets and
  HDF5 group attributes (emdfile `Metadata.to_h5` writes scalars/strings as
  attributes).
- Calibration regression harness exists: `tools/calibration-test/`
  (C fixture generator + standalone Swift harness compiling H5Reader
  unchanged; two fixtures: attribute-form and dataset-form).
- QR_flip handling verified: h5py stores Python bools as int8-based enum
  {FALSE,TRUE}; read via `readIntAttribute` (HDF5 converts enum→int, never
  enum→double). Verified against hand-built enum fixtures.
- UTF-8 HDF5 string reading fixed: `readStringValue` uses a copy of the
  file's own string type (HDF5 has no UTF-8↔ASCII conversion path; h5py
  writes UTF-8).
- py4DSTEM origin/ellipse scalar keys (`qx0_mean`, `qy0_mean`, `a`, `b`,
  `theta`) are read into `PixelCalibration` (kept in py4DSTEM's axis frame,
  NOT yet consumed by the app — see conventions below).
- DM4Reader Swift 6 actor-isolation warning fixed (async init; `ByteReader`
  marked nonisolated).
- AppState/compute-layer Swift 6 warnings fixed: weak-self captures moved to
  inner @MainActor tasks; ~13 pure-value compute types marked `nonisolated`
  (OrientationPlan, Crystal, ScatteringFactors, CubeDims, VirtualDetector,
  OriginCalibration, etc.).
- Full clean build succeeds with zero Swift warnings.

## 4. Current roadmap order

1. Reliable loading/calibration (real-file verification) ← ACTIVE
2. Virtual imaging parity (numeric diff vs py4DSTEM)
3. Bragg disk detection parity (parameter-semantics mapping)
4. Origin/ellipse correction (consume mean origin; read origin maps; ellipse)
5. ACOM completion (real Euler angles, QC display)
6. Export/reporting (EMD writer py4DSTEM can re-open)
7. Metal/MLX acceleration (only after CPU paths are parity-validated)

Agreed next ~10 slices (from roadmap session): real py4DSTEM fixture →
consume mean origin in AppState → calibration provenance UI → virtual-imaging
parity script → read origin maps → single-pattern disk parity → peak overlay
UI → ACOM Euler angles → cancel for disk detection → Bragg vectors EMD export.

## 5. Current next slice

Create a real py4DSTEM-written minimal EMD/HDF5 fixture and add it to the
calibration verification flow. Plan: python venv with
`References/py4DSTEM-dev` installed (+h5py/numpy), script writes a tiny
calibrated DataCube to EMD, then run `tools/calibration-test` harness (or an
extended run.sh step) against it. This replaces hand-built-fixture
assumptions (emdfile layout, key names `a`/`b`/`theta`) with ground truth.

## 6. Important scientific conventions/risks

- **AXIS CONVENTION (highest risk in project):** py4DSTEM indexes patterns
  (qx, qy) with qx along the FIRST (row) axis; this app uses [Ry, Rx, Qy, Qx]
  with Qy as the row axis. So py4DSTEM qx0 ↔ app detector y, qy0 ↔ app x.
  `PixelCalibration.qx0Mean/qy0Mean` are stored in py4DSTEM's frame; convert
  at point of use, in exactly one documented place.
- Ellipse key names `a`/`b`/`theta` match py4DSTEM to best knowledge but are
  UNVERIFIED against a real py4DSTEM-written file (next slice fixes this).
- Virtual detector masks use py4DSTEM's half-open convention rIn² ≤ r² < rOut².
- ACOM in-plane angle is mod 180° (Friedel); euler output is placeholder —
  treat ACOM results as indicative, not validated.
- emdfile Metadata: scalars/strings are HDF5 *attributes* on the calibration
  group; arrays are datasets. Loader supports both forms.
- Module compiles with main-actor default isolation: new compute types need
  explicit `nonisolated` or they silently become @MainActor.

## 7. Build/test commands

- Xcode is Xcode-beta; the CLI needs:
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- Build: `DEVELOPER_DIR=... xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -configuration Debug build -quiet`
- Calibration regression test: `DEVELOPER_DIR=... tools/calibration-test/run.sh`
  (builds fixtures with the repo's libhdf5, compiles H5Reader standalone,
  asserts all calibration values; ad-hoc re-signs dylib copies in a temp dir
  because the bundled dylibs' signatures don't validate for local tools).
- No XCTest target exists; tests are standalone harnesses under `tools/`.
- Warning check after concurrency-related edits: append
  `2>&1 | grep ".swift.*warning"` to a clean build.

## 8. Files not to touch unless relevant

- `References/` (py4DSTEM source, migration source, training data) — read-only
  reference material.
- `mac4DSTEM.xcodeproj/` internals, especially `project.pbxproj` (no test
  target on purpose; adding files to the app target requires pbxproj edits —
  avoid; `tools/` harnesses deliberately live outside the target).
- `libhdf5.dylib`, `libsz.2.dylib`, `libaec.0.dylib` at repo root — do not
  re-sign or modify in place (tools copy + ad-hoc sign instead).
- `*.xcuserstate` — user state, churns on its own.

## 9. Resume instructions for future agents

1. Read this file; do NOT re-map the repository.
2. Confirm build health cheaply: run the build command in §7 (expect zero
   warnings) and `tools/calibration-test/run.sh` (expect "all passed").
3. Implement the single slice in §5. Keep it small enough that the app builds
   after the change. Prefer extending `tools/` harnesses over touching the
   Xcode target.
4. If a py4DSTEM behavior is in question, read the actual source under
   `References/py4DSTEM-dev` rather than relying on memory; mark anything
   still unverified as UNVERIFIED here.
5. Before ending the session: update §3 (append), §5 (new next slice), and
   any §6 risks resolved or discovered. Keep this file under ~120 lines.
