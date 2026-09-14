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
4. **Identify precipitate classes.** Two routes, and the owner's objection —
   "the user has to check by hand anyway, are we running into slop here?" — is
   what separates them:
   - **Unsupervised (weak).** Read each class's average diffraction pattern and
     decide by eye which show the superlattice reflections. This is the slop he
     named: k-means returns k *unlabelled* groups, and nothing makes them
     "matrix + 3 variants" rather than "thin + thick + bent + oxide".
   - **Template-matched (strong, and preferred).** We KNOW the structure. Import
     β″ as a CIF, predict its diffraction for each variant orientation, and
     match each class average — or each position directly — against those
     templates. The class comes back **labelled, with a score**, not as a group
     awaiting interpretation.

   **The app already has this machinery**: `Core/Crystal/CIFImport.swift`,
   `CrystalModel.swift`, `OrientationMatcher.swift`, `OrientationPlan.swift`,
   `ScatteringFactors.swift` — the template matching ACOM runs on. It is not a
   new capability, it is an existing engine pointed at a second structure.
   Decision 2 in §5 is now "unsupervised or template-matched", and the
   recommendation is template-matched with clustering as the fallback for
   whatever the templates do not explain.
5. **Separate spatially** — connected components on the class map.
6. **Density.** Areal = accepted count ÷ calibrated analysed area, criterion in
   provenance. **Areal is a way-station, not the goal.** The goal is a
   VOLUMETRIC number density, and the route to it was designed before this
   registration existed: `docs/ai-ml/README.md` §5, "Thickness and the path to
   number density" — PACBED-based foil-thickness estimation, then volumetric =
   count ÷ (area-weighted thickness × area). That design was **not lost and
   never coded**; it was marked a v1 non-goal in `precipitates.md`:15 and is
   unbuilt on both branches (no Swift file on either side mentions thickness).
   It is out of scope here only because thickness is its own feature with its
   own validation — §5 is explicit that thickness needs a stated material,
   orientation, convergence angle, detector sampling, valid range and failure
   behaviour, and that one must "not silently turn an areal count into a
   volumetric claim". This registration must therefore **report areal and say
   so**, and must not be read as settling the density question.

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

