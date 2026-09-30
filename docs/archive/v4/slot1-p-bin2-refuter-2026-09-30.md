# Slot 1 lane P — bin-2 aperture default: independent refuter (Fable 5.1, read-only, 2026-09-30 night)

# Refuter — lane P item 1 (bin-2 aperture ring), Fable 5.1, 2026-09-30 ~22:40, read-only

## Verdict: HOLDS WITH CORRECTIONS
The diagnosis (mechanism iv: the VIEW-frame default aperture centre re-referenced a second time as if it were a SOURCE-frame
position) is the only candidate that predicts the shot's number and all three headless numbers; (i)–(iii) are each refuted by an
observation. The fix is minimal and leaves every file-origin, full-extent and session-sidecar path bit-identical. One test hole
(finding 7) must be closed before this lands; two notes (8, 9) are for the docs.

## Findings
1. Shot measured by me (docs/archive/v4/drives-2026-09-30-night-shots/d3-52-bin2-done.jpg, 1100×690; pane x 208–525 = 317 px,
   y 206–522; 3× crop of the pane): white dot at (288, 286) → pane fraction (0.253, 0.254); ring radius 79.7 px = 16.1 of 64.
   (iv) predicts (15.75 + 0.5)/64 = 0.254 and r = 64/4 = 16. Discriminating alternatives: (i) source-descriptor default → r = 32
   (half the pane) and centre at 1.0 (unmoved) or 0.504 (moved); (iii) a stale Aperture carries its stale radius too (one struct,
   HEAD AppState+Open.swift:416-421 assigns it whole) → r = 32; (ii) needs a recorded mean the file has not got — the row reads
   "Not set", H5Reader.swift:813 reads only `qx0_mean`, and tools/demo-dataset/make_demo.py:339-344 writes no such attribute
   (only Q/R pixel size, units, QR_flip). Each refuted by an observation, not by argument. The diagnosis's "fresh open -n instance"
   for (iii) is NOT evidenced (drive3-report.md B3b, lines 50-52, records no pid for that launch); the radius observation and the
   unconditional assignment carry the refutation without it.
2. Arithmetic re-derived from the code: HEAD passes `(aperture.centerX, aperture.centerY)` = (32, 32) built from `view.descriptor`
   (HEAD:378, 416-421 → 535-537); `readDetectorCrop` is non-nil for any bin > 1 (LoadSpecification.swift:317-320, offset 0);
   apply line 237-239: binnedCoordinate(32 − 0, 2) = 32.5/2 − 0.5 = 15.75. P1 binnedCoordinate(16, 2) = 7.75; P2 16 − 16 = 0
   (≥ −0.5 → carried as (0,0)); P3 8 − 48 = −40 → outside → nil + `.origin` refusal (247-253), HEAD caller then default + .geometricDefault.
   All three follow from (iv) alone.
3. Logs: P/test-1.log:198-202 shows exactly the predicted pattern (3 red, the 2 controls green). Mutants: test-3-M1 3 red; test-4-M2
   only testAFileRecordedCentreIsStillRebinnedIntoTheView red; test-5-M3 5 red (3 + pure + session), controls green; test-6-M4 only
   the session test red; test-7-green 7/7 passed. CAVEAT: the assertion text (7.75 / 0.0 / "(-40.0, -40.0)") is in no log — only
   pass/fail lines survive the deleted .xcresult; those numbers rest on the report's quotes, though finding 2 reproduces them by hand.
   The wrapper P/run-tests.sh echoes EXIT to the terminal, not into the log: no log carries an exit line; "** TEST FAILED **"
   present (test-1, 3, 4, 5, 6) / absent (test-7) is the in-log evidence. Restoration: CalibrationReReference.swift.fixed and
   SessionCalibrationFramePolicy.swift.fixed are byte-identical to the working tree; AppState+Open.swift.fixed differs only by the
   later item 2e/3 hunks (diffed).
4. (b) Callers of `CalibrationReReference.apply`: two in the app (AppState+Open.swift:546, SessionCalibrationFramePolicy.swift:162),
   both fixed. Harnesses pass genuine source-frame positions — tools/reduced-export-test/main.swift:246,276 (fixture beam mean
   25.25/28.625), tools/load-spec-calibration/main.swift:233,315,335 (meanX/meanY), tools/load-spec-roundtrip/main.swift:114,118
   (44,55), tools/two-spec-analysis-test/main.swift:632,655 (18,16), tools/preprocess-crop-bin-test/main.swift:164 (4,4);
   CalibrationReReferenceTests.swift:67 default (5,6). No other view-frame placeholder exists; non-optional → optional compiles.
