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
