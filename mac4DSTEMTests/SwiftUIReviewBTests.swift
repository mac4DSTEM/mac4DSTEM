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
}
