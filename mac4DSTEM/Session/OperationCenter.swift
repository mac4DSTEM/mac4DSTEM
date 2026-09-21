//
//  OperationCenter.swift
//  v2.5 step 5b (2026-09-03): the one owner of "is something running, how far,
//  can it be cancelled" — the busy flag and progress that AppState used to
//  keep beside AnalysisOperationController, plus the controller itself. Every
//  way an operation ends (finish, cancel, reset on dataset change) goes
//  through here, so `isBusy` can no longer be left stale by a bare reset
//  (plan §10c). AppState forwards `isBusy`/`progress` and keeps `statusText`,
//  whose didSet now feeds `ActivityLog` (the log itself moved off AppState,
//  2026-09-04).
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
    /// for exactly that reason (session S21, ROADMAP.md "Settings window").
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
    @ObservationIgnored private let controller: AnalysisOperationController

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
        endKeepAwake: @escaping (NSObjectProtocol) -> Void = { _ in }
    ) {
        self.controller = controller
        self.beginKeepAwake = beginKeepAwake
        self.endKeepAwake = endKeepAwake
    }

    package var activeOperation: String? { controller.name }
    package var canCancel: Bool { isBusy && controller.hasActiveOperation }

    package func begin(name: String, totalUnits: Int?) -> AnalysisCancellationToken {
        let token = controller.begin(name: name, totalUnits: totalUnits)
        isBusy = true
        progress = 0
        return token
    }

    /// True when `token` was the current operation and it is now over.
    @discardableResult
    package func finish(_ token: AnalysisCancellationToken) -> Bool {
        guard controller.finish(token) else { return false }
        isBusy = false
        progress = nil
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
    }
}
