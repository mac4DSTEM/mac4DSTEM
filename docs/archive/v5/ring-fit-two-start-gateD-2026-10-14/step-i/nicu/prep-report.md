# S5 prep (Ni65Cu35 ROI6, mean pattern) — ring-fit Gate D, step (i), 2026-10-14

No fit was run, no `EllipseCalibration` call was made, no `cubes/bin/fit-*` was executed. Everything here is numpy/h5py on the
cube plus plots. Cube dir: `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/cubes/nicu/`.
Scripts (re-runnable, python -I): `scripts/s5_mean.py` (+ `.log`), `scripts/s5_annuli.py` (+ `.log`, `.json`).

## Files

| file | content |
|---|---|
| `s5_mean.f32` | mean pattern, 32 x 32 float32 LE row-major (4096 bytes), the S5 fit source |
| `s5_mean.png` | quick look, log10(1 + max(I,0)), 640 x 640 |
| `s5_mean.profile.txt` | azimuthal-mean radial profile about the centre guess, 0.5 px bins: `radius mean count` (45 bins, 0.25 to 22.75) |
| `s5_mean.annuli.txt` | the 6 registered annuli, `tag inner outer`, `#` header with the rule |
| `s5_mean.annuli.png` | the mean pattern with the annuli drawn (yellow solid = Rk, cyan dashed = Rkw), centre guess as a red cross |
| `s5_max.f32`, `s5_max.png` | max pattern, 32 x 32 float32 LE, for information only (not a fit source) |
| `s5_mean.annuli.optional.txt` | NOT part of the registered set: the rejected shoulder at r = 3.25 as `S5-X1`, `S5-X1w` (see below) |

Cube: 200 x 200 x 32 x 32 float32 at `dm_dataset_root/dm_dataset/data` (shape [ry, rx, qy, qx], as the app's descriptor reads it;
no chunking). 40 000 patterns, 0 non-finite values, 327 765 negative values (global minimum -20 057.7; the mean is positive everywhere,
minimum 1381.84 at (0,0)). Metadata (`metadatabundle/calibration`): Q pixel 0.156828 A^-1, R pixel 3 nm. The file carries no origin or
ellipse attribute, so on load the app's aperture centre is the detector midpoint (see centre guess).

## Mean pattern: what was mirrored

- The app's meanDP: `AppState+Calibration.swift:19-45` `computeDPStatistics` calls `VirtualDetector.tiledDPStatistics`
  (`Core/Analysis/VirtualDetector.swift:422-467`) and stores `DiffractionPattern(qy: d.qy, qx: d.qx, pixels: meanDP)` (`:45`). The
  mean is over all scan positions per detector pixel, in float32 (`Shaders/DPStatistics.metal:36-46`: `vSum += v` over scan index in
  scan order, `outMean = vSum / float(nScan)`), then summed in Double weighted by each tile's scan count and divided by the total
  (`VirtualDetector.swift:459, 467`), cast to float32. Reproduced as one tile (the 164 MB cube fits one tile): a float32 sequential
  sum over s = row * rx + col, divided by 40 000, read in chunks of 20 scan rows. Cross-check: the same mean in float64 differs by at
  most 1.04e-5 relative (max over pixels) and six individual pixels recomputed straight from `d[:, :, a, b]` agree to 6 digits.
  `Origin calibration` (`:108`) would replace the stored mean with the same quantity from `OriginCalibration.tiledRun`; not needed here.
