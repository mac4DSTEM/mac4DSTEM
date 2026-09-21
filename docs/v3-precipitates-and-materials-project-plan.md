# Next release — precipitate classification + Materials Project: plan and session board

Registered 2026-09-21 (owner brief, in chat). The next release is **not** the
calibration-only v3.1.0 cut: it ships (A) precipitate phase classification
from Bragg vectors, checked against Thronsen et al.'s published ground truth,
and (B) the Materials Project (MP) importer as the default phase source.
Number decided at the cut. Rules: `CLAUDE.md`; the method sources below are
verified from code and data, not from earlier prompts.

## 1. What was found (2026-09-21)

- **Reference** (`References/SPED-phase-mapping-main`, pyxem 0.14.2): the
  paper's vector analysis is *not* an orientation search. Al peaks are
  stripped first (nearest peak to a hand-picked Al pattern, 8 px); ≤ 1
  surviving spot → Al; otherwise every surviving spot is matched to its
  nearest reference spot in **five fixed references** (T1 at two in-plane
  rotations, θ′ edge-on at two, θ′ face-on at one, all from the stated
  orientation relationship), score = Σ distance ÷ unique reference spots hit,
  argmin wins, score > 0.07 Å⁻¹ → not indexed. Labels 0 Al, 1 θ′ edge-on,
  2 θ′ face-on, 3 T1, 4 not indexed. Metric: mismatched positions ÷ all.
  Methods land at 0.96–1.75 % (vector analysis 1.54 %).
- **Ours** (`Core/Crystal/PhaseVectorMatching.swift`): a library search
  (zone axes × in-plane sweep, OR-constrained for θ′, free for T1) with a
  pair radius (0.02 Å⁻¹), matched floors (3, or 2 with a Friedel pair), a
  chance-match guard and a 0.015 Å⁻¹ cliff. **4.21 %** (1230 / 29 241) on the
  stride-3 truth; residual T1 → not indexed 617, Al → not indexed 354,
  θ′ edge-on → T1 52. Decision 026's stopping rule (> 3 % after the three
  pre-registered levers → revisit the pre-registration, not the knobs) is
  hit: this plan is that revisit.
- **Data**: `References/thronsen-datasetA/datasetA_stride3.h5` (171 × 171 ×
  128 × 128) with the app's own Bragg vectors in its sidecar; truth
  `truth_stride3.json`: Al 21 494, θ′ edge-on 417, θ′ face-on 970, T1 6 358,
  disagreement 2.
- **Built, unwired**: class map → objects bridge
  (`PrecipitateSegmentation.classObjects`) and its Session owner.
- **MP API** (openapi fetched 2026-09-21): `GET /materials/summary/?material_ids=mp-N&_fields=…`,
  header `X-API-KEY`; `structure.lattice{a,b,c,alpha,beta,gamma}`,
  `sites[{species[{element,occu}],abc}]`, `symmetry{symbol,number,point_group}`.
  The app has no networking, no Keychain, no Settings scene, and no
  `network.client` entitlement (all checked).

## 2. Feature A — precipitate classification by known variants

