# Closed and trimmed open-items text — Slot 4⅞ closeout (2026-10-04)

Moved verbatim from `docs/open-items.md`; the live file keeps a one-to-four-line residual for each.

### The 2026-09-09 register, triaged 2026-09-29 — every reachable candidate fixed 2026-09-30; residuals below
All 156 clusters judged against `main` (`archive/2026-09-09-review/triage-2026-09-29.md`); D019/D023/D025 fixed with
refuters (`archive/v4/register-D019-D023-D025-gateD-2026-09-30.md`). D006 (multi-`data_` CIF refused, structure blocks
named), D021 (parallax stack mean in Double) and D079 (ptychography origin = `Calibration.referenceOrigin`) fixed (`archive/v4/register-D006-D021-D079-gateD-2026-09-30.md`), refuter
held (D079's drag symptom is by design; the gap was replay/lineage restore; a pre-fix record whose aperture differs from the
fit now reproduces a different ptycho result, intended). D098/D004 fixed (one dose scale per pattern; seam
margins close the unsearched bands; ≤ 256 px byte-identical; `archive/v4/learned-windows-D098-D004-gateD-2026-09-30.md`).
D020 was P1's IPF fix (`023a5b0`). D068 and D017 fixed (9f5d4eb, `archive/v4/register-D068-D017-2026-09-30.md`). Residuals: Clear
Calibration makes no calibration node (a run after Clear records the old nodes as inputs — needs a "cleared" lineage state;
an aperture-centre drag and Restore Fitted Origin record nodes since the 2026-09-30 night, and a map on the first fit stays
stale after Restore); a Q edit deletes the
ACOM map instead of marking it stale; D069 (an unresolved ACOM model compares no settings); a restored product is not
labelled as saved anywhere. (`occupiedPositions`: `archive/v4/gateD-occupied-aperture-drag-2026-09-30.md`.)

---

### Tiled GPU memory: classical and learned Detect All and the virtual-detector loops gated flat
Classical and learned `detectAll` are gated by `tools/tiled-detection-memory-test` (`archive/v4/s10-s11-gateD-2026-09-30.md`).
In the app (2026-09-30, scratch build, Thronsen A 171², 128²): learned Detect All, 29 241 positions in 1:17, footprint flat
1.63–1.67 GB (peak 1.72 GB), 955 MB after. `VirtualDetector`'s six streaming paths measured flat and gated by
`tools/virtual-detector-memory-test` (S16, 0–2 MB over 10 tiles; retained-buffer mutants 352 MB); on Thronsen A 778 MB stays
between passes as 662.7 MB "Malloc Large (empty)" = two 331 MB tiles (an observation, no mechanism; the ≈ 0.93 GB baseline
may be the same). Resident-cube paths unmeasured. D1: the shipped max(0.02 Å⁻¹, 1 px) tolerance fits all four datasets.

---

- Polish 2026-09-30 (driven, drives 3–4): the Matrix picker names β″ twins by zone axis; Show Objects / Match Distance swap to
  "Show Phase Map"; Evidence help names the selected position; a visible Re-measure; "Saved with the dataset" from a real
  session flag; carried-calibration refusals shown in Prepare; the annulus centre drags; units read Å⁻¹; the promote footer keeps
  the pattern readout; a fresh cube shows its virtual image; counts grouped. Slot 1 lane P (2026-09-30 night) took the rest of
  the drives' list (lineage order, legend counts, crop-warning axes, the configurator status, "px", the drag sentence) and the
  bin-2 aperture default (Gate D: the view-frame default was re-referenced as a source point; `archive/v4/v41-plan-2026-09-30.md`
  § Log). [Info › Provenance labels: landed `ceac82b1`.]

---

- Slot 1 P drive residuals (2026-09-30 night, shots in `archive/v4/slot1-p-drive-2026-09-30-shots/`): [the bottom area's sliver: a 140-pt floor since
  Slot 4⅞ lane F, owner Q6 a]; the "Positions used"
  percentage fallback (> 2 % excluded) was not reached on screen.

---