- Layout: row = detector row (axis 2 of the cube, "qx" in the fitter's naming), column = axis 3 ("qy"). The fitter reads
  `pixels[row * qx + col]` and computes `radius = hypot(row - centerQX, col - centerQY)` (`Core/Analysis/EllipseCalibration.swift:158-163`
  for `fit1D`, `radius > inner && radius <= outer`; `:483-484` for the profile fit, `radius < outer`, strict). The detector is square
  (32 x 32), so the row/column naming cannot be mixed up here. The profile in `s5_mean.profile.txt` uses the same `hypot` in the same frame
  (pixel index = coordinate).
- Not used: Disks-mode Bragg-vector map (`AppState+Calibration.swift:144-162`, `DiskDetection.swift:711, 746`). S5 is mean-pattern only;
  there is no map for this source, so no Swift harness was needed.

## Centre guess

`centreRow = 15.001983`, `centreCol = 15.162129` (centreQX = aperture.centerY = row, centreQY = aperture.centerX = column,
`AppState+Calibration.swift:179-180`).

How: lane P5's rule (`au/meanpat.py`), because the app's own value cannot be reproduced offline without a user action. The app's
aperture centre after load is the detector midpoint `(qx/2, qy/2)` = (16.0, 16.0) (`AppState+Open.swift:525-528`; this file records no
origin, so the file-origin branches at `:600-640` do not apply). It becomes the measured beam only after the user runs Origin
calibration (`AppState+Calibration.swift:112-115`, `aperture.centerX/Y = meanOrigin`), whose per-pattern probe/beam fit
(`OriginCalibration.tiledRun`) I did not reproduce. So: intensity-weighted centroid of the pixels above the 99th percentile of the
mean pattern (`np.percentile(m, 99)` = 9.2206e6, strict `>`, 11 pixels, weights = pixel values). For information: the unweighted
centroid of those 11 pixels is (14.364, 15.545); the argmax is pixel (15, 15) (4.356e8, 4.6 times its brightest neighbour,
(16,15) = 9.37e7); the detector midpoint is (16.0, 16.0), 1.3 px from the guess. Three of the 11 brightest pixels are off-axis
spots ((9,21) = 1.02e7, (10,15) = 9.76e6, (18,14) = 9.49e6); dropping the two farthest ones ((9,21), (10,15), 2.7 % of the weight)
would move the weighted centroid to (15.155, 15.081), i.e. by 0.15 px in row and 0.08 px in column, so the guess is good to
about 0.15 px by this rule.

## What the mean pattern looks like

A wide, nearly uniform disc about 30 px across (the profile falls from 3.6e5 at r = 13.75 to 7.5e4 at 15.25 and 1.6e4 at 16.25: its edge
is at r = 15 and it fills the detector), with one saturated central beam pixel (4.36e8) whose tail reaches about r = 2.5, and speckle of
individual bright pixels (1e7 to 3e7) on a 5e5 to 4e6 floor. The rings are weak bumps made of a few spots each: ring-bin means exceed
the bin medians by 1.27x (r = 5.75: mean 3.27e6, median 2.57e6), 1.65x (8.25: 1.95e6 vs 1.18e6) and 1.15x (11.75: 9.93e5 vs 8.63e5). Plausibility only, not
a calibration: for fcc Ni65Cu35 (a taken as 3.55 A) with the file's 0.1568 A^-1 per pixel the low-index rings fall at
111 3.11, 200 3.59, 220 5.08, 311 5.96, 222 6.22, 400 7.18, 331 7.83, 420 8.03, 422 8.80, 511/333 9.33, 440 10.16, 531 10.63,
600/442 10.78, 620 11.36, 533 11.78 px; the three bumps at 5.75, 8.25 and 11.75 sit among these but the data cannot say which.

## Radial profile: peaks and minima (0.5 px bins [r, r+0.5), bin-centre radius, mean over the bin's pixels)

Strict local maxima of the mean profile (`s5_annuli.log`):

| peak r | mean | median | n | min left (r, mean) | min right (r, mean) | rel. prominence | outcome |
|---|---|---|---|---|---|---|---|
| 3.25 | 4.009e6 | 3.21e6 | 13 | 2.75, 3.681e6 | 4.75, 2.022e6 | 0.082 | rejected: a shoulder on the beam tail (below 0.15) |
| **5.75** | 3.274e6 | 2.57e6 | 17 | 4.75, 2.022e6 | 7.75, 1.217e6 | 0.382 | ring R1 |
| **8.25** | 1.946e6 | 1.18e6 | 28 | 7.75, 1.217e6 | 10.75, 7.86e5 | 0.374 | ring R2 |
| **11.75** | 9.933e5 | 8.63e5 | 32 | 10.75, 7.86e5 | 16.25, 1.646e4 | 0.209 | ring R3 |
| 16.75, 18.25, 20.25, 21.75 | 1.6e4 down to 8e3 | | 32, 17, 7, 3 | | | 0.002, 0.059, 0.051, 0.199 | outside the radius cap (15.998), vacuum floor and detector corners |

The rule (written before any fit, and applied mechanically): a ring is a strict local maximum of the mean profile with r below the
cap, whose relative prominence (peak minus the higher of its two flanking minima, over the peak) is at least 0.15, with the flanking
minima found by walking down monotonically each side to the nearest local minimum; at most 5 rings, kept by prominence. The 0.15
threshold lies between the rejected shoulder (0.082) and the weakest accepted ring (0.209); it is my choice, say so if a different
rule is wanted. The median profile has no peak at 3.25 either, and puts the middle ring at 8.75. R3's right-hand minimum is the
vacuum floor outside the disc (r = 16.25), as the mean profile falls monotonically from 11.75 to 16.25.

## Annuli (about the centre guess)

Annulus recipe, as registered: base = [peak - (peak - minL)/2, peak + (minR - peak)/2]; a base narrower than 3 px (all three are:
1.5, 1.5, 2.75) is widened symmetrically about its midpoint to exactly 3 px; `Rkw` = `Rk` widened by 2 px each side; inner >= 1; outer at
most 15.998 (the farthest detector edge from the guess, in the pixel-index frame in which the first and last pixels are 0 and 31:
max(15.002, 31 - 15.002, 15.162, 31 - 15.162) = 15.998; counting pixel borders instead would give 16.498, and only `R3w` is near it).

| tag | inner | outer | base annulus before the 3 px floor | pixels (inner < r <= outer) | mean / median in annulus |
|---|---|---|---|---|---|
| S5-R1 | 4.5000 | 7.5000 | [5.25, 6.75] | 114 | 2.35e6 / 1.67e6 |
| S5-R1w | 2.5000 | 9.5000 | | 264 | 2.16e6 / 1.60e6 |
| S5-R2 | 7.2500 | 10.2500 | [8.00, 9.50] | 166 | 1.40e6 / 1.10e6 |
| S5-R2w | 5.2500 | 12.2500 | | 388 | 1.41e6 / 1.07e6 |
| S5-R3 | 11.1250 | 14.1250 | [11.25, 14.00] | 240 | 6.26e5 / 5.29e5 |
| S5-R3w | 9.1250 | 15.9980 | | 536 | 5.62e5 / 5.09e5 |

In every annulus the brightest pixel is 2 to 4 % of the annulus sum (no single spot dominates). Notes a reader of the fit
results needs: R1w starts inside the beam tail (the bin at r = 2.75 is 3.7e6); R3w reaches the disc edge and the vacuum floor
(outer 15.998), so its pixels fall by two orders of magnitude from the inside to the outside; R1 and R2 overlap by 0.25 px.
`s5_mean.annuli.optional.txt` holds the rejected shoulder as `S5-X1 2.0 5.0` and `S5-X1w 1.0 7.0` (inner clamped from 0.0 to 1.0),
for use only if the coordinator wants a fourth ring; it is not in `s5_mean.annuli.txt`. The app's own default Fit annulus for a 32 px
detector (`AppState+Open.swift:522-524`: inner max(1, 16 x 0.35) = 5.6, outer max(inner + 2, 16 x 0.9) = 14.4) covers all three
rings and excludes the 3.25 shoulder, which is some support for dropping it.

## Could not do / caveats

- The app's own centre was not reproduced: no origin calibration was run (it needs the app, or a reimplementation of
  `OriginCalibration`); the P5 fallback was used, as instructed. Radii about (16.0, 16.0) would differ by up to 1.3 px.
- Profile bins hold few pixels at small r (1, 1, 5, 3, 11, 5, 13 for r < 3.5), so the profile below r = 3 is not an azimuthal
  average in any useful sense; the rings used are all at r >= 5.75 (17 to 32 pixels per bin).
- The rings of S5 are spot-built and ride a falling background, so the registered prediction Pi1 ("nearly noise-free") is likely
  to fail on this source; that is for the measurement step to record, not amended here.
- The prominence threshold (0.15), the 3 px floor handling (symmetric about the midpoint) and the pixel-index definition of the
  detector edge are rule readings of mine where the record leaves room; each is written in the annuli file header.
