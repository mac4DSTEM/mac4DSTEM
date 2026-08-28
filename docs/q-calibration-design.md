# Q-calibration design — S12

**Written 2026-08-28.** S12 is a **Plan** session (`docs/v2-release.md` §8): it
runs experiments and produces a design; it changes no app code. Its output is
this file, and the release owner reviews it before S13 implements anything.

> **Read with S13's corrections, 2026-08-28.** S12 said plainly that §3's two
> checks were *"designed, not prototyped — their discriminating power is
> asserted and S13's pre-registered experiment may refute it."* It did, twice:
> §3.1's claim to catch the geometric-middle fallback is **false**, and §3.2 as
> specified **fires on healthy data**. Both are corrected in place below, marked
> **REFUTED**, with the measurement and the repair. §6(b) is also now answered.
> The implementation and its evidence are
> [`docs/archive/v2-session-records/s13.md`](archive/v2-session-records/s13.md).

What the brief asked for, and where each answer is:

| S12 owed | Answer |
|---|---|
| Read the campaign's `constant_rms`/`parabola_rms` — settle **#29**'s direction | §1 — **answered, and #29's binary framing turns out to be incomplete** |
| Design the estimator-internal plausibility gate | §3 — **and S13's experiment refuted part of it; the corrections are inline, marked REFUTED** |
| Design the sane-origin / measure-Q split | §2 |
| Weigh the `measureOrigin` coarse step **on a measurement**, recommend in-or-out for S13 | §4 — **OUT**, with the re-entry condition |
| What S13 should build, in order | §5 |
| Owner decisions | §6 |

Everything below is reproducible today. The RMS table comes from the existing
`tools/training-dataset-campaign`; the distribution and cost numbers come from
`tools/origin-fit-diagnostics`, added by this session, which does not gate and
says why in its own header.

---

## 1. #29 answered — what `OriginMaps.rmsResidual` actually measures

**#29's question.** `originFitIsQuantitative` (`Core/Data/Calibration.swift:473`)
refuses when RMS(measured − fitted) exceeds the probe radius. #29 records that a
large residual is equally consistent with two opposite causes and that nobody
had told them apart:

- **(a) the fit is too rigid** — the per-position origins carry real descan a
  plane cannot follow, so `fittedX/Y` (what every analysis consumes) is
  genuinely displaced, and refusing is right;
- **(b) the measurements are noisy** about a smooth truth the fit already
  recovers, so `fittedX/Y` is fine and refusing withholds a good calibration.

### 1.1 The three fit functions on the same measured maps

Run: the campaign harness on all four training datasets, 2026-08-28. Its
`origin_calibration` stage fits a plane and then re-fits the *same* measured
maps with a constant (0 free parameters) and a parabola (5), so the three are
directly comparable.

| dataset | scan | probe *r* | RMS constant | RMS **plane** | RMS parabola | gate (RMS ≤ *r*) |
|---|---|---|---|---|---|---|
| `downsample_Si_SiGe_exp` | 50×200 | 5.026 | 13.133 | **11.655** | 11.302 | **BLOCK** |
| `sim_Au_data_all_binned` | 100×84 | 6.096 | 0.639 | **0.162** | 0.152 | pass |
| `polycrystal_2D_WS2` | 128×128 | 1.859 | 0.0139 | **0.00103** | 0.00103 | pass |
| `Particle_1…bin8` | 90×45 | 10.624 | 18.720 | **18.295** | 18.138 | **BLOCK** |

Two things fall straight out.

**Going from 0 parameters to 5 barely moves the residual on the datasets that
are blocked.** Si_SiGe: 13.13 → 11.66 → 11.30, a 14% span. Particle_1:
18.72 → 18.29 → 18.14, a 3% span. Whatever the gate is measuring, it is not the
plane being too rigid — a parabola is not meaningfully better, and a *constant*
is barely worse.

