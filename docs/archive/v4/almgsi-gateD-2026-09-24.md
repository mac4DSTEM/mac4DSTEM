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

## Result, part 3: H5 (runs `gd-h5.log` at 0.15 % and `gd-05.log` at 0.5 %, all exit 0)

| | predicted | 0.15 % floor | 0.5 % floor |
|---|---|---|---|
| (a) RMS residual, 8 centres | ≤ 0.3 px | **0.153 px** | 0.131 px |
| axis ratio (major axis) | 1.05–1.15 | **1.0853** (69.6°) | 1.0841 (69.6°) |
| Q = 0.4939 / √det A | 0.0265 ± 3 % | **0.026392** | 0.026431 |
| (b) ⟨100⟩ after correction | ≥ 80 % | **94.5 %** (next family 24.0 %) | not re-run |
| (c) drive's map, matrix | ≥ 70 % | **91.1 %** (β″ 0.8, not indexed 8.1) | not re-run |
| (d) {400}/{420} hits vs chance | ≥ 3× | **33 vs 0.5 (65×)**, 2 of 12 positions inside the detector, 81 peaks beyond 33 px | — |

**H5 holds on every registered criterion.** The 0.5 % run also completes part 1's registration.
It reproduces the drive (matrix 1.9, β″ 20.2 / 13.9, not indexed 64.1 %; drive 2.2 / 19.6 /
13.5 / 64.7), and H1 and H3 are refuted there too (median |Δθ| 0.5°; survivors median 0.55).

**A correction to part 2's claim about what can support H5, made before the refuter saw it.**
A linear map can carry any 2D lattice onto any other. The 0.15 px residual and the (d) hits
therefore prove that the disks form **one distorted 2D lattice**. They do not by themselves
prove the zone. What picks [001] over the alternatives:
- the **size of the distortion** each reading needs. An equal-sided rhombus of 84° becomes a
  square with an axis ratio of 1/tan 42° ≈ 1.11 (fitted: 1.085). It becomes ⟨110⟩'s
  70.5° rhombus only with tan 42° / tan 35.26° ≈ 1.27, a 27 % distortion;
- **nothing inside the inner ring**, which fits fcc [001] ({200} is the innermost reflection);
- no fcc zone gives an undistorted equal-sided 84° rhombus with an empty interior. [113] and
  [012] were checked by hand and do not.

**Robust to the zone question:** at the file's Q, 0.045741 Å⁻¹/px, the inner ring is at
0.852 Å⁻¹, and Al has no zone whose innermost reflection sits there. **The file's Q is wrong
for Al under any reading.** Observation, no mechanism claimed: the file's Q is 1.733× the
fitted one, which is √3 to within 0.1 %.

**Diagnosis (for the refuter):** the matrix is lost because the cube's calibration is wrong
twice. Its Q is about 1.73× too large, and the pattern carries an elliptical distortion of
about 8.5 % (major axis at 69.6° in the detector) that the drive did not model. With both
corrected, the app's own matcher calls 91 % of positions matrix, and β″ falls from 45 % to
0.8 %. The matcher did what it was given. **No app code is implicated by this mechanism.**

## Part 4: independent refuter (Sonnet, own numpy on `gd-peaks-015.json`, no repo code run)

1. **Fit: NOT REFUTED.** Re-derived from the raw peaks: RMS 0.1528 px, axis ratio 1.0853,
   69.6°, Q 0.026392. Exact.
2. **Zone: PARTLY.** A ⟨110⟩ ideal gives the **identical** RMS (0.1528 px). This is provable:
   one ideal lattice is a fixed linear reparametrisation of the other. **So the residual can
   never tell zones apart**, which is stronger than part 3's caveat. What does tell them apart:
   the axis ratio each needs ([001] 1.085, ⟨110⟩ **1.305**), and the intensities. The four
   inner spots are near-equal (spread 1.19×), and inner ({200}) are 6.3× stronger than outer
   ({220}), as fcc [001] predicts. An oblique 8.5 % ellipse is on the high side but plausible
   for 4D-STEM. Its 69.6° angle argues against non-square binned pixels.
3. **"The file's Q is wrong for Al": holds.** Across 175 low-index fcc zones, none has its
   innermost reflection near 0.852 Å⁻¹. Only implausible high-index axes such as [1 2 5] come
   close, and they would not give this pattern.
4. **(d): REFUTED as evidence.** The only two predicted positions inside the detector are a
   Friedel pair at r ≈ 40.7 px, in the detector's corners. At that radius a square detector
   admits peaks only in a wedge about 0.85° wide per corner, narrower than the 1 px match
   disk. Any peak that far out "hits" by geometry. **The 65× is an artefact of the detector's
   shape, and (d) supports nothing.** The criterion stays as registered; the evidence is
   withdrawn.
5. **Reproduction: NOT REFUTED.** The tool's steps trace to `AppState+PhaseMapping.swift`. The
   ≤ 1.4-point gaps to the drive plausibly come from the kernel choice, which the drive record
   does not state.
