# 039 — The detector ellipse can be typed in Prepare, in py4DSTEM's convention

Dates: 2026-09-28

Status: live. Driven by the owner on 2026-09-28 (their build, the Al-Mg-Si ellipse copy): typed 19,5 / 17,97 / 20,5 (decimal commas taken), Apply → readiness "Manual · a 19.5 · b 17.97 · θ 20.5°";
the Correction line and status bar agree, and the overlay ring shrank onto the {200} disks. Owner decision 5 of the 2026-09-25 board ("calibration from a
known crystal — which route"): the manual field first, a v4 search only if the owner asks for one.
The three choices below were put to the owner as options with a recommendation; he took each
recommendation.

## Decision

1. **Placement.** Three rows and a button — Semi-axis a (px), Semi-axis b (px), θ (°), Apply
   Ellipse — under Fit Ellipse in Prepare's collapsed "Ellipse correction" section
   (`UI/PrepareSettings.swift`). About 120 pt, only while expanded. The readiness list and the
   five frozen-shell files (035) are unchanged.
2. **Inputs are py4DSTEM's a, b, θ.** a is the semi-major axis, and θ is its tilt from qx (the
   row axis, the app's detector y), in degrees. These are the numbers the Correction line and
   the readiness row show, so a displayed ellipse round-trips. They are not the detector x/y
   angle: on the owner's cube that angle is 69.5°, and θ is 20.5°. Only b/a and θ change the
   correction; a and b size the drawn ring.
3. **Nothing changes until Apply Ellipse.** The fields open on the ellipse in use, and
   half-typed values never become calibration. That avoids the manual-Q field's emptied-field
   trap (`open-items.md`).

The rule lives in `CalibrationSession.applyManualEllipse`. It refuses non-positive or
non-finite values, and it refuses a < b (Gate B). Otherwise it marks the ellipse `.manual` and
retires the last fit's rows. After it lands, the app does what a fit does: a displayed Bragg
map is reprojected, and strain and ACOM are left for the user to rerun.

## Evidence

`mac4DSTEMTests/ManualEllipseTests.swift`: 7 tests. The ground truth is analytic: points on
py4DSTEM's ellipse must map to a circle of radius b. It uses θ = 20.5°, which is not
symmetric. An anti-vacuity test types the x/y angle and must fail. Before trusting the tests,
11 mutations were applied, and each turned its target test red. Gate B (an independent Sonnet
refuter) checked the convention against py4DSTEM's own formulas
(`elliptical_coords.py`, `braggvectors.py:494-516`) to 1e-14, and the display round trip. It
REFUTED completeness: the axes typed in the wrong order with θ kept were accepted, leaving a
spread of 17.97–21.16 px. That order is now refused. The refuter's other reports are not
regressions: save/reload relabels any ellipse "From session", and a new ellipse leaves
strain/ACOM results unmarked. Both are pre-existing, and both are the same for a fitted
ellipse.
