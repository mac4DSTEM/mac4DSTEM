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

## Next planned sequence — revised with the owner, 2026-09-28 evening

The morning's tracks A–C (archived verbatim in `docs/archive/v4/roadmap-history.md`) ran the same day: A2 truth
committed, A3a reproduced Thronsen's vector analysis on this Mac (99.99 %), C2 proved the training route (and failed its
registered bars), B1 diagnosed the edge-on speckle. What that taught, in the owner's words distilled: **our vector
matching is powerful; keep the app simple, robust, pure macOS, with an intuitive UI; rethink the approach whenever a
better one appears, and use the Neural Engine where it earns its place.**

**Principles.** One method per job in the app (ADR 044). Every change is judged on Thronsen's truth (T4, per-position
error and every class's speckle together) until the owner's own data reach that standard. The workspace layout is
settled; rooms move only on a concrete plan the owner accepts.

**Order.**
1. ~~**The 915-pt launch crash**~~: fixed 2026-09-28 (sidebar max 270, owner's pick).
2. **Precipitate analysis, polished.** The owner's recipe reproduces the map in the app; finish what it lacks: the
   per-phase slab field (landed 2026-09-28 night), then a polishing cycle over the whole precipitate path
   (settings, legend, objects, table, export) — the table→map highlight and the "Any rotation" prompt landed 2026-09-29 night. Thickness → volumetric density is the last missing step: registered 2026-09-28 with a typed thickness (PACBED deferred).
3. **The owner's own Al-Mg-Si high-resolution scans, subsampled.** First cube done 2026-09-29 (stride 3, full 256² detector, bit-identical; `archive/v4/ssd-subsample-2026-09-29.md`), calibrated from its own lattice the same day (every prediction held); next: analyse it — the in-app Detect All Disks no longer grows memory per tile (overnight A1), the match tolerance is under measurement (D1). The 28 GB cubes are sampled in real space (every
   n-th position, full diffraction resolution kept), as was done for Thronsen's dataset: more reciprocal-space
   resolution for disk detection, fewer real-space pixels, precipitates still visible. On the stronger Mac, or here with
   a streaming job proven on a small file first (never read a file larger than RAM, 2026-09-24).
4. **Where precipitate analysis lives.** The AI Analysis workspace will be folded into the others later, on a concrete
   plan; image segmentation stays for now. Owner's call, not a design exercise.
5. **On-device training, in the Disks section** (track C). The loop the owner wants: detect disks (classical or the
   learned detector on the Neural Engine), mark or refine positions by clicking, train on the GPU with MLX (C2: the
   route works; memory ≤ 2 GB first), write the model back so it runs on the Neural Engine, detect again. Judged by
   detection on held-out marks (ADR 043) and by what it does to the segmentation.

**Reduced or dropped.** The full reproduction of Thronsen's maps "to the digit" (A3) is not needed now: A3a proved the
environment. Ports from the paper only where they teach the app something (ADR 044); her ANN stays the one challenger.
The microprobe re-acquisition (B3) waits for new measurements; the existing scans come first.

**Already there.** The learned disk detector has run on the Neural Engine since v3.0.0 (Detector: Learned, offered
once *Offer learned detector* is on in Settings). What is missing is training it on the user's own marks.

## How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
