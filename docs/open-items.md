# Open items

Live defects, debts, owed runs and open questions only — status is `docs/status.md`, history is `docs/archive/`. Four lanes
(owner, 2026-09-03): **Science** items are taken one at a time in the order the status handoff names, carry no release
number, and a landed change to a scientific output cuts a release; **Verification debt** closes when its run happens;
**Known, scoped** items and the owner's bug reports ship in the next patch; **Code hygiene** rides with the session that
touches its file. Each entry is ≤ 12 lines and dated: what is wrong, the pinning evidence, the trap, the owner. No
narrative. Closed items: [`archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md). Text trimmed out of entries
(verbatim, 2026-09-29 night): [`archive/v4/open-items-detail-2026-09-29.md`](archive/v4/open-items-detail-2026-09-29.md); earlier
trims are the `open-items-*.md` files in `archive/` and its `v3/`, `v4/` folders. UI findings: [`archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3.

## Science & parity

### R–Q rotation in py4DSTEM's convention — fixed 2026-09-28 (ADR 040); residuals
One `RQRotationConvention` converts at every boundary; parity leg (b) gates (`archive/v4/rq-sign-gateD-2026-09-28.md`).
Residuals: a datacube exported by the app before 2026-09-28 and reopened is sign-flipped (re-export it);
`tools/training-dataset-campaign`'s report keeps the app's sign; the parallax fit's own rotation is untested against it.

### Origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay owed, still `validation:"none"`
`OriginMaps.originValidity` carries the robust trim's `kept` mask (disclosure only; ADR 033); the D4 count
(`PrepareSettings.positionsUsedValue`) is **unverified on screen**. Step-3 trim sweep, 4 cubes: excluded 0.6–15.7 %, `maxGap`
1–5, two cubes alike but spatially different. **Owed:** the spatial overlay (excluded positions greyed via
`DisplayedProduct.validityMask`), not built. Owner: unclaimed. Detail: `archive/open-items-detail-2026-09-18.md`.

### Parallax and ptychography are unrunnable on the owner's Mac — release-notes item
8–11 GB working set for a 268 MB cube (30–40×): true cost, or an over-estimate that refuses work the machine could do? A Gate D
of its own, not a knob to raise. Both ship **undriven on real data** and release notes say so. **Owed (owner, 2026-09-28):**
drive both on the stronger Mac, then keep or remove them. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Phase mapping under the T4 object bar (ADR 040) — one metric short
Raw speckle, not cleaned counts, certifies a classifier (`docs/cloud/2026-09-23/T2-direction-check.md`); the truth's cuts
(782 / 10 / 4 px) are that dataset's, never an app default. First scored run: FAIL on θ′ edge-on raw spurious 7 > 5.
B1 (`archive/v4/b1-edge-on-gateD-2026-09-28.md`, `b1-narrow-guard-2026-09-28.md`): 3 are edge calls 1–2 px from truth
needles, 4 real T1 → edge-on; a global guard breaks T1, the narrow one moves errors between classes — neither shipped.
The largest error class, T1 edges called Al (204), is mostly where the truth draws the edge (`t1-edge-detection-gateD`).

### Tiled GPU memory: classical detection fixed 2026-09-29 (A1); the learned and virtual-detector loops are not
Classical `TiledDiskDetection.detectAll` holds one tile (a pool per tile, and `findMaxima` survivors copied to their
own size); gated by `tools/tiled-detection-memory-test` (`archive/v4/tiled-detection-memory-gateD-2026-09-29.md`).
**Open:** `LearnedDiskDetection.detectAll(data:)` has the same per-tile `makeBuffer` in an async loop but awaits
Core ML inside, so a plain pool cannot wrap it — no learned Detect All Disks on multi-GB cubes until measured;
`VirtualDetector`'s tiled loops have the same shape (maybe the unexplained ≈ 0.93 GB baseline). The match tolerance was
measured overnight (D1, `archive/v4/phase-tolerance-results-2026-09-29.md`): the shipped max(0.02 Å⁻¹, 1 px) fits all four
datasets (raw cube 84.4 % matrix); the 97 % was the probe's rule. Owner: keep it (option a).

### Precipitate objects residuals — found driving the app, 2026-09-23/24 night
- **owner request 2026-09-25:** mark on the CBED which disks each phase claimed (matrix / each β″ slot / unexplained), like the Bragg-disk rings — new surface: cost it, then Prepare-style mock first;
- displayed numbers print "76.2" whatever the Mac's region: **declined by the owner 2026-09-28** (the app is English);
- zone-axis ties list in a run-dependent order (unchanged code, pre-e4 vs post-e4k0);

### Phase mapping runs on an uncalibrated cube and says nothing — owner's drive, 2026-09-24
`datasetA_stride3.h5` has no calibration; Map Phases ran with Q unset (scale bars "20 px", fallback `ImagePanes.swift:298`) and
returned 29 241 / 29 241 not indexed, every phase 0; Find Matrix Zone Axis "at chance". Q 0,1904 nm⁻¹ and Map Phases re-run (no
re-detection): T1 3680 / θ′ 833 / matrix 22 068 / not indexed 2660. Owner: "add this later" — refuse, or say why, when Q is
uncalibrated; the stale zone-axis list also survives a calibration change.

### Diffraction groups in a Debug build — fixed 2026-09-28 (three Gate Ds); one test gap
Covariance, embed and projection moved to Accelerate (`archive/v4/embedding-*-gateD-2026-09-28.md`); 1 000 patterns at 32 × 32
in Debug: 90.7 → 1.02 s. **Gap:** no shipped test reaches the two-pass path (cube cache > 512 MB). **Owed (2026-09-28
clean-up):** profile diffraction groups (Release vs Debug, per phase) before deciding its fate.

### Phase mapping's matrix verdict is by exclusion, and the cross-phase winner ignores completeness — MEASURED, unwired candidate parked
`Core/Crystal/PhaseVectorMatching.swift`: `minimumVectors` = 2 (`:73`, applied `:882`), so a position is "matrix" when almost
nothing survives removal, never because the matrix entry explains it; the best entry per phase is chosen by mean distance alone,
so a sparse precise match outranks a dense one (Gate B 2026-09-15: 0.004 two-vector beats 0.012 ten-vector). The count-aware
candidate (`completenessAwareCrossPhaseRanking`, `:182`, off) is byte-identical on the demo cube on or off — no regression, not an
improvement; Thronsen is not a valid second measurement (T1 reference already known wrong); step 3 stride-3 sits outside every
threshold tried (98.26 % shipped; 26.2–26.4 % at 1–10 %). Gate D before any edit. Owner: unclaimed.
Detail: `archive/v3/step3-2026-09-16.md`, `archive/v3/open-items-detail-2026-09-16.md`.

### T1 [0 -4 1] not-indexed pairs are detection noise, not origin or reference — measured 2026-09-17/21, lever choice owed
252 not-indexed T1 positions each leave one real {200} Friedel pair 2.5–5.2° off antiparallel (`containsFriedelPair` false); a
per-position origin recovers 10 % (centroid noise, not origin error); missing (2026-09-21) are the weak {014}/{214} families
under the 5 % floor; py4DSTEM's ACOM labels 100 % of them Al — validates matrix removal, not a lever. Levers, each its own Gate D:
better centroiding; looser antiparallel tolerance (~half, more Al false positives); accept detection-limited recall.
Owner: which lever, if any. Detail: `archive/open-items-detail-2026-09-18.md`.

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

### Precipitate segmentation defects — the image `segment` path, unwired; the class-map path is wired (ADR 038)
`PrecipitateSegmentation.segment` only (owner: whether/how to fix, not urgent while unwired): a
large contiguous NaN region survives imputation; NaN on a feature erases it silently; two
one-token mutants (robust sigma, fill statistic) leave every test green; dark ridges register
via their flanks. Shared `measure`: a negative peak collapses an object to 1×1 (no fixture).
Full wording: `archive/open-items-detail-2026-09-23.md`.

### Other named science residuals
One line each; full wording `archive/v4/open-items-detail-2026-09-25.md` (earlier: `archive/open-items-detail-2026-09-23.md`).
- Al-Mg-Si peak set: 39 % explained by the best Al orientation (2026-09-12) — detection, not the matcher.
- β″ zone axes presented under ⟨110⟩Al unanswered (known, scoped).
- Hexagonal IPF key may be labelled the wrong way round (2026-09-11) — settle, pin with a test.
- Single-slice ptychography export guard may miss its mode (`ResultExport.swift:1506`; old `:1627`/`:1478` gone) — Gate D.
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

## Data, IO & sessions

### Full-cube Friedel origin calibration: no plateau any more, but the ETA only grows (drive 2, 2026-09-29 night)
The 2026-09-19 fix holds on Thronsen A (171², Debug build): progress moves and Cancel works. New: the rate falls from
329 to 106 positions/s over the first 12 000 positions, so the ETA rises (58 s → 2:39) and never settles; progress is
bursty (≈ 20 s stalls at one count); Cancel takes ≈ 20 s to land (`report-drive2.md` step 7, shot
`archive/v4/overnight-2026-09-29-shots/d2-07b-friedel-later.jpg`). Cause not established (Debug `-Onone`? tile
reads? the stall pattern) — a Gate D before any change. Proposal once diagnosed: an ETA from a trailing-window rate.

### An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07)
Agent drive (`drive/shots-c3/b2-qr-unset-bug.png`): with Q "From file", typing `0.2` in Prepare's Manual field entered nothing
(locale wants `0,2`; the period dropped silently); Return on the empty field flipped the row to "Not set" and the bar `0.5 Å⁻¹` →
`5 px`. Gate D owes: why a period is rejected rather than parsed; whether an empty entry clears or restores the file value. Not
re-checked since the v4 Prepare rebuild. Owner: `/diagnose`.

### HDF5 runs under one lock — what that still costs (fixed 2026-09-15 late night)
Costs: a caller blocks for one operation (a sidecar write can be seconds); the two `dlopen`s stay two; no unit test can
crash-test it. **Residual:** thread-safety rests on one 2026-08-19 `nm` inspection; `H5is_library_threadsafe` is called nowhere.

### resultexport-split and braggvector-emd-writer-split — both prepared and parked, Gate B support owed
`Support/ResultExport.swift` and `Core/Data/BraggVectorEMDWriter.swift` are the two largest wire-format-risk files; one
zero-behaviour extraction each landed (`+Rendering.swift`, `BraggVectorEMDTypes.swift`). **Parked:** the HDF5-adjacent split (four
ResultExport files, `sessionPixelCalibration` single-sourced; the writer's `H5Fcreate`/`H5Dwrite` by dataset kind, each new file
`nonisolated`-verified by a cold build). Owner: a session with Gate B support, or authorize a refuter. Detail: `archive/open-items-detail-2026-09-18.md`.

### C2 spike failed as registered; the ANE bar replaced by detection (ADR 043), two items owed (2026-09-28)
MLX trains the shipped graph and its weights reach the ANE (15/15 convs), but criterion 1's 1e-2 sits below the ANE's own
fp16 error on the fixture (0.0355 shipped weights, 0.0591 fine-tuned); MLX's training peak is 2.78 GB at batch 8; in-memory
injection is 3.2× slower (the on-disk package 1.00× but ≥ 0.056 off on the ANE); criterion 4 (the app's Swift path) not run.
Owner chose 2026-09-28: judged by detection on held-out labels (ADR 043). **Owed before C3:** a smaller training step
(≤ 2 GB); criterion 4 through the app's Swift path. Record
`archive/v4/c2-mlx-spike-2026-09-28.md`.

### The detector's real-data truth re-labelled and committed (A2, 2026-09-28); not yet scored
The owner's 306 labels (sha `3c43e89d…`) were lost while `.gitignore:44` ignored them; the line is gone. The same
40 seed-1 bullseye positions were re-labelled by Claude by eye (no detector consulted), approved by the owner on the
review sheet, central beam kept: 370 centres, 148 in the central 128 px (`tools/disk-detector/labels/bullseye-2026-09-28.json`).
Scored 2026-09-28 (`archive/v4/a2-label-scoring-2026-09-28.md`): net 0.584 / 0.655 at 0.7, 2 px; label-vs-net scatter
median 1.2 px, no offset, so label precision is a confound. **Owed:** an inter-labeller check; the classical floor at the
app's own settings (at `evaluate.py`'s the 70-peak cap binds). The in-app labelling route is still untried on real data.

### DM4 on external volumes — fixed and proved small 2026-09-28; the 28 GB parity run owed
`.mappedIfSafe` read whole files into anonymous memory off any removable or network volume; on 2026-09-24 the
owner's 28 GB raw DM4 (exFAT/FSKit SSD) **kernel-panicked this 8 GB Mac**. **Trap: never open a file over ~2 GB
through an unproven path here.** Fixed: `DM4Reader.readingOptions(forPath:)` maps on every `MNT_LOCAL` volume
(128 MB fixture on an exFAT image: +128 MB before, +0 after; Gate B, inventory pins `init`). Residuals: a vanished volume is a SIGBUS crash with no dialog; network volumes keep the
old full read. 2026-09-29: the physical SSD is proved directly (footprint 3–53 MB opening and subsampling the 28 GB
file, `archive/v4/ssd-subsample-2026-09-29.md`). **Owed: the 28 GB `--parity` run** (`almgsi-gateD-2026-09-24.md` 6, 8).

### The sidecar reader has D003's missing attribute-length guard too (2026-09-09)
`H5Reader.swift` fixed D003 (`elementCount == 1` guards, `:897/:949/:965`); `BraggVectorEMDWriter.swift`'s `readStringAttribute`
(`:2453`) still calls `H5Aread` with no type/extent check (measured originally: 24 bytes into 8; 32 into 9). Same fix
(`H5Aget_space` + `elementCount == 1`). Owner: a patch session.

### Scan-fastest DM4 detector pair may be transposed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps tags `[Rx, Ry, Qy, Qx]` (pattern 480×448); a transposed pattern silently
flips strain axes and R–Q rotation. Owed: the owner reads width/height in GMS — if 448 wide, flip `DM4Reader.scanFastestStrides`
(`:194`) and pin an ncempy checksum. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Load/promote/replay trust residuals
- **Fabricated provenance on pre-2026-08-18 sidecars**: `AppState+Open.swift:700,893,906` do `snapshot.loadSpecification ??
  .fullExtent`, asserting full-extent for an unknown-era crop. Needs a synthesised sidecar. Unowned.
- **Cancel can vanish mid-load** (the open/promote unwind is sixfold): `DatasetSession.finishLoading()`
  (`Session/DatasetSession.swift:104`) unconditionally nils `loadCancellation`; with two loads in flight the first tail to finish
  disarms Cancel for the second. No fixture. Owner: whichever session next touches any of the six.
- **Promote/replay**: (a) promote: carry scan position, or land at (0,0)? (b) fitted origin maps refuse the full-extent restore's
  shape check, unexplained; (c) parallax/ptychography not in the replay record; (d) a user analysis mid-replay steals Cancel;
  (e) per-kind replay contracts live in three places held together by tests.
- **Reopen dead-ends after a failed recent**: `openRecent` (`AppState+DatasetSession.swift:11`) drops the entry but `reopenLastDataset` (`:37`) still says "No recoverable dataset." Unowned.
- **Resident/streaming**: `releaseResident()`'s "freed" is a derived byte count, never measured (a leaked `MTLBuffer` is invisible to tests); resident cancellation is 2.5× coarser than streaming (academic: nothing requests `.resident`).

### Sidecar/session UX residuals, mostly small
A sidecar retarget made before any save survives only until the next dataset change. Repeating "Save Session Sidecar
As…" can prefill a doubled `.h5.h5`. Pre-S4 calibration-only sidecars stay unrecognisable (owner: open-panel filter).
`calibration.*` accessibility identifiers are emitted twice while the export sheet is open. Seen 2026-09-29 night:
Recents location labels ("This Mac", `d1-01`); the manual Q field stays visible and editable after a new value
(`d3-03b`). Fixed and seen 2026-09-29 night (drive 5): an unchanged manual Q/R value no longer flips its source to
"Manual"; a Manual value's help says "Your value. Entering another replaces it." Owner: unclaimed.

### Misc data-layer items, low priority
`#31` `validationIssues` is O(n²) in a SwiftUI view body, called inline from `DiskDetection`/`TiledDiskDetection`, not
cached. `#32` `isSymmetry`'s bijection check has no fixture. `#30` origin calibration over a NAS ran at ~3 MB/s
(2026-08-06), uninvestigated. C3 drive leftovers, unprovoked: staleness (f); "Fit Detector Ellipse" on the demo ending
"residual is too large (0.247)". Standing limits, not gaps: ptychography pads both object axes (a `DEVIATION` note);
`.automatic` residency was dropped, not tuned (CLAUDE.md); `bragg-spacing-probe` and `residency-sweep` need multi-GB
data and stay diagnostics. A real load cancel was driven 2026-09-29 night ("Load cancelled", `d1-09c`).

## UI & on-screen

### Small things seen driving, 2026-09-29 night — each with a proposal (GREEN when taken)
- Voltage reads "0 kV" while readiness says "Accelerating voltage: Not set" (`d1-02`): an empty field, placeholder "Not set".
- At 1000 pt a busy run clips the status text on the left and hides the metrics line (zero width); the image panes
  widen while busy so the inspector covers ~110 pt of the phase-map pane (`report-drive3.md` step 4): give the status
  metrics the truncation priority, keep the panes' split fraction constant while busy.
- The welcome's Recents list runs off the bottom at 915 pt (drive 3): let it scroll.

### The panel overlap — a transient blank/black window, not diagnosed, parked 2026-09-22
Live on `datasetA_stride3.h5` (171×171): twice, during a calibration busy→idle toolbar transition, the whole window went blank
(menu bar only) for ~1 s, and a click during it still reached the app (one action ran twice). Not a `.zIndex`/`.offset` bug
(grepped). The guess — ADR 035's width budget recomputing per toolbar change — was deleted the same night but not re-tested on a
real cube; the owner has not seen it recur across the rebuild's drives (`413bcdc`). Owner: reopen with a screen recording if it
returns; `WorkspaceView.swift`/`ContentView.swift` are Frozen Shell regardless.

### View state has four owners, and three Frozen Shell residuals sit behind it — code hygiene
26 `@SceneStorage`/`@AppStorage` sites across `UI/` (2026-09-23 grep), incl. `WorkspaceInspector.swift:50`'s
`@AppStorage("ui2.inspectorTab")` — a deleted-UI2 relic, unrenamed because the file is Frozen Shell (ADR 035). Behind the same wall:
**`PhaseSettings.swift` → `ReconstructSettings.swift`** unrenamed (only call site `WorkspaceInspector.swift:199`) and **no
"Unvalidated" badge on the Info tab** (`ProductInfoSections`, `WorkspaceInspector.swift:570`: a `validation:"none"` product
reaches Info as one more Provenance row while Settings shows an orange warning). `WorkspaceNavigation` (104 lines) does not yet own
all 26 sites. Rides with the first Frozen Shell exception or the next room conversion. Owner: unclaimed.

### Inspector kit gaps — confirmed still open 2026-09-23
`UI/InspectorRows.swift` has no adaptive `Menu` (Add Phase stays hand-rolled) and no warning-note variant (`InspectorNote` is a
plain caption; orange captions and unvalidated badges stay hand-rolled, shape frozen). Long labels ("Measured kernel mode") wrap
beside wide pickers — wording is the owner's call. Scoped work, not bugs.

### No workflow logic in the rooms — seen on a real cube 2026-09-29 night; owner to confirm
Prepare on Thronsen A (`d1-03`, `d1-02`): the calibration rows in `stepOrder` (origin & probe, ellipse, R–Q, Q, R), each
with a state mark, its source and one verb, and the `readinessSummary` line ("Quantitative in 4 of 6 steps · still
needed: …"). Bragg disks the same shape (`d1-04b`). Owner: judge it against the 2026-09-21 critique, then close.

### Two pre-rebuild UI process gaps, still open
- **UI tests cannot see layout**: 33 UI-adjacent tests are pure functions; drives keep finding what they cannot (the
  2026-09-21 drive: eight defects under 844 green tests; 2026-09-29 night: the AI-room abort below ~1000 pt). Light mode
  on a real cube was seen 2026-09-29 (`d1-07a/b`, legible); a busy run at the floor could not be, the room aborts there.
- **UI docs written for agent continuity, not owner decisions**: `archive/v4/window-design.md` is 442 lines / 4 416
  words (2026-09-23). Next: brief + red-box screenshot + a 20-row element table; retire ADR 034's rejected half. Unclaimed.

### Cosmetic parallax-completeness disagreement, confirmed still present (2026-09-23)
`parallaxStage4IsComplete` (`PhaseSettings.swift:271`) fixed the checkmark, but two "is parallax done" checks still read
`parallaxSubpixel` alone: `WorkspaceView.swift:304` (Frozen Shell) and `AppState.swift:1187` (were `:309`, `:1236`). Cosmetic — the
dispatcher's own gate is correct. Owner: unclaimed.

### No automated visual baseline (2026-08-17), residual
Every acceptance run is numeric-only; driving is the only evidence anything looks right, and it keeps catching defects
under green gates. Seen since the v4.0.0 drive: light appearance on a real cube and a real load cancel (2026-09-29
night, session drives). Still never seen: the bounded promote run. Retired trap notes:
`archive/v2/visual-acceptance-checklist-2026-09-03.md`. Owner: one sitting.

### The 915-pt floor: fixed and seen on screen 2026-09-30 (owner's pick); one residual
The constraint-loop abort (`archive/v4/ai-room-narrow-crash-gateD-2026-09-29.md`) is closed in the room and the shell:
rows ≤ 248 pt (guard test), Info rows stack when they cannot share a line, the inspector's maximum fixed at 460 and the
sidebar stepping aside below 1095 pt (never returning by itself). Driven at 915 / 960 / 1150 / 1250 with the inspector
widest: no overflow, no loop. **Residual:** Show Tools on a narrow window relies on macOS growing the window (it did,
915 → 1190) — untested with the window against the screen's right edge.

### GitHub CI's unit job is paused until a macOS 27 runner exists (ADR 040, 2026-09-28)
The macOS 27 floor (v4.0.0) leaves the `macos-26` runner unable to build the app (target above its SDK); paused 2026-09-28
(`if: false`, `ci.yml`). Before that its Xcode 26.6 type checker timed out on `ContentView`'s file-importer closure (Xcode 27.0
compiles it); three `main` runs failed unread. Every green gate in `status.md` is a LOCAL run on Xcode 27.

### The 2026-09-09 register, triaged 2026-09-29 — 11 Gate D candidates hold and are reachable
All 156 clusters judged against `main` (`archive/2026-09-09-review/triage-2026-09-29.md`): 105 present in code, 22
closed, 8 duplicates; a refuter broke 4 of the 37 science rows and narrowed 15. Reachable with realistic data, each
its own Gate D: **D025** circle-ROI mask +0.5 px off the drawn ROI; **D023** empty positions add 3.4e38 to the strain
clustering median; **D019** one NaN pixel loses a pattern's peaks; **D079** parallax/ptycho take the aperture centre,
not the fitted origin; **D098**, **D004** learned-detector window effects over 256 px; **D068** calibration edits never
stale a strain map; **D017**, **D020**, **D006**, **D021** (see the record). Owner: order.

### The learned-detector parity fixture is a same-runtime claim; CI has no Neural Engine (2026-09-14)
`testLearnedPathMatchesPythonReference` failed on both runner jobs, passed locally; now skips (stated) where no Neural Engine is
listed; the 98 % bars were NOT loosened. A CPU-written second fixture would turn the skip back into a check. Owner: whether CI should verify this.

### Acceptance-harness gaps — red gate names the symptom, counts not positions, thin infrastructure (2026-09-02/09)
- **Symptom, not cause; one harness reaches it** (2026-09-08/09): `compare.py`'s `fail()` raises `SystemExit` at the first mismatch
  (cheap fix: collect all); `real-data-acceptance/run.sh` is the only harness `all` reaches — `scientific` stayed green three days
  past a real regression (`ba6360d`, 43 commits before symptom).
- **Counts, never positions** (2026-09-09): `AcceptanceReport` has no coordinates; on `ba6360d` one peak moved ~26 px, count
  unchanged, harness silent (likely two noise peaks trading places). Owner: a tolerance design pass.
- **Infrastructure** (2026-09-02): empty-glob SKIP exits 0 (should it consult `expected.json`?); the 15 s budget gates 4 pinned
  datasets only; virtual-image `abs_tol` exceeds one fixture's range; `rel_tol` on `diskProbeRadiusPixels` is inert below 50 px;
  `if not actual:` is unkillable; the runner aborts at the first red harness.

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — process trap (2026-09-12)
Twice a new test method was not discovered by XCTest: N-1 of N cases ran, suite reported success — reconcile the case count
against `func test` per file. A test appended "at the end of the file" can land in the wrong `XCTestCase` class and report
"TEST SUCCEEDED" having run zero cases — `grep -n "^final class\|XCTestCase"` first; grep the log for the test's own name.

### The published v2.5.1 artefact is universal but its libraries are arm64-only — status unclear, verify against the current release
`lipo -archs` on that build's executable is `x86_64 arm64` while all three embedded libraries are `arm64`, and `Info.plist` invites
every macOS 14 machine — every `.h5`/`.emd` open fails on Intel. Not re-checked against v4.0.0 (arm64-only, macOS 27 floor, per
`docs/decisions.md`), which superseded it — likely moot. Owner: confirm the current download; withdraw or annotate v2.5.1?

### Owed on screen from earlier drives (2026-09-09)
Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh, configurator single-pattern preview,
"No preview available") reaching the status strip, and the disk-centre label round trip (a click on the Metal/Canvas
pane: the owner's hand). Seen 2026-09-29 night: both Reset confirmations — "Reset recommended detection settings?" and
"Clear all calibration values?", each with Cancel (`d3-01b`, `d3-02a`).

### The three redistributed dylibs have no rebuild path (2026-09-09)
They came from Homebrew `hdf5 2.1.1` / `libaec 1.1.7` on one machine; nothing in the repo rebuilds them. Owner: whether a release
needs a rebuild script.

## Accessibility (does NOT block a release — owner decision, 2026-09-11)

Deferred to a far-future release but a live defect, not VoiceOver-only: any AX client resolving labels on the front window trips
it (blocking any automated driving rig) and it crashed the owner's own session twice on 2026-09-08. **Two crash reports (evidence
aged off 2026-09-15):** `EXC_BAD_ACCESS` at a stack guard page — overflow — in `AccessibilityNode.accessibilityLabel()` →
`labelsToResolve` → `resolvedRole(forPlatformElement:)` → AppKit, both while an AX client resolved labels on the front window.
**In-body controls report no accessibility label — same bug:** `Compute Mean / Max`, `Fit Detector Ellipse`, both image-pane
buttons, every `Advanced` disclosure are bare `AXButton`/`AXDisclosureTriangle` with empty title/description/value; AppKit-backed
toolbar items are fine. One Gate D, not two fixes. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

## Code hygiene

### The audit's refactor list, rows 4–13 — most parked, one closed off-list
Rows 1–3, 10 landed (`e415929`); row 8 closed 2026-09-17; row 5 (AppState seams) closed 2026-09-18 (`AppState.swift` 5476 → 1474 lines,
since regrown). **Open:** row 4 (a shared harness `fail` helper — Gate B, a shared bug can green 46 harnesses); rows 6–7 (the two
splits above); row 12 (the >1 000-line harness mains). **Row 9 is a do-not:** five `median` bodies in Core stay separate until a
Gate D shows they should agree (ADR 015). Owner: whoever picks a row. Detail: `archive/open-items-detail-2026-09-18.md`.

### Minor tooling/hygiene residuals
`tools/free-space.sh`: the temp prefix is spelled by producer and reaper separately and the MCP root is hardcoded — a `tools/lib/`
constants file is deliberately NOT taken (a bad line there kills every gate). `.fixedSize()` in `UI/`: 20 call sites at the
2026-09-29 re-grep (entry said 12 bare) against the constraint-loop rule, one armed — the zoom badge (`ImagePanes.swift:639`, was
`:587`) inserts/removes a child mid-pinch; not fixed deliberately, not urgent.