**A defect, narrower than it first looked: three of the refusal's four
remedies cannot work.** `Calibration.originFitRefusal` (`:506-511`) appends
*"Try another Origin fit (Constant / Plane / Parabola) and re-run Calibrate
Origin, or enter the scale manually."* On both datasets where that text is
shown, **all three fit functions miss the gate** — by 2.2× on Si_SiGe (11.30
vs 5.03 at best) and 1.7× on Particle_1 (18.14 vs 10.62 at best). The sentence
leads with, and spends most of its words on, the one remedy that provably
cannot succeed.

**The fourth remedy does work, and an earlier draft of this section wrongly
said the refusal was a dead end.** "Enter the scale manually" bypasses the
estimator entirely (`AppState.setManualQPixelSize`), and the manual field is
rendered in *both* branches of the readiness row — which is why
`AppState.swift:4951` records that "refusing here is never a dead end", a Gate B
decision from 2026-08-25 that the earlier draft's truncated quotation erased.
The defect is that the text buries the remedy that works behind three that
cannot, not that the user is stuck. Fix: say what actually failed — broad
measurement failure versus excluded outliers, which the app can now tell apart —
and lead with manual entry rather than with three fit functions that span 14%
of a residual sitting 1.7–2.2× above the gate.

*Pre-registration outcome.* Written before the numbers were read: predicted the
"mixed" pattern (large constant→plane drop, small plane→parabola drop) on the
smooth datasets, and "at least one dataset where plane→parabola is also large."
The first is **confirmed** on sim_Au (3.9× constant→plane, then 6%). The second
is **refuted** — on all four the plane→parabola drop is ≤ 6%.

### 1.2 The distribution — where #29's binary breaks down

RMS is one number over a vector the code already has. Reading the vector
(`tools/origin-fit-diagnostics/run.sh residuals`) shows the two blocked
datasets fail by **two different mechanisms**, which is why one threshold on
one statistic cannot serve both.

| | Si_SiGe | Particle_1 | sim_Au |
|---|---|---|---|
| plane RMS / gate | 11.655 / 5.026 | 18.295 / 10.624 | 0.162 / 6.096 |
| residual p50 | 10.706 | **3.346** | 0.105 |
| residual p95 | 19.069 | 47.934 | 0.339 |
| **median / RMS** | **0.919** | **0.183** | 0.649 |
| positions > *r* | **84.0%** | 26.6% | 0% |
| positions > 2*r* | 54.4% | 24.5% | 0% |
| trimmed refit keeps | **100.0%** | **72.7%** | 84.5% |
| trimmed RMS **over kept** | 11.655 | 2.188 | 0.092 |
| trimmed RMS **over ALL** — what the shipped gate reads | **11.655 → BLOCK** | **18.475 → BLOCK** | 0.168 → PASS |

("Trimmed refit" = iterate three times: fit a plane, drop positions beyond
median + 3·1.4826·MAD of the residual, refit. Median/RMS ≈ 0.83 is what a
Rayleigh-distributed scatter gives; well below that means a heavy tail.)

**Si_SiGe is broad measurement failure.** median/RMS 0.919, no tail to trim —
trimming converges keeping *every* position and moves the RMS by nothing
(11.6551 → 11.6551) and the fitted origin by 0.000 px anywhere on the map.
84% of positions land more than a probe radius from the fit. The per-position
origin measurement is unreliable across the whole scan. **Refusing is correct.**

**Particle_1 is outlier contamination.** median/RMS 0.183 — a textbook heavy
tail. The median residual is 3.35 px against a 10.62 px gate, while p95 is
47.93 px: about three quarters of the scan measures a consistent origin and a
quarter fails catastrophically. Trimming converges at 72.7% kept, and over the
positions it keeps the residual is **2.19 px**.

**But a robust fit does NOT, on its own, clear the shipped gate — and an
earlier draft of this section said it did.** That claim was refuted in review
and the correction matters more than the original point. `originFitIsQuantitative`
thresholds `OriginMaps.rmsResidual`, which is computed over **all** scan
positions. RMS over the *kept* subset is not that number, and comparing it to
the gate is circular: trimming removes the largest residuals by construction,
so RMS(kept) is guaranteed to fall. The quantity the shipped gate would
actually see for the trimmed fit is **18.47 px** — measured, and *marginally
worse* than the shipped plane's 18.29 px. The direction is forced, not
accidental: full-scan ordinary least squares minimizes exactly that quantity,
so refitting on a self-selected subset can only raise it.

