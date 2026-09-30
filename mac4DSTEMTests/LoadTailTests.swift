//
//  LoadTailTests.swift
//  S18 (a): a load's cancelled tail resets the session only while that load
//  is still the current one.
//
//  BEFORE: `if datasetSession.loadWasCancelled { await discardPartialLoad() }`
//  read the CURRENT load's token and ran the reset whoever owned the tail, so
//  with two loads in flight (the older one's tail running after a newer load
//  began) the older tail discarded the newer load's dataset. The owned cancel
//  token of S5 stopped that tail clearing busy, not the reset.
//
//  Two loads in flight is driven through the seam the tails themselves use,
//  `unwindLoadIfNeeded(owner:orNoDataset:)`: the second `beginDatasetLoading`
//  supersedes the first exactly as a promote/replay started under a live load
//  would. (`openFile` and promote refuse a second load while one runs, so the
//  overlap is not reachable by a click today; the reset must still not depend
//  on that.)
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class LoadTailTests: XCTestCase {

    private func loadedState() async -> AppState {
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset, "precondition: a dataset to lose")
        return state
    }

    /// Mutation it catches: the helper resets whatever load is current
    /// (the pre-S18 tail), or resets on any cancelled token.
    func testASupersededLoadsCancelledTailLeavesTheCurrentLoadsDatasetAlone() async {
        let state = await loadedState()
        let older = state.beginDatasetLoading("Older load")
        _ = state.beginDatasetLoading("Newer load")
        XCTAssertTrue(state.datasetSession.requestCancellation(),
                      "precondition: the NEWER (current) load is the one cancelled")
        let epoch = state.datasetSession.epoch

        let stop = await state.unwindLoadIfNeeded(owner: older)

        XCTAssertTrue(stop, "the tail still stops — the current load is cancelled")
        XCTAssertTrue(state.hasDataset, "but it must not reset the session it no longer owns")
        XCTAssertEqual(state.datasetSession.epoch, epoch, "no discard ran: the epoch did not advance")
        XCTAssertTrue(state.datasetSession.isLoading, "and the newer load is still the load in flight")
    }

    /// The guard must not swallow the ordinary case. Mutation it catches: the
    /// owner check made unconditionally false (a cancelled open never unwinds).
    func testTheCurrentLoadsCancelledTailStillResets() async {
        let state = await loadedState()
        let load = state.beginDatasetLoading("Only load")
        state.cancelDatasetLoad()

        let stop = await state.unwindLoadIfNeeded(owner: load)

        XCTAssertTrue(stop)
        XCTAssertFalse(state.hasDataset, "a cancelled current load unwinds to the welcome screen")
        XCTAssertNil(state.descriptor)
    }

    /// A load cancelled and then superseded is still cancelled: its tail must
    /// stop although the token it reads through the session is now the newer,
    /// uncancelled one. Mutation it catches: the cancelled test reads only the
    /// session's current token.
    func testACancelledLoadThatWasSupersededStillStopsWithoutResetting() async {
        let state = await loadedState()
        let older = state.beginDatasetLoading("Older load")
        state.cancelDatasetLoad()
        _ = state.beginDatasetLoading("Newer load")
        XCTAssertFalse(state.datasetSession.loadWasCancelled, "precondition: the current token is fresh")
        let epoch = state.datasetSession.epoch

        let stop = await state.unwindLoadIfNeeded(owner: older)

        XCTAssertTrue(stop, "its own token is cancelled")
        XCTAssertTrue(state.hasDataset)
        XCTAssertEqual(state.datasetSession.epoch, epoch)
    }

    func testAnUncancelledLoadDoesNotStop() async {
        let state = await loadedState()
        let load = state.beginDatasetLoading("Only load")

        let stop = await state.unwindLoadIfNeeded(owner: load)

        XCTAssertFalse(stop)
        XCTAssertTrue(state.hasDataset)
    }

    /// The `orNoDataset` stop (`activate` presented its own error and left
    /// nothing loaded) resets for the current load only. Mutation it catches:
    /// the owner check applied to the cancelled branch alone.
    func testTheNoDatasetStopResetsOnlyForTheCurrentLoad() async {
        let state = AppState()
        let older = state.beginDatasetLoading("Older load")
        let newer = state.beginDatasetLoading("Newer load")
        let epoch = state.datasetSession.epoch

        let supersededStop = await state.unwindLoadIfNeeded(owner: older, orNoDataset: true)
        XCTAssertTrue(supersededStop, "nothing is loaded, so the caller stops")
        XCTAssertEqual(state.datasetSession.epoch, epoch, "but a superseded tail resets nothing")

        let currentStop = await state.unwindLoadIfNeeded(owner: newer, orNoDataset: true)
        XCTAssertTrue(currentStop)
        XCTAssertEqual(state.datasetSession.epoch, epoch &+ 1, "the current load's tail runs the reset")
    }
}
