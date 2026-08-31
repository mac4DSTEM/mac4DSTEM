# W4b — S16: ACOM on polycrystal_2D_WS2 (2026-08-31)

Run under the owner's recorded decisions (§9, 2026-08-31): safe defaults —
peak starvation is measured and recorded, never "fixed" by retuning shipped
defaults; the Track B row is written against the stricter reading of "reaches
ACOM honestly". Gate B at the end.

## §0 Pre-registration — WRITTEN BEFORE ANY EXPERIMENT RAN

Per the recovered-testimony lesson (2026-08-29): the predicted and observed
outcomes live in THIS file, amended as the experiments run, never in a second
write that may not happen.

**Diagnosis D.** WS₂'s ACOM starvation is caused by the relative-intensity
threshold — default `minRelativeIntensity = 0.005` with `relativeToPeak = 0`,
i.e. 0.5% of the brightest candidate, which on this beam-dominated cube is the
direct beam — discarding genuine but dim Bragg spots. It is NOT caused by
absence of diffraction signal: the mean pattern carries hk0 rings at ratios
1 : √3 : 2 (refuter measurement, 2026-08-31), and the pinned
`real-data-acceptance` counts show 45–47 candidates surviving correlation and
the absolute stage before the relative stage cuts to 1.

**Refuting observations R — what would kill D.**
- R1: lowering `MAC4DSTEM_DISK_MIN_RELATIVE` (the campaign's env mirror of the
  app's advanced "Min relative intensity" control — user-reachable, so this is
  app use, not a default retune) fails to raise the median peaks/pattern to
  ≥ 4 at any value down to 1e-4.
- R2: the recovered peaks do NOT cluster at a common radius from the mean
  origin with second-ring ratio ≈ √3 — i.e. they are noise, not Bragg spots.

**Predicted outcomes P, numbered.**
- P1 (baseline, shipped defaults, `ws2_2h` assigned in the manifest): median
  peaks/pattern ≈ 1 (the beam); `KnownCrystalQCalibration.estimate` fails for
  want of a non-central shell, so the campaign records the dataset WITHOUT an
  ACOM product. The honest baseline: WS₂ reaches the ACOM stage and is refused
  for want of peaks.
- P2 (sweep 0.002 / 0.001 / 0.0005): median peaks/pattern rises monotonically;
  at some user-reachable value the median is ≥ 4, and the recovered peak radii
  cluster with r₂/r₁ = 1.73 ± 0.05 (the Bragg discriminator).
- P3 (the (0002) defect, end to end): once peaks exist, `estimate` succeeds
  and returns invAngstromPerPixel ≈ 0.16230/r₁ — if r₁ ≈ 19 px, ≈ 0.0085
  Å⁻¹/px, the predicted 2.256× under-scale — and its shell-ratio diagnostic
  reports observed ≈ 1.73 against predicted 2.00 (= (0004)/(0002)), the
  mismatch REPORTED and passed through, exactly as the open item says.
- P4 (does the mis-scale bite?): full matching at the defective scale vs a
  control run at the corrected scale (0.36621/r₁, assigning r₁ to (10-10))
  shows markedly lower mean reliability and/or an implausible zone-axis
  distribution at the defective scale; at the corrected scale the indexed
  positions cluster near [0001] (the cube is measured basal). If both scales
  match equally well, the mis-scale claim's PRACTICAL bite is refuted (the
  matcher would be scale-insensitive) and the open item must be amended.

