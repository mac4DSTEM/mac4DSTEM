# Roadmap — superseded sections (moved 2026-09-23)

Verbatim sections moved out of `ROADMAP.md` when it was brought current for
HEAD after the v4.0.0 release (2026-09-23). Each is superseded by the cited
evidence; nothing here is live.

## "Next planned sequence — registered 2026-09-19" (superseded: items 1 and 2 both done)

Superseded by `docs/status.md` § Handoff and `docs/releasing.md` § Releases
— v3.1.0 shipped as part of v4.0.0 (2026-09-23, `d9fd32e`) and the
Materials Project importer's S4a/S4b/S5 landed 2026-09-21 (first live
fetch still pending). Original text:

1. **Release v3.1.0:** the three acceptance cubes are restored; run `all` and the archive rehearsal before the credentialed cut. Full-cube Friedel bar/ETA remains an on-screen check, not a gate. No feature slips in.
2. **Materials Project importer:** build the pre-registered, user-initiated importer with offline provenance; settle its UX choices before UI code.
3. **Orientation coverage:** prepare monoclinic 2/m first if the owner confirms it; it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts and phase validation:** diagnose R–Q; decide T1 and Parallax experiments; use the paper truth set before detector or learned-model work.

## "Learned disk candidates — pre-registration" (superseded: shipped in v3.0.0, 2026-09-11)

