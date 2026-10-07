//
//  SwiftUIReviewBTests.swift
//  Lane B of the 2026-10-07 SwiftUI review: concurrency hygiene.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SwiftUIReviewBTests: XCTestCase {

    /// B1: closing a window cancels the operation it is running and the load it has in flight.
    func testWindowClosedCancelsTheActiveOperationAndTheLoad() {
        let state = AppState()
        let operation = state.beginCancellableOperation("Test run", status: "Running")
        let load = state.beginDatasetLoading("Opening…")
        XCTAssertFalse(operation.isCancelled)
        XCTAssertFalse(load.isCancelled)

        state.windowClosed()

        XCTAssertTrue(operation.isCancelled, "a closed window must not keep its operation running")
        XCTAssertTrue(load.isCancelled, "a closed window must ask its dataset load to unwind")
        XCTAssertFalse(state.operationCenter.isCurrent(operation),
                       "the cancelled operation is no longer the current one")
    }

    func testWindowClosedWithNothingRunningIsHarmless() {
        let state = AppState()
        state.windowClosed()
        XCTAssertFalse(state.isBusy)
        XCTAssertFalse(state.datasetSession.isLoading)
    }

    /// B2: opening a file must not block the main actor behind the global HDF5 lock. Another thread holds the
    /// lock and gives it up only once the MAIN ACTOR has proved it still runs: a main-actor sleep started after the
    /// open began wakes, and then signals the holder. If `makeReader` ran on the main thread it would sit in the
    /// lock's `acquire` with the main thread blocked, the sleep could never wake, and the holder would give up on
    /// its own timeout without the signal (no timing threshold: only the 10 s backstop).
    func testMakeReaderWaitsForTheHDF5LockOffTheMainActor() async throws {
        let held = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let signalled = Flag()
        let holder = Thread {
            HDF5Serial.acquire()
            held.signal()
            signalled.set(release.wait(timeout: .now() + 10) == .success)
            HDF5Serial.release()
        }
        holder.start()
        XCTAssertEqual(held.wait(timeout: .now() + 5), .success)

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-file-\(UUID().uuidString).h5")
        let open = Task { try? await AppState.makeReader(for: url) }
        try await Task.sleep(nanoseconds: 200_000_000)   // the main actor is alive while the open waits on the lock
        release.signal()
        _ = await open.value
        XCTAssertTrue(signalled.value, "the main actor was blocked behind the HDF5 lock while the file opened")
    }

    private nonisolated final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        nonisolated func set(_ v: Bool) { lock.lock(); stored = v; lock.unlock() }
        nonisolated var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
