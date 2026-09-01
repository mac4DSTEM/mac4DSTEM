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
0.0005 gives 13.0; 0.0002 gives 24.1. **The ring discriminator:** 100% of the
180,815 non-central peaks lie within ±2 px of two ring centers, r₁ = 18.83 px
and r₂ = 32.65 px, with **r₂/r₁ = 1.7342 vs √3 = 1.7321** (0.12%). These are
Bragg spots. The ellipse stage's a ≈ 32.68 was ring 2 all along.

> **Amended by Gate B, 2026-08-31 — every number above verified from the raw
> 197,199 vectors, but two of the arguments were not the ones the data
> supports.**
> **(a) Why 0.001.** The original text chose it because reliability was
> "falling (noise entering)" at 0.0002 — the metric this same record says
> points the wrong way, and the 0.0005/0.0002 output directories were not
> retained, so "noise entering" was asserted, never measured. (0.0005 also
> matched 484/484 positions against 0.001's 473/484.) The justification the
> data *does* support: 0.001 yields a median of exactly **12 peaks/pattern =
> 1 beam + 6 + 6**, the hexagonal expectation.
> **(b) The ±2 px test is ~4× looser than the data justifies, and its null was
> never stated.** Against area-uniform noise over the detectable detector the
> hit probability is 9.23%, so 100% is a genuine **10.8× enrichment** and R2 is
> dead — but against area-uniform noise over the *observed annulus* it is
> 38.7%, and the ring centres were fit to these same peaks. The bands' 1–99
> half-widths are **0.62 px and 0.92 px**, so ±2 px is 6.7σ and 4.9σ: as
> stated, the test is close to tautological. Two stronger corroborations the
> record had and did not use: **95.7% of patterns carry exactly 6 ring-2
> spots** (a hexagonal lattice, not a coincidence of radii), and the ellipse
> stage's independent mean-pattern fit **a = 32.678** agrees with the ring-2
> mean 32.6528 to **0.08%** by a completely different code path — and is
> byte-identical across all five runs, so it does not depend on the threshold.
> **(c) 0.12% from √3 is ~19σ, not agreement.** SE(ratio) ≈ 0.0068% over
> 86,187 and 94,628 peaks. It is a systematic — subpixel/kernel bias, or the
> 0.35% ellipticity the same report measures (a = 32.678 / b = 32.563) — and
> must not be quoted as a calibration-quality result.
> **(d) Only two of the crystal's five hk0 rings are detected.** A prior
> refuter measured 1 : √3 : 2 : √7 : 3 in the mean pattern
> (`docs/open-items.md`); nothing above 33.734 px survives detection at 0.001.
> So the matcher sees data spanning 0.344–0.656 Å⁻¹ (corrected) against
> templates built to `kMax` 1.2.

**E3 — P3 CONFIRMED end to end.** `KnownCrystalQCalibration.estimate`
returned **invAngstromPerPixel = 0.008789** — the (0002) defect live on the
real cube through the real code path. Data-derived corrected scale:
0.36621/18.83 = **0.019448 Å⁻¹/px**. The campaign's own status string was
already honest: `pass_operational_not_quantitatively_validated`.

> **Amended by Gate B, 2026-08-31 — three corrections, one of them a second
> defect this session did not notice.**
> **(a) The measured factor is 2.2129×, not 2.2564×.** 0.019448/0.008789 =
> 2.21285. The 2.2564 figure (= 0.366200/0.162298) is the *geometry-only*
> ratio of the two shells and is not what the runs produced; only
> `docs/open-items.md` had this right.
> **(b) The two scales are built on DIFFERENT radius statistics**, which is
> where the missing 2% lives. The estimator takes the per-pattern MINIMUM
> radius, then the median over positions → 18.46677 px, and
> 0.162298/18.46677 = 0.008788661, the reported value to nine digits. The
> corrected scale uses the ring-1 POPULATION mean, 18.8283 px. Ring 1 carries
> 5.26 spots/pattern at σ = 0.2992, so E[min of 5.26 draws] ≈ 18.45: the
> 0.36 px gap is **order-statistic bias, 1.92% low**, making the estimator's
> scale ~1.9% too large *independently of the shell blunder*. Fixing only the
> shell and keeping the estimator's own statistic gives 0.019830, not 0.019448.
> That min-statistic bias is a real second calibration bias and is now its own
> open item.
> **(c) "Brackets the py4DSTEM tutorial's hand-set 0.0192" is wrong twice** —
> a single value cannot bracket another (0.019448 is +1.29% from it), and the
> tutorial sets it by eye (`References/py4DSTEM_tutorials-main/notebooks/`
> `orient_strain_01_WS2.ipynb`, cell 27: overlay structure factors and try
> different pixel sizes). It corroborates to a few percent — enough to kill
> 0.0088, nowhere near enough to arbitrate 0.019448 against 0.019830.

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

The mis-scale bites: the score halves and the zone axis is wrong. **The zone
axis is the load-bearing half.** A polar-correlation matcher is scale-sensitive
by construction — changing the assumed pixel scale moves the data onto
different template rings, so a score drop at the wrong scale is close to what
the algorithm is *defined* to do. The result carrying physical content is that
a basal specimen must index to 0.0° off beam and the defective scale gives 4.6°.

**And the metric the app surfaces points the wrong way — BETWEEN THE TWO
SCALES.** Reliability (best minus second-best) is HIGHER at the defective
scale, because at the correct scale the near-[0001] templates are nearly
degenerate (the fiber-texture effect the feasibility review predicted). So a
reliability-ranked comparison between candidate Q scales would PREFER the wrong
one, and nothing surfacing this defect may lean on reliability to choose.

> **Corrected by Gate B, 2026-08-31.** This paragraph originally generalised
> that one pair into "reliability is anti-correlated with correctness on a basal
> specimen". **The session's own data refutes it.** Within the corrected run,
> split on the physically-required basal template, the CORRECT assignment has
> the HIGHER median reliability (t0 0.0940 vs non-t0 0.0827);
> Spearman(score, reliability) is +0.011 corrected and −0.096 defective; and
> across the E2 sweep mean reliability FALLS (0.1023 → 0.0605) as noise enters —
> tracking quality positively. One ordered pair between two runs is not a
> correlation. The between-scales statement above is what the evidence supports,
> and it is what must travel into `docs/open-items.md` and the Track B row.

**The map is real — on the grain structure and the zone axis, not on the
coherence figure.** The 15,717 [0001] positions resolve into **19 grains
≥ 50 px covering 99.0%** of them (25 connected components, ~28×28 px), whose
in-plane angles cluster over [0°, 60°). `polycrystal_2D_WS2` has reached ACOM —
operational, honestly labelled not-quantitatively-validated, and at the
corrected scale it produces a physically consistent basal polycrystal
orientation map.

> **Corrected by Gate B, 2026-08-31.** This paragraph originally rested on
> "**99.1%** of neighbour pairs agree within 3° (random ≈ 10%)". The figure is
> right — 99.09% of 30,143 both-t0 pairs, against a 10% uniform null and an
> 11.97% marginal-preserving one — but it **does not discriminate correct
> indexing from incorrect**. The refuter ran the identical test on the run this
> session calls WRONG and got **95.75%**, equally overwhelming against the same
> null. In-plane hexagon rotation is measurable with no crystal model and no
> correct Q scale at all, so coherence establishes spatial SMOOTHNESS only.
> Two cautions on "distinct modes", both real: the in-plane angle is quantised
> at 0.9375° (= 60/64) by the correlation grid and only 40 of 64 grid values are
> occupied, and 90% of neighbour pairs differ by *exactly* zero — that is the
> grid, not smoothness.

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
   0.01/2.2564 (the geometry-only (0004)/(0002) shell ratio — NOT the factor
   the cube produced, which was 2.2129; see §1 E3(a)) and assert the median
   score drops by ≥25% (**measured on the real cube: 46%** — corrected
   2026-08-31 by Gate B; the "87%" written here was the same measurement
   stated backwards, the *rise* from defective to corrected, and an agent
   implementing against it would have written an assert that fails on a
   correct matcher). That pins "the matcher is
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

## §3 Continuation — the owed work, 2026-08-31 (second sitting)

Picked up from §2 with nothing started. Items 1–4 below are §2's list; the
corrections above (§1's amended blocks) came out of the Gate B this sitting ran.

**1. The gated fixture arm — LANDED** in `tools/acom-matching-test`, after the
Mg arm. Two deliberate deviations from §2's spec, both because the tree measured
something sharper than the spec predicted:

- **Recovery tightened from ≥6/8 to 8/8.** The fixture is deterministic and the
  narrowest margin over all competing templates is 0.0595 against a CPU-vs-Metal
  spread of 6e-7. A ≥6 threshold would let two positions regress silently.
- **A recovery-COLLAPSE assertion added** (≤1/8 at the defect scale, measured
  0/8). This is the assertion with teeth and the one that mirrors the real cube:
  the mis-scale returns *different orientations*, not merely lower scores. The
  bound allows one because ~8/48 coincidental hits are expected by chance.

Measured: **8/8 at the true scale, 0/8 at 1/2.2564, median score −68.2%**
(1.0000 → 0.3182).

**Break-every-new-test: 7 author mutations, 7 caught**, each a distinct red.
Six were caught on the first pass. The seventh — median swapped for max —
**survived**, because at the defect scale every order statistic collapses, so
the drop assertion cannot discriminate between them. Closed with a self-check on
the `median` helper rather than documented as a limitation, and the mutation
re-run to confirm it goes red.

**2. Gate B — two refuters, the house split. ~22 findings; both targets were
materially wrong in places.**

*Refuter 1 (the E1–E4 analysis).* Reproduced every E4 number to four decimals
and `0.008788661` to nine digits from the raw vectors, so the table is real. But
**four claims did not survive**, all corrected in §1 above: the reliability
anti-correlation (refuted by the session's own data), the 99.1% coherence figure
(does not discriminate — the run this session calls WRONG scores 95.75% on the
identical test), the 2.2564× factor (the runs produced 2.2129×), and the choice
of 0.001 (justified by the very metric the same record calls untrustworthy).
It also found a **second, unrecorded calibration bias** — the estimator measures
the ring by a per-pattern *minimum*, biased 1.92% low — now its own open item.
Diagnosis D itself survived and is better supported than the record argued:
every non-central peak has relative intensity below 0.002, which is
unanswerable, and py4DSTEM's own tutorial for this dataset sets
`minRelativeIntensity: 0`.

*Refuter 2 (the fixture arm + the campaign override).* Confirmed the arm does
what it says and that its scope comment is accurate, then found that **seven
mutations survive it**, two of them wrong science with no net anywhere in the
gate. Acted on this sitting: the true-scale score assertion (F5) and an in-plane
angle assertion; three comments corrected (the 0.101 margin, the 2.2564
provenance, the median guard's reach); the `medianScore` wrapper removed so the
self-check cannot be bypassed one level up; and the campaign override's two
honesty defects fixed — it now refuses an unparseable or non-positive value
instead of falling back silently to the un-overridden estimate, and records
`.manual` provenance plus an `issues` line rather than claiming `.measuredInApp`
for a number that came from the environment.

> **The review's top recommendation was wrong, and this was measured rather than
> taken on authority.** Refuter 2's F1 — a projection transpose or handedness
> flip is invisible to every gated ACOM harness — is real and severe, and it
> proposed an in-plane-angle assertion as the one-line fix. That assertion was
> written and **both mutations still pass**: the fixture builds its experimental
> pattern with the same `project` that builds the templates, so the cancellation
> preserves the relative angle exactly as it preserves the score. The assertion
> was kept (it independently catches an angle-reporting defect at
> `OrientationMatcher.swift:314`, verified) but its comment now says plainly
> what it does not close, and F1 is filed as an open item with the fix that
> would actually work. **A refuter's proposed remedy gets broken before it is
> trusted, the same as a test.**

Not fixed, filed instead: the orientation-matrix/template decoupling (the
obvious assertion is wrong — `euler` is symmetry-reduced, matching at position 1
to 4.5e-8 and disagreeing at the other seven by O(1); a correct comparison needs
the symmetry group and inventing that unreviewed is the failure mode Gate B
exists to prevent), the additive-radial-offset blind spot, unpinned reliability,
unpinned `intensityPower`, and the override's two remaining artifact-disagreement
findings.

**3. Track A.** `run-tests.sh scientific` — **exit 0** (read from the retained
log, not a pipe), **41 started / 41 completed, zero FAIL and zero SKIP lines**,
counted by grep. No new harness: the WS₂ work is an *arm* inside
`acom-matching-test`, which is why the count stays 41.

**No unit gate is owed, and here is the run that covers this tree.** Nothing
under `mac4DSTEM/` changed in W4b in either sitting — verified with
`git diff -- mac4DSTEM/` after every mutation sweep, and again at closeout. The
last commit touching `mac4DSTEM/` is **`81893fb` (W4a, 2026-08-31)**, and the
working tree is byte-identical to it under that path, so the covering run is
W4a's closeout unit gate: **391 passed / 2 skipped / 0 failed, exit 0,
2026-08-31**. The three files this sitting touched are
`tools/acom-matching-test/main.swift`,
`tools/training-dataset-campaign/main.swift` and
`.claude/skills/adversarial-review/SKILL.md`.

**4. F1.45 queued** in `docs/visual-acceptance-checklist.md`, written to the
stricter reading: it names the Min-relative-intensity step without which there is
nothing on screen, warns that IPF·Z is legitimately near-uniform on a basal
specimen and that the grains live in the in-plane angle map, and carries the
reliability trap **in its narrowed form** — reliability ranked a wrong Q scale
above the right one, which is what the evidence supports, not the general
anti-correlation Gate B refuted.

**Not verified.** F1.45 on screen (owner). The projection-frame and
matrix-decoupling defects are *demonstrated present and unpinned* — no shipping
result is known wrong, but nothing gated would notice if it were. The min-statistic
calibration bias is measured on one cube and undiagnosed. The campaign override
fix was compiled, not run against real data (the campaign needs the multi-GB
cube). `References/parity_records/latest` was not touched in either sitting.

**Kickoff tax.** 3,481 → 3,576 lines across `CLAUDE.md` + `docs/v2-release.md` +
`docs/open-items.md`, **+95 net, this sitting's doing**: five new open items from
Gate B and a §9 entry long enough to carry what the two refuters overturned. The
first draft was +128; the five entries were rewritten against the file's ≤20-line
rule, moving the narrative here and leaving pointers, which recovered 30 lines.
The residual is findings, not story — but it is still growth, and the next
session that needs room should look here first.

**Skills.** `/pickup` routed correctly: §9 carried W4b as `[~]` and its handoff
was precise enough to start from cold. Two notes for whoever maintains them.
(1) `adversarial-review` step 1b — "when the change IS the fixture, ask what
transformation leaves every check green while producing wrong science" — was the
highest-value line in any skill this session; both of refuter 2's severe findings
came from it, and it should stay worded as an instruction to *run* the candidates,
not to reason about them. (2) A gap worth closing: nothing in the skill says a
**refuter's proposed remedy** must itself be broken before it is trusted. This
session implemented refuter 2's one-line fix, found it did not work, and only
caught that because the mutations were re-run against it. The same discipline the
repo applies to its own tests ("break every new test") applies to a reviewer's
recommendation — a suggested fix is a hypothesis, and here it was wrong.
