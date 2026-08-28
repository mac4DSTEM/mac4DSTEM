# Post-v1 feature ideas

Product ideas that are **out of v1 scope** but worth capturing while the
thinking is fresh. Nothing here is committed to, scheduled, or promised.

> **The first two entries have graduated.** Cropping and partial/binned loading
> are now stages L3 (crop-on-read) and L4 (bin-on-read) of the active plan,
> [`docs/load-pipeline-plan.md`](load-pipeline-plan.md) (2026-08-06), alongside
> a resident in-memory cube and an open-time preview. Every trap recorded here
> is reproduced there, with the py4DSTEM source lines that prove it. Keep this
> file as the origin record; **plan from the plan.**
>
> **The third entry graduated 2026-08-18** — *Q calibration is fragile to
> origin error below the readiness threshold* is claimed by
> [`docs/v2-release.md`](v2-release.md) sessions S11–S13 (triage → design →
> implement); the constraints recorded below are the design input. **WS₂
> step 1 graduated the same day** (S14–S16). Step 2 (Materials Project) and
> the precipitate pipeline remain unclaimed, as do the two 2026-08-18
> entries and the 2026-08-26 EDX entry at the end. The precipitate entry
> gained the density deliverable 2026-08-26, at the owner's request.

## Why this file exists (and what does *not* belong here)

There are three other places an idea could go, and each excludes this kind:

- **`docs/open-items.md`** carries only UI/workflow-safe items; every one is
  a workflow- or presentation-layer change and that **no item touches `Core/`**.
  The ideas below all touch data loading and calibration semantics, so filing
  them there would break that contract — which is what makes that backlog
  safe to hand out as implementation prompts.
- **`docs/v1-scope.md`** is the frozen release contract. Its Post-v1 section is
  deliberately a terse enumeration; speculative detail does not belong in a
  contract.
- **`ROADMAP.md`** holds the three standing priorities, not a feature list.

So: **UI/workflow polish → the backlog. Scope decisions → v1-scope. Ideas that
need real design and touch `Core/` → here.**

Each entry records the constraints that are non-obvious *now*, so a future
session doesn't rediscover them. An idea graduating from this file should get a
proper scope decision first (`ROADMAP.md`'s rule: a new feature must close a gap
in `docs/v1-scope.md`, or it is post-v1).

---

## Cropping in real and diffraction space

**Requested 2026-08-05.** Let the user crop the datacube — a real-space region
of interest, and/or a diffraction-space sub-window — rather than always working
on the full array.

**py4DSTEM reference:** `preprocess.crop_data_real(datacube, crop_Rx_min,
crop_Rx_max, crop_Ry_min, crop_Ry_max)` and `crop_data_diffraction(datacube,
crop_Qx_min, crop_Qx_max, crop_Qy_min, crop_Qy_max)`
(`References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:123,139`). Both are
plain array slices that then reset the dim vectors.

**The trap, and it is in the reference implementation:** neither py4DSTEM
function adjusts the **origin**. `crop_data_diffraction` slices the detector
axes and resets `Qx`/`Qy` dim vectors, but leaves `qx0`/`qy0` untouched — so a
previously fitted origin silently refers to the *old* detector frame. In this
app the origin is a per-scan-position fitted map (`Calibration.origin`), the
ellipse fit is in detector coordinates, and `minPeakSpacing` is now derived from
the probe radius in detector pixels. A diffraction crop must re-reference all of
them or explicitly invalidate them. **Do not copy py4DSTEM here without
deciding this deliberately** — and if the app diverges, it needs an inline
`DEVIATION` note per the repo's port rule.

**Other constraints:**
- A real-space crop changes what scan indices *mean*. Any already-computed
  result (strain map, ACOM map, Bragg vectors) is indexed against the old
  extent and becomes ambiguous, not merely stale.
- The cropped cube is a **different dataset**. Provenance must record the crop
  bounds, or an exported product cannot be traced to the source (ROADMAP P1.1
  keeps interpretation attached through export and reopen).
- Interaction with existing region controls: the app already has a real-space
  ROI (`realSpaceShape`, `acomRegionRadius`, strain's "Current real-space ROI"
  reference). A crop is a *different* concept from a region-of-analysis, and
  the UI must not blur them.