**So the conclusion is stronger than "fix the fit", not weaker: the statistic
has to change too.** A robust fit alone leaves the gate refusing. What §2
proposes — gating on a *robust* residual plus the outlier fraction — is
therefore load-bearing rather than tidy-up, and the two changes have to land
together or neither does anything.

**And the contaminated fit is displaced, which is why the fit still needs
fixing.** The shipped (untrimmed) plane differs from the trimmed one by p50
**2.03 px**, p95 4.64 px, **max 6.00 px** across the scan. That matters because
#29's own item 1 puts the Q estimator's breakdown at ≈2 px of origin error,
non-monotone and peaking around 3 px. So on Particle_1 the app today computes
an origin that is materially wrong across most of the scan *and* refuses it on
a statistic that describes the contamination rather than the displacement.
Both halves are defects; neither fixes the other.

### 1.3 The answer

> **#29 is answered: both (a) and (b) occur, on different real datasets, and the
> current gate cannot tell them apart because RMS discards exactly the
> information that separates them. The discriminator is free — it is the
> residual vector the gate already computes.**
>
> The corollary is the actionable half, and it is **two** changes rather than
> one: **the plane fit is not robust**, so contaminated scans get a displaced
> origin (up to 6 px here); and **the gate's statistic reports the
> contamination rather than the displacement**, so making the fit robust does
> not by itself change what the gate decides — measured, the trimmed fit's
> full-scan residual is 18.47 px against 18.29 px for the shipped one. Fix the
> fit *and* gate on a robust residual. Either alone accomplishes nothing.

---

## 2. The split — "is this origin sane?" vs "may I measure a reciprocal scale?"

Today one predicate answers both. `originFitIsQuantitative`
(`Core/Data/Calibration.swift:473-476`) drives the Prepare readiness badge
*and*, through `originFitRefusal`, gates `calibrateQFromCrystal`. #29 warns
explicitly against resolving this by tightening that one threshold to 2 px,
and §1 says why that would be wrong anyway: on Particle_1 the number being
thresholded is contaminated, so no threshold on it is meaningful.

**The design is two predicates over one policy owner**, on the seam S7 already
built (`App/SessionGates.swift`) — S11 found this exact question answered four
different ways at four call sites, which is the S7 class, so the split must not
create a fifth.

**`originFitIsSane`** — the looser question, drives the readiness badge and
anything that only needs a centred frame (Bragg map display, DPC, virtual
detectors).
- computed on the **robust** residual (§1.2's trimmed refit), not the raw one;
- carries `originOutlierFraction` beside it, because "2.19 px RMS over 73% of
  positions" is a different claim from "2.19 px RMS over all of them" and the
  product must be able to say which;
- Si_SiGe still fails it (11.66 px trimmed — trimming removes nothing there);
  Particle_1 passes it (2.19 px over the 72.7% kept). **Note what this buys:**
  §1.2 measured that Particle_1's trimmed fit does *not* clear the CURRENT
  gate — 18.47 px full-scan — so this predicate is the thing that changes the
  outcome, not the robust fit on its own.

**`originSupportsReciprocalMetrology`** — the stricter question, consulted by
`calibrateQFromCrystal` only. Deliberately **not** a tighter threshold on the
same number. It requires all three of:
1. `originFitIsSane`;
2. the origin is a **measured** origin, not the geometric-middle fallback — this
   is S11's confirmed worst finding (`.fileMean`/`.sessionMean` leave
   `calibration.origin` nil and `calibratedBraggVectors` substitutes
   `(qx/2, qy/2)`, `AppState.swift:4720-4721`), and it is S13's to fix;
3. the estimator's own plausibility checks (§3) passed.

The reason (3) carries the weight rather than a pixel threshold is that the
estimator can check itself against the crystal, which no origin-residual
threshold can do — and that check catches (2) for free even if the fallback
survives.

---

## 3. The estimator-internal plausibility gate

