> **Not shipped** (owner card D1 c, 2026-10-02: leave the silent adoption for v4.1). Lane B's work is kept as [`review-sidecar-identity-2026-10-02.patch`](review-sidecar-identity-2026-10-02.patch), which applies on top of the tree after the Slot 4¾ lanes landed (it was cut from the working tree, so its context is post-lane, not `b3461496`). Paths under `$SP/` below are the session scratchpad, not retained.

# Lane B report — sidecar identity (Gate D) — 2026-10-02
## Summary
Diagnosis confirmed by experiment (test-1.log): a sidecar whose own peak grid proves a 128 × 128 detector was adopted onto a 64 × 64 file
(Q 0.0123 adopted, no gate, saves enabled). Fix: a source stamp (file NAME + NATIVE shape) on the session root, a pure restore verdict
asked before anything is adopted (refusal = .doesNotFit, which disables saves), a writer refusal on a stamped shape mismatch; legacy files
refuse only on a peak grid larger than the file. Write-side wiring (ResultExport) and the crop pre-check (AppState.swift) are outside my
write-set: delivered as verified patches. 12 lane tests green after red; 2 wiring tests verified red/green in an isolated copy.

## Diagnosis (Gate D — trigger: a change that can move a scientific number: which calibration a dataset adopts)
Claim under test (finding a2): a sidecar written by one source is adopted by a different source that maps to the same sidecar path,
calibration included, with no identity check anywhere on the restore path.
Candidates, each with what would refute it:
1. Path collision — `sessionSidecarURL(forSourcePath:)` keys on the stem only (BraggVectorEMDWriter.swift:202-207). Refuted if
   "/d/scan.dm4" and "/d/scan.h5" map to different URLs. Read: `deletingPathExtension().lastPathComponent + ".mac4dstem.h5"` — survives (by reading; the experiment pins it).
2. No identity on the file — writeFile writes no source name/shape on the session root (only Rshape/Qshape inside braggvectors, :2396-2398,
   and only when vectors exist). Refuted if any root attribute names the source. grep of writeFile's root attributes: schema, minimum reader,
   spec (reduced only), replay, lineage, labels, result nodes — none identifies the source. Survives.
3. No check on restore — loadSessionSnapshot (AppState+Open.swift:946-1000) adopts inventory, recipe, lineage, then calibration through
   SessionCalibrationFramePolicy.decide(.recorded(.fullExtent), loaded: .fullExtent) → .identity → adopted verbatim. Refuted if any step
   compares the sidecar's shape to the opened file's. The only shape gate is AppState.swift recordedLoadSpecification's LoadView build,
   which a `.fullExtent` record always passes. Survives.
4. (alternative) "The peaks check already protects it" — SessionPeakRestore refuses a grid of another detector shape, but only the PEAKS;
   calibration/recipe/results are adopted before it runs. Refutes "protected": partial only.
Survivor: 1+2+3 together. Lane B fixes 2+3 (identity stamp + restore refusal); 1 (the name) is the owner's call.

## Predictions
- 2026-10-02 P1 (experiment, HEAD code + mac4DSTEMTests/ReviewSidecarIdentityTests.swift experiment tests only; log B/test-1.log):
  testExperimentSiblingSourcesShareOneSidecarPath PASSES (scan.dm4 and scan.h5 → one URL).
  testExperimentLegacySidecarWithALargerDetectorIsRefusedWhole FAILS on all three assertions: Q pixel size 0.0123 ADOPTED onto the
  64 × 64 demo from a sidecar whose peaks sit on a 128 × 128 detector; sidecarRestoreFailure nil; mayWriteSidecar true.
  testExperimentLegacyCalibrationOnlySidecarIsStillAdopted PASSES (0.0123 adopted, no gate). Exit 65.
- P1 OBSERVED (test-1.log, EXIT=65): exactly as predicted — sibling-path test passed; legacy-larger-detector test failed all three
  (xcresult: "XCTAssertNil failed: "0.0123" - adopted Q pixel size: Optional(0.0123)", "gate: nil", "XCTAssertFalse failed");
  calibration-only test passed. The diagnosis survives: a sidecar whose own peaks prove another detector is adopted verbatim, saves enabled.

