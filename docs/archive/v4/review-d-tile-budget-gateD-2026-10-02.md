# Lane D report — large cubes (d1 Gate D, d4 caption)

## Summary
d1 (Gate D): FourDArray.scanTileRows now budgets a tile at the reader's pre-bin READ extent, so binned H5 / scan-fastest DM4 tiles stay within budget (was bin² over); bin 1 byte-identical by construction and by test.
d4: the keep-in-memory refusal caption names the bound that actually refused (GPU working set or largest single GPU buffer) with its value.
7 new tests, each red on its mutation and green after (test-1/4/5/6 red, test-7 green); app build 0; core 0; inventory 0 (working tree); 5 harnesses exit 0.

## Diagnosis (Gate D, d1) — 2026-10-02
Claim under test: `FourDArray.scanTileRows` sizes a tile from POST-bin bytes (`descriptor` = view.descriptor, the binned extent),
while some readers allocate the PRE-bin tile before `view.binned()` reduces it, so the bounded transient is bin² × budget.
Candidates and the observation that settles each (all read at HEAD b3461496):
1. "No reader allocates pre-bin per tile" — REFUTED: H5Reader.read() (H5Reader.swift ~:720) allocates
   `slab.count.reduce(1,*)` floats, the hyperslab built at the READ (pre-bin) detector extent over every tile row, then bins at :730.
   DM4 scan-fastest: `scanFastestGather` allocates `count * height * width` at readDetectorCrop extent (pre-bin) for the whole tile.
2. "The DM4 detector-fastest headline (5.7 GB at bin 4) holds" — REFUTED (verifier is right): LoadSpecification.swift:317 sets
   `readDetectorCrop` non-nil whenever bin > 1, so `rowsAreContiguous` is false for every binned view and detector-fastest DM4
   takes the per-row/per-pattern path (buffer reserved at view extent). Vendor raw (EMPAD, MIB) and Demo also read row-by-row
   into a post-bin buffer: bounded.
3. "scanTileRows already accounts for bin" — REFUTED: FourDArray.swift:367 `bytesPerRow = descriptor.rx*descriptor.qy*descriptor.qx*4`,
   no detectorBin / readDetectorCrop term.
Survivor: binned H5 views and binned scan-fastest DM4 views allocate bin² × the per-tile budget (verifier numbers: 8 GB Mac,
256²×256² at bin 4 → 85 rows → ~5.5 GB pre-bin [Float]; bin 8 → rows clamp at ry → whole cube).
Fix: bytesPerRow from the READ extent: rx × (readDetectorCrop?.height ?? source.qy) × (readDetectorCrop?.width ?? source.qx) × 4.
For bin 1 the read extent IS the descriptor extent (readDetectorCrop nil → source == descriptor qy/qx; a bin-1 detector crop has
readHeight = crop height = descriptor.qy), so bin 1 is byte-identical by construction. For bin b the read extent is exactly
(b·qy_view)×(b·qx_view), so rows_new = floor(budget / (b²·post)) = floor(floor(budget/post)/b²) — "divide by bin², floor, ≥ 1".
Note: the bound applies to every reader, including the ones already bounded (detector-fastest DM4, raw); they get bin²-smaller
tiles (more, smaller reads; no memory cost). Reader-aware sizing would be new surface; not done.

## Predictions (written BEFORE any run) — 2026-10-02
P1 (order dependence). Tile size only changes numbers in reducers that COMBINE partials across tiles:
  `tiledDPStatistics` (mean pattern: weighted float sum across tiles — order-dependent; the max pattern is order-independent,
  max is exact), `tiledDiffraction` (running sum — order-dependent), `DiffractionEmbedding` (OuterProductAccumulator across
  tiles — order-dependent). Per-position reducers are tile-invariant: virtual images (`virtualMaskSum`/`virtualAperture`,
  one thread per scan position, ResidentCube.swift:11-17), measured origins, CoM, Friedel origins (OriginCalibration:
  per-pattern), classical/learned disk detection (per-pattern). So virtual images and origins: 0 bits move.