**Experiment plan E.** E1: compile the campaign harness once, run WS₂-only at
defaults (baseline). E2: the `MIN_RELATIVE` sweep. E3: read the Q-cal numbers
from the report. E4: a small non-gating driver (`tools/ws2-acom-diagnostics`)
that runs `OrientationMatching.matchAll` at both scales on the same detected
vectors and reports reliability / zone-axis statistics. The campaign binary is
invoked DIRECTLY with a scratch output directory, skipping `run.sh`'s parity
stage so `References/parity_records/latest` is not overwritten mid-experiment
(S12's precedent, recorded there as a deviation, repeated here deliberately).

## §1 Outcomes — amended as each experiment lands

**E1 (baseline, shipped defaults) — P1 CONFIRMED.** `bragg_detection`:
16384 peaks over 16384 positions, exactly 1.0/pattern (params logged by the
stage: spacing 4, edge 5, σCC 2, probe 1.8594 px). The ACOM stage refused —
*"Not quantitatively testable: known-crystal Q calibration could not be
established"* — recorded as `expected_prerequisite_block`. Also logged:
origin (63.996, 63.996) RMS 0.0011 px; the ellipse stage fit a ring at
a ≈ 32.68 px — consistent with the SECOND (11-20) ring if r₁ ≈ 18.9 px,
where the tutorial scale puts (10-10).

**E2 (the sweep) — P2 CONFIRMED, and R1/R2 are dead.**
`MIN_RELATIVE` 0.002 still starves (1.00/pattern); **0.001 recovers a median
12.0 peaks/pattern** and ACOM runs (473/484 preview positions matched);
0.0005 gives 13.0; 0.0002 gives 24.1 with reliability falling (noise entering
— 0.001 is the sweet spot). **The ring discriminator:** 100% of the 180,815
non-central peaks lie within ±2 px of two ring centers, r₁ = 18.83 px and
r₂ = 32.65 px, with **r₂/r₁ = 1.7342 vs √3 = 1.7321** (0.12%). These are
Bragg spots. The ellipse stage's a ≈ 32.68 was ring 2 all along.

**E3 — P3 CONFIRMED end to end.** `KnownCrystalQCalibration.estimate`
returned **invAngstromPerPixel = 0.008789** — the (0002) defect live on the
real cube through the real code path (implied r₁ = 18.47 px). Data-derived
corrected scale: 0.36621/18.83 = **0.019448 Å⁻¹/px** (brackets the
py4DSTEM tutorial's hand-set 0.0192). The campaign's own status string was
already honest: `pass_operational_not_quantitatively_validated`.

**E4 — P4 CONFIRMED, with a sharper edge than predicted.** Full-scan matching
on the same detected vectors at both scales (via the campaign's new
`MAC4DSTEM_ACOM_SCALE_OVERRIDE`, documented on the
`MAC4DSTEM_DISK_KERNEL_MEASURED` precedent):

| | defective 0.008789 | corrected 0.019448 |
|---|---|---|
| matched | 16076/16384 | 16076/16384 |
| median score | 0.2140 | **0.3994** |
| median reliability | **0.1153** | 0.0940 |
| top template share | 73% (t71) | 98% (t0) |
| c-axis vs beam | **4.6°** (wrong zone) | **0.0°** ([0001], as the pure-hk0 pattern requires) |

The mis-scale bites: the score halves and the zone axis is wrong. **And the
metric the app surfaces points the wrong way** — reliability (best minus
second-best) is HIGHER at the defective scale, because at the correct scale
the near-[0001] templates are nearly degenerate (the fiber-texture effect the
feasibility review predicted). Reliability is anti-correlated with
correctness on a basal specimen.

**The map is real.** In-plane angles of the 15,717 [0001] positions form
distinct modes over [0°, 60°), and **99.1% of neighbour pairs agree within
3°** (random ≈ 10%): spatially coherent grains. `polycrystal_2D_WS2` has
reached ACOM — operational, honestly labelled not-quantitatively-validated,
and with the corrected scale it produces a physically consistent basal
polycrystal orientation map.

## §2 HANDOFF — session stopped at the owner's usage limit, 2026-08-31

Everything above is DONE and committed; nothing below is started. W4b is
`[~]` in §9. The next agent continues here — `/pickup` finds W4b as the open
partial session.

**Owed, in order:**
1. **The gated fixture arm** in `tools/acom-matching-test` (after the Mg arm):
   generate the ws2_2h plan (48 zone axes, `.hexagonal`), build the synthetic
   fixture with the existing `vectors(plan:crystal:width:height:)` helper
   (4×2), match at the true scale 0.01 — assert provenance + ≥6/8 positions
   recover their generating template — then match the SAME fixture at
   0.01/2.2564 (the (0002)-defect factor) and assert the median score drops
   by ≥25% (measured on the real cube: 87%). That pins "the matcher is
   scale-sensitive", which is what makes the open item's defect matter.
   **Break it before trusting it** (set the factor to 1.0 → the assert must
   fail). Scope comment: the fixture is generated FROM the same crystal, so
   it pins the MATCHING path, never the model — `ws2-crystal-test` pins the
   model.
2. **Gate B, two refuters** (the house split): one refuting the E1–E4
   analysis and the "reached ACOM honestly" claim (this file + the two
   parity_input.json files under the session scratchpad `w4b-work/`, if still
   present — every number is also in §1); one attacking the fixture arm and
   the campaign's `MAC4DSTEM_ACOM_SCALE_OVERRIDE` edit
   (`tools/training-dataset-campaign/main.swift`, the
   KERNEL_MEASURED-precedent block).
3. `run-tests.sh scientific` after the arm lands (nothing under `mac4DSTEM/`
   changed in W4b, so no unit gate is owed — say so at closeout).
4. **Queue F1.45** (fit overlay) in the checklist, written to the stricter
   reading: the overlay row must warn that reliability is anti-correlated
   with correctness on basal data, and that the demo of "grains" is the
   in-plane angle map, not the IPF colour (which is uniform for basal).
5. §9 tick, board republish, closeout.

**Standing state to know:** the campaign manifest now assigns `ws2_2h` to
`polycrystal_2D_WS2.h5` — at DEFAULT thresholds the campaign still records
`expected_prerequisite_block` for its ACOM stage (1 peak/pattern), which is
honest and correct; the recovered-map runs used `MAC4DSTEM_DISK_MIN_RELATIVE=
0.001` (a user-reachable control, not a default change — the eval-only rule
was not touched). `References/parity_records/latest` was NOT overwritten
(harness invoked directly; S12's precedent).