## Design (decided before the fix)
- Core `SessionSourceIdentity` (BraggVectorEMDTypes.swift): source file NAME (never the path) + native (ry, rx, qy, qx), JSON on the
  session root as `mac4dstem_source`. Written by writeFile when the caller hands one; nil PRESERVES the file's existing stamp (the
  labels/replay rule) so tools and old callers never erase it. Present-but-undecodable refuses by name (v2 S7 rule).
- Restore verdict `SessionSourcePolicy.decide` (Session/SessionCalibrationFramePolicy.swift), pure:
  stamped + shape differs → refuse; stamped + same shape + other name → adopt, with a note naming both; stamped + same → adopt silently;
  unstamped (legacy) → refuse ONLY when the stored Bragg Rshape/Qshape exceeds the opened file's native scan/detector on an axis (a
  sidecar's peaks are always on some crop/bin of its OWN source, so every axis ≤ native — a larger one is proof); otherwise as today.
- loadSessionSnapshot asks it BEFORE anything is adopted; a refusal → gates.noteSidecarRestoreFailed(.doesNotFit, message) (arms
  sidecarRewriteRefusal; the sidebar/inspector already render .doesNotFit), nothing restored.
- Writer defence: a save handing an identity whose SHAPE differs from the existing file's stamp is refused (the first-save panel's
  Replace path, where the merge would otherwise carry the other dataset's results into this one's file).
- 2026-10-02 P2 (fix applied: writer stamp + loadSession read + SessionSourcePolicy + loadSessionSnapshot check; log B/test-2.log):
  all 12 ReviewSidecarIdentityTests pass, EXIT=0 — incl. the experiment test that failed in P1 (now refused whole, .doesNotFit,
  saves disabled) and the calibration-only legacy test (still adopted, as before).
- 2026-10-02 P3 (mutation run A = M3 legacy `>`→`!=`, M4 writer drops the carry-forward, M6 loadSession leaves storedPeakShape unset,
  M8 identity from the VIEW descriptor, M9 renamed note not shown; log B/test-3.log): EXIT=65; RED exactly
  testAnUnstampedSidecarIsRefusedOnlyOnALargerPeakGrid (M3), testTheStampRoundTripsAndSurvivesASaveThatNamesNoSource (M4),
  testTheStoredPeakShapeReachesTheSnapshot + testExperimentLegacySidecarWithALargerDetectorIsRefusedWhole (M6),
  testTheSameFileReopenedWholeBinnedOrCroppedStillRestores (M8, the binned case), testARenamedFileRestoresAndTheLogNamesBothFiles (M9);
  the other 6 green.
- P3 OBSERVED (test-3.log, EXIT=65): exactly the six predicted red, the other six green. All five mutations reverted (script asserts one match each).
- 2026-10-02 P4 (mutation run B = M1 policy shape guard removed, M5 writer refusal not thrown; log B/test-4.log): EXIT=65; RED exactly
  testAStampOfAnotherShapeIsRefusedNamingBothFiles + testAStampedSessionOfASiblingIsRefusedWholeAndSavesAreDisabled (M1: a different
  shape under a different name falls to the rename branch and is adopted), testASaveForASourceOfAnotherShapeIsRefusedAndTheFileIsUntouched (M5); the other 9 green.
- P4 OBSERVED (test-4.log, EXIT=65): exactly the three predicted red, 9 green. Reverted.
- 2026-10-02 P5 (mutation run C = M2 a name mismatch refuses, M7 loadSessionSnapshot ignores `.refuse`; log B/test-5.log): EXIT=65; RED
  testASameShapeStampUnderAnotherNameRestoresWithANote + testARenamedFileRestoresAndTheLogNamesBothFiles (M2),
  testAStampedSessionOfASiblingIsRefusedWholeAndSavesAreDisabled + testExperimentLegacySidecarWithALargerDetectorIsRefusedWhole (M7); 8 green.
