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
30 first-order-Laue-zone reflections (`archive/v4/s10-s11-gateD-2026-09-30.md`) — the library comment is stale.

### Tiled GPU memory: classical and learned Detect All gated and seen flat; the virtual-detector loops unmeasured
Classical and learned `detectAll` are gated by `tools/tiled-detection-memory-test` (`archive/v4/s10-s11-gateD-2026-09-30.md`).
In the app (2026-09-30, scratch build, Thronsen A 171², 128²): learned Detect All, 29 241 positions in 1:17, footprint flat
1.63–1.67 GB (peak 1.72 GB), 955 MB after. **Open:** `VirtualDetector`'s tiled loops have the same shape (maybe the
unexplained ≈ 0.93 GB baseline). D1: the shipped max(0.02 Å⁻¹, 1 px) tolerance fits all four datasets.

### The 2026-09-09 register, triaged 2026-09-29 — 8 Gate D candidates left (D019, D023, D025 fixed 2026-09-30)
All 156 clusters judged against `main` (`archive/2026-09-09-review/triage-2026-09-29.md`); D019/D023/D025 fixed with
refuters (`archive/v4/register-D019-D023-D025-gateD-2026-09-30.md`). Reachable, each its own Gate D: **D079**
parallax/ptycho take the aperture centre, not the fitted origin; **D098**, **D004** learned-detector window effects over
256 px; **D068** calibration edits never stale a strain map; **D017**, **D020**, **D006**, **D021** (see the record).
New from the D023 refuter: `occupiedPositions` (`StrainMapping.swift`) counts central-beam-only positions, raising the
minimum cluster support — at 95 % central-only no basis. Owner: order.

### Phase mapping's matrix verdict is by exclusion, and the cross-phase winner ignores completeness — MEASURED, unwired candidate parked
`Core/Crystal/PhaseVectorMatching.swift`: `minimumVectors` = 2 (`:73`, applied `:882`), so a position is "matrix" when almost
nothing survives removal; the best entry per phase is chosen by mean distance alone (Gate B 2026-09-15: 0.004 two-vector
beats 0.012 ten-vector). The count-aware candidate (`completenessAwareCrossPhaseRanking`, `:182`, off) is byte-identical on
the demo cube on or off; Thronsen is not a valid second measurement; step 3 stride-3 sits outside every threshold tried.
Gate D before any edit. Owner: unclaimed. Detail: `archive/v3/step3-2026-09-16.md`.

### Origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay owed, still `validation:"none"`
`OriginMaps.originValidity` carries the robust trim's `kept` mask (disclosure only; ADR 033); the D4 count
(`PrepareSettings.positionsUsedValue`) is **unverified on screen**. Step-3 trim sweep, 4 cubes: excluded 0.6–15.7 %, `maxGap`
1–5. **Owed:** the spatial overlay (excluded positions greyed via `DisplayedProduct.validityMask`), not built — new
surface. Owner: unclaimed. Detail: `archive/open-items-detail-2026-09-18.md`.

### ACOM / zone-axis science residuals — three measured gaps, no fix attempted
- **Zone axis up to 12.8° beyond the bank's own sampling** (2026-09-15): winner outscores truth by 0.6–10 %, worst ⟨122⟩; next:
  dump the winner's and the true axis's templates for one failing case.
- **26 of 200 templates fail to recover themselves off-grid** (2026-09-14) by 1.7–9.3°, 0/200 on-grid; two hypotheses spent; Gate D owed.
- **Rotation null loses power at the highest noise**: 3/12 refused at sd 0.05 vs 0/60 shuffle null; the demo cube (sd≈0.010) is
  certified 2/60 — "measured −67.5°" recurs ~1 in 30. `power_radial` is omitted by decision (DEVIATION, `OrientationPlan.swift:212-229`).
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Origin-fit and Q-calibration open holes
- **Origin gate** (2026-09-05): which statistic gates `originFitIsSane` (full-scan RMS can't see bias; the robust residual of
  2026-08-28 passes a 15 px-displaced fit); the trimmed fit is blind to clustered contamination ≥ 50 % (a 40 px-off quarter →
  100 % kept, 20.6 px error). Owner: a design pass, `docs/q-calibration-design.md`.