**Pre-registration.** Add a second per-position rule to the existing
matcher, `ClassificationRule.knownVariants` (the paper's), beside today's
`.search`. Same library, same matrix removal; then: survivors ≤ 1 → matrix;
score every library entry as Σ (nearest-reference distance over *all*
survivors) ÷ unique references hit — no pair radius, no matched floor, no
chance guard; argmin over entries; score above `residualCutoffInvAngstrom`
(paper 0.07) → not indexed. Each departure from the notebook (library
entries instead of five hand-built references; Å⁻¹ matrix tolerance instead
of 8 px) gets an inline `DEVIATION` note. Material-general: the variants come
from the phase list's orientation relationships, nothing Al-specific.

**Gate D.** Diagnosis: the 971 not-indexed residuals fail our floors/guards,
not the cliff (`archive/v3/step3-2026-09-16.md` measured 98 % "nothing
cleared the guards"); the paper's rule has no such floors and labels them by
argmin. Refuting observation: if survivors at those positions are mostly 0–1,
the rule cannot help (they become matrix, not T1) — measured this session by
`phase-map-probe --residual-detail` before any code. **Predicted outcome**:
`--rule known-variants` on the same peaks and library lands ≤ 3 %
mislabelled (decision 026's bar); the band 0.96–1.75 % is the target, not a
tie condition, because our peaks are correlation-detected, not LoG.
Thresholds (0.07 Å⁻¹, survivors ≤ 1) are the paper's values on the paper's
dataset — shipped as settings, distribution printed by the probe, never
retuned on the truth. Ship gate: ≤ 3 % with the confusion table recorded
under `docs/archive/v3/`, else the rule ships as an experimental option
badged unvalidated and the record says why.

**Then**: derive T1's stated relationship ((0001)T1 ∥ (111)Al, [1‑10]Al ∥
[10‑10]T1) into the OR form so T1 stops being a free sweep; wire the class
map to `classObjects` for per-class fraction, object count and areal
density; the `validation:"none"` badge comes off only when the gate above
passes on this dataset with truth.

## 3. Feature B — Materials Project importer, the default phase source

Pre-registered in `v3-materials-project-preregistration.md`; the owner's
2026-09-21 brief settles its open decisions: **D1** a native Settings scene
(⌘,) with the API key in Keychain; **D2** re-derive the family with
`CIFImport.classifyFamily`, MP's `symmetry` is a cross-check and provenance;
**D3** a new source case `materials_project` with `materials_project_id`
and fetch date in provenance, structure embedded in the sidecar so recipes
reproduce offline; **D4** v1 is "paste an mp-id, fetch" — no search, no
dropdown. The built-in preset list leaves the pickers; `CrystalModelLibrary`
stays only as a resolver for replay records and tests (older sidecars name
`al_fcc` etc.). Phase sources become exactly two: **Materials Project…** and
**Import CIF…**.

**Identity check (owner requirement).** A fetched material must match the
phase the user asked for by *formula and space group*, not formula alone:
the import sheet carries the expected formula and space-group number
(typed, or prefilled from the slot being replaced); a mismatch is shown and
Import is disabled — e.g. mp-1185307 is LiAl₂Cu in Fm‑3m (225) and T1 is
Al₂CuLi in P6/mmm (191). `CrystalModel` gains an optional
`spaceGroupNumber` (from `_symmetry_Int_Tables_number` or MP) to carry it.

**Gate.** Unit tests first: decode fixtures (cubic, hexagonal, low-symmetry,
malformed), `crystalModel(from:)` reuses the CIF classifier by identity,
the mismatch refusal, Keychain round-trip, replay of an MP-sourced phase
offline. Live fetch is manual and opt-in, never gated. No Gate D: no
scientific number moves. Fixtures hand-built from the schema until the
owner's key allows a real capture (recorded as such).

## 4. Session board

| # | Session | Scope | Gate | Model | State |
|---|---|---|---|---|---|
| S0 | 2026-09-21 | Surveys, this plan, `--residual-detail` measurement, resume note | none (measurement) | Sonnet surveys, Fable plan | **running** |
| S1 | A · rule | `ClassificationRule.knownVariants` in Core, synthetic fixture broken first, probe `--rule`, measured vs truth, archive record | D + B (Sonnet refuter) | Sonnet writes, Fable gates | next |
| S2 | A · T1 OR | T1 relationship derived into the OR form; re-measure; unit + `phase-vector-matching` harness | D + B | Sonnet, Fable gates | after S1 |
| S3 | A · wire | Classifier picker in Phase mapping settings; class map → objects, per-class fraction/density in Results; export; badge logic | unit + inventory; **on-screen owed** | Sonnet | after S1; surface waits for the drive row or the owner's word |
| S4a | B · core | Entitlement (landed `f500a31`); `Core/Crystal/MaterialsProjectImport.swift` (decode, request, `crystalModel(from:)` via the CIF classifier, `PhaseExpectation` check, `spaceGroupNumber`, `materials_project` source); Keychain store; fixtures; tests first | unit + core | Sonnet | done `6324314` |
| S4b | B · cell | MP serves the relaxed cell, usually **primitive** (unverified here: no key on this machine). Conventional-cell standardisation by centring matrices with a metric + volume guard, refusing what it cannot standardise ("import a conventional CIF"); fixtures built from known conventional cells | D + B | Sonnet, Fable gates | done 2026-09-21 (8 fixtures, 3 mutations red→green) |
| S5 | B · UI | Settings scene; MP sheet with expected-structure check and visible refusal; pickers reduced to two sources; provenance in sidecar | unit + inventory; on-screen owed | Sonnet | done 2026-09-21, unverified on screen |
| S6 | B · data | Owner's key: fetch Al, θ′, T1 from MP, compare cells to the paper's CIFs, phase-map through them within the S1 band; mp-1185307 refused for real | manual, recorded | Fable + owner | after S5 |
| S7 | release | CHANGELOG, status, open-items, board; `all`; rehearsal; cut | `all` exit 0 | Fable | last |
| S8 | later | ANN on the Neural Engine (the paper's simulated-training route) — pre-registration only | — | — | not scheduled |

Owner decisions owed: the release number; whether S3/S5 surface may land
before the "Unverified on screen" row is emptied; the T1 recall lever stays
parked until S1 reports.