5. (c) `fileApertureCenter` is written only at AppState+Open.swift:506 (fileMean) and 531 (maps mean) — the very values
   `aperture.center` held at HEAD's call site in those branches → identical `apply` input → identical outcome on every file-origin
   path; the `else if fileApertureCenter != nil` fallback (556-561) is HEAD's behaviour restricted to "something was refused".
   Full extent: apply's guard (CalibrationReReference.swift:169) returns the input, nil → aperture untouched = HEAD's identity
   re-assignment. Session sidecar: `center` was `sessionCenter == nil ? nil : outcome.apertureCenter`; apply never touches a nil,
   so `center` is identical in every case and only the false `.origin` entry leaves `invalidated`. The drive's legacy sidecar took
   `.refuse` (decide(record: .unrecorded, loaded: bin 2), SessionCalibrationFramePolicy.swift:37-45) and applySessionCalibration
   returns before the aperture (AppState+Open.swift:1024-1033): the drive's ring came from activate alone.
6. (d) Calibration.swift:788-801: maps → recorded mean → aperture → middle. On a binned/cropped load with no file origin the aperture
   IS the origin for AppState+DiskDetection.swift:51/67/448 (kernel centre, measured probe, recentring), AppState+PhaseMapping.swift:502,
   Core/Analysis/ParallaxPreprocessing.swift:64, AppState+Calibration.swift:312, Session/SessionGates.swift:96, Support/ResultExport.swift:472,
   UI/PhaseClaimOverlay.swift:242 — and the virtual-detector integration region. No pin covers that path: tools/real-data-acceptance/main.swift
   has no LoadSpecification (whole loads only); every existing reduced-view demo test is calibrated: true (ReplayExecutionTests.swift:216
   binnedSpec, ExportProvenanceTests.swift:113, SessionReplayAppStateTests …) and the one calibrated: false test
   (ProductWorkflowTests.swift:560) is full extent. Nothing should have been red; the report's claim stands.
7. (e) MUST FIX — a code change that leaves all 7 green with the ring off in the app: `DemoFourDDataSource(includesCalibration: false)`
   returns `pixelCalibration() == nil` (DemoFourDDataSource.swift:92), so no red-first test ever ENTERS the `if let pc` block
   (AppState+Open.swift:461-534). The drive's file is the other case: Q/R sizes present, no origin. The mutation
   `fileApertureCenter = .init(x: aperture.centerX, y: aperture.centerY)` anywhere in that block — or a future "pixel size present →
   seed the centre" edit — keeps 7/7 green and reproduces shot 52 exactly. Add one test on a source whose PixelCalibration carries
   qSize/rSize and no qx0Mean/originMaps (a third DemoFourDDataSource mode or a stub reader), bin 2, asserting (16, 16) and
   originProvenance .geometricDefault; break it with that mutation first. Other probes came back clean: crop-then-bin order (apply
   subtracts the source-frame offset then bins, 237-239; the reader crops before binning, LoadSpecification.swift:317); bin is one Int
   (no non-square bin); a non-square detector defaults per axis; the presets (AppState+ResultPresentation.swift:164-165) reset radii
   from the live view descriptor and never the centre.
8. (f) Assumed, and what the shot shows: source 128 px (make_demo.py:33 DET = 128; the pane header 64 × 64 after bin 2 agrees) and no
   file origin (finding 1) are both supported. NOT remarked in the diagnosis: the direct-beam disk sits at the pane centre = binned
   31.5 (source ORIGIN = 63.5, make_demo.py:36), while the geometric default after the fix is qx/2 = 32.0 — the bounds check
   (CalibrationReReference.swift:241-243) is pixel-centre, whose middle is 31.5. Half a binned pixel (one source pixel at full extent),
   pre-existing at every extent, not this item's mechanism; the driver will see the ring 0.5 px right/below the disk. Record as an
   observation (threshold rule: a convention, not a defect until measured on a file with a true origin), do not fold into this fix.
9. The registered hypothesis ("likely a stale …", the refuted (iii)) was already replaced while this review ran: docs/open-items.md:117
   now reads "the view-frame default was re-referenced as a source point" — correct; nothing further owed here.

## Before this lands
- Finding 7: the one missing red-first test (pixel sizes present, origin absent, reduced view), broken by the named mutation.
- Finding 3: the report's Runs table should say the exit codes were read from the wrapper's terminal echo and the assertion values
  from the deleted .xcresult (the logs hold only pass/fail lines), so a reader is not sent looking for lines that are not there.
- Finding 8: one observation line in the docs; no code. (9 is already done.)
