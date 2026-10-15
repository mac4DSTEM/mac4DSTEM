# DiffractoKit 0.0.3 -> 0.1.0 re-pin (2026-10-15, tier 1)

Pin: `exact: "0.1.0"` (tag object `2a191b96`, commit `7348b929`), in `Package.swift`, the Xcode project requirement and both
`Package.resolved`. No source changed: the app compiles unmodified (no `RingCalibration.Refusal` switch, no `.tetragonal`
pattern, no use of the removed enums `DiffractoGeometry`/`DiffractoScattering`/`DiffractoOrientation`).
The detector-ellipse path keeps the default `requireRingEvidence: false` (the owner's decision, tied to his annulus-guard card).
Rule of the owner (2026-10-15 13:10): a registered fixture reproduces through the kit to its tolerance, or its move is one the
kit's note (`DiffractoKit/docs/consumers-0.1.0.md`) names; no refuter of its own.

## Before / after, same harness binaries' sources, -O, bit patterns
Harnesses: `ellipse-calibration-test`, `calibration-test`, `fit-overlay-test`, `q-calibration-gate-test`,
`real-data-acceptance` (it runs disk detection and virtual imaging, not an ellipse fit), and a bit dump of `fit1D`
(two residual caps), `fitBestAvailable` and `fitAmorphousRing` on 24 synthetic patterns plus the `Calibration` ellipse
transform (12 x 7).

- The five harnesses: output identical line for line (real-data-acceptance differs only in elapsed times and its temp dir).
- Bit dump: the 12 patterns of the 0.0.3 switch (circle, noisy ellipse, missing arc, rectangular, central blob, 512^2, blank,
  sparse arc, bad dimensions, bad count, bad radii, NaN centre), the transform rows, and the new `dr0.6` (range 0.6) and `dr1e3` patterns: **bit identical**.
- Rows that moved, each classified by the kit note's item:

| Pattern (4 calls each) | Before (0.0.3) | After (0.1.0) | Item |
|---|---|---|---|
| ring + one pixel at 10x / 1000x the ring peak (annulus) | `insufficientAngularCoverage(1)` | fits, cx 64.2889 cy 61.7003 (conic), the two values identical | 3 |
| ring + one pixel at -500 (annulus) | fitted, conic cx 64.28371 -> 64.28899 (+5.3e-3 px), a +6.1e-3 px; `best` a +2.5e-4 px, nres 0.0125 -> 0.0256 | pixel skipped (n 7392 -> 7391), identical to the hot rows | 3 |
| ring + hot pixel at 100x peak outside the annulus / in the centre (`best`, `amorphous`; `fit1D` unchanged) | skipped by neither | a -3.1e-4 px, b -2.8e-4 px, cy -6.8e-7 px, cx +1.2e-7 px | 3 ("a one-pixel spike anywhere") |
| ring of amplitude 1e-7 (range 1e-7) | `insufficientSignal` | fits (cx 64.3 of plant 64.3) | 4 |
| range 1e-3, noiseless (`best`, `amorphous`) | | a, b, cx, cy equal; theta +1.7e-16 | 4 |
| range 1e-3, noise 5e-5 (`best`, `amorphous`) | | all parameters within 1.6e-13 px | 4 |
| range 0.4 (`best`, `amorphous`) | | a, b within 2.1e-11 px | 4 |

Range 0.6 and 1e3 are bit identical (item 4: 0.5 and more). `fit1D` of the three small-range patterns is bit identical.
One figure to read with care: the note bounds a one-pixel central beam at <= 1.1e-4 px; the spike outside the annulus
here is 100x the ring peak and moves `a` by 3.1e-4 px. It is the same mechanism (item 3), a larger spike.

Logs: lane scratchpad `lane-R3/{before,after}` (not retained). Gates: see the commit message.
