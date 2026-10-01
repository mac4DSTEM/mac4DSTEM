# Lane F-C report (rows 8, 25, 27)

## Diagnosis (claims restated; Gate D applies to all three: each can move a recorded/published value)
- Row 8: runVirtualDetector merges `currentResultPersistenceMetadata.provenance` (the DISPLAYED product's) into the virtual image; changeMode keeps the product, so strain -> Imaging -> BF carries source_product=strain_exx etc.
  Candidates: (a) the accessor returns the displayed product's provenance [read: ResultExport.swift ~1621, product != nil branch]; (b) the mode-keyed metadata is also wrong for VD [refuted by read: default branch yields only analysis_mode]. Survivor (a); test is the observation.
- Row 25: quiet runs have no token yet replaceProduct + recordReplayStep; commitApertureChange does not wait; A landing after B overwrites B. Candidate fixes: request counter (needs a stored property on ResultPresentation, Session/ResultPresentation.swift, OUTSIDE my write-set) vs a staleness check (landing run's aperture/shape must equal the live ones) in AppState+ResultPresentation.swift. Smaller + in write-set: staleness check. Seam: static hook awaited between compute and landing (no behaviour change; added first).
- Row 27: runDiskDetection captures learnedThreshold before the detach (line ~287) but records via learnedDetection.replayParameters(for:) reading live `threshold` (LearnedDetection.swift ~268). Test: change threshold while the run is in flight (operation active => capture already happened; main-actor ordering makes this deterministic).

## Predictions (2026-10-01, before run 1 on HEAD + seam only)
- test-1 (all three new classes, on HEAD): Row8 RED (strain keys present), Row25 RED (last step outer 5.0 and/or image differs), Row27 RED (learned_threshold "0.9" not "0.5"). If Row27 errors on the model missing in the test bundle, I record it as unreproduced-by-environment and report.

## Run 1 result (HEAD + seam only; log test-1.log, EXIT=65 = red as predicted)
- Row8 RED: "virtual image inherited source_product=strain_exx / basis_mode=consensus / qr_rotation_deg=12.5", analysis_mode "strain" not "virtualDetector".
- Row25 RED: last virtual_detector step outer "5.0" not "9.0"; committed image replaced (pixels ~5848 vs B's ~6393).
- Row27 RED: learned_threshold "0.9" not "0.5" (model present in the test bundle; the run completed).
Reproductions hold; fixes follow.

## Predictions (2026-10-01, before run 2: fixes applied)
- test-2 (same 3 classes): all GREEN, EXIT=0. Then mutation runs: M8 (merge currentResultPersistenceMetadata back) RED on Row8; M25 (drop the staleness guard) RED on Row25; M27 (pass live threshold) RED on Row27.
- Run 2 (test-2.log, EXIT=65): Row25 and Row27 GREEN as predicted; Row8 failed only on MY test's wrong literal ("virtualDetector" vs the enum rawValue "Virtual Det"); the key assertions (no source_product/basis_mode/qr_rotation_deg) passed. Test corrected to AnalysisMode.virtualDetector.rawValue. Prediction for run 3: all three green, EXIT=0.

## Changes
- App/AppState+ResultPresentation.swift: row 8 virtual image published via publishProduct (domain .scan, own sampling, extraProvenance quantitative_status/virtual_shape; the explicit bumpResultVersion dropped since publish bumps once); row 25 staleness guard for quiet runs (landing aperture/shape must equal live) + static test seam `virtualDetectorBeforeLanding` (nil in production).
- Session/LearnedDetection.swift: replayParameters(for:threshold: Float? = nil); nil keeps the live value for non-run callers (AppState.swift:965, outside write-set, unchanged).
- App/AppState+DiskDetection.swift: threshold captured once before the detach and passed into the recorded step (row 27).

## Tests (new): FCRow8VirtualDetectorProvenanceTests, FCRow25VirtualDetectorOrderingTests, FCRow27LearnedThresholdCaptureTests
- RED on HEAD+seam: test-1.log EXIT=65 (reasons under Run 1). GREEN with fixes: test-3a/3b/3c.log EXIT=0 (test-2 had my literal error, see above).
- Mutations (each applied, RED, reverted; cmp restored): M8 old inherit merge -> mut-8.log EXIT=65; M25 guard disabled (`if false`) -> mut-25.log EXIT=65; M27 live threshold (nil) -> mut-27.log EXIT=65. After restore: test-4a.log EXIT=0 (Row8; 25 and 27 greens are 3b/3c, run before mutation, files restored byte-identical by cmp).
- Neighbours green: ReplayExecutionTests, ExportProvenanceTests, LearnedDetectionSessionTests, DetectorTrainingFlowTests, SessionGatesTests: test-5.log EXIT=0, 47 passed, 0 failed.
- core.log EXIT=0, inv.log EXIT=0 (run-tests.sh core / inventory).

## Deviations from the brief
- Row 25: staleness check, not a request counter (counter's owner is Session/ResultPresentation.swift, outside write-set). Quiet runs landing for the live aperture still record the step (harmless: identical to the commit's). A stale quiet run returns .cancelled with no status text.
- Row 8 residual (not fixed, by the row's own proposal): publishProduct reads currentScalarPersistenceMetadata, keyed by the CURRENT mode; a VD run triggered while another mode is active (replay executor, applyDetectorPreset sets the mode first so it is fine) would take that mode's keys. Refuter may probe the replay path.
- Row 27's repro relies on main-actor ordering (isBusy true => threshold already captured); deterministic, no sleeps.

## Proposed doc lines
- open-items: close review rows 8, 25, 27 (F-C); note row 8 residual above.
- status: F-C done, three Gate D tests with mutation results; the VD publish now bumps resultVersion once (was twice-equivalent: bump + replace).

## Measurements: none (no shipped harness number moves; recorded step/provenance values only).
## git status --short: my files = AppState+DiskDetection.swift, AppState+ResultPresentation.swift, Session/LearnedDetection.swift, FCRow8/25/27 test files; other entries belong to other lanes.

## Round 2 (2026-10-01, refuter corrections C25-1, C8-1, C25-2) -- predictions before the runs
- Row25 test extended (quietA == .cancelled; live-aperture quiet run == .published, last step outer 9.0; gate released in a defer). Mutation `if quiet { return .cancelled }` (replacing the staleness condition): predicted RED (live quiet run returns .cancelled, not .published). Unmutated: GREEN.
- C8-1: "analysis_mode" pinned in the VD site's extraProvenance (row-8 test already asserts it equals the VD rawValue; it stays green, the pin makes it hold regardless of current mode).
- Final single xcodebuild (3 FC classes + ExportProvenanceTests + ReplayExecutionTests): predicted GREEN, EXIT=0.

## Round 2 results (2026-10-01)
- Mutation `if quiet {` in place of the staleness condition (quiet runs never land): mut-25b.log EXIT=65, Row25 test failed (as predicted; the new live-aperture assertion catches it). Restored, cmp identical.
- Final run test-6.log (FCRow8, FCRow25, FCRow27, ExportProvenanceTests, ReplayExecutionTests, one xcodebuild): EXIT=0, 13 test cases passed, 0 failed.
- core2.log: EXIT=0. inventory (inv2.log, inv3.log): EXIT=1, cause "UNCLASSIFIED acom-mirror-test" = another lane's new untracked tools/acom-mirror-test/, not in my write-set (diff of inv.log vs inv3.log shows only that line plus size counters). My earlier inventory run (inv.log) was EXIT=0.
## Files changed this round
- mac4DSTEM/App/AppState+ResultPresentation.swift (analysis_mode pinned in extraProvenance + comment, C8-1)
- mac4DSTEMTests/FCRow25VirtualDetectorOrderingTests.swift (quietA == .cancelled; live quiet run .published + step outer 9.0; gate released in defer; C25-1/C25-2)
- FCRow8 test unchanged: it already asserts analysis_mode == AnalysisMode.virtualDetector.rawValue.
