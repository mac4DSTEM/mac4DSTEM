# F2 gate copies: unit counts reconciled by method name (2026-10-14)

Read-only reconciliation. No tests, builds or xcodebuild were run. Output only in this folder.

## Method

- **Declared** = every `func test...()` in each copy's `mac4DSTEMTests/*.swift`, keyed `Class.method` (innermost enclosing type). Extracted by `declared.py` (Python scanner, attributes such as `@MainActor` handled). Cross-checked against `grep -rn 'func test'`: the two agree in every copy (head-a 2238, head-b 2237, a 2238, b 2237, ab 2238, HEAD 2236). No duplicate names, no commented-out `func test`.
- **Executed** = `Test case 'Class.method()' (passed|failed|skipped) on ...` lines in each `*-unit.log`, `()` stripped, counted unique. Raw `Test case` line counts equal the unique counts in all five logs (2238, 2237, 2238, 2237, 2238), so no name ran twice.
- **Declared vs HEAD** = set difference of declared names. HEAD = `/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/mac4DSTEMTests`.

## Table per copy

| copy | declared | passed | failed | skipped | passed+failed+skipped | declared, never executed | executed, not declared | declared minus HEAD | HEAD minus copy |
|---|---|---|---|---|---|---|---|---|---|
| head-a | 2238 | 2232 | 2 | 4 | 2238 | 0 | 0 | 2 (EllipseNoisyRingTests) | 0 |
| head-b | 2237 | 2232 | 1 | 4 | 2237 | 0 | 0 | 1 (EllipseNoisyRingTests) | 0 |
| a | 2238 | 2234 | 0 | 4 | 2238 | 0 | 0 | 2 (EllipseNoisyRingTests) | 0 |
| b | 2237 | 2233 | 0 | 4 | 2237 | 0 | 0 | 1 (EllipseNoisyRingTests) | 0 |
| ab | 2238 | 2234 | 0 | 4 | 2238 | 0 | 0 | 2 (EllipseNoisyRingTests) | 0 |
| HEAD tree | 2236 | | | | | | | | |

HEAD reference run, the last 2026-10-13 HEAD unit run (`d571dab9.../scratchpad/close-unit.log`, 18:29; `s4-unit3.log` at 17:38 is identical by name): passed 2231, failed 0, skipped 5, total 2236. Its executed set equals the HEAD declared set exactly (0 missing, 0 extra).

The gap is one file. The copies differ from HEAD by exactly one added file, `EllipseNoisyRingTests.swift`, and by nothing else. The declared name sets of head-a, a and ab are identical; so are head-b and b. head-a and a have 2 methods in that class; head-b and b have 1 (`testNoisyGappedRingFallsBackToTheConicNamingTheFloor`, line 88 in head-b).

Name lists: `<copy>-declared.sorted.txt`, `<copy>-passed.txt`, `<copy>-failed.txt`, `<copy>-skipped.txt`, `<copy>-executed.txt`; the 2026-10-13 runs are `2026-10-13-close-*.txt` and `2026-10-13-s4-unit3-*.txt`.

## Failed names

- head-a (2): `EllipseNoisyRingTests.testNoisyGappedRingIsNotDrainedIntoTheBackground` (EllipseNoisyRingTests.swift:110), `EllipseNoisyRingTests.testNoisyRingDoesNotDriftOffCentre` (:117)
- head-b (1): `EllipseNoisyRingTests.testNoisyGappedRingFallsBackToTheConicNamingTheFloor` (:88)
- a, b, ab: none

These are the new Gate D registrations in `EllipseNoisyRingTests.swift`. The a, b and ab copies pass all of them. The copies differ from HEAD only by that file, so no other method changed status.

## Skips

The same four names are skipped in all five 2026-10-14 logs (byte-identical lists):

