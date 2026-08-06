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
> **The third entry has not graduated** — *Q calibration is fragile to origin
> error well below the readiness threshold* (2026-08-06) belongs to no plan yet
> and needs a scope decision before anyone implements it.

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

**Do not** re-derive this by replacing the estimator with nearest-neighbour
spacing — that was tried on 2026-08-06 and refuted (breaks `tools/strain-test`
on single-peak patterns; Q errors to +176% on superimposed lattices). The full
refutation is in archived backlog #46.