- **Coarse block seed lands on the wrong blob on noisy cubes** (Gate B refuter, §9): 28/169, 29/195, 2/169 of three cubes miss by
  >1 px vs a Gaussian-argmax seed; plane-fit trimming hides most. Owner: a design pass before the holes above.
- **Reference-shell pick has no l-filter**: 2H-WS₂ selects (0002), invisible on a [0001] zone — predicted mis-scale 2.26×, silent;
  score-based rescue fails (score halves, reliability rises). Owner: its own design pass.

### Other named science residuals
One line each; full wording in `archive/closed-items-2026-09.md` (2026-09-30) and `archive/v4/open-items-detail-2026-09-25.md`.
- T1 [0 -4 1]: 252 not-indexed positions are detection noise (a Friedel pair 2.5–5.2° off); levers (centroiding, tolerance, accept) are the owner's.
- R–Q (ADR 040) residuals: a datacube exported before 2026-09-28 and reopened is sign-flipped; the campaign report and the parallax fit's own rotation keep the old sign / are untested.
- Image `PrecipitateSegmentation.segment` is unwired and has four defects (NaN regions, two surviving mutants, dark ridges) — retire it (lean-app) or fix.
- Diffraction groups: no shipped test reaches the two-pass path (cube cache > 512 MB); profile Release vs Debug before deciding its fate.
- Al-Mg-Si peak set: 39 % explained by the best Al orientation (2026-09-12) — detection, not the matcher.
- β″ zone axes presented under ⟨110⟩Al unanswered (known, scoped).
- Hexagonal IPF key may be labelled the wrong way round (2026-09-11) — settle, pin with a test.
- Single-slice ptychography export guard may miss its mode (`ResultExport.swift:1506`) — Gate D.
- Region circle radius: the mask takes centres up to ½ px outside the drawn ring (`R + 0.5`, strict `<`; R 5: 97 px vs `d ≤ R` 81, py4DSTEM 69) — own Gate D (D025 refuter).
- Bullseye detection accepts noise: outer-edge probe size for structured probes open.
- Twisted bilayer graphene finds only the beam at defaults — Gate D with a per-pattern funnel.
- Learned detector above 256 px: probe/pattern anchor mismatch — one >256-px case scored both ways (Gate B).
- #18 training campaign can't reproduce the app's Si_SiGe strain — two candidate fixes, own Gate B.
- CIF import can accept a wrong crystal (partial ops list, Gate B escape E2) — needs an IT-number table.
- ACOM exported Euler angles differ from py4DSTEM/orix by frame rotation `P` — relabel-vs-convert, then Gate B.

### Other named presentation and trust residuals
One line each; full wording as above.
- Ellipse "Fit anyway" mark lost on a session round trip — sidecar wire-format decision.
- Challenged matrix verdict drawn like one by exclusion (same grey). Presentation.
- Quantitative badge consults no origin gate outside ACOM — stated limitation; Gate D+B owed.
- Radius-only aperture drag destroys the fitted origin (rounding trips the centre branch) — Gate D.
- "Computed this session" reports what exists, not what was computed. Presentation.
- Moving the detector destroys the origin fit with no durable warning — owner: confirm, banner or refuse.
- One-peak warning below the fold; Strain unlocks on vectors existing, not usable. No Gate D.
- DPC's always-shown qualitative banner over quantities called quantitative — trust-fixes session.

## Polish — the Session queue's rooms (S3–S6)