| test | skip site | condition | depends on |
|---|---|---|---|
| DiffractionEmbeddingTwoPassTests.testProfileSingleVersusTwoPass | DiffractionEmbeddingTwoPassTests.swift:239 | `environment["PROFILE_DG"] == "1"` | env var (TEST_RUNNER_PROFILE_DG); unset, so always skipped |
| SpectroGoldenTests.testRecordBaseline | SpectroGoldenTests.swift:375 | `recordDir == nil` | env var SPECTRO_GOLDEN_DIR; unset, so always skipped (recorder) |
| SpectroscopyViewModelTests.testRenderRoom | SpectroscopyViewModelTests.swift:223-224 | `environment["SPECTROSCOPY_RENDER_DIR"]` absent | env var; unset, so always skipped |
| TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes | TB1StallProbeTests.swift:24-25 (helper `requireFile`), called at :73 for `polycrystal_2D_WS2.mac4dstem.h5` | file missing under `References/training_dataset/` | machine-local file. The `.h5` is present; the `.mac4dstem.h5` sidecar is absent now. The 2026-10-13 close log skips it too; I did not verify the sidecar's state on that date |

**The fifth skip on 2026-10-13.** The 2026-10-13 HEAD run skipped 5. The fifth is:

- `BookmarkResolutionLatencyTests.testClickingARecentOnAnUnmountedVolumeKeepsTheEntry`, skip site `TB1StallProbeTests.swift:134` (class `BookmarkResolutionLatencyTests` is declared at :98, in the same file). Condition: `XCTSkipUnless(!candidates.isEmpty)`, where `candidates` = the owner's persisted recents entries whose bookmark resolves to an unmounted volume (`WorkspaceRecoveryStore.unmountedVolumeName(forBookmark:)`).
- It depends on machine state, not on the repo: the owner's persisted recents. On 2026-10-13 it skipped (0.112 s), which means no recents entry was on an unmounted volume then. On 2026-10-14 all five copies run it and it passes (0.110 s). No commit touched `TB1StallProbeTests.swift` after 2026-10-13 00:00, and no commit touched `mac4DSTEMTests` or the `WorkspaceRecovery` store after the 18:27 commit `5ddec30d` that the 18:29 run used. So the test code is unchanged; the difference is the recents state on this Mac, which I did not read (the store is in the app container, and it is the owner's data).
- Its sibling at `TB1StallProbeTests.swift:110` (`!state.recents.entries.isEmpty`) ran and passed on both dates.
- Note the test does `state.openRecent(entry)` on the real persisted recents; its teardown only re-adds an entry the test removed. Whether it runs now depends on which recents the owner holds.

Other conditional skips, all 32 `XCTSkip` sites are in `skip-sites.txt`. None fired on either date; they are gated on hardware or on files that exist here: Neural Engine (`LearnedDiskDetectorTests` and friends), Metal device (`DetectorTrainerTests.swift:110`, `ACOMRow1MirrorZoneTests.swift:108`), keychain (`MaterialsProjectImportTests.swift:402`), `References/demo-edx` (`DemoEDXFixtureTests.swift:59`, `RegistrationTests.swift:310`, `SpectroscopyLaneUTests.swift:22`, `SpectroscopyPoolsH9Tests.swift:32`), `References/crystal-structures` (`CIFMultiBlockTests.swift:94`), and "source tree not beside the tests" (`FinalPolishPTests.swift:159`, `FinalPolishR2Tests.swift:84`, `ReviewUXTests.swift:183`). The last group is the one to watch for a gate copy: it skips if a copy lacks the source files beside the tests. None of the five copies skipped, so all five keep them.

## Log-parse caveat (2026-10-13 close run)

`d571dab9.../close-unit.log` line 2921-2924: the `SpectroscopyRoomLiveRegionTests.testARegionsQuantificationCarriesAWholeMapComparisonLine` "passed" line is split by interleaved xcodebuild stderr (`IDETestOperationsObserverDebug` at 18:28:58). A strict prefix parse drops it (2230 vs 2231 raw). The name is recovered from the fragment at line 2924; `s4-unit3.log` shows the same test passing cleanly. Counts above use 2231 passed.

Not used: `base-unit.log` (2489 passed) and the `00151eb0...` logs (2465-2490 passed) belong to other trees or scopes; the counts do not match the 2236-method HEAD set. `s4-unit.log` and `s4-unit2.log` have zero counts.
