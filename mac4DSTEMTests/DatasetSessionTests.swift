import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class DatasetSessionTests: XCTestCase {

    func testConstructionDefaultsAreEmptyAndIdle() {
        let session = DatasetSession()

        XCTAssertNil(session.reader)
        XCTAssertNil(session.fourD)
        XCTAssertTrue(session.datasets.isEmpty)
        XCTAssertNil(session.preview)
        XCTAssertEqual(session.epoch, 0)
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.loadingProgress)
        XCTAssertNil(session.loadingStatus)
    }

    func testActivationInstallsOneReaderArrayPairAndAdvancesEpoch() async throws {
        let session = DatasetSession()
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let view = try LoadView(source: descriptor, specification: .fullExtent)

        session.beginActivation()
        session.install(reader: reader, view: view)

        XCTAssertTrue(session.reader === reader)
        XCTAssertNotNil(session.fourD)
        XCTAssertEqual(session.fourD?.view.descriptor, view.descriptor)
        XCTAssertEqual(session.epoch, 1)
    }

    func testRequestCancellationPreservesTheLoadingObserverEffects() {
        let session = DatasetSession()
        session.beginLoading("Opening…")

        XCTAssertTrue(session.requestCancellation())

        XCTAssertTrue(session.loadWasCancelled)
        XCTAssertTrue(session.isCancellingLoad)
        XCTAssertNil(session.loadingProgress)
        XCTAssertEqual(session.loadingStatus, "Cancelling…")
        XCTAssertFalse(session.canCancelLoad)
    }

    /// S5: two loads in flight. The older load's tail must not disarm Cancel
    /// for the newer one. Mutation it catches: drop the `=== owner` guard in
    /// `finishLoading(owner:)` (the pre-S5 unconditional clear) — the first
    /// finish then nils B's token and `canCancelLoad` goes false.
    func testAnOlderLoadsTailLeavesTheNewerLoadCancellable() {
        let session = DatasetSession()
        let older = session.beginLoading("Opening A…")
        let newer = session.beginLoading("Opening B…")

        XCTAssertFalse(session.finishLoading(owner: older),
                       "a superseded load's tail must change nothing")
        XCTAssertTrue(session.isLoading)
        XCTAssertTrue(session.loadCancellation === newer)
        XCTAssertEqual(session.loadingStatus, "Opening B…")
        XCTAssertTrue(session.canCancelLoad, "Cancel must stay armed for the running load")

        XCTAssertTrue(session.finishLoading(owner: newer))
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.loadCancellation)
        XCTAssertFalse(session.finishLoading(owner: newer),
                       "a second finish of the same load is a no-op")
    }

    /// The same through AppState, whose wrapper also owns the busy flag.
    /// Mutation it catches: `finishDatasetLoading(owner:)` ignoring the
    /// session's refusal (calling `setBusy(false)` unconditionally).
    func testAnOlderLoadsTailLeavesTheNewerLoadBusy() {
        let state = AppState()
        let older = state.beginDatasetLoading("Opening A…")
        let newer = state.beginDatasetLoading("Opening B…")

        state.finishDatasetLoading(owner: older)
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(state.datasetSession.canCancelLoad)

        state.finishDatasetLoading(owner: newer)
        XCTAssertFalse(state.isBusy)
        XCTAssertFalse(state.datasetSession.isLoading)
    }

    func testDiscardClearsOwnedStateAndAdvancesEpochAgain() async throws {
        let session = DatasetSession()
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        let view = try LoadView(source: descriptor, specification: .fullExtent)
        session.beginActivation()
        session.install(reader: reader, view: view)
        session.prepare(reader: reader, datasets: [descriptor])

        session.clearReaderAndArray()
        session.clearDatasetListAndPreview()
        session.advanceEpochAfterDiscard()

        XCTAssertNil(session.reader)
        XCTAssertNil(session.fourD)
        XCTAssertTrue(session.datasets.isEmpty)
        XCTAssertEqual(session.epoch, 2)
    }

    func testAppStateHoldsTheSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("datasetSession"))
        for oldName in ["reader", "fourD", "datasets", "datasetPreview", "datasetEpoch"] {
            XCTAssertFalse(names.contains(oldName), "\(oldName) must not shadow DatasetSession")
        }
    }
}