---

## Loading a large dataset partially, or reduced

**Requested 2026-08-05.** Two related modes, both aimed at working with cubes
too large to load whole:

1. **Load a real-space subregion only** — e.g. a small patch of the scan.
2. **Bin in diffraction space on load** — reduce detector resolution at read
   time rather than after.

**py4DSTEM reference:** `bin_data_diffraction(datacube, bin_factor, dtype)` and
`bin_data_mmap(datacube, bin_factor, dtype=np.float32)`
(`preprocess.py:155,222`). `bin_data_mmap` is the closest existing precedent to
"bin on load" and is worth reading before designing this.

**What binning does to calibration — py4DSTEM's own handling, verified:**
- It **sums**, not averages (`.sum(axis=(3,5))`), so intensities scale by
  `bin_factor²` and any absolute-intensity threshold moves with it.
- It **crops the edge remainder** when the detector size is not divisible by
  the bin factor.
- It scales `Q_pixel_size` **up** by `bin_factor` and writes it back to the
  calibration.
- It **does not rescale the origin** — the same trap as cropping.

**What it would touch in this app:**
- Q pixel size scales by `bin_factor`; probe radius in pixels scales by
  `1/bin_factor`; the origin scales likewise.
- `minPeakSpacing` is now derived from the fitted probe radius (backlog #5 /
  pipelines §10.3), so it follows the probe automatically — one thing that
  should *not* need special handling, and a small vindication of that fix.
- There is already a bin concept in the codebase to be consistent with:
  `BraggVectorEMDWriter` divides the probe semiangle by a bin factor on export,
  and the training set carries `bin2` / `bin8` files.
- Memory: the app already rejects loads it cannot satisfy; partial/binned
  loading is precisely the escape hatch for the datasets that trip it.

**The scientific-labelling question, which is the real design work:** a binned
or partially-loaded cube is **not the same measurement** as the full one.
Results from it must be labelled and exported as such, or two products that
look alike will not be comparable. This is the same class of problem the
Exploratory-vs-Physical scale labelling already solves for ACOM, and it should
probably reuse that pattern rather than invent a second one.

**Open question worth settling early:** is a partial load a *view* of the
original dataset (recoverable, re-openable at full extent) or a *new* dataset
in its own right? That answer determines session-restore and export behaviour,
and it is much cheaper to decide before implementing than after.

---

## Crystal models: a real WS₂ structure, then a Materials Project lookup

**Raised 2026-08-06.** Two steps, and the first is small enough to do soon.

**Step 1 — ship a 2H-WS₂ CIF as a fixture, and close #11 with it.**
`CrystalModelLibrary` currently holds seven models, six of them cubic and every
one a single element; `mg_hcp` is the only hexagonal entry. A WS₂ structure adds
the two things nothing else covers: **hexagonal symmetry** and a **two-species
compound** (scattering factors for a mixed basis, symmetry expansion on a
non-cubic cell). It therefore tests the CIF import path far better than another
cubic metal would, and it is what `polycrystal_2D_WS2` needs to reach ACOM at
all.

**Do not invent the lattice.** Use the published 2H-WS₂ structure — P6₃/mmc,
a ≈ 3.153 Å, c ≈ 12.323 Å. A fabricated cell would still import, still index,
and still produce an orientation map, which is exactly the #46 failure mode: a
result that exists, looks plausible, and is wrong. Lattice parameters are
measured facts; take them from the crystallographic literature and record the
source in the CIF header.

**Step 2 — Materials Project lookup.** Search the database from inside the app
and pull the CIF directly, instead of the user finding and downloading one.
Recorded once before, in `docs/archive/audit-master-prompt-fable5.md`, which is
frozen history nothing points into — hence this entry. Open questions before
anyone builds it: it needs an API key (so: where is it stored, and what happens
offline?), the app is sandboxed and currently makes no network calls at all,
and an imported structure needs provenance that survives export and reopen
(ROADMAP P1.1) — "which structure did this orientation map actually use?" must
have an answer that outlives the session. Step 1 is a prerequisite: get the
import path and its provenance right on a local file before adding a network.

