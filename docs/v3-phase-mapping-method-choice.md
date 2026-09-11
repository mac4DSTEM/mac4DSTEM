# Which of Thronsen et al.'s four methods fits mac4DSTEM — evaluated 2026-09-11

Read from the paper (Ultramicroscopy 255 (2024) 113861, CC BY 4.0) at the
owner's direction, against what this app already owns.

## First, a correction to how this repo reported their result

An earlier note here said template matching was "the worst of their four
methods". **The paper says the differences are not significant**: all four reach
98.5 % ± 0.5 %, and "the small differences in accuracies are not significant"
because the ground truth was made manually. The per-method numbers (ANN 0.96 %,
NMF 1.50 %, vector 1.54 %, template 1.75 % mislabelled) are real but must not be
read as a ranking. Corrected in
`archive/v3/sped-phase-mapping-reference-2026-09-11.md`.

The choice therefore turns on **fit to our framework**, not on their accuracy
table.

## Recommendation: vector matching

**Because its single hardest dependency is this app's largest existing
investment.** The paper, §5.1.2:

> "Perhaps most challenging, decent results rely on an accurate peak-finding
> method … ideally one that can detect weak Bragg peaks while simultaneously
> avoiding mislabelling background noise. **The peak finding step is also the
> most computationally intensive step** of the vector matching process."

That is a description of `Core/Analysis/DiskDetection.swift` and C7's learned
detector. We have:

| what vector matching needs | what mac4DSTEM already has |
|---|---|
| accurate Bragg peak positions | `DiskDetection` + `TiledDiskDetection`, sub-pixel by parabola **and** DFT-upsampled cross-correlation |
| weak peaks without false positives | the Core ML learned detector on the Neural Engine (C7), with a Compare Detectors mode |
| accurate calibration and beam centring | origin fitting, R–Q rotation, ellipse and Q-scale calibration, all gated |
| the peaks for every scan position | `BraggVectors` — computed **once** and already shared by strain and ACOM |

## The deviation worth making

**For them peak finding is the bottleneck. For us it is already paid for.**
`BraggVectors` is computed once per scan and cached; strain and ACOM both
consume it. Vector matching would be a **post-processing pass over data the app
already has**, not a new pipeline — the cheapest of the four to add and the only
one whose expensive step we have already optimised and validated.

Two further simplifications fall out:

- **Their matrix masking becomes trivial.** Template matching needs
  image-space masking (difference-of-Gaussians, a hand-drawn matrix region,
  threshold, smooth, invert). In vector space it is: drop experimental vectors
  lying close to the Al reference vectors. No new image pipeline, and this
  repo's own measurement already showed masking is what rescues discrimination
  (`archive/v3/phase-discrimination-2026-09-11.md`).
- **Their refusal maps onto ours.** Vector matching scores by mean distance
  between experimental and reference vectors and declares "not indexed" above
  0.07. This app's culture is refusals that name what failed; a score with an
  explicit unindexed verdict fits it exactly, where an argmax does not.

## Why not the others, for us specifically

**Template matching** — the paper's own numbers are the argument against it
here: basic pre-processing gave **86.24 %**, and adding background subtraction
took it to **98.24 %**. A twelve-point swing decided by pre-processing choices,
plus a `max{s}` parameter tuned per phase, which they say "reduces the ease of
use … and also the objectiveness". We would also inherit the wrong-phase
problem this session measured, since it scores whole patterns.

**ANN** — the infrastructure genuinely exists (Core ML, the Neural Engine,
`tools/disk-detector`'s simulate/train/export/hash/check chain), it is the
fastest at run time and it handles weak reflections best. But it needs ~10 000
simulated patterns per phase with careful augmentation, and a trained model is
material-specific. **Right answer later, wrong answer first** — and it needs
the simulation machinery vector matching would build anyway.

**NMF** — the only method that needs *no* diffraction simulations and the only
one that handles phases overlapping along the beam. That makes it the natural
**exploratory** tool, and we are closest to it already: `DiffractionEmbedding`
does PCA + k-means with a py4DSTEM parity harness. Its drawback is the one the
owner already named as slop — the user must label components by hand — and the
paper confirms errors there "propagate to produce phase maps that might look
visually correct, but are physically wrong".

## The shape this suggests

1. **Exploration — what we have.** PCA/k-means class maps, no prior knowledge,
   no simulations. Already built and gated.
2. **Quantitative phase mapping — vector matching.** Built on `BraggVectors`,
   using reference vectors from an imported CIF.
3. **Throughput — ANN, later**, reusing the simulation machinery step 2 builds.

## What is still blocking step 2, unchanged by this evaluation

- **`CIFImport.swift:798-810` refuses monoclinic** — cubic, hexagonal, throw.
  β″ cannot be loaded. This blocks reference-vector generation and is the first
  thing to fix.
- **A β″ CIF**, or agreement to author one from the published Wyckoff table.
- **The orientation relationship** between β″ and Al — their method leans on it
  being known a priori, and for β″ in Al-Mg-Si it is published.
- **Their implementation is zone-axis only** and struggles where phases overlap
  and where strain shifts peak positions. We would inherit all three.
