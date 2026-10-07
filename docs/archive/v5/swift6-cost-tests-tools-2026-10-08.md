# Swift 6 cost — the test targets and tools/ (2026-10-08, measurement only)

Lane M6 (Haiku 5.5), on a scratch copy of `0c4da322`, completing `swift6-cost-2026-10-07.md` (which measured the app only). No code changed. Its one side finding (autoid-velox-check did not compile after lane V) was fixed the same night.

## 1. Test targets

Test bundles in the scheme: `mac4DSTEMTests.xctest` only. Swift package test targets: none (`Package.swift` declares three library targets and no `testTarget`).

Commands (all `build-for-testing`, Debug, `-destination 'platform=macOS'`, `CODE_SIGNING_ALLOWED=NO`, `-jobs 3`, `-derivedDataPath` a fresh dir per variant):
- Swift 5, as shipped: `xcodebuild build-for-testing -project mac4DSTEM.xcodeproj -scheme mac4DSTEM ...` log `tests-base.log`, GATE_EXIT=0, 2 min.
- Complete checking, the note's method: same command plus `SWIFT_STRICT_CONCURRENCY=complete`, and a trial `.enableUpcomingFeature("StrictConcurrency")` added to the three package targets. Log `tests-strict.log`, GATE_EXIT=0.
- Swift 6 first wave: the strict trial plus `SWIFT_VERSION = 5.0` changed to `6.0` in the two `mac4DSTEMTests` configurations only (pbxproj lines 684 and 703). Log `tests-v6.log`, GATE_EXIT=65 (TEST BUILD FAILED).
- Probe, not a fix: `nonisolated` prefixed on all 304 XCTestCase class lines (254 files). Log `tests-v6-probe.log`, GATE_EXIT=65. Result below.