6. **Provenance:** `h5dump -A` shows the file stores 0.0457415 Å⁻¹ in `Q_pixel_size`, `dim2` and
   `dim3`, consistently. The app read what the file says. The √3 ratio stays unexplained.

## Conclusion

**Cause established:** the cube's calibration is wrong twice, and the matcher did what it was
given. Q is 1.733× too large (the file says 0.045741 Å⁻¹/px; the data says 0.02639), and an
elliptical distortion (axis ratio 1.085, major axis 69.6°) was not modelled. The specimen is on
**[001]Al**, not ⟨110⟩Al as recorded since 2026-09-12. Corrected, the app's own matcher calls
91.1 % of positions matrix; β″ falls from 45 % to 0.8 %. The evidence for [001] is the distortion
size, the empty interior and the {200}/{220} intensities. The residual and (d) are not
evidence. **No app code is implicated in the mechanism.** Two app gaps it exposed go to the
owner, not into a fix:
- the ellipse can come only from the app's own ring fit, a py4DSTEM file or a session. There
  is no manual entry, and a four-spot ring is too sparse for the ring fit (refused unless "Fit
  Anyway");
- nothing flagged a matrix fit explaining 43 % of vectors. A correct identification here
  explains about 95 %. By the threshold rule this is a quantity to show, not a cut-off to
  invent.

## Part 5: where the file's Q came from (owner's question 1, 2026-09-24)

The owner's preprocessing notebook (`LMN_MA_4DSTEM/code/4DSTEM_first_steps_loading_preprosessing.ipynb`,
on the owner's backup volume) runs `py4DSTEM.import_file(dm4)` → `bin_Q(n)` → `save`. It hardcodes
no calibration. The raw file (`4DSTEM_170330/ROI_5/raw/SI data (7)/060_STEM SI.dm4`, 28 GB, read
with ncempy header-only) stores **Dimension 1/2 Scale 0.11435369 nm⁻¹/px** on a 256 × 256 frame:
GIF Continuum, 4× hardware binning, 200 kV, STEM camera length 60, alpha tilt 18.1°. Divided
by 10 (nm⁻¹ → Å⁻¹) and multiplied by 4 (`bin_Q(4)`), that is 0.0457415, **exactly the stored
Q**. The preprocessed file on the backup is byte-identical to `References/training_dataset/`.

- **py4DSTEM carried the microscope's recorded scale faithfully. The error is in
  DigitalMicrograph's diffraction calibration** for that setup, 1.733× the value the Al [001]
  lattice gives. The same notebook's other dataset (Ni65Cu35, also CL 60, 2024-11) recorded
  0.0196 Å⁻¹/px unbinned. The recorded scale is not even consistent between sessions at one
  nominal camera length.
- `Au_ref_ROI15_…bin_4_20241214.h5` stores the same 0.04574148. Its strongest rings, at 25.38
  and 29.62 px (ratio 1.1675, close to Au {200}/{111} = 1.1547), would put its true Q near
  0.0167 Å⁻¹/px. **Not claimed**: its disks are large (probe radius 8 px), 35 % of its peaks lie
  inside the first ring, and its raw metadata is not on hand.
- The ellipse: energy-filter (GIF) optics are a plausible source of a several-percent
  distortion. Not measured here, and no mechanism is claimed.

**Consequence for the app:** on data from this microscope setup, a file's Q cannot be trusted.
Q, and the ellipse, must come from a known crystal in the data.

## Part 6: preprocessing in mac4DSTEM (plan C), status and runbook, 2026-09-24

**What happened.** The first attempt to observe the DM4 bug opened the 28 GB raw
`060_STEM SI.dm4` (exFAT via FSKit on the owner's external SSD) through the **unfixed** reader on
this 8 GB Mac. `.mappedIfSafe` read it into anonymous memory, swap ran out and the kernel
panicked (watchdog timeout, "LOW swap space"). The session's scratchpad was lost with it. No
number from that run exists. **Rule since:** memory bugs are reproduced on small files only.

**What is ready (uncommitted until its proof):**
- the fix, `DM4Reader.readingOptions(forPath:)`: map on any `MNT_LOCAL` volume, keep
  `.mappedIfSafe` on network volumes;
- `tools/dm4-parity-probe/` (`diagnostic`): `--make-fixture` (a 128 MB synthetic 4D DM4 from the
  robustness harness's writer), `--foundation-check` (the mechanism, as footprint deltas),
  `--open-only`, and `--parity RAW.dm4 PRE.h5 --bin 4`. That last one compares every position of
  the app's own binned raw read (sum, like py4DSTEM `bin_Q`) with the py4DSTEM file, plus a
  transposed comparison. Both sides are float32 (DM data type 2), so py4DSTEM's
  `.astype(dtype)` cannot have wrapped.

**Proof on this Mac, owed next:** the fixture on an exFAT disk image, `--foundation-check`
(prediction: `.mappedIfSafe` grows the footprint by about the file size, `.alwaysMapped` does
not), then `--open-only` through the fixed reader. Then Gate B on the fix.

**Runbook for the owner's stronger Mac:** close every other heavy process, then

```sh
tools/dm4-parity-probe/run.sh --parity "<…>/ROI_5/raw/SI data (7)/060_STEM SI.dm4" \
  "References/training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5" --bin 4
```

Predicted: 108 900 patterns compared, max relative Δ ≤ 1e-6 (float32 summation order only), and
a transposed max |Δ| far larger. Run it only with the fix in place; the probe's watchdog is a
backstop, not protection.

## Part 7: the owner's in-app re-drive with the lattice calibration, 2026-09-25

**How the calibration got into the app.** The app has no field for an ellipse. It reads py4DSTEM's
calibration keys `a`, `b`, `theta` from the file. So a copy of the cube, `…bin_4_20260712_ellipse-20260925.h5`
(gitignored), got three datasets added to `dm_dataset_root/metadatabundle/calibration`. The
values came from the whole-cube lattice fit (Q 0.026384, ratio 1.0853, major axis 69.5° in x/y;
`lattice-calibration-feasibility` part 3). They were converted through a literal port of
`Calibration.ellipseTransform`, now `tools/lattice-calibration-probe/app_ellipse.py`. Applying that
port to the cube's own peaks and refitting gives a round lattice (axis ratio 1.0001, 95.2 %
explained) at **Q 0.027488 Å⁻¹ per corrected px**. That is the Q to type, not 0.02639: the ellipse
leaves the minor axis at scale and stretches the major one. It becomes 0.027553 with the paper's
Al CIF, a = 4.04 Å. Slip: the copy carries a = 21.1647 and b = 19.5013 px. The ratio and θ are
right, and the correction reads only b/a and θ. The absolute sizes are 8.5 % large, so the
overlay ellipse is drawn outside the {200} disks. The tool now prints 19.50 / 17.97.

**Driven by the owner** (their build, the ellipse copy; screenshots in the session, not
retained). Prepare showed "Ellipse distortion · From file · a 21.16 · b 19.5 · θ 20.5°". The log
reported "pair radius 0.0275 Å⁻¹, one detector pixel", so Q ≈ 0.0275 was in force. Disk detection
at the 0.15 % floor found 1 010 514 peaks. Phases: `Al_thronsen2024.cif` plus
`beta_double_prime_Mg5Si6_needle.cif` and `beta_double_prime_Mg5Si6.cif`. **Both β″ slots stayed at
[0 0 1]**; the end-on [0 1 0] slot was never set. Search rule.
- Find Matrix Zone Axis: **⟨100⟩, 88 % of vectors at 0.0096 Å⁻¹**, three equivalent axes tied
  (at the file's Q on 2026-09-24: ⟨110⟩, 43 %). The app now agrees with parts 3–4.
- Map: **matrix 99 976 (91.8 %)**, β″ 90 + 123 (0.1 % + 0.1 %), not indexed 8 711 (8.0 %) of
  108 900. The corrected probe run of part 3 gave 91.1 % matrix at stride 2.
- The map shows **two perpendicular families of streaks**, which are the in-plane needles. As
  read from the screenshot, **they are drawn in the not-indexed grey**. The β″ calls are
  scattered 1-px specks: 80 + 98 objects, median length 1.54 nm, which is one scan pixel. So the
  needles are located by exclusion (matrix removal leaves their vectors unexplained), not
  identified as β″. The run did not include the end-on slot, so whether [0 1 0] would claim the
  end-on cross-sections is untested.
- Show Objects on 1-px objects shows nothing the owner could see ("does not seem to do a lot").
  The Object Table read well.

**Re-runs the same afternoon, with one slot set to [0 1 0]** (as in the app log; screenshot not
retained):
- **Search rule:** β″[010] 755, β″[001] 102, matrix 99 976, not indexed 8 067. The end-on slot
  claims only 665 more positions, and the streaks stay not indexed.
- **Known-variants rule** (guard k = 1; the log's last line): **β″[010] 5 633 (5.2 %), β″[001] 1 705
  (1.6 %), matrix 101 512 (93.2 %), not indexed 50 (0.05 %).** The streaks are now drawn in β″
  colours, mostly the [0 1 0] slot's. Scattered 1-px β″ specks remain across the matrix. At
  minimum size 1 there are 1 464 + 672 objects, median 1.54 nm (one scan pixel), and 58 on the
  scan edge. The needles are fragmented and speckle dominates the count.
- Open question, not tested: why the in-plane streaks take the [0 1 0] (end-on) slot's label.
  Either the known-variants rule labels a slot's whole variant set, or the label is wrong for
  in-plane needles. Read `PhaseVectorMatching`'s variant generation before interpreting it.

**Not claimed:** that β″ is mapped, that any fraction is a precipitate fraction, or that the object
counts are counts. These are runs of an unvalidated method, and the object pass bar (T4) is still
the owner's decision.
