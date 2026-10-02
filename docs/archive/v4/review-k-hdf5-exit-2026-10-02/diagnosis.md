# HDF5 teardown crash — Gate D diagnosis (2026-10-02, HEAD b3461496)

## 1. Reports (parsed by $SP/hdf5/parse_all.py → ips-112949-all.txt, ips-180302-all.txt)
- 10-01-112949 (owner install 4.0.0/7, launched 11:13:55, crash 11:29:47): main thread only active frame chain:
  NSApplication terminate: (AE quit) → exit → __cxa_finalize_ranges → H5_term_library → H5FL_term_package →
  H5FL_garbage_coll → H5FL__reg_gc → H5FL__reg_gc_list+52 → free() → "pointer being freed was not allocated" → abort.
  Thread 1 NSEventThread idle in mach_msg; threads 2–5 have NO frames (parked workqueue threads). Nobody else in HDF5.
  One libhdf5 image (Contents/Frameworks, uuid b246fb1f…), libsz, libaec. 17 images total.
- 10-01-180302 (XCTest host in /private/tmp/*/mac4DSTEM.app, launched 18:02:59.80, crash 18:03:00.96 = 1.2 s run):
  _XCTestMain → exit → H5_term_library → … → H5FL__reg_gc_list+44 SIGSEGV, far = 0x8, x0 = 8 (loaded a free-list node
  whose `next` pointer was 8). 20 threads: NSEventThread, one NSAnimation runloop wq thread, DebugSymbolsDT Spotlight,
  rest frameless. Nobody else in HDF5. One libhdf5 (same uuid b246fb1f) — the test bundle has no second copy.
- Both: the free list of a "regular" H5FL head held a node whose first word (the `next` link) was overwritten after
  HDF5 put the block on the list → a write-after-free into an HDF5 free-list block (or a racing H5FL update) happened
  EARLIER; exit's garbage collection is only where it surfaces.

## 1b. The test-host report is IDENTIFIED (not a production defect)
- Its pid 62763 = "Test suite 'CR3ReviewFixTests' started on 'My Mac - mac4DSTEM (62763)'" in session 87fbd9cf's
  scratchpad/CR3/test-4.log (mtime 18:03:05). CR3/report.md: "Prediction run 4 (M5: element-count check in
  readInt64Vector dropped)… Run 4: test-4.log EXIT=65". The fixture qshape3.mac4dstem.h5 has Qshape = [8,8,8]
  (CR3/report.md line 9). So: the mutation let H5Dread write 3×Int64 (24 B) into a 2-element [Int64] (Swift storage
  32 B header + 16 B = 48 B malloc block) → the 8-byte overrun wrote the value 8 into the first word of the NEXT heap
  block, which was a block parked on an H5FL regular free list → its `next` link became 0x8 → H5FL__reg_gc_list
  dereferenced 0x8 at exit. far = 0x8 = the fixture's third Qshape value. Mechanism class demonstrated by accident:
  an app-side heap overrun by an HDF5 read into an undersized Swift buffer surfaces ONLY at exit, in H5FL gc.

## 4. Experiments — PREDICTIONS (written 2026-10-02 before any run)
Harness $SP/hdf5/harness/main.swift (+build.sh), compiled from the `export` source group of a git-archive copy of
HEAD ($SP/hdf5/mac4DSTEM), dlopen'ing a copy of the bundled libhdf5 2.1.1 (MAC4DSTEM_HDF5_PATH), exiting with exit(0)
so H5_term_library runs from atexit exactly as in both reports. Exit status 134 = SIGABRT, 139 = SIGSEGV.
- P1 (positive control, M5 copy $SP/hdf5/m5/mac4DSTEM = HEAD minus the readInt64Vector element-count guard,
  `qshape` mode on a copy of Fixtures/qshape3.mac4dstem.h5): "loaded, no throw", then death AT EXIT in
  H5FL__reg_gc_list (139, far 0x8) in most of 10 runs; under libgmalloc a fault INSIDE H5Dread instead (overrun
  caught at the write). If it does not crash at all, the harness cannot see the mechanism and nothing below counts.
- P2 (HEAD, same `qshape` mode): throws, exit 0 in 10/10.
- P3 (HEAD, `app` mode: H5Reader open/discover/describe/calibration/probes/every scan tile/64 patterns, file left
  OPEN at exit; sidecar write + merge + loadSession/loadPeakGrid/loadResultMap/labels on the new sidecar and on
  copies of the two real sidecars in References/training_dataset): exit 0 in 10/10, and clean under libgmalloc
  (no overrun in the shipped read paths). A crash here would make an app-pattern defect the surviving mechanism.
- P4 (HEAD, `exitrace`: a detached Task loops H5Reader.readPattern while main calls exit): crashes in some runs
  (H5_term_library tears down while H5Dread runs; HDF5Serial does not cover the atexit path), signature may or
  may not be H5FL. Tests candidate (d) generally; the owner's report showed no thread in HDF5 at crash time.

## 1c. The owner's report is NOT the Xcode/owner install — it is the pre-push scratch build
Unified log ($SP/hdf5/ulog-112947-all.txt, ulog-111350-launch.txt): loginwindow "appDeath … bundle path:
…/mac4DSTEM/build/prepush/DerivedData/Build/Products/Debug/mac4DSTEM.app" for pid 10860; launched 11:13:55 by
launchd (LaunchServices resolved the bundle id to the pre-push hook's Debug build). Quit arrived as an Apple-Event
quit (_handleAEQuit: Dock "Quit", logout, or `osascript quit`), not Cmd-Q. The only agent session then
(a00d4764) was rate-limited 11:19→11:30, so no agent quit it. Build provenance: last pre-push log before the crash
is build/prepush/prepush-20260930-214046.log (HEAD 02174c9c); HDF5 code in that window differs from HEAD only by the
readInt64Vector guard (CR3, 07fccf3f) and the lane-X export (bb80be62). App logs nothing of its own; what the
owner did in the 16 min is unknown (Biome/LS bursts 11:14–11:15 and 11:23–11:25 = user activity).

## 2/3. Candidates and refuting observations
(a) free() on HDF5-allocated vlen strings — H5Reader.swift:1032. REFUTED for this build: ctest/vlen.c on the bundled
    2.1.1 (memory checker OFF): the vlen pointer is a malloc block start (malloc_size=48, run-vlen.log), so free()
    == H5free_memory here; and a mismatch would abort at the read, not at exit. Hygiene only (use h5freeMemory).
(b) HDF5 entered from two threads (Threadsafety OFF, confirmed by `strings libhdf5.dylib`). Static audit: every
    entry (H5Reader init/deinit/each method; every BraggVectorEMDWriter package entry, publish via locked callers,
    the export's manual acquire/release 1576–1650/1676) is under HDF5Serial (HDF5Types.swift:99); no other
    dlopen/dlsym in mac4DSTEM/ or Packages/. Not refuted in principle, but no unlocked call site found.
(c) Handle closed twice — none found (each close is a single defer; ids are not reused). Not exercised further.
(d) Work still in HDF5 when exit runs — the app has NO quit hook (no applicationWillTerminate/ShouldTerminate;
    grep), so a running Task can race H5_term_library, which HDF5Serial does not cover. P4 shows it is real
    (1/20, h-head-2026-10-02-161844.ips: main in H5F_term_package, a reader thread in H5Dread/H5T__conv_ushort_float).
    REFUTED as the owner's crash: that race leaves the reader thread visibly inside libhdf5; the owner's report has
    no thread in HDF5 and faults in H5FL gc, not on a reader.
(e) Heap overrun by an HDF5 read into an undersized app buffer, landing on a block parked on an H5FL free list —
    proven mechanism for the TEST-HOST report (§1b; P1 below). For the owner's build the only unguarded site in
    that window is readInt64Vector (Qshape), which overruns only on a file with ≠2 Qshape values; the app writes
    exactly 2 (BraggVectorEMDWriter.swift:2398). Writer-side readDoubleDataset/readBoolDataset/readStringDataset
    (1053/1068/1083) still read the whole dataspace into one scalar with no element-count check (HEAD too) —
    stack, not heap, and only for a foreign/hand-edited sidecar.
(f) Any other heap corruption in the process (unsafe-pointer Swift, Metal/vDSP readbacks) — H5FL keeps many freed
    blocks alive in the same malloc zones and walks them only at exit, so it is the canary, not necessarily the cause.
- P5 (written before run, 2026-10-02): 100 more `exitrace` runs (delays 30–129 ms). Predicted: a few % crash; most
  crashes on the READER thread inside H5Dread (as P4); the owner's exact signature (main thread in
  H5FL__reg_gc_list → malloc "not allocated", no other thread in libhdf5) in at most a small minority, possibly 0.
- P6 (written before run, 2026-10-02): `app` mode extended (HARNESS_WRITERS=1) with every remaining HDF5 entry —
  mergeRGBAResultMap, mergeCalibration(+labels), removeResult, loadRGBAResultMap(id:), writeScientificBundle +
  loadScientificBundleField, writeCalibratedDataCube (qBin 2, stride 2, crop, hot-pixel filter on) and re-opening
  the export. Predicted: exit 0 in 10/10 plain runs and 2/2 under libgmalloc.

## 4b. Results (logs under $SP/hdf5/)
- P1 M5 `qshape`, plain, 10 runs (run-P1.log): 10× "loaded, no throw (q 8x8)"; exit status 0 in 10/10; 2/10 print
  "HDF5: infinite loop closing library … FL,FL,FL…" (H5FL teardown state damaged). PREDICTION REFUTED as worded
  (no signal in this harness's heap layout); the overrun itself is real: under libgmalloc 3/3 SIGSEGV
  (run-P1-gmalloc.log; ~/Library/Logs/DiagnosticReports/h-m5-2026-10-02-161747.ips): fault in _platform_memmove ←
  H5D__contig_readvv_sieve_cb ← H5Dread ← BraggVectorEMDWriter.readInt64Vector. So the XCTest-host crash = M5's
  8-byte overrun; whether it lands on an H5FL block (→ SIGSEGV @0x8 at exit) depends on heap layout.
- P2 HEAD `qshape` (run-P2.log): 10/10 + 1 gmalloc: "threw … Qshape does not hold exactly 2 values", exit 0. As predicted.
- P3 HEAD `app` (run-P3.log): 10/10 exit 0; cube 100x100x128x128 read, calibration found; new sidecar + both real
  sidecars loaded (session/grid/map/labels). Under libgmalloc (run-P3-gmalloc.log, 2 "GuardMalloc version" lines =
  active): 2/2 exit 0. As predicted. (A first gmalloc attempt through /usr/bin/time was void: SIP strips
  DYLD_INSERT_LIBRARIES from platform binaries; rerun without it.)
- P4 HEAD `exitrace`, 20 runs (run-P4.log): 19× 0, 1× 139. P5, 100 runs (run-P5.log): 94× 0, 6× 139. All 7 crash
  reports (h-head-2026-10-02-1618*/1620*.ips) fault on the READER thread (H5Dread → H5T__conv_ushort_float /
  H5D__chunk_unlock / H5T__path_table_search / H5FO_top_decr) with main inside H5_term_library's earlier packages
  (H5F/H5T/H5P/H5C/H5SL term). 0/120 show the owner's signature. As predicted.