Superseded by `docs/releasing.md` § Releases (v3.0.0 row: "the learned disk
detector, the flat/file probe kernel"). Original text:

A second `DetectorClass` beside the classical one: a Core ML U-Net paints a
disk-centre heatmap on the Neural Engine, and the existing
correlation/centroid refinement measures each candidate to sub-pixel;
opt-in, off by default. **Verdict (step 3): passed 2026-09-08** — on the
frozen hand-labelled test set the net finds the same real disks with far
fewer inventions (256 px: 0.667 / 0.840 against the classical 0.487 / 0.485).
Full pre-registration:
[`docs/archive/v3/learned-detector-preregistration-2026-09-07.md`](../v3/learned-detector-preregistration-2026-09-07.md).

## "Settings window, Xcode-style sidebar" (superseded: landed and driven)

Superseded by `docs/status.md` § Handoff ("Unverified on screen": the
Settings scene and mp-id sheet were owner-driven 2026-09-21) and by
`docs/releasing.md`. Original text:

**Settings window, Xcode-style sidebar** (owner, 2026-09-21) — grows the
scene the Materials Project key opened. Sections: *General* (what Open
Dataset does by default, sidecar location, keep the Mac awake during long
runs, clear recents); *Appearance* (theme System / Light / Dark, default
colormap for maps and for diffraction, log or linear intensity by default,
scale bar, inspector density); *Analysis* — machine knobs only: streaming
memory budget, engine preference, whether the learned detector is offered;
*Materials Project* (key, last fetch); *Advanced* (log verbosity, reveal
the log, reset). **Never a threshold, radius or floor** — those are
properties of a dataset and live in the session (ADR 029). State owner:
one `AppPreferences` over `UserDefaults`, injectable for tests; the
scene is a `NavigationSplitView` (allowed), never a split view. **Landed
2026-09-21** (`900fe7b`), unverified on screen.

## "Bottom area as a second workspace, Xcode-style" (superseded: closed 2026-09-22 night)

Superseded by `docs/status.md` § Handoff ("Window design residuals":
closed 2026-09-22 night, ADR 008/035–037) and `docs/open-items.md`, which
carries the live residuals (the toolbar's leading jump, inspector-kit
gaps, the parked panel-blank lead). Original text:

**Bottom area as a second workspace, Xcode-style** (owner, 2026-09-21,
revised 2026-09-22) — the infobar is the centre column's fixed-height
divider and full-width drag handle, moving from its bottom to its top;
Output / Run / Lineage never change its position. The 2026-09-21
implementation (ADR 034) was driven and rejected. The decided anatomy is
`docs/window-design.md` §1 and §6: full-height collapsible side panels,
room actions in a centre-only header that flexes with them, then the
Prepare reference room. Phase 1 has no recorded owner acceptance. The
lineage graph and copy/search/filter follow later.

## The 2026-09-23 sequence, superseded 2026-09-28 (moved verbatim from ROADMAP.md)

### Next planned sequence — registered 2026-09-23

The 2026-09-19 sequence's first two items are both done: v3.1.0 shipped as
part of v4.0.0 (2026-09-23) and the Materials Project importer landed
2026-09-21 (superseded text: `docs/archive/v4/roadmap-history.md`). Current
order, from `docs/status.md` § Handoff and the 2026-09-23 overnight records:

1. **Owner decisions and one Gate D first:** the known-variants guard shipped on 2026-09-23
   (ADR 038). Still owed: the R–Q displayed sign convention (`docs/open-items.md`); the Al
   lattice constant `DEVIATION` (4.0495 vs 4.04 Å, a `kMax` knife edge); a macOS 27 CI runner;
   the object-level pass bar (T4 draft). Gate D next: the owner's real Al-Mg-Si cube, where the
   matrix almost never wins (`archive/v4/almgsi-drive-2026-09-23.md`).
2. **Materials Project S6:** the live fetch works (owner, 2026-09-23); owed are
   the pre-registered comparisons — Al/θ′/T1 cells vs the paper's CIFs, a
   phase map through them within the S1 band, mp-1185307 refused.
3. **Orientation coverage:** monoclinic 2/m first, once the owner confirms
   it — it unlocks β″ and is a separate Gate D/B feature.
4. **Scientific debts:** the parallax default bin schedule (diagnosed,
   fix owed), the cross-phase completeness guard (candidate built, parked),
   T1's remaining detection-limited recall — each its own Gate D, in the
   order `docs/status.md` § Handoff names.


## Moved from ROADMAP.md at the 2026-09-28 closeout (finished items)

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


## The 2026-09-28 morning sequence (tracks A–D), superseded the same evening

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
2. **One method in the app (ADR 044):** vector matching stays; Thronsen's four methods are references in
   `tools/`, scored on inputs we choose (A3a on stride 3 on this Mac, A3 on the full dataset). Her ANN is the one
   challenger: it replaces vector matching only if it beats it under T4 on truth, through track C's
   label → train route. NMF and template-matched phase mapping are not ported.
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



## Retired 2026-09-30 — the 2026-09-28 evening sequence, verbatim

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

## Session-queue lines ticked through 2026-09-30 (moved at that closeout)

- [x] **S1 Close** (2026-09-30, `45d1228`): board 7 lanes, open-items 22 entries (see step 1 above).
- [x] **S2 Workspaces** (2026-09-30, `d8cb7d2`): ADR 046's six, driven at 915 and 1470 pt.
- [x] **S3 Prepare** (2026-09-30, `15d2b6c`, `9fe9440`): number entry in any region (Gate D + refuter); Friedel speed
  (Core `-O` in Debug). Open: re-drive the ETA's falling shape.
- [x] **S4 Phases & precipitates** (2026-09-30): Q prerequisite; the tie order (the probe's Dictionary; the app ranking made
  total). Carried: busy status line at narrow widths (Frozen Shell), the Al-Mg-Si recipe preset (owner's run first).
- [x] **S5 Sessions & sidecars** (2026-09-30, `1fc9f8f`): attribute guard, owned cancel token, reopen; residuals in open-items.
- [x] **S7–S9 Gate D** (2026-09-30, `c217038`): D025, D023, D019 fixed with refuters.
- [x] **A. Verify and finish** (2026-09-30): the unverified rows driven (S5 reopen last; it found a defect); S10 A and
  B refuted (T4 ships as a quantity); S11 flat in the app; S6 both halves; number fields commit on Return, and before
  any run (`PendingEdits`).
- [x] **B. The owner's sitting, taken under delegation** (2026-09-30): ADR 047 (lineage), 048 (training on MPSGraph,
  the C3 flow, T4 as a quantity, hardware waits) — overrule on sight.
- [x] **D. Lineage graph (ADR 047)** (2026-09-30): L1 record v2 (Gate B, amended), L2/L3 the graph in the Lineage pane,
  L4 Rewind to Here (`34af213`), `lineage_step` on phase maps, objects and groups with stale marking by the active path
  and the export edge to its own run (`c8cf592`, Fable supervisor, driven). Residuals in open-items.
- [x] **S17 Lean sweep** (2026-09-30 night, `c403125`): the stale open-items entries retired; diffraction groups' two-pass path kept or deleted by profile.
- [x] **S12 Stale marks II** (`b8b4544`, driven): zone-axis stale check (phase, tolerance), objects re-run as a run, "Computed this session".
- [x] **S13 CIF trust** (`f59e65f`): short symmetry-op lists refused; a symmetry-only second block no longer merges.
- [x] **S19 Regression net** (`f73be56`): positions not counts; empty globs fail; every check broken first.
- [x] **S22 Accessibility** (`53440b3`): probe, retire what holds, label what does not.
- [x] **S16 Virtual-detector tiled loops** (`e19b32c`, flat): measured; fixed only if not flat.
- [x] **S18 Promote / replay / load tail** (`64015f0`, driven): the superseded-load tail, promote position, restore shape check, provenance.
- [x] **S15 R–Q sign residuals** (`19f5b07`, label-only): pre-2026-09-28 exports refused or labelled, never silently flipped.
- [x] **S23 Origin validity overlay** (`08f457a`, driven): excluded positions greyed (new surface, driven).
- [x] **S14 · S20 · S21 (YELLOW)** (`1c3da28`, `a29359b`, `7d5f0a8`): measured; only S21 proposes a patch (owner).
- [x] **S14-D Gate D on the origin refine step** (2026-09-30): mechanism confirmed (the refine walks along the ring: bullseye_sim
  3.87 px → 0.02 px at window k = 2); bar not met (the demo fixture moves 1.70 px) — no patch; a window-dependence check proposed (owner).
- [x] **Polish from the drives** (2026-09-30): 13 items across three rooms, supervised and driven (drives 3–4); left: open-items S4.

### Ticked 2026-09-30 evening (new Mac)
- [x] **New Mac bring-up** (2026-09-30, `9026863`, `62c8eda`, closeout): baseline unit 1302 / 1 / 4, scientific 51 harnesses
  exit 0, package-test exit 0; the M5 training crash fixed; limits re-measured (`archive/v4/newmac-gateD-2026-09-30/`).

### Ticked 2026-09-30 night (residency), and the sequence ADR 049 replaced
- [x] **Residency returns, measured (2026-09-30):** measured, knee not clean, `.automatic` stays dropped (ADR 013 stands).
  Resident is 20–70 × faster on repeated passes, slower on a single one; record `archive/v4/residency-characterisation-2026-09-30/`.

Verbatim from `ROADMAP.md` until 2026-09-30 night:

### Next planned sequence — clear the board, then consolidate and polish (2026-09-30)

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