### S4 Phases & precipitates: an uncalibrated run, tie order, the busy line, the recipe
- Fixed 2026-09-30: phase mapping and Find Matrix Zone Axis now require a physical Q scale (a prerequisite with its route
  to Prepare; a refusal line — unverified on screen). The zone-axis list now records its Q scale and calibration and
  shows "…changed since this ranking — fit again" instead of rows once they move (unverified on screen: change Q after
  a fit). The "run-dependent tie order" was `tools/phase-map-probe`'s Dictionary, fixed; the app's own ranking is now a total order too.
- At 1000 pt a busy run clips the status text and hides the metrics line; the panes widen while busy so the inspector
  covers ~110 pt of the phase map (`report-drive3.md` step 4): metrics get truncation priority, split fraction constant.
- Built 2026-09-30, unverified on screen: the claimed-disks overlay (drive after a phase-mapping run; a challenge-turned
  matrix position shows its disks as unexplained — the challenger's axis is not recorded) and the Al–Mg–Si preset.

### S5 Sessions & sidecars: residuals (the guard, cancel token and reopen fixed 2026-09-30)
- **A superseded load's tail still runs `discardPartialLoad`** (`AppState+Open.swift:810`) over whatever load is current;
  the owned cancel token (S5) stops it clearing busy, not the reset. Needs two loads in flight (promote/replay).
- **Fabricated provenance on pre-2026-08-18 sidecars**: `AppState+Open.swift:700,893,906` `?? .fullExtent`. Needs a synthesised sidecar.
- **Promote/replay**: (a) promote lands at (0,0)? (b) fitted origin maps refuse the full-extent restore's shape check; (c)
  parallax/ptychography not in the replay record; (d) a user analysis mid-replay steals Cancel; (e) replay contracts in three places.
- **Resident**: "freed" bytes never measured; the reopen fix has no test (the recovery store is real `UserDefaults`). UX: a retarget before any save lasts one dataset change; pre-S4 calibration-only sidecars unrecognisable;
  `calibration.*` identifiers doubled under the export sheet; Recents labels "This Mac". (`.h5.h5`: fixed 2026-09-09, `a8b13c6`.)

### S6 closed 2026-09-30 (driven); what the drive found next
- **No workflow logic in the rooms** (2026-09-29): judged against the 2026-09-21 critique — closed, the rooms carry the
  calibration rows, one verb each and the readiness line.

## Waits on hardware or the owner

### Waits on the stronger Mac: parallax/ptychography and the 28 GB parity run
- **Parallax and ptychography** need 8–11 GB for a 268 MB cube (30–40×): true cost or an over-estimate? A Gate D, not a knob.
  Both ship **undriven on real data** (release notes say so). Owner (2026-09-28): drive both there, then keep or remove.
- **The 28 GB `--parity` run** (`almgsi-gateD-2026-09-24.md` 6, 8). The DM4 reader maps on every `MNT_LOCAL` volume
  (`DM4Reader.readingOptions(forPath:)`; the SSD proved at 3–53 MB, `archive/v4/ssd-subsample-2026-09-29.md`). **Trap: never open
  a file over ~2 GB through an unproven path on the 8 GB Mac** (it kernel-panicked 2026-09-24). Residuals: a vanished volume is a
  SIGBUS crash with no dialog; network volumes keep the old full read.

### Training (ADR 043/048): the app's step loop leaks — Gate D open (2026-09-30)
- The headless C5 run through the app's Training/ path grew linearly, 227 MB (step 1) → 1313 (100) → 2404 MB (200),
  ~11 MB/step, and was stopped when swap filled the disk; the spike's step is flat at 1.48 GB (C2.5). The in-app
  Train Model… (`aa920d0`) shares the loop: do not train in the app until this closes. Mechanism not yet established.
  Log: `archive/v4/c5-training-leak-run-2026-09-30.log` (admission refused 8× at 2.16 GB needed, then the run started anyway).
- **Detector truth** (A2, `tools/disk-detector/labels/bullseye-2026-09-28.json`, 370 centres re-labelled by eye, owner-approved;
  `archive/v4/a2-label-scoring-2026-09-28.md`): net 0.584 / 0.655 at 0.7, 2 px; label-vs-net scatter 1.2 px. **Owed:** an
  inter-labeller check; the classical floor at the app's own settings. The in-app labelling route is untried on real data.

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
`#31` `validationIssues` is O(n²) in a SwiftUI view body, not cached. `#32` `isSymmetry`'s bijection check has no fixture. `#30`
origin calibration over a NAS ran at ~3 MB/s (2026-08-06). C3 drive leftovers: staleness (f); "Fit Detector Ellipse" on the demo
ending "residual is too large (0.247)". HDF5 runs under one lock: thread-safety rests on one 2026-08-19 `nm` inspection
(`H5is_library_threadsafe` called nowhere); a sidecar write can block a caller for seconds. Standing limits: ptychography pads
both object axes (`DEVIATION`); `bragg-spacing-probe` and `residency-sweep` need multi-GB data and stay diagnostics.

### Acceptance-harness gaps — red gate names the symptom, counts not positions, thin infrastructure (2026-09-02/09)
- **Symptom, not cause; one harness reaches it**: `compare.py`'s `fail()` raises at the first mismatch (cheap fix: collect
  all); `real-data-acceptance/run.sh` is the only harness `all` reaches — `scientific` stayed green three days past `ba6360d`.
