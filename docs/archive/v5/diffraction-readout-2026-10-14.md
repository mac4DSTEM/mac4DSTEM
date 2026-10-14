# Diffraction pane pointer readout: registration (tier 1, 2026-10-14, lane H1; written before the code)

A new number on screen (UI audit 2026-10-14, Summary item 1; owner asked for it). While the pointer is over the pattern, the
Diffraction pane header shows `Qx 123 · Qy 87 · I 4210 · q 3.21 nm⁻¹`. Four quantities, each with one definition and one source.

## Definitions

1. **Pixel (Qx, Qy).** For a pointer at (u, v) in the unzoomed pattern box (SwiftUI maps the hover through zoom and pan, as it
   does for the overlay handles), Qx = floor(u / boxW · W), Qy = floor(v / boxH · H); outside the box there is no readout.
   Same floor as `RealSpacePane`'s readout (`ImagePanes.swift`, `onContinuousHover`) and `RealSpacePointerPolicy.scanPosition`;
   the exact inverse of `PeakOverlayGeometry.center` (a pixel's centre is its integer index plus one half), so a Bragg peak at
   integer (x, y) drawn at its centre reads back as (x, y). Qx is the **column** and Qy the **row** (the app's convention, the
   header's "Qx × Qy = columns × rows"; py4DSTEM names the axes the other way round, and the label says the app's).
2. **I.** `DiffractionPattern.pixels[Qy · W + Qx]` of `AppState.displayedPattern` (current, mean, max, or the ROI sum, whatever
   is drawn): the stored value, not the log or the normalised display value. A non-finite pixel reads "—".
3. **q**, only when both hold: (a) the Q scale is physical (`qPixelSize` finite and positive, unit passing
   `CalibrationUnitConversion.isPhysicalReciprocalUnit`: the readiness row's `validQ`); (b)
   `Calibration.originSupportsReciprocalMetrology` (origin fit sane, and the origin a measured beam centre: fitted maps or the
   file's recorded mean, never the aperture centre or the geometric middle, S11/S13). Then

   q = s · | E(p − o) |, p = (Qx, Qy), o the origin, E = `Calibration.ellipseCorrectedOffset` (identity without an ellipse),
   s = `qPixelSize` in the pane's unit (the footer scale bar's own choice: the calibrated unit, or mrad per detector pixel in mrad
   mode, shown as θ).

   This is the map `BraggVectors.calibrated(with:referenceOrigin:)` applies to a peak: a calibrated peak lies at
   `referenceOrigin + E(raw − localOrigin)`, so its distance from the reference origin is |E(raw − localOrigin)|. `o` is the
   per-position fitted origin at the selected scan (`FitOverlays.localOrigin`) when the pattern is that one position (Current and
   Point shape: `FitOverlayPresentation.patternShowsSelectedPosition`), else `Calibration.referenceOrigin` (the mean). For the
   ROI-sum, mean and max patterns q is therefore the distance from the mean origin, which is what those patterns are centred on to
   within the descan spread.
4. **Not shown.** No q (pixel and I stay) when the Q scale is unset or in pixels, the origin is a stand-in, or the origin fit
   exceeds the probe radius: a distance from an unmeasured centre is not a q.

A readout never outlives its basis: it clears when the zoom or pan changes under a resting pointer, and refreshes when the pattern
changes under it (arrow-key scan stepping, mean/max, a new load).

## Predictions (each a test in `DiffractionPointerReadoutTests`)

- **P1 pixel.** On a 7 × 5 detector drawn in a 140 × 100 box (non-square cells), the centre of every cell and its top-left corner
  read that cell; a point at u = boxW or v = boxH reads nothing; the Bragg-peak round trip `pixel(at: center(x:y:))` returns (x, y)
  for all 35 pixels. The mapping equals `RealSpacePointerPolicy.scanPosition` on the same point.
- **P2 value.** I at (Qx, Qy) = `pixels[Qy · W + Qx]` on a pattern whose every pixel value is distinct (an off-by-axis swap is seen).
- **P3 ellipse oracle (independent of the code under test).** With a = 10, b = 5, θ = π/2 (the ellipse's long axis along the
  columns, the app's convention) the lattice points (10, 0), (0, 5), (6, 4), (8, 3) lie on the ellipse; each maps onto the circle of
  radius b, so q = 5 · s for all four, from origin (64, 64) and s = 0.02 nm⁻¹ per pixel: q = 0.100. Without the ellipse the same
  pixels read 10, 5, 7.211, 8.544 pixels times s.
- **P4 against the app's own pipeline.** For a `BraggVectors` peak at raw pixel p, `calibrated(with:referenceOrigin:)` followed by
  s · |peak − referenceOrigin| equals the readout's q at p, with an ellipse and with per-position origins, to Float precision.
- **P5 gates.** q is nil for: no Q scale; Q in pixels; an aperture-centre origin; a geometric-middle origin; a fit residual above the
  probe radius. The pixel and I are present in every case. With the same calibration made valid, q appears.
- **P6 per-position origin.** On a 2 × 1 scan with fitted origins (60, 60) and (66, 62), the readout at the second position uses the
  second origin; the ROI-sum and mean patterns use the mean (63, 61).
- **P7 mrad.** In mrad mode q is the pixel distance times the mrad-per-pixel scale and carries the unit "mrad".

**Refuting observations.** Any prediction failing. In particular a q that differs from `BraggVectors.calibrated`'s own distance
(P4), or a q shown for a stand-in origin (P5).

## Test plan

New file `mac4DSTEMTests/DiffractionPointerReadoutTests.swift`. Every test broken once, on the logic it names, and seen red:
M1 `floor` replaced by `round` in the pixel map (P1); M2 the row/column swapped in the pixel index (P2); M3 the ellipse correction
skipped (P3, P4); M4 the per-position origin replaced by the mean (P6); M5 the origin gate removed (P5). Gate: unit, core, inventory
in an isolated copy. A Gate B refuter is the session's.

## What this registration does not settle

On-screen behaviour (the header slot at narrow widths, the hover mapping while zoomed, the refresh under a resting pointer) is
unverified until a drive: the readout sits in the header's flexible gap and shortens, then disappears, rather than ever changing
which header layout is chosen.

## Result (2026-10-14, lane H1)

P1 to P7 held on the first run: the 15 tests of `DiffractionPointerReadoutTests` passed in an isolated copy of HEAD (`h1a-class.log`), and in the
full unit gate of the committed state (2274 passed, 0 failed, 4 skipped = 2278 `func test`, `h1d-unit.log`; `core` exit 0). P4 is the independent
oracle: for a peak at a raw pixel, `BraggVectors.calibrated(with:referenceOrigin:)` gives the same distance as the readout to Float precision, with an
ellipse (a = 1.1, b = 1, θ = 0.7) and per-position origins on a 2 × 1 scan, at both positions.

Every test went red on its mutation, and only on tests the mutation should reach (`mut-*.log`, one `heavy.sh` run each):

| Mutation | Red |
|---|---|
| M1 `floor` to `round` in the pixel map | `testEveryCellCentre…`, `testAPeakDrawnAtItsPixelCentre…`, `testSameFloorAsTheRealSpaceReadout` |
| M2 row and column transposed in the pixel index | `testTheValueIsTheStoredPixel…` |
| M3 ellipse correction skipped | `testAgreesWithBraggVectorsCalibrated…`, `testPixelsOnTheEllipseAllReadTheMinorSemiAxis` |
| M4 per-position origin replaced by the mean | `testAgreesWithBraggVectorsCalibrated…`, `testTheSinglePositionPatternUsesItsOwnOrigin…` |
| M5 origin gate removed | `testNoQFromAStandInOrigin`, `testNoQWhenTheOriginFitExceedsTheProbeRadius` |
| M6 non-finite value not withheld, M7 physical-unit test dropped, M8 mrad flagged as a distance | `testANonFinitePixel…`, `testNoQWithoutAPhysicalQScale…`, `testInMilliradianModeQIsTheAngle…` |

The bounds, plain-Euclid, field-name and θ-versus-q tests have theirs in one further run (far edge `<` to `<=`; the square root dropped; the field values swapped; the angle symbol made a q): red `testOutsideTheBoxAndTheFarEdge…`, `testWithoutAnEllipseTheDistanceIsPlainEuclidean` (with the ellipse and Bragg tests, which the dropped root also moves), `testTheTextKeepsEachNumbersMeaning…`, `testInMilliradianModeQIsTheAngleInMrad`.

Not settled by this registration, and not claimed: how the readout sits in the header at every pane width, the hover mapping under a live
pinch, and the refresh under a resting pointer. All three are drive items. The refresh keys on `patternVersion`: a pattern replaced
without a version bump would leave the previous pixel's reading until the pointer moves.
