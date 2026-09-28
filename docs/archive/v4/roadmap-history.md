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