- **Counts, never positions**: `AcceptanceReport` has no coordinates; on `ba6360d` one peak moved ~26 px, count unchanged.
- **Infrastructure**: empty-glob SKIP exits 0; the 15 s budget gates 4 pinned datasets only; virtual-image `abs_tol` exceeds one
  fixture's range; `rel_tol` on `diskProbeRadiusPixels` is inert below 50 px; `if not actual:` is unkillable; the runner aborts
  at the first red harness.
- **Learned-detector parity is a same-runtime claim**: skips where no Neural Engine is listed (bars not loosened); a
  CPU-written second fixture would make it a check. With CI's unit job paused (ADR 040) every green gate is local.

### Accessibility (does NOT block a release — owner decision, 2026-09-11)
A live defect, not VoiceOver-only: any AX client resolving labels on the front window trips it and it crashed the owner's
session twice on 2026-09-08 — `EXC_BAD_ACCESS` at a stack guard page in `AccessibilityNode.accessibilityLabel()` →
`labelsToResolve` → `resolvedRole(forPlatformElement:)`. **In-body controls report no accessibility label — same bug:**
`Compute Mean / Max`, `Fit Detector Ellipse`, both image-pane buttons, every `Advanced` disclosure are bare. One Gate D, not
two fixes. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### The audit's refactor list, rows 4–13 — most parked
Open: row 4 (a shared harness `fail` helper — Gate B, a shared bug can green 46 harnesses); rows 6–7, the
**resultexport-split and braggvector-emd-writer-split**, each prepared and parked (the HDF5-adjacent split: four
ResultExport files, `sessionPixelCalibration` single-sourced; the writer by dataset kind, each file `nonisolated`-verified by a
cold build) — a session with Gate B support; row 12 (the >1 000-line harness mains). **Row 9 is a do-not:** five `median`
bodies in Core stay separate until a Gate D shows they should agree (ADR 015). Detail: `archive/open-items-detail-2026-09-18.md`.

### Minor tooling/hygiene residuals
`tools/free-space.sh`: the temp prefix is spelled by producer and reaper separately and the MCP root is hardcoded — a `tools/lib/`
constants file is deliberately NOT taken (a bad line there kills every gate). `.fixedSize()` in `UI/`: 20 call sites
(2026-09-29) against the constraint-loop rule, one armed — the zoom badge (`ImagePanes.swift:639`) inserts/removes a child
mid-pinch; not urgent.
