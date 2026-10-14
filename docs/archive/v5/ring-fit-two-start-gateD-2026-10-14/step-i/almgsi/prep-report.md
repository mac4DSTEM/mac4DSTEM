# Prep report: Al-Mg-Si 060 (S1 mean pattern, S2 Bragg-vector map), ring-fit Gate D step (i), 2026-10-14

No fit was run (no `fit-*` binary, no `EllipseCalibration` call). The annuli below were fixed from the radial profiles alone.
Cube dir: `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/cubes/almgsi/`
(all paths below are relative to it). The repo was read only.

## Files

| id | pattern (float32 LE, row-major, 64 x 64, row = qx = cube axis 2, col = qy = cube axis 3) | quick look | profile | annuli |
|---|---|---|---|---|
| S1 | `s1_mean.f32` (16384 B) | `s1_mean.png` | `s1_mean.profile.txt` | `s1_mean.annuli.txt` |
| S2 | `s2_bvm.f32` (16384 B) | `s2_bvm.png` | `s2_bvm.profile.txt` | `s2_bvm.annuli.txt` |

Both are square (64 x 64), so the row/column naming (the app's `DiffractionPattern(qy:, qx:)` vs the harness's "rows = qx") cannot
disagree. Source cube: dataset `dm_dataset_root/dm_dataset/data`, 330 x 330 x 64 x 64 float32, unchunked.

Scripts and checks (reproduce with `~/miniconda3/envs/py4dstem/bin/python -I`): `meanpat.py` (S1), `export_peaks.py` (sidecar to
`s2_peaks.bin`, `s2_fittedX.f32`, `s2_fittedY.f32`), `bvm-src/main.swift` + `build.sh` + binary `bvm` (S2, the app's own code),
`bvm_check.py`, `orient_check.py`, `prof0.py`, `rings.py`, `make_annuli.py`, `centre_sens.py`, `occupancy.py`; logs `bvm-run.log`,
`occupancy.txt`, `orient-check.log`, `centre-sensitivity.log`, `build-bvm.log` (+ `.exit` = 0).

## Centre guess (both sources)

**(centreRow, centreCol) = (31.7953815, 31.8026600)**, i.e. centerQX = aperture.centerY, centerQY = aperture.centerX
(`AppState+Calibration.swift:179-180`). Obtained as the app's own aperture centre for this cube and sidecar:

- The sidecar carries fitted origin maps (`qx0`, `qy0`, 330 x 330). Restoring a sidecar with maps sets
  `calibration.origin` and moves the aperture to the maps' mean origin (`SessionCalibrationFramePolicy.swift:132-140`, applied at
  `AppState+Open.swift:1219-1226`). The mean origin is `Calibration.meanOrigin` (`Calibration.swift:943-952`): `fittedX.reduce(0, +) / count`,
  a sequential Float sum, with `fittedX = qy0` (column) and `fittedY = qx0` (row) (`Calibration.swift:1019-1029`, `appOriginMaps`).
- The Swift harness computed it with that very property: `meanOrigin x(col)=31.80266 y(row)=31.7953815` (`bvm-run.log`). It equals the
  sidecar's scalars `qy0_mean = 31.80265998840332`, `qx0_mean = 31.795381546020508` and the lineage node `calibration_origin`
  (`origin_x_px 31.80266`, `origin_y_px 31.795382`), so the app wrote that same Float value when it fitted the origin.
- Worth knowing, not mine to fix: the float64 mean of the same maps is (row 31.8172916, col 31.8049831). The app's Float `reduce` is
  0.0219 px (row) and 0.0023 px (col) lower, a float32 accumulation error over 108 900 values (checked by a sequential float32
  emulation in `export_peaks.py`). I used the app's value because it is what the aperture holds.

S1: the same point is the app's aperture centre for the mean pattern when the sidecar is opened. The record's literal wording for mean
patterns is "the centroid of its brightest 1 % of pixels, as P5" (intensity-weighted, pixels above the 99th percentile). That rule gives
(31.8323786, 31.8229897) on S1, 0.037 px (row) and 0.020 px (col) from the app's. I followed the computed task's rule (use the app's
centre when it can be reproduced). It changes nothing here: S1's annuli are identical under either centre (`centre-sensitivity.log`).
If the orchestrator wants the literal rule, pass those two numbers; the annuli files stay valid.