---

## Analysis pipeline for needle-shaped precipitates

**Raised 2026-08-06; not previously recorded anywhere.** A domain-specific
workflow for needle/rod-shaped precipitates — the kind of task where the
generic virtual-detector → disks → strain/ACOM chain is the wrong shape,
because the object of interest is a morphology with an axis, not a field
sampled per scan position.

Nothing is designed. What is worth writing down now, before it is:

- It probably wants **segmentation or detection in real space** driving a
  per-object analysis, which is a different control flow from every existing
  task (all of which run over the whole scan or a rectangular ROI).
- A per-object result is **not a map**, so `resultImage` / `resultRGBA` and the
  session product model may not fit it. That is a product-model question, not
  an algorithm question, and it is the expensive part to get wrong.
- This is a plausible first home for **MLX** (see
  `docs/development-process.md` §5): object detection is where ML earns its
  keep, far more than reimplementing disk detection.

Likely end of a second phase or later. Recorded so the idea survives the gap.

**Re-requested by the owner 2026-08-26, with a new deliverable: precipitate
*densities* (count per area/volume).** What that adds beyond the per-object
pipeline above, worth writing down before it is designed:

- A density is **counting divided by a calibrated extent**, so it inherits
  every real-space calibration guarantee v2 hardened — and adds a new one:
  the *denominator* must come from the scanned area actually analysed (a
  cropped or partially-driven scan silently shrinks it), or the number is a
  precise wrong claim under the refusal rule.
- A count needs a **detection threshold**, and a threshold needs the same
  honesty treatment as Q calibration got: state what was counted, at what
  criterion, and refuse a density when the criterion cannot be stated. An
  areal density from a projection is not a volumetric density — claiming
  number-per-volume needs foil thickness, which the app does not measure;
  that gap is exactly the EDX/thickness territory of the entry below.
- Statistics over many datasets is where this earns its keep, and **v2 S5's
  replay record is the seed**: "apply this recipe to N cubes and tabulate
  counts" is the batch-processing deferral in `docs/v2-release.md` §3, not a
  new mechanism.

---

## Q calibration is fragile to origin error well below the readiness threshold

**Found 2026-08-06 by the adversarial review of the #46 fix.** #46 itself is
closed: `calibrateQFromCrystal` now refuses when `Calibration.originFitRefusal`
is non-nil, so a Q pixel size can no longer contradict a warning the app has
already issued. What the review established is that the *threshold* that gate
inherited is looser than the failure it guards against, and that a second route
to the same wrong number is not gated at all. Both need `Core/` changes, which
is why they are here and not in `docs/open-items.md`.

**1. The gate fires at the probe radius; the estimator breaks at ~2 px.**
`KnownCrystalQCalibration.estimate` discards peaks inside `minimumRadiusPixels`
(default `2`, and `AppState.calibrateQFromCrystal` does not override it). By the
mechanism #46 itself established — `BraggVectors.calibrated` re-centres every
pattern on its fitted origin, so a per-position fit error δ puts the direct beam
at radius |δ| — once δ exceeds 2 px the direct beam survives that filter and
becomes the "innermost non-central reflection". The failure onset is therefore
≈2 px, not the 5.03 px probe radius used by `originFitIsQuantitative`.
Everything in `(2 px, probeRadius]` still calibrates and is still stamped
`.measuredInApp`.

The review's simulation of that mechanism (Si_SiGe: a = 14.9 px,
|g₁₁₁| = 0.318925 Å⁻¹, true Q ≈ 0.02140) also makes the error **non-monotone** —
≈1.1× at 2 px, peaking ≈3.5× at 3 px, falling to ≈2.4× by 11.66 px as δ
saturates near 0.38a. So the current threshold rejects the mild end of the
failure curve and accepts the severe end. Datasets with a larger probe radius
(Particle_1, ≈10.6 px) have a correspondingly wider hole.

