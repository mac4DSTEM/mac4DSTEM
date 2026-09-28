# R–Q rotation in py4DSTEM's convention at the boundary — Gate D, 2026-09-28

Owner decision 2 of ADR 040: the R–Q rotation is displayed and written in py4DSTEM's convention.

## Diagnosis (established 2026-09-23; registered here before any code change)

The app reads a file's axes as (Ry, Rx, Qy, Qx) (`DatasetDescriptor.swift`), and py4DSTEM reads them
as (Rx, Ry, Qx, Qy). Both the scan pair and the detector pair are swapped. A reflection applied to
both spaces conjugates R(θ) to R(−θ). So the **app's internal angle is the negative of py4DSTEM's on
the same file, and the transpose flag is identical.** This was measured by the independent refuter
of `archive/v3/rq-frame-class-2026-09-23.md`:
- planted fields: +25° → app −25.1°; −60° → app +59.9°;
- the real cube `Particle_1_Stack_1…bin8.h5`: py4DSTEM +80.0° T, app −80.1° T.

Today that number crosses every boundary unconverted, while origins and peaks are swapped there.

**Refuting observation:** if a file-faithful py4DSTEM call and the app agreed in sign on an
asymmetric planted field, the diagnosis would be wrong.

## Change

Everything inside the app (DPC, strain frame, ACOM, ptychography, parallax preprocessing) keeps
the app's internal angle. It is self-consistent with the app's axis order, and no number there
moves. The sign flips in exactly one place, a new `RQRotationConvention`
(`RotationCalibration.swift`, with a `DEVIATION` note), used at every boundary.

**Files:**
- **py4DSTEM import:** `QR_rotation` (`AppState+Open`), app = −file.
- **Sidecar write:** `QR_rotation` and `QR_rotation_degrees` in py4DSTEM's convention, plus a new
  `QR_rotation_convention = "py4DSTEM"` string beside them.
- **Sidecar read:** a sidecar with the marker is converted. **One without it is a legacy file
  written in the app's sign, and it is read as-is.**
- **Strain export keys:** `qr_rotation_rad` / `qr_rotation_deg` in py4DSTEM's convention, plus
  `qr_rotation_convention`.

**Display:**
- the Prepare "R–Q rotation" row;
- the readiness detail;
- the "Rotation ✓ θ =" status line;
- the strain frame description;
- the rotation plot's VoiceOver value. That value is in `WorkspaceInspector.swift`, a frozen-shell
  file: it is a string change, and the plot's picture is unchanged.

**Out of scope, recorded:**
- **The parallax fit's own "Fitted rotation".** It is recovered by a py4DSTEM-ported routine
  (`ParallaxAberrationFitting`) whose convention relative to the calibration is untested, and
  parallax is unrunnable on this Mac.
- **`ellipseTheta`.** It needs no conversion: it is stored in py4DSTEM's (qx, qy) frame and applied
  through `ellipseCorrectedOffset`'s explicit axis swap. That is already pinned by
  `ManualEllipseTests`' analytic py4DSTEM-parametrised fixture.

## Predictions

