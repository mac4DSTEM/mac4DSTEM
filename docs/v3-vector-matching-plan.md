# Vector-matching phase mapping — the plan, 2026-09-11

How Thronsen et al. (Ultramicroscopy 255 (2024) 113861, **CC BY 4.0**) gets
incorporated. Method choice and its reasoning:
[`v3-phase-mapping-method-choice.md`](v3-phase-mapping-method-choice.md).

## What we take, and what we may not

| source | licence | what we may use |
|---|---|---|
| the **paper** | **CC BY 4.0** | the method, and **Table 2's structures** (space groups, lattice parameters, atomic positions for Al, T1, θ′) — reusable with attribution |
| their **GitHub repo** | **none** | nothing. Default copyright: no code, no notebook fragment, no CIF file |
| their **Zenodo dataset** | **CC BY 4.0** (checked 2026-09-11) | the 4D data, the published ground-truth phase map, their four phase maps, and their trained ANN |
| py4DSTEM | GPL-3.0 | source-level, as today |

**The distinction that unlocks the plan: the repo and the paper are not the same
artefact.** We cannot copy their `cif-files/`, but we can author CIFs from the
paper's Table 2 and cite it. Parameters that exist only in their notebooks
(`min_sigma=3.6`, mask thresholds) are derived here instead.

## The single biggest thing we gain

**An external ground truth.** Every validation problem this repo has hit on
precipitates comes from having nothing to check against: the precipitate maths
has no py4DSTEM counterpart, the synthetic fixture cannot discriminate, and the
Al-Si-Mg hand count does not exist.

Their dataset ships a **ground-truth phase map built independently by three
people**, plus four published phase maps scored against it. That is a real
acceptance target — and their metric is simple enough to adopt verbatim: the
**fraction of mislabelled scan positions**.

So the plan validates the method on *their* material, where truth exists, before
applying it to *ours*, where it does not.

## The build order

### 0 — Unblock the importer  *(small, no science)*
`CIFImport.swift:798-810` has three paths: cubic, hexagonal, `throw`. Add the
`.identity` path so a monoclinic or tetragonal cell can load at all. Settled by
measurement 2026-09-11: symmetry never touches template generation or the
winner — it is read only at `OrientationPlan.swift:120` (zone-axis sampling) and
`OrientationMatcher.swift:319` (orientation reduction). **Owner's ruling owed:**
admitting `.identity` means a phase whose orientation cannot be reduced, so its
IPF colour must be withheld. `CIFImport.swift:10-17` argues for refusing rather
than half-reporting.

### 1 — Reference vectors from a CIF  *(Core, no UI)*
Reciprocal lattice → rotate to a zone axis → keep points in a thin slab about
z = 0 → apply the matrix's in-plane rotation. `Crystal.reflections(kMax:)`
already handles arbitrary cells and `OrientationPlan.project` already does the
zone-axis projection, so this is composition, not new mathematics. Their slab
thicknesses (0.030 / 0.300 Å⁻¹) are phase-dependent; ours get derived.
**Gate:** unit tests against hand-computed vectors for a cubic case where the
answer is known by arithmetic.

### 2 — The matcher  *(Core; Gate D and Gate B both apply)*
Three parts, each small:
- **Matrix removal in vector space** — drop experimental vectors lying close to
  the matrix reference vectors; fewer than two survivors means matrix. This is
  the whole of their image-space DoG masking, done where we already work.
- **Per-pattern reference subset** — for each experimental vector keep only its
  closest reference vector, so a thin precipitate showing two spots is not
  penalised against a phase with forty.
- **Score** — mean |u − v| over *unique* reference vectors, lowest wins,
  **above a threshold the answer is "not indexed"** rather than a forced label.

Gate D applies: the output is a phase label that reaches an export. Gate B
applies: it is new Core that moves a scientific number.

### 3 — Validate against their published ground truth  ← **the point of all this**
- Author `Al`, `T1`, `θ′` CIFs from the paper's Table 2, attributed CC BY 4.0.
- Fetch their Zenodo dataset — **licence checked 2026-09-11: Creative Commons
  Attribution 4.0 International**, so this is usable today with attribution.
  The record is 451 GB in total, but the parts that matter are small:
  `ground_truth.hspy` is **37.3 kB** and the preprocessed `datasetA` is ~7.4 GB.
- Run our matcher; compare to their ground truth by their own metric.
- **Acceptance, pre-registered here:** our mislabelled fraction must land within
  the band their four methods occupy (they report 98.5 % ± 0.5 % and say the
  differences between methods are not significant). Landing outside that band
  means our implementation is wrong, not that the method is.

This is the first acceptance test in the precipitate programme that does not
depend on the owner's eye.

### 4 — Apply to Al-Mg-Si  *(the actual goal)*
Needs a β″ CIF — **not from their repo**, which has none: Andersen et al. 1998
(*Acta Mater.* 46(9):3283) or Materials Project mp-31404 (CC BY 4.0, DFT-relaxed
and therefore ~1 % off on d-spacings, which needs its own note). Plus the β″/Al
orientation relationship, which is published. Then: phase map → connected
components → count ÷ calibrated area.

### 5 — UI
The AI Analysis room grows a phase-mapping task beside diffraction grouping.
Deferred until 3 has passed — there is no point designing screens for a method
that has not met its acceptance test.

## What we inherit that is not good

Stated now so it is not discovered later. Their implementation:
- **is zone-axis only**;
- **cannot handle phases overlapping along the beam** — NMF is the only one of
  their four that can, which is an argument for keeping `DiffractionEmbedding`
  as the exploratory tool rather than replacing it;
- **is confused by strain shifting Bragg positions** — and they name this, not a
  low vector count, as the main cause of their interface errors. This app
  measures strain, so it may be able to do better here than they did, but that
  is a hypothesis, not a plan.

## Decisions owed by the owner

1. **`.identity` symmetry:** accept a phase labelled without an IPF orientation
   colour? Blocks step 0.
2. **A β″ CIF** — author from Andersen 1998, or take mp-31404 and carry the
   DFT-relaxation note? Blocks step 4, not steps 0-3.
3. **Zenodo download** — no longer a licence question (CC BY 4.0, checked), only
   a disk one: preprocessed `datasetA` is ~7.4 GB against a machine sitting at
   9 GB free with an 8 GB gate floor. The ground truth itself is 37 kB.
   Blocks step 3.