**The suggested shape, not yet designed:** do the check *inside* `estimate`,
where the observed innermost radius, its MAD, and the reference g-length are all
in hand — e.g. refuse when the median innermost radius is implausibly small
relative to the reference shell. That is dataset-independent and would catch
item 2 below for free. It is deliberately **not** "tighten
`originFitIsQuantitative` to 2 px": that predicate also drives the Prepare
readiness badge, and "is this origin fit sane?" is a genuinely looser question
than "may I measure a reciprocal scale in this frame?". Splitting them is part
of the design work.

**2. `meanOrigin == nil` silently measures from the geometric detector centre.**
`AppState.calibratedBraggVectors` falls back to `(qx/2, qy/2)` when
`calibration.meanOrigin` is nil. `meanOrigin` requires the per-position maps in
`calibration.origin`, and the `.fileMean` import path sets `aperture.centerX/Y`
from the file's `qx0_mean`/`qy0_mean` while leaving `calibration.origin` nil —
so **the file's own stated beam centre is ignored** and radii are measured from
the detector's geometric centre. `.fileMean` maps to a non-nil readiness
provenance, so the Origin row reads ready; there is no residual, so
`originFitIsQuantitative` returns `true` and the #46 gate does nothing.
`.sessionMean` restore sets `calibration.origin = nil` explicitly and reaches
the same state. Any beam more than ~2 px off the geometric centre then collapses
the innermost radius exactly as in item 1.

**3. The residual may not measure what the gate assumes.**
`OriginMaps.rmsResidual` is RMS(measured − fitted), i.e. how far the *fit*
departs from the per-position measurements — but the analysis path consumes
`fittedX`/`fittedY`. A large residual is equally consistent with a fit too rigid
to follow real descan (the fitted origin is displaced, and refusing is right)
and with noisy per-position measurement that the fit correctly averages out (the
fitted origin is fine, and refusing withholds a good calibration). #29 records
this as unanswered; the #46 gate resolves it by assumption. The discriminating
evidence already exists and has never been read:
`tools/training-dataset-campaign` records `constant_rms_px` and
`parabola_rms_px` beside the plane fit, so comparing the three fit functions on
the same dataset should settle it cheaply.

