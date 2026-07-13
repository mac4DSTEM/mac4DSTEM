import Foundation

/// Thread-safe cooperative cancellation shared by detached tasks and their
/// DispatchQueue workers. A token is single-operation and cancellation is
/// monotonic/idempotent; callers check at row or iteration boundaries.
nonisolated final class AnalysisCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