P2 (how many bits on a binned view). Only when the binned view's ry exceeds the NEW budget rows (b² times fewer rows) does the
  grouping change; then the mean/sum reducers move in the last ~1-3 float32 ulps (relative ~1e-7, the same class as the Gate B
  8.5231 vs 8.5035 grouping note in FourDArray's comment — that one was a summed quantity downstream). Not measured on a real
  binned H5 here (no such cube in the lane); stated as prediction, not result.
P3 (bin 1). Byte-identical: identical row counts for every bin-1 view (full extent and detector-cropped), so identical numbers.
P4 (harnesses). preprocess-crop-bin-test, virtual-detector-test, tiled-detection-memory-test, virtual-detector-memory-test,
  resident-cropped-view all EXIT 0 and print the same PASS lines as before: every one either pins `maximumRows`/`maximumTileRows`
  (1, 2 or 8) — a path this change does not touch — or uses cubes whose whole scan fits one tile under either formula.
  Hence they cannot SEE this change; the unit test below is what discriminates (stated so nobody reads their green as evidence).
P5 (unit test, ReviewTileBudgetTests): at HEAD the bin-4 view's rows == 16 × (floored) the bin-1 view's rows → RED; after the fix
  bin-4 rows == bin-1 rows (same read extent) and rows × rx × readH × readW × 4 ≤ min(gpu/8, phys/24) → GREEN.

## Diagnosis (d4, not Gate D: wording, mechanism proven by reading) — 2026-10-02
PendingLoad.swift:429 refuses on `bytes > min(limitBytes, maxBufferBytes)`; LoadConfigurator.swift:147 always says "GPU
working-set limit". Confirmed. The existing `case refused` is compared with `==` in KeepInMemoryTests.swift (outside my
write-set), so an associated value would break that file's compile; instead the enum gets a pure `refusingBound(...)` that
`decide()` itself uses (one source of truth) and a pure `refusalCaption(cubeBytes:bound:)`.

## Runs
- 2026-10-02 test-1 (HEAD formula, new ReviewTileBudgetTests d1 tests only). Prediction: build succeeds; testBinnedTileIsBudgetedAtTheReadExtent FAILS
  (bin 2/4/8 rows = 4×/16×/64× bin-1 rows); testRemainderTrimmedReadExtentSetsTheBudget FAILS; testBinOneRowsUnchanged and
  testMaximumRowsStillWins PASS. Expected EXIT=65.
- test-1 result: EXIT=65; failed testBinnedTileIsBudgetedAtTheReadExtent + testRemainderTrimmedReadExtentSetsTheBudget; passed
  testBinOneRowsUnchanged + testMaximumRowsStillWins (test-1.log). As predicted.