1. **Parity harness against py4DSTEM — BUILT 2026-09-11**,
   `tools/embedding-pca-parity`, in the `scientific` gate, 8 checks green.
   **It is narrower than this section first claimed, and the claim is corrected
   rather than quietly met.** As written it promised "same cube, same
   featurisation, compare class assignment and class-average patterns against
   `Featurization`". None of those three is deliverable, established by
   measurement:
   - **Not the featurisation.** py4DSTEM's only shipped featuriser is
     `from_braggvectors`; it has no binned-pattern representation. Both sides
     therefore consume the matrix `embed` produced, which is why negative
     control NC6 (log1p → identity) stays green.
   - **Not class assignment.** `grep -rin "kmeans|k_means|KMeans"` over the
     pinned tree returns **nothing** — py4DSTEM clusters with `GaussianMixture`.
     Any k-means number is an sklearn reference, never a py4DSTEM parity, so it
     is printed and never gated.
   - **Not a real cube.** py4DSTEM passes neither `svd_solver` nor
     `random_state`, so sklearn's `auto` flips to the randomized solver above
     500 rows. Measured: n=500 → 0.0 run-to-run drift in
     `explained_variance_ratio_`, n=501 → 5.9e-4. The fixture is capped at 400.

   **What it does check, and this is still the first upstream-checkable number
   on the app's AI side:** PCA decomposition against py4DSTEM's *own*
   `Featurization.PCA` (which does accept an arbitrary positions × dims matrix,
   verified — its scores equal sklearn's to 9.8e-15), and `symmetricEigenTop`
   against `numpy.linalg.eigh`. The second is the one that would have caught the
   2026-09-06 subspace-iteration defect; the PCA checks alone cannot, because
   explained-variance *ratios* hide a uniform eigenvalue error.

   This correction is a factual one — the registration described a capability
   py4DSTEM does not have — not a goalpost moved after seeing a result. §6's
   rule stands for results.
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

1. **PCA or NMF. SETTLED 2026-09-11: keep PCA for now** (owner). NMF stays a
   named comparison, not a prerequisite: it is physically righter for
   intensities (a pattern is a non-negative SUM of contributions, and NMF models
   exactly that, while a negative PCA coefficient means "subtract this pattern",
   which photon counts cannot do) and its components look like indexable
   patterns rather than signed difference-patterns. Against it: NMF is a
   non-convex optimisation with a random start, so two runs differ unless
   seeded, and it has no explained-variance equivalent to justify a component
   count. PCA is deterministic, fast, already gated.
2. **REFUTED 2026-09-11 AS PRE-REGISTERED — per-position template matching does
   not work, measured before the importer work was paid for.** Full record:
   [`archive/v3/phase-discrimination-2026-09-11.md`](archive/v3/phase-discrimination-2026-09-11.md);
   reproduce with `tools/phase-discrimination-probe/run.sh`.
   - **The mixing flip is at f = 0.60**, against a pre-registered ceiling of
     0.30. The matrix wins until the precipitate supplies 60 % of the pattern.
   - **Worse: the score picks the wrong phase.** On a pattern containing only
     aluminium, **gold fcc scores 0.98758 against aluminium's 0.97949** —
     contrast −0.008. A bare argmax over phases returns the wrong one,
     confidently.
   - **Why: a sampling limit, not a bug.** The polar template has `nRadial` bins
     over `kMax`; at defaults one bin is 0.05 Å⁻¹, and Al–Au (111) differ by
     0.0030 Å⁻¹ — **6 % of one bin**. Al–Cu differ by 103 % of a bin and are
     correctly separated (0.500). Phases closer than one bin are the same
     pattern to this score.

   **This does not condemn shipped ACOM** — it matches orientation for a phase
   the user chose, is single-phase by design, and no shipped number is wrong.
   It condemns building phase identification on a bare `bestScore` argmax.

   **What survives, and none of it is measured yet:** the discriminating signal
   must come from what is NOT matrix — score only the reflections unique to the
   candidate phase (β″'s superlattice reflections sit at r ≈ 9-10 px where Al's
   first ring is ~18 px, many bins apart), or score the difference from a matrix
   reference, or require a contrast margin over the runner-up rather than a bare
   argmax. And the radial sampling must resolve the phases at all, which is a
   settable parameter nobody has costed.

   **Consequence the owner should see: the unsupervised clustering step he
   called "slop" is back in play**, because the class-average difference
   pattern, not the per-position pattern, is where the signal survives.

   The superseded approval, kept for the record — **template-matched, and
   material-general** (owner: "yes
   that is a great idea! make it scientifically more reliable, and more
   versatile for different samples not just al"). The class identity comes from
   matching an imported CIF, never from a hardcoded Al-Mg-Si assumption — which
   also discharges `docs/ai-ml/README.md` §2's standing requirement to "derive
   everything from the data, not from Al-Si-Mg-specific constants".

   **This is MULTI-PHASE IDENTIFICATION**, which `v3-plan.md`:20 already ranks
   immediately before precipitates ("multi-phase → precipitates → EDX"). Two
   blockers, both measured 2026-09-11:
   - `Core/Crystal/OrientationMatcher.swift:324` hardcodes `phaseID: 0`. The
     field exists; only one phase is ever written. Multi-phase means carrying N
     `CrystalModel`s and reporting which one won, with its score.
   - **`CIFImport` refuses a monoclinic cell outright** — the real blocker, and
     not the one this section first named. `CIFImport.swift:798-810` has exactly
     three paths: cubic, hexagonal, `throw unsupportedPointGroup`. There is no
     fourth return, so **`.identity` is unreachable from the importer** and a β″
     CIF cannot be loaded at all today. The earlier text here said β″ "falls to
     `.identity`"; that was wrong.

   **SETTLED 2026-09-11 by line-level trace, and favourably** — it was flagged
   untested when first written: point-group coverage is needed to REPORT an
   orientation, not to decide WHICH PHASE a pattern is. Template *generation* is
   symmetry-agnostic (`Crystal.swift:76-105` builds the general triclinic metric
   tensor from arbitrary a,b,c,α,β,γ; `reflections(kMax:)` tiles hkl with no
   family assumption), and symmetry is read in exactly two places:
   `OrientationPlan.swift:120` (which zone axes are sampled) and
   `OrientationMatcher.swift:319` (`symmetry.reduce`, which runs AFTER the argmax
   at :287-290). So `.identity` costs sampling density, not correctness. Since
   precipitate phase labelling does not wait for monoclinic point groups, and
   `v3-plan.md`:22's "multi-phase needs point-group coverage" applies to the
   orientation half only. It also does not need grain segmentation: the plan
   pairs those for polycrystal work, and a precipitate is not a grain.

   The superseded alternative, and the owner's objection that killed it: unsupervised clustering returns unlabelled groups
   that a human must interpret, which is soft. Template matching against an
   imported β″ CIF returns a labelled class with a score, and the app already
   owns the engine (`Core/Crystal/*`, what ACOM runs on). **Recommendation:
   template-matched, clustering as the fallback for what templates do not
   explain.** Needs from the owner: a β″ CIF, or agreement to fetch one.
3. **The ridge filter.** Owner, 2026-09-11: "maybe it has to go, or come back
   later — maybe we were too fast and didn't think it through." A third option
   exists and was not visible when the question was first put: **it is
   fixable**. `PrecipitateSegmentation.swift:389` computes both Hessian
   curvatures and then keeps only the most negative one
   (`max(0, -lambdaMin)`) — so a round blob, curved downward in EVERY
   direction, scores at least as high as a needle. It is not measuring
   elongation at all; it measures "is this a bump". That is why its own
   pre-registered baseline came out a tie with both arms reporting every round
   particle. Elongation selectivity requires COMPARING the two curvatures.
   Proposal: do not retire it on a tie it lost for a correctable reason. Park
   it; if the classification route wins §4.4 it is moot, and if it loses, fix
   the eigenvalue comparison and re-run the baseline.
4. **Per-object results — storage AND presentation.** Still open from §1.5. A
   per-object list has no home in a per-scan-position data model, and `clear()`
   drops it on dataset change with nothing written, so a save/reopen loses every
   measured number. Owner, 2026-09-11: "an endlessly long table doesn't seem to
   be the solution" — agreed, and the two halves are separable. **Storage** is
   settled by a sidecar table plus CSV export, which costs nothing in the UI and
   is what statistics and plotting need. **Presentation** is the open question:
   the useful on-screen object is almost certainly a length/orientation
   HISTOGRAM and a labelled map you can click, with the table as export only.
   Not designed here.
5. **Multi-dataset density, and VOLUMETRIC density.** Two separate features,
   both out of scope here, both named so they are not lost again:
   - Several cubes combined as total count ÷ total area (never the mean of
     per-cube densities, which weights a small field like a large one). The app
     is one-dataset-at-a-time throughout.
   - **Volumetric number density via thickness** — `docs/ai-ml/README.md` §5,
     designed and never built. This is the owner's actual goal; areal is the
     way-station. Needs its own pre-registration.

## 6. What this does not claim

It does not claim to be more accurate — that is what §4.4 measures. It claims
to use the information the instrument recorded, to be checkable against
upstream, and to have no threshold or shape parameter for a reviewer to
question. If the parity harness or the adjudicated count says otherwise, the
registration is what it is measured against, not a thing to be revised
afterwards.
