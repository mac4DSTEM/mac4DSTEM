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

## Recommendation

**Balanced, on-axis: 17.** Strict is the most defensible per object but is
visibly conservative; inclusive is 38 % contamination. Whichever the owner
picks — or corrects — the number he confirms is the ground truth, and step 4's
real-data half can then be scored against it.
