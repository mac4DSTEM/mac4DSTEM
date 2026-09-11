# Does the ACOM score discriminate PHASE? — measured 2026-09-11

Reproduce: `tools/phase-discrimination-probe/run.sh`.

`docs/v3-precipitate-classification.md` proposed labelling each scan position by
matching its diffraction pattern against per-phase templates. This is the
measurement that was supposed to be able to kill that route before the CIF
importer work was paid for. **It killed it, twice over, and the second finding
is the one that matters.**

## The pre-registered criterion, written before the first run

A β″ needle is ~4 nm across in a 50–100 nm foil, so the precipitate's share of
the beam path is roughly 0.05–0.5. **If the argmax needs a precipitate fraction
above 0.3 to pick the precipitate phase, per-position template matching is not
viable** and classification must run on class-average patterns instead.

## Finding 1 — the mixing flip is at 0.60

Al fcc as matrix, Si diamond as stand-in precipitate, one [001] zone axis,
peaks synthesised through `OrientationPlan.project`. Sweeping the precipitate's
share `f` of the diffracted intensity:

| f | matrix score | precipitate score | winner |
|---|---|---|---|
| 0.00 | 0.97949 | 0.79480 | matrix |
| 0.30 | 0.78569 | 0.66684 | matrix |
| 0.55 | 0.71127 | 0.71027 | matrix |
| **0.60** | 0.69536 | **0.72579** | **precipitate** |
| 1.00 | 0.82076 | 0.97900 | precipitate |

**FAIL.** The matrix wins until the precipitate supplies 60 % of the pattern —
twice the pre-registered ceiling and far above anything physical.

## Finding 2 — the score picks the WRONG PHASE, and this is the real defect

On a pattern containing **only aluminium** reflections:

| candidate phase | score |
|---|---|
| aluminium — the true phase | 0.97949 |
| **gold fcc, a = 4.08** | **0.98758** |
| silicon diamond | 0.79480 |
| copper fcc, a = 3.61 | 0.50032 |

**Gold outscores aluminium on an aluminium pattern.** Contrast between the true
phase and the best wrong phase is **−0.008**: negative. An argmax over phases
would confidently return the wrong one.

## Why, quantitatively — it is a sampling limit, not a bug

The polar template is sampled on `nRadial` bins over `kMax`, so two phases whose
reflections differ by less than one bin are the same pattern to the score. At
the defaults (`nRadial` 32, `kMax` 1.6), one bin is **0.05 Å⁻¹**:

| pair | Δg (111) | fraction of one bin | score on Al |
|---|---|---|---|
| Al–Au | 0.0030 Å⁻¹ | **6 %** — same bin | 0.988, wins |
| Al–Cu | 0.0514 Å⁻¹ | 103 % — resolved | 0.500 |
| Al–Si | 0.1088 Å⁻¹ | 218 % — resolved | 0.795 |

Al and Au are 0.7 % apart in lattice parameter and land in the same radial bin.
Nothing in the scoring can separate them.

## What this does and does not condemn

**It does not condemn shipped ACOM.** ACOM matches *orientation* for a phase the
user chose; it is single-phase by design and `phaseID` is write-only. No shipped
number is wrong.

**It does condemn two things in the pre-registration:**
1. Per-position template matching for precipitates — finding 1.
2. Phase identification by a bare argmax over per-phase plans — finding 2. Any
   multi-phase feature built on `bestScore` would inherit it.

## What the route must become, and none of this is yet measured

The matrix reflections dominate the score in both findings, so the signal must
come from what is *not* matrix:

- Score on reflections **unique to the candidate phase** — β″'s superlattice
  reflections sit at r ≈ 9–10 px where Al's first ring is at ~18 px, i.e. many
  bins apart and resolvable — rather than on the whole pattern.
- Or score the **difference** from a matrix reference, so the common part
  cancels before the comparison.
- Or require a **contrast margin** over the runner-up instead of a bare argmax,
  which finding 2 shows can be negative.

Also open, and a prerequisite for any of them: the radial sampling has to
resolve the phases in question. That is a settable parameter (`nRadial`,
`kMax`), and nobody has measured what it costs to raise it.

## The honest consequence for the plan

The template-matched route is not dead, but **it cannot be built as
pre-registered**, and the unsupervised-clustering step the owner called "slop"
is back in play — because the class-average difference pattern, not the
per-position pattern, is where the discriminating signal survives.
