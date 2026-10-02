# Lane C report — Slot 4¾ review fixes (b1 Gate D, d2 budget, b4 row)
Started 2026-10-02.

## Summary
(filled at end)

## Diagnosis (b1, Gate D)
Question: which sign convention does `ParallaxAberrationFitter.fitLowOrder`'s `rotationRad` carry, relative to the app's
calibrated `Calibration.rotationRad` (app-internal sign, RQRotationConvention.swift:12-22) and py4DSTEM's QR_rotation?
Code reading (before the experiment): the parallax path never reads the calibrated rotation (grep: `physical.rotationRad`
is stored by ParallaxPhysicalCalibration.resolve and read only by PtychographyPreparation.swift:334); the fit recovers the
angle from the shift field with py4DSTEM's labelling (qx = detector row, ParallaxAberrationFitting.swift:151-152).
`PtychographySettings.useParallaxFit` (App/PtychographySettings.swift:65-69) sets defocus = -C1 with no reference to any
rotation: the "apart" number CHOOSES NOTHING in code. It reaches science only through the user, via the .help at
ReconstructionSettings.swift:179 ("if the calibrated rotation is about 180° from the fit's, use the opposite defocus sign").
Candidates:
- H1 (verifier): fit is in py4DSTEM's sign (= -app). Then on a calibrated cube the status prints |θ_app - θ_py| = 2|θ|.
- H2: fit is in the app's sign. Then the status's "apart" is right but every displayed fit angle disagrees with Prepare.
- H3: neither — the fit's angle relates to the calibration by a 180° or 90° fold / transpose (the polar decomposition folds
  into (-90°, 90°] with a C1 sign flip, ParallaxAberrationFitting.swift:192-196), so the two conventions need a branch map.
