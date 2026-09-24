# Gate D — the real Al-Mg-Si cube loses its matrix, 2026-09-24

Owner's go, 2026-09-24: "gate d first, orient coverage after, drive it headless". The defect is
`open-items.md` "The owner's real Al-Mg-Si cube: matrix almost never wins", measured in
[`almgsi-drive-2026-09-23.md`](almgsi-drive-2026-09-23.md) B2/B3: matrix 0.7 % (0.15 % floor) and
2.2 % (0.5 %), β″ speckle, about 4 of 6 detected peaks per pattern unexplained by one Al
orientation. **Cause not established. No fix is proposed here.** This file is committed before
any run; results are appended below it, never edited into it.

Cube: `References/training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5`,
330 × 330 scan, 64 × 64 detector, 0.045741 Å⁻¹ per pixel (the file's own), no truth.

## What the code does today (read, not assumed)

- `PhaseVectorMatcher.map` fits **one** matrix entry for the whole scan
  (`fitMatrixOrientation`, `PhaseVectorMatching.swift:769`: one zone axis, one in-plane angle,
  from ≤ 2000 sampled patterns) and removes, at every position, the vectors within the matrix
  tolerance of that single entry (`:865`).
- A position is **matrix only by exclusion**: fewer than `minimumVectors` = 2 vectors survive
  removal (`:884`). Nothing asks whether the matrix explains the pattern.
- Descan is corrected before matching: `calibratedBraggVectors` shifts each position's peaks by
  its fitted origin (`AppState+PhaseMapping.swift:105`). A moving origin is not a candidate.
- At the drive's scaled tolerance, 0.046 Å⁻¹, an in-plane rotation δ moves a reflection at |g| by
  |g|·δ: the ⟨110⟩Al {111} spots (0.43 Å⁻¹) leave tolerance at about 6°, {004} (0.99 Å⁻¹) at
  about 2.7°.

## Three hypotheses, each with the observation that would refute it

**H1: the Al orientation varies across the scan** (bending, sub-grains, a second grain), so one
global entry cannot remove matrix peaks everywhere.
*Measurement:* per position, the best in-plane angle of the global zone axis (0.5° steps, ±20°
around the global angle), and the best entry over every low-index Al axis (5° steps).
*Prediction:* median |Δθ| from the global angle ≤ 1°; < 10 % of fitted positions beyond 2.5°;
≥ 90 % pick the global ⟨110⟩ axis; a per-position refit raises the explained fraction of all
vectors by < 10 points. **Refuted (H1 holds) if** median |Δθ| > 2°, or > 25 % beyond 2.5°, or the
refit raises the explained fraction by ≥ 20 points. Δθ is also checked for spatial coherence
(neighbour vs random-pair difference), because noise fits scatter and real bending is smooth.

**H2: the unexplained peaks are reflections the reference omits** (the T1 lesson of 2026-09-21:
a weak family under the 5 % intensity floor or outside the excitation slab).
*Measurement:* after removal by the per-position best entry, the survivors' |q| histogram; the
fraction within tolerance of any Al shell radius against the same fraction for uniformly placed
points (the chance baseline); the fraction matching a ⟨110⟩Al reflection built with intensity
floor 0.
*Prediction:* the histogram is peaked, and ≥ 50 % of survivors sit on Al shell radii at ≥ 2×
the chance baseline. **Refuted if** < 30 % sit on Al radii or the rate is within 1.5× chance
(that would point to noise, H3).

**H3: the survivors are weak spurious maxima, and the exclusion rule turns any two of them into
"not matrix".**
*Measurement:* survivors' peak intensity relative to the same pattern's removed (matrix) peaks;
the fraction of positions with ≥ 2 survivors all below 10 % of the pattern's median matrix-peak
intensity; the same at the 0.5 % floor.
*Prediction:* survivors are weak (median ≤ 0.2 of the matrix-peak median); at the 0.15 % floor
≥ 50 % of positions have ≥ 2 survivors, all weak. **Refuted if** survivors' median relative
intensity ≥ 0.5.

H1–H3 are not exclusive. **A template overlay** closes the loop: about 12 patterns, stratified by
the drive's β″ / not-indexed labels, rendered with the detected peaks, the fitted Al template and
the survivors marked, so a reader can see disks against kernel maxima.

## Instrument

A new diagnostic tool, `tools/matrix-orientation-probe/`, built from the app's own sources. It
uses the same pipeline the app does: plane origin fit, a synthetic kernel at the fitted probe
radius, `DiskDetectionParams.detectorAdapted`, calibrated (descan-corrected) vectors, and
`PhaseVectorResolution.scaledToDetector` tolerances. Floors 0.15 % and 0.5 %. Scan stride 2
(165 × 165 = 27 225 positions), since the question is a distribution, not a map count. Its
first check is to reproduce the drive: the global fit must land on ⟨110⟩, explaining about 43 %
of vectors, or it is a different instrument and nothing below it is read.

**Not in scope:** any change to `mac4DSTEM/`; tuning the floor or the β″ library; the fix. An
independent refuter reviews the diagnosis before any fix is proposed to the owner.