> **ANSWERED by S12, 2026-08-28 — and the question above is a false
> dichotomy.** Both causes occur, on different real datasets, and the current
> gate cannot tell them apart because RMS discards exactly the information that
> separates them. `downsample_Si_SiGe_exp` is broad measurement failure
> (median/RMS 0.919, 84% of positions beyond the probe radius, iterative
> trimming removes nothing and moves the fit by 0.000 px) — refusing is right.
> `Particle_1…bin8` is outlier contamination (median/RMS 0.183; trimming
> converges at 72.7% kept, RMS 2.19 px against a 10.624 px gate) — and the
> contaminated plane is itself displaced by up to 6.00 px, past the ≈2 px
> breakdown item 1 names. The three fit functions span ≤14% on both, so the
> refusal's "try another fit function" remedy provably cannot work on either.
> Design, numbers and what S13 implements:
> [`docs/q-calibration-design.md`](q-calibration-design.md).
>
> One correction to the sentence above: the campaign *computes* those two
> metrics on demand, it does not retain them — there is no file to go read.
> **`tools/training-dataset-campaign/run.sh` reproduces them** — note that
> `tools/run-tests.sh campaign` does **not**: that mode's array is the parallax
> and ptychography harnesses and does not include `training-dataset-campaign`
> at all (a wrong instruction in this note's first draft, caught in review).
> S12 ran the campaign's compile-and-harness half without run.sh's py4DSTEM
> parity step, so `References/parity_records/latest` was left intact.

**Do not** re-derive this by replacing the estimator with nearest-neighbour
spacing — that was tried on 2026-08-06 and refuted (breaks `tools/strain-test`
on single-peak patterns; Q errors to +176% on superimposed lattices). The full
refutation is in archived backlog #46.

---

## Align streaming tiles to HDF5 chunk boundaries

**Recorded 2026-08-18, from the release-planning review.** A performance
idea, not a correctness one, so it waits for a measurement before any design.

The evidence that motivates it already exists: `LoadPushdown` was made
honest on 2026-08-18 by measuring that a crop *inside* a chunk skips nothing
— HDF5 reads and decompresses whole chunks (full detector 0.137 s, 1/64 of it
0.135 s on a gzip-chunked cube). The same fact cuts the other way: a
streaming **tile whose boundary straddles chunks decompresses the shared
chunks twice**, once per tile. Reading the chunk layout (`H5Pget_chunk`) and
snapping `scanTileRows()` boundaries to it would eliminate the double work
in the one reader where it matters.

Constraints worth knowing before building: the tile size currently derives
from the GPU working-set budget (`recommendedMaxWorkingSetSize / 8`), so
snapping must round *down*, never up — a tile grown to a chunk boundary can
blow the memory budget on exactly the machines that need streaming (see the
8 GB jetsam item in `docs/open-items.md`). And measure first on a
py4DSTEM-written chunked EMD, not the contiguous training cubes, where the
change is a no-op by construction.

---

## EDX correlation — a second signal per scan position ("5D")

**Requested by the owner 2026-08-26.** Correlate 4D-STEM products with EDX
maps acquired over the same scan — composition beside strain/orientation,
per scan position. Named in `docs/v2-release.md` §3 as its own product;
nothing is designed. The constraints that are non-obvious now:

- **This is a data-model change before it is a feature.** Today the model is
  one cube + one calibration + products derived from it. A second signal
  needs: its own reader (vendor EDX formats, or a pre-quantified map), its
  own axes/units, and a **registration** onto the scan grid — EDX and 4D-STEM
  acquisitions rarely share exact pixel grids, and resampling is a scientific
  operation that must be recorded, not silent. The `AppState` seam-per-session
  work (ROADMAP P3) is what makes this insertable later; if the facade stops
  shrinking, this feature is what pays the price.
- **Registration provenance is the refusal-rule surface**: an overlay of two
  signals implies they are the same place. The claim "this strain pixel is
  this composition pixel" needs the transform + its source stored with the
  product, or the correlation can fabricate spatial coincidence. Same class
  as the scan-frame work S8 shipped — reuse that carrier pattern, don't
  invent a second one.
- **Sidecar/EMD schema impact**: a second signal in the session sidecar is a
  schema version bump (the §5 min-reader machinery from S5 exists for
  exactly this) and a py4DSTEM interchange question — py4DSTEM's EMD tree
  can hold sibling arrays, so parity export is plausible, but pick the tree
  layout against the vendored lock before writing any file.
- Cheapest honest first step, when the time comes: **import a
  pre-quantified EDX map as an overlay layer** with a user-confirmed affine
  registration — no vendor spectral readers, no quantification, correlation
  scatter (strain vs composition per position) as the first product. Full
  spectral 5D (energy axis per position) is a much bigger cube and a
  separate decision.
- Blocked on real paired acquisitions from the owner's instrument time —
  like the MIB/EMPAD readers, this cannot be verified on synthetic data
  alone.

---

## Uncertainty propagation — error bars on quantitative results

**Recorded 2026-08-18.** The long-term scientific direction, deliberately
after v2: results carry model, scale, units and validity labels, but no
uncertainty. The ingredients already exist unread — the origin fit residual
(`OriginMaps.rmsResidual`), the per-peak correlation quality, the lattice-fit
covariance — and today they gate or decorate, but never propagate.
"ε_xx = 0.0132 ± 0.0008" is worth more to a paper than another analysis
modality; it is also the natural completion of ROADMAP P1.4's levels of
evidence (a number without an uncertainty cannot honestly claim the top
level).

What is non-obvious now, so it isn't rediscovered: the propagation must not
become a fabrication channel — an error bar computed from a model that does
not hold (e.g. treating the origin-fit residual as i.i.d. noise) is a *precise
wrong claim*, the worst kind under the refusal rule. **#29 is now answered —
S12, 2026-08-28, above** — and the answer sharpens this warning rather than
clearing it: the residual is broad scatter on one dataset and a heavy-tailed
mixture on another, so a propagation that assumes either shape globally is
wrong on the other. Every propagated interval
needs the same fixture treatment as the value it decorates: a case where the
true uncertainty is known analytically, and a negative control that fails
when the propagation is wrong.