Location: inside `KnownCrystalQCalibration.estimate`
(`Core/Analysis/QCalibration.swift:19-51`), where `firstRadii`, its median,
its MAD, `sampleCount` and the reference shell are all already in hand. Two
checks, because there are two distinct failures.

### 3.1 Shell consistency — catches origin error and the geometric-middle fallback

The innermost *allowed* shell has one |g|. Changing orientation changes which
reflections are excited, not their length, so its observed radius should be
nearly constant across scan positions. Under #29's mechanism the "innermost
non-central peak" is instead the direct beam at radius |δ|, the per-position
origin error — which varies with scan position by construction.

**Refuse when `medianAbsoluteDeviationPixels / observedRadiusPixels` exceeds a
threshold.** Dataset-independent, uses only what the estimator already
computes.

> **REFUTED IN PART BY S13, 2026-08-28.** This paragraph originally continued:
> *"and it fires on the geometric-middle fallback too, because a wrong centre
> makes the innermost radius track the true beam's offset."* **It does not.**
> S13's pre-registered experiment displaced `sim_Au`'s fitted origin by a
> uniform 5 px and MAD/observed came back at **0.0121 — below its own 0.0156
> baseline.** A constant offset shifts every position's innermost radius
> together, which is precisely what a median-absolute-deviation statistic is
> built to ignore. The claim is left visible rather than deleted because the
> design's §2 leans on it.
>
> What replaced it: a second, physically derived check — **the innermost shell
> must sit further from the origin than one probe radius**, since a reflection
> closer than that overlaps the direct beam. Measured on `sim_Au`, every sound
> case is ≥ 3.35 × the probe radius and every collapsed one ≤ 0.81, with
> nothing between. Above the probe radius the *origin-fit* gate takes over
> (residual ≈ δ for a constant displacement, measured), so the two layers meet
> at the probe radius with no gap.
>
> **And the fallback is not covered by either**, which is the part that
> mattered: measured, the geometric-middle substitution is 1.14 px on `sim_Au`
> (below the estimator's 2 px floor) and 7.07 px on `downsample_Si_SiGe_exp`
> (above the radius check's band, with no origin gate above it because a nil
> origin has no residual to judge). That is why S13 closed it structurally in
> `Calibration.referenceOrigin` instead of watching for it.
> Full numbers: [`docs/archive/v2-session-records/s13.md`](archive/v2-session-records/s13.md) §1.

**The threshold must be measured, not invented.** sim_Au is the only training
dataset where Q calibration currently runs, so it gives one point, not a
threshold. **S13's entry ticket:** pre-register and run the controlled
experiment — MAD/observed on sim_Au as shipped and under deliberately displaced
origins (δ = 1, 2, 3, 5 px, spanning #29's non-monotone error curve) — and set
the threshold from the separation, the same shape as S17's discriminator.
Inventing a number here would reproduce exactly the failure mode S17 diagnosed:
a threshold that was one machine's measurement rounded up.

### 3.2 Shell-ratio self-check — catches wrong-shell assignment

S11's confirmed structural finding: the estimator assumes the innermost
*detected* peak is the innermost *allowed* shell. If the first shell is too weak
to detect in a given zone the second is read as the first and the scale is wrong
by the shell ratio — √4/√3 = 1.155 for FCC, a 15% error, silently stamped
`.measuredInApp`. One shell cannot detect this. Two can.

**Collect the innermost two radii per position and compare
median(r₂)/median(r₁) against g₂/g₁ from `Crystal.reflections`** — which already
applies structure-factor extinction and sorts ascending
(`Core/Crystal/Crystal.swift:131,139`), so the reference side is sound. A
mismatch means the assignment is wrong.

> **REFUTED AS SPECIFIED, AND REPAIRED, BY S13, 2026-08-28.** As written this
> fires on good data. `Crystal.reflections` returns every symmetry equivalent
> **separately, all at the same |g|**, and several equivalents of the first
> shell are excited at one scan position — so r₁ and r₂ are usually two peaks of
> the *same* shell and the check compares a shell against itself. Measured on
> healthy `sim_Au`: **1.02048** against an expected **1.15470**.
>
> The repair is one added condition, and its size is **derived rather than
> chosen**: r₂ must be the innermost radius at least `(g₂/g₁ − 1) / 2` larger
> than r₁ — half the gap the crystal itself predicts. At that separation
> `sim_Au` agrees to **−0.57%** with 99.7% of positions still contributing, and
> `downsample_Si_SiGe_exp` misses by **+18.2%**, firing on the dataset whose
> assignment really is wrong.
>
> **Stated asymmetry, which follows from the filter and not from the data:**
> because r₂ is *selected* as separated, a ratio that is too *small* cannot be
> detected. That is the harmless direction — reading shell 2 as shell 1 makes
> the ratio too large — but it is a real limit and it is in the code comment.
> The two innermost DISTINCT lengths must also be grouped by |g| at the call
> site; `reflections[1]` is another equivalent of the first shell, not the
> second one.

This is the cheap in-app half of py4DSTEM's `get_dq_from_indexed_peaks`
(`process/calibration/qpixelsize.py:26-65`), which least-squares-fits
`q ≈ c·√(h²+k²+l²)` across indexed shells. It keeps the estimator's robustness
(median over positions, which is why the app's version survives dense patterns)
rather than adopting the indexed fit wholesale — that would be a much larger
change and would need indexing the app does not do at this stage.

**State the limit honestly:** when only one shell is detectable at all the
check cannot run, and that must be reported as *not self-checked*, not silently
passed. That state is real for thin or weakly-scattering samples, and it is
exactly the state in which the single-shell assumption is least safe.

---

## 4. The `measureOrigin` coarse step — recommendation: **OUT of S13**

`docs/open-items.md` requires this be weighed "on a measurement, not on the
header." The header of `Shaders/OriginMeasure.metal` asserts that py4DSTEM's
translation-equivariant coarse step,
`argmax(gaussian_filter(dp, sigma=r))`, is "prohibitively expensive" and
substitutes an argmax over binned block sums.

**Accuracy was already measured** (S2, 2026-08-19): striding the block scan by 1
instead of by `bin` — two tokens, `OriginMeasure.metal:47,49` — takes the
translation-equivariance error from **0.6094 px to 9.54e-07 px**, and leaves the
**absolute** error unchanged at 0.337 px.

**Cost, measured 2026-08-28** (`tools/origin-fit-diagnostics/run.sh
coarse-cost`; both kernels derived from the shipped shader at run time, so
neither can drift from it; median of 15 dispatches).

**Measured at the grid the app actually dispatches, which is a *tile*, not a
scan.** An earlier draft of this table timed invented scan shapes and was
wrong in every ratio — caught in review. `measureOrigin` is dispatched once per
tile by `VirtualDetector.tiledMeasuredOrigins`, and `dispatch2D` derives the
threadgroup grid from the tile's height, so timing at the wrong grid measures
occupancy rather than work. The tool now computes the tile height with
`FourDArray.scanTileRows`' own formula instead of hardcoding it.

| dataset | bin | tile dispatched | shipped | stride-1 | ratio |
|---|---|---|---|---|---|
| WS2 128×128, *r* = 1.86 | 2 | 42 × 128 | 1.3 µs/pattern | 3.3 | **2.5×** |
| Si_SiGe 128×128, *r* = 5.03 | 5 | 27 × 200 | 2.2 | 32.6 | **14.8×** |
| sim_Au 125×125, *r* = 6.10 | 6 | 68 × 84 | 3.3 | 71.4 | **21.6×** |
| Particle_1 128×128, *r* = 10.62 | 11 | 90 × 45 | 2.6 | 224.3 | **86.3×** |

> **This is a per-machine number.** `scanTileRows` bounds the tile by
> `min(GPU recommended working set / 8, physical RAM / 24)`, so the tile heights
> above are what an **8 GB** machine produces. A 16 GB machine tiles twice as
> tall, changes occupancy, and will not reproduce these ratios exactly. The
> ordering and the order of magnitude are what transfer.

In context: the whole `origin_calibration` stage costs **60–174 µs/position** on
these datasets, of which the shipped kernel is **1.3–5.5%** (per dataset, each
paired with its own stage time — an earlier draft quoted "2–5%" by pairing the
smallest kernel time with the smallest stage time from a *different* dataset).
The naive change adds **+3% to the stage at *r* = 1.9, +17% at *r* = 5, +113%
at *r* = 6.1, and +261% — 3.6× the whole stage — at *r* = 10.6.**

So the header is half right, and half right in the direction that matters:
negligible for small probes, and at a large probe radius the "prohibitively
expensive" verdict is essentially correct — the coarse step alone would cost
more than three times the entire origin-calibration stage.

**Recommendation: out.** Four reasons, in order of weight:

1. It buys 0.61 px, and 0.61 px is not currently a product claim — it is a
   *stated bound*, already pinned by `tools/two-spec-analysis-test`
   (`P4_KNOWN_BOUND` 0.65 px).
2. It does not touch the 0.337 px **absolute** error, which S2 measured as
   unchanged. It is not the accuracy fix it looks like.
3. §1 puts the origin on two of four real datasets 11.7 px and 18.3 px wrong
   for an unrelated reason. Buying 0.6 px while 12 px is on the table is the
   wrong order of work.
4. If it is ever wanted, **stride-1 is the wrong implementation.** A separable
   box filter restores O(qy·qx) and should cost ~2–3× the shipped coarse step
   rather than 86× — and that estimate must itself be measured before it is
   believed.

**Re-entry condition:** when sub-pixel agreement between a cropped view's origin
and the full-extent one becomes a claim the product makes (it is not one today),
or when §5's work lands and 0.6 px becomes the dominant error term.

**One line to fold in anyway.** S11 handed S12 the `OriginMeasure.metal`
half-pixel convention residual: line 44 seeds `coarseX = qx * 0.5` (an index
convention) while line 60 sets the winner as `0.5*(bx + xEnd - 1)` (a
pixel-centre convention). The seed is reachable only when no block sum beats
`-FLT_MAX` — an all-NaN pattern, where the CoM produces garbage regardless — so
it is cosmetic. S13 will be reading this file; fix the seed to the same
convention with a one-line comment, and do not dignify it as a defect.

---

## 5. What S13 should build, in order

S13 is **Gate B** (`docs/v2-release.md` §8): a separate agent briefed to refute,
plus a `tools/` fixture whose negative controls name the line they break.

1. **Robust origin fit.** Iteratively-trimmed plane refit (§1.2). This is the
   largest single win and it changes both what the app *computes* and what it
   *refuses* — on Particle_1 it improves the fitted origin by up to 6 px and
   turns a wrong refusal into an admission. Fixture: the trimmed-vs-untrimmed
   fit on a synthetic map with a planted outlier population, plus the
   `tools/origin-fit-diagnostics` numbers as the real-data anchor.
2. **The origin fallback.** S11's confirmed worst finding — `.fileMean` /
   `.sessionMean` leaving `calibration.origin` nil so `calibratedBraggVectors`
   substitutes `(qx/2, qy/2)` for the file's recorded beam centre, in Q
   calibration, strain, ACOM and the Bragg map at once. **One policy owner for
   the fallback**, replacing the four divergent derivations S11 catalogued.
   Note S11's blind spot: every `QCalibrationOriginGateTests` case builds origin
   *maps*, so the suite has never run the nil branch — a test that exercises it
   is part of the fix, and must be broken before it is trusted.
3. **The split** (§2), on the S7 `SessionGates` seam, not as a fifth copy.
4. **The estimator-internal checks** (§3), each with its threshold measured by
   its own pre-registered experiment, never invented.
5. **The refusal text** (§1.1) — it leads with three fit functions that
   provably cannot clear the gate on either dataset where it is shown, and
   buries manual entry, the one remedy that works, at the end. It should say
   what actually failed (broad measurement failure vs excluded outliers) and
   lead with the remedy that succeeds.
6. **The strain-weighting provenance key** — already S13's from S11, unchanged
   by this session.
7. **Not** the coarse step (§4).

---

## 6. Owner decisions

The brief marks S12 as the design the owner sees. Two decisions are genuinely
the owner's, not mine:

**(a) Should a robust fit *admit* Particle_1-class data?**
**DECIDED 2026-08-28 by the release owner: ADMIT, and show the fraction.**

> *"I think it is good to admit that only x% of positions are used, that shows
> that this is something we thought of. I prefer to have the origin measured
> more accurately over having 100% of the beam positions found considered."*

The reasoning is the binding part, not just the verdict: **accuracy of the
fitted origin outranks coverage of the input measurements**, and the excluded
fraction is *disclosure*, not an apology — it is evidence the app knows what it
did. S13 implements accordingly:

- the robust (trimmed) fit becomes the origin the analyses consume;
- the excluded fraction is **carried on the product**, not buried in a log — it
  travels with the result the way the strain frame does, so it survives export
  and reopen;
- it must reach the reader who sees the *number*, since that reader is the one
  who would otherwise over-trust it.

**(b) A hard ceiling on the excluded fraction — MEASURED BY S13, 2026-08-28:
no ceiling is defensible on the available evidence.** At a *forced* 2% kept —
98% excluded — the fitted origin's own uncertainty is still **0.10 px**, two
orders of magnitude below the pre-registered 2 px criterion, on five datasets;
the app's own trim never excludes more than 34% on any of them. **S13's
recommendation is to ship without a ceiling**, refuse on the robust residual and
report the fraction, which is the branch this section permits — and it is a
recommendation the owner can overrule. The stated limit: bootstrap SD measures
the fit's *precision*, not its *bias*, so a ceiling justified by
representativeness is neither supported nor refuted.
[`docs/archive/v2-session-records/s13.md`](archive/v2-session-records/s13.md)
§2 has the sweep. The question as posed:

**Not answered with
(a), and S13 must not invent one. 27% passes on `Particle_1`; whether 60% should
still pass when the remaining 40% look tight is unresolved. **S13 measures where
a ceiling would go rather than picking a round number** (the S17 lesson: a
threshold that was one machine's measurement rounded up). If the measurement
does not support a defensible ceiling, ship without one and say so.

**(b) Is there a hard ceiling on the excluded fraction** above which the app
refuses regardless of how good the trimmed residual looks? 27% passes on
Particle_1; 60% probably should not, whatever its residual says. If you want a
ceiling, S13 measures where to put it rather than picking a round number.

---

## 7. What S12 did **not** verify

- **Nothing was implemented or reviewed.** This is a design; §3's thresholds do
  not exist, and §1's robust fit is a measurement made by a diagnostic tool, not
  by app code.
- **§3's two checks were not prototyped against data.** Their *shape* follows
  from S11's structural findings and §1's measurements; their discriminating
  power is asserted, not demonstrated. That demonstration is S13's pre-registered
  experiment, and it may refute the design.
- **The trimmed refit is a plane refit**, matching the app's default. Whether
  trimming should also be offered for the constant and parabola fits is not
  addressed.
- **Two of four datasets carry no phase model**, so Q calibration has been
  exercised end to end on exactly one (sim_Au). Every claim about the Q
  estimator's *behaviour* here is read from the code path and from S11's
  triage, not from a red test.
- **The cost table is synthetic-pattern timing** of the kernel alone. The coarse
  loop's cost is data-independent by construction (fixed iteration count, no
  early exits), but the stage percentages combine that timing with the
  campaign's wall-clock stage time on real data — two runs, not one
  instrumented run. **The tile heights are this machine's**: `scanTileRows`
  bounds them by physical RAM, so an 8 GB and a 16 GB machine do not tile the
  same and will not reproduce these ratios exactly.
- **Three claims in the first draft of this document were refuted in review and
  are corrected above, not quietly dropped:** that the refusal's remedies
  "cannot work" (the fourth, manual entry, does — and a Gate B decision from
  2026-08-25 says so); that a robust fit "clears the gate" (it does not — the
  gate's statistic has to change too); and the entire §4 cost table (timed at
  invented scan shapes rather than the tile grid the app dispatches). The
  design's conclusions survived all three, but two of them survived with
  different reasoning than they were first given.
- **Track A was not run**, and is not owed: nothing under `mac4DSTEM/` was
  touched.
