# mac4DSTEM roadmap

Imported 2026-09-03 from the "mac4DSTEM v3 Themes" artifact of 2026-08-28
(seven parallel surveys of the pinned py4DSTEM source against `Core/`: 166
findings, 45 high-value gaps, 77 absent, 54 partial, 7 absent by recorded
decision; the ranking is a recommendation, sizes are rough). The first v3
feature to land bumped the version to v3.0.0, released 2026-09-11; v4.0.0
(2026-09-23) carries the v3.1 calibration foundation and a rebuilt interface
on the macOS 27 floor (`docs/releasing.md` § Releases). What is live now is
`docs/status.md`; this file is the forward plan.

## Decided 2026-08-28

Recorded in full at `docs/decisions/031-v3-sequencing.md`.

1. **v3 is a sequence, not a bet.** Order comes from two scarce resources —
   one Gate B campaign in flight, the owner's driving time — plus dependencies.
2. **Grain segmentation and multi-phase ship together** — segment the
   grains, then identify each one's phase.
3. **The notebook exports the recipe as py4DSTEM code, no comparison** — a
   translation, with an inline `DEVIATION` note at each step.
4. **Materials Project as an importer that embeds** the fetched structure in
   the session sidecar with its provenance, so recipes reproduce offline.
5. **Precipitates enter v3 as a design session, implementation unscheduled**
   — a per-object result, its export/sidecar life, and what density refuses without a denominator.
6. **A run layer (`AnalysisRunner` with an injected host)** is the recorded
   next consolidation item, unscheduled; run functions stay on `AppState`.

## Parity themes

Ranked by value to a working microscopist.

| # | Theme | Absent today | Size · depends on |
|---|---|---|---|
| 1 | **Calibration foundation** — everything else stands on it | **Landed 2026-09-17 as v3.1, shipped in v4.0.0** (`docs/v3-features.md#calibration-v31`): vacuum probe from a separate scan, beamstop-tolerant origin (`get_origin_friedel` + beamstop mask), origin validity mask (count on screen; the spatial overlay is still owed). The CoM beam centre in `probeSize` is parked (Gate D: marginal). The origin-method picker and the Friedel demo have been driven by the owner; the spatial overlay stays owed. | done |
| 2 | **Amorphous and nanocrystalline** — a modality the app lacks | polar / polar-elliptical transform (gates the rest); radial profile I(q); pair distribution function (scattering factors already ported); radial variance / fluctuation microscopy | large · polar transform first |
| 3 | **Strain where disk detection fails** — the peak-finding path finds no basis on three of four training datasets (`docs/archive/qc-run-findings-2026-08.md` §9.2/§10.3) | whole-pattern fitting; user-supplied reference lattice (absolute strain); strain from the ACOM solution | medium–large · — |
| 4 | **From maps to the numbers a paper reports** | grain segmentation (size distribution, boundary misorientation, twin fraction); multi-phase identification (which phase is where); full point-group coverage | medium · point-group coverage first |
| 5 | **Interoperability** | read a native py4DSTEM EMD (probe, Bragg vectors, calibration); the notebook export | medium · pinned py4DSTEM env exists |
| 6 | **Detector realism** | per-position detector shift (the origin map exists); arbitrary detector masks (the GPU path takes a weight image); hot-pixel filtering; ARINA reader, MIB packed modes | small each · — |
| 7 | **Phase-contrast depth** | direct ptychography (SSB / OBF / WDD); mixed-state; probe-position correction | large · — |