- **Slot 4½ residuals** (2026-10-02; the rest of `archive/v4/polish-drive-2026-10-01.md` fixed): [the β″ preset's CIF picker closed 2026-10-02: the RC drive
  opened and applied it — the earlier report does not reproduce]; [the SCAN inset moved into the
  diffraction pane, Slot 4⅞ lane R2 (owner Q3 a); its height follows the scan aspect (a 4:1 scan gives 472 pt); with no product shown
  only the arrow keys move the position]; a window that resized itself (unreproduced). Since Q7 a (lane F) Virtual detector
  has no toolbar verb: after another room cleared its image, Imaging shows "No Result Yet" until an aperture edit or a preset re-runs it.

---

**Sidecar access (2026-09-30 night, owner's drive):** on a Mac with no grant (every dataset after a migration or a rebuild that
lost the container's bookmarks) each session read "could not be read — HDF5 … errno 1"; the only remedy was Save As on the same
file. Fixed: "Allow Access…" under the sidebar warning and in the Dataset menu (an open panel at the sidecar, the grant
remembered, the dataset reopened), driven on a scratch build (40 labels restored). Since Slot 4⅞ lane S (2026-10-04) the warning names
the sandbox and Allow Access…, the raw line goes to the Log (unverified on screen: needs a Mac without the grant); a related-item
declaration was tried and refused (the sidecar's extension is the dataset's `.h5`).

---

- S18 (2026-09-30 night, driven): a load's tail resets only its own load; promote keeps the scan position (crop offset added);
  crop-shaped origin maps on a whole-file reopen are named ("Not carried into this view"); a schema-5 sidecar's view is
  "unrecorded" (adopted only at whole file). Residuals: a schema-5 sidecar's stored disks are refused even at whole file (v1.0.0
  disks no longer restore — owner); an uncancelled superseded tail still runs on (unreachable by click); (c) parallax/ptychography
  not in the replay record; (d) a user analysis mid-replay steals Cancel; (e) replay contracts in three places (the recording
  sites + `ProductWorkflow.currentReplaySignature`, `ReplayRecordFrameMap.role`, `ReplayPlanner.parse`) — a design change.

---

- **Coarse block seed lands on the wrong blob on noisy cubes** (Gate B refuter, §9): 28/169, 29/195, 2/169 of three cubes miss by
  >1 px vs a Gaussian-argmax seed. S14 (2026-09-30 night, `archive/v4/s14-*`): a box seed does not meet its bar; trimming does
  NOT hide the offset on Si_SiGe_exp, both bullseye cubes and Au_ref (0.5–2.8 px); on bullseye the refine step's iterated
  r + 1.5 window walks along the ring — confirmed by S14-D (`archive/v4/s14d-*`): bullseye_sim 3.87 → 0.02 px at
  k = 2, compact cubes ≤ 0.03 px, but the demo fixture moves 1.70 px; no fixed window ships (refuter HOLDS, held-out truth check 0.003 px). Done (lane Q, 2026-09-30 night):
  `tiledRun.windowSensitivityPixels` — median px between the caller's window and k 2.5 on a strided, byte-bounded sample: compact
  cubes ≤ 0.07 px, Particle_1 0.34, bullseye 3.8, Au_ref 5.3; 0.84 s on the gzip row-chunked demo cube (I/O). Not surfaced: the demo
  fixture reads 3.36 px in S14-D's table and was not re-measured — measure it before any display line. The demo fixture's origin is
  pinned by no harness.

---

- **Off-grid self-recovery** (S20, 2026-09-30 night): 37–43 of 200 fail at 1.4° (0/200 on-grid, worst 9.3°). Candidate F (exact
  azimuth + 4× shifts) sweep 430 → 24; closed 2026-09-30 night at true Q (lane Q, `archive/v4/slot1-q-record-2026-09-30.md`): grain C
  stays t2 (0.00°) under F at Q 0.012, so the S20 regression was the probe's 13.5 %-low Q, not F; F moves grain A 5.03 → 3.18° at
  kMax 1.2 and costs 3.8× on CPU — After v4.1. Grain B (6.50°, winner t84): mechanism open — the
  quantisation reading was refuted 2026-10-01 (the sub-bin deposit leaves it at 6.50°; `archive/v4/slot2-sb-refuter-2026-10-01.md`).
