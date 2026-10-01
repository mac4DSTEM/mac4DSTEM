# How py4DSTEM calibrates Q from a known crystal, and whether it gets [001] Al right — 2026-10-01

The owner's question on card Q1 ("how does py4DSTEM do it? we are not reinventing the wheel"). Read-only study (Fable 5.1); the scripts are in `q-calibration-py4dstem-2026-10-01/` (run with the py4dstem env, py4DSTEM from References/py4DSTEM-dev).

# Q1 — how py4DSTEM calibrates the Q pixel size from a known crystal (2026-10-01, read-only)

Pinned copy: References/py4DSTEM-dev (0.14.19). Scripts + logs: $SP/Qpy/synth.py, synth.log, landscape.py, landscape.log.

## 1. What py4DSTEM does
One route only: `Crystal.calibrate_pixel_size` (py4DSTEM/process/diffraction/crystal_calibrate.py:14-163; bound at crystal.py:54-56).
Its sibling `calibrate_unit_cell` (crystal_calibrate.py:168+) fits a, b, c… with the pixel size held, same machinery.
No ring assignment anywhere. The method:
- Experimental side (crystal.py:1406-1482 `calculate_bragg_peak_histogram`): ALL Bragg vectors of ALL positions, `get_vectors(center, ellipse-if-set, pixel=True, rotate-if-set)` → |q| in the CURRENT calibrated units
  → linear-interpolated 1D histogram on k = arange(k_min, k_max, k_step) (k_step 0.002 Å⁻¹ default, k_max = crystal.k_max), weighted by intensity^p · k^q (p=q=1 default), normalised to max 1.
- Model side (utils.py:141-222 `calc_1D_profile`): the crystal's |g| list × `scale_pixel_size`, weights |F|² (`struct_factors_int`, crystal.py:690), same histogram, Gaussian-broadened by `k_broadening` (0.002 Å⁻¹ default = 1 bin), × one global `int_scale` (or one per reflection if `fit_all_intensities`).
- Objective: plain `scipy.optimize.curve_fit` least squares of model vs data profile over (scale, k_broadening, int_scale…), bounds (0, ∞), p0 = (1.0, 0.002, 1) (crystal_calibrate.py:79-105). pixel_size_new = pixel_size_prev / scale (line 112-113).
- So: all rings jointly, |F|²-weighted, a LOCAL optimiser, and it NEEDS a starting pixel size — the one already on the BraggVectors' Calibration (docstring lines 38-42: "a guess of the pixel size in Å⁻¹"; with pixel size 1 the k-grid 0..k_max Å⁻¹ would not even span the pixel radii). Convergence basin: a few percent at the default broadening.

## 2. Does it get [001] Al right? NO — same alias, and its objective prefers it.
Synthetic (synth.py): py4DSTEM's own Al Crystal (a 4.05), Bragg set = [001]-zone (hk0, h,k even) only, |F|² intensities, 16 positions, 0.3 px jitter, true pixel 0.01 Å⁻¹. `calibrate_pixel_size(scale_pixel_size=1.0)` from a nominal pixel size off by factor f (returned/true):
- defaults: f 1.00→1.000, 0.95→0.948, 1.05→1.048, 0.90→0.867, 1.10→1.093, 0.866→0.865, 0.80→0.866, 1.20→1.167, 0.707→0.707, 1.414→1.415.
  (±5 % barely moves — 1-bin-wide combs give no gradient; −10/−20 % land in the (200)-as-(111) basin at 0.866.)
- k_broadening 0.02: 1.0/1.05/1.1/0.8/1.2 → 1.000; 0.95→0.865; 0.90→0.867; 0.866→0.865; 0.707→0.773; 1.414→1.415.
- k_broadening 0.02 + fit_all_intensities: 0.95→0.447, 0.80→0.388, 1.20→1.660 (free per-peak intensities make it worse).
Objective landscape (landscape.py, best int_scale per scale, k_broadening 0.002): minima sorted by SSE — model-scale 1.154 (= pixel 0.866, the (200)↔(111) alias) SSE 1.457 < truth 1.000 SSE 1.517 < √2 alias 1.718. Same order at broadening 0.02 (1.755 vs 1.761).
Why: the data's strongest ring (200) against the model's strongest (111) is the deepest overlap; the model's unmatched {111},{311},{331}… cost about the same in either basin. The fcc √2 self-similarity gives further minima at 0.707/1.414 exactly as the card says. py4DSTEM resolves none of this; it relies on the user's nominal pixel size being within ~5 %.

## 3. App vs py4DSTEM, and the port
App (Core/Analysis/QCalibration.swift:161-269; caller App/AppState+ACOM.swift:76-100): per-position innermost same-shell cluster mean → median over positions → scale = g(first allowed shell, Crystal.reflections kMax 2.5) / r₁. One ring, no intensities, no prior, second shell measured only as a reported ratio. Differences: (a) py4DSTEM fits the whole comb |F|²-weighted; (b) py4DSTEM starts from a prior and refines locally; (c) py4DSTEM applies ellipse/rotation through get_vectors (the app's `calibratedBraggVectors` already does the equivalent).
Smallest faithful port (≈ 150 lines Core): `KnownCrystalQCalibration.fitComb(bragg, origin, crystal, priorPixelSize, window)` = port of calculate_bragg_peak_histogram + calc_1D_profile + a scale search; prior = the file's Q pixel size when `provenance.qScale == .importedFile`; DEVIATION: bounded grid (±10 %, 0.2 % steps) then parabolic refine instead of curve_fit (curve_fit does not move at the 1-bin default broadening and walks into the alias from −10 %). Report the residual beside the pixel size. Without a file prior, fall back to today's first-shell estimate + "unchecked".
Risk: it inherits py4DSTEM's limit — on [001] Al with no prior within ~5 % it returns the SAME 13 %-low answer (and its objective calls that the better fit), so it is not the fix for the owner's cubes unless his DM4 metadata carries a usable Q pixel size; the prior window is a threshold and needs its own measurement. The refuter's per-zone rule (slot1-q-refuter-2026-09-30.md:143-152: 4 equivalents at 90° ⇒ [001] ⇒ innermost = (200)) is the cheap non-py4DSTEM fix and is not a port.
Harnesses re-pinned: QCalibrationShellBadgeTests, QCalibrationOriginGateTests, tools/q-calibration-gate-test, tools/q-shell-probe, tools/origin-fit-diagnostics/shell-check; plus one NEW harness pinning the Swift histogram/profile to py4DSTEM's on the synthetic. Keep `QCalibrationEstimate` additive so acom-matching-test, real-acom-benchmark, strain-test, training-dataset-campaign stay.
