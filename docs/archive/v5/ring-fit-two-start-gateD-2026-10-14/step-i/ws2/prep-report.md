# Step (i) preparation, WS2 cube (S3 mean pattern, S4 Bragg-vector map) — 2026-10-14

Record: `docs/archive/v5/ring-fit-two-start-gateD-2026-10-14.md`, "Step (i)" (read first, followed). **No fit was run**: no
`bin/fit-*`, no `EllipseCalibration` call, no test host, no app. The repo was read only. The only swiftc build (the
S4 map helper) went through `heavy-build.sh` (slot heavy.1, released, exit 0).

Cube dir: `/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/cubes/ws2/`
Cube: `References/training_dataset/polycrystal_2D_WS2.h5`, `4DSTEM/datacube/data`, 128 x 128 x 128 x 128 float32 (no
non-finite values; the file carries no origin or ellipse, only `Q_pixel_size` etc.).

## Files (all float32 little-endian row-major, 128 rows x 128 cols; row = py4DSTEM qx, col = qy)

| file | what |
|---|---|
| `s3_mean.f32`, `.png`, `.profile.txt`, `.annuli.txt` (+ `.annuli.png`: image with annuli and the profile) | S3, the mean pattern |
| `s4_bvm.f32`, `.png`, `.profile.txt`, `.annuli.txt` (+ `.annuli.png`) | S4, py4DSTEM's peaks mapped the app's way |
| `s3_max.f32` | the max pattern (not needed, a by-product of the same pass) |
| `s4_peaks_py4dstem.npz`, `s4_kernel.npy`, `s4_detect.log` | S4's raw peaks (749 790), origins (measured and fitted), the kernel, the run log |
| `bvm/` | the Swift helper (`main.swift`, `build.sh`, `bvm-bin`), its inputs (`s4_peaks.bin`, `s4_origin.bin`), `run.log` |
| `mean_s3.py`, `s4_common.py`, `s4_detect.py`, `s4_check.py`, `profile.py`, `make_products.py` | every script, in run order |

Annuli: 5 rings x (plain, widened) = 10 per source. Every line is `tag inner outer` with single spaces, '#' header lines; the
fit harness's parser (`cubes/harness/main.swift`) skips them.

## Centre guesses

| source | centreRow (= centerQX) | centreCol (= centerQY) | how |
|---|---|---|---|
| S3 | 63.7328357 | 63.7380687 | intensity-weighted centroid of the pixels above the 99th percentile of the mean pattern (164 pixels): lane P5's rule, `au/meanpat.py`. The app's own rule for a mean pattern is "the aperture centre", which is the geometric (64, 64) after a plain load (`AppState+Open.swift:663-664`) or the fitted mean origin after Origin calibration (`AppState+Calibration.swift:113-116`), the latter needs the Metal origin run and cannot be reproduced offline; the record names the 1 % centroid, so that is used. |
| S4 | 63.8875198 | 63.8874969 | the mean origin the map was collapsed onto: `Calibration.meanOrigin` of the fitted origin maps, as the app computes it (see S4 below). `centreRow = aperture.centerY`, `centreCol = aperture.centerX`, `AppState+Calibration.swift:179-180`. |

