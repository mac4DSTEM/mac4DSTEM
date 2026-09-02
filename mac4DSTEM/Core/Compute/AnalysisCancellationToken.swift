import Foundation

/// Thread-safe cooperative cancellation shared by detached tasks and their
/// DispatchQueue workers. A token is single-operation and cancellation is
/// monotonic/idempotent; callers check at row or iteration boundaries.
package nonisolated final class AnalysisCancellationToken: @unchecked Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init() {}

    private let lock = NSLock()
    private var cancelled = false

    package var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    package func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
