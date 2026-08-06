# Post-v1 feature ideas

Product ideas that are **out of v1 scope** but worth capturing while the
thinking is fresh. Nothing here is committed to, scheduled, or promised.

> **Both entries below have graduated.** They are now stages L3 (crop-on-read)
> and L4 (bin-on-read) of the active plan,
> [`docs/load-pipeline-plan.md`](load-pipeline-plan.md) (2026-08-06), alongside
> a resident in-memory cube and an open-time preview. Every trap recorded here
> is reproduced there, with the py4DSTEM source lines that prove it. Keep this
> file as the origin record; **plan from the plan.**

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