- vlen check (run-vlen.log): H5Aread of a vlen string → malloc_size 48 (a malloc block start).
- P6 HEAD `app` + HARNESS_WRITERS=1 (run-P6.log): 10/10 exit 0 plain, 2/2 exit 0 under libgmalloc ("writers ok;
  export 50x50x56x60"). As predicted. Every HDF5 entry point the app has is now exercised clean under Guard Malloc
  on the demo cube + both real sidecars.
- Frameless threads: in the exitrace reports idle threads are also frameless while the busy reader shows its full
  HDF5 stack, so "EMPTY" = idle; supports "no thread in HDF5" for the owner's report.

## 5. Verdict
- Test-host crash (10-01-180302): EXPLAINED — the CR3 M5 mutation run (guard removed on purpose), heap overrun of
  a 2-element [Int64] by a 3-element Qshape (value 8 → far 0x8). Overrun reproduced at the write under gmalloc.
  Not a product defect; HEAD carries the guard and CR3ReviewFixTests.testAQshapeWithThreeElementsIsRefused pins it.
- Owner-side crash (10-01-112949, the pre-push Debug build): NOT REPRODUCED. Signature = a corrupted H5FL regular
  free-list link (readable, not a malloc block) walked by exit's garbage collection. Refuted: vlen free() mismatch,
  a second libhdf5, a racing HDF5 thread at crash time / exit race (different signature, 0/120), an overrun in any
  current HDF5 entry point on the files available (gmalloc clean). Unrefuted: a stray write elsewhere in the process
  into a freed block HDF5 caches (H5FL is the canary), or an HDF5 path/file combination not exercised. Confidence
  that the app's HDF5 code caused it: low.
- Separate, REPRODUCED defect found on the way: quitting while a Task is inside HDF5 crashes (exit race, 7/120).

## 6. Fix sketches (none applied; repo untouched)
F1 exit race (reproduced): in both `HDF5Library.load()` (H5Reader.swift:191-192) and `HDF5WriteLibrary.load()`
   (BraggVectorEMDWriter.swift:~3021-3022), right after the first `h5open()` — once per process, under HDF5Serial —
   `atexit { HDF5Serial.acquire() }` (never released). atexit is LIFO and HDF5 registers H5_term_library inside that
   first H5open, so this runs first: exit waits for the in-flight operation, then tears HDF5 down with no other
   thread able to enter. Pure Core, no AppKit. Cost: quit waits for at most one locked operation (a whole sidecar
   publish is one). Deadlock check: no DispatchQueue.main.sync / assumeIsolated anywhere in mac4DSTEM/ (grep).
   RED-BEFORE TEST: a gated tools/ probe = this harness's `exitrace` mode, 200 runs, require 0 signals; measured
   7/120 before (P(0/200 | 5.8 %) ≈ 7e-6). It cannot be an XCTest (exit kills the host).
F1b (owner call, not recommended alone): `H5dont_atexit()` before the first H5open — no teardown at exit, so neither
   the race nor the owner's quit-time abort can happen; read-only sources and temp-file publish make it data-safe,
   but it silences the canary for whatever corrupted the heap.
F2 hardening (HEAD, same class as M5/D003): writer-side readDoubleDataset / readBoolDataset / readStringDataset
   (BraggVectorEMDWriter.swift:1053/1068/1083) read the WHOLE dataspace into one scalar with no element-count (and,
   for strings, no vlen) check — a foreign/edited sidecar overruns a stack slot. Guard as readInt64Vector does;
   test = a 3-element `a` (and a fixed-length string) fixture → loadSession throws; red with the guard removed.
F3 hygiene: H5Reader.swift:1032 `free(cString)` → H5free_memory (equivalent in this build: malloc_size 48).
Next experiment for the owner's crash: an ASan (-enableAddressSanitizer YES) scratch build driven through his
   usual 15-minute workflow; ASan sees Swift-side overruns/UAF and libhdf5's memmove into app buffers.
Side finding: pid 10860 was LaunchServices launching build/prepush/…/Debug/mac4DSTEM.app (unsigned,
   CODE_SIGNING_ALLOWED=NO, same bundle id). The pre-push hook therefore rebuilds a bundle the owner may be running.
