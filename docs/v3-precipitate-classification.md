# Pre-registration — precipitate density by diffraction classification

Registered 2026-09-11, owner approved in chat. Written before the code, per
`v3-plan.md` §6. This **supersedes the route `v3-plan.md`:64 specifies**
("per-object, real-space segmentation"), and supersedes the §1.5 design
session, which was skipped when the AI port reversed the 2026-09-08 "leave"
decision.

## 1. Why the existing route is wrong, measured not argued

The shipped precipitate chain forms a virtual dark-field image, then segments
that image. It collapses each diffraction pattern — **4096 numbers on this
cube** — into **one** number, the aperture sum, before any decision is made.
Everything after is an attempt to recover structure already discarded.

Three failures this session, all downstream of that one choice:

- **A shape filter deleted a whole variant.** A needle pointing along the beam
  projects as a dot, aspect ≈ 1. `aspect >= 2.5` removed 7 compact objects of
  median 4.9 nm — the β″ cross-section. Counting 17 where there were 35, low by
  2.1x (`archive/v3/precipitate-handcount-2026-09-11.md`).
- **The ridge filter does not do its job.** Its own pre-registered baseline is a
  TIE: both arms report all three round particles, which the ridge filter exists
  to reject (`archive/v3/precipitate-baseline-2026-09-11.md`).
- **No upstream to check against.** Zero `DEVIATION` notes; the segmentation
  abandoned skimage's convention. **A parity harness is impossible for this
  route** — established 2026-09-11 and unchanged since.

A virtual dark-field image is also, as an image, *worse* than HAADF: a small
aperture collects a small fraction of the scattered electrons. The 4D advantage
was never a better picture. It is that the whole pattern is retained and can be
classified.

## 2. What is built

Classify every scan position by its **full diffraction pattern**, then measure
objects on the class map.

1. **Featurise** each position's pattern (log-scale, per-pattern normalise, box
   bin — the existing `DiffractionEmbedding` front end, already on `main`).
2. **Decompose** — PCA today; NMF pre-registered as the comparison (§4).
3. **Cluster** into classes.
4. **Identify precipitate classes** from each class's **average diffraction
   pattern**: a precipitate class shows the superlattice reflections, the matrix
   class does not. This is the step that replaces a brightness threshold.
5. **Separate spatially** — connected components on the class map.
6. **Density** = accepted count ÷ calibrated analysed area, with the criterion
   in provenance. Unchanged from the current rule, and still areal, never
   volumetric without foil thickness.

**No brightness threshold. No shape filter. No ridge filter.** An end-on needle
classifies correctly because its *pattern* is precipitate-like even though its
*image* is a dot.

## 3. What it touches, and who owns the state

| | |
|---|---|
| Reuses | `Core/Analysis/DiffractionEmbedding.swift` — featurisation, PCA, k-means, streaming, cancellation. Already on `main`, gated, 7 tests. |
| New Core | class-average diffraction patterns; the precipitate-class criterion; spatial separation. |
| State owner | A `Session/` product type, to be created. **It does not exist on `main`** — `PrecipitateProduct.swift` is still branch-only, because steps 5-7 were skipped when the precipitate ship gate came up unmet. `Session/DiffractionGroupsProduct.swift` (landed step 9) is the shape to copy. One `AppState` `let`, no forwarding properties. |
| UI | the existing **AI Analysis** workspace. No new room. |
| Retired | `PrecipitateSegmentation`'s ridge/threshold path, *if* §4 shows the new route wins. Not before. |

`Core/Analysis/Precipitates/` stays where it is: it is named by outcome, which
is the repo's rule (D1). Nothing moves into an `AI/` folder — "AI" is a
technique, not an outcome, and only one file in the repo imports CoreML.

## 4. The tests, written before the code

**This route can finally be checked against upstream, and that is its strongest
claim.** `References/py4DSTEM-dev/py4DSTEM/process/classification/` ships
`Featurization` (PCA, ICA, NMF, GMM, `spatial_separation`, `consensus`) and
`BraggVectorClassification` (NMF refine, `split`, `merge`).

1. **Parity harness against py4DSTEM** — `tools/` gated, joins
   `run-tests.sh scientific`. Same cube, same featurisation, compare class
   assignment and class-average patterns against `Featurization`. Deviations get
   inline `DEVIATION` notes. **This is the acceptance gate the image route could
   never have.**
2. **Synthetic fixture** — patterns with known class membership per position,
   built so a wrong assignment cannot pass. Broken before trusted.
3. **The Al-Si-Mg cube** — the class map's precipitate classes must recover the
   35 marked objects (`archive/v3/precipitate-handcount-2026-09-11.md`) within
   the owner's adjudication, **including the 7 end-on ones the image route
   deletes by construction**. That is the discriminating test between routes.
4. **Ship gate, pre-registered here**: the classification route must beat the
   image route on the owner's adjudicated count — recall and precision, a tie
   passes, matching the rule already set on 2026-09-11 — **or it does not
   ship and the image route stands.** Symmetric with what the ridge filter was
   held to.

## 5. Decisions owed to the owner

1. **PCA or NMF.** Upstream offers both. NMF's non-negativity is physically
   right for intensities and is what `BraggVectorClassification` uses; PCA is
   already implemented and gated. Proposal: keep PCA, add NMF, let the parity
   harness decide. **Owner's call.**
2. **How many classes, and who picks.** k is a user control today. A precipitate
   map probably wants "matrix + N variants" chosen from the data, not a slider.
   **Owner's call.**
3. **Does this retire the ridge filter, or do both ship?** Proposal: keep both
   until §4.4 decides, then retire the loser rather than carrying two.
4. **Per-object export.** Still open from §1.5 and still unanswered: a per-object
   list has no home in a per-scan-position data model, and `clear()` drops it on
   dataset change with nothing written. This route does not fix it.
5. **Multi-dataset density.** The owner asked (2026-09-11) for density over
   several cubes for accuracy. Not in this registration; it is a separate
   aggregation feature and needs its own.

## 6. What this does not claim

It does not claim to be more accurate — that is what §4.4 measures. It claims
to use the information the instrument recorded, to be checkable against
upstream, and to have no threshold or shape parameter for a reviewer to
question. If the parity harness or the adjudicated count says otherwise, the
registration is what it is measured against, not a thing to be revised
afterwards.
