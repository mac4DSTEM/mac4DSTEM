# Vector-matching phase mapping — the plan, 2026-09-11

> **Where it stands, 2026-09-12.** Steps **0, 1, 2, 4 and 5 are done**; step 3
> is **deferred on disk, not abandoned**, and everything the app produces is
> labelled unvalidated until it runs. The record of what landed, what two
> pre-registered predictions got wrong, and what the Al-Mg-Si cube actually
> said is [`archive/v3/phase-mapping-2026-09-12.md`](archive/v3/phase-mapping-2026-09-12.md).

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

### 1 — Reference vectors from a CIF  *(Core, no UI)*  — **DONE 2026-09-12**
`Core/Crystal/PhaseReferenceLibrary.swift`. Gated by
`tools/phase-vector-matching` against arithmetic: fcc |g| = 2/a and 2√2/a to
1e-9, and the monoclinic reciprocal metric to 2.2e-16. **What the plan did not
anticipate:** a visibility cut is not optional. A library holding every
kinematically allowed reflection gives every experimental vector a near
neighbour for every phase; `maximumVectorsPerEntry` is the control and
`chanceMatchFraction` is the number that makes the trade visible.

Reciprocal lattice → rotate to a zone axis → keep points in a thin slab about
z = 0 → apply the matrix's in-plane rotation. `Crystal.reflections(kMax:)`
already handles arbitrary cells and `OrientationPlan.project` already does the
zone-axis projection, so this is composition, not new mathematics. Their slab
thicknesses (0.030 / 0.300 Å⁻¹) are phase-dependent; ours get derived.
**Gate:** unit tests against hand-computed vectors for a cubic case where the
answer is known by arithmetic.

### 2 — The matcher  *(Core; Gate D and Gate B both apply)*  — **DONE 2026-09-12**
`Core/Crystal/PhaseVectorMatching.swift`. **One deviation from the score below,
and it was the second thing tried:** the "mean |u − v| over unique reference
vectors" needs a completeness requirement, and a minimum matched FRACTION
cannot be it — a capped library can never explain every spot a pattern shows.
An entry must instead beat its own chance-match expectation by 5×.

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

### 3 — Validate against their published ground truth  ← **DEFERRED 2026-09-12, on disk**
Not abandoned and not skipped: their `datasetA` is ~7.4 GB against a machine
at 5.7 GB free, and the owner has deleted everything he is willing to delete.
The decision and its condition are in `decisions.md` (2026-09-12): the rest
lands **labelled unvalidated** in four places, and no density or phase fraction
leaves the app as a quantitative claim until this passes. `ground_truth.hspy`
is 37 kB and its HyperSpy schema (`/Experiments/__unnamed__/data`) is already
among `H5Reader`'s candidate paths, so the only obstacle is size.

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

### 4 — Apply to Al-Mg-Si  *(the actual goal)*  — **RUN 2026-09-12, and it refused**
`tools/phase-map-probe` (diagnostic). Three results, and the refusal is the
useful one:
- **β″ IS resolvable** on this 4×-binned detector — the pre-registered
  prediction that a* = 1.50 px would make it unresolvable was WRONG, because
  C2/m's h + k even extinguishes odd h in the k = 0 zone and the closest kept
  pair is 2a* = 2.99 px. The extinction checks the structure.
- **The specimen is on ⟨110⟩Al**, not ⟨100⟩ — all five sampled ⟨110⟩
  equivalents tie at 39.0 %, as cubic symmetry requires.
- **So the [010]β″ library was the wrong one**, and the run said so: 99.0 %
  "not indexed". With the beam on ⟨110⟩Al no β″ variant is viewed down its
  needle axis.
The honest limit alongside: only 39 % of detected vectors are explained by the
best Al orientation, which is a statement about the peak set — a synthetic
kernel on a binned detector — not about the matcher.


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

### 5 — UI  — **DONE 2026-09-12**, ahead of 3 and labelled for it
The plan said to defer this until 3 passed. It was brought forward with 3
deferred instead, on the owner's decision, because a method you cannot look at
is a method you cannot judge — and the labelling is what makes that safe.
Two choices in it carry more than presentation: **the phase list IS the
legend** (one row per phase, carrying the swatch the map is drawn with and the
fraction it claimed, so there is no second legend to fall out of step), and
**every position can be taken apart** (`Evidence` names the phase, the matched
count, the mean distance in Å⁻¹, the matrix removals and the runner-up, for the
position under the cursor). "Not indexed" is hatched rather than coloured, so
it can never be read as one more phase.

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

1. ~~**`.identity` symmetry**~~ — **resolved 2026-09-11**, accepted; step 0
   landed at `ee2221c`.
2. ~~A β″ CIF~~ — **resolved 2026-09-11.** Generated from Andersen et al. 1998,
   verified against the published cell content. No decision needed.
3. **Zenodo download** — **deferred 2026-09-12**, a disk question only
   (CC BY 4.0, checked). Reopens when there is an external drive or ~8 GB free.
   Blocks step 3 and nothing else.
