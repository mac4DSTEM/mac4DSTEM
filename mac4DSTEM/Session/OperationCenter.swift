//
//  OperationCenter.swift
//  The one owner of "is something running, how far, can it be cancelled" —
//  the busy flag and progress that AppState used to keep beside
//  AnalysisOperationController, plus the controller itself. Every way an
//  operation ends (finish, cancel, reset on dataset change) goes through
//  here, so `isBusy` can no longer be left stale by a bare reset. AppState
//  forwards `isBusy`/`progress` and keeps `statusText`, whose didSet feeds
//  `ActivityLog`.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class OperationCenter {
    /// The single source of "something is running" — `begin`/`finish`
    /// (interactive analyses) and `setBusy` (dataset load, `AppState+Open.swift`)
    /// are two different call paths, but both land here, so a `didSet` on
    /// THIS property, not on either caller, is the one true run-start/run-end
    /// seam. Settings' "Keep the Mac awake during long runs" hangs off it
    /// for exactly that reason (`ROADMAP.md` "Settings window").
    package private(set) var isBusy = false {
        didSet {
            guard oldValue != isBusy else { return }
            if isBusy {
                keepAwakeToken = beginKeepAwake()
            } else if let token = keepAwakeToken {
                endKeepAwake(token)
                keepAwakeToken = nil
            }
        }
    }
    /// Fractional progress [0,1] of the running operation, nil when idle or
    /// indeterminate.
    package var progress: Double?

    /// Bytes streamed so far by the running operation, when the loader
    /// underneath it reports a byte count — nil when the operation does not
    /// (or none is running). The bottom workspace's Run tab prints it as
    /// "Streamed"; cleared on `begin`/`finish`/`reset` like `progress`.
    package var bytesStreamed: Int64?

    /// Whether a finished operation ran to completion or was stopped early.
    /// `finish(_:)` runs on BOTH paths — `runVirtualDetector`'s
    /// `defer { finishCancellableOperation(cancellation) }` reaches it same
    /// as a normal finish — so this is read from the TOKEN's own
    /// `isCancelled` bit at the moment `finish` is called, not inferred from
    /// elapsed time or any other proxy that a cancelled-but-fast run could
    /// share with a completed one.
    package enum Outcome: Equatable {
        case completed
        case cancelled
    }

    /// The most recently finished operation's name, wall-clock elapsed time,
    /// finish timestamp and outcome — the Run tab's idle-state "Last run"
    /// line. Cleared by the next `begin`, so it never describes two runs ago.
    package private(set) var lastFinished: (name: String, elapsed: TimeInterval, at: Date, outcome: Outcome)?

    @ObservationIgnored private let controller: AnalysisOperationController
    @ObservationIgnored private let now: () -> Date

    /// Closures, not an `AppPreferences` reference, for the same reason
    /// `Session/ReplayRun.swift`'s keep-awake pair is injectable: a unit test
    /// cannot observe a real `ProcessInfo` activity, and this type should not
    /// need to know the preference exists to be tested. The default is a
    /// no-op pair, so every existing `OperationCenter()` call site (this
    /// class's own tests included) is unchanged until a caller actually
    /// wires a preference through — see `AppState.init`.
    @ObservationIgnored private let beginKeepAwake: () -> NSObjectProtocol?
    @ObservationIgnored private let endKeepAwake: (NSObjectProtocol) -> Void
    @ObservationIgnored private var keepAwakeToken: NSObjectProtocol?

    package init(
        controller: AnalysisOperationController = AnalysisOperationController(),
        beginKeepAwake: @escaping () -> NSObjectProtocol? = { nil },
        endKeepAwake: @escaping (NSObjectProtocol) -> Void = { _ in },
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.beginKeepAwake = beginKeepAwake
        self.endKeepAwake = endKeepAwake
        self.now = now
    }

    package var activeOperation: String? { controller.name }
    package var canCancel: Bool { isBusy && controller.hasActiveOperation }

    /// The controller's own total, forwarded so a view never reaches past
    /// `OperationCenter` for it (bottom-workspace Run tab, ADR 034).
    package var totalUnits: Int? { controller.totalUnits }

    /// `(progress × totalUnits).rounded()`, nil until both are known — the
    /// Run tab's "Positions done / total" row.
    package var unitsDone: Int? {
        guard let total = controller.totalUnits, let progress else { return nil }
        return Int((progress * Double(total)).rounded())
    }

    package func begin(name: String, totalUnits: Int?) -> AnalysisCancellationToken {
        let token = controller.begin(name: name, totalUnits: totalUnits)
        isBusy = true
        progress = 0
        bytesStreamed = nil
        lastFinished = nil
        return token
    }

    /// True when `token` was the current operation and it is now over.
    @discardableResult
    package func finish(_ token: AnalysisCancellationToken) -> Bool {
        // Read the controller's own metrics BEFORE it forgets the operation
        // (`controller.finish` clears `active`), so the "Last run" line can
        // report how long the run actually took.
        let name = controller.name
        let elapsedAtFinish = controller.metrics(progress: progress)?.elapsed
        // Read BEFORE `controller.finish` — cancellation lives on the token,
        // not the controller, so this ordering is not load-bearing, but it
        // keeps every fact this method records read from the same pre-finish
        // snapshot.
        let outcome: Outcome = token.isCancelled ? .cancelled : .completed
        guard controller.finish(token) else { return false }
        if let name, let elapsedAtFinish {
            lastFinished = (name: name, elapsed: elapsedAtFinish, at: now(), outcome: outcome)
        }
        isBusy = false
        progress = nil
        bytesStreamed = nil
        return true
    }

    package func isCurrent(_ token: AnalysisCancellationToken) -> Bool { controller.isCurrent(token) }

    /// Accepts progress only from the current, uncancelled operation.
    @discardableResult
    package func update(_ token: AnalysisCancellationToken, progress fraction: Double) -> Bool {
        guard controller.isCurrent(token), !token.isCancelled else { return false }
        progress = min(1, max(0, fraction))
        return true
    }

    /// Accepts a streamed-byte count only from the current, uncancelled
    /// operation — the same guard as `update(_:progress:)`, so Cancel
    /// freezes "Streamed" at the same instant it freezes progress/positions
    /// instead of letting a late progress callback keep advancing it.
    @discardableResult
    package func update(_ token: AnalysisCancellationToken, bytesStreamed: Int64) -> Bool {
        guard controller.isCurrent(token), !token.isCancelled else { return false }
        self.bytesStreamed = bytesStreamed
        return true
    }

    /// The name of the operation asked to stop, nil when nothing was running.
    package func cancel() -> String? { controller.cancelCurrent() }

    package func metrics(at date: Date = Date()) -> AnalysisOperationMetrics? {
        controller.metrics(progress: progress, at: date)
    }

    /// The dataset load is busy without an analysis token — it carries its own
    /// cancellation — so it says so explicitly rather than reaching in.
    package func setBusy(_ busy: Bool) { isBusy = busy }

    /// Dataset change: drop whatever was running AND the busy state with it.
    package func reset() {
        controller.reset()
        isBusy = false
        progress = nil
        bytesStreamed = nil
        lastFinished = nil
    }
}
