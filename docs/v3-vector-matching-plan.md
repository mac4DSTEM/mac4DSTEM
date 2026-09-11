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

**The β″ structure is no longer a blocker — found 2026-09-11.** The owner already
had the canonical source: **Andersen et al., *Acta Materialia* 46(9), 3283-3298
(1998)**, in his own library. Table 3, set 3 is the C2/m refinement (R = 3.16 %
over 377 reflections, seven data sets):

| | |
|---|---|
| space group | **C2/m** (No. 12), C-centred monoclinic |
| cell | a = 15.16, b = 4.05, c = 6.74 Å, β = 105.3° |
| sites (all y = 0) | Mg1 (0, 0, 0) · Mg2 (0.3459, 0, 0.089) · Mg3 (0.430, 0, 0.652) · Si1 (0.0565, 0, 0.649) · Si2 (0.1885, 0, 0.224) · Si3 (0.2171, 0, 0.617) |

`tools/crystal-structures/make_beta_double_prime.py` writes the CIF into
`References/` (gitignored), and **asserts** that expanding the six sites under
C2/m gives Mg₁₀Si₁₂ = 2 × Mg₅Si₆ = 22 atoms — the cell content the paper states.
A misread coordinate or the wrong axis setting fails that assertion, which is
the check worth having, because sources disagree on the axis setting: some
publish a = 15.16, b = 6.74, c = 4.05 with γ = 105.3° instead.

**Not Materials Project mp-31404** (same phase, CC BY 4.0) — it is DFT-relaxed,
and relaxed volumes run a few percent high, roughly 1 % on d-spacings. That is a
systematic error in exactly the quantity this method matches on. The
Crystallography Open Database has **no** Mg₅Si₆ entry (checked).

**The orientation relationship comes free from the same paper:** β″ is coherent
along its needle direction — its **b-axis — with a ⟨100⟩ Al direction**, and
b = 0.405 nm *is* Al's lattice parameter. That is the prior knowledge the vector
matching method leans on.

Then: phase map → connected components → count ÷ calibrated area.

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
2. ~~A β″ CIF~~ — **resolved 2026-09-11.** Generated from Andersen et al. 1998,
   verified against the published cell content. No decision needed.
3. **Zenodo download** — no longer a licence question (CC BY 4.0, checked), only
   a disk one: preprocessed `datasetA` is ~7.4 GB against a machine sitting at
   9 GB free with an 8 GB gate floor. The ground truth itself is 37 kB.
   Blocks step 3.