- 2026-10-02 test-2 (d1 fix + d4 fix, all 7 ReviewTileBudgetTests). Prediction: all 7 pass, EXIT=0.
- test-2 result: EXIT=65 — a BUILD failure in another lane's in-flight ResultExport.swift (no member 'sidecarHoldsUnrestoredLabels'),
  not this lane. From here every run is in an isolated copy ($SP/D/iso/mac4DSTEM = git archive HEAD + this lane's 4 files + References symlink).
- 2026-10-02 test-3 (isolated copy; ReviewTileBudgetTests + KeepInMemoryTests). Prediction: 7 + 5 = 12 tests pass, EXIT=0.
- test-3 result: EXIT=0, 12 "passed on '" lines, 0 failed (test-3.log).
- 2026-10-02 test-4 (isolated copy, MUTATION A+C in refusingBound: always `.workingSet(limitBytes)`, and `>=`). Prediction:
  testRefusalBetweenTheBoundsNamesTheSingleBuffer FAILS (A), testRefusalAndBoundAgreeAtTheEdges FAILS (C, cube == limit);
  KeepInMemoryTests.testRefusedOnlyAboveTheGPUWorkingSetLimit also FAILS (C, "at the limit is still allowed");
  the d1 tests and testRefusalBelowASmallerWorkingSetNamesTheWorkingSet pass. EXIT=65.
- test-4 result: EXIT=65; exactly the three predicted failures, 9 passed (test-4.log).
- 2026-10-02 test-5 (isolated copy, MUTATION B: comparison inverted `maxBufferBytes > limitBytes`). Prediction: both bound-naming
  tests FAIL (each names the other bound); edges test and KeepInMemoryTests pass (decide unaffected). EXIT=65.
- test-5 result: EXIT=65; exactly the two predicted failures, 10 passed (test-5.log). PendingLoad.swift restored in the copy, cmp == working tree.
- 2026-10-02 test-6 (isolated copy, MUTATION D in scanTileRows: read extent = source qy/qx, ignoring readDetectorCrop).
  Prediction: testBinOneRowsUnchanged FAILS (bin-1 crop 100×120 budgeted as 256×256), testRemainderTrimmedReadExtentSetsTheBudget
  FAILS (250² instead of 248²), testBinnedTileIsBudgetedAtTheReadExtent passes (256 is a multiple of 2/4/8). EXIT=65.
- test-6 result: EXIT=65; exactly the two predicted failures, 5 passed (test-6.log). FourDArray.swift restored in the copy (cmp == working tree).
- 2026-10-02 test-7 (isolated copy, all lane files restored, ReviewTileBudgetTests + KeepInMemoryTests). Prediction: 12 pass, EXIT=0.
- test-7 result: EXIT=0, 12 passed, 0 failed (test-7.log). build-1 (isolated copy, app scheme, own derivedDataPath): EXIT=0 (build-1.log).
- 2026-10-02 harnesses (isolated copy, each through heavy.sh, logs h-<name>.log, exits in harness-exits.log). Prediction = P4:
  all five EXIT=0 with their usual PASS lines; none can see this change (pinned maximumRows or one-tile cubes).
- core (isolated copy): CORE_EXIT=0 (core.log). inventory in the isolated copy: exit 1 ONLY because the copy has no .git
  ("HEAD^ does not resolve", inventory.log) — not a finding; inventory in the working tree: INV_EXIT=0 (inventory-2.log).

## Changes
- mac4DSTEM/Core/Data/FourDArray.swift — `scanTileRows`: bytesPerRow from the READ extent
  (readDetectorCrop?.height/width ?? source.qy/qx) instead of the post-bin descriptor; comment says why and that bin 1 is unchanged.
- mac4DSTEM/App/PendingLoad.swift — `KeepInMemoryDecision`: new `Bound` (workingSet(UInt64) | singleBuffer(UInt64)), pure
  `refusingBound(...)` that `decide()` now refuses through (one source of truth), pure `refusalCaption(cubeBytes:bound:)`.
  Plus one computed (not stored) `PendingLoad.keepInMemoryRefusalBound` beside `keepInMemoryDecision`, same machine numbers.
  `case refused` kept bare so KeepInMemoryTests (outside my write-set) compiles unchanged.
- mac4DSTEM/UI/LoadConfigurator.swift — `keepInMemoryRow` caption only: calls `refusalCaption` with the bound. Cost: the caption
  gains the limit in parentheses (~11 characters, e.g. " (41.7 GB)"); in the sheet's wrapping caption that is at most +1
  caption line (~14 pt) on a refusal, 0 rows otherwise. Unknown size now reads "Size unknown; Load streams." (was "Zero KB is above…").
- mac4DSTEMTests/ReviewTileBudgetTests.swift — new, 7 tests (class ReviewTileBudgetTests). No pbxproj change (synchronised folder).

## Tests (all runs in the isolated copy except test-1, which ran in the working tree at HEAD's formula)
| test | mutation | red | green |
|---|---|---|---|
| testBinnedTileIsBudgetedAtTheReadExtent | HEAD formula (post-bin bytes) | test-1 EXIT=65 | test-7 EXIT=0 |
| testRemainderTrimmedReadExtentSetsTheBudget | HEAD formula; and source qy/qx ignoring the crop | test-1, test-6 EXIT=65 | test-7 |
| testBinOneRowsUnchanged | read extent = source qy/qx (fires at bin 1 with a crop) | test-6 EXIT=65 | test-7 |
| testMaximumRowsStillWins | guard only (green at HEAD and after, by design: pins the untouched parity path) | — | test-7 |
| testRefusalBetweenTheBoundsNamesTheSingleBuffer | refusingBound always `.workingSet` | test-4 EXIT=65 | test-7 |
| testRefusalBelowASmallerWorkingSetNamesTheWorkingSet | comparison inverted | test-5 EXIT=65 | test-7 |
| testRefusalAndBoundAgreeAtTheEdges | `>=` in refusingBound | test-4 EXIT=65 | test-7 |
test-7: 12 passed (7 + 5 KeepInMemoryTests), 0 failed. Every red run failed exactly the predicted tests.

## Deviations from the brief
- d4: decide()'s refused case does NOT carry the bound as an associated value: `.refused` is compared with `==` in
  mac4DSTEMTests/KeepInMemoryTests.swift (not in my write-set), which would stop compiling. The bound comes from
  `refusingBound`, which decide() itself calls, so they cannot disagree (pinned by testRefusalAndBoundAgreeAtTheEdges).
- PendingLoad.swift: besides the enum, one computed property `keepInMemoryRefusalBound` (not stored state) so the view does not
  read Metal device numbers itself.
- d1 low-bit measurement: no binned real cube large enough to cross the new tile boundary exists in this lane; P2 stays a
  prediction. The parity harnesses cannot see the change (P4) — the unit test is the discriminating evidence.

## Proposed doc lines
- open-items: close "binned view sizes tiles by post-bin bytes (bin² transient)" — fixed 2026-10-02, tiles budgeted at the read
  extent; bin 1 unchanged (ReviewTileBudgetTests). Residual: tiles of row-by-row readers (detector-fastest DM4, EMPAD, MIB) are now
  bin² smaller than they need be (no memory cost; more reads). Optional later: bin row-by-row inside H5Reader.read / scanFastestGather.
- status handoff/plan log: "Slot 4¾ lane D: d1 tile budget at read extent (Gate D, test red→green), d4 keep-in-memory caption names
  the bound that refused (working set or single GPU buffer, with its value)."

## Open questions for the supervisor
1. tools/origin-fit-diagnostics/coarse-cost.swift says it copies scanTileRows' formula "verbatim (FourDArray.swift:365-400)" — a
   diagnostic runner, outside my write-set; its copy is now the pre-fix formula (bin-1 identical, so its numbers stand for bin 1).
2. Binned numbers will shift in their low bits for mean pattern / diffraction sum / embedding on binned views whose ry exceeds the
   new (b²-smaller) tile — a release-note line may be wanted ("binned views: mean-pattern low bits may differ from 4.0").
3. Gate D asks for an independent refuter of the diagnosis; not run by this lane.
- harnesses (2026-10-02, isolated copy, harness-exits.log): preprocess-crop-bin-test 0, virtual-detector-test 0, resident-cropped-view 0,
  virtual-detector-memory-test 0, tiled-detection-memory-test 0; zero FAIL lines across h-*.log. As predicted (P4) — and, per P4, not evidence for d1.

## Files (all lane D)
mac4DSTEM/Core/Data/FourDArray.swift (scanTileRows) · mac4DSTEM/App/PendingLoad.swift (KeepInMemoryDecision.decide/Bound/refusingBound/refusalCaption; PendingLoad.keepInMemoryRefusalBound)
· mac4DSTEM/UI/LoadConfigurator.swift (keepInMemoryRow caption) · mac4DSTEMTests/ReviewTileBudgetTests.swift (new)

## git status --short (working tree, shared with other lanes, 2026-10-02)
 M README.md
 M SECURITY.md
 M docs/architecture.md
 M mac4DSTEM/App/AppState+DPC.swift
 M mac4DSTEM/App/AppState+DiffractionGroups.swift
 M mac4DSTEM/App/AppState+DiskDetection.swift
 M mac4DSTEM/App/AppState+MaterialsProject.swift
 M mac4DSTEM/App/AppState+Open.swift
 M mac4DSTEM/App/AppState+PhaseContrast.swift
 M mac4DSTEM/App/AppState+PhaseMapping.swift
 M mac4DSTEM/App/AppState.swift
 M mac4DSTEM/App/PendingLoad.swift
 M mac4DSTEM/App/ProductWorkflow.swift
 M mac4DSTEM/App/mac4DSTEMApp.swift
 M mac4DSTEM/Core/Analysis/ParallaxAlignment.swift
 M mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift
 M mac4DSTEM/Core/Data/BraggVectorEMDTypes.swift
 M mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift
 M mac4DSTEM/Core/Data/FourDArray.swift
 M mac4DSTEM/Session/DiskCentreLabels.swift
 M mac4DSTEM/Session/SessionCalibrationFramePolicy.swift
 M mac4DSTEM/Session/SessionGates.swift
 M mac4DSTEM/Session/SessionSidecarLocator.swift
 M mac4DSTEM/Support/ResultExport.swift
 M mac4DSTEM/UI/ImagePanes.swift
 M mac4DSTEM/UI/LoadConfigurator.swift
 M mac4DSTEM/UI/MapSettings.swift
 M mac4DSTEM/UI/PhaseMappingSettings.swift
 M mac4DSTEM/UI/ReconstructionSettings.swift
 M mac4DSTEM/UI/WorkspaceSidebar.swift
 M mac4DSTEM/UI/WorkspaceView.swift
 M tools/run-tests.sh
?? docs/archive/v4/owner-decisions-2026-10-02-review.json
?? mac4DSTEMTests/ReviewDataSafetyTests.swift
?? mac4DSTEMTests/ReviewLandingTests.swift
?? mac4DSTEMTests/ReviewPhaseContrastTests.swift
?? mac4DSTEMTests/ReviewSidecarIdentityTests.swift
?? mac4DSTEMTests/ReviewTileBudgetTests.swift
?? mac4DSTEMTests/ReviewUXTests.swift

## Fix round — 2026-10-02 (refuter: HOLDS_WITH_CORRECTIONS)
### MUST-FIX 1 — scope of the d1 claim (verified by reading the working tree, 2026-10-02)
Both sibling post-bin formulas exist and bypass the fixed `scanTileRows` budget:
- mac4DSTEM/App/AppState+ResultPresentation.swift:247-251 `virtualDetectorProgressTileRows`: rows from `descriptor.rx*qy*qx*4`
  (post-bin) against 16 MiB; passed as `maximumTileRows` to the five virtual-detector calls (:331/:336/:347/:354), which is the
  `maximumRows ??` override in scanTileRows — so the fixed budget never applies there. Pre-bin transient bin² × 16 MiB:
  64 MiB at bin 2, 256 MiB at bin 4, 1 GiB at bin 8 (per tile; the opening virtual-image pass). Bounded, but not by the budget.
- mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:546-551 `resolvedTileRows`: 64 MiB post-bin when `options.tileRows` is nil,
  which the app always passes (AppState+PhaseContrast.swift:96-100) → pre-bin bin² × 64 MiB, ≤ 4 GiB at bin 8.
Both files are outside lane D's write-set (ParallaxPreprocessing.swift is also being edited by another lane), so this lane does
NOT edit them; they are registered as the residual below, and the one-line close of the first is offered to the supervisor
(Open question 4). The Summary's "binned H5 / scan-fastest DM4 tiles stay within budget" is CORRECTED to: "tiles sized by
FourDArray.scanTileRows (mean/max pattern, diffraction sum, embedding, origins, Detect All, keep-in-memory fill) stay within
budget; the virtual-image pass and parallax preprocessing still size from post-bin bytes (residual, below)."
Corrected proposed doc lines (supersede the earlier ones):
- open-items: "Binned views, tile budget (2026-10-02): FourDArray.scanTileRows now budgets at the pre-bin read extent
  (ReviewTileBudgetTests). Residual: two sibling post-bin formulas — AppState+ResultPresentation.swift virtualDetectorProgressTileRows
  (16 MiB post-bin → ≤ 1 GiB pre-bin at bin 8, the opening virtual-image pass) and ParallaxPreprocessing.resolvedTileRows
  (64 MiB post-bin → ≤ 4 GiB at bin 8) — on H5 and scan-fastest DM4." (drop the first residual if the supervisor lands OQ4.)
- status handoff: "Slot 4¾ lane D: scanTileRows tile budget at the read extent (Gate D, red→green); the virtual-image and parallax
  tile formulas are the named residual; d4 caption names the bound that refused."

### Minor notes — predictions (written BEFORE the runs), 2026-10-02
- test-8 (isolated copy, MUTATION E: scanTileRows returns `min(ry, budgetRows)`, the `maximumRows ??` override dropped),
  ReviewTileBudgetTests only. Prediction: testMaximumRowsStillWins FAILS (rows = budget rows ≫ 3 on this Mac, not 3); the other 6 pass. EXIT=65.
- test-9 (isolated copy, mutation reverted + a scratch test that exists ONLY in the isolated copy, ScratchLaneDP2Tests):
  Demo cube 12×12×64×64 at bin 4 (view 12×12×16×16), tiledDPStatistics with maximumTileRows 12 (one tile, the old formula's
  grouping when the cube fits) vs 1 (twelve tiles, the bin²-smaller grouping), plus bin 1 (12 vs 1) as control.
  Prediction: maxDP bit-identical in all cases (max is exact); meanDP differs in at most the last 1-2 float32 ulps in some pixels
  — and possibly 0 pixels on this cube if its per-tile float sums are exact (Demo values may be small); cross-tile partials are
  combined in Double (VirtualDetector.swift:456-458), so only the GPU's within-tile float mean regroups. This is ONE dataset:
  the number is not a property of the method. ReviewTileBudgetTests 7 + KeepInMemoryTests 5 + scratch 1 = 13 pass, EXIT=0.

### Minor notes — results, 2026-10-02
- test-8 (mutation E, isolated copy): EXIT=65; exactly testMaximumRowsStillWins failed, 6 passed (test-8.log). As predicted —
  testMaximumRowsStillWins is now a real test (red on dropping the `maximumRows ??` override), no longer "guard only".
  FourDArray.swift restored in the copy; cmp == working tree.
- test-9 (isolated copy, reverted + scratch measurement): EXIT=0; 13 "passed on '", 0 "failed on '" (test-9.log).
  P2 measurement (test-9.log "P2 bin" lines; also p2-measure.txt), Demo cube, tiledDPStatistics, 1 tile vs 12 tiles:
  | view | maxDP pixels differing | meanDP pixels differing | max ulp | max relative |
  |---|---|---|---|---|
  | bin 1, 12×12×64×64 | 0 / 4096 | 3308 / 4096 | 10 | 9.29e-7 |
  | bin 4, 12×12×16×16 | 0 / 256 | 208 / 256 | 8 | 7.42e-7 |
  Prediction P2 ("last 1-2 ulps") was WRONG on magnitude: the regrouping moves the mean pattern by up to 8-10 float32 ulps
  (~1e-6 relative) on this cube; the max pattern is bit-identical, as predicted. One dataset only — a release-note line should say
  "binned views: mean pattern / diffraction sum may differ from 4.0 at ~1e-6 relative", not quote a bit count as a property.
  The scratch test existed only in the isolated copy and is deleted (count of Scratch* files in the copy: 0).
- Stale comment (refuter note 2): tools/origin-fit-diagnostics/coarse-cost.swift:30-36 "copies scanTileRows verbatim" — outside
  the write-set; already Open question 1. Bin-1 numbers it produced stand.
- core (working tree): CORE_EXIT=0 (core-2.log). inventory (working tree): INV_EXIT=0 (inventory-3.log).
- No repo file changed in this round: the four lane files are byte-equal to the isolated copy that ran test-8/test-9.

### Open question 4 (new) — supervisor's call, outside lane D's write-set
Close the virtual-image residual with one line in AppState+ResultPresentation.swift `virtualDetectorProgressTileRows`:
  `let bin = datasetSession.loadView?.specification.detectorBin ?? 1` and `bytesPerScanRow = descriptor.rx * descriptor.qy * bin
  * descriptor.qx * bin * 4`. Virtual images are per-position (P1), so no number moves; only the progress tick count on binned views.
  (`DatasetSession.loadView` exists: DatasetSession.swift:44; `LoadView.specification.detectorBin`: LoadSpecification.swift:86/236.)
  Not edited here. ParallaxPreprocessing.resolvedTileRows stays the residual (parallax mean is order-dependent; Gate D if changed).
- Amendment 2026-10-02 (to OQ4's last sentence, after reading ParallaxPreprocessing.swift:337-353): the parallax mean is NOT
  tile-order-dependent — pass 1 accumulates `detectorMean[q] += pixel` pattern by pattern in scan order on the CPU, the same order
  for any tile size. So a bin² term in `resolvedTileRows` would also move no number (memory only); it is still outside this lane's
  write-set and that file is being edited by another lane, so it stays the registered residual, closeable like OQ4 (not Gate D).
