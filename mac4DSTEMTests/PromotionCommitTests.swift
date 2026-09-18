import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PromotionCommitTests: XCTestCase {
    private func makePending() async throws -> PendingLoad {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        return PendingLoad(
            source: descriptor, reader: reader,
            url: URL(fileURLWithPath: descriptor.filePath),
            accessedSecurityScope: false, fileByteCount: nil
        )
    }

    func testCommitRefusalPreservesThePendingLoadForCorrection() async throws {
        let state = AppState()
        let pending = try await makePending()
        let qy = pending.source.qy
        let qx = pending.source.qx
        var mean = [Float](repeating: 0, count: qy * qx)
        mean[(qy / 2) * qx + qx / 2] = 100
        let pattern = DiffractionPattern(qy: qy, qx: qx, pixels: mean)
        pending.preview = DatasetPreview(
            realSpace: FloatImage(width: 1, height: 1, pixels: [1]),
            meanDP: pattern, maxDP: pattern,
            strideY: 1, strideX: 1, sampledPositions: 1, totalPositions: 1
        )
        pending.configuration.detectorCrop = AxisCrop(
            yOffset: 0, xOffset: 0, height: max(1, qy / 4), width: max(1, qx / 4)
        )
        XCTAssertNotNil(pending.directBeamRefusal, "precondition: crop excludes the sampled beam")
        state.promotionRun.replace(with: pending)

        state.commitPendingLoad()

        XCTAssertTrue(state.promotionRun.pendingLoad === pending,
                      "A refused commit must remain editable in the configurator")
    }

    func testDoubleCommitTransfersThePendingLoadOnlyOnce() async throws {
        let state = AppState()
        let pending = try await makePending()
        state.promotionRun.replace(with: pending)

        state.commitPendingLoad()
        XCTAssertNil(state.promotionRun.pendingLoad)
        state.commitPendingLoad()
        XCTAssertNil(state.promotionRun.pendingLoad,
                     "A second commit cannot transfer the same reader/security scope twice")

        for _ in 0..<100 where state.datasetSession.isLoading {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(state.datasetSession.isLoading)
    }
}
