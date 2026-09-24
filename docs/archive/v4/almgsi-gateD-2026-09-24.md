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

## Result, part 1: the 0.15 % floor (run 2026-09-24, `gd-015.log`, exit 0)

The line citation above should read `:882`, not `:884`.

**The instrument reproduces the drive.** Axis ⟨110⟩ at 43.6 % of sampled vectors (drive 43 %),
with all five ⟨110⟩ tied at exactly 1451 of 3331. Map at stride 2: matrix 0.6, β″[010] 28.2,
β″[001] 17.0, not indexed 54.1 % (drive 0.7 / 27.1 / 16.6 / 55.7). Origin plane fit spans
0.27 × 0.17 px, so descan is negligible. 1 010 514 peaks, median 9 per pattern, identical to
the drive.

- **H1: REFUTED, as predicted.** The refit's median |Δθ| is 0.50°, which is the sweep step, and
  the 95th percentile is 1.5°. A neighbour's Δθ differs by as much as a random position's does
  (0.50° vs 0.50°), so there is no spatial structure. 99.9 % of positions pick the global axis.
  The in-plane refit raises the explained fraction from 43.7 to 51.5 % (+7.8 points, under
  the 10-point bar). The orientation does not vary.
- **H2: REFUTED by its stated criterion, and the criterion had no power.** 81.4 % of the
  survivors sit on an Al shell radius, but uniform chance is 77.8 %: at a 0.046 Å⁻¹ tolerance
  the Al shells cover most of the annulus. The part with power: **0.0 % of survivors match a
  ⟨0 -1 1⟩Al reflection at intensity floor 0**, so the reference omits nothing. The histogram
  is sharply peaked, but at |q| 0.84–0.88 and 1.14–1.18 Å⁻¹.
- **H3: REFUTED.** The survivors are strong: median 0.68 of the same pattern's matrix-peak
  intensity (75th percentile 1.9). No position has two or more survivors that are all weak.

**The overlay** (`gd-015-overlay.png`: 12 patterns, 3 per drive label) shows why. Every pattern
has about eight clean disks plus the direct beam, all real, on two rings. The dense ⟨110⟩
template (34 vectors) catches about half of them by density and misses the rest by about a
pixel. The disks are arranged four-fold: an inner four about 90° apart, and an outer four
offset about 45° at about √2 the radius. Nothing lies inside the inner ring. **This was seen,
not predicted**, so it is registered below as H4 before it is tested.

## H4, registered after the overlay and before its test

**H4: the specimen is on [001]Al and the file's Q, 0.045741 Å⁻¹/px, is about 1.7× too large.**
The inner ring is then {200} (0.4939 Å⁻¹) and the outer ring {220}. The dense ⟨110⟩ entry won
only because, at the wrong scale, it covers the detector densely enough to catch half of any
pattern. All five ⟨110⟩ tying exactly is the tell.

*Measurement:* the same tool, with rings measured in detector pixels (no Q involved), then the
whole pipeline re-run at Q = 0.4939 / r1.

*Predictions:*
- (a) The two strongest rings have r2/r1 = 1.414 ± 0.03. Each ring's four azimuth clusters are
  spaced 90° ± 3°, and ring 2's clusters sit 45° ± 3° from ring 1's. Under 0.5 % of peaks lie
  inside r1 apart from the direct beam.
- (b) At Q = 0.4939 / r1, `fitZoneAxis` ranks a ⟨100⟩ axis first, explaining ≥ 80 % of vectors
  and ≥ 20 points above the best non-⟨100⟩ axis.
- (c) At that Q, the drive's map (Al + β″ [010] and [001], search rule, scaled tolerances)
  calls ≥ 70 % of positions matrix.

