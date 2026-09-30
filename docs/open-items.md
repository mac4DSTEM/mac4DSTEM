# Open items

Live defects, debts, owed runs and open questions only — status is `docs/status.md`, history is `docs/archive/`. Grouped
(2026-09-30, S1) by where each is taken: **Science** one Gate D at a time in the handoff's order (a landed change to a
scientific output cuts a release); **Polish** by the Session queue's room (`ROADMAP.md`, S3–S6); **Waits** on hardware or
the owner; **Code hygiene** rides with the session that touches its file. Each entry is ≤ 12 lines and dated: what is
wrong, the pinning evidence, the trap, the owner. No narrative. Closed items and every sentence trimmed out (the whole
pre-S1 body is verbatim there): [`archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md); earlier trims are the
`open-items-*.md` files in `archive/` and its `v3/`, `v4/` folders.

## Science & parity

### Phase mapping under the T4 object bar (ADR 040) — one metric short
Raw speckle, not cleaned counts, certifies a classifier (`docs/cloud/2026-09-23/T2-direction-check.md`); the truth's cuts
(782 / 10 / 4 px) are that dataset's, never an app default. First scored run: FAIL on θ′ edge-on raw spurious 7 > 5.
B1 (`archive/v4/b1-edge-on-gateD-2026-09-28.md`, `b1-narrow-guard-2026-09-28.md`): 3 are edge calls 1–2 px from truth
needles, 4 real T1 → edge-on; a global guard breaks T1, the narrow one moves errors between classes — neither shipped.
The largest error class, T1 edges called Al (204), is mostly where the truth draws the edge (`t1-edge-detection-gateD`).
S10 (2026-09-30): candidate A refuted at step 0; B (noise hit) refuted at the bar (error 1.31 → 4.41 %); the metric ships as a quantity (ADR 048). T1's [0 -4 1] entry holds
30 first-order-Laue-zone reflections (`archive/v4/s10-s11-gateD-2026-09-30.md`).

### Tiled GPU memory: classical and learned Detect All and the virtual-detector loops gated flat
Classical and learned `detectAll` are gated by `tools/tiled-detection-memory-test` (`archive/v4/s10-s11-gateD-2026-09-30.md`).
In the app (2026-09-30, scratch build, Thronsen A 171², 128²): learned Detect All, 29 241 positions in 1:17, footprint flat
1.63–1.67 GB (peak 1.72 GB), 955 MB after. `VirtualDetector`'s six streaming paths measured flat and gated by
`tools/virtual-detector-memory-test` (S16, 0–2 MB over 10 tiles; retained-buffer mutants 352 MB); on Thronsen A 778 MB stays
between passes as 662.7 MB "Malloc Large (empty)" = two 331 MB tiles (an observation, no mechanism; the ≈ 0.93 GB baseline
may be the same). Resident-cube paths unmeasured. D1: the shipped max(0.02 Å⁻¹, 1 px) tolerance fits all four datasets.

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

### Phase mapping's matrix verdict is by exclusion, and the cross-phase winner ignores completeness — MEASURED, unwired candidate parked
`Core/Crystal/PhaseVectorMatching.swift`: `minimumVectors` = 2 (`:73`, applied `:947`), so a position is "matrix" when almost
nothing survives removal; the best entry per phase is chosen by mean distance alone (Gate B 2026-09-15: 0.004 two-vector
beats 0.012 ten-vector). The count-aware candidate (`completenessAwareCrossPhaseRanking`, `:182`, off) is byte-identical on
the demo cube on or off; Thronsen is not a valid second measurement; step 3 stride-3 sits outside every threshold tried.
Gate D before any edit. Owner: unclaimed. Detail: `archive/v3/step3-2026-09-16.md`.

### Origin validity mask: disclosure, D4 count and (S23, 2026-09-30 night) the Prepare wash; still `validation:"none"`
`OriginMaps.originValidity` carries the robust trim's `kept` mask (ADR 033). In Prepare, with Fit overlay on, the real-space pane
greys the excluded positions with "N of M positions excluded by the origin fit's robust trim" (`FitOverlays.originTrimOverlay`);
seen on screen on sim_Au: 891 of 8400, Positions used 7509 (drive 1, 2026-09-30 night). Residuals: an imported or restored origin
has no mask (no wash, by design); pinch-zoom tracking unverified (rotation seen); no standalone origin-map product.

### ACOM / zone-axis science residuals — three measured gaps, no fix attempted
- **Zone axis up to 12.8° beyond the bank's own sampling** (2026-09-15): winner outscores truth by 0.6–10 %, worst ⟨122⟩; next:
  dump the winner's and the true axis's templates for one failing case.
- **Off-grid self-recovery** (S20, 2026-09-30 night): 37–43 of 200 fail at 1.4° (0/200 on-grid, worst 9.3°; the old "26" named no
  definition). Candidate F (exact azimuth + 4× shifts) sweep 430 → 24; not proposed — its demo grain-C regression was measured at a
  known-crystal Q 13.5 % low (refuter, `archive/v4/s20-refuter-2026-09-30.md`): a Gate D at true Q settles it.
- **Known-crystal Q on a cube whose majority grain lacks the reference shell** read the demo cube's Q by the (200)/(111) ratio in
  the S20 probe and the tool ignored the shell check — check whether the app's calibration path can do the same (Gate D).
- **Rotation null loses power at the highest noise**: 3/12 refused at sd 0.05 vs 0/60 shuffle null; the demo cube (sd≈0.010) is
  certified 2/60 — "measured −67.5°" recurs ~1 in 30.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Origin-fit and Q-calibration open holes
- **Origin gate** (2026-09-05): which statistic gates `originFitIsSane` (full-scan RMS can't see bias; the robust residual of
  2026-08-28 passes a 15 px-displaced fit); the trimmed fit is blind to clustered contamination ≥ 50 % (a 40 px-off quarter →
  100 % kept, 20.6 px error). Owner: a design pass, `docs/q-calibration-design.md`.
- **Coarse block seed lands on the wrong blob on noisy cubes** (Gate B refuter, §9): 28/169, 29/195, 2/169 of three cubes miss by
  >1 px vs a Gaussian-argmax seed. S14 (2026-09-30 night, `archive/v4/s14-*`): a box seed does not meet its bar; trimming does
  NOT hide the offset on Si_SiGe_exp, both bullseye cubes and Au_ref (0.5–2.8 px); on bullseye the refine step's iterated
  r + 1.5 window walks along the ring — confirmed by S14-D (`archive/v4/s14d-*`): bullseye_sim 3.87 → 0.02 px at
  k = 2, compact cubes ≤ 0.03 px, but the demo fixture moves 1.70 px; no fixed window ships (refuter HOLDS, held-out truth check 0.003 px). Next: the window-sensitivity
  quantity in Core (median px between k 1.2 and 2.5, strided; < 0.1 s). The demo fixture's origin is pinned by no harness.
- **Reference-shell pick has no l-filter**: 2H-WS₂ selects (0002), invisible on a [0001] zone — predicted mis-scale 2.26×, silent;
  score-based rescue fails (score halves, reliability rises). Owner: its own design pass.

### Other named science residuals
One line each; full wording in `archive/closed-items-2026-09.md` (2026-09-30) and `archive/v4/open-items-detail-2026-09-25.md`.
- T1 [0 -4 1]: 252 not-indexed positions are detection noise (a Friedel pair 2.5–5.2° off); levers (centroiding, tolerance, accept) are the owner's.
- R–Q (ADR 040): an unmarked mac4DSTEM export (before 2026-09-28) keeps today's reading and its R–Q row says the sign is unrecorded (S15;
  `archive/v4/s15-rq-legacy-exports-2026-09-30.md`); `Si-SiGe_calibrated.h5` is one (app-measured: re-export it to mark it).
- Al-Mg-Si peak set: 39 % explained by the best Al orientation (2026-09-12) — detection, not the matcher.
- Region circle radius: the mask takes centres up to ½ px outside the drawn ring (`R + 0.5`, strict `<`; R 5: 97 px vs `d ≤ R` 81, py4DSTEM 69) — own Gate D (D025 refuter).
- Bullseye detection accepts noise: outer-edge probe size for structured probes open.
- Twisted bilayer graphene finds only the beam at defaults — Gate D with a per-pattern funnel.
- Learned detector above 256 px: the anchor measured 2026-09-29, no change (same disks; a zeroed probe channel bit-identical); < 256 px with an off-centre probe still scales by the crop's maximum (kept for byte-identity) — owner.
- #18 training campaign can't reproduce the app's Si_SiGe strain — two candidate fixes, own Gate B.
- CIF symmetry (S13, 2026-09-30, `CIFImport.spaceGroupOrder`): a list shorter than the named IT group's order is refused; residuals — a group
  named by H-M symbol alone is not checked, a partial list in a primitive-looking cell passes, a primitive C-monoclinic cell with β = 90.00 is falsely refused.
- ACOM exported Euler angles differ from py4DSTEM/orix by frame rotation `P` — relabel-vs-convert, then Gate B.

### Other named presentation and trust residuals
One line each; full wording as above.
- Quantitative badge consults no origin gate outside ACOM — stated limitation; Gate D+B owed.
- Lineage (ROADMAP D closed 2026-09-30): a map restored from the sidecar has no task-row verdict (the rows read in-memory products); a phase map left by a rewind cannot be re-shown from Results.
- The single-slice ptychography sampling unit prints "A", not "Å" (presentation).

## Polish — the Session queue's rooms (S3–S6)

### S4 Phases & precipitates: residuals (the zone-axis stale check, the busy line, a challenged matrix position)
- The zone-axis ranking's stale check (Q, origin, ellipse, and since S12 the matrix phase and tolerance) does not cover the
  reference settings, direct-beam radius or maximum vector `fitZoneAxis` also reads (`PhaseVectorMatching.swift:728-750`).
- At 1000 pt a busy run clips the status text and hides the metrics line; the panes widen while busy so the inspector
  covers ~110 pt of the phase map (original wording, `archive/closed-items-2026-09.md`): metrics get truncation priority,
  split fraction constant.
- A challenge-turned matrix position shows its disks as unexplained in the claimed-disks overlay (the challenger's axis is not recorded; named in the evidence line since S12).
- Polish 2026-09-30 (driven, drives 3–4): the Matrix picker names β″ twins by zone axis; Show Objects / Match Distance swap to
  "Show Phase Map"; Evidence help names the selected position; a visible Re-measure; "Saved with the dataset" from a real
  session flag; carried-calibration refusals shown in Prepare; the annulus centre drags; units read Å⁻¹; the promote footer keeps
  the pattern readout; a fresh cube shows its virtual image; counts grouped. Left (proposals, shots `drives-2026-09-30-night-shots/`):
  the Lineage list puts a later origin fit above earlier nodes; the S23 legend chip prints ungrouped counts ("60 of 10000"); the
  crop warning mixes axis orders ("64x60 at (16, 20)" vs "60 × 64 scan"); Info › Provenance shows raw snake_case keys; the
  configurator's status keeps "Sampling a preview · row 24 of 25"; the origin detail wraps "px" alone; a from-file drag sentence
  could read "Aperture center replaced the file's origin".
- **After a detector-bin-2 load the aperture ring sits off-centre** in the 64 × 64 pattern (drive 3, shot 52): likely a stale
  128 px aperture — reproduce, then Gate D (it sets what the virtual image integrates).

### S5 Sessions & sidecars: residuals (the guard, cancel token and reopen fixed 2026-09-30)
- S18 (2026-09-30 night, driven): a load's tail resets only its own load; promote keeps the scan position (crop offset added);
  crop-shaped origin maps on a whole-file reopen are named ("Not carried into this view"); a schema-5 sidecar's view is
  "unrecorded" (adopted only at whole file). Residuals: a schema-5 sidecar's stored disks are refused even at whole file (v1.0.0
  disks no longer restore — owner); an uncancelled superseded tail still runs on (unreachable by click); (c) parallax/ptychography
  not in the replay record; (d) a user analysis mid-replay steals Cancel; (e) replay contracts in three places (the recording
  sites + `ProductWorkflow.currentReplaySignature`, `ReplayRecordFrameMap.role`, `ReplayPlanner.parse`) — a design change.
- **Resident**: "freed" bytes never measured; the reopen fix has no test (the recovery store is real `UserDefaults`). UX: a retarget before any save lasts one dataset change; pre-S4 calibration-only sidecars unrecognisable;
  `calibration.*` identifiers doubled under the export sheet; Recents labels "This Mac". (`.h5.h5`: fixed 2026-09-09, `a8b13c6`.)

## Ready on the new hardware (owner, 2026-09-30) — and what still waits on the owner

### The new Mac (M5 Pro, 64 GB): brought up 2026-09-30 — the three hardware lanes
Baseline, limits re-measured (floors kept, `-jobs 2` and "quit Claude to train" retired, the > 2 GB read rule kept until the 28
GB DM4 is read here) and the owed old-Mac run of the MPSGraph repro: `archive/v4/newmac-gateD-2026-09-30/record.md`. **Lanes:**
(1) C5, 500 training steps on ≥ 12 held-out labelled positions and Train Model… driven (the labelled sidecar sits beside the
bullseye cube); (2) parallax and single-slice ptychography on real data — 8–11 GB asked for a 268 MB cube: a Gate D on the true
cost, then the owner keeps or removes them; (3) the 28 GB `--parity` run of the raw Al-Mg-Si DM4 (`almgsi-gateD-2026-09-24.md`
6, 8). RAM does not fix: a vanished volume is a SIGBUS with no dialog; network volumes keep the full read. Detector truth (A2,
370 centres, net 0.584 / 0.655): an inter-labeller check owed.

### Scan-fastest DM4 detector pair may be transposed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps tags `[Rx, Ry, Qy, Qx]` (pattern 480×448); a transposed pattern silently
flips strain axes and R–Q rotation. Owed: the owner reads width/height in GMS — if 448 wide, flip `DM4Reader.scanFastestStrides`
(`:194`) and pin an ncempy checksum. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Owed on screen from earlier drives (2026-09-09)
Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh, configurator single-pattern preview,
"No preview available") reaching the status strip, the disk-centre label round trip (the owner's hand), and the bounded
promote run. There is no automated visual baseline; drives are the evidence (standing note archived 2026-09-30).

## Data, harnesses & code hygiene

### Misc data-layer items, low priority
C3 drive leftovers: staleness (f). HDF5 runs under one lock: thread-safety rests on one 2026-08-19 `nm` inspection
(`H5is_library_threadsafe` called nowhere); a sidecar write can block a caller for seconds. Standing limits: ptychography pads
both object axes (`DEVIATION`); `bragg-spacing-probe` and `residency-sweep` need multi-GB data and stay diagnostics.

### Acceptance-harness gaps — red gate names the symptom, counts not positions, thin infrastructure (2026-09-02/09)
- S19 (2026-09-30): `compare.py` collects every mismatch, peak positions are pinned per sampled position (0.05 px, measured on
  this Mac's GPU only), no data is a FAIL, `scientific` reaches the harness (`CI`/`MAC4DSTEM_NO_REAL_DATA` skip it loudly; `all`
  has no opt-out); `--check-data` is existence-only; 4 datasets stay UNPINNED.
- **Infrastructure**: the 15 s budget gates the pinned datasets only; virtual-image `abs_tol` exceeds one
  fixture's range; `rel_tol` on `diskProbeRadiusPixels` is inert below 50 px; `if not actual:` is unkillable; the runner aborts
  at the first red harness.
- **Learned-detector parity is a same-runtime claim**: skips where no Neural Engine is listed (bars not loosened); a
  CPU-written second fixture would make it a check. With CI's unit job paused (ADR 040) every green gate is local.
  **M5 Pro (2026-09-30, Gate D, refuter HOLDS):** Core ML's `.all` runs it all on the GPU (aned log) → 8 extra picks, red;
  forced ANE passes 354/354 (batch 32 only — others fall silently to CPU). Mechanism unknown; owner pick a/b in ROADMAP.

### Accessibility (does NOT block a release — owner decision, 2026-09-11)
The 2026-09-08 `EXC_BAD_ACCESS` in `AccessibilityNode.accessibilityLabel()` did not recur: a full AX probe of every room
(2026-09-30 night, scratch build) ran without a crash, and the controls named then already expose labels. The eight bare ones it
found (detection and group steppers, Fit overlay, Show claimed disks, remove-phase) are labelled (S22). Residual: the whole
Advanced-detection section shares one identifier (`disk.advancedDisclosure`); the crash's cause was never established.

### The audit's refactor list, rows 4–13 — most parked
Open: row 4 (a shared harness `fail` helper — Gate B, a shared bug can green 46 harnesses); rows 6–7, the
**resultexport-split and braggvector-emd-writer-split**, each prepared and parked (the HDF5-adjacent split: four
ResultExport files, `sessionPixelCalibration` single-sourced; the writer by dataset kind, each file `nonisolated`-verified by a
cold build) — a session with Gate B support; row 12 (the >1 000-line harness mains). **Row 9 is a do-not:** five `median`
bodies in Core stay separate until a Gate D shows they should agree (ADR 015). Detail: `archive/open-items-detail-2026-09-18.md`.

### Minor tooling/hygiene residuals
`tools/free-space.sh`: the temp prefix is spelled by producer and reaper separately and the MCP root is hardcoded — a `tools/lib/`
constants file is deliberately NOT taken (a bad line there kills every gate). `.fixedSize()` in `UI/` (20 call sites counted
2026-09-29) against the constraint-loop rule: the one suspect, the zoom badge (`ImagePanes.swift:662`, in the header's
`ViewThatFits`), is not armed by reading — monospaced digits, so its width changes only when the digit count does, and it
is inserted once per pinch, not per tick; never seen to abort. Unverified on screen; the rule stays a review item.
