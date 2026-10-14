# RH1 report — diffraction pane pointer readout, frozen commit 515257ea (Gate B, tier 1, once)

Method: `git archive 515257ea` copy at lanes/RH1/src/mac4DSTEM (read-only repo untouched); standalone harness lanes/RH1/harness/main.swift compiled
against the Core `fitoverlays` group + the lane's UI/DiffractionPointerReadout.swift; the lane's own tests and my mutations through xcodebuild of the
copy (lanes/RH1/{build-tests,run-class}.sh via heavy-build.sh / heavy.sh). No app launched, nothing driven.

## Predictions (written before any experiment ran)
- H1 convention: the app's `ellipseCorrectedOffset`, fed points on MY ellipse (a-axis at angle theta from py4DSTEM-qx = image ROW, i.e. direction
  (dx,dy) = (sin th, cos th)), returns radius b for any theta. PASS expected (Calibration.swift documents exactly this).
- H2 readout q == s*|my E(p-o)| on a 96x64 detector, theta != 0, random origin/pixel; I == pixels[y*96+x]. PASS expected.
- H3 readout q == s*|BraggVectors.calibrated(peak at the pixel) - reference| with a 3x2 per-position origin map, non-square detector, theta=2.1;
  mean-origin patterns likewise. PASS expected.
- H4 pixel map == floor(u/boxW*W), floor(v/boxH*H) incl. aspect-mismatched boxes; PeakOverlayGeometry.center round trip. PASS expected.
- H5 suppression: no q for aperture-centre / geometric-middle origin, px / nil / negative / NaN / real-space unit, residual > probe radius. PASS expected.
  Unrecognised-but-physical spelling labels (A^-1, 1/nm, 1/Å) show canonical. A NaN per-position fitted origin: PREDICT q text "q — nm⁻¹" (odd, not a wrong number).
- H6 text: `displayNumber(value, digits: 4)` is ICU significant-digit rounding, which also rounds INTEGER digits: PREDICT I = 12345 prints "12350",
  65535 prints "65540", 123456 prints "123500" (a stored value shown as a different number). If Foundation keeps integer digits this prediction is refuted.
- M-A mutation `distance`: swap dx/dy into ellipseCorrectedOffset -> RED in testPixelsOnTheEllipseAllReadTheMinorSemiAxis and the BraggVectors test.
- M-B mutation `pixel(at:)`: take x from point.y/box.height -> RED in P1 tests.
- M-C blind-spot probe: ImagePanes.readoutBasis (UI wiring: singlePosition, scanWidth/Height, aperture, mrad) is a private View method no test reaches.
  PREDICT: mutating it (singlePosition always true; scanWidth/scanHeight swapped) leaves DiffractionPointerReadoutTests GREEN.

## Results

### Harness (lanes/RH1/harness/main.swift, log logs/harness-run.log): 38949 checks, 0 failures
- H1 PASS: the app's `ellipseCorrectedOffset` maps my ellipse (a-axis (dx,dy)=(sin th, cos th), i.e. theta from py4DSTEM-qx = image row, as Calibration.swift
  and AppState+Open.swift document) onto radius b for 2000 random (a, b, theta, t); my own correction `v + (b/a-1)(v.u)u` agrees with the app's to 2e-3 px.
- H2 PASS: readout q == s*|my E(p-o)| on 3000 random (pixel, origin, s, ellipse) on a 96x64 detector; I == pixels[y*96+x] (columns = x, rows = y).
- H3 PASS: readout q == s*|BraggVectors.calibrated(peak at the pixel) - reference| for all 6 positions of a 3x2 per-position origin map (theta 2.1,
  96x64 detector, 1200 pixels), and for the mean-origin pattern (singlePosition=false) against a calibration whose maps all equal the mean.
- H4 PASS: pixel(at:) == floor(u/boxW*W), floor(v/boxH*H) for 9000 random points in three boxes (aspect-matched and mismatched); the
  PeakOverlayGeometry.center round trip holds for all 6144 pixels of 96x64 in each box. No transposition anywhere (Qx = column, Qy = row, index y*W+x),
  consistent with how the pane draws (`MetalImageView(width: qx, height: qy)`, row-major) and with `FloatImage`.
