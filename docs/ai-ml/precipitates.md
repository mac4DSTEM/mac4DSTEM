# Precipitate segmentation and counting — feature specification

Status: design only, unscheduled (`docs/ai-ml/README.md` §9 step 3). No code,
no build, nothing on screen. Format per `docs/ai-ml/README.md` §8.

## 1. User outcome / non-goals

From a 4D-STEM scan of a precipitate-bearing alloy: individual precipitates
(needles, plates, particles) as objects with calibrated length, width,
orientation and area; a count and an areal number density over the analysed
extent; variant grouping (needle families by orientation/reflection).

Non-goals for v1: volumetric density (needs foil thickness — `v3-plan.md`
§"The precipitate chain" step 3, not this feature); phase identity from CIFs;
any net. A learned segmenter is optional and later (§2 step 6), not a
prerequisite for a first version.

## 2. The workflow that survives new samples and crystallographies

The owner's requirement (2026-09-07): derive everything from the data, not
from Al-Si-Mg-specific constants.

1. **Precipitate reflections.** Local maxima of the scan's MAX diffraction
   pattern that are not on the matrix lattice, inside the first matrix ring
   included. The matrix lattice comes from the classical Bragg vectors/ACOM
   already in the app, or from two user-clicked basis vectors when neither
   has run. Reproduced on the Al-Si-Mg cube: reflections at 7–10 px of a
   64-px detector, matrix disks at ~18 px
   (`docs/images/precipitates-al-simg-near-beam-2026-09-07.png`). The user
   confirms or edits the proposed list before anything downstream runs.
2. **One virtual dark-field image per confirmed reflection**, using the
   existing virtual-detector engine, plus BF/ADF. Each dark-field image
   selects one variant — demonstrated on the same cube: an annulus over both
   near-beam reflections shows both needle families, a 2.5-px circle on one
   reflection shows one family only (README §4).
3. **Real-space segmentation, classical first.** Per dark-field image:
   background flattening, a ridge/needle filter for elongated objects
   (oriented second-derivative or a steerable filter) and a threshold for
   blobs, then connected components → objects. Explicit rules: a minimum
   length; an object crossing the scan edge is flagged, not counted; overlaps
   are recorded, not silently merged or dropped.
4. **Per-object measurement.** Length and width from the object's principal
   axes, orientation, area, and the mean diffraction pattern inside the mask
   (a Metal/CPU reduction) — the last is stored for future phase work, not
   used for phase in v1.
5. **Areal density** = accepted count ÷ calibrated analysed area (R pixel
   size squared × counted positions), with the counting criterion recorded in
   provenance. Variants are counted separately and combined.
6. **Learned parts are optional and later.** An instance segmenter only where
   step 3 fails (touching needles), trained on synthetic shapes plus the
   owner's corrections, through the same tooling shape as the disk detector
   (`tools/disk-detector/`: simulate, train, export, hash, check). A learned
   "which reflections are precipitates" classifier only if step 1 proves
   brittle across samples. Neither is scoped or scheduled here.

## 3. Proposed screens

Minimal, in the existing workspaces — the owner wants slow, conservative UI
integration (README §3). No new sidebar workspace in v1.

- A "Precipitate reflections" list in the Imaging workspace's virtual-detector
  settings: propose → confirm, same interaction shape as an existing
  detector-geometry control.
- The resulting dark-field images are ordinary products, viewed like any
  other virtual image.
- A "Segment" action producing an object overlay on the real-space pane, plus
  an objects table in the inspector.
- Corrections by click: accept/reject now, split/merge later (not v1).
- Density in the Results workspace, shown with its assumptions (criterion,
  analysed area, variant breakdown) rather than a bare number.

When a learned part lands (§2 step 6), it moves into the AI workspace the
brief proposes (README §3); v1 has no dependency on that workspace existing.

## 4. Owner of state / data model

New `Session/PrecipitateProduct.swift`, on the `StrainProduct` pattern
(`mac4DSTEM/Session/StrainProduct.swift`): `@Observable`, `@MainActor`,
`package final class`, held by `AppState` with no forwarding properties,
`package private(set)` product state replaced only through a `publish`/
`clear` pair, run controls that survive dataset activation, a
`failureCause`-shaped explicit "why nothing published" state rather than a
silent empty result. No new stored state in `AppState` (`CLAUDE.md`).