**Refuted if:** ring 1's clusters are spaced about 70.5° / 109.5° (⟨110⟩ {111}), or r2/r1 is
not √2 within 0.03; or at the new Q a ⟨110⟩ axis still wins, or ⟨100⟩ explains < 60 %. Q is set
from ring 1 alone, so ring 2, the zone-axis ranking and the map are independent checks on it.
**If H4 holds, the cause is the dataset's calibration, not the matcher**, and no app code
would change. The app's known-crystal Q estimate (`KnownCrystalQCalibration`), and whether the
app should have caught this, is the follow-on question for the owner.

## Result, part 2: H4 (runs `gd-h4a.log` and `gd-h4b.log`, both exit 0)

- **(a) REFUTED as registered.** The strongest rings are at 18.62 and 27.62 px, r2/r1 = 1.483
  (predicted 1.414 ± 0.03). Ring 1's azimuth clusters are spaced 84° / 96° and ring 2's
  87° / 93°, both outside 90° ± 3°. Ring 2 sits 42° / 45° off ring 1. **What held: 0.09 % of
  peaks lie inside r1** apart from the direct beam.
- **(b) REFUTED as registered (below the 60 % bar), though the ranking moved decisively.** At
  Q = 0.4939 / 18.62 = 0.026518 Å⁻¹/px, the ⟨100⟩ family wins with 53.1 % of vectors. The best
  non-⟨100⟩ axis explains 18.2 %, a 35-point gap. At the file's Q, the whole ⟨110⟩ family tied
  at 43.6 % and the runner-up family was not separated.
- **(c) REFUTED.** Matrix 2.2 %, β″[001] 77.8 %, not indexed 16.0 %.
- **Correction to H4's text:** an exact tie across one family is not a "tell". The members of a
  family are symmetry-equivalent, so they project to the same pattern and tie whenever they are
  swept at the same rotations. The ⟨100⟩ family ties the same way at the new Q.

**What part 2 establishes, independent of H4's fate.** At the file's Q, ⟨110⟩Al puts its
strongest reflections, {111} and {200}, at 9.4 and 10.8 px. The data has 0.09 % of its peaks
inside 17 px. **So the drive's "⟨110⟩, 43 %" was a density match, not an identification, and
the premise carried since 2026-09-12 ("the specimen sits on ⟨110⟩Al") is unsupported.** The
pattern is four-fold-like, but not square: a rhombus of 84° / 96°, with the outer ring split.
A square seen through an elliptical distortion of about 5 % gives exactly that. That is H5,
registered here before its test.

## H5, registered before its test

**H5: [001]Al, seen through a linear (elliptical) distortion of the diffraction pattern, at a Q
near 0.0265 Å⁻¹/px.**

*Measurement:* the whole-scan cluster centres of the four inner spots and the four outer spots
(the outer ones taken as the sums of adjacent inner ones). One 2 × 2 map A is fitted, with
ideal {200} = unit vectors. A's polar decomposition gives the ellipse axis ratio and angle, and
Q = 0.4939 / √det A. The pipeline is then re-run with every vector mapped through A⁻¹ and
scaled so {200} = 0.4939 Å⁻¹. This is equivalent to Q + ellipse (a, b, θ) + an in-plane
rotation that the matcher searches anyway.

*Predictions:*
- (a) A fits the eight centres with an RMS residual ≤ 0.3 px. The axis ratio is 1.05–1.15
  (≈ 1.11 from the 84° gap) and Q is within 3 % of 0.0265.
- (b) After correction, ⟨100⟩ ranks first and explains ≥ 80 % of vectors.
- (c) The drive's map calls ≥ 70 % of positions matrix.
- (d) **The test that does not reuse the fit's own peaks:** peaks near the predicted {400} and
  {420} positions (A·(±2, 0), A·(±2, ±1) and so on, in the detector corners) at ≥ 3× the rate
  of an equal area at the same radius. This is reported as untestable if fewer than 50 peaks
  lie beyond 33 px.

**Refuted if** the RMS is > 0.6 px, or (b) is < 60 %, or (c) is < 50 %, or (d) is < 1.5×
chance. (a)–(c) partly reuse the peaks A was fitted to, so they can only refute. Only the
residual and (d) can support H5.
