# v3.x feature registrations and plans of record

One entry per live v3 feature: status, who owns the state, what is
pre-registered against work not yet built, decisions still owed to the
owner, and where the evidence lives. History already recorded verbatim under
`docs/archive/v3/` or `docs/decisions/` is linked here, not repeated; a
number is quoted only with the dated log or archive file that measured it.
No product here is called validated while it self-reports `validation:
"none"` — precipitate/phase-mapping outputs stay badged unvalidated in every
release note until they pass their stated ship gate.

Consolidates, 2026-09-21: `v3-materials-project-preregistration.md`,
`v3-precipitate-classification.md`, `v3-precipitates-and-materials-project-plan.md`,
`v3-vector-matching-plan.md`, `v3.1-calibration-preregistration.md` — each
written before its code, per `ROADMAP.md` §6 ("How a v3 feature is done").
Originals are superseded by this file; their content lives on here and in
the archive/decision links each section cites.

Non-negotiables carried from `CLAUDE.md`, governing every section below:
break every new test before trusting it; a change to what the app draws is
unverified on screen until the owner has seen it; port deviations from
py4DSTEM get an inline `DEVIATION` note; this repo does not set
`ResidencyAdmission.measuredWorkingSetFraction`; docs land in the same
commit as the code they describe.

- [Calibration foundation (v3.1)](#calibration-v31)
- [Vector matching (phase mapping)](#vector-matching)
- [Precipitate classification](#precipitate-classification)
- [Materials Project](#materials-project)
- [Precipitates + Materials Project — plan of record](#precipitates-mp-plan)

<a id="calibration-v31"></a>

## Calibration foundation (v3.1)

**Status.** Landed 2026-09-17. Sequenced least-risk-first (`ROADMAP.md`
theme 1, Gate B capacity is one campaign at a time): item 1 (origin validity
mask — Core disclosure + on-screen count), item 3 (`get_origin_friedel` +
beamstop mask, wired as an origin-method picker) and item 4 (vacuum probe
from a separate scan) all landed 2026-09-17. Item 2 (recover the discarded
CoM beam centre in `probeSize`) was Gate D **diagnosed and parked** the same
day — marginal and two-sided, not built. The v3.1.0 release cut itself is
still owed.

**Scope and state owner.** `OriginMaps` (`Core/Data/Calibration.swift`) owns
the new `originValidity: [Bool]?`, populated by the two `OriginCalibration`
trimmed-fit constructors (`tiledRun`, `run`) from `TrimmedFit.kept`.
`Core/Analysis/FriedelOrigin.swift` (a new, opt-in origin method) and
`Core/Analysis/BeamstopMask.swift` (ported from py4DSTEM's
`DataCube.get_beamstop_mask`, one `DEVIATION` note for wraparound subpixel
indexing) are additive Core; `OriginMethod.friedel` sits beside
`.centreOfMass`. `OriginCalibration.vacuumProbeKernel` +
`AppState.generateVacuumProbeKernel(fromScan:)` own the vacuum-probe path,
source `.vacuumScan`. All three landed items are additive/opt-in — no
existing origin path changed.

**What is pre-registered, still governing unbuilt work.**
- Item 2 stays parked, not abandoned: re-open only after measuring
  CoM-vs-fitted-mean origin on the resident cubes
  (`References/{demo-dataset,training_dataset}`) — a science change here is
  marginal and two-sided without that evidence, and it would add a branch to
  a currently clean derivation.
- D3 (sidecar/EMD persistence of `originValidity`) is deferred to the
  owner's wire-format decision (plan §8); a restored session's mask reads
  `nil` until then, and touching it means touching the parked
  `BraggVectorEMDWriter` split (high HDF5 risk).
- D4's spatial validity overlay (origin fit over the scan grid, excluded
  positions greyed via `DisplayedProduct.validityMask`) is a larger
  follow-on, not built — only the position count ("142 of 150 positions")
  landed.
- Item 3 follow-on decisions: where the origin-method choice lives in
  settings (not `AppState`); whether the Friedel origin feeds the same
  `OriginMaps` path or its own; the beamstop mask's threshold/distance
  defaults (py4DSTEM's 0.25 / 2 px) fixed or user-exposed. Gate D applies
  the moment the Friedel origin becomes one an analysis consumes — the
  parity harnesses are its Gate-B-grade validation until then.
- Origin-method picker and the "Vacuum Scan…" button/importer are
  **unverified on screen**.

**Decisions owed to the owner.** D1 (mask representation) and D2 (mask
semantics) ship at their proposed defaults — overrule on sight. D3 (whether
and when to persist the mask) and D4 (the on-screen overlay design) are
undecided, owner's call.

**Records.** `docs/decisions/033-v3.1-origin-validity-mask.md`;
`docs/archive/v3/status-handoff-2026-09-18.md` (full landed narrative:
Friedel/beamstop parity numbers, break-first mutations M1–M4/Mf1/Mf2/Mv1,
the step-3 trim-sweep table across four cubes).

<a id="vector-matching"></a>

## Vector matching (phase mapping)

**Status.** Partly landed. Steps 0, 1, 2, 4 and 5 done (2026-09-11/12).
Step 3 — validation against Thronsen et al.'s published ground truth
(Ultramicroscopy 255 (2024) 113861, CC BY 4.0) — ran on a stride-3
subsample and remains open: the sequence improved 26 % → 13.24 % → 6.64 %,
then **4.21 %** at a 0.1 % detection threshold, no default moved
(`docs/archive/v3/step3-2026-09-16.md`); the known-variants rule (see
[Precipitates + Materials Project — plan of record](#precipitates-mp-plan))
later reached **1.81 %**, still 0.06 points above their 0.96–1.75 % band.
Every phase output stays explicitly `validation:"none"`.

**Scope and state owner.** `Core/Crystal/PhaseReferenceLibrary.swift`
(reference vectors from a CIF, gated by `tools/phase-vector-matching`);
`Core/Crystal/PhaseVectorMatching.swift` (the matcher, UNVALIDATED per its
own file header); `Session/PhaseMappingProduct.swift` owns the phase list,
the two Core settings structs, the map and its run record — the only writer
is `AppState+PhaseMapping.swift`, views read `phaseMapping.…` directly, no
forwarding properties. UI: `UI/PhaseMappingSettings.swift`, badged
unvalidated until step 3 passes.

**What is pre-registered, still governing unbuilt work.**
- Licensing wall (checked 2026-09-11, still binding): the **paper** (CC BY
  4.0) gives the method and Table 2's structures, reusable with attribution;
  their **GitHub repo** gives nothing — no licence, no code, no CIF; their
  **Zenodo dataset** (CC BY 4.0) gives the 4D data, the ground truth, and
  their four published phase maps.
- Score rule: mean |u − v| over *unique* reference vectors, lowest wins; an
  entry must beat its own chance-match expectation by 5×; above threshold →
  "not indexed", never a forced label. Matrix removal happens in vector
  space first (fewer than two survivors after dropping matrix-close vectors
  means matrix).
- Next-session validation lane (registered 2026-09-19, still the live
  route): (1) reproduce the 4.21 % control before any new lever; (2) Gate D
  one residual at a time — matrix-by-exclusion, then T1/θ′ — a threshold,
  reference or detector change needs prediction, refuter, truth measurement
  and independent review; (3) `DiffractionEmbedding`/PCA stays an
  exploratory comparator and future precipitate-classification route, not a
  shortcut — the paper's ANN is a benchmark, never imported, retrained or
  called validated absent its own truth-set campaign.
- What this implementation inherits and has not fixed: zone-axis only;
  cannot separate phases overlapping along the beam (the argument for
  keeping `DiffractionEmbedding` rather than replacing it — NMF is the only
  one of the paper's four methods that can); confused by strain-shifted
  Bragg positions, which this app measures and so may do better on, a
  hypothesis not a plan.
- Any phase-label or default change follows Gate D, Gate B, and a new
  release decision — evidence may prepare alongside other work, the change
  itself may not land ahead of that.

**Decisions owed to the owner.** Whether a candidate may be indexed on one
or two characteristic reflections, and at what false-positive cost — opened
by step 3's failure, addressed in practice (not yet closed) by the
known-variants rule below.

**Records.** `docs/decisions/021-phase-mapping-decisions.md` (method
choice); `docs/archive/v3/step3-2026-09-16.md` (the 2026-09-15 decisions and
the full threshold record, 98.26 % → 26.4 % → 13.24 % → 8.75 % → 7.96 % →
6.64 %); `docs/archive/v3/phase-mapping-2026-09-12.md` (steps 1/2/4/5);
`docs/archive/v3/status-steps-2026-09-16.md` (orientation-relationship form
landed, measured 6.64 %); `docs/decisions/026-step3-thresholds-and-orientation-relationship.md`
(Friedel floor, reach, cliff, OR form, and the >3 %-after-three-levers
stopping rule the next plan revisits).

<a id="precipitate-classification"></a>

## Precipitate classification

**Status.** Registered 2026-09-11, owner-approved in chat; supersedes the
plan's original real-space segmentation route. The classification route
(via the known-variants rule) is now the live route for precipitate density
— see [Precipitates + Materials Project — plan of record](#precipitates-mp-plan)
— but has not itself passed its owner-adjudicated ship gate against the
image route, so it stays `validation:"none"`.

**Scope and state owner.** `Session/PrecipitateClassificationProduct.swift`
owns a published spatial class result; `AppState.precipitateClassification`
composes it with no forwarding properties. `Session/PhaseMapObjectsBridge.swift`
is the pure `PhaseMap → labels/roles` mapping `PrecipitateSegmentation.classObjects`
needs. The originally-registered full-diffraction-pattern classification
route (featurise → PCA/NMF → cluster → template-match) is **still unbuilt**
— today's wiring runs off the vector-matched phase map, a different producer
of the same owner, not a replacement. `Core/Analysis/Precipitates/` stays
named by outcome, not moved into an `AI/` folder.

**What is pre-registered, still governing unbuilt work.**
- Ship gate (unchanged since 2026-09-11): the classification route must beat
  the image route on the owner's adjudicated count — recall and precision, a
  tie passes — or it does not ship and the image route stands.
- No brightness, shape or ridge threshold in the classification route — an
  end-on needle classifies correctly because its *pattern* is
  precipitate-like even though its *image* is a dot. The old image route had
  **zero `DEVIATION` notes** because its segmentation abandoned skimage's
  convention outright — a parity harness was impossible for it, which the
  classification route fixes by construction.
- Density reported here is areal, a way-station, never the goal: must
  "report areal and say so," never be read as settling the volumetric
  question. Volumetric number density via PACBED-based foil-thickness
  estimation is designed (`docs/ai-ml/README.md` §5) and unbuilt — its own
  future pre-registration.
- Multi-dataset density (total count ÷ total area across cubes, never the
  mean of per-cube densities) is out of scope, named so it is not lost.
- Per-object storage is settled (a sidecar table plus CSV export); per-object
  **presentation** — almost certainly a length/orientation histogram plus a
  clickable labelled map, table as export only — is still undesigned.
- The parity harness (`tools/embedding-pca-parity`, `scientific` gate)
  checks PCA against py4DSTEM's own `Featurization.PCA` and
  `symmetricEigenTop` against `numpy.linalg.eigh` only — **not**
  featurisation (py4DSTEM has no binned-pattern representation), **not**
  class assignment (py4DSTEM clusters with `GaussianMixture`, never
  k-means), and **not** a real cube (sklearn's solver flips above 500 rows,
  so the fixture is capped at 400). This narrower scope is permanent, not a
  gap to close.

**Decisions owed to the owner.** Per-object presentation design; whether and
when to build multi-dataset and volumetric density.

**Records.** `docs/decisions/018-ai-pipeline-on-main.md` (PCA over NMF;
ridge filter parked, not retired); `docs/decisions/019-precipitates-by-classification.md`
(the route decision and ship gate); `docs/archive/v3/precipitate-baseline-2026-09-11.md`,
`docs/archive/v3/precipitate-handcount-2026-09-11.md` (the measured failures
that killed the image route); `docs/archive/v3/precipitates-real-space-route-2026-09-07.md`
(the superseded route, history); `docs/archive/v3/phase-discrimination-2026-09-11.md`
(per-position template matching measured and refuted); `docs/archive/v3/phase-map-objects-gateD-2026-09-21.md`
(the class-map → objects bridge, Gate D/B reviewed, deliberately unwired).

<a id="materials-project"></a>

## Materials Project

**Status.** Importer landed 2026-09-21 (session S4a/S4b/S5 of
[Precipitates + Materials Project — plan of record](#precipitates-mp-plan)):
entitlement, decode + primitive-cell standardisation, Keychain, a native
Settings scene, the mp-id import sheet, pickers reduced to two sources
(Materials Project… and Import CIF…). Point-group coverage — the second
item of this feature's original pre-registration — is **unbuilt**: a
scoping/design pass only, no symmetry math written.

**Scope and state owner.** `Core/Crystal/MaterialsProjectImport.swift` — a
new `Core/Crystal/` file parallel to `CIFImport.swift`, no `AppState`
dependency — decodes `GET /materials/summary/`, builds a `CrystalModel` via
`CIFImport.classifyFamily` reused verbatim (not re-implemented), checks a
`PhaseExpectation`, and carries `spaceGroupNumber` and provenance
(`materials_project` source, mp-id, fetch date). `Session/MaterialsProjectKeyStore.swift`
owns the API key in the Keychain, never `UserDefaults`. `CrystalModelLibrary`
stays only as a resolver for replay records and tests (older sidecars name
`al_fcc` etc.); the `mac4DSTEM.entitlements` network-client addition landed
first and in isolation, so a build break there stays separate from the
feature code.

**What is pre-registered, still governing unbuilt work.**
- Point-group coverage is explicitly **not** "implement all 32" — each
  additional point group needs its own hand-derived Gate D (symmetry
  operators, fundamental zone, disorientation formula sourced and cited,
  ported with a `DEVIATION` note on any divergence, a fixture with a planted
  orientation, an independent refuter) before any Swift is written — the
  same rigor `CubicOrientationSymmetry`/`HexagonalOrientationSymmetry`
  themselves were held to. `.identity`'s honest refusal is correct behaviour
  for every uncovered group, not a bug to silently patch.
- D5 — owner preference, 2026-09-19: prepare **monoclinic 2/m** first (the
  β″ case is measured and blocked today, `open-items.md`); tetragonal 4/mmm
  and trigonal -3m are the broader-reach follow-ons once Materials Project
  import volume makes demand measurable. Confirm at pickup before any
  symmetry math.
- D6 — how much point-group coverage counts as "done" for v3 is undecided:
  three groups (one more than today's two) may be enough to badge as a real
  capability, or this becomes an ongoing backlog item.
- Live network fetch stays manual/opt-in, never in the gated suite — matches
  how other network-shaped, non-reproducible things are kept out of
  `run-tests.sh`.
- Identity check (landed, owner requirement): a fetched material must match
  the phase the user asked for by **formula and space-group number**, not
  formula alone — a mismatch is shown and Import is disabled (e.g.
  mp-1185307 is LiAl₂Cu, Fm-3m 225, not T1's Al₂CuLi, P6/mmm 191).

**Decisions owed to the owner.** Which point group to prepare after
monoclinic 2/m; D6 (how much coverage is "done" for v3).

**Records.** `docs/decisions/031-v3-sequencing.md` item 4 (the 2026-08-28
sequencing decision this importer implements: embeds the fetched structure
with provenance, required DFT-relaxation warning, ~1 % off measured).

<a id="precipitates-mp-plan"></a>

## Precipitates + Materials Project — plan of record

**Status.** Registered 2026-09-21 (owner brief, in chat). Governs the
**next release** (not the calibration-only v3.1.0 cut): (A) precipitate
phase classification by known variants, checked against Thronsen et al.'s
published ground truth, and (B) the Materials Project importer as the
default phase source. Both largely landed 2026-09-21 per the session board
below; the release number and cut are owed.

**Scope and state owner.** Feature A extends
`Core/Crystal/PhaseVectorMatching.swift` with
`ClassificationRule.knownVariants` (Thronsen et al.'s own per-position rule)
beside today's `.search`, then wires the class map to `classObjects` via
`Session/PhaseMapObjectsBridge.swift` into
`Session/PrecipitateClassificationProduct.swift`. Feature B is the
Materials Project importer — state ownership as in
[Materials Project](#materials-project) above.

**What is pre-registered, still governing unbuilt work.**
- Feature A departs from the paper's notebook rule in two ways, each with
  its own inline `DEVIATION` note: library entries stand in for the paper's
  five hand-built references, and an Å⁻¹ matrix tolerance replaces their
  8 px image-space one. The rule is material-general: variants come from the
  phase list's own orientation relationships, nothing Al-specific.
- Feature A ship gate: ≤ 3 % mislabelled on the Thronsen truth (decision
  026's bar) with the confusion table recorded under `docs/archive/v3/`, or
  the rule ships only as an experimental option badged unvalidated, with the
  record saying why. **Outcome 2026-09-21:** refuted as predicted
  (18.11 %), explained (the T1 reference lacked {014}/{214} under a 5 %
  kinematic intensity floor), **2.64 %** at floor 0 (bar met, band not); the
  T1 orientation relationship in its OR form → 2.67 %; a per-phase
  excitation slab (θ′ at 0.3) → **1.81 %**, 0.06 above the 0.96–1.75 % band.
  Residual, owed: Al → precipitate 407 false calls (the rule carries no
  chance guard); the app's phase slots have no per-phase slab field yet
  (probe-only today); the search rule's floor default is unmeasured on any
  dataset but this one.
- The `validation:"none"` badge on phase mapping and precipitate
  classification comes off **only** when Feature A's ship gate passes on
  this dataset with truth — not before, regardless of how close 1.81 % sits
  to the band.
- Feature B's identity check and decisions D1–D4 are settled in
  [Materials Project](#materials-project) above; S6 (the owner's key fetches
  Al, θ′ and T1 from MP, compares cells to the paper's CIFs, phase-maps
  through them within the S1 band, and confirms mp-1185307 is refused for
  real) is the one step still owed, scheduled after S5.
- The session board below is the authoritative sequencing record for this
  plan; only S6 (manual, owner's key) and S7 (the release cut, gate `all`
  exit 0) remain open. S8 (an ANN on the Neural Engine, the paper's
  simulated-training route) is pre-registration-only, not scheduled.

| # | Session | Scope | Gate | State |
|---|---|---|---|---|
| S0 | Surveys, this plan, residual measurement | none (measurement) | done |
| S1 | `ClassificationRule.knownVariants` in Core, fixture, probe `--rule`, measured vs truth | D + B | done: 2.64 % at floor 0 — `known-variants-rule-2026-09-21.md` |
| S2 | T1 relationship derived into the OR form; re-measured | D + B | done: 2.67 %, edge-on→T1 295→45 — `t1-relationship-2026-09-21.md` |
| S3 | Classifier picker; class map → objects; per-class fraction/density; export; badge logic | unit + inventory; on-screen owed | done, unverified on screen |
| S4a | MP core: entitlement, decode, `crystalModel(from:)`, Keychain, fixtures | unit + core | done |
| S4b | MP conventional-cell standardisation from a primitive cell | D + B | done, 8 fixtures |
| S5 | MP Settings scene; import sheet with expected-structure check; pickers reduced to two sources | unit + inventory; on-screen owed | done, unverified on screen |
| S6 | Owner's key: fetch Al/θ′/T1, compare cells, phase-map within the S1 band | manual, recorded | after S5 |
| S7 | Release: CHANGELOG, status, open-items, board; `all`; cut | `all` exit 0 | last |
| S8 | ANN on the Neural Engine (pre-registration only) | — | not scheduled |

**Decisions owed to the owner.** The release number; whether S3/S5's surface
may land before the "Unverified on screen" row of `docs/status.md` is
emptied (`CLAUDE.md`'s 2026-09-18 rule: it may not); the T1 recall lever,
parked pending S1's outcome, now reported and still open.

**Records.** `docs/archive/v3/known-variants-rule-2026-09-21.md` (S1);
`docs/archive/v3/t1-relationship-2026-09-21.md` (S2);
`docs/archive/v3/theta-prime-slab-2026-09-21.md` (per-phase slab, 1.81 %);
`docs/archive/v3/phase-map-residual-detail-2026-09-21.md` (residual
detail); `docs/decisions/026-step3-thresholds-and-orientation-relationship.md`
(the >3 %-after-three-levers stopping rule this plan revisits).
