# S20 ACOM off-grid recovery: pre-registration (written 2026-09-30, before any run)

Item: `open-items.md` "ACOM / zone-axis science residuals" (26 of 200 templates fail to recover themselves off-grid; zone axis up
to 12.8 deg beyond the bank's floor). Records: `archive/v3/acom-zone-axis-2026-09-15.md`, `archive/v3/open-items-detail-2026-09-16.md`.
YELLOW: measure, refute, propose; probes live in the session scratchpad, nothing in `mac4DSTEM/` changes.
## Already spent (not re-tested unchanged)
 radial binning; bank kMax; intensity power; `power_radial`; reduced blur; per-ring and whole-image L2; parabolic peak
interpolation; 1000 templates (68 vs 48 wrong of 136); linear azimuthal deposition (40 -> 28 of 136 wrong, but <012>/<112>, exact today,
made wrong); Gaussian deposition at the exact fractional bin (same answer). Seen 2026-09-15 on ONE case only (<122>, 0.35 deg, winner
+4.88 %): the truth's ring groups peak at shifts 57 and 58, the winner's agree at 13. Never done: the dump for the 26; 512/1024 azimuthal bins were tried with the blur held at 1.5 BINS, so the blur shrank in degrees at the same time.

## Question
Why does the true template lose off-grid, and does one change to the score/plan recover >= 24 of the 26?

## Step 1 (this file's job): the dump, before any fix
Production `OrientationPlan`/`OrientationMatcher` copied to the scratchpad (Al fcc a = 4.0495 A, kMax 1.2, 200 templates, 32 x 128,
defaults). Cases: (a) the worst self-recovery failure (peaks = template i's own spots, intensity weight^(1/0.25), rotated 1.4 deg = 0.498
bin and by 0.35 deg x k; failure = winner axis > 0.5 deg from i's); (b) planted <122> at 0.35 deg (plant: `git show
2e805f9:tools/acom-groundtruth/orientation-accuracy.py`). For truth and winner dump: spots (r, azimuth, weight, deposited bin, fractional
offset), counts, matched-spot count, score, per-ring best shift and value, and the score with UNROUNDED azimuth (continuous sub-bin
shift), to separate quantisation loss from intrinsic dissimilarity. Reproduction gate: failures must land in 20-32 with 0/200 on-grid
(rotation 0, 2.8125 x k deg); else report the count found, say 26 is not reproduced, go no further on the number.

## Datasets (every one a scoring change would touch and that exists on this Mac)
Synthetic: the 200-template bank (wavelength nil AND 200 kV curvature: the app passes one when a voltage is known); the 136 planted
patterns (9 Al axes x 17 rotations, < 5-spot plants dropped); the WS2 hex fixture. Pinned harnesses:
acom-orientation-test, acom-matching-test (WS2 8/8, defect 0-1/8), acom-convention-test (median < 3 deg cubic / < 2 hex, 40 external
cases), fit-overlay-test, phase-vector-matching, parity-metric-test; unit ACOMScanSelection / DemoWorkflow / ACOMSession. Real, ACOM'd: `demo-dataset/AlMgSi_demo.h5` (truth.json grain orientations; grain B <011> came back
7.0 / 3.6 deg off), `thronsen-datasetA/datasetA_stride3.h5` (truth = phase classes only, no orientation truth), and the four
`training_dataset` parity cubes with py4DSTEM ACOM records (`parity_records/latest`: sim_Au, polycrystal_2D_WS2, downsample_Si_SiGe_exp,
Particle_1). Cubes without orientation truth report "positions whose template changed / median change in deg", never accuracy; multi-GB
cubes only via already-detected peak lists, under the footprint guard.

## Statistic
Self-recovery: failures / 200 at off-grid rotations (per rotation, plus the worst-rotation count) and on-grid failures / 200.
Planted: wrong answers / 136 and excess beyond the bank's floor per axis (the shipped 40 / 136, 18.79 deg total; axes exact at every
rotation today: <100> <111> <012> <112>). Dump: per-ring peak-shift spread of truth vs winner; winner/truth spot-count ratio.

## Predictions (direction + numbers, fixed now)
- P1 quantisation phase (H "ring groups"): in >= 22 of the failing self-recovery cases the truth's per-ring peak shifts take >= 2
  distinct values while the winner's take 1, AND the truth's continuous (unrounded) score >= the winner's in >= 24 of 26. If the
  continuous score still loses in > 4 cases, the loss is intrinsic to the polar score, not quantisation, and P1 is refuted.
- P2 density (H1, winner has more spots): refuted for self-recovery: median winner/truth spot-count ratio in 0.75-1.33; at most 4 of
  26 winners have > 1.5x the truth's spots.
- P3 excitation cutoff (H2): no effect on self-recovery (the pattern IS the truth's list); in planted <122> the truth's outer spots are
  down-weighted by sg (1 deg off, g = 1 A^-1: 0.92), explaining < 1 % of the 4.88 % gap.
- P4 in-plane sampling (H3): 512 bins with the blur held at 4.2 deg (6 bins) removes >= 20 of 26 ONLY IF P1 holds (rounding shrinks 4x);
  were the shift grid the mechanism, the truth's rings would agree (contradicting P1) and parabolic interpolation would have worked.
- If P1 holds, the candidate fix class is exact sub-bin azimuth in the FFT domain (ring spectrum written analytically, exp(-i k phi) x
  Gaussian, no rounding; correlation on a zero-padded finer shift grid). A probe must show it differs from the spent deposition variants.

## Bar to propose a change
>= 24 of 26 recovered AND 0 on-grid regressions AND no axis exact at every rotation today becomes wrong in the 136 sweep (what killed
linear deposition) AND every pinned harness and unit class inside its own tolerance. Real-cube changes are reported; a patch that
worsens the demo cube's truth-bearing grains is not proposed. Otherwise: the dump and the refuted hypotheses only, no patch.

## What refutes what
P1 fails if the truth's ring shifts agree (span 1) in most failing cases, or the continuous score loses in > 4 of 26. A fix fails if it
recovers < 24, regresses on-grid, or breaks <012>/<112>. A null is "not explained", never a mechanism. Thresholds (0.5 deg, 22/26,
1.5x) belong to this bank and these settings only.

## Amendment 1 (2026-09-30 night, after the gate failed, before any P1-P4 run)
The gate (record `s20-acom-offgrid-results-2026-09-30.md`, committed 090975b) found 43 (no wavelength) / 37 (200 kV) failures of 200 at
1.4 deg, not 26, with 0/200 on-grid. Decided by the orchestrator overnight (overrule on sight); nothing but the gate has been run.
- Reproduced population: those 43 / 37 failures (0.5 deg failure line, 1.4 deg rotation), each plan reported separately; on-grid stays 0/200.
- P1: "22 of 26" becomes >= 85 % of the reproduced failures with truth per-ring shift span >= 2 and winner span 1; "24 of 26" (continuous
  score puts truth at or above winner) becomes >= 92 %; the refutation "continuous score still loses in > 4 of 26" becomes > 8 % of them.
- P2 "at most 4 of 26" and P4 ">= 20 of 26" scale likewise (<= 15 %; >= 77 %); P3 unchanged.
- Bar: >= 90 % of the reproduced failures recovered (at 1.4 deg and reported across the 0.35 deg x k sweep), 0 on-grid regressions, no axis
  exact at every rotation today made wrong in the 136 sweep, pinned acom-* harnesses and unit classes within tolerance.
- Everything else unchanged. Further amendments are appended here before the result they concern is read.