## Conventions mirrored (file:line in HEAD 26389404, identical to the HEAD copy used for the Swift build)

S1, the mean pattern:
- `AppState+Calibration.swift:19-46`: `computeDPStatistics` calls `VirtualDetector.tiledDPStatistics`, then
  `meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: meanDP)` (`:45`); `calibrateOrigin` stores the same (`:108`).
- `VirtualDetector.swift:422-470`: mean over all `ry * rx` scan positions; per tile the mean comes from Metal in float32, the tiles are
  combined as a Double weighted sum (`:459`) and divided by `Double(ry * rx)` (`:466`), cast to Float. Mirrored as a float64 sum of all
  108 900 patterns (22 scan rows per read) divided by 108 900, cast to float32 (`meanpat.py`). The only difference to the app is the
  float32 Metal per-tile accumulation (order 1e-7 relative; `HotPixelFilter.swift` header documents the same effect). No load-time
  filtering exists in the default load path.
- Layout: pixel index = row * width + column, row = cube axis 2, column = cube axis 3.

S2, the Bragg-vector map (the Fit in Disks mode):
- `AppState+Calibration.swift:144-163`: `uncorrected = calibration` with `ellipseA/B/Theta = nil`; `origin = calibration.meanOrigin`
  (else detector middle); `bvm = vectors.calibrated(with: uncorrected, referenceOrigin: origin).map(qy: descriptor.qy, qx: descriptor.qx)`;
  `DiffractionPattern(qy:, qx:, pixels: bvm.pixels)`.
- `DiskDetection.swift:711-741` `calibrated`: because `canUseMaps` (origin maps 330 x 330, 108 900 values) it moves every peak by the
  per-position origin: `x' = refX + (x - fittedX[scan])`, `y' = refY + (y - fittedY[scan])`, with no ellipse (`ellipseCorrectedOffset`
  returns `(dx, dy)` when `ellipseTransform()` is nil). The scan index is the flat row-major index over (ry, rx).
- `DiskDetection.swift:746-763` `map`: bilinear deposition, `x0 = floor(x)`, weights `(1-fx)(1-fy)`, `fx(1-fy)`, `(1-fx)fy`, `fx fy` on
  `(x0,y0)`, `(x0+1,y0)`, `(x0,y0+1)`, `(x0+1,y0+1)`, times the raw peak intensity, bounds `0 <= xi < qx`, `0 <= yi < qy`,
  `out[yi * qx + xi]`; Float32 accumulation in peak order. 1 010 514 peaks, none outside or touching the edge.
- Peaks: `BraggVectorEMDWriter.swift:723`, `:811-813` `loadPeakGrid`: `x = Float(record.qy)` (column), `y = Float(record.qx)` (row),
  `intensity = Float(record.intensity)`; `BraggPeak` is x = column, y = row (`DiskDetection.swift:34-37`). The saved vectors are the
  `_v_uncal` object array (330 x 330 cells, compound float64 `(qx, qy, intensity)`; `braggvectors/metadatabundle/_braggvectors_shape/Qshape`
  = (64, 64)). 1 010 514 peaks, every cell non-empty, max 18 per position.
- Built by the app's own code: `bvm-src/main.swift` compiled against the `detection` source group of the HEAD copy (so the production
  `Calibration`, `OriginMaps`, `BraggVectors.calibrated` and `.map` ran), via `heavy-build.sh` (exit 0). Not a Python mirror, so
  Float32 accumulation order (and absorption of small peaks by the 3.8e9 beam pixel) is the app's. An independent float64 numpy
  mirror (`bvm_check.py`) agrees to 6.4e-6 relative on the 57 pixels above 1e6; the faint pixels differ by up to 8e-4 relative because
  of that Float accumulation, and both pick (32, 32) as the maximum.
- Axis order checked, not assumed: with `x = qy`, `y = qx` the BVM's spots coincide with the mean pattern's (the same four brightest
  spots outside r < 8 at (row, col) = (14, 37), (25, 15), (39, 49), (50, 26) in both; correlation of the detrended S1 with S2 is +0.43
  as is, +0.01 transposed, +0.03 and +0.02 with rows or columns flipped; `orient-check.log`). The origin maps swap the same way (`fittedX = qy0`), and the resulting mean origin equals
  the sidecar's own scalars (above).