Refuting observation for each: one synthetic weak-phase cube with a detector rotation planted at an asymmetric angle
(37°, not 0/90/180), run through BOTH the app's RotationCalibration and its parallax fit, and through py4DSTEM's DPC
rotation solve and Parallax fit (vendored References/py4DSTEM-dev @ f050d207). H1 is refuted if app_fit ≈ app_cal (mod 180);
H2 is refuted if app_fit ≈ -app_cal; H3 is refuted if either H1 or H2 holds within ~2°.
Experiment files (lane dir, not committed): C/gated/make_cube.py (py4DSTEM-side, writes cube.h5 + py4DSTEM's two angles),
C/gated/main.swift (app-side: H5Reader → CoM field → RotationCalibration.solve; preprocess → align (all levels) → fitLowOrder).

## Predictions
- 2026-10-02, before runs py-0 / py-37 / py-m37 (make_cube.py <rot> 500; logs C/gated/py-0.log, py-37.log, py-m37.log):
  py-0: py4DSTEM DPC ≈ 0° (±2°), Parallax rotation ≈ 0° (±2°), C1 ≈ -500 Å (convention_check measured -508.7 at this geometry).
  py-37: py4DSTEM DPC = s·37° ± 2° and Parallax = s·37° ± 2° with the SAME sign s (one of ±1, not predicted); C1 ≈ -500 Å
  (no fold: |37°| < 90°). py-m37: both flip to -s·37°.
- 2026-10-02, before runs app-0 / app-37 / app-m37 (C/gated/main.swift on the same cube.h5; logs app-0.log, app-37.log, app-m37.log):
  RotationCalibration = -(py4DSTEM DPC) ± 1° (ADR 040, rotation-parity leg b); fitLowOrder = py4DSTEM Parallax ± 1°
  (parallax-aberration-test parity) → app_fit = -app_cal, i.e. H1; HEAD's status line would print "74.00° apart" at 37°.

## Runs (Gate D experiment, 2026-10-02; files in C/gated/, py4DSTEM @ f050d207, python ~/miniconda3/envs/py4dstem)
| run | command | log | exit |
|---|---|---|---|
| py-0 | make_cube.py 0 500 cube-0.h5 | C/gated/py-0.log | 0 |
| py-37 | make_cube.py 37 500 cube-37.h5 | C/gated/py-37.log | 0 |
| py-m37 | make_cube.py -37 500 cube-m37.h5 | C/gated/py-m37.log | 0 |
| app-0 | heavy.sh run.sh cube-0.h5 0.04166667 1.5 80 | C/gated/app-0.log | 0 |
| app-37 | run.sh cube-37.h5 … | C/gated/app-37.log | 0 |
| app-m37 | run.sh cube-m37.h5 … | C/gated/app-m37.log | 0 |

## Measurements (b1)
| planted (scipy rotate on Qx,Qy) | py4DSTEM DPC (curl) | py4DSTEM Parallax rot / C1 | app RotationCalibration (internal) | app displayText (Prepare) | app fitLowOrder rot / C1 |
|---|---|---|---|---|---|
| 0° | 0.000° | -0.021° / -508.97 Å | +0.100° | -0.100° | -0.021° / -508.98 Å |
| +37° | -37.000° | -37.023° / -507.18 Å | +37.100° | -37.100° | -37.025° / -507.13 Å |
| -37° | +37.000° | +36.979° / -507.22 Å | -37.100° | +37.100° | +36.981° / -507.18 Å |
Verdict: H1 SURVIVES. The fit's rotation is py4DSTEM's sign (equal to py4DSTEM's own DPC and Parallax, and to what Prepare
displays); the app's calibrated angle is its negative. H2 refuted (app_fit = -app_cal, not +app_cal, at ±37°); H3 refuted
(no fold or transpose: agreement within 0.12° after one negation). Predictions held on every line (py s = -1).
Consequence at HEAD: on cube-37 the status would read "fit rotation -37.03°, calibrated rotation 37.10°, 74.13° apart"
for two angles that are the same branch (0.08° apart in one convention). The "Fitted rotation" row and the aberration-fit
status already print py4DSTEM's sign (no conversion needed there); only the calibrated half of the seed status was wrong.
Does "apart" choose anything? No code path: `useParallaxFit` sets defocus = -C1 unconditionally. It is a science number
only through the reader, via the .help that tells the user to flip the defocus sign at ≈180° — so a wrong "apart" near
|θ| ≈ 90° (prints ≈180°) would have led a user to flip defocus and reconstruct a conjugated object. SAY LOUDLY: the text
steers a defocus sign; an Opus/Fable refuter should check the fix.
- 2026-10-02, before test-1 (ReviewPhaseContrastTests, fixed tree, C/test-1.log): 5 tests, all pass, EXIT=0.
  (Level-2 refusal payload = 4S + fft exactly; held + peak identity holds.)
- 2026-10-02, before test-2 (mutation M1: AppState+PhaseContrast `let degrees = Double(rad) * 180 / .pi`, HEAD's line): EXIT=65,
  only testTheSeedStatusComparesBothRotationsInPy4DSTEMsSign fails ("calibrated rotation 37.10°", "74.13° apart").
- 2026-10-02, before test-3 (mutations M2+M3+M4 together, each in a different test: M2 `inputBytesCounted` returns
  preprocessing.stackByteCount for every level; M3 workingLimitBytes drops `- held`; M4 refusalMessage guard `residentCubeBytes > 0`
  only): EXIT=65, testAlignmentLevelTwoCountsThePriorItReads (refusal nil at 3S+fft), testTheWorkingLimitSubtractsWhatEarlierStagesHold,
  testTheAppCountsEveryHeldStackOnceDuringAlignment (limit and identity), testTheRefusalNamesTheHeldStacks fail; the b1 test passes.
- Results: test-1 EXIT=0 (5/5 passed, as predicted). test-2 EXIT=65, only the b1 test failed, as predicted; its xcresult message read
  "fit rotation -37.03°, calibrated rotation 37.10°, 74.13° apart" (and for the 80° case "160.10° apart"; for a TRUE opposite branch
  — py4DSTEM -100° vs fit +80° — HEAD printed "20.00° apart": HEAD also hid a real wrong branch). test-3 EXIT=65: three tests red as
  predicted, but PREDICTION MISSED on testTheAppCountsEveryHeldStackOnceDuringAlignment — it PASSED under M2+M3. Why: its limit
  assertion called the same (mutated) budget function on both sides, and under M2 the identity held + peak still equals the true live
  total (what M2 drops from the level's peak, the held term gains). The test as written could not catch the mutations it named.
- 2026-10-02 amendment, before test-4: the test is rewritten to test the app's own alignment-held function (extracted as
  `AppState.parallaxAlignmentHeldBytes`, used by alignParallaxNextLevel) and an explicit expected limit (half of RAM − held, computed in
  the test). Prediction for test-4 (mutation M5: `parallaxAlignmentHeldBytes` returns `phaseContrastHeldBytes`, i.e. no subtraction;
  plus M6: `phaseContrastHeldBytes` drops the alignment term): EXIT=65, testTheAppCountsEveryHeldStackOnceDuringAlignment fails, the
  other four pass. test-5 (restored): EXIT=0, 5/5.
- test-4 EXIT=65 as predicted (only the app-held test red; 4 others passed). Its xcresult was deleted before the message was read,
  so M5 alone is proven separately: 2026-10-02 prediction for test-5 (M5 only: no subtraction in parallaxAlignmentHeldBytes): EXIT=65,
  the app-held test fails at "level 1 reads the blended stack" (2S vs S); prediction for test-6 (restored tree): EXIT=0, 5/5.
- test-5 EXIT=65 as predicted: the app-held test failed at "level 1 reads the blended stack" (51200 vs 25600 bytes; S = 25600 here)
  and at the identity (219136 vs 167936). 2026-10-02 prediction for test-6 (restored tree; ReviewPhaseContrastTests +
  PtychographyProbeTests + PhaseContrastResidentBudgetTests + PhaseContrastMemoryBudgetTests + ParallaxAlignedMeanTests): EXIT=0,
  every case passes (the existing seed test's 0.10° / 179.90° cases are unchanged in py4DSTEM's sign; the 4 200-image level-1 run
  is unaffected because level 1 still counts 3S + fft).
- test-6 EXIT=0: 23 cases passed, 0 failed (C/test-6.log), as predicted.
- 2026-10-02 prediction for harness-align (tools/parallax-alignment-test/run.sh, which runs multi-level alignNextLevel at a 128 MiB
  limit and a 1-byte refusal case): exit 0, final line "all passed" — its fixtures are KB-sized, so 4S + fft stays far under 128 MiB.
- harness-align EXIT=0, "parallax-alignment-test: all passed" (C/harness-align.log), as predicted.

## Runs (gates)
| run | log | exit |
|---|---|---|
| test-1 ReviewPhaseContrastTests (fixed) | C/test-1.log | 0 (5/5) |
| test-2 M1 (calibration in app sign) | C/test-2.log | 65 (b1 test red) |
| test-3 M2+M3+M4 | C/test-3.log | 65 (3 red; app-held test wrongly green -> rewritten) |
| test-4 M5+M6 | C/test-4.log | 65 (app-held test red) |
| test-5 M5 alone | C/test-5.log | 65 (app-held test red: 51200 vs 25600) |
| test-6 restored, 5 classes | C/test-6.log | 0 (23 passed, 0 failed) |
| harness tools/parallax-alignment-test | C/harness-align.log | 0 |
| BUILD (lane dd) | C/build-1.log | 0 (two "failed with exit code 0" lines are pre-existing warning noise in DSTEMSession, not errors) |
| run-tests.sh core | C/core.log | 0 |
| run-tests.sh inventory | C/inventory.log | 0 |

## Summary
b1 (Gate D): measured on one synthetic cube with a planted ±37° detector rotation that the parallax fit's rotation is py4DSTEM's sign
(= py4DSTEM DPC and Parallax, = Prepare's display) and the app calibration its negative; the seed status now shows and compares both in
py4DSTEM's sign. d2: the budget subtracts the held preprocess + alignment stacks; a level-2+ alignment counts the prior it reads. b4: row removed.

## Changes
- mac4DSTEM/App/AppState+PhaseContrast.swift — usePtychographyProbeFromParallaxFit: calibrated angle via RQRotationConvention.displayDegrees
  (py4DSTEM's sign) for display and "apart"; comment cites the Gate D numbers. phaseContrastWorkingLimitBytes (now = (heldBytes:) of
  phaseContrastHeldBytes), new phaseContrastWorkingLimitBytes(heldBytes:), phaseContrastHeldBytes, parallaxAlignmentHeldBytes (computed,
  no stored state); presentPhaseContrastFailure(_:heldBytes:); alignParallaxNextLevel uses the alignment-held limit and names it on refusal;
  PhaseContrastMemoryBudget.refusalMessage(_:residentCubeBytes:heldProductBytes:) names the held stacks.
- mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift — PhaseContrastMemoryBudget.workingLimitBytes gains heldProductBytes (clamped, floor kept).
- mac4DSTEM/Core/Analysis/ParallaxAlignment.swift — ParallaxAligner.inputBytesCounted (new), alignLevel's peak = input (S at level 1,
  prior stack+masks 2S after) + 2S + fft (level 2+: 4S+fft, was 3S+fft); ParallaxAlignmentResult.heldByteCount (new); options doc line.
- mac4DSTEM/UI/ReconstructionSettings.swift — "Use Parallax Fit" .help names the convention (both py4DSTEM's sign, Prepare's R–Q
  rotation vs Fitted rotation); ParallaxAlignmentDetails: Shift-fit RMS row deleted (b4). UI cost: -1 inspector row; help/status 0 rows.
- mac4DSTEMTests/ReviewPhaseContrastTests.swift — new, 5 tests.
The "Fitted rotation" row and the aberration-fit status needed no change: the fit already is py4DSTEM's sign (measured).

## Tests
| test | mutation | red | green |
|---|---|---|---|
| testTheSeedStatusComparesBothRotationsInPy4DSTEMsSign | M1 calibration printed/compared in app sign | test-2 65 | test-1/6 0 |
| testTheWorkingLimitSubtractsWhatEarlierStagesHold | M3 held ignored | test-3 65 | 0 |
| testAlignmentLevelTwoCountsThePriorItReads | M2 inputBytesCounted = S at every level | test-3 65 | 0 |
| testTheAppCountsEveryHeldStackOnceDuringAlignment | M5 no subtraction (+M6 alignment term dropped) | test-4/5 65 | 0 |
| testTheRefusalNamesTheHeldStacks | M4 guard on cube only | test-3 65 | 0 |
b4 (row deletion): untestable (view text).

## Deviations from the brief
- d2 count is 4S+fft at level 2+, not the verifier's 5S: the prior's stack IS the level's input (ParallaxAlignment.swift
  `inputStack = previous?.shiftedStack ?? …`), so 3S already held one of the prior's two stacks; only its masks were missing. The app's
  alignment limit subtracts preprocess 2S + the whole prior level less what the level counts itself — total live at level 2 counted
  once = 6S + 2 planes + fft (testTheAppCountsEveryHeldStackOnceDuringAlignment pins the identity).
- The held term covers preprocess + alignment only (the brief's terms). KDE/depth/correction/ptychography products are not counted.

## Proposed doc lines
- status handoff: "Slot 4¾ lane C: seed status prints both R–Q rotations in py4DSTEM's sign (Gate D: fit = py4DSTEM sign, measured at ±37°);
  phase-contrast limit less held preprocess+alignment stacks; Shift-fit RMS row removed. Refuter on b1 pending."
- open-items (verification debt, the R1 branch item the refuter required): "Ptychography rotation branch: the defocus sign (−C1) holds on the
  fit's branch; nothing checks the calibrated rotation is on it — the seed status prints the angle apart (py4DSTEM's sign since 2026-10-02).
  Both solvers fold to a half-circle, so ≈180° apart arises only from an imported/hand-set rotation or near ±90°, where the fit's fold flips C1.
  No 180° case measured on data with truth."
- open-items (memory): "Phase-contrast budget: held products after the fit (KDE, depth planes, correction) and ptychography's prepared
  amplitudes + reconstruct working set (each checked against the same limit, both alive) are not summed. Refusal threshold only."

## Open questions for the supervisor
1. b1 is a science-adjacent text that steers a defocus sign via the .help: an Opus/Fable refuter should check the Gate D (C/gated/*.log,
   make_cube.py, main.swift) and the fix. Note HEAD also printed "20.00° apart" for a TRUE opposite branch (test-2 message), i.e. it hid real ones.
2. Near |θ| ≈ 90° both solvers fold (RotationCalibration −89…90°, the fit's (−90°, 90°] with a C1 sign flip), so two physically equal
   angles can read ≈180° apart AND the fit's C1 sign flips with the fold — the .help's rule is right there, but the reading is fragile. Owner card?
3. PtychographySettings.useParallaxFit doc comment (not my write-set) says the run uses `calibration.rotationRad`; still true, no change needed.
4. phaseContrastHeldBytes could live on Session/PhaseContrastProduct (the owner) — outside my write-set, so it is a computed var in the AppState extension.

## git status --short (whole tree; lane C's files: the four M files above + ReviewPhaseContrastTests.swift)
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

## Fix round (2026-10-02, refuter HOLDS_WITH_CORRECTIONS, two MUST-FIX)
### Item 1 — a re-preview was charged for the products it replaces
Chosen: release both products before the run (refuter's first option). New `AppState.releaseParallaxProductsForPreview()
-> (limitBytes, releasedPreview)` (computed, no stored state): nils parallaxAlignment (its didSet drops fit/KDE/depth/correction,
as a successful preview already did at the publish) then parallaxPreprocess, and returns the limit read AFTER the release, so the
order is fixed inside one function. prepareParallaxPreview calls it after the physical calibration resolved (a missing calibration
still leaves the old preview) and passes its limit as maxStackBytes. Cost: a cancelled or refused re-preview leaves no preview; the
cancel status now says "…; the previous preview was released". No display change: showParallaxProduct(.preprocess) with a nil
product returns early, so the resetParallaxAlignment pattern would publish nothing here (same as the Calibration/ACOM release sites).
Why not heldBytes: 0: that hands the new 2S the full half while the old 2S + alignment stay alive — the blind spot d2 closed.
Tests (ReviewPhaseContrastTests): testARePreviewIsNotChargedForTheProductsItReplaces (unit: limit == max(floor, half) after the
release, held 0), testPrepareParallaxPreviewReleasesTheOldProductsBeforeItsRun (drives prepareParallaxPreview on an all-zero
source: the run starts, fails on "no positive finite signal", nothing held).
Predictions (2026-10-02, before the runs):
- test-7 (M7: helper reads the limit before releasing): EXIT=65, only testARePreviewIsNotCharged… fails (limit = half − held KB);
  the other 6 pass.
- test-8 (M8: prepareParallaxPreview skips the release, maxStackBytes = phaseContrastWorkingLimitBytes): EXIT=65, only
  testPrepareParallaxPreviewReleases… fails (preprocess and alignment still non-nil, held = 2S + level); the other 6 pass.
- test-9 (restored; ReviewPhaseContrastTests + PtychographyProbeTests + PhaseContrastResidentBudgetTests +
  PhaseContrastMemoryBudgetTests + ParallaxAlignedMeanTests + PhaseContrastProductTests): EXIT=0, all pass (23 + 2 + PhaseContrastProductTests' cases).
### Item 2 — the rotation-branch open-items line
Not editable by a lane (RULES.md: never docs/). The line is in "Proposed doc lines" above ("Ptychography rotation branch: …");
the supervisor lands it in the same commit as this code (CLAUDE.md: docs are part of done).
### Fix-round results (2026-10-02)
| run | log | exit | seen |
|---|---|---|---|
| test-7 M7 (limit read before release) | C/test-7.log | 65 | only testARePreviewIsNotCharged… failed, 6 passed — as predicted |
| test-8 M8 (preview skips the release) | C/test-8.log | 65 | only testPrepareParallaxPreviewReleases… failed (two XCTAssertNil + the held XCTAssertEqual; its "no positive finite signal" premise passed) — as predicted |
| test-9 restored, 6 classes | C/test-9.log | 0 | 30 passed, 0 failed (23 + 2 new + 5 PhaseContrastProductTests = 30) — as predicted |
| BUILD | C/build-2.log | 0 | |
| run-tests.sh core | C/core-2.log | 0 | |
| run-tests.sh inventory | C/inventory-2.log | 0 | |
Mutations were applied and reverted by exact-string replacement (another lane edits this file); after each revert the file was
diffed against C/phasecontrast.fix.bak: identical.
Changes this round: mac4DSTEM/App/AppState+PhaseContrast.swift — new releaseParallaxProductsForPreview(); prepareParallaxPreview
(release after resolve, maxStackBytes = its limit, cancel status names the release). mac4DSTEMTests/ReviewPhaseContrastTests.swift —
2 tests + a private ZeroSource actor. UI cost: 0 rows (status text only).
Refuter's other note (Gate D evidence only in the scratchpad): for the supervisor — commit C/gated/make_cube.py, main.swift, run.sh and
the six logs under docs/archive/v4/ (lane may not), or accept the comment in usePtychographyProbeFromParallaxFit as the record.
git status --short (lane C files):  M mac4DSTEM/App/AppState+PhaseContrast.swift; M mac4DSTEM/Core/Analysis/ParallaxAlignment.swift; M mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift; M mac4DSTEM/UI/ReconstructionSettings.swift;?? mac4DSTEMTests/ReviewPhaseContrastTests.swift;