- **P1 file-faithful parity, now gating** (`tools/rotation-parity-test` leg (b)). py4DSTEM's
  frozen curl search is called file-faithfully (axis 0 kept as Rx; `com_x` = the app's `cy`,
  `com_y` = the app's `cx`), on the 40 × 40 direct field, the 40 × 40 transposed field and a new
  40 × 30 non-square field. The expected results are (+37, F), (−37, T) and (+37, F). The app's
  **converted** angle agrees with each within 0.75°, the transpose flag is equal, and the
  **unconverted** angle is off by more than 10° (anti-vacuity).
- **P2 sidecar:** an app θ of 0.6 rad is written as `QR_rotation` = −0.6 with the marker, and reads
  back as 0.6. A legacy sidecar (no marker, `QR_rotation` = 0.6) reads back as 0.6.
- **P3 import:** a py4DSTEM file's `QR_rotation` of φ becomes an app θ of −φ and is displayed as φ.
- **P4 display:** every listed site shows py4DSTEM's convention (unit tests on the pure formatters).
- **P5 nothing inside moves:** the unit, core and scientific gates are unchanged apart from the new
  tests (strain-frame-test, DPC and ACOM harnesses green).
- **P6 real data** (diagnostic): on `Particle_1…bin8.h5`, the app's displayed angle equals
  py4DSTEM's +80° within 0.5°, transpose T.

## Outcome, same day

Every log ends with exit 0 on its own line unless stated otherwise.
- **P1 held** (`parity-after.log`). File-faithful py4DSTEM gives the three predicted results: **(+37.0, F)**
  direct 40 × 40, **(−37.0, T)** transposed, **(+37.0, F)** 40 × 30. The app's converted angle is
  +37.2 / −37.2 / +37.2 with the same transpose, off by 0.2°, which is py4DSTEM's 1° grid. The
  unconverted angle is off by 74.2° in every case. With the conversion removed, the harness FAILs
  with exit 1 (`parity-mut-noconvert.log`). Leg (b) now gates; until today it was informational.
- **P2, P3, P4 held** (`RQRotationConventionTests`, 4 tests; `green.log` 19/19 with `StrainFrameTests`).
  - A py4DSTEM file's 0.6 rad becomes −0.6 inside the app. The readiness row shows "34.4°", and
    so does the strain frame label.
  - The sidecar snapshot writes −0.6 plus the marker, and nothing when there is no rotation.
  - A marked sidecar reads back as 0.6, and so does a legacy one.

  Six mutations, one per boundary, were each red on their own test: the import not negated; the
  snapshot not converted; the read ignoring the marker; the read always converting; the display
  unconverted; the strain keys unconverted.
- **P4, one deliberate expectation change:** `StrainFrameTests` pinned the export keys in the
  app's sign. They now pin py4DSTEM's: "37.2" and "64.0" (were "-37.2" and "-64.0"). The caption
  now reads "-37.2" for an internal +37.2°, and `qr_rotation_convention` is asserted.
- **P6 held** (`real/py_side.log`, `real/app_side.log`). On the real cube, py4DSTEM's own DPC gives
  **+80.0° T**. The app's solver on the same CoM field gives −80.1° T internally, **shown as +80.1° T**.
  The field does not beat its own null there (ADR 024), so the app would decline to apply it, as
  before. The sign relation is exact either way.
- **Residual, recorded:** the diagnostic `tools/training-dataset-campaign` writes and reads the app's
  own sign on its private path. It is not a user boundary, and it is left as is.

## Independent refuter (Sonnet), same day

**NOT REFUTED on the predictions; PARTLY REFUTED on completeness.** I checked the handback: every
changed file `cmp`-identical, no processes left.
- **Every boundary converts.** The refuter checked each site by grep, and found no angle in the replay
  recipes or the export sheet. The parallax fit's rotation is a different quantity, correctly left
  alone.
- **Gap closed.** No test drove the real HDF5 writer and reader together. A writer that dropped the
  marker while the snapshot still converted (so the next open would read py4DSTEM's sign as a
  legacy app sign) left all four boundary tests green.
  `testARealSidecarRoundTripKeepsTheAppAngle` now writes through `BraggVectorEMDWriter.write` and
  reads back through `loadSession` and `translate`. It is green on the fix and red on that
  mutation (`roundtrip-green.log`, `roundtrip-dropmarker.log`).
- **Residual, recorded, not fixed.** A datacube this app exported **before 2026-09-28** holds the
  app's sign with no marker. If it is reopened as a dataset (File › Open), the import negates it
  as if it were a py4DSTEM file, so it is shown and used with the wrong sign. It cannot be told
  apart from a genuine py4DSTEM file, and few such files exist. The fix is to re-export the file.
  This is in `open-items.md`.
- `tools/training-dataset-campaign`'s JSON report writes `rotation_degrees` in the app's sign,
  unlabelled. It is a diagnostic's private file, now named as a residual defect.
- **Internals untouched,** by diff: RotationCalibration, DPC, ptychography, parallax, and
  StrainFrame's maths.
- **The frozen-shell edit is acceptable:** one VoiceOver format argument in
  `WorkspaceInspector.swift`, and not a pixel changes.
