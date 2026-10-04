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
- **Off-grid self-recovery** (S20, 2026-09-30 night): 37–43 of 200 fail at 1.4° (0/200 on-grid, worst 9.3°). Candidate F (exact
  azimuth + 4× shifts) sweep 430 → 24; closed 2026-09-30 night at true Q (lane Q, `archive/v4/slot1-q-record-2026-09-30.md`): grain C
  stays t2 (0.00°) under F at Q 0.012, so the S20 regression was the probe's 13.5 %-low Q, not F; F moves grain A 5.03 → 3.18° at
  kMax 1.2 and costs 3.8× on CPU — After v4.1. Grain B (6.50°, winner t84): mechanism open — the
  quantisation reading was refuted 2026-10-01 (the sub-bin deposit leaves it at 6.50°; `archive/v4/slot2-sb-refuter-2026-10-01.md`).
- **ACOM mirror pass (row 1) — residuals** (landed 2026-10-01, owner's card): (i) the pass costs ≈ 7/144 Au trials to the half-turn
  class (no pass: 40-set mean 132.1; with it ≈ 125, min 118; the gate's fixed set 116, pinned) — mechanism open; (ii) the linear
  sub-bin deposit as a parity step, predicted neutral ±1 on paired seeded sets (`archive/v4/slot2-sb-subbin-deposit-2026-10-01.patch`);
  (iii) the experiment-side py4DSTEM port (shell grid, arc-length kernel, ring mean in) vs an independent truth; (iv)
  `ACOMSession.estimatedDuration` ≈ 2× optimistic under the ×2 CPU pass. Predictions quote counts as distributions over angle sets.
  (v) code review 2026-10-01: for a mirrored win `inPlaneAngle` is "angle + π relative to the mirrored template" (`OrientationMatcher.swift:420-424`, `OrientationResult.swift:676-679`); the `acom_in_plane` map and its export publish it raw with no
  per-pixel mirrored flag, so pixels across a mirror boundary are not comparable (Euler, IPF and FitOverlays handle the flag) — a
  convention to settle (map the mirrored win to its proper-rotation equivalent, or export the flag), Gate D before any number moves — labelled 2026-10-02 (owner S2 a: Info › Mirrored and the in-plane note name py4DSTEM's +π); the convention waits for after v4.1.
  (vi) code review round 3: `selectOrientation` compares forward and mirrored in-plane bins in the runner-up "distinct orientation" test
  (`OrientationMatcher.swift` ~168, Metal ~310) — can shift `secondScore`/reliability only, never the winner.
- **Known-crystal Q reads the (200) ring as (111) on an Al [001] majority** — confirmed on the app's own path (lane Q, 2026-09-30
  night): the owner's raw and binned 060 cubes, the demo cube and Thronsen A read Q 12.5–13.5 % low, shell ratio 1.37–1.43 vs 1.155
  (the 09-29 "0.006577 / 1.0846" row was the Python lattice fit and an ellipse axis ratio, not this estimator). Shipped: the one-shell
  case reads "Shell ratio unchecked" (threshold-free); a "disagrees" line did not ship — the pre-registered rule flips on one number
  on each side (healthy n = 1: 2.4 % measured, 4.07 % recorded; WS₂ 13.3 % is the same failure class until an (00l) filter exists),
  so on his cube the Q row still reads "Measured" with the ratio beside it — the owner's card. The fix (ring-sequence assignment) is
  diagnosed in the record: recovers his cube to +0.45 % (ellipse) / +2.5 %, but the fcc √2 self-similarity needs a bounded N or the
  zone's own ring count — a design pass, not a patch. The caveat is lost on rewind, sidecar restore and re-reference (not persisted).
  Q1b (owner: measure first, 2026-10-01; `archive/v4/q1b-healthy-cubes-2026-10-01.md`): three healthy cubes, app vs py4DSTEM on the same peaks —
  Si-SiGe +1.36 / +1.40 %, sim_Au −2.72 / −1.12 %, Au_ref −4.41 / −5.30 %; the alias did not occur, but Au_ref's shell ratio is 10.6 % off
  (healthy side now {1.7, 2.4, 10.6} %, undiagnosed); NiCu_COPL excluded (file Q 3.57× the app's, undiagnosed). No rule proposed.
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
  k = 2, compact cubes ≤ 0.03 px, but the demo fixture moves 1.70 px; no fixed window ships (refuter HOLDS, held-out truth check 0.003 px). Done (lane Q, 2026-09-30 night):
  `tiledRun.windowSensitivityPixels` — median px between the caller's window and k 2.5 on a strided, byte-bounded sample: compact
  cubes ≤ 0.07 px, Particle_1 0.34, bullseye 3.8, Au_ref 5.3; 0.84 s on the gzip row-chunked demo cube (I/O). Not surfaced: the demo
  fixture reads 3.36 px in S14-D's table and was not re-measured — measure it before any display line. The demo fixture's origin is
  pinned by no harness.
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
- Lane F-B (2026-10-01, review rows 9/29/24; `archive/v4/slot2-fb-refuter-2026-10-01.md`): (a) a file ellipse with a non-positive semi-axis is now
  dropped silently by the importers ("No detector-distortion correction"), not refused by name — owner: make it a named refusal
  (recommended yes; py4DSTEM's `_transform` and `set_ellipse` validate nothing, so a refusal is stricter than py4DSTEM). (b) The
  count of non-finite pixels filled in both origin paths is not written into provenance (recommended: leave). (c) NEW:
  `Core/Analysis/ProbeKernel.swift:207,209` (`y < py / 2 ? y : y - py`, same for x) has the odd-N wrap alias row 9 fixed in
  `MatrixDFTCorrelation` — on odd N the middle row/column reads distance (N+1)/2, not (N-1)/2 (the refuter: "the same odd-N alias
  slip"; py4DSTEM builds that kernel on a centred meshgrid, so not the same formula). Gate D first; `:274,276` are already right.

### Other named presentation and trust residuals
One line each; full wording as above.
- Quantitative badge consults no origin gate outside ACOM — stated limitation; Gate D+B owed.
- Lineage (ROADMAP D closed 2026-09-30): a map restored from the sidecar has no task-row verdict (the rows read in-memory products); a phase map left by a rewind cannot be re-shown from Results.
- Export Data… (S8): py4DSTEM.read takes the RealSlice's dims as pixel indices ("pixels") and its data units as "intensity" — the existing bundle writer's layout; the true sampling and units are in `dim0`/`dim1` and the `mac4dstem_*` attributes (`archive/v4/polish-i-2026-10-02/`).
- Virtual-detector "Annulus" with inner 0 excludes the exact centre pixel (strict r² > rIn²; ≈ 5e-4 of each graphene pattern); the preview's bright-field disk includes it — py4DSTEM's convention unchecked, Gate D before any number moves (lane D refuter, 2026-10-02).
- Ptychography rotation branch (Slot 1 R1 refuter; review b1, 2026-10-02, `archive/v4/review-c-rotation-gateD-2026-10-02/`): the defocus sign (−C1) holds on the fit's branch; nothing checks the calibrated rotation is on it — the seed status prints the angle apart, both in py4DSTEM's sign (measured: the parallax fit reports py4DSTEM's sign at ±37°). Both solvers fold to a half-circle, so ≈ 180° apart arises only from an imported or hand-set rotation or near ±90°, where the fit's fold flips C1. No 180° case measured on data with truth.
- Phase-contrast budget (review d2, 2026-10-02): held products after the fit (KDE, depth planes, correction) and ptychography's prepared amplitudes plus its reconstruct working set are not summed; refusal threshold only.
- Session file shared by stem (review a2; owner card D1 c, 2026-10-02 — left for v4.1): `scan.dm4` and `scan.h5` in one folder map to one `scan.mac4dstem.h5`, so opening one adopts the other's calibration (a 2×-binned conversion: Q off by 2) and a save replaces the other's recipe, lineage and labels. An identity check (source name + native shape stamped, a shape mismatch refused) is built and archived, not shipped: `archive/v4/review-sidecar-identity-2026-10-02.patch`; naming by full file name is the alternative (plan §8).
- Binned views, tile budget (review d1, 2026-10-02, `archive/v4/review-d-tile-budget-gateD-2026-10-02.md`): `FourDArray.scanTileRows` now budgets at the pre-bin read extent; the binned mean pattern moves by up to 8–10 float32 ulps (~1e-6 relative, one cube; max pattern bit-identical; bin 1 byte-identical). The virtual-image progress tiles and parallax preprocessing size at the read extent too (lane L; products bit-identical for any grouping). Left: `DatasetPreviewBuilder.stride` sizes a 64 MB I/O budget from post-bin bytes (b² more disk read on binned views, no transient), and the "Streamed" byte figures (`AppState+ResultPresentation`, `SystemMonitor`) show post-bin bytes, b² under the bytes read.
- HDF5 at quit (2026-10-02, `archive/v4/review-k-hdf5-exit-2026-10-02/`): quitting during an HDF5 call crashed in teardown (probe 198/200 on the old code); quit now waits for the call in flight — one tile read at the scan-tile budget, 1–2 s on NVMe, ~30 s from a 150 MB/s external drive, unbounded on a stalled volume (Force Quit is safe: publishes are temp + rename). Not reproduced: the 10-01 abort in H5FL at exit with no thread in HDF5 — that process was the pre-push hook's unsigned build, which LaunchServices launches like the app (the hook can rebuild an app the owner is running).
- Owner cards D2/D3 residuals (lane I, 2026-10-02): stored Bragg disks are not a "carried result" — after a relabelling save (rehearsal A with disks saved → Open with Options… a same-size crop B → Save Calibration, allowed since no result maps) a reopen restores A's disks at B's positions (same shape, other offset passes `SessionPeakRestore.refusal`); no fix without a Remove for disks (card D3 b). The open-window registry withdraws on `.onDisappear`; whether a hidden window tab fires it is unverified (it re-enrols on `.onAppear`).
- RC drive finds (2026-10-02, minor, `archive/v4/rc-drive-2026-10-02/`): the sidebar's different-view warning truncates the refusal and remedy (full text only on hover, and the hover sends to an Info section that does not hold it); Dataset › Ignore Session Sidecar… reloads without asking and drops a crop's unsaved disk detection. [The removal that cleared an unsaved virtual image: fixed 2026-10-04, Slot 4⅞ lane S.]
- Review lane F residuals (2026-10-02): ⌘R's readiness predicate and the toolbar's private `primaryActionEnabled`/title are two copies (unify in a frozen-shell session); iDPC carries no `dpc_frame`; a detector-frame DPC angle keeps the Quantitative badge with its frame stated, as strain does (owner S1 b).
- **Crash after Compute Strain** (re-drive 2026-10-02, `archive/v4/polish-redrive-2026-10-02/`): an AppKit layout exception (EXC_BREAKPOINT in
  `_layoutSubtreeWithOldSize`, `~/Library/Logs/DiagnosticReports/mac4DSTEM-2026-10-02-133933.ips`) right after Compute Strain on the demo cube,
  after a label export and Detect All; not reproduced on a fresh launch. Cause not established — Gate D before any fix.
- **Slot 4½ residuals** (2026-10-02; the rest of `archive/v4/polish-drive-2026-10-01.md` fixed): [the β″ preset's CIF picker closed 2026-10-02: the RC drive
  opened and applied it — the earlier report does not reproduce]; [the SCAN inset moved into the
  diffraction pane, Slot 4⅞ lane R2 (owner Q3 a); its height follows the scan aspect (a 4:1 scan gives 472 pt); with no product shown
  only the arrow keys move the position]; a window that resized itself (unreproduced);
  "Compute Image" offered while the image is live (frozen toolbar — needs a picture, after v4.1).
- Number fields (lane N, 2026-10-04, a declared trade-off): while a finer value is stored, typing exactly the text the field shows (0,03 over 0.0275) is a no-op; 0,030 or 0.03 set it.
- Lane R residuals (2026-10-04): Origin calibration in Prepare still runs the remembered task's analysis (`AppState+Calibration.swift` ~:130 — under Disks the Bragg map replaces the virtual image). Decided by the session (overrule on sight): a map restored from the sidecar at open is covered by the opening virtual image under every remembered task, as it already was under Virtual detector; it stays in the Results list.
- Room switches, seen on lane N's drive (2026-10-04, scratch build of a841f9ae, shots 44 and 50 in `archive/v4/polish-plan-2026-10-02/lane-N-drive/`; deferred by the owner for cost, Gate D before any fix): after an ACOM preview, Imaging › Virtual imaging kept showing the ACOM map; with an ACOM full scan held (exploratory Q), Crystal Maps › Strain → Orientation showed "No Result Yet" (`presentProductForEnteredMode` has no `.virtualDetector` case; the Orientation branch unexplained).
- Lane M residuals (2026-10-04): ⌘O / Preprocess Raw Data… with Settings or the object table key open a second dataset window (`openWindow` always creates one, as New Dataset Window does there); `PhaseClaimOverlay`'s legend and note still sit inside the zoomed layer (the fit chip's old defect); rename `residentMemoryMB` → `appMemoryMiB` when the frozen shell next opens.
- Lane F-C (2026-10-01, review rows 8/25/27; `archive/v4/slot2-fc-refuter-2026-10-01.md`), all pre-existing, registered not fixed: (1) [the VD step fixed 2026-10-01, lane FC2; the disk, diffraction-groups and phase-map steps 2026-10-02, lane E; strain, ACOM and DPC steps still take the current mode's keys] replay, lineage
  rewind and the opening pass publish through `publishProduct`, which keys provenance by `navigation.analysisMode`; the executor
  never switches mode, so a replayed virtual_detector step run under `.disks` carries `source_product=bragg_vector_map` (fixture:
  record a VD step, change mode, replay). (2) `learned_model_sha256` / `learned_model_*` are read live at record time
  (`LearnedDetection.replayParameters`); a model swap during Detect All would record the new hash for an old-model run. (3) fixed 2026-10-01 (lane FC2: VD runs numbered at start; an older run never lands over a newer one).

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
  the pattern readout; a fresh cube shows its virtual image; counts grouped. Slot 1 lane P (2026-09-30 night) took the rest of
  the drives' list (lineage order, legend counts, crop-warning axes, the configurator status, "px", the drag sentence) and the
  bin-2 aperture default (Gate D: the view-frame default was re-referenced as a source point; `archive/v4/v41-plan-2026-09-30.md`
  § Log). Left: Info › Provenance shows raw snake_case keys (`WorkspaceInspector.swift:625`, frozen; a wording edit that corrects
  no false claim — the owner's call, the one-line patch is in the Slot 1 record).
- Slot 1 P drive residuals (2026-09-30 night, shots in `archive/v4/slot1-p-drive-2026-09-30-shots/`): the bottom Lineage/Output pane
  is ~1.5 rows tall at 1470 × 923 (frozen `WorkspaceView`); the sidebar session-warning headline truncates; the "Positions used"
  percentage fallback (> 2 % excluded) was not reached on screen.

### S5 Sessions & sidecars: residuals (the guard, cancel token and reopen fixed 2026-09-30)
**Sidecar access (2026-09-30 night, owner's drive):** on a Mac with no grant (every dataset after a migration or a rebuild that
lost the container's bookmarks) each session read "could not be read — HDF5 … errno 1"; the only remedy was Save As on the same
file. Fixed: "Allow Access…" under the sidebar warning and in the Dataset menu (an open panel at the sidecar, the grant
remembered, the dataset reopened), driven on a scratch build (40 labels restored). Since Slot 4⅞ lane S (2026-10-04) the warning names
the sandbox and Allow Access…, the raw line goes to the Log (unverified on screen: needs a Mac without the grant); a related-item
declaration was tried and refused (the sidecar's extension is the dataset's `.h5`).
- S18 (2026-09-30 night, driven): a load's tail resets only its own load; promote keeps the scan position (crop offset added);
  crop-shaped origin maps on a whole-file reopen are named ("Not carried into this view"); a schema-5 sidecar's view is
  "unrecorded" (adopted only at whole file). Residuals: a schema-5 sidecar's stored disks are refused even at whole file (v1.0.0
  disks no longer restore — owner); an uncancelled superseded tail still runs on (unreachable by click); (c) parallax/ptychography
  not in the replay record; (d) a user analysis mid-replay steals Cancel; (e) replay contracts in three places (the recording
  sites + `ProductWorkflow.currentReplaySignature`, `ReplayRecordFrameMap.role`, `ReplayPlanner.parse`) — a design change.
- **Resident**: "freed" bytes never measured; the reopen fix has no test (the recovery store is real `UserDefaults`). UX: a retarget before any save lasts one dataset change; pre-S4 calibration-only sidecars unrecognisable;
  `calibration.*` identifiers doubled under the export sheet; Recents labels "This Mac". (`.h5.h5`: fixed 2026-09-09, `a8b13c6`.)

## Ready on the new hardware (owner, 2026-09-30) — and what still waits on the owner

### The new Mac (M5 Pro, 64 GB): brought up 2026-09-30 — the hardware lanes
Baseline, limits re-measured (floors kept, `-jobs 2` and "quit Claude to train" retired) — `archive/v4/newmac-gateD-2026-09-30/record.md`
(chip vs OS for the MPSGraph bug stays open: the old Mac is retired). **Done 2026-09-30 night:** the 28 GB `--parity` run
(`archive/v4/parity-28gb-2026-09-30.md`: the app's raw read is right; the "unfiltered" bin-4 cubes are hot-pixel filtered at 15
detector pixels incl. the direct beam — the owner's files, not the app; the > 2 GB read rule is retired for mapped local
volumes); the parallax/ptychography cost (`archive/v4/parallax-ptycho-cost-2026-09-30.md`: estimators honest, the 051 cube is
not an acquisition for them); owner: KEEP, limits now half of RAM (`PhaseContrastMemoryBudget`). **On py4DSTEM's graphene cube, 2026-10-01 (R4 + DC, `archive/v4/r4-*`, `dc-*`):** the aligned BF matches py4DSTEM to 3.6e-5
(the vignette was a Float32 stack-mean reduce; C1 663.42 vs 664.05 Å); the (2,1) pair's ≈ 600 Å is py4DSTEM's basis-origin offset on an
exactly linear shift field — unobservable in both with the default alignment, the app's 0 labelled (owner 2026-10-01: the higher-order
toggle removed; `regularize_shifts` not offered); the difference map is removed (α = 0 alternating projections with it); the |O| ≤ 1 clamp is on by
default — GD's gap to py4DSTEM 8.6 → 1.7 % at 8 iterations, growing after (2.3e-2 at 32), `fix_probe_com` still off (5e-4); the object
still correlates 0.69 with py4DSTEM's. Archived scripts that call `ptycho dmap` or an unflagged `ptycho gd` reproduce only at their commit.** C5's 500-step run done headless
(`archive/v4/c5-training-run-2026-09-30.md`: 68 s, 745 MB peak, D7 declines the candidate — recall 58.4 → 57.1 %, precision
65.7 → 72.1 %). **Open:** the Train Model… drive is the owner's (a scratch build cannot read his sidecar's labels — the
grant is his build's bookmark, C10); the inter-labeller check on the 370 centres. A DM4 whose disk is disconnected refuses
every later read until reopened (Slot 4⅞ lane D: a held descriptor + latch, measured on HFS+/APFS/exFAT RAM disks,
`archive/v4/polish-plan-2026-10-02/lane-D-probe/`); a read in flight at the yank can still crash; the probe is unit-blind — any change to
the reader's held descriptor re-runs `lane-D-probe/drive.sh`; after the latch each pattern click re-presents the alert (no dedupe).
Network volumes keep the full read.

### Scan-fastest DM4 detector pair: order unverified against GMS — a named limit (2026-09-05; owner 2026-09-30: leave it)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps tags `[Rx, Ry, Qy, Qx]` (pattern 480×448) with one axis order for the
scan pair and the other for the detector pair; a transposed pattern would silently flip strain axes and R–Q rotation. The owner
declined the GMS check (ADR 050). Not on the v4.1 path; a session that touches the reader pins an ncempy checksum first.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Owed on screen from earlier drives (2026-09-09)
Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh, configurator single-pattern preview,
"No preview available") reaching the status strip, the disk-centre label round trip (the owner's hand), and the bounded
promote run. There is no automated visual baseline; drives are the evidence (standing note archived 2026-09-30).

## Data, harnesses & code hygiene

### Preprocessing export (Slot 2 lane X, 2026-10-01): four named residuals
Stride, detector crop and py4DSTEM's hot-pixel filter landed (`archive/v4/slot2-x-record-2026-10-01.md`, `-refuter-`). (1) The
bin's float32 sum order is not numpy's: ≤ 1.14e-4 relative on the 28 GB cube, never bit-identical — owner's call whether to match
it. (2) The filter's mean is Double where numpy's is float32 (DEVIATION): numpy is 45–230 counts off at 2e5 against thresh 8, so
inside a bright direct disk py4DSTEM's own mask is partly an accumulation artefact; the 060 match (exactly the 15) is one dataset
with an unmeasured margin — `--export-parity` could print it. (3) A strided or detector-cropped export carries no replay recipe
(named in the status line when there is one to omit). (4) Since Slot 4⅞ lane V the export carries the
accelerating voltage; a session voltage above 1000 kV is stamped as typed and reopens divided by 1000 (the opener's eV rule). Polish from the drive: 1-px crop steppers; the sheet's short scroll area.

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
- **Learned detector on the Neural Engine (2026-09-30 night, Gate D + two refuter passes, `archive/v4/ane-return-2026-09-30/`):**
  the load asks for `.cpuAndNeuralEngine` and refuses a model the Neural Engine did not run; the parity test is green for the
  right reason. Residuals: measured on this Mac only (M5 Pro, macOS 27.0.1); a machine with no Neural Engine now refuses the
  learned detector (was: ran on other numerics unannounced) and re-runs the 0.3 s check on every live preview; the fine-tuning
  candidate's unit and a partial Neural Engine plan are not pinned by a test; at threshold 0.9 the unit moves up to 5 % of
  accepted peaks (0.45 % at the shipped 0.7). CI's unit job stays paused (ADR 040); every green gate is local.

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
