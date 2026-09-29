# The owner's raw Al-Mg-Si cube at stride 3 — calibration and first analysis, registered (2026-09-29)

Cube: `ROI_5/mac4dstem_subsampled/060_STEM_SI_stride3.h5` on the owner's SSD — 110 × 110 positions (4.618 nm step),
256 × 256 detector, bit-identical to the raw (`ssd-subsample-2026-09-29.md`). The file's Q, 0.011435 Å⁻¹/px, is the
raw DM value — exactly ¼ of the binned file's 0.045741, which the 2026-09-24 Gate D showed is 1.733× too large
(`almgsi-gateD-2026-09-24.md`: the data's own lattice gave 0.02639 Å⁻¹/px on the 64² detector, specimen on [001]Al,
an ≈ 8.5 % oblique ellipse, typed later as py4DSTEM's (a, b, θ) = (19.50, 17.97, 20.5°), ADR 039).

## Method (the 2026-09-24 recipe, scaled to the 256² detector)

Peaks from `tools/matrix-orientation-probe --dump-peaks` (0.15 % floor, disk radius and tolerances scaled to the
detector), then `tools/lattice-calibration-probe` (`lattice_fit.py --expect`) for Q, axis ratio and angle from the
Al lattice alone; then the phase map (Al + β″ [010]/[001], known variants) with that calibration. Memory rules: one
heavy job at a time, reads from the SSD, footprint watched.

## Predictions (fixed now)

1. **Q from the lattice = 0.02639 / 4 = 0.00660 Å⁻¹/px** (within 1.5 %); the file's 0.011435 is again 1.73× too
   large. The {200} ring sits near 0.4939 / 0.00660 ≈ 74.9 px.
2. **Ellipse:** axis ratio ≈ 19.50 / 17.97 = 1.085 (± 0.015), angle ≈ 20.5° (± 3°) — the same distortion, since
   binning does not change geometry; in py4DSTEM's (a, b) that is ≈ (78.0, 71.9) px. A transposed angle (≈ −20.5° or
   ≈ 69.5°) would be an axis-convention difference between the DM raw and the preprocessed file, reported, not failed.
3. **Zone:** [001]Al ranks first by explained vectors, as on the binned cube.
4. **Map:** matrix ≥ 85 % of positions (binned, corrected: 91.1 %); β″ and not-indexed fractions reported, not
   barred — 4× finer detector sampling may change what the detector resolves, which is the question this cube asks.

**Refuted if** Q differs from 0.00660 by > 1.5 %, or the axis ratio from 1.085 by > 0.015: then the binned file and
the raw differ in geometry, not only in sampling, and that is the finding.

## Result (2026-09-29; Sonnet runner, logs `raw3-*` in the session scratchpad; every run under a footprint guard)

| | predicted | measured | |
|---|---|---|---|
| Q | 0.00660 ± 1.5 % | **0.006577** (−0.34 %) | HELD |
| axis ratio | 1.085 ± 0.015 | **1.0846** | HELD |
| angle (py4DSTEM θ) | 20.5° ± 3° | **20.8°** (69.2° in lattice_fit's x/y frame; binned 69.6°) | HELD |
| zone | [001] first | **[001], 92.9 %** of vectors (next 24 %) | HELD |
| {200} ring | ≈ 74.9 px | 75.1 px; py4DSTEM (a, b) = (78.2, 72.1) | — |
| matrix | ≥ 85 % | **86.4 %** (β″ [010] 0.8, [001] 0.2, not indexed 12.6) | HELD |

104 050 peaks, all 110 × 110 positions, disk radius measured 10.24 px, 0.15 % floor. The file's Q is again 1.74× too
large. For the app: Q 0.006850 Å⁻¹ per corrected pixel with the ellipse (`app_ellipse.py`). Raw and binned agree
in geometry; no axis-convention difference. Matrix 4.7 pp below the binned cube's 91.1 %.

**Two findings about the app, not the specimen:**
1. **GPU memory grows per tile in `TiledDiskDetection.detectAll` on this 3.2 GB cube:** the guard killed three runs
   (2.1, 1.8, 1.6 GB footprint); `vmmap` showed IOAccelerator 770 MB in 22 tile-sized buffers. In the probe only, each
   tile in an `autoreleasepool` (same arithmetic; peaks identical on an 8-row crop) held it at ≈ 500 MB. Mechanism
   not proved; the app's own Detect All Disks likely shares it — **do not run it in the app on this cube until a
   Gate D.**
2. **The phase-match tolerance is in detector pixels:** at the app's 1 px on a 256² detector (0.0066 Å⁻¹, a quarter
   of the binned run's physical tolerance) 97.0 % of positions are not indexed; at 4 px (the binned run's physical
   tolerance, the registered scaling) 86.4 % are matrix.

Not done: known variants (the matrix-orientation probe has only the search rule); a control at `--px-scale 1`.
The probe takes the fitted stretch as `--distortion-matrix` (no ellipse input), dropping the fit's in-plane rotation
(harmless on square [001]).


## The app recipe for this cube (given to the owner 2026-09-30; from this record and D1, not yet confirmed by his run)

Prepare, in this order: ellipse (manual a, b, θ) **78,2 / 72,1 / 20,8°**, applied first; Q manual **0,0685 nm⁻¹**
(= 0.006850 Å⁻¹ per ellipse-corrected pixel — the file's 0.1144 nm⁻¹ is 1.74× too large; "On this detector" should
then read ≈ 2.9 px, not 1.75); R manual **4,618 nm** (the stride-3 step); R–Q as measured (83.7° in his run). Disks: the
0.15 % floor gives **116 150 peaks**, the probe's count exactly — no re-detection needed after the calibration.
Phase mapping: Al (matrix, zone 0 0 1) + `beta_double_prime_Mg5Si6.cif` **twice**, zones **0 1 0** (needles end-on)
and **0 0 1** (in-plane); "Parallel to matrix" empty; classifier **Known variants**; tolerances left at the shipped
**0,020 / 0,020 / 0,015** (D1: 84.4 % matrix here; never "Scale to this detector"); ignore peaks beyond 0. Precipitates:
no validated minimum size — compare 1, 3, 5 px; quote densities with pixel size, minimum size and count. Expect
fragmented needles (seen on the binned cube). To become a preset in polish session S4 once his run confirms it.
