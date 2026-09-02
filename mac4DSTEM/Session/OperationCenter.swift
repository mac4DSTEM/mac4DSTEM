//
//  OperationCenter.swift
//  v2.5 step 5b (2026-09-03): the one owner of "is something running, how far,
//  can it be cancelled" — the busy flag and progress that AppState used to
//  keep beside AnalysisOperationController, plus the controller itself. Every
//  way an operation ends (finish, cancel, reset on dataset change) goes
//  through here, so `isBusy` can no longer be left stale by a bare reset
//  (plan §10c). AppState forwards `isBusy`/`progress` and keeps `statusText`
//  because its log hangs off it.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class OperationCenter {
    package private(set) var isBusy = false
    /// Fractional progress [0,1] of the running operation, nil when idle or
    /// indeterminate.
    package var progress: Double?
    @ObservationIgnored private let controller: AnalysisOperationController

    package init(controller: AnalysisOperationController = AnalysisOperationController()) {
        self.controller = controller
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
