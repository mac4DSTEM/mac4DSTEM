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

## Next planned sequence — registered 2026-09-28

Three tracks, in dependency order. **Truth comes first**, because both of the others are judged
against it. Every step is registered before it runs. Gate D applies where a number moves, and an
independent refuter reviews every verdict. Tracks B and C share one rule: a port or a trained model is
scored against its reference's own outputs on the same input before it is called equivalent. Three
steps open with a design session with the owner, each once its input exists: B2's port order (after
A3), C3's shape and Core ML vs Core AI (after C2), and C5's mock, which also settles B4. The
2026-09-23 sequence is in `docs/archive/v4/roadmap-history.md`.

### A — Ground truth, kept and reproduced (the foundation)

**Where each step runs.** A remote session runs on Linux: no Xcode, Metal, Core ML or Neural Engine,
and no `References/` data (gitignored, and on 2026-09-23 the cloud proxy refused Zenodo). So it can do
docs and code reading only. Everything that builds, runs the app or touches the data needs the Mac.

1. **A truth ledger** (*remote-capable, docs only*): one row per feature, giving its truth, the
   reference numbers we reproduced, its pass bar and its status. Phase mapping has one: Thronsen A, their errors reproduced to the
   digit, the T4 bar. Disk detection, strain and ACOM do not yet have real-data truth.
2. **Truth artefacts are committed, never gitignored** (*this Mac, the owner present to label*). The owner's 306 hand labels were lost that way
   (`open-items.md`). Re-label with the in-app Training labels rows, and commit the result. The export exists
   (`exportForFineTuning`), but its old home `tools/disk-detector/labels/` is still gitignored
   (`.gitignore:44`): A2 drops that line first. Commit the
   stride-3 Thronsen truth (CC BY 4.0, with attribution) beside it.
3. **Run the Thronsen code locally (ADR 042)** (*the stronger Mac*, or a Linux box with ≥ 32 GB and
   Zenodo access. Full dataset A is about 7.4 GB, too close to the 8 GB Mac: see the 2026-09-24 kernel
   panic. Reading and planning the ports can be remote). First reproduce their four published maps from their own
   code on dataset A; that proves the environment. Then run their methods on inputs we choose:
   stride 3, dataset B, the owner's Al-Mg-Si cube. That turns "agreement" into a real reference
   wherever the published maps don't reach.

### B — Precipitate analysis

Everything in B builds or runs the app's Swift/Metal code on local data: **this Mac**. B3 needs the stronger Mac.

1. **Close the one failing T4 metric,** θ′ edge-on speckle (7 against 0–5). Gate D, diagnosis first:
   the 7 are 1–2 px objects next to other phases. Every scored run uses the adopted T4 bar, with
   edge-on flips in the null.
2. **Port Thronsen's methods where it makes sense (ADR 042),** each scored against their own output
   (A3) before it is called equivalent:
   - vector analysis, closest to the app's matcher;
   - NMF on Accelerate;
   - their ANN as a reference model, with inference through Core ML or Core AI on the Neural Engine,
     and retraining through track C.
3. **The microprobe Al-Mg-Si re-acquisition** on the stronger Mac: calibrate it from its own lattice,
   then score it with agreement metrics (there is no truth there).
4. **Where precipitate analysis lives** is the owner's call, after track C settles what the AI
   workspace becomes. No UI moves before a mock the owner has accepted (the frozen shell, ADR 035).

### C — The Neural Engine and on-device training (owner, 2026-09-28: "soon")

C1–C4 are **Mac only** (MLX, Metal, Core ML, the Neural Engine). The research sizes C2 at batch 8 on this M3. The C5 mock can be drawn remotely; the decisions are the owner's.

The goal: **a user labels a dataset by hand, trains on this Mac, checks the model against labels held
out from training, and works from there.** Inference runs on the Neural Engine, and training runs
where Apple allows it (see C2). The first model is the learned disk detector.
1. **Labels as a product.** The existing labelling rows write labels into the session sidecar, with
   provenance. They export as a truth file, and fixtures commit them (A2).
2. **A measured framework spike, ≤ 1 day** (`archive/v4/ondevice-training-research-2026-09-28.md`).
   Only **MLX Swift** or MPSGraph can train this net in-app. Core ML's updatable models cannot
   backprop through a U-Net's concatenated skips, Create ML has no heatmap task, and Core AI is
   inference-only. **No public API trains on the Neural Engine.** The route back to it:
   - mirror the shipped BN-free graph in MLX;
   - fine-tune it;
   - inject the weights into the shipped Core ML spec through
     `MLModelAsset(specification:blobMapping:)`;
   - check placement with `MLComputePlan`.

   The spike's four pass criteria (a round trip ≤ 1e-2, the loss falling within ≤ 2 GB, the convs
   placed on the Neural Engine, the evaluation equal to `evaluate.py`'s) and its kill condition are in
   the record. **Ran 2026-09-28 and failed as registered** (`archive/v4/c2-mlx-spike-2026-09-28.md`); the
   heatmap bars are replaced by detection on held-out labels (ADR 043). MLX stays out of the `DSTEMCore` package: SwiftPM cannot build its shaders. This also
   re-decides Core ML against Core AI (ADR 014).
3. **A training loop in Core.** It runs off the main thread, is cancellable, fits in a memory budget
   measured on the 8 GB Mac, and makes deterministic splits. Evaluation uses the record's rule
   (recall/precision, a 2 px match, the eligible frame). Every trained model carries versioned
   provenance: its data, labels, seed and code.
4. **Neural Engine inference of the trained model,** with parity checked against the training
   framework's own output (the learned detector's existing fixture pattern).
5. **The AI workspace, redesigned around label → train → evaluate → use.** The owner's mock and
   decisions come first, then one room built and driven before any other.

### D — Carried

A second dataset with truth before the 0.15 % floor (ADR 041) is re-judged; R–Q residuals
(`open-items.md`); drive parallax and ptychography on the stronger Mac; the 28 GB DM4 parity run;
the cross-phase completeness guard; the 119-defect triage.

## How a v3 feature is done

Each feature is pre-registered the way the train's steps were (plan §9–§11 of
the archived v2.5 plan are the models): what it touches and which owner holds
its state, the tests written before, the decisions owed to the owner. Built on
the packages and sessions, one Gate B campaign at a time, `/pickup` with the
feature named.
