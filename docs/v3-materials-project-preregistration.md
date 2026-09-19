# Materials Project importer + point-group coverage — pre-registration

Registered 2026-09-19. The feature this file is checked against; nothing is
merged yet. Model: [`v3.1-calibration-preregistration.md`](v3.1-calibration-preregistration.md)
and `ROADMAP.md` "How a v3 feature is done". Origin: ROADMAP.md's
"Theme 4's point-group coverage is also a Materials Project dependency" note
(2026-09-19), written after a live check of both the pinned py4DSTEM source
and the Materials Project API.

## The theme, sequenced

Two related items, sequenced least-risk-first within one session, same
principle as the calibration foundation (`v3.1-calibration-preregistration.md`).

1. **Materials Project importer** — leads. Mostly plumbing (networking +
   JSON decode), not science; the one Gate-D-relevant piece (which symmetry
   family a fetched structure gets) reuses the CIF importer's already-tested
   classifier verbatim. Useful on day one even before item 2 lands — identify
   now, orientation-map once the phase's point group is covered.
2. **Point-group coverage** — a **scoping and design pass this session**,
   not a from-scratch implementation of all 32 crystallographic point
   groups. Output: which 1–2 groups earn a hand-written symmetry type next,
   their math sourced and cited, and their own Gate D pre-registration —
   the actual port + tests are their own follow-on session, matching how the
   calibration doc deferred its largest item ("its own pre-registration when
   reached").

Point-group coverage is **not** blocked on the importer, and the importer is
**not** blocked on point-group coverage — either can land first. They are
pre-registered together because the importer is what makes the gap concrete
(item 1's search UI is the thing that will show the owner, in practice,
which point groups real materials actually need).

## Item 1 — Materials Project importer

**What it is.** A picker that searches the Materials Project database by
formula/element/chemical system and imports the chosen structure into a
`CrystalModel`, embedded in the session sidecar with its provenance — the
2026-08-28 decision of record (`decisions/031-v3-sequencing.md` item 4).
Additive: a new source beside the existing built-in presets, the custom
editor, and CIF import; changes no existing path.

**API facts, verified live 2026-09-19** (fetched `https://api.materialsproject.org/openapi.json`
directly, not from memory):
- Plain REST/JSON, no Python required — MP's own docs say so explicitly
  ("possible to use the API with many libraries in many languages... JavaScript,
  MATLAB, Mathematica"). A free API key, generated on registration, sent as a
  request header; no special approval for normal interactive use.
- **One call gets everything needed.** `GET /materials/summary/` (filterable
  by `material_ids`, `formula`, `chemsys`, `elements`, with `_fields` to keep
  the response small) returns a `SummaryDoc` carrying `material_id`,
  `formula_pretty`, `structure` (a `TypedStructureDict`: `lattice` — `a, b, c,
  alpha, beta, gamma, volume, matrix`, all plain numbers — and `sites`, each
  an element + fractional `abc` + occupancy), **and** `symmetry`
  (`SymmetryData`: `crystal_system`, `symbol`, `number`, `point_group`).
- No CIF text round-trip needed. This JSON decodes directly into the shapes
  `Crystal`/`AtomSite` already use (`Core/Crystal/Crystal.swift:37-40`); MP's
  own computed point group can cross-check (not replace, see D2) the existing
  cell-metric classifier.

**What it touches, and who owns the state.**
- **A new networking layer** — the app has never made an outbound network
  call: `mac4DSTEM.entitlements` has `com.apple.security.app-sandbox` true
  and no `com.apple.security.network.client` (checked directly, not assumed).
  This entitlement addition is the first thing to land, on its own, so a
  build break here is isolated from the feature code.
- **API key storage** — Keychain, not `UserDefaults`. There is no existing
  Settings/Preferences window in the app (checked: every `*Settings.swift`
  file is a per-workspace analysis panel, not an app-level preferences
  scene) — this is genuinely new UI surface, not a slot-in.
- **The JSON → `CrystalModel` conversion** — a new `Core/Crystal/` file
  (parallel to `CIFImport.swift`), `package static func crystalModel(from
  summary: MaterialsProjectSummary) throws -> CrystalModel`, reusing
  `CrystalModel.validationIssues` and `ACOMCrystalSymmetry` classification
  unchanged (`CrystalModel.swift:94-115`, `:195-220`). Owner: this file, on
  the `CIFImport.swift` precedent — a pure function, no `AppState` dependency.
  `AppState` only gets the button/sheet that calls it and the result's UI
  presentation, on the `CIFImport` picker's existing shape.
- **Provenance** — a new `CrystalModelSource` case (today: `builtIn`,
  `custom`, `imported`, `CrystalModel.swift:5-9`) or a provenance field on
  `.imported` (D3) naming the mp-id, the fetch date, and the required
  DFT-relaxation warning already on record (`decisions/031-v3-sequencing.md`
  item 4: "~1 % off measured").

**Off by default / risk boundary.** The network call is exclusively
user-initiated (search button, import button) — nothing calls out
automatically, nothing changes for the offline CIF/custom/built-in paths.
The sandboxed app's blast radius from the new entitlement is exactly "can
open outbound HTTPS," which the OS enforces regardless of app bugs.

**Gate.** The networking layer and JSON decoding are ordinary unit-testable
code (mock the `URLSession`, fixture JSON captured from a real response —
e.g. mp-149 silicon, cubic; a known hexagonal entry; a known low-symmetry
entry) — no Gate D. The symmetry-classification step **is** Gate D-relevant
in principle, but it reuses `CIFImport`'s already Gate-D-covered classifier
rather than writing new science, so the honest bar is: prove by test that
the reuse is exact (same function, not a re-implementation), not a fresh
Gate D campaign. A live network smoke test (real API key, real request)
stays manual/opt-in, never in the gated suite — matching how other
network-shaped, non-reproducible things are kept out of `run-tests.sh`.

**Tests, to write before code.**
- Decode a captured real `SummaryDoc` JSON fixture into the new Swift
  `Codable` types for a cubic entry, a hexagonal entry, and a low-symmetry
  entry (e.g. the known monoclinic β″ case's family, if MP carries an
  equivalent) — pins the wire shape independent of network flakiness.
- The JSON → `CrystalModel` path produces a model whose
  `validationIssues`/`supportsOrientationMapping` match hand-computation for
  each fixture — proves the reuse, not a parallel implementation.
- A malformed/incomplete response (missing `structure`, null `symmetry`)
  refuses with a named reason, never a crash or a silently-wrong model.
- Keychain wrapper: round-trips a key, and a missing key produces the
  "no API key set" refusal the search UI shows, not a network error.
- Break-first on at least the classification-reuse test (mutate to a
  hand-rolled classifier) and the malformed-response refusal.

**Decisions owed to the owner.**
- **D1 — API key entry UX.** New Settings surface (first one in the app) vs.
  a lighter inline prompt the first time the picker opens. *No default
  proposed — this is the app's first Preferences-shaped surface, worth the
  owner's call on precedent.*
- **D2 — trust MP's `symmetry.point_group` or re-derive.** *Proposed
  default: re-derive with the existing `classifyFamily` cell-metric
  check, treat MP's field as a cross-check/log-only value.* Consistent with
  CIF import (which never trusted a file's stated symmetry either,
  `CIFImport.swift:777-780`), and defends against the field being null
  (schema marks it optional) or stale.
- **D3 — provenance shape.** A new `CrystalModelSource` case vs. a
  provenance field on `.imported`. *Proposed default: provenance field
  (`crystal_model_source` stays `"imported"`, a new
  `materials_project_id`/`fetch_date` key carries the rest) — smaller diff,
  and "imported" is already true.*
- **D4 — search UI scope for v1.** Full search-and-browse vs. "paste an
  mp-id, fetch it" as a smaller first cut with search added later. *No
  default proposed — a real UI/UX call on how this should feel, not an
  engineering one.*

## Item 2 — Point-group coverage (design pass, this session)

**What it is.** Today `ACOMCrystalSymmetry` hand-implements exactly two of
the 32 crystallographic point groups — cubic m-3m and hexagonal 6/mmm
(`Core/Analysis/OrientationResult.swift:487-543`) — each its own fundamental-
zone sampling, disorientation reduction, and IPF-color formula. Anything
else identifies but is refused for orientation mapping
(`CrystalModel.orientationMappingIssue`, `CrystalModel.swift:214-220`).
This item is **not** "implement all 32" — it is: pick the next 1–2 that earn
their place, and pre-register them properly before any math is written.

**Why not all 32, and why not lean on a library.** py4DSTEM itself only
reaches full point-group generality by handing off to `orix` (structure via
`pymatgen`'s `SpacegroupAnalyzer`, IPF color via `orix.plot.IPFColorKeyTSL`)
— its own built-in plotting is honestly no more general than mac4DSTEM's:
`plot_orientation_maps`'s docstring says "Currently, no symmetry reduction.
Therefore the x and y orientations are going to be correct only for the
\[001]\[011]\[111] orientation triangle" (cubic only). Swift has no `orix`
equivalent to lean on — each additional point group here means hand-deriving
its fundamental zone and reduction, the same work `CubicOrientationSymmetry`/
`HexagonalOrientationSymmetry` already did. That is real, slow, Gate-D-grade
work per group; doing it 30 times speculatively is not proportionate to
what any dataset in hand actually needs.

**Candidate list, for the owner to rank, not a decision yet.**
- **Monoclinic 2/m** — already blocking a known, real case: the β″
  precipitate phase in the Al-Mg-Si dataset identifies today but cannot be
  orientation-mapped (`open-items.md`, "The β″ zone axis for ⟨110⟩Al data is
  not chosen"; `CIFImport.swift:818-824`'s comment names this exact phase as
  the reason non-cubic/hexagonal CIFs were admitted for identification at
  all). Highest concrete value today.
- **Tetragonal 4/mmm** and **trigonal -3m** — the two next-most-common
  point groups across real inorganic materials generally (informed by
  py4DSTEM's own `orientation_ranges` table, which special-cases both with
  their own fundamental-zone geometry, `crystal_ACOM.py:2755-2792`); the
  ones most likely to come up once the Materials Project importer makes
  "search for anything" real.
- **Orthorhombic mmm** — third-ranked on the same reasoning; no known
  dataset need yet.

**This is Gate D, not placement.** An orientation-reduction or IPF-color
formula is exactly the class of change `[[review-the-diagnosis-not-the-code]]`
warns about: it can pass every test written for it and still be wrong,
including at symmetric test constants that hide a sign or axis error. Each
group needs: a diagnosis citing the point-group's actual symmetry operators
and fundamental zone (py4DSTEM's `orientation_ranges` entry and/or a
standard crystallography reference, ported with a `DEVIATION` note on any
divergence — the repo's port-fidelity rule applies here same as anywhere
else in `Core/`), a predicted outcome, a fixture with a planted orientation,
and an independent refuter before the code — the same protocol as
`CubicOrientationSymmetry`/`HexagonalOrientationSymmetry` themselves, whose
own tests are on record as needing that rigor.

**What "figure out" means concretely, for next session.**
1. Owner ranks the candidate list (or names a different one — the β″ case
   is evidence, not a mandate).
2. Diagnosis for the chosen group: its symmetry operators, its fundamental
   zone in the same Cartesian-direction convention `ACOMCrystalSymmetry`
   already uses, and the disorientation formula — written down and reviewed
   *before* any Swift is.
3. Pre-registration of that one group as its own item (this doc's item 4
   equivalent), on the calibration doc's precedent of deferring the largest
   piece to its own file when reached.
4. Only then: `CubicOrientationSymmetry`-shaped implementation, break-first
   tests, an independent refuter, Gate D sign-off.

Do **not** treat "does the app support point group X" as answered until a
group has gone through this — `.identity`'s honest refusal
(`orientationMappingIssue`) is correct behaviour for every group not yet
covered, not a bug to silently patch over.

**Decisions owed to the owner.**
- **D5 — which point group first.** **Owner preference, 2026-09-19: prepare
  monoclinic 2/m first** — the β″ case is measured and blocked today. Confirm
  that choice at pickup before any symmetry math; tetragonal/trigonal remain
  the broader-reach follow-ons once MP import volume makes demand measurable.
- **D6 — how much coverage is "done" for v3.** Three point groups (adding
  one to today's two) may be enough to badge as a real capability, or this
  may want to become an ongoing backlog item picked up opportunistically.
  *No default proposed.*

## Non-negotiables carried from CLAUDE.md

Break every new test before trusting it. A change to what the app draws is
unverified on screen until the owner has seen it. Port deviations get an
inline `DEVIATION` note. Docs land in the same commit as the code they
describe. The model that writes a Gate D change does not approve it alone —
an independent refuter reads the diagnosis, not the diff, before item 2's
code, same as item 1's classifier-reuse claim should be checked by someone
other than whoever wrote it.