- H5 PASS: no q for an aperture-centre origin, a geometric-middle origin (aperture nil), an aperture exactly at the middle, a missing / px / negative /
  NaN / infinite scale, a real-space or pixel or unknown unit, a fitted-map residual above the probe radius (and q appears when the radius is raised);
  mrad mode still hides q for a stand-in origin and falls back to the calibrated unit without a voltage. Spellings A^-1, 1/nm, 1/Å show Å⁻¹ / nm⁻¹ / Å⁻¹.
  A NaN in one position's fitted origin makes `meanOrigin` nil, the reference falls to the aperture centre, and q is HIDDEN (my prediction of "q — nm⁻¹" was
  refuted; the actual behaviour is the safe one).
- H6 CONFIRMED (finding F1): `DiffractionPointerReadout.Sample.valueText` formats the stored value with `displayNumber(digits: 4)`, which is ICU
  significant-digit rounding applied to the INTEGER digits too:
  stored 4210 -> "I 4210"; 9999 -> 9999; 10000 -> 10000; **12345 -> "I 12340"; 65535 -> "I 65540"; 123456 -> "I 123500"; 4213567 -> "I 4214000"; -12345 -> -12340**.
  (A saturated 16-bit pixel reads 65540; every ROI-sum pixel above 9999 is rounded.) No test uses a value above 52, so none sees it.

### The lane's tests and my mutations (xcodebuild test of the archive copy, class DiffractionPointerReadoutTests, logs/baseline.log, logs/mut-{A,B,C,D}.log)
- Baseline on 515257ea: 15 passed, TEST SUCCEEDED (18:28).
- M-A (swap dx/dy into `ellipseCorrectedOffset` in `distance`): RED in testPixelsOnTheEllipseAllReadTheMinorSemiAxis and testAgreesWithBraggVectorsCalibrated... (as predicted;
  the no-ellipse tests rightly stay green because |(dy,dx)| = |(dx,dy)|).
- M-B (`pixel(at:)` takes x from point.y/box.height): RED in testEveryCellCentre..., testAPeakDrawnAtItsPixelCentre..., testSameFloorAsTheRealSpaceReadout (as predicted).
- M-C (ImagePanes.readoutBasis: `singlePosition: true`, `scanWidth: d.ry, scanHeight: d.rx`): **GREEN, 15/15** (as predicted). The view-side wiring of the Basis (single-position rule, scan
  extents, aperture, mrad flag) is a private View method that no test reaches; a wrong rule there shows the owner a wrong per-position origin and nothing goes red.
- M-D (proposed fix for F1: `digits: 7` in valueText): 15/15 green, i.e. the tests neither pin the 4-digit rounding nor object to the fix.
- Copy restored byte-for-byte from 515257ea after each run (cmp checked). DerivedData and tmp deleted.

### Code read (items 2, 3, 5), committed state only
- Axis convention: `pixels[Qy*W+Qx]` is how the pane draws (`MetalImageView(width: qx, height: qy)`, `FloatImage(width: qx, height: qy)`); origin.x / peak.x / aperture.centerX are columns
  (PeakOverlayGeometry.center maps x against patternWidth); `ellipseCorrectedOffset(dx: column offset, dy: row offset)` is what BraggVectors.calibrated passes. No transposition (H2-H4 verify numerically).
- Hover mapping: `onContinuousHover` is on the unzoomed box container before `.scaleEffect(drawZoom).offset(...)`; the image is zoomed by the shader with the same transform
  (`MetalDisplayTransform`, no rotation/mirror in this pane), the existing aperture handles and the label tap (`SpatialTapGesture` + `PeakOverlayGeometry.pixel`) already rely on SwiftUI mapping
  local coordinates through the same transform, and RealSpacePane's readout sits before a `.rotationEffect` the same way. A point outside [0, box) returns nil (cleared). Unverified on screen
  (the commit says so); I found no reason in the code to expect an error.
- Suppression: `originSupportsReciprocalMetrology` (fit sane AND kind in {fittedMaps, recordedMean}) gates q; the pane always passes the aperture centre, so geometric middle cannot arise and
  aperture only ever reaches `kind == .apertureCentre`, which is refused. The readout is MORE conservative than the footer scale bar (which also draws a "px"-unit bar).
- Refresh: patternVersion is bumped by the load (`loadCurrentPattern`), ROI sum, mean/max, display mode, Calibrate Origin; zoom/pan clear. Not bumped by: a Q-scale or ellipse change (N2).
  `readPointer` skips recomputation only for the same pixel with a live sample; `.ended` clears the pixel so re-entry recomputes.