- P5 OBSERVED (test-5.log, EXIT=65): exactly the four predicted red, 8 green. Reverted.
- 2026-10-02 P6 (regression sweep of the sidecar/session classes; log B/test-6.log): EXIT=65 with ONE red:
  BraggPeakRestoreOnOpenTests.testADetectorShapeMismatchLeavesThePeaksNil — its fixture writes a peak grid on a 66-wide detector beside a
  64-wide file, which the legacy rule now reads as proof of another dataset: the peaks stay nil (its first assertion holds) but the status
  is the whole-session refusal, not the peak refusal's "detector, not". Everything else green.
- P6 OBSERVED (test-6.log, EXIT=65; 163 passed, 2 failed): (1) testADetectorShapeMismatchLeavesThePeaksNil red as predicted in kind
  (peaks nil; status assertion fails) but the status it saw was a later load stage ("Sampling a preview · row 12 of 12"), not my
  refusal line — the open's later stages overwrite statusText; the durable channels are the gate (sidebar/inspector) and the activity log.
  (2) UNPREDICTED: SessionGatesTests.testSidecarRewriteRefusalLifecycle red — it asserts the .unreadable remedy contains "Change…",
  which LANE A's uncommitted remedy rewording (SessionGates.swift ~:199-207, "Dataset › Change Session Sidecar…" / "Allow Access…")
  removed. Not lane B's code; flagged to the supervisor.
- 2026-10-02 P7 (isolated copy $SP/B/iso/mac4DSTEM = working tree at 16:33 + resultexport-stamp.patch + the wiring test; log B/test-7.log):
  ReviewSidecarIdentityWiringTests + ReviewSidecarIdentityTests all 13 pass, EXIT=0; the stamp read back is
  {"file_name":"mac4DSTEM Demo.h5","shape":[12,12,64,64]} although the view is 32 × 32.
- P7 OBSERVED (test-7.log, EXIT=0): 13/13 passed (the wiring test compares against SessionSourceIdentity(source: demo) = 12,12,64,64).
- 2026-10-02 P8 (isolated copy; W1 = the `sourceIdentity:` argument removed from ResultExport's mergeCalibration call, plus the PROPOSED
  BraggPeakRestoreTests fixture change gridDetectorDelta 2 → -2; log B/test-8.log): EXIT=65; RED only
  testACalibrationSaveFromABinnedViewStampsTheFilesNativeIdentity (stamp nil); BraggPeakRestoreOnOpenTests all green incl.
  testADetectorShapeMismatchLeavesThePeaksNil ("detected on a 62 × 64 detector, not 64 × 64").
- P8 OBSERVED (test-8.log, EXIT=65): exactly as predicted — the wiring test red under W1, BraggPeakRestoreOnOpenTests 10/10 green with the
  proposed -2 fixture (11 passed in total).
- 2026-10-02 P9 (isolated copy; W1 still applied, + appstate-recorded-spec.patch + testASiblingsRecordedCropIsNotAppliedToThisFile; log
  B/test-9.log): EXIT=65; red: the binned-stamp test (W1, unchanged) only; the new crop test green (sibling → nil + .doesNotFit; own → crop).
