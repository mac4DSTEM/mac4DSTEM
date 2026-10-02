# Lane K — HDF5 at quit + three unguarded readers (Slot 4¾ review fixes), 2026-10-02
(written incrementally; Summary filled at the end)

## Diagnosis (Gate D — mechanism REPRODUCED by $SP/hdf5/report.md; this lane verifies its preconditions before the fix)
Inherited: exit race reproduced 7/120 on HEAD (run-P4.log 1/20, run-P5.log 6/100), every crash on the reader thread in H5Dread
while main runs H5_term_library from atexit. Candidates for the fix's preconditions, each with its refuting observation:
- (i) HDF5 registers H5_term_library with atexit during the FIRST H5open → a handler we register after a successful H5open runs
  BEFORE HDF5's teardown (Darwin __cxa_finalize_ranges is LIFO over atexit + __cxa_atexit). Refuting observation would be: an
  H5atclose callback (fires inside H5_term_library) sees HDF5Serial FREE although our barrier was registered after H5open.
  libhdf5 (repo root, cmp-identical to $SP/hdf5/lib copy) imports _atexit and exports _H5atclose / _H5_term_library (nm, 2026-10-02).
- (ii) No deadlock: HDF5Serial is an NSRecursiveLock (HDF5Types.swift), so exit() on a thread that already holds it re-enters at
  once. A deadlock needs a lock holder that waits for main: grep over mac4DSTEM/ for main.sync | DispatchSemaphore | exit( |
  assumeIsolated | terminate( | .wait() → 0 hits (2026-10-02). Darwin's __cxa_finalize_ranges drops the atexit mutex around each
  handler, so a lock holder that itself calls atexit (the first H5open) cannot deadlock against it either.
- (iii) Cost: quit waits for at most one locked operation (the lock is per logical op and never held across an await).
- Only two dlopen sites of libhdf5 in mac4DSTEM/ (grep 'dlopen(' → H5Reader.swift:166, BraggVectorEMDWriter.swift:3009).

## Predictions
- P-K1-RED (2026-10-02, written before the run): tools/hdf5-exit-race-test/run.sh 200, run from a git-archive copy of HEAD
  26b3f9ef ($SP/K/head/mac4DSTEM, no barrier) — log $SP/K/probe-red.log. `make` writes the 12x12x64x64 float32 cube;
  `order` prints "held … = no" → FAIL order; `race`: ≥ 1 abnormal run of 200 (statuses 139/134/138). The diagnosis measured
  5.8 % on a 100x100x128x128 uint16 cube with uint16→float conversion in H5Dread; this float32 64x64 cube has shorter reads, so
  I expect a lower rate, 1–6 % (2–12 runs). run.sh exits 1. If race shows 0/200 the probe cannot see the mechanism on this
  cube and must change (bigger/uint16 cube) before anything else counts.
- Run 1 of P-K1-RED (probe-red.log, EXIT=1) is VOID: compile error "cannot find 'DemoFourDDataSource'" (it lives in the
  `readers` group, not `export`). run.sh now sources `readers export`. Same prediction stands for the rerun (probe-red2.log).
- P-K1-RED result (probe-red2.log, heavy.sh run.sh 200 on the HEAD 26b3f9ef copy, EXIT=1; 38.3 s wall incl. compile):
  make OK (12x12x64x64); order: "held … = no", order exit 0 (an exit with no busy reader is clean — the control);
  race: 198/200 abnormal (183× 139 SIGSEGV, 13× 138 SIGBUS, 2× 133 SIGTRAP). Prediction "≥ 1 crash" HELD; the rate
  prediction (1–6 %) was WRONG: 99 %. Likely why (not tested): this probe is built -O and its reads are tiny, so the reader
  is inside libhdf5 nearly all the time; the diagnosis harness was -Onone on 128x128 uint16 patterns (Swift-side conversion
  dominates). 26 .ips written (ReportCrash throttles), parsed in $SP/K/red2-crash-summary.txt: 24/26 main thread inside
  H5_term_library with the faulting thread a cooperative-pool reader inside libhdf5 (H5Dread / H5Dopen2 / H5S / H5T / H5FL);
  2/26 list the reader as thread 0 with main already gone. Same mechanism as the diagnosis's P4/P5.
- Static check for K2 (2026-10-02, h5dump -H on the three real sidecars under References/: training_dataset Al_Mg_Si…bin_4,
  calibrationData_bullseyeProbe, thronsen-datasetA/datasetA_stride3): every calibration number is a SCALAR (F64LE / QR_flip U8LE)
  and every unit/convention string is a SCALAR H5T_VARIABLE string (bullseye has no calibration group) — the guard accepts them.
- Isolated copy for gated runs: $SP/K/iso/mac4DSTEM = git archive 7ae5d593 + my 3 Core/Data files + the test file + the probe
  (+ References symlink). Mutations happen only there, never in the shared tree.
- P-K1-GREEN (2026-10-02, before the run): probe run.sh 200 in the iso copy (barrier installed) → log $SP/K/probe-green.log:
  order prints "held … = yes"; race 0/200 abnormal; "PASS order", "PASS race"; exit 0; wall < 60 s (RED was 38 s).
- P-K1-MUT (before the run): iso copy with the barrier installed BEFORE `h5open()` in both loaders (HDF5's handler then
  registers after ours and runs first) → log $SP/K/probe-mut-before.log: order "held … = no" (FAIL order); race ≥ 150/200
  abnormal (as HEAD); exit 1. This is the experiment for precondition (i).
- P-K2-GREEN-1 (before the run): xcodebuild test -only-testing:mac4DSTEMTests/ReviewHDF5GuardTests in the iso copy → log
  $SP/K/test-1.log: 7 tests, 0 failures, EXIT=0.
- P-K1-GREEN result (probe-green.log, EXIT=0, 46.5 s wall incl. compile): "held … = yes", PASS order; PASS race 200/200 clean.
  As predicted.
- P-K1-MUT result (probe-mut-before.log, EXIT=1, 37.7 s): "held … = no", FAIL order; FAIL race 199/200 (171× 139, 25× 138,
  3× 133). As predicted. Precondition (i) SURVIVES: HDF5 2.1.1 registers its teardown inside the first H5open, and only a
  barrier registered after it runs first. iso copy restored (cmp with the shared tree: identical).
- P-K2-GREEN-1 result (test-1.log, EXIT=0): 7/7 ReviewHDF5GuardTests passed. As predicted. (Then, before any mutation run, the
  string guard was simplified to `h5tisVariableStr(type) > 0` alone — HDF5 answers false for every non-string type — so the
  class compare was redundant; test comments updated. Final green below re-runs on that code.)
- P-K2-MA (2026-10-02, before the run): iso copy, `requireOneElement` returns at once (no element check) → log test-2.log:
  RED = testAThreeElementDoubleIsRefusedByName (no throw, or a host crash from the 16-byte stack overrun),
  testAThreeElementFlagIsRefusedByName (no throw), testAnEmptyDoubleIsRefusedByName (reads 0, no throw),
  testThreeStringsAreRefusedByName (refused by the vlen check instead → message lacks "exactly one value");
  GREEN = the other 3. EXIT=65.
- P-K2-MA result (test-2.log, EXIT=65): exactly the 4 predicted red — testAThreeElementDouble: host CRASH "stack buffer
  overflow" in readDoubleDataset (the defect itself); Flag and Empty: "did not throw"; ThreeStrings: refused by the vlen check
  ("…which is not one variable-length string"), so the "exactly one value" assertion failed. The other 3 passed. As predicted.
  iso copy restored (cmp identical).
- P-K2-MBD (2026-10-02, before the run): iso copy, two mutations on DISJOINT tests — MB: the `h5tisVariableStr > 0` guard in
  readStringDataset deleted; MD: the element check weakened to `(elementCount ?? 2) <= 1` → log test-3.log:
  RED = testANumberWhereAUnitBelongsIsRefusedByName (MB: 2.5's bits become the string address → host crash),
  testAFixedLengthUnitStringIsRefusedByName (MB: 16 bytes into the 8-byte pointer → crash), testAnEmptyDoubleIsRefusedByName
  (MD: reads 0, no throw); GREEN = own-calibration and the three 3-element tests (3 > 1 still refused). EXIT=65.
- P-K2-MBD result (test-3.log, EXIT=65): exactly the 3 predicted red — Number and FixedLength: host CRASH in
  readStringDataset; Empty: "did not throw". The other 4 passed. As predicted. iso restored (cmp identical).
- P-K2-MC (2026-10-02, before the run): iso copy, element check written as rank 1 (`h5sgetSimpleExtentNdims(space) == 1`)
  → log test-4.log: testTheAppsOwnCalibrationStillRestores RED (the writer's scalars refused — loadSession throws). The other
  six go red too (rank-1 extents accepted → overrun/no throw; scalars refused with the count message where the vlen message
  is asserted) — this run is for the own-calibration test only. EXIT=65.
- P-K2-MC result (test-4.log, EXIT=65): all 7 red, the own-calibration test with "XCTUnwrap failed: threw … reading dataset
  R_pixel_size, which does not hold exactly one value". As predicted. iso restored (cmp identical).
- P-K2-GREEN-2 (2026-10-02, before the run): iso copy restored (cmp-identical to the shared tree's three Core/Data files and
  test file) → test-5.log: 7/7 pass, EXIT=0.
- P-K2-GREEN-2 result (test-5.log, EXIT=0): 7/7 passed. As predicted.
- P-REG (2026-10-02, before the run): the 13 existing test classes that open HDF5 through H5Reader / loadSession / the
  writer (CR3ReviewFixTests BraggPeakRestoreTests DiskCentreLabelTests PreprocessSheetModelTests RQRotationConventionTests
  RQLegacyExportTests SessionReplayAppStateTests SessionLineageSidecarTests SidecarProvenanceTests SidecarAttributeGuardTests
  SessionReplayTests SidecarRecognitionTests SessionGatesTests; 172 `func test` by grep) in the iso copy → test-6.log: all
  pass, 0 failures, EXIT=0 (K3's H5free_memory and K2's guard leave the app's own files and the existing hostile-file
  tests unchanged; the barrier only acts at exit).
- P-REG result (test-6.log, EXIT=0): 104 passed, 0 failed, 0 skipped. Reconciled per class: 9 classes ran exactly their
  `func test` count (CR3 7, PreprocessSheetModel 7, RQRotationConvention 5, RQLegacyExport 4, SessionReplayAppState 25,
  SessionLineageSidecar 17 of the file's 24 — the other 7 are FitAnywayRestoresOnReopenTests, SidecarAttributeGuard 4,
  SessionReplay 20, SidecarRecognition 6, SessionGates 9 = 104). Three FILE names were not class names (-only-testing takes
  the class): BraggPeakRestoreTests, DiskCentreLabelTests, SidecarProvenanceTests ran 0 — covered next.
- P-REG2 (before the run): their 11 classes (BraggPeakGridRoundTripTests DiskDetectionRecordMatchTests
  DiskDetectionControlsFromStepTests BraggPeakRestoreOnOpenTests BraggPeakSeedsControlsOnOpenTests DiskCentreLabelStoreTests
  DiskCentreLabelSidecarTests ToggleDiskCentreTests SidecarViewRecordTests SidecarRestoreProvenanceTests
  FitAnywayRestoresOnReopenTests) in the iso copy → test-7.log: all pass, 0 failures, EXIT=0; count = 25+22+14+7 = 68.
- P-REG2 result (test-7.log, EXIT=0): 68 passed (one result line split by interleaved xcodebuild output — 67 by the plain
  grep; testRefusesWithNoDatasetOpen found at log line 66, passed), 0 failed. As predicted.
- P-REAL (2026-10-02, before the run): the diagnosis harness ($SP/hdf5/harness, `app` mode) built from the iso copy
  (-Onone, build.sh) → log $SP/K/harness-app.log, on References/demo-dataset/AlMgSi_demo.h5 (read-only) and COPIES of the
  three real sidecars in $SP/K/work: every line "session true" for the new sidecar, almgsi and thronsen and bullseye
  (bullseye has no calibration group; it loaded as "session true" in run-P3 too); exit status 0.
- P-REAL result (harness-app.log, STATUS=0; harness-build.log BUILD_EXIT=0): session true on the new sidecar, almgsi,
  thronsen and bullseye; cube 100x100x128x128 read, calibration true. As predicted — K2 refuses none of the real files.
- P-BUILD (2026-10-02, before the run): app build of the SHARED working tree (other lanes' edits included) → build-1.log,
  EXIT=0, no error lines from HDF5Types.swift / H5Reader.swift / BraggVectorEMDWriter.swift.
- P-BUILD result (build-1.log, EXIT=0): one "error: the following command failed with exit code 0 but produced no further
  output" line — xcodebuild noise, also present in the iso test logs (test-1.log), not from a lane-K file; the only warning in
  my three files is the pre-existing H5Reader `legacyNote` isolation warning (HEAD line 829, now 833).
- core: core.log CORE_EXIT=0. inventory: inventory.log INV_EXIT=0 ("tools/: gated 54, diagnostic 24 …", no UNCLASSIFIED).
- P-TREE (2026-10-02, before the run): the probe from the SHARED working tree (final run.sh; other lanes' Core edits
  included) → probe-tree.log: "held … = yes", PASS order, PASS race 200/200, exit 0, < 60 s.
- P-TREE result (probe-tree.log, EXIT=0, 47.3 s): "held … = yes", PASS order, PASS race 200/200. As predicted.

## Summary
K1: a quit barrier — one atexit handler, registered once per process right after the first successful H5open in both libhdf5
loaders, takes HDF5Serial and keeps it, so exit() waits for the in-flight HDF5 call before HDF5 tears down. New gated probe
tools/hdf5-exit-race-test: RED 198/200 crashes on HEAD's code, GREEN 0/200 with the fix; registering the barrier BEFORE H5open
reproduces the crash (199/200) and fails the deterministic order check — precondition (i) proved. K2: the three sidecar
calibration readers refuse by name any dataset that is not exactly one value (and, for strings, not one variable-length
string); 7 new unit tests, each red on its mutation (one red as a "stack buffer overflow" crash). K3: H5free_memory for vlen.

## Changes
- mac4DSTEM/Core/Data/HDF5Types.swift: HDF5Serial.installExitBarrier() + private exitBarrierInstalled (owner HDF5Serial, under
  its lock) — the quit barrier (K1).
- mac4DSTEM/Core/Data/H5Reader.swift: HDF5Library.load() — `if h5open() >= 0 { HDF5Serial.installExitBarrier() }` (K1);
  H5freeMemory typealias + h5freeMemory member + symbol; readStringValue frees with h5freeMemory, not free() (K3).
- mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift (my functions only): new requireOneElement(_:_:hdf5:); readDoubleDataset,
  readBoolDataset, readStringDataset call it; readStringDataset also requires h5tisVariableStr > 0 (K2);
  HDF5WriteLibrary.load() — barrier after h5open (K1). Lane A's regions untouched.
- tools/hdf5-exit-race-test/{main.swift,run.sh} (new): make/order/race modes; synthetic cube from DemoFourDDataSource via the
  app's exporter (no References/ data → CI-safe); 200 runs, perl-alarm 20 s hang guard. 38–47 s incl. compile.
- tools/run-tests.sh: `hdf5-exit-race-test` appended to the `scientific` roster (runs < 2 min). Distinct from lane R's block.
- mac4DSTEMTests/ReviewHDF5GuardTests.swift (new, class ReviewHDF5GuardTests): 7 tests + a private calibration-dataset patcher.

## Tests (iso copy $SP/K/iso = 7ae5d593 + lane K files; mutations only there)
| test | mutation | red | green |
|---|---|---|---|
| testAThreeElementDoubleIsRefusedByName | requireOneElement returns at once (MA) | test-2 65 (crash: stack buffer overflow) | test-5 0 |
| testAThreeElementFlagIsRefusedByName | MA | test-2 65 (did not throw) | test-5 0 |
| testAnEmptyDoubleIsRefusedByName | MA; and check weakened to `<= 1` (MD) | test-2 65; test-3 65 (did not throw) | test-5 0 |
| testThreeStringsAreRefusedByName | MA | test-2 65 (wrong refusal) | test-5 0 |
| testANumberWhereAUnitBelongsIsRefusedByName | vlen-string guard deleted (MB) | test-3 65 (crash) | test-5 0 |
| testAFixedLengthUnitStringIsRefusedByName | MB | test-3 65 (crash) | test-5 0 |
| testTheAppsOwnCalibrationStillRestores | check written as rank 1 (MC) | test-4 65 | test-5 0 |
| probe order + race (tools/hdf5-exit-race-test) | no barrier (HEAD 26b3f9ef) / barrier before H5open | probe-red2 1 (198/200) / probe-mut-before 1 (199/200) | probe-green 0, probe-tree 0 |
K3: no new test (no observable difference in this build — malloc_size 48, diagnosis run-vlen.log); existing readers green:
test-6.log 104 + test-7.log 68 = 172 tests, 22 classes, 0 failures (EXIT 0 both).

## Runs
probe-red.log VOID (compile error, wrong source group) · probe-red2.log 1 · probe-green.log 0 · probe-mut-before.log 1 ·
probe-tree.log 0 · test-1..7.log 0/65/65/65/0/0/0 · harness-build.log 0 · harness-app.log STATUS=0 · build-1.log 0 ·
core.log 0 · inventory.log 0.

## Measurements
| code | order check | race abnormal / 200 | statuses | wall |
|---|---|---|---|---|
| HEAD 26b3f9ef (no barrier) | held = no | 198 | 183×139, 13×138, 2×133 | 38.3 s |
| barrier before H5open (mutation) | held = no | 199 | 171×139, 25×138, 3×133 | 37.7 s |
| K1 (iso) | held = yes | 0 | — | 46.5 s |
| K1 (shared tree) | held = yes | 0 | — | 47.3 s |

## Deviations from the brief
- Precondition (i) proved by experiment (H5atclose callback + the before-H5open mutation), not from the HDF5 2.1.1 source.
- (ii) the lock is NSRecursiveLock, so exit on a holding thread cannot deadlock; grep for main.sync/DispatchSemaphore/exit(/
  assumeIsolated/terminate(/.wait() in mac4DSTEM/ → 0 hits.
- K2 refuses a fixed-length string rather than reading it (readStringAttribute reads one): the writer only writes vlen strings,
  and h5dump shows the three real sidecars are all vlen/scalar; simpler. An EMPTY calibration dataset is now refused too
  (it used to restore silently as 0 — e.g. R_pixel_size 0).
- The probe's synthetic cube crashes ~99 % pre-fix vs the diagnosis's ~6 % (probe -O, tiny reads; not investigated further).

## Proposed doc lines
- open-items (HDF5 teardown item): "Exit race FIXED 2026-10-02 (quit barrier in HDF5Serial; tools/hdf5-exit-race-test gates it:
  198/200 → 0/200). The owner's 10-01 H5FL-gc abort (no thread in HDF5) stays NOT REPRODUCED; next: ASan scratch build."
- open-items: "Sidecar calibration datasets that are not one value / one vlen string are refused by name (was a stack overrun)."
- status: "Lane K — quit barrier + calibration-reader guards; probe gated in scientific (54 gated)."
- architecture.md (HDF5Serial paragraph): "exit() waits for the in-flight HDF5 call (quit barrier) before HDF5 tears down."

## Open questions for the supervisor
1. K1 fixes the REPRODUCED exit race only; the owner's 10-01 crash (H5FL free-list link corrupt, nobody in HDF5) is unchanged.
2. Quit now waits for one locked operation — seconds for a large sidecar publish, unbounded if a read stalls on a hung volume.
3. 30 probe-2026-10-02-*.ips and 3 mac4DSTEM-2026-10-02-1717/1718*.ips (my red runs) sit in ~/Library/Logs/DiagnosticReports
   — outside my lane, not deleted.
4. Evidence: the probe/test logs are scratch; archive the Measurements table if the commit message cites the numbers.

## git status --short (2026-10-02, end of lane K; files not in my write-set belong to other lanes)
 M mac4DSTEM.xcodeproj/project.pbxproj
 M mac4DSTEM/App/AppState+Open.swift
 M mac4DSTEM/App/AppState+ResultPresentation.swift
 M mac4DSTEM/App/AppState.swift
 M mac4DSTEM/App/mac4DSTEMApp.swift
 M mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift
 M mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift
 M mac4DSTEM/Core/Data/H5Reader.swift
 M mac4DSTEM/Core/Data/HDF5Types.swift
 M mac4DSTEM/Session/SessionGates.swift
 M mac4DSTEM/Support/ResultExport.swift
 M mac4DSTEM/UI/ContentView.swift
 M mac4DSTEM/UI/ResultsSettings.swift
 M mac4DSTEM/UI/WorkspaceSidebar.swift
 M tools/run-tests.sh
?? mac4DSTEM/Session/OpenDatasetRegistry.swift
?? mac4DSTEMTests/ReviewHDF5GuardTests.swift
?? mac4DSTEMTests/ReviewOwnerCardsTests.swift
?? mac4DSTEMTests/ReviewTileBudgetSiblingsTests.swift
?? tools/hdf5-exit-race-test/

## Refuter correction (2026-10-02, HOLDS_WITH_CORRECTIONS — one must-fix)
Finding: a NULL dataspace (h5py.Empty / H5Screate(H5S_NULL)) has rank 0, so `elementCount` returns 1 for it and
requireOneElement accepted it; H5Dread transferred nothing and R_pixel_size restored as 0.0. Change: requireOneElement now
counts with HDF5's own H5Sget_simple_extent_npoints (0 for NULL, 1 for scalar and shape (1,)); the symbol is resolved in
HDF5WriteLibrary like the others (typealias + member + symbol line — the loader region; elementCount itself, shared with
readInt64Vector / readStringAttribute, is untouched). testAnEmptyDoubleIsRefusedByName gains the NULL case (patcher
`.nullDataspace`: double type, sCreate(2), nothing written).
- P-NULL-RED (before the run): iso copy synced, then requireOneElement's count back to `elementCount(…) == 1` → test-8.log:
  testAnEmptyDoubleIsRefusedByName RED ("did not throw", at the NULL assertion — the (0,) assertion before it still passes,
  since elementCount gives 0 there); the other 6 GREEN; EXIT=65.
- P-NULL-GREEN (before the run): restored → test-9.log: 7/7 pass, EXIT=0.
- P-PROBE2 (before the run): probe run.sh 200 in the iso copy → probe-green2.log: "held … = yes", PASS order, PASS race
  200/200, exit 0.
- P-NULL-RED result (test-8.log, EXIT=65): only testAnEmptyDoubleIsRefusedByName red, one failure "did not throw" (the NULL
  assertion; the (0,) one passed); 6 green. As predicted. iso restored (cmp identical to the shared tree, all lane-K files).
- P-NULL-GREEN result (test-9.log, EXIT=0): 7/7 passed. As predicted.
- P-PROBE2 result (probe-green2.log, EXIT=0, 44.2 s): "held … = yes", PASS order, PASS race 200/200. As predicted.
- core-2.log and inventory-2.log: see exits in the final message (run after the correction on the shared tree).
- core-2.log CORE_EXIT=0; inventory-2.log INV_EXIT=0.
