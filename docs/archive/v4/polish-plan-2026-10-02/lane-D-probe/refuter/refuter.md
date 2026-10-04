# Lane D — independent refuter (Fable 5.1), 2026-10-04
Copy: $SP/D/refute/mac4DSTEM = git-archive of HEAD a841f9ae + lane.patch (APPLY_EXIT=0, refute-refcopy.log).
Patched DM4Reader.swift is byte-identical to the working tree's and to the lane's DM4Reader.good.swift; FinalPolishDTests.swift identical to the working tree (cmp).

## Predictions (written BEFORE any run, 2026-10-04)
- test-0-green (refuter copy, FinalPolishDTests + DM4ReadingOptionsTests + ErrorRoutingTests): 23 passed, EXIT=0.
- E1 HFS+/yank/HEAD reader: readingOptions alwaysMapped true; after `hdiutil detach -force`, the first read dies, probe status 138.
- E2 HFS+/yank/guarded: both reads THREW the owner's sentence, status 0.
- E3 ExFAT/yank/HEAD: alwaysMapped true (exFAT reports MNT_LOCAL); status 138. (If alwaysMapped printed false, the owner's exFAT SSD would be UNGUARDED and read whole into RAM — the refutation that matters most.)
- E4 ExFAT/yank/guarded: THREW x2, status 0; after-yank check: fstat(fd) fails (EBADF or another non-zero errno).
- E5 ExFAT/unmount-remount/guarded: soft `diskutil unmount` refused (busy); after `unmount force`: THREW; after `diskutil mount` of the SAME device (same file, same inode, nothing copied): THREW again; check after-remount: statfs/stat(path) OK with the open-time dev/ino, fstat(fd) still FAIL.
- E6 ExFAT/unmount-remount/HEAD: dies 138 at the first read after the forced unmount.
- E7 APFS/yank/guarded: THREW x2, status 0. E8 APFS/yank/HEAD: 138.
- E9 HFS+/yank/M11 (fstat -> fcntl F_GETFD in HeldDescriptor.answers): alwaysMapped true; after the yank the mutated check still says alive and the read dies, status 138 — while FinalPolishDTests stays 11/11 green on the same mutation (test-M11 run): the real probe is invisible to the unit suite.
- E10 HFS+/eject (diskutil eject force, the non-deprecated verb)/guarded: THREW x2, status 0.
- Hash: probe-head vs probe-guard `hash` on a 32 MB internal-disk cube print the same `hash c9ce3a0f1eb243a tilePixels=16777216`.

## Results so far (2026-10-04; logs under $SP/D/refute/)
- test-0-green.log: 23 passed / 0 failed (FinalPolishDTests 11 + DM4ReadingOptionsTests 2 + ErrorRoutingTests 10), EXIT=0 — as predicted.
- Hash (exp/hash-head.txt, hash-guard.txt, hash-m11.txt): all `hash c9ce3a0f1eb243a tilePixels=16777216` — the guard moves no pixel (my own probe builds of HEAD and of the patched file, refbuild.sh).
- E1 HFS+/yank/HEAD: 138. E2 HFS+/yank/guarded: THREW x2, 0. E7 APFS/yank/guarded: THREW x2, 0 (after-yank: statfs/stat ENOENT, fstatfs ENOTSUP, fstat EBADF, pread EIO — same as the lane's HFS+ table). E8 APFS/yank/HEAD: 138. E10 HFS+/`diskutil eject force`/guarded: THREW x2, 0. All as predicted (exp/E*.log, *.probe.log).
- E9 M11 (fcntl F_GETFD instead of fstat): test-M11.log EXIT=0, 11/11 PASSED — and exp/E9-hfs-yank-m11.log: probe status 138. CONFIRMED: the unit suite cannot see the real probe; the RAM-disk drive is the only evidence for HeldDescriptor.answers.
- E3–E6 (exFAT) did not run: `diskutil erasevolume ExFAT mac4dstemDref` refused the 13-character name (exFAT allows 11). Re-run below with M4DREF.

## Predictions, second round (before the runs)
- M2 (no latch; mut/DM4Reader.m2-nolatch.swift): RED exactly testOnceGoneEveryLaterReadStillRefusesEvenWhenTheDiskAnswersAgain (the third read returns pixels), 10 green, EXIT=65.
- M1 (the three `try requireDiskAlive()` calls removed): RED 6 (the 3 per-entry refusals, the owner's-sentence test, the modal-alert test, the once-gone test, the once-per-read count test = 7? — the lane counted 6 before the modal-alert test existed; with it I expect 7 red: ReadPattern/ScanRow/ScanTile refusals, TheRefusalReadsAsTheOwnerWrote, TheRefusalReachesTheModalAlert, OnceGone, EachPublicReadAsksTheDiskExactlyOnce), 4 green, EXIT=65.
- E3 exFAT/yank/HEAD: mount line says exfat + local; alwaysMapped true; 138. E4 exFAT/yank/guarded: THREW x2, 0. E5 exFAT/unmount-remount/guarded: soft unmount refused (busy), force unmount ok, THREW; `diskutil mount` of the same device brings the same inode back; THREW again; after-remount check: statfs/stat(path) OK, fstat(fd) FAIL. E6 exFAT/unmount-remount/HEAD: 138 at the first read after the forced unmount.
- E11 HFS+/unmount-remount/guarded and E12 HFS+/unmount-remount/HEAD: same pattern as E5/E6; the soft `diskutil unmount` is refused for BOTH readers (the mapping alone already pins the volume) — if HEAD's soft unmount succeeds while the guarded one is refused, the held descriptor changed eject behaviour and that is a finding.

## Results, second round (2026-10-04; logs under $SP/D/refute/)
- test-M2.log EXIT=65: RED exactly testOnceGoneEveryLaterReadStillRefusesEvenWhenTheDiskAnswersAgain, 10 green (test-M2.results.json). Predicted.
- test-M1.log EXIT=65: RED exactly the 7 predicted (3 per-entry refusals, owner's-sentence, modal-alert, once-gone, once-per-read), 4 green (test-M1.results.json). Predicted. Copy restored, cmp identical to the lane's DM4Reader.good.swift.
- E3 exFAT/yank/HEAD: mount line `(exfat, local, ..., fskit)` — exFAT is FSKit-served on 27.0.1 and still MNT_LOCAL; alwaysMapped true; 138. E4 exFAT/yank/guarded: THREW x2, 0; after-yank fstat(fd) EBADF, pread EIO (same table as HFS+/APFS).
- E5 exFAT/unmount-remount/guarded: soft `diskutil unmount` exit 1 (refused), `unmount force` ok, THREW; `diskutil mount /dev/disk5` brought the SAME file back (ino=9, fsid=16777238,24 identical to open time), fstat(fd) still EBADF, THREW again x2; status 0. E6 same scenario/HEAD: 138 at the first read after the forced unmount.
- E11/E12 HFS+/unmount-remount: guarded THREW through the same-device remount (ino=20 back), status 0; HEAD 138. Soft unmount refused (exit 1) for HEAD and guarded alike: the held descriptor changes no eject behaviour — the mapping already pinned the volume.
- Every scenario created and detached only its own RAM disk (/dev/disk5 each time; the owner's PL_SSD_2TB = disk4 untouched); diskutil-list-before/after differ only in "Macintosh HD - Data" used size; /Volumes afterwards = Macintosh HD, PL_SSD_2TB, Recovery; hdiutil info shows only the pre-existing Metal toolchain image.
- core.log CORE_EXIT=0. inventory.log INVENTORY_EXIT=1 on my copy ONLY because a git-archive copy is not a git repository ("fatal: not a git repository", Licenses UNTRACKED); its DM4 line reads "one Data(contentsOf:), options from readingOptions(forPath:)". The lane's inventory-3.log on the working tree exited 0.
- py4DSTEM: References/py4DSTEM-dev/py4DSTEM/io/filereaders/read_dm.py:100-127 confirms the comment's citation (mem="RAM"/binfactor via a memmap, mem="MEMMAP" at :123); py4DSTEM/ncempy has no volume guard of its own, so there is no upstream number to compare beyond the pixel hash (identical).

## Verdict: HOLDS_WITH_CORRECTIONS
must_fix
1. DM4Reader.swift:44 cites `docs/archive/v4/polish-plan-2026-10-02/lane-D-probe/`, which does not exist in the repo. The commit that lands lane D must copy $SP/D/archive-lane-D-probe/ there (the lane's own Open question 3) — a dead citation in source is the repo's known hygiene failure, and inventory's DEAD PATH check does not scan .swift. Verify: `ls docs/archive/v4/polish-plan-2026-10-02/lane-D-probe/README.md drive.sh main.swift` after the commit. Add $SP/D/refute/refuter.md and $SP/D/refute/exp/*.log (exFAT/APFS/same-device-remount evidence) to that folder so the archive carries the owner's SSD format.
should_fix
2. MappingLiveness.descriptor(path:) returns nil when open() fails, and the reader then opens UNGUARDED if Data(contentsOf:) nonetheless succeeds (EMFILE/ENFILE, or a permission race between the two opens). Practically unreachable, but it is a gate that fails silently: throw DM4Error.cannotOpen (the file is mapped and cannot be witnessed) instead of returning nil, or at least make the comment say the guard is dropped. One line; the healthy-file tests stay green.
3. The real probe is unit-blind (M11: fstat -> fcntl F_GETFD keeps FinalPolishDTests 11/11 green and dies 138 on the RAM disk). The archived drive.sh is the only check: register it as the re-run condition for any DM4Reader change (open-items line below), and in its README note exFAT volume names ≤ 11 chars and that `hdiutil attach -nomount` is deprecated on 27 (`diskutil image attach --noMount`).
4. After the latch every pattern click re-presents the modal alert (AppState+Open.swift:303 present(error) has no dedupe; loadCurrentPattern :1248 calls it per selection). Pre-existing for any persistent read failure, now a designed one; outside lane D's write-set — confirm tolerable on the drive or register it.