- P9 OBSERVED (test-9.log, EXIT=65): as predicted.
- 2026-10-02 P10 (isolated copy; appstate-recorded-spec.patch REVERSED (the mutation), W1 restored; log B/test-10.log): EXIT=65; red: the
  crop test only (the sibling's 6 × 6 crop is returned); the binned-stamp test green.
- P10 OBSERVED (test-10.log, EXIT=65): as predicted.
- 2026-10-02 P11 (isolated copy, both patches applied, the -2 fixture; log B/test-11.log): EXIT=0 for ReviewSidecarIdentityWiringTests (2) +
  ReviewSidecarIdentityTests (12) + BraggPeakRestoreOnOpenTests (10) = 24 passed.
- P11 OBSERVED (test-11.log, EXIT=0): 25 passed — BraggPeakRestoreOnOpenTests has 11 tests, not 10 (my count in P8/P11 was wrong;
  test-8's "11 passed" was those 11, all green with the -2 fixture).
- 2026-10-02 P12 (sidecar harnesses on the working tree; logs B/h-sidecar-result.log, B/h-sidecar-error.log): both EXIT=0, no FAIL lines —
  an unstamped tool write must read back exactly as before (the stamp is additive; nil carries forward).
- P12 OBSERVED: h-sidecar-result.log EXIT=0 ("sidecar-result-test: all passed", 13 PASS lines); h-sidecar-error.log EXIT=0 (2 PASS lines;
  the "failed" hits are the HDF5 error stacks the harness provokes on purpose).
- 2026-10-02 P13 (app build, working tree; log B/build-1.log): EXIT=0. P14: `run-tests.sh core` and `inventory` exit 0 (logs B/core.log, B/inventory.log).

## Changes (lane B's hunks only)
- Core/Data/BraggVectorEMDTypes.swift: new `SessionSourceIdentity` (file_name + native [ry,rx,qy,qx], JSON, `decoded` validates 4 positive
  extents); `SessionSidecarSnapshot.sourceIdentity` + `.storedPeakShape` (vars with defaults, init untouched).
- Core/Data/BraggVectorEMDWriter.swift: `sourceIdentityAttribute` ("mac4dstem_source"); `sourceIdentity:` param (default nil) threaded
  mergeResultMap / mergeRGBAResultMap / mergeCalibration / removeResult → publish → writeFile; writeFile: read the existing stamp, REFUSE a
  save whose identity's shape differs (invalidDimensions naming both files), carry the stamp forward when nil, write it after the labels;
  loadSession: read the stamp (present-but-undecodable → malformedAttribute) and the peak grid's Rshape+Qshape (unreadable → nil).
- Session/SessionCalibrationFramePolicy.swift: new pure `SessionSourcePolicy.decide(recorded:storedPeakShape:opened:)` → adopt / adoptRenamed(note) / refuse(reason).
- App/AppState+Open.swift: `sessionSourceIdentity(for:)` (computed: `datasetSession.loadView?.source ?? descriptor`, one derivation for
  stamp and check); loadSessionSnapshot asks the policy BEFORE sessionInventory/recipe/lineage/calibration; refuse → gates
  `.doesNotFit` + status (logged by didSet), return nil; renamed → status line naming both.
- mac4DSTEMTests/ReviewSidecarIdentityTests.swift (new, 12 tests).
- SessionGates.swift: NOT touched — `.doesNotFit` already says "move the sidecar aside / choose another", and the sidebar + inspector render it (0 rows of new UI).

## Tests (mutation → red exit → green exit; logs)
| test | mutation | red | green |
|---|---|---|---|
| testExperimentLegacySidecarWithALargerDetectorIsRefusedWhole | HEAD (no fix) / M6 / M7 | test-1 65, test-3 65, test-5 65 | test-2 0 |
| testAStampOfAnotherShapeIsRefusedNamingBothFiles | M1 shape guard removed | test-4 65 | test-2 0 |
| testASameShapeStampUnderAnotherNameRestoresWithANote | M2 name mismatch refuses | test-5 65 | test-2 0 |
| testAnUnstampedSidecarIsRefusedOnlyOnALargerPeakGrid | M3 `>`→`!=` | test-3 65 | test-2 0 |
| testTheStampRoundTripsAndSurvivesASaveThatNamesNoSource | M4 no carry-forward | test-3 65 | test-2 0 |
| testASaveForASourceOfAnotherShapeIsRefusedAndTheFileIsUntouched | M5 throw removed | test-4 65 | test-2 0 |
| testTheStoredPeakShapeReachesTheSnapshot | M6 shape unset | test-3 65 | test-2 0 |
| testAStampedSessionOfASiblingIsRefusedWholeAndSavesAreDisabled | M1 / M7 refusal ignored | test-4 65, test-5 65 | test-2 0 |
| testTheSameFileReopenedWholeBinnedOrCroppedStillRestores | M8 view descriptor, not source | test-3 65 | test-2 0 |
| testARenamedFileRestoresAndTheLogNamesBothFiles | M9 note dropped / M2 | test-3 65, test-5 65 | test-2 0 |
| testExperimentSiblingSourcesShareOneSidecarPath | none (documents the collision; owner's naming call) | — | test-1/2 0 |
| testExperimentLegacyCalibrationOnlySidecarIsStillAdopted | none (pins "behave as today") | — | test-1/2 0 |
| (patch) testACalibrationSaveFromABinnedViewStampsTheFilesNativeIdentity | W1 arg removed | test-8 65 | test-10/11 0 (isolated copy) |
| (patch) testASiblingsRecordedCropIsNotAppliedToThisFile | AppState patch reversed | test-10 65 | test-9/11 0 (isolated copy) |
Mutations applied/reverted by $SP/B/mutate.py (each asserts exactly one match). Untested: a malformed stamp (no writer for a bad attribute).

## Runs
test-1..6 (working tree, lane dd): 65, 0, 65, 65, 65, 65 (test-6 = 20-class sidecar sweep, 163 pass / 2 fail, below).
test-7..11 (isolated copy + patches, iso-dd, since deleted): 0, 65, 65, 65, 0. h-sidecar-result.log 0, h-sidecar-error.log 0,
build-1.log 0, core.log 0, inventory.log 0.

## Deviations from the brief
- The writer write-set said "only writeFile's root attributes and loadSession": the stamp cannot reach writeFile without a defaulted
  `sourceIdentity:` parameter on the four merge/remove entry points and `publish` (additive, default nil = today's behaviour).
- The writer also REFUSES a stamped shape mismatch (defence for the first-save panel's Replace path); not in the brief.
- No new SessionGates kind: `.doesNotFit` is the right class and is already rendered.
- No schema bump (`SessionSidecarFormat.currentSchema` lives in HDF5Types.swift, outside the set): the stamp is additive and its absence self-describing.

## Proposed doc lines
- open-items (a2, replace or close): "Sidecar identity (review a2): sidecars stamp source name + native shape (`mac4dstem_source`); a
  stamp of another shape, or an unstamped peak grid larger than the file, refuses the whole restore and disables saves (.doesNotFit);
  same shape + other name restores with a line. OPEN: sidecar naming (scan.dm4.mac4dstem.h5) — owner's call; unstamped calibration-only
  sidecars of a sibling are still adopted (no evidence to refuse on)."
- status: "Lane B (a2) — identity stamp + restore refusal; ReviewSidecarIdentityTests 12 red→green (test-2..5)."

## Open questions for the supervisor
1. APPLY $SP/B/patch/resultexport-stamp.patch (4 ResultExport call sites pass `sessionSourceIdentity(for: descriptor)`) — without it the
   app never WRITES a stamp and only the legacy rule is live. Add $SP/B/patch/ReviewSidecarIdentityWiringTests.swift WITH it.
2. APPLY $SP/B/patch/appstate-recorded-spec.patch (AppState.recordedLoadSpecification asks the same policy before applying a recorded
   crop) — without it a sibling's recorded crop is applied to this file before loadSessionSnapshot refuses the rest.
3. BraggPeakRestoreTests.swift:388 `open(gridDetectorDelta: 2)` → `-2`: its fixture's 66-wide grid beside a 64-wide file is now (correctly)
   proof of another dataset; at -2 the peak check still refuses with "detector, not" (verified: test-8 / test-11, 11/11 green).
4. SessionGatesTests.testSidecarRewriteRefusalLifecycle is red on LANE A's remedy rewording ("Change…" no longer in the .unreadable text) — test-6.
5. Rename trade-off (decided conservative, per brief): same shape + other name ADOPTS with a line. Risk: a py4DSTEM-converted scan.h5 with
   NO binning beside scan.dm4 (same shape) adopts the dm4's session — that is usually the same data, so it is the right default; refuse
   instead only if the owner wants name-exact sessions.
6. The .doesNotFit headline in the frozen sidebar/inspector says "describes a region this file does not have" — imprecise for a source
   mismatch (the detail line names both files). A word-only fix in a frozen file is the owner's (ADR 050).
7. Gate D's independent refuter was not run by lane B (no agent tool here); scope for it: can any legitimate reopen (crop, bin, promote,
   moved folder, preprocess-export-then-reopen of the ORIGINAL) be refused? My matrix: stamp is the source's native shape, so all of those match.
8. Writes via python in mutate.py rewrote whole files for ms; no concurrent edit was lost as far as `git diff` shows, but say so.

## git status --short (lane B's files)
 M mac4DSTEM/App/AppState+Open.swift (also other lanes' hunks at :112,:126,:614,:1151 — mine: sessionSourceIdentity(for:), loadSessionSnapshot)
 M mac4DSTEM/Core/Data/BraggVectorEMDTypes.swift
 M mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift (lane A's hunks at writeScientificBundle and writeFile's existing-file open are not mine)
 M mac4DSTEM/Session/SessionCalibrationFramePolicy.swift
?? mac4DSTEMTests/ReviewSidecarIdentityTests.swift

## Fix round — 2026-10-02 (refuter verdict HOLDS_WITH_CORRECTIONS; five MUST-FIX items)
Applied to the working tree (git apply, no index): (1) $SP/B/patch/resultexport-stamp.patch → Support/ResultExport.swift (4 call sites pass
`sessionSourceIdentity(for: descriptor)`); (2) $SP/B/patch/appstate-recorded-spec.patch → App/AppState.swift recordedLoadSpecification asks
SessionSourcePolicy before applying a recorded crop; (3) mac4DSTEMTests/ReviewSidecarIdentityWiringTests.swift added (copied from patch/, 2 tests);
(4) BraggPeakRestoreTests.swift testADetectorShapeMismatchLeavesThePeaksNil: gridDetectorDelta 2 → -2 (+3-line comment why);
(5) ReviewSidecarIdentityTests.testExperimentSiblingSourcesShareOneSidecarPath deleted (pinned a known defect; 12 → 11 tests).
Broken-first for the wiring tests stands on the isolated-copy runs (test-8 red W1, test-10 red AppState patch reversed; green test-9/11);
not re-mutated in the shared tree (ResultExport/AppState carry other lanes' live hunks).
- 2026-10-02 P15 (working tree, all five items applied; log B/test-12.log): -only-testing ReviewSidecarIdentityWiringTests (2) +
  ReviewSidecarIdentityTests (11) + BraggPeakRestoreOnOpenTests (11) → 24 passed, 0 failed, EXIT=0.
- P15 OBSERVED (test-12.log, EXIT=0): 24 "passed" lines, 0 "failed on" lines — Wiring 2/2, Identity 11/11, BraggPeakRestoreOnOpen 11/11
  (incl. testADetectorShapeMismatchLeavesThePeaksNil at -2). xcresult deleted after reading.
- Gates after the fix round: tools/run-tests.sh core → B/core-2.log EXIT=0; inventory → B/inventory-2.log EXIT=0. No app build re-run
  (test-12 compiled the app target with both patches applied). Nothing verified on screen.
- Refuter cosmetic notes (headline wording in frozen files, double-named multi-datacube message, refusal logged twice, rename trade-off)
  are unchanged and remain owner/supervisor calls (Open questions 5, 6 above). SessionGatesTests red is lane A's (Open question 4).
- Proposed status line amended: "Lane B (a2) — identity stamp + restore refusal + write-side stamp + crop pre-check;
  ReviewSidecarIdentityTests 11 + ReviewSidecarIdentityWiringTests 2 red→green (test-1..5, 8, 10), green together test-12."
### git status --short (fix round; lane B's files now also include)
 M mac4DSTEM/App/AppState.swift (patch hunk in recordedLoadSpecification; other lanes' hunks present)
 M mac4DSTEM/Support/ResultExport.swift (4 stamp call sites; other lanes' hunks present)
 M mac4DSTEMTests/BraggPeakRestoreTests.swift
?? mac4DSTEMTests/ReviewSidecarIdentityWiringTests.swift
(full listing: B/status-2.txt)