## Verdict: UPHELD WITH CORRECTIONS

Everything the registration claims about q, the pixel, the axes and the suppression rules holds against the app's own calibration code (38949 harness checks, 0 failures; BraggVectors.calibrated
agrees to 2e-5 relative on a non-square detector with theta != 0, a per-position origin map and the mean origin). One displayed number is wrong.

### Must-fix
- **F1 `mac4DSTEM/UI/DiffractionPointerReadout.swift:144`** (`valueText`: `number(Double($0), digits: 4, ...)`). `displayNumber(digits: 4)` rounds integer digits: a stored 12345 prints "I 12340",
  65535 prints "I 65540", 123456 "I 123500", 4213567 "I 4214000". The registration defines I as "the stored value". Fix: `digits: 7` (Float carries ~7; M-D shows the 15 tests stay green) or print
  integral values with all their digits; add a test with a value >= 10000 (65535 and 12345 round-trip exactly, in en_US_POSIX and de_DE). The same helper is used by `spoken()` (line 171) so VoiceOver is fixed with it.
  q at 4 significant digits (line 148) is fine.

### Should-fix (not blocking the number's correctness)
- S1 `mac4DSTEM/UI/ImagePanes.swift:483-493` (`readoutBasis`): the Basis wiring is untested (M-C green). Move the construction into a pure function on `DiffractionPointerReadout.Basis`
  (inputs: calibration, descriptor, selectedScan, patternDisplayMode, realSpaceShape, aperture, patternScaleUnit, mrad scale) and unit-test the single-position rule, rx/ry order and aperture; or
  pin the three expressions with an inventory grep. Until then the "per-position origin" claim (P6) is tested only on the pure function, not on how the pane feeds it.
- S2 `DiffractionPointerReadout.swift:164-166` (`lines`: `short`, `minimal`): at narrow widths the readout drops the field names: "(74, 64) · 1 · q 0.2 nm⁻¹". The registration's point that the label says
  the app's axes (Qx = column) is lost exactly there, and the app's own code (AppState+Open.swift:602, Calibration.swift:631) says py4DSTEM's qx is the ROW. A py4DSTEM user can read (74, 64) as (row, col),
  and the bare "1" is not obviously an intensity. Keep "Qx 74 · Qy 64" in `short`, or say "(Qx, Qy)" / "I"; and consider a `.help` on the readout saying "columns x rows, as the header".

### Notes
- N1 q on the ROI-sum / mean / max patterns is measured from the global mean origin. The ROI sum (VirtualDetector.tiledDiffraction) is a plain sum with no per-position shift, so its beam
  sits at the mean of the fitted origins over the ROI, not over the scan; the readout there is off by the descan difference between the two (times s) and says nothing about it. The registration
  disclosed "within the descan spread"; the screen does not. Consider computing the ROI mean (the mask is known) or dimming/labelling q (for example "q ≈") when the origin map's spread exceeds a pixel.
- N2 ImagePanes.swift:500, :459: a Q-scale or ellipse change (manual entry, a finishing background Calibrate Q) under a pointer resting on the pane does not refresh or clear the readout
  until the pointer moves to another pixel (no patternVersion bump). Same for a resize of the pane (the box changes, no hover event). Transient, self-heals on the next move.
- N3 During arrow-key stepping the selected scan changes before the pattern arrives; a hover tick in that window pairs the old pattern's value with the new position's origin until
  `patternVersion` bumps and `refreshPointer` re-reads. Self-corrects.
- N4 `.onChange(of: zp.drawZoom) { cursor.clear() }` (ImagePanes.swift:460): with the later "zoom about the pointer" commit (aa4df75a, after the frozen commit) the pixel under the pointer is preserved by a
  zoom, so the clear is unnecessary there (harmless, but the readout will blink off on every zoom step until the pointer moves).
- N5 `singlePosition` is `.current && .point` while `displayedPattern` can still be the single-position pattern for a non-point ROI shape whose summed pattern has not arrived (or a `.mean` mode without a mean pattern);
  q then uses the mean origin for a single-position pattern. Same rule as FitOverlayPresentation.patternShowsSelectedPosition, so consistent with the fit overlay; difference is the descan only.
- N6 A NaN in a single position's fitted origin hides q at every position (meanOrigin goes nil, reference falls to the aperture): safe, not a defect.