Diagnostics are deduplicated by file:line:col:message from the `path:line:col: warning|error:` primary lines. The xcodebuild tree lines (`` `- warning: ``) repeat them and are not counted.

| Target | Setting | Messages | Sites | Categories | Sessions |
|---|---|---|---|---|---|
| mac4DSTEMTests | Swift 5 as shipped (`tests-base.log`) | 36 | 36 | C 30 (MainActor member from nonisolated context), B 4 (MainActor closure converted to @Sendable), A 1 (MainActor property mutated from Sendable closure), H 1 (redundant await) | in the union below |
| mac4DSTEMTests | complete checking (`tests-strict.log`) | 956 | 344 | G 912 + 27 = 939 XCTest class-level isolation (304 class declarations x 3 inherited initializers `init()`, `init(invocation:)`, `init(selector:)`, and 27 `setUpWithError`/`tearDownWithError` overrides); 17 other: C 10, B 5, A 1, H 1 | |
| mac4DSTEMTests | union of the two runs | 976 | 364 | G 331 sites (304 + 27); other 33 sites: 13 seen only under complete checking, 20 seen only in the Swift 5 run | 1-2 (see below) |
| mac4DSTEMTests | Swift 6 first wave (`tests-v6.log`) | 939 errors | 331 | all G (XCTest class-level isolation) | the rest hidden |
| mac4DSTEMTests | probe: all XCTest classes `nonisolated` (`tests-v6-probe.log`) | 1338 | 1053 | 148 "multiple actor-isolation attributes (@MainActor and 'nonisolated')", then 93+56+44+... more | not a fix |

Estimate for the test target, in sessions:
- The 331 XCTest sites are one family. If one edit per class clears them, about 1 session. Not verified: the class-level `nonisolated` edit I probed is not that edit (it produces 148 "multiple actor-isolation attributes" errors, and 1053 sites in total in the probe). The right pattern needs a decision.
- The other 33 sites: about 0.5 session.
- Wave 2 (what Swift 6 reports once wave 1 clears) is unmeasured. The probe is not evidence either way, because it changed the isolation of every test method.
- Test target estimate: 1 to 2 sessions, with the upper end depending on wave 2.

Observed anomaly, not explained: 20 messages appear under Swift 5 (`tests-base.log`) and not under complete checking (`tests-strict.log`). All are "call to main actor-isolated ... in a synchronous nonisolated context" in `SpectroscopyProposerTests.swift` (15 `kramers`), `BraggPeakRestoreTests.swift` (2 `params`/`nonDefaultParams`), `DM4ExperimentTests.swift` (2 `encode`) and `SwiftUIReviewFTests.swift` (1 initializer). The strict run also reports the XCTest messages in the same files. Whether the XCTest errors suppress these is a guess, so it is not stated as a cause. The union is used above.

## 2. tools/

Swift in tools/: 85 `.swift` files in 74 directories. One is a SwiftPM package (`tools/mlx-training-spike`, 477 lines, MLX dependency from github.com at exact 0.31.6, Metal shaders). Its run.sh builds it with `xcodebuild` and needs owner-local data, so it is not built here (no network fetch attempted). `tools/disk-detector` is Python-only; its nested `scan-bench` is Swift and is measured. Of the remaining 72 Swift harness directories (nested `scan-bench` included), each is compiled through its own harness: `run.sh` runs `xcrun swiftc ... ${MAC4DSTEM_SOURCES[@]} ${MAC4DSTEM_ISOLATION_FLAGS[@]} main.swift`, with the sources from `tools/lib/sources.manifest`. The run.sh preflights (data files, Python env) exit before the compile in 7 directories. Five of them were rerun with dummy arguments (only the arg check bypassed), two (`hdf5-race-probe`, `velox-parity`) by running their swiftc line by hand with the same sources and flags (`manual.zsh`).

Method (copied from the app note's spirit, adapted to swiftc): `$LANE/shim/xcrun` intercepts `xcrun swiftc` inside each run.sh, rewrites `-O` to `-Onone`, adds `-wmo -emit-object`, adds `-strict-concurrency=complete` for the strict variant only, writes the diagnostics to a log, and exits 99 so the run.sh stops before running the binary. Optimisation level does not change the diagnostic set; the isolation flags come from the manifest and are unchanged. Logs: `tools-logs/base/` and `tools-logs/strict/` (one `.diag` per harness, `summary.txt`, `summary-extra.txt`), driver `tools-sweep.zsh`, `single.zsh`, `manual.zsh`, analysis `analyze_tools.py` (output `tools-distinct.json`). Logs from `tools-sweep.log`, `single.log`, `manual.log` (all GATE_EXIT=0 for their slot wrappers).

Results (deduplicated across harnesses; Core is compiled by many harnesses and counted once):

| Scope | Swift 5 | Complete checking | Union | Sites | Categories (complete) |
|---|---|---|---|---|---|
| tools/ files (harness main.swift and helpers) | 2 | 63 (53 warnings, 10 errors) | 64 | 47 | B 29 (non-Sendable value into a sending/Sendable position), C 19, A 11 (captured var in concurrent closure), D 4 (global shared mutable state) |
| Core/UI shared with the app (same lines as the app build) | 1 (compile error, below) | 40 | 40 | 35 | A 19, B 9, C 9, D 2, plus the error |

Compile status per harness (72 directories plus scan-bench):
- Swift 5: 2 warnings in total (`embedding-profile`, `hdf5-race-probe`); everything else compiles clean except one compile error: `autoid-velox-check` does not compile at 0c4da322 (`UI/Spectroscopy/SpectroscopyLogic.swift:449: cannot find 'ResultFormat' in scope`). Its run.sh uses group `readers` only; `ResultFormat` is defined in `UI/Spectroscopy/QuantPanelView.swift`, which that group does not contain. This is a harness defect, not a Swift 6 item, and it is not fixed here (measure only).
- Complete checking: 4 harnesses fail to compile with errors, so their counts are partial: `disk-correlation-parity` (2 errors: MainActor top-level `backend`, `params`), `fit-overlay-test` (3: MainActor top-level `strainCal`), `sidecar-error-detail-test` (5: MainActor top-level `failures`), and `autoid-velox-check` (the pre-existing error). The compiler reports top-level variables in these `main.swift` files as MainActor-isolated and referenced from nonisolated closures; the errors stop compilation before the later phases.
- `load-spec-test` (30 distinct messages) and `matrix-orientation-probe` (16) carry most of the tools-only messages, mostly sending closures and captured vars.

Estimate: tools-only 47 sites plus the 4 partial harnesses and the one manifest defect: 0.5 to 1 session.

## 3. Totals

Distinct sites, complete checking, Swift 5 + complete (union with the Swift 5 run where it has messages):
- app + Core + Session + UI (test build, 47 messages / 34 sites): derived by the note's per-site rate (3.5 to 5 sessions for 64 sites, 0.055 to 0.078 per site) at about 2 to 3 sessions. This is a derivation, not a measurement at this commit.
- tests: 976 messages / 364 sites: 1 to 2 sessions.
- tools: 64 messages / 47 sites: 0.5 to 1 session.

One line: app + tests + tools = 34 + 364 + 47 = 445 distinct sites (47 + 976 + 64 = 1087 messages); about 3.5 to 6 sessions, with wave 2 of the tests unmeasured.

## Skipped or not done
- No code changes, no commits, no docs edits. Nothing verified on screen; no UI touched.
- mlx-training-spike not built (remote MLX dependency, Metal shaders, owner-local data; run.sh builds it only with xcodebuild).
- Two harnesses (`hdf5-race-probe`, `velox-parity`) were compiled by replaying their own swiftc line with the same sources and flags (`manual.zsh`), because their run.sh preflight needs data or a Python env. Five more were run through run.sh with dummy arguments (section 2).
- Python and shell tools are out of scope: 96 `.py` files and 96 `.sh` files under tools/ (including tools/lib).
- Cleanup NOT done: a `rm -rf` on `$LANE/dd`, `dd-strict`, `dd-v6`, `dd-v6p` and `$LANE/tmp` was refused by the safety check (no reason to bypass it). About 2.8 GB remains (dd 779 MB, dd-strict 784 MB, dd-v6 611 MB, dd-v6p 604 MB, tmp 193 MB). Please delete these from the supervisor side.
- Heavy slots: each run took heavy.1 or heavy.2 through `slot-run.sh` and released its own slot ("slot released" in each log). A heavy.1 present at 01:13 was taken by another session after ours was released; it was not touched.

## Needs verification
- Wave 2 of the test target: a real XCTest-pattern edit on one class, then one Swift 6 build, to see what remains (this lane could not establish it).
- `tools/autoid-velox-check/run.sh`: add the file that defines `ResultFormat` to its manifest group, or move the type; then rerun `run-tests.sh inventory`. Measured failure is at 0c4da322.
- The 20 Swift 5 messages absent under complete checking (section 1) and the note's anomaly: check whether the complete-checking build suppresses them, by compiling one of the files alone under both flag sets.
