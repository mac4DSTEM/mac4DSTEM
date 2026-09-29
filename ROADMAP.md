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

The v3.1 calibration foundation's pre-registration and landing notes are in `docs/archive/v4/roadmap-history.md`.

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
tests; `docs/v3-features.md#materials-project`) — shipped in v4.0.0;
the owner live-tested a fetch 2026-09-23 (it worked); S6's comparisons owed. Point-group coverage beyond
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

## Next planned sequence — clear the board, then consolidate and polish (2026-09-30)

The owner, 2026-09-30: "clear the board and then start to consolidate and polish for some sessions." The overnight
session of 2026-09-29 cleared its own list, not the board: most lanes are features or decisions only the owner can take.
Clearing is three moves, in this order.

1. **Closed 2026-09-30 (S1):** board 18 → 7 lanes (done and parked lanes in its ledger), `open-items.md` 46 → 22
   entries grouped by polish room; the standing process notes are one line each in `docs/architecture.md`.
2. **Decided 2026-09-30 (ADR 046):** training and the lineage graph (a real graph with rewind) kept; volumetric
   density and β″ orientation maps parked; A3 retired. Originally: **keep, defer or retire** each feature lane — disks claimed per phase, β″
   orientation maps, the lineage graph, volumetric density, on-device training, the full Thronsen reproduction (A3).
   Deferred lanes move to "Later" below and off the board; retired ones are deleted from code in the same session
   (lean-app directive), e.g. the unwired image `segment` path. Hardware-gated work (parallax/ptychography drive, the
   28 GB `--parity` run) waits for the stronger Mac and leaves the board as one "waits on hardware" row.
3. **Polish (GREEN, one room per session, each drive-verified).** First the workspaces, ADR 046's accepted picture:
   Prepare · Imaging (+ diffraction groups) · Bragg Disks (detect, labels, training) · Crystal Maps (strain,
   orientation, phases and precipitates) · Reconstruction (DPC, parallax, ptychography) · Results. Then one room per
   session (S3–S6 below; their items are `docs/open-items.md` § Polish). 4. **Science, one Gate D per session** (S7–S11).

**Session queue** — each `/pickup` takes the first unchecked line; its closeout ticks it here and moves the handoff.
- [x] **S1 Close** (2026-09-30, `45d1228`): board 7 lanes, open-items 22 entries (see step 1 above).
- [x] **S2 Workspaces** (2026-09-30, `d8cb7d2`): ADR 046's six, driven at 915 and 1470 pt.
- [x] **S3 Prepare** (2026-09-30, `15d2b6c`, `9fe9440`): number entry in any region (Gate D + refuter); Friedel speed
  (Core `-O` in Debug). Open: re-drive the ETA's falling shape.
- [x] **S4 Phases & precipitates** (2026-09-30): Q prerequisite; the tie order (the probe's Dictionary; the app ranking made
  total). Carried: busy status line at narrow widths (Frozen Shell), the Al-Mg-Si recipe preset (owner's run first).
- [x] **S5 Sessions & sidecars** (2026-09-30, `1fc9f8f`): attribute guard, owned cancel token, reopen; residuals in open-items.
- [x] **S7–S9 Gate D** (2026-09-30, `c217038`): D025, D023, D019 fixed with refuters.

**Clearing the board (owner, 2026-09-30: "make a plan to clear everything").** Sessions drive the app themselves; the
owner is asked only for decisions, batched into ONE sitting (phase B). Each line lands as commits with its gate.
- [ ] **A. Verify and finish (sessions, now).** Drive every "Unverified on screen" row on a scratch build; S10 T4's last
  metric (Gate D, pre-registered first); S11 the learned detector's tiled memory (Gate D); S6's non-shell half.
- [ ] **B. One owner sitting, prepared as artifacts** — each a recommendation he accepts or overrules: (1) the Frozen
  Shell picture: the sidebar-clip fix, the busy status line, the view-state owners, the Info-tab badge; (2) the
  lineage session format (ADR draft: step ids, input edges, sidecar v2) and a graph-view mock; (3) the training flow
  (C3 design: where labels live, split, the non-inferiority screen, model swap); (4) hardware: is the stronger Mac here.
- [ ] **C. On-device training, the C track (ADR 043).** C2.5 a training step ≤ 2 GB on this Mac (batch/activation
  memory, measured) and criterion 4 through the app's Swift path; C3 pre-register; C4 build label → train on the GPU
  (MLX) → write the weights into the Core ML package (the on-disk route, 1.00× speed) → run on the Neural Engine →
  judge on held-out labels (non-inferiority, both numbers shown) → swap or keep; C5 drive on real data. The ANE does
  inference only — no public API trains on it.
- [ ] **D. Lineage graph (ADR from B2).** L1 session record v2 (step ids, input edges; old sidecars still read); L2 a
  lineage list in Results; L3 the graph view to the accepted mock; L4 real rewind — a node restores its parameter
  state through the replay machinery. Each driven.
- [ ] **E. The remaining lanes.** Precipitates: T4 passes, or the metric ships as a quantity (S10's verdict); the
  disks-claimed-per-phase view (mock in B). Al-Mg-Si: the recipe preset once the owner's microprobe run confirms it.
  Materials Project: its comparison run. Hardware: the 28 GB parity run and the parallax/ptychography drive.
- A lane leaves the board when its line here is ticked; the board is cleared when A–E are.

## How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
