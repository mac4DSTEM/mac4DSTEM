# Refuter RH1 brief — the diffraction pane pointer readout (tier 1), frozen commit 515257ea (mac4DSTEM, 2026-10-14)
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM (READ-ONLY; other lanes edit its working tree — read only committed
state: `git -C $REPO show 515257ea`, `git -C $REPO show 515257ea:<path>`, `git -C $REPO archive 515257ea`). Use ABSOLUTE paths.
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
Your dir: $SP/lanes/RH1/ (write only there).

What is claimed: the registration docs/archive/v5/diffraction-readout-2026-10-14.md (committed at 3e873c82, before the code) defines
the readout `Qx · Qy · I · q` on the Diffraction pane: pixel = floor of the hover point in the unzoomed box (Qx the column, Qy the row),
I = the stored value of the displayed pattern, and q = s · |E(p − o)| only when the Q scale is physical and the origin is a measured
beam centre (o = the per-position fitted origin for a single-position pattern, else the mean reference origin; E the ellipse
correction; s qPixelSize in the pane's unit, θ in mrad mode). Predictions P1... are tests in DiffractionPointerReadoutTests (in the commit).

Tier 1 Gate B (suite ../CLAUDE.md "Rigour follows risk"; once, on the frozen commit): find what would show the owner a wrong number.
1. Re-derive q independently from the app's own calibration code (Calibration, ellipseCorrectedOffset, BraggVectors.calibrated,
   CalibrationUnitConversion, the scale bar's unit choice) — not from the lane's code — and compare on cases you choose: an ellipse
   with theta != 0, a non-square detector, the mrad mode, a per-position origin vs the mean, a peak at a pixel centre. Write a small
   harness compiled against the committed sources (a `git archive 515257ea` copy in a directory NAMED mac4DSTEM; see
   $SP/harness/build.sh for how the Core source group is gathered; the readout code lives in UI/, so either compile the pure
   functions it calls or run the lane's tests plus your own in an xcodebuild test of that copy through $SP/heavy.sh — one test host
   machine-wide; class-only -only-testing is fine).
2. Axis conventions: Qx column / Qy row vs the app's DiffractionPattern(qy:,qx:) storage (pixels[qx * width + qy]?) — check the
   registration's `pixels[Qy · W + Qx]` against how the pane draws the pattern. A transposed readout on a non-square detector is the
   classic wrong number here.
3. The suppression rules: is q ever shown from the geometric centre or the aperture centre? Is it hidden when it should show?
4. Tests: break two of them by a mutation each in the code they guard (e.g. swap row/column, drop the ellipse) and confirm red.
5. The hover mapping under zoom/pan (code read) and the refresh/clear rules.
Verdict: UPHELD / UPHELD WITH CORRECTIONS / REFUTED, must-fix items (file:line) separate from notes. No app launch, no drive. Write
$SP/lanes/RH1/report.md (predictions before each experiment). Final message as text, <= 25 lines.
