# Precipitate candidates, marked and counted — 2026-09-11

**What this is.** Three counts of variant-1 β″ needles on the Al-Si-Mg cube,
with every candidate marked and numbered so the owner can adjudicate by
checking marks instead of counting from scratch. He asked for this after
judging the first counting sheet unclear — he was right, for a reason that
turned out to be the reflections, not the contrast (see
[`precipitate-baseline-2026-09-11.md`](precipitate-baseline-2026-09-11.md)).

**What this is NOT, and the distinction is load-bearing.** It is not the hand
count the feature's pre-registration demands, and it cannot be substituted for
one. An algorithmic count cannot score an algorithm. Worse, the obvious way to
produce one — threshold plus connected components — **is the baseline arm** of
the step-4 comparison, so using it as ground truth would let the baseline score
itself. The count becomes ground truth only when the owner confirms or corrects
the marks. Until then these are candidates.

Reproduce: `tools/precipitate-handcount/run.py <cube.h5> <outdir>`.

## Image

Dark field over Friedel pair 1 — detector pixels (35,23) and (29,41), r ≈ 9.4,
summed — from `060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5`. 330×330
scan at 1.539 nm/px, 508 nm field. Background flattened (σ=12 subtract, σ=0.8
smooth) and expressed in robust sigmas. Peak z = 31.1.

## The three criteria and what they give

| | σ | min area | min length | min aspect | total | **on-axis** | off-axis | purity |
|---|---|---|---|---|---|---|---|---|
| strict | 6 | 10 px | 8 px | 3.0 | 14 | **12** | 2 | 86 % |
| balanced | 5 | 6 px | 5 px | 2.5 | 23 | **17** | 6 | 74 % |
| inclusive | 4 | 4 px | 4 px | 2.0 | 39 | **24** | 15 | 62 % |

On-axis means within 20° of the variant direction, **−36.6°**, taken as the
length-weighted mean of the strict set.

| | on-axis length (nm) | areal density (µm⁻²) |
|---|---|---|
| strict | 77.4 ± 50.6 | 46.5 |
| balanced | 62.4 ± 50.4 | 65.9 |
| inclusive | 50.1 ± 51.8 | 93.0 |

## What the angular test shows, and it is the useful part

A single crystallographic variant runs in **one** direction. Relaxing the
criteria does not mainly find fainter needles — it mainly finds objects at the
wrong angle:

```
strict     -45:#########  -30:###  -15:##
balanced   -45:############  -30:####  -15:#####  0:#  +45:#
inclusive  -45:############  -30:############  -15:##########  0:#  +45:##  +60:##
```

Going from strict to inclusive adds 25 objects, of which **13 are off-axis**.
The image carries faint horizontal and vertical texture aligned with the scan
axes — scan-line artefact — and the looser thresholds pick fragments of it up
as short "needles". That is why the loosest count is the least trustworthy, not
the most complete.

## Two things the owner should check, because they are where this can be wrong

1. **Merged parallel needles.** The longest object reads 177 nm, long for β″.
   Neighbouring parallel needles that touch become one component, which
   undercounts and overestimates length. The end-caps on each mark make this
   visible: one mark spanning two distinct bright streaks is a merge.
2. **Missed faint needles.** The strict set is 86 % pure but makes no claim to
   be complete. If green marks are missing from streaks that are obviously
   needles, the threshold is too high for the count that matters.

## CORRECTION, same day — the three counts above are all too low

The owner's objection: the image is formed by putting a detector **on a
precipitate reflection**, so brightness *is* the evidence of a precipitate;
why filter on shape at all? He is right, and the numbers above are wrong for a
number density.

Filters 3 and 4 (minimum length, minimum aspect ratio) and the 20° angle cut
are assumptions imposed by this analysis, not required by the contrast
mechanism. They optimise **purity** when a density needs **completeness**. Cost,
measured at 5 σ: 39 bright objects of area ≥ 4 px, of which the aspect filter
removed 16 and the angle cut a further 6, leaving the 17 recommended above —
**56 % discarded**. At 4 σ it is 74 %.

The discarded population is not noise. Pure Gaussian noise above 5 σ predicts
**0.03 pixels** in a 108 900-pixel scan; 39 objects is entirely real signal.

Worse, the aspect filter deleted exactly the population the crystallography
predicts must exist. Classified rather than filtered, the 39 are:

| class | n | median length | reading |
|---|---|---|---|
| elongated, aspect ≥ 2.5 | 23 | **37.5 nm** | β″ needles lying in the foil plane |
| short, 1.5–2.5 | 9 | 9.2 nm | short or inclined needles |
| compact, < 1.5 | 7 | **4.9 nm** | needles seen **end-on** |
| raster signature | 4 | 3–4.6 nm | exactly 0°, ≤ 2 px wide — artefact |

β″ in Al-Mg-Si is roughly 4 nm across and 20–50 nm long. A 37.5 nm median for
the in-plane needles and 4.9 nm for the compact objects — the cross-section —
is the signature of the same particle seen two ways. A needle viewed end-on has
aspect ≈ 1, and `aspect ≥ 2.5` deletes it by construction.

**The only defensible exclusion is the raster artefact**, identified by its own
signature (exactly axis-aligned, ≤ 2 px wide, 3–5 nm long) rather than by a
general rule about angle.

## Corrected count

**35 precipitates** at z > 5 σ, area ≥ 4 px: 39 bright objects less 4 raster
artefacts. Areal density **135.6 µm⁻²**, against the 65.9 the filtered count
gave — low by a factor of 2.1.

Still for the owner to adjudicate, and still not a substitute for his eye: the
threshold (5 σ) is a choice, merged parallel needles remain a real undercount
(the longest object reads 177 nm), and whether the compact objects are end-on
needles or something else is a crystallographic judgement, not one this
analysis can make.
