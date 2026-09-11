# Gate D — A2: the learned full-scan run executes on the main thread

Written **before** the experiment was run (2026-09-06, fix-a session). The
symptom and its primary evidence are the owner-driven captures
`drive-learned/04-mainthread-sample.txt` (847/847 `com.apple.main-thread`
samples) and `drive-groups/sample-main-thread-during-run.txt` (698/698).

## 1. The diagnosis

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
(`project.pbxproj:501-502`), so any declaration that does not say
`nonisolated` is `@MainActor`.

**Learned disks.** `LearnedDiskDetector.detectAll(data:descriptor:…)` is
declared `package func detectAll(` at `Core/ML/LearnedDiskDetection.swift:143`,
inside `extension LearnedDiskDetector` (`:99`) — an extension in a *different
file* from the `package nonisolated final class LearnedDiskDetector`
declaration (`Core/ML/LearnedDiskDetector.swift:25`). The classical twin says
the keyword explicitly: `package nonisolated static func detectAll(`
(`Core/Analysis/TiledDiskDetection.swift:72`), and its `ProgressCoalescer` is
`nonisolated private final class` (`:13`) where the learned copy
(`LearnedDiskDetection.swift:107`) dropped it. The build's only warning,
`LearnedDiskDetection.swift:174:30: call to main actor-isolated instance
method 'admits' in a synchronous nonisolated context`
(`build-20260906.log:357`), proves the MainActor default does reach inside
this extension — for the nested type at least.

The claim under test: **`detectAll(data:…)` is MainActor-isolated**, so the
`Task.detached` at `AppState.swift:4924-4931` — which exists precisely to keep
this off the main actor — `await`s straight back onto the main actor, and
`DispatchQueue.concurrentPerform` (`LearnedDiskDetector.swift:343`) then
conscripts the main thread as a `dispatch_apply` worker for every batch.

**Diffraction groups.** A *different* mechanism with the same symptom.
`DiffractionEmbedding` is already `package nonisolated enum`
(`Core/Analysis/DiffractionEmbedding.swift:40`), so `compute` (`:137`) is
`nonisolated async` — and under SE-0461 a `nonisolated async` function runs on
its **caller's** executor. `AppState+DiffractionGroups.swift:52` awaits it
directly from the `@MainActor` `runDiffractionGroups()`, with no
`Task.detached` anywhere in the file. So the compute runs on the main actor
and the progress hop at `:40-49` can never be serviced.

**Precipitates.** `PrecipitateSegmentation` is `package nonisolated enum`
(`Precipitates/PrecipitateSegmentation.swift:19`) and `segment` is a
`nonisolated` *synchronous* static func (`:88`), already called inside
`Task.detached` (`AppState+Precipitates.swift:88-90`). Predicted: **not
affected** — no change needed there. Recording this so the negative is on the
record rather than assumed.

## 2. The observation that would refute it

- **Learned:** if `detectAll(data:…)` were already nonisolated, then a call
  from a nonisolated context would compile with no isolation diagnostic, and a
  call made from `Task.detached` would see `Thread.isMainThread == false`
  inside its own `progress:` callback — because `Task.detached` runs on the
  global concurrent executor, and a nonisolated async callee inherits *that*
  caller's executor, not the main one. Seeing `false` before any fix refutes
  the diagnosis, and the 847/847 main-thread samples would then have to come
  from somewhere else (a MainActor hop inside `heatmaps`/Core AI, or
  `Task.detached` not doing what is assumed).
- **Groups:** if `DiffractionEmbedding.compute` did hop off on its own, the
  status bar would have repainted during the run. It did not (0 %, 0 s, for
  the whole 5 minutes) — already-collected refuting-observation evidence that
  went the diagnosis's way.
- Either would also be refuted by the classical full-scan run freezing the
  same way. It does not: `drive-learned/05a-classical-run.png`, 54.8
  positions/s with a live progress bar, through the structurally identical
  `Task.detached` at `AppState.swift:4907`.

## 3. The predicted outcome, stated before running

Experiment: a new unit test,
`LearnedDiskDetectionScanTests.testLearnedFullScanRunsOffTheMainThread`,
reusing the 4×4 in-memory fixture at `LearnedDiskDetectionScanTests.swift:172`.
It calls `learned.detectAll(data:…, maximumTileRows: 1)` from inside
`Task.detached(priority: .userInitiated)` and records, under an `NSLock`,
whether `Thread.isMainThread` was ever true inside the `progress:` closure,
then asserts `XCTAssertFalse(sawMainThread)`.

**Prediction, before the fix: the assertion FAILS — `sawMainThread == true`,
the progress callback runs on the main thread even from a detached task.**
Run against the unmodified branch. If it passes before the fix, the diagnosis
is refuted and no `nonisolated` change may land on this account.

## 4. Outcome

**The prediction was met.** Run 2026-09-06 22:06 on the unmodified branch,
log `prefix-tests-20260906.log` (exit 65), failures extracted to
`prefix-failures-20260906.txt`:

> `testLearnedFullScanRunsOffTheMainThread():`
> `    XCTAssertFalse failed - the learned full scan ran its progress callback
> on the main thread (5 of 5 calls) even from Task.detached — the detached
> task hopped back onto the main actor`

5 of 5 progress callbacks on the main thread, from a `Task.detached` — the
refuting observation (any `false` reading) did not occur. `nonisolated` on
the class declaration in `LearnedDiskDetector.swift:25` does **not** reach a
member declared in another file's extension: the open link the read-only pass
could not close is now closed by measurement, in the direction the diagnosis
predicted.

The same run is the break-log for the other three fixes (A1, A3, A5), which
all failed on the unmodified branch — A1 with `("0") is not equal to ("3")`,
proving the three-disk fixture yields peaks in `.disks` and none in
`.learnedDisks`.

## 5. The fix, and what it does not touch

- `Core/ML/LearnedDiskDetection.swift:107` and `:143` gain `nonisolated`,
  matching `TiledDiskDetection.swift:13` and `:72`. The build's only warning
  (`'admits' in a synchronous nonisolated context`) disappears with them.
- `App/AppState+DiffractionGroups.swift` wraps `DiffractionEmbedding.compute`
  in `Task.detached(priority: .userInitiated)` — the same shape
  `AppState.swift:4907` uses for the classical full scan. No `nonisolated`
  keyword was needed there: `DiffractionEmbedding` already has it
  type-wide, and the defect was purely SE-0461 caller-executor inheritance
  from a `@MainActor` caller.
- **Precipitates: no change.** `PrecipitateSegmentation.segment` is a
  `nonisolated` *synchronous* static func already called inside
  `Task.detached` (`AppState+Precipitates.swift:88-90`); a synchronous
  nonisolated call cannot hop, so the mechanism does not reach it. Recorded
  as a negative rather than assumed.

## 6. Post-fix

`postfix-tests-20260906.log`: `testLearnedFullScanRunsOffTheMainThread`
passes, and the seven named classes are green. Counts are in the log and in
the session report.
