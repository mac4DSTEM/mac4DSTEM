import Foundation

package struct AnalysisOperationMetrics: Equatable {
    package let elapsed: TimeInterval
    package let unitsPerSecond: Double?
    package let eta: TimeInterval?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(elapsed: TimeInterval, unitsPerSecond: Double?, eta: TimeInterval?) {
        self.elapsed = elapsed
        self.unitsPerSecond = unitsPerSecond
        self.eta = eta
    }
}

/// Owns the lifecycle of one foreground scientific operation. `AppState`
/// remains the observable UI facade, but no longer owns token identity/timing.
package final class AnalysisOperationController {
    private struct ActiveOperation {
        package let name: String
        package let token: AnalysisCancellationToken
        package let startedAt: Date
        package let totalUnits: Int?
    }

    private let now: () -> Date
    private var active: ActiveOperation?

    package init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    package var name: String? { active?.name }
    package var totalUnits: Int? { active?.totalUnits }
    package var hasActiveOperation: Bool { active != nil }

    package func begin(name: String, totalUnits: Int?) -> AnalysisCancellationToken {
        active?.token.cancel()
        let token = AnalysisCancellationToken()
        active = ActiveOperation(
            name: name, token: token, startedAt: now(), totalUnits: totalUnits
        )
        return token
    }

    /// Only the active token may finish the visible operation. A late defer
    /// from replaced work is harmless.
    @discardableResult
    package func finish(_ token: AnalysisCancellationToken) -> Bool {
        guard active?.token === token else { return false }
        active = nil
        return true
    }

    package func isCurrent(_ token: AnalysisCancellationToken) -> Bool {
        active?.token === token
    }

    @discardableResult
    package func cancelCurrent() -> String? {
        guard let active, !active.token.isCancelled else { return nil }
        active.token.cancel()
        return active.name
    }

    /// Dataset replacement and explicit recovery both invalidate outstanding
    /// work before clearing identity.
    package func reset() {
        active?.token.cancel()
        active = nil
    }

    package func metrics(progress: Double?, at date: Date? = nil) -> AnalysisOperationMetrics? {
        guard let active else { return nil }
        let elapsed = max(0, (date ?? now()).timeIntervalSince(active.startedAt))
        guard elapsed > 0, let progress, progress > 0 else {
            return AnalysisOperationMetrics(
                elapsed: elapsed, unitsPerSecond: nil, eta: nil
            )
        }
        let fraction = min(1, max(0, progress))
        let rate = active.totalUnits.map { Double($0) * fraction / elapsed }
        let eta = fraction < 1 ? elapsed * (1 - fraction) / fraction : 0
        return AnalysisOperationMetrics(
            elapsed: elapsed, unitsPerSecond: rate, eta: eta
        )
    }
}