- Not driven: whether the app, on this machine, adopts the stored peaks on open (`SessionPeakRestore`: identity view required) is
  unverified on screen. This prep assumes the Disks-mode map is built from exactly these vectors, as the record states.

Radial profiles: `profile.txt` = azimuthal mean in 0.5 px bins [r, r+0.5), radius = bin centre, count of pixels; pixel centres at integer
(row, col), the fitter's coordinates (`EllipseCalibration.swift:159-166`, in-annulus test `radius > inner && radius <= outer`).

## Reading the rings (the rule, fixed before any fit)

The record's rule: one annulus per ring visible outside the central beam, the ring's peak radius -/+ half the distance to the
neighbouring minimum on each side, plus each widened by 2 px both sides; inner >= 1 px; outer <= the distance from the centre guess to
the farthest detector edge. How peak and minimum were read: profile smoothed once with [1,2,1]/4; a peak or minimum is the extreme of
the smoothed profile within +-3 bins (+-1.5 px); a ring needs its smoothed peak >= 1.5 x the larger of its two bounding minima and
r >= 3.5 px (beyond the beam, probe radius 2.54 px from the lineage); only radii up to the cap count; on a side with no interior minimum the
minimum is the cap bin. Cap = max(row, 63 - row, col, 63 - col) = 31.80266 px (pixel indices 0..63; with edges at -0.5 and 63.5 it
would be 32.30), the last 0.5 px bin centre at or below it is 31.75. Ties among equal minima: the nearest to the peak.

### S1 (mean pattern), centre (31.7953815, 31.8026600)

Profile: central beam to r ~ 3 (7.4e5 falling to 8.8e4 by r = 3.25), then a smooth tail (4.4e3 at r = 14.75), one bump, then a
shoulder/plateau of ~2.0e3 at r = 22.75 to 26.75, then smooth decay to 8e2 at r = 31.75.

| ring | smoothed peak | raw bin max | inner minimum | outer minimum |
|---|---|---|---|---|
| R1 | r = 18.25 (8506) | 9263 at 18.75 | r = 14.75 (4441) | none before the cap, cap bin r = 31.75 (801) |

Annuli: `s1-R1` 16.5 25 ; `s1-R1w` 14.5 27.
- S1 has one ring in the radial-profile sense, so Pi1's "most annuli" rests on these two annuli only. The image (`s1_mean.png`)
  shows that the bump is four discrete spots (centroids at r = 18.5, 18.5, 18.8, 18.8 px) on a smooth tail, not a continuous ring.
  The same weak outer spots that S2 resolves (two at r ~ 25.5, two at r ~ 27.8) are faintly visible in the mean pattern but add no
  peak to the azimuthal mean (the 22.75 to 26.75 plateau varies by < 8 %, bin-to-bin noise), so by the rule they are not rings.
- Because the outer side has no minimum the annulus reaches 25.0, i.e. it includes ~3 px of the 2.0e3 plateau (and R1w ~5 px).

### S2 (Bragg-vector map), centre (31.7953815, 31.8026600)

Profile (dynamic range 4e9 at the beam to 4 at r ~ 31): empty from r = 2.25 to 7.75 (zeros), then four shells. The image
(`s2_bvm.png`) shows discrete spot clusters, not continuous rings: R2 is four spots (centroids r = 18.4 to 18.7), R3 two spots
(r = 25.4, 25.5), R4 two spots (r = 27.5, 27.8); R1 is diffuse weak clusters, about 0.3 % of R2's intensity.

| ring | smoothed peak | raw bin max | inner minimum | outer minimum |
|---|---|---|---|---|
| R1 | r = 11.75 (1.32e4) | 1.47e4 at 12.25 | r = 7.25 (0, the empty gap; 8.25-9.75 holds a 4e2-5e3 shoulder) | r = 14.25 (578) |
| R2 | r = 18.75 (4.70e6) | 6.04e6 at 18.75 | r = 14.25 (578) | r = 22.25 (12.7) |
| R3 | r = 25.25 (3.23e5) | 3.81e5 at 25.75 | r = 22.25 (12.7) | r = 26.75 (1.34e5, raw 6.8e4) |
| R4 | r = 27.75 (2.13e5) | 2.23e5 at 27.75 | r = 26.75 (1.34e5) | none before the cap, cap bin r = 31.75 (3.6) |

