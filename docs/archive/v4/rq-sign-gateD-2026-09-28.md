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