Owns:

- the confirmed reflection list (position, source: derived or user-clicked);
- segmentation settings (filter choice, thresholds, minimum length);
- the object list: id, mask (run-length or bounding polygon — undecided,
  §8), length/width/orientation/area, mean masked diffraction reference,
  variant, accepted/rejected/edge flags;
- the density result and the criterion that produced it.

Persisted in the session sidecar, alongside `StrainMap` and its siblings.
Exported as CSV (one row per object) plus the masks as a labelled
scan-domain image, matching the export shape the app already uses for other
per-position products.

Core algorithms in `mac4DSTEM/Core/Analysis/Precipitates/` (reflection
finder, segmentation, measurements) — plain Swift/Accelerate/Metal, package
`DSTEMCore`, no SwiftUI, no AppState, no Session. Nothing in `Core/ML/` in
v1: no learned component is in scope yet (§2 step 6).

## 5. Input/output and unit contracts

Reflections and mask images are scan-domain (`ry × rx`), the app's existing
real-space grid. Density's area comes from R pixel size in the active
calibration; **no calibration, no density** — the refusal rule
(`docs/archive/v2/post-v1-ideas.md` §"Analysis pipeline for needle-shaped
precipitates": a count needs a stated criterion and a real denominator, or
the number is a precise wrong claim. Detector-space reflection coordinates
are (row, col), matching py4DSTEM's (qx, qy) convention already used
elsewhere in the app (`docs/architecture.md`).

## 6. Validation and acceptance, pre-registered

- A synthetic fixture: drawn needles of known length, orientation and count
  on a textured background, committed under a tracked fixtures path, broken
  four ways (the disk-detector fixture's shape — `docs/status.md`).
- The Al-Si-Mg cube as the real check, against the owner's hand count on a
  frozen sub-region (proposed: 100 × 100 scan positions) — recall and
  precision of objects, length error against the hand measurement.
- A baseline: threshold + connected components without the ridge filter.
  The ridge filter must beat it on both the synthetic fixture and the hand
  count, or it does not ship.
- Gate B (`docs/development-process.md`) at merge, independent of the model
  that wrote the change. On-screen acceptance is the owner's drive
  (`CLAUDE.md`) — this spec authorizes no app change.

## 7. Runtime budget

Seconds per scan on the CPU: one virtual-image pass per confirmed reflection
(existing engine cost) plus one segmentation pass per dark-field image. No
ANE in v1 (§2 step 6 defers the only learned component).

## 8. Unresolved decisions for the owner

- Ridge filter choice: oriented second-derivative vs. a steerable filter
  bank, and how many orientations.
- How variants are named (by reflection index, by angle, by the user).
- The edge-object convention: flagged-and-excluded by default, or
  flagged-and-included with a toggle.
- Whether the reflection finder needs the full matrix lattice (Bragg
  vectors/ACOM) or can run from just "not the beam and not the matrix disks
  the user clicks" — affects whether it depends on Strain & ACOM having run.
- The first sub-region to hand-count, and who counts it.
- Mask storage: run-length encoding vs. bounding polygon (§4).

## 9. Links to evidence

- Figure: `docs/images/precipitates-al-simg-near-beam-2026-09-07.png`
  (MAX pattern, annulus dark-field, single-reflection dark-field).
- Dataset:
  `References/training_dataset/Al_SiMg_Precipitates_SI60_preprocessed_unfiltered_bin_4_20260712.h5`
  (330 × 330 positions, 1.54 nm, 64 × 64 detector binned 4, 0.046 Å⁻¹/px,
  Al matrix on zone axis) — gitignored, owner-local.
- `docs/ai-ml/README.md` §4, the owner's 2026-09-07 observation and its
  design consequences (near-beam reflections as the segmentation channels,
  centre-plus-orientation object representation).
- `docs/v3-plan.md` "The precipitate chain" (2026-09-06) for the longer
  chain this v1 is a subset of (phase classification, strain/orientation
  channels, instance separation by heatmap) — exploration, not pre-registered.
- `docs/archive/v2/post-v1-ideas.md` §"Analysis pipeline for needle-shaped
  precipitates" (2026-08-06, re-requested 2026-08-26) for the per-object
  data-model warning and the density/threshold honesty requirement.
