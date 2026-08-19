//
//  DatasetLoadCancellationTests.swift
//  Cancelling an open. Requested by the release owner 2026-08-18: picking the
//  wrong file left quitting the app as the only exit.
//
//  The property that matters is not "the button works" — it is that a cancelled
//  open leaves NOTHING behind that looks loaded. A half-loaded dataset showing
//  dimensions and a calibration for a cube whose pixels were never read would be
//  worse than having no cancel at all, because every number computed afterwards
//  would be about data the app never finished reading.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class DatasetLoadCancellationTests: XCTestCase {

    private func loadedState() async -> AppState {
        let state = AppState()
        await state.openDemoFixture()
        return state
    }

    func testTheAffordanceIsOfferedOnlyWhileALoadIsRunning() async {
        let state = AppState()
        XCTAssertFalse(state.canCancelDatasetLoad,
                       "nothing is loading, so there is nothing to cancel")
        XCTAssertFalse(state.isLoadingDataset)

        // After a completed load the offer is withdrawn — a Cancel that lingers
        // on a finished open would cancel nothing and say otherwise.
        let loaded = await loadedState()
        XCTAssertTrue(loaded.hasDataset)
        XCTAssertFalse(loaded.canCancelDatasetLoad)
    }

    func testCancellingWhenNothingIsLoadingDoesNothing() async {
        let state = await loadedState()
        let descriptorBefore = state.descriptor
        state.cancelDatasetLoad()
        XCTAssertEqual(state.descriptor?.datasetPath, descriptorBefore?.datasetPath,
                       "a stray cancel must not tear down a dataset that finished loading")
        XCTAssertTrue(state.hasDataset)
    }

    func testTheDemoFixtureIsNeverRemembered() async {
        // Named for what it actually checks. The demo source is synthetic and
        // touches no disk, so it has no file to remember; this pins that the
        // demo path does not accidentally write a Recents entry pointing at
        // nothing.
        let state = AppState()
        let before = state.recents.entries.count
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset)
        XCTAssertEqual(state.recents.entries.count, before)
    }

    // MARK: - The property that matters

    func testDiscardingALoadLeavesNothingThatLooksLoaded() async {
        // THE INVARIANT. Everything above tests the affordance; this tests the
        // consequence, which is the part that could produce a wrong number.
        // Driven through `discardPartialLoad` directly rather than by racing a
        // cancel against a demo load that finishes in milliseconds — the timing
        // is not the property, the resulting state is.
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset, "precondition: something to discard")
        XCTAssertNotNil(state.descriptor)

        let recentsBefore = state.recents.entries.map(\.id)
        await state.discardPartialLoad()

        // The welcome screen is driven by `hasDataset`, which is
        // `descriptor?.is4D` — so this is the single condition that decides
        // whether the app looks loaded.
        XCTAssertFalse(state.hasDataset)
        XCTAssertNil(state.descriptor)
        XCTAssertTrue(state.datasets.isEmpty)
        XCTAssertNil(state.datasetPreview)

        // A discarded load is not remembered — the release owner's call.
        XCTAssertEqual(state.recents.entries.map(\.id), recentsBefore)

        // NOT ASSERTED HERE, deliberately: `residency.isResident`,
        // `residency.byteCount` and `loadedView.isFullExtent`. All three are
        // ALREADY in their post-discard state after a demo open — residency is
        // dormant by decision, and a demo load is full extent — so asserting
        // them would pass whether or not `discardPartialLoad` touched them.
        // Controls proved exactly that: deleting the residency release and the
        // `loadedView.reset()` from the teardown left this test green.
        //
        // They are still released, because a real cancelled open CAN hold a
        // resident buffer and a cropped view. Pinning that needs a fixture that
        // reaches those states first, which this one cannot — recorded in
        // docs/open-items.md rather than papered over with an assertion that
        // looks like coverage.
    }

    func testDiscardingClearsTheCalibrationRatherThanLeavingItBehind() async {
        // A calibration read from a file whose cube was never finished is the
        // most dangerous thing to leave behind: it is exactly the kind of value
        // that reads as trustworthy and describes data the app does not have.
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertNotNil(state.calibration.origin,
                        "precondition: the demo fixture carries origin maps")

        await state.discardPartialLoad()
        XCTAssertNil(state.calibration.origin)
        XCTAssertNil(state.calibration.qPixelSize)
        XCTAssertEqual(state.calibration.originProvenance, .geometricDefault)
    }

    func testCancellationIsMonotonicAndIdempotent() {
        let token = AnalysisCancellationToken()
        XCTAssertFalse(token.isCancelled)
        token.cancel()
        token.cancel()
        XCTAssertTrue(token.isCancelled, "cancellation never un-cancels")
    }
}