Annuli (inner outer, px):
`s2-R1` 9.5 13 ; `s2-R1w` 7.5 15 ; `s2-R2` 16.5 20.5 ; `s2-R2w` 14.5 22.5 ; `s2-R3` 23.75 26 ; `s2-R3w` 21.75 28 ;
`s2-R4` 27.25 29.75 ; `s2-R4w` 25.25 31.75.

Notes:
- R3 and R4 are one pair separated by a shallow dip (raw 6.8e4 at r = 26.75 against 3.8e5 and 2.2e5). The split depends on the centre
  guess: with the float64-mean centre (31.8173, 31.8050) the smoothed dip is no longer a local minimum within +-1.5 px and the
  rule returns R3 = [23.75, 28.5], R4 = [25, 29.75] (`centre-sensitivity.log`); with the P5-rule centre the annuli are as written.
  The files use the app's centre; do not recompute R3/R4 at another centre.
- Features beyond the cap (r > 31.8: 25 at r = 33.75, 6.6e2 at r = 41.75) are corner pixels with partial angular coverage, not read.
- R1's inner minimum is the zero-valued gap, so R1's lower edge (9.5) sits just inside the 4e3 shoulder at r = 9.25 to 10.25.
- All S2 annuli lie inside the cap; `s2-R4w` ends at 31.75.

## Angular coverage (a pre-fit descriptor, computed to warn the fit step; no fit run, the annuli were not altered by it)

`fit1D` refuses an annulus before any optimisation when fewer than 30 of its 36 angular bins hold a "strong" sample (value >= annulus
minimum + 0.2 x annulus range; `EllipseCalibration.swift:80, 217-232`, `fitBestAvailable` calls `fit1D` first, `:405-419`), and the
`acceptSparseCoverage` path still needs 12 (`:81`). Counted on the final annuli with the same statistic and the same angle convention
(`occupancy.py`, `occupancy.txt`):

| annulus | occupied bins of 36 |
|---|---|
| s1-R1 / s1-R1w | 10 / 11 |
| s2-R1 / s2-R1w | 7 / 8 |
| s2-R2 / s2-R2w | 5 / 5 |
| s2-R3 / s2-R3w | 2 / 4 |
| s2-R4 / s2-R4w | 2 / 4 |

**All ten annuli are below the default bound of 30, and all are also below the sparse floor of 12.** The harness's default-argument
`fitBestAvailable` (and `fit1D`) is therefore expected to throw `insufficientAngularCoverage` on every one of them under HEAD, with no
ring model ever tried; Pi1 and Pi2 (which assume fits to compare) cannot be exercised on this cube with rings read from its profiles.
This is consistent with the Al-Mg-Si history (the owner uses the manual ellipse field, ADR 039). It is a count of the data, not a
fit; the orchestrator should decide whether that outcome ("refused on every annulus") is itself the measurement for S1 and S2.

## Verification summary

- S1: `s1_mean.f32` 4096 finite values, min 81.08, max 754 181.94; centre beam at (31, 32); 108 900 patterns summed.
- S2: `bvm` output: peaks 1 010 514, raw intensity sum 6.91825715e9, map sum 6.91821619e9 (Float accumulation), all finite, max 3.80508339e9 at (32, 32).
- Annuli files parse with the fit harness's parser (`cubes/harness/main.swift`: `#` lines skipped, `tag inner outer`, no spaces in tags).

## Could not do / open points

- The app was not driven (no app, no test host): the Disks-mode map and the aperture centre are reproduced from the source, not seen.
- S1's mean differs from the app's Metal float32 per-tile mean at the 1e-7 relative level (not measurable offline without the app).
- The annulus choice for S1 (one wide annulus with a tail side) and the R3/R4 split are reading choices under the rule above; the
  alternatives are recorded here (S1: the 22.75-26.75 plateau; S2: the centre-fragile dip) so a reader can overrule.
