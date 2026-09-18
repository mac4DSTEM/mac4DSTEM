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
