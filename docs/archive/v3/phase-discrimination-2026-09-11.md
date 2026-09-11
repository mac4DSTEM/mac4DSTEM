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

## Addendum, same day — matrix masking transfers, and it works

Thronsen et al. mask the matrix reflections and the direct beam out of every
pattern before matching (`sped-phase-mapping-reference-2026-09-11.md`). Their
**method**, implemented independently here from the published description — the
repository carries no licence, so nothing was copied and the parameter below is
ours. Peak-list analogue: drop any peak within `radius` of a matrix-reference
reflection.

**Flip moves from f = 0.60 to f = 0.05** — a twelvefold improvement, stable at
mask radii 2, 4 and 6 px. Their accommodation transfers to our scoring geometry.

Scores are **f-independent above the flip**, which is correct rather than
suspicious: with the matrix masked away the surviving pattern is pure
precipitate, and the matcher L2-normalises, so scaling every intensity leaves
the normalised pattern identical.

**Three limits this measurement does not escape, and they bound the claim:**

1. **The mask here is perfect** — built from the exact reference peak positions.
   A real mask is built from a real matrix region through background removal and
   thresholding, and is not. This is an upper bound on how well masking works.
2. **The score floor survives masking.** The matrix plan still scores **0.826**
   on a pattern holding none of its reflections, against the precipitate's
   0.933 — a contrast of ~0.11, not ~1. **Masking fixes the mixing problem and
   not the wrong-phase problem**; finding 2 above stands.
3. **Masking cannot separate phases whose reflections overlap.** Masking Al
   would mask Au with it, because they share radial bins. It works here because
   Si sits 218 % of a radial bin from Al — which is also true of a superlattice
   ring against Al's first ring, so the geometry is favourable for β″
   specifically.

## The honest consequence for the plan

The template-matched route is not dead, but **it cannot be built as
pre-registered**. With matrix masking it becomes viable on the mixing axis —
under a perfect mask, and with the wrong-phase problem untouched. The remaining
work is therefore not "does masking help" (measured: yes, 12x) but **how much a
realistic, imperfect mask gives back**, and whether a contrast of ~0.11 between
the right and wrong phase is enough to label on.

And Thronsen et al.'s own numbers say the destination may not be template
matching at all: scored against a common ground truth, template matching was the
**worst** of their four methods (1.75 % mislabelled) and NMF was 1.50 %. The
unsupervised step the owner called "slop" is back in play, and in their paper
the user naming the NMF factors is still how the best classical method works.
