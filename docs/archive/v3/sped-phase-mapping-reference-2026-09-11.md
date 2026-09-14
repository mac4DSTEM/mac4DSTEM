# What `elisathr/SPED-phase-mapping` teaches us — read 2026-09-11

The code behind **Thronsen et al., "Scanning precession electron diffraction
data analysis approaches for phase mapping of precipitates in aluminium
alloys" (2023)** — the paper the owner has five copies of. Read at the owner's
direction, from a shallow clone into the session scratchpad. Nothing was copied
into this repo, and nothing can be: see the licence note at the bottom.

Data: <https://doi.org/10.5281/zenodo.6645396>. Stack: pyxem 0.14.2, hyperspy,
diffsims, orix, tensorflow, scikit-image.

## 1. It independently corroborates our refutation, on real data

They implement **four** phase-mapping approaches and score all four against a
common ground truth by the fraction of mislabelled pixels:

| method | mislabelled |
|---|---|
| artificial neural network | **0.96 %** |
| non-negative matrix factorisation | 1.50 % |
| vector analysis | 1.54 % |
| **template matching** | **1.75 %** — worst of the four |

**CORRECTED 2026-09-11 after reading the paper itself: this is NOT a ranking,
and reporting it as one was wrong.** The paper states all four reach
98.5 % ± 0.5 % and that "the small differences in accuracies are not
significant", because the ground truth was made manually. The numbers are real;
the ordering is not meaningful. An earlier version of this file called template
matching "the worst of the four" — it is not established to be worse than any
other.

Our own measurement (`phase-discrimination-2026-09-11.md`) refuted per-position
template matching *as we would have built it*, on a synthetic mixture. That
stands on its own evidence, and does not need their table to support it.

## 2. They hit our exact problem and say so in the notebook

`TemplateMatching/templatematching_3_phasemapping.ipynb`, markdown cell 6:

> "we will only include T1 and θ' and filter out badly matched regions as Al in
> the end. Done because **Al has overlapping reflections with the precipitates**."

That is our finding in their words. Their accommodations, three of them:

1. **Mask the matrix reflections AND the direct beam out of every pattern**
   before matching (`templatematching_1_masking_and_DoG.ipynb`): average a
   matrix-only region, difference-of-Gaussians background removal
   (min_sigma 3.6, max_sigma 6.4), threshold to a reflection mask, a *separate
   larger* mask for the central beam, Gaussian-smooth both (sigma 5), invert and
   combine.
2. **Leave the matrix out of the template library entirely** — only precipitate
   phases are simulated.
3. **Assign the matrix by exclusion** — whatever matches badly is called Al.

This is the remedy our own measurement pointed to ("score what is NOT matrix"),
arrived at by a different group for the same reason. It also means a phase map
is only as good as the matrix mask, which is built once, by hand, from a region
the user picks.

They also sample orientations far more finely than we do — 0.5° between
templates, with the tilt range limited around specific zone axes — against our
600 zone axes over a fundamental zone.

## 3. Their ground truth is the answer to our hand-count problem

> "Three different ground truths were prepared by **three different people** and
> then compared to increase the reliability of the ground truth."

And the method each person used is **the virtual dark-field route we shelved**:
a VDF per precipitate-phase reflection, then segmentation (watershed,
`threshold_triangle`/`threshold_li`, `regionprops`, `peak_local_max`).

The distinction is the useful part: **VDF + segmentation is good enough to
ESTABLISH ground truth under human oversight; it is not what they use to produce
the phase map.** That is exactly the split this repo arrived at — marked
candidates for the owner to adjudicate, with the mapping done another way — and
it says our one-person count should be at least two.

## 4. Their accuracy metric is simple and adoptable

`error = count_nonzero(phase_map - ground_truth) / (512 × 512)` — the fraction
of mislabelled scan positions, applied identically to all four methods. That is
a better acceptance number than anything currently pre-registered here, and it
needs a labelled ground truth rather than a count.

## 5. The "slop" the owner objected to is inherent to published practice

`NMF/README.md`: SVD to choose a component count, then NMF, and then **"the user
must manually determine which phase each factor corresponds to, and how to best
threshold their loadings"**, repeating with already-identified pixels masked.

So the best-scoring classical method in the paper still has a human naming the
factors. The owner's instinct that hand-interpretation is unsatisfying is right,
and **nobody in this paper has an automatic answer either**. Their lowest error
came from the ANN — supervised, trained on simulated patterns — which is the
one approach that moves the human effort from interpretation to training-set
construction.

## 6. Licence — we may learn from it, we may not copy it

**There is no LICENSE file in the repository.** Default copyright therefore
applies: no grant to copy, modify or redistribute. This repo is public and
GPL-3.0, so **no code, notebook fragment or CIF from it may be copied into
mac4DSTEM.** Method and published results are citable; the implementation is
not ours to take.

Their `cif-files/` holds **Al.cif, T1.cif, thetaprime.cif** — an Al-Cu-Li /
Al-Cu system. There is no β″ there, so it would not have solved our CIF blocker
even if the licence allowed it.

## 7. What is worth acting on

- **A real validation target exists.** The Zenodo dataset ships with a published,
  three-person ground-truth phase map and four scored methods. That is a
  parity opportunity of a kind we do not otherwise have for classification —
  stronger than any synthetic fixture.
- **Matrix masking before matching** is the concrete next measurement for the
  template route, and it is now evidence-backed rather than a guess.
- **NMF beats template matching here** (1.50 % vs 1.75 %), which bears on the
  PCA-vs-NMF decision the owner deferred.
- **Two independent ground truths minimum** for our own hand count.
