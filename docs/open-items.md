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
S10 (2026-09-30): candidate A (zero-weight evidence) refuted at step 0; B (noise hit) left. T1's [0 -4 1] entry holds
30 first-order-Laue-zone reflections (`archive/v4/s10-s11-gateD-2026-09-30.md`) — the library comment is stale.

### Tiled GPU memory: classical fixed (A1); the learned loop measured flat 2026-09-30 (S11), the virtual-detector loops not
Classical and learned `detectAll` are gated by `tools/tiled-detection-memory-test` (classical: per-tile growth; learned:
per-tile footprint slope ≤ 0.25 tile/tile — each awaited Core ML batch drains the pool; `archive/v4/s10-s11-gateD-2026-09-30.md`).
**Owed:** one in-app learned Detect All on a multi-GB cube before the "don't run" warning lifts; `VirtualDetector`'s tiled
loops have the same shape (maybe the unexplained ≈ 0.93 GB baseline). D1: the shipped max(0.02 Å⁻¹, 1 px) tolerance fits
all four datasets (`archive/v4/phase-tolerance-results-2026-09-29.md`).

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

### S3 Prepare: the Friedel ETA's falling shape (speed fixed 2026-09-30)
- **Speed — fixed.** Gate D (`tools/origin-fit-diagnostics/run.sh friedel-timing`, Thronsen A 171², 128²): the app's
  Friedel pass runs at 3 572 positions/s at `-O` (cube in 8 s, footprint flat 753 MB) and 38/s at `-Onone` (765 s) — and
  the Debug app linked `DSTEMCore` built `-Onone`. Reads are not it (6 600–7 000 patterns/s, both builds; h5py 5 300+).
  `Package.swift` now builds both packages `-O` in Debug.
- **Open:** the drive's falling rate (329 → 106/s) was not reproduced — the `-Onone` probe starts slow and levels at
  38/s. Re-drive the owner's Debug build; if the ETA still wanders at 8 s, a trailing-window rate is the proposal.
- The manual Q field stays visible and editable after a new value (`d3-03b`).

### S4 Phases & precipitates: an uncalibrated run, tie order, the busy line, the recipe
- Fixed 2026-09-30: phase mapping and Find Matrix Zone Axis now require a physical Q scale (a prerequisite with its route
  to Prepare; a refusal line — unverified on screen). The stale zone-axis list still survives a calibration change
  (proposal: store the fit's scale beside `zoneAxisFits`). The "run-dependent tie order" was `tools/phase-map-probe`'s
  Dictionary, fixed; the app's own ranking is now a total order too.
- At 1000 pt a busy run clips the status text and hides the metrics line; the panes widen while busy so the inspector
  covers ~110 pt of the phase map (`report-drive3.md` step 4): metrics get truncation priority, split fraction constant.
- The owner's Al-Mg-Si recipe as a preset (`archive/v4/almgsi-raw-stride3-registration-2026-09-29.md`).
- **Owner request 2026-09-25, not in S4's scope:** mark on the CBED which disks each phase claimed — new surface: cost it, mock first.

### S5 Sessions & sidecars: residuals (the guard, cancel token and reopen fixed 2026-09-30)
- **A superseded load's tail still runs `discardPartialLoad`** (`AppState+Open.swift:810`) over whatever load is current;
  the owned cancel token (S5) stops it clearing busy, not the reset. Needs two loads in flight (promote/replay).
- **Fabricated provenance on pre-2026-08-18 sidecars**: `AppState+Open.swift:700,893,906` `?? .fullExtent`. Needs a synthesised sidecar.
- **Promote/replay**: (a) promote lands at (0,0)? (b) fitted origin maps refuse the full-extent restore's shape check; (c)
  parallax/ptychography not in the replay record; (d) a user analysis mid-replay steals Cancel; (e) replay contracts in three places.
- **Resident**: "freed" bytes never measured; the reopen fix has no test (the recovery store is real `UserDefaults`). UX: a retarget before any save lasts one dataset change; pre-S4 calibration-only sidecars unrecognisable;
  `calibration.*` identifiers doubled under the export sheet; Recents labels "This Mac". (`.h5.h5`: fixed 2026-09-09, `a8b13c6`.)

### S6 Inspector kit & view state, with the Frozen Shell residuals
- **View state has four owners**: 26 `@SceneStorage`/`@AppStorage` sites (2026-09-23), incl. `WorkspaceInspector.swift:50`'s
  `"ui2.inspectorTab"` relic; `PhaseSettings.swift` → `ReconstructSettings.swift` unrenamed (call site `WorkspaceInspector.swift:199`);
  no "Unvalidated" badge on the Info tab (`ProductInfoSections`, `:570`). `WorkspaceNavigation` does not own all 26.
- **Kit gaps**: `UI/InspectorRows.swift` has no adaptive `Menu` (Add Phase hand-rolled) and no warning-note variant; long labels
  wrap beside wide pickers (wording the owner's).
- Parallax "done" read from `parallaxSubpixel` alone at `WorkspaceView.swift:304` and `AppState.swift:1187` (cosmetic).
- **The 915-pt floor's residual, now seen** (S2 drive, `archive/v4/s2-workspaces-2026-09-30-shots/`): Show Sidebar at 915 pt
  with the app in the background did not grow the window; the layout stayed ~1190 wide, centred and clipped both sides at
  915 (`s2-02`), and left ~142-pt strips at 1470 until relaunch (`s2-05`). No abort. Diagnosis (read-only, PLAUSIBLE): the
  split pins detail 595 + sidebar 270 after an unfinished grow; `ContentView.swift:46` measures the rigid child, not the
  window, so the 1095-pt step-aside never fires. Proposal: measure the window (`maxWidth: .infinity` before
  `.onGeometryChange`). Owner: check R1 first — foreground Show at 915, then drag to 915 by hand (user-reachable?).
- The welcome's Recents list runs off the bottom at 915 pt: let it scroll.
- **No workflow logic in the rooms** (seen 2026-09-29, `d1-02/03`, `d1-04b`): the owner judges it against the 2026-09-21 critique, then close.

## Waits on hardware or the owner

### Waits on the stronger Mac: parallax/ptychography and the 28 GB parity run
- **Parallax and ptychography** need 8–11 GB for a 268 MB cube (30–40×): true cost or an over-estimate? A Gate D, not a knob.
  Both ship **undriven on real data** (release notes say so). Owner (2026-09-28): drive both there, then keep or remove.
- **The 28 GB `--parity` run** (`almgsi-gateD-2026-09-24.md` 6, 8). The DM4 reader maps on every `MNT_LOCAL` volume
  (`DM4Reader.readingOptions(forPath:)`; the SSD proved at 3–53 MB, `archive/v4/ssd-subsample-2026-09-29.md`). **Trap: never open
  a file over ~2 GB through an unproven path on the 8 GB Mac** (it kernel-panicked 2026-09-24). Residuals: a vanished volume is a
  SIGBUS crash with no dialog; network volumes keep the old full read.

### Training prerequisites (Session queue S12; ADR 043)
- **C2** (`archive/v4/c2-mlx-spike-2026-09-28.md`): MLX trains the shipped graph and its weights reach the ANE (15/15 convs);
  judged by detection on held-out labels. **Owed before C3:** a training step ≤ 2 GB (MLX peaked 2.78 GB at batch 8);
  criterion 4 through the app's Swift path.
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