**Calibration foundation (theme 1) — pre-registration, v3.1.** Sequenced
least-risk first (Gate B capacity is one campaign at a time). The **origin
validity mask leads** (owner, 2026-09-17): surface the per-position `kept` mask
the robust origin fit already computes and discards, completing the 2026-08-28
admit-with-fraction decision from a scalar to a spatial map — disclosure only,
no shipped number moves, a unit gate. **Landed 2026-09-17:** item 1 (mask + D4
count + step-3 measured); the CoM centre in `probeSize` **diagnosed and parked**
(marginal, two-sided); and **`get_origin_friedel`'s Core algorithm ported**
(`FriedelOrigin.swift`, beamstop-tolerant, opt-in/additive) with a gated parity
harness at ~1e-6 px against py4DSTEM, `get_beamstop_mask` ported (pixel-identical to
scipy on the real Au_ref beamstop cube) and **wired as an origin-method picker**; and
the **vacuum probe from a separate scan** (a "Vacuum Scan…" probe source). **All four
Calibration-foundation items landed 2026-09-17** (item 2 parked as marginal); the UI
additions are unverified on screen. Full registration:
[`docs/v3-features.md#calibration-v31`](docs/v3-features.md#calibration-v31),
decision [`docs/decisions/033-v3.1-origin-validity-mask.md`](docs/decisions/033-v3.1-origin-validity-mask.md).

**Theme 4's point-group coverage is also a Materials Project dependency, not
only a grain-segmentation one** (found 2026-09-19). Today's
`ACOMCrystalSymmetry` implements exactly two point groups by hand in Swift —
cubic and hexagonal — so a live Materials Project connection will hit the
"can identify, can't orientation-map" wall far more often than today's
curated CIF imports do; py4DSTEM is no more general by default (its own
built-in plotting is cubic-only too — full coverage there needs the
external `orix` library, which Swift has no equivalent of). **The Materials
Project importer landed 2026-09-21** (decode/standardise/refuse a cell,
classify via the CIF importer's own function, Keychain key, mp-id sheet, 39
tests; `docs/v3-features.md#materials-project`) — its first live fetch is
still pending (owner: retry mp-134, then S6). Point-group coverage beyond
cubic and hexagonal remains unclaimed.

## Beyond py4DSTEM — the differentiators

All requested by the owner; all out of v2 by the 2026-08-18 decision ("each
is its own product").

- **Needle-shaped precipitate pipeline** (2026-08-06, re-requested
  2026-08-26) — classifying each scan position by its full diffraction
  pattern, superseded from real-space segmentation 2026-09-11
  (`docs/v3-features.md#precipitate-classification`,
  `docs/decisions/019-precipitates-by-classification.md`). Ships unvalidated
  (`validation:"none"`, `docs/status.md` § Handoff). **2026-09-23 overnight
  Gate D:** an Al → precipitate false-call guard (`specific ≥ 1`) measured
  423/29241 = 1.45 % against the baseline 1.81 %, independently refuted in
  part — the headline number stands, but it is not parameter-free (it rides
  a (count, pair-radius) ridge) and the object-table evidence it cited is
  spurious-singleton removal, not repaired detection
  (`docs/archive/v3/precipitate-overnight-2026-09-23.md`). Owner: pre-register
  the guard as a two-parameter rule and measure it on a second dataset before
  it ships as a flag (`docs/status.md` § Handoff).
- **EDX correlation** (2026-08-26) — a data-model change before a feature: a
  second signal with its own reader and units, registered onto the scan grid
  with the transform recorded. Unclaimed.
- **Live acquisition · copilot** — named, nothing designed. Unclaimed.
- **Settings window, Xcode-style sidebar** (owner, 2026-09-21) — the
  Materials Project key, general/appearance/analysis/advanced sections, one
  `AppPreferences` state owner. **Landed 2026-09-21** (`900fe7b`) and driven
  by the owner the same night. Full design:
  [`docs/archive/v4/roadmap-history.md`](docs/archive/v4/roadmap-history.md).
- **Bottom area as a second workspace, Xcode-style** (owner, 2026-09-21,
  revised 2026-09-22) — **closed 2026-09-22 night**: the macOS 27 rebuild on
  Apple's inspector guidance, driven and accepted by the owner on a real
  cube (ADR 008, 035–037, `docs/status.md` § Handoff). Live residuals: the
  toolbar's leading jump at a long file name, inspector-kit gaps, a parked
  panel-blank lead (`docs/open-items.md`). Earlier, rejected design:
  [`docs/archive/v4/roadmap-history.md`](docs/archive/v4/roadmap-history.md).
- **Lineage graph with real rewind** (owner, 2026-09-21) — every derived
  product shows its inputs as a graph, and clicking a node rewinds the
  parameter state, not a text history. Nothing exists today beyond the
  linear `SessionReplayRecord` and per-product provenance; a record with
  step ids and input edges (a sidecar wire-format decision, owed) comes
  first, a lineage list in Results second, the graph view only after the
  drive row is empty. Unclaimed, unscheduled — follows the window design
  above.
- **Learned disk candidates** (owner, 2026-09-05; Core ML on the Neural
  Engine, 2026-09-07) — the first ML feature, **shipped in v3.0.0**
  (2026-09-11, `docs/releasing.md` § Releases). Pre-registration and the
  passing step-3 verdict:
  [`docs/archive/v4/roadmap-history.md`](docs/archive/v4/roadmap-history.md).

## Leave alone; where the app is ahead

Not chased: py4DSTEM's visualization layer, `utils/` helpers for their own
sake, `.automatic` residency (needs a second machine). Ahead of py4DSTEM and
part of the product story: the load-specification and promote workflow,
provenance that survives export and reopen, refusals that name what failed,
the session sidecar as a sharing unit.

## Next planned sequence — registered 2026-09-23

The 2026-09-19 sequence's first two items are both done: v3.1.0 shipped as
part of v4.0.0 (2026-09-23) and the Materials Project importer landed
2026-09-21 (superseded text: `docs/archive/v4/roadmap-history.md`). Current
order, from `docs/status.md` § Handoff and the 2026-09-23 overnight records:

1. **Four owner decisions from last night's Gate D runs, before anything
   below them moves:** the known-variants precipitate guard (pre-register as
   a two-parameter count/pair-radius rule, measure on a second dataset —
   `docs/archive/v3/precipitate-overnight-2026-09-23.md`); the R–Q displayed
   sign convention (app θ = −py4DSTEM's on real data; decide which is
   displayed, then Gate D the sign conversion — `docs/open-items.md`); the Al
   lattice constant DEVIATION mechanism (4.0495 Å pure Al vs 4.04 Å the
   paper's CIF, a `kMax` knife edge, not an excitation-slab effect); and a
   macOS 27 CI runner image (`macos-26` can no longer build the app at all).
2. **Materials Project live fetch (S6):** retry mp-134, then build S6 on a
   real fetch.
3. **Orientation coverage:** monoclinic 2/m first, once the owner confirms
   it — it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts:** the parallax default bin schedule (diagnosed,
   fix owed), the cross-phase completeness guard (candidate built, parked),
   T1's remaining detection-limited recall — each its own Gate D, in the
   order `docs/status.md` § Handoff names.

## How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