For orientation, not used: py4DSTEM's own mean origin from the tutorial chain is (63.895474, 63.895474) in double precision
(the app's Float sum gives 63.8875, below); `get_probe_size` on the mean pattern gives (63.8428, 63.8428); the unweighted
centroid of the top 1 % is (62.63, 63.80) because only 20 of those 164 pixels lie within 10 px of the beam and 144 are on the
rings, which is why the intensity-weighted form matters. All sit within 0.17 px of each other (the fit moves its own centre).

## Conventions mirrored (file:line in the HEAD tree, 26389404)

- **Mean pattern.** `AppState+Calibration.swift:30` calls `VirtualDetector.tiledDPStatistics`; `:45` stores
  `DiffractionPattern(qy: d.qy, qx: d.qx, pixels: meanDP)`. `VirtualDetector.swift:459,467`: per-tile Float means, weighted by
  scan count in Double, one Float at the end, i.e. the mean over every scan position (16 384) accumulated in Double and
  stored float32. Offline (`mean_s3.py`): slabs of 16 scan rows (134 MB), Double accumulation, one cast to float32; the Metal
  tile means are Float, so the two differ by float rounding (about 1e-7 relative), not by method. Pixel (row, col) = array
  indices [qx, qy] of the last two HDF5 axes (`DatasetDescriptor.swift:41-42`: shape[2] = rows, shape[3] = columns).
- **Fit frame.** `EllipseCalibration.swift:158-166`: loop variable "qx" over rows, "qy" over columns, pixel
  `pixels[qx * width + qy]`, an annulus test `radius > inner, radius <= outer` with the pixel at its integer index.
  The radial profile (`profile.py`) uses exactly this frame (pixel (row, col) at integer coordinates).
- **Bragg-vector map (S4).** `AppState+Calibration.swift:144-162` (Disks mode): `uncorrected` = calibration with ellipse
  a, b, theta nil (`:151-154`); `origin = calibration.meanOrigin ?? (qx/2, qy/2)` (`:155-156`);
  `vectors.calibrated(with: uncorrected, referenceOrigin: origin).map(qy:, qx:)` (`:157-159`).
  `DiskDetection.swift:711-721` `calibrated`: with origin maps of the scan's size (`canUseMaps`) each peak is moved to
  `referenceOrigin + (raw - fittedOrigin[position])` (no ellipse: `ellipseCorrectedOffset` is the identity,
  `Calibration.swift:973-976`); `:746-760` `map`: bilinear deposition of the four neighbouring pixels, weight = the raw peak
  intensity, bounds-checked, Float accumulation, index `yi * qx + xi` with `xi` from `peak.x` (column). The `Calibration.swift:943-950`
  `meanOrigin` is a left-to-right Float sum divided by the Float count.
  **The map is produced by the app's own code**: `bvm/main.swift` is compiled against HEAD's `detection` source group
  (`gates/head/mac4DSTEM`; its whole `mac4DSTEM/Core` tree is identical to the repo's at 26389404, `diff -rq`) and calls `calibrated(...)` and
  `map(...)` unchanged. Cross-check: a numpy mirror of the same rule (Float reference, double accumulation) agrees with the
  Swift map to 3e-5 relative on every pixel above 1e-3 of the maximum (larger only on pixels near zero, where Float
  accumulation order differs), and the nonzero-pixel count is identical (5 041).
- **Axis frame of the peaks.** `BraggPeak.x` = detector column = py4DSTEM `qy`, `.y` = row = `qx`
  (`BraggVectorEMDWriter.swift:2514-2516`, `:721`; origin maps `Calibration.swift:1019+`, `AppState+Open.swift:602`).
  The export wrote `x = qy`, `y = qx`, origin `fittedX = qy0_fit`, `fittedY = qx0_fit`, position index `p = rx * 128 + ry`.

## S3 (mean pattern)

Dynamic range 8e-10 to 2.1e-2 (the pattern sums to 0.2496). Central beam to about r = 2.75 px (profile below 1e-3 of its
maximum), then a broad flat floor of about 5e-9 and eight rings (profile: `s3_mean.profile.txt`, 0.5 px bins, 183 lines).

| ring | peak r (value) | left minimum r (value) | right minimum r (value) | annulus | widened |
|---|---|---|---|---|---|
| R1 | 18.75 (5.207e-6) | 8.25 (4.83e-9) | 24.75 (4.99e-9) | 13.500 - 21.750 | 11.500 - 23.750 |
| R2 | 32.25 (3.428e-6) | 24.75 (4.99e-9) | 35.75 (1.22e-7) | 28.500 - 34.000 | 26.500 - 36.000 |
| R3 | 37.75 (5.645e-7) | 35.75 (1.22e-7) | 42.25 (4.59e-9) | 36.750 - 40.000 | 34.750 - 42.000 |
| R4 | 50.25 (3.401e-7) | 42.25 (4.59e-9) | 53.25 (6.92e-9) | 46.250 - 51.750 | 44.250 - 53.750 |
| R5 | 56.75 (3.201e-7) | 53.25 (6.92e-9) | 60.75 (2.72e-9) | 55.000 - 58.750 | 53.000 - 60.750 |

Rings beyond the five (not used): R6 65.75 (1.5e-7), R7 75.25 (2.3e-8), R8 85.25 (5.8e-8; the last two lie beyond the
inscribed detector radius 63.7 and have partial angular coverage). Outer cap 63.738 (farthest edge from the centre guess):
no annulus reaches it. Two things a reader of the annuli should know: R2's top is flat (32.25 and 32.75 equal to four
digits; the argmax takes 32.25), and R3w's inner edge (34.75) lies inside R2's falling flank, where the mean (6.2e-7) is
above R3's own peak (5.6e-7).

## S4 (Bragg-vector map from py4DSTEM's own detection)

**These peaks are py4DSTEM's (vendored 0.14.19), not the app's.** Chain, from `orient_strain_01_WS2.ipynb` (cells read in
full), run in the `py4dstem` env with the vendored package first on the path and the numpy-2 shims
(`s4_common.py`, `s4_detect.py`; whole run 13 s):

1. dp_mean (cell 7): from `s3_mean.f32` (the Double-accumulated mean above, not py4DSTEM's `get_dp_mean`; same quantity).
2. cell 11 `get_probe_size(dp_mean)`: probe_semiangle 1.858419 px, centre (63.842817, 63.842817).
3. cell 15 `get_vacuum_probe(ROI=(10,30,10,30))`: **deviation**: the vendored `DataCube.get_vacuum_probe` slices a tuple
   ROI wrongly (`datacube.py:575` builds `_ROI[10:30, 10:30]`, a 20 x 20 array of ones, so it averages positions
   (0..19, 0..19), not (10..29, 10..29)). The intended block was handed over as its own 20 x 20 datacube with `ROI=None`
   (all its positions), `plot=False`, defaults otherwise (`align=True`, `zero_vacuum=True`).
4. cell 16: `probe.get_kernel(mode='sigmoid', radii=(0, 4 * probe_semiangle), bilinear=True)`.
5. cell 18/19 `find_Bragg_disks` on every position with the notebook's `detect_params` verbatim (corrPower 1, sigma 0,
   edgeBoundary 4, minRelativeIntensity 0, minAbsoluteIntensity 1e-7, minPeakSpacing 12, subpixel 'poly', upsample_factor 8,
   maxNumPeaks 1000). The cube was read in 16-row slabs (never whole); the per-position routine is independent of the slab:
   five positions re-run from slabs with different boundaries, through the notebook's `data=(rxs, rys)` mode, match the
   saved peaks bit for bit (`s4_check.py`). Result: 749 790 peaks, 38 to 51 per position (mean 45.8); one peak per
   position is the central beam (intensity 0.0119), the rest 9e-8 to 2.5e-5.
6. cell 21 `measure_origin()` (no arguments: findcenter 'max', score 'intensity') then `fit_origin()` (fitfunction
   'plane', not robust) with `plot=False` (the notebook plots; irrelevant here). Measured origin std 0.0009 px, fitted
   mean (63.895474, 63.895474), fit residual rms 0.0009 px (the data's beam does not move).
7. The map the app's way, `bvm/main.swift` (above): fitted origins as `OriginMaps`, no ellipse. The app's Float
   `meanOrigin` is (x = col 63.8874969, y = row 63.8875198), 0.008 px below the Double mean 63.895474: that is the app's own
   summation (`Calibration.swift:947`), kept, not corrected. Raw intensity sum 198.2122, map sum 198.2077 (Float
   accumulation in the central pixels, the app's behaviour), maximum 152.96 at the centre, all finite, 5 041 nonzero pixels.

The map is sparse: exact zeros between the rings (r < 16.25, 21.25-29.25, ...), so the minima beside a ring are often a
plateau of zeros; the rule's tie goes to the bin nearest the ring.

| ring | peak r (value) | left minimum r (value) | right minimum r (value) | annulus | widened |
|---|---|---|---|---|---|
| R1 | 18.75 (1.066e-2) | 16.25 (0) | 21.25 (0) | 17.500 - 20.000 | 15.500 - 22.000 |
| R2 | 32.75 (6.154e-3) | 29.25 (0) | 35.25 (9.67e-10) | 31.000 - 34.000 | 29.000 - 36.000 |
| R3 | 37.75 (7.915e-4) | 35.25 (9.67e-10) | 40.25 (0) | 36.500 - 39.000 | 34.500 - 41.000 |
| R4 | 50.25 (4.763e-4) | 46.25 (0) | 52.75 (8.0e-12) | 48.250 - 51.500 | 46.250 - 53.500 |
| R5 | 56.25 (4.164e-4) | 52.75 (8.0e-12) | 59.75 (0) | 54.500 - 58.000 | 52.500 - 60.000 |

Beyond the five: R6 65.25 (1.3e-4, with a shoulder to 69), R7 75.75 (1.6e-5), then weaker features past 79.
Outer cap 63.888; no annulus reaches it. The rings sit at the same radii as S3's (18.75 / 32.x / 37.75 / 50.25 /
56.x), as they should for one cube; the map's rings are about 1.1-1.2 px wide at half maximum (R1, R2: peaks are subpixel positions
on a sparse set), the mean pattern's about 3.1-3.2 px.

## The ring rule as fixed here (before any fit; the record's wording leaves these readings open)

Profile: 0.5 px bins, bin-centre radius. Central-beam edge: the first bin below 1e-3 of the profile maximum (S3 2.75,
S4 1.75). A ring peak: the maximum within +-1.5 px (3 bins), beyond the beam edge, at least 1e-3 of the strongest value
beyond the beam, and at least 3 x the larger of its two bounding minima. A minimum: the lowest raw (unsmoothed) bin between
this ring's peak and the neighbouring ring's peak (for ring 1 the beam edge); an exact tie goes to the bin nearest the
ring. Annulus = peak -+ half the distance to that minimum; widened = 2 px more on each side; inner clipped to >= 1, outer
to the farthest-edge distance max(cr, 127 - cr, cc, 127 - cc) (neither clipped here); the five innermost rings. These are
readings, not additions: if the owner wants the minimum read differently (a smoothed profile, the plateau's middle) the
annuli move: S4 R1 would go from [17.5, 20.0] to [13.9, 22.0] if the middles of the zero plateaus (9.0 and 25.25) were taken;
S3 R1's inner edge would move from 13.5 to 13.0 or 14.25 if the flat floor's minimum were read at 7.25 or 9.75 (profile
values 4.84e-9 and 4.88e-9 against 4.83e-9 at 8.25), its outer edge by about 0.5.

## What I could not do or noticed

- S3's centre is the record's 1 % rule, not the app's Origin-calibration result (needs the Metal run; see above). The
  difference to the S4 origin is 0.16 px.
- S4's origin is py4DSTEM's (tutorial) measurement, not the app's `OriginCalibration`; the peaks are py4DSTEM's.
- `plot=False` in the notebook's plotting calls; vacuum-probe ROI deviation (step 3 above).
- The fit harness's header says `DiffractionPattern(qy: cols, qx: rows)`; the app builds `DiffractionPattern(qy: rows, qx: cols)`
  (`AppState+Calibration.swift:160`, `EllipseCalibration.swift:158-164`). Immaterial here (every source is square), a trap
  for a non-square one.
- The mean-pattern floor (5e-9) is the pattern's own tail, not noise; the map's floor is exactly zero. Both facts bear on the
  step-(i) predictions Pi1 (tailed) and Pi2 (flat background), which this preparation does not test.
