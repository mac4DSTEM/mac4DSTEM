import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PromotionRunTests: XCTestCase {
    private func makePending() async throws -> PendingLoad {
        let reader = DemoFourDDataSource()
        let descriptor = try await reader.discoverPrimaryDataset()
        return PendingLoad(
            source: descriptor,
            reader: reader,
            url: URL(fileURLWithPath: descriptor.filePath),
            accessedSecurityScope: false,
            fileByteCount: nil
        )
    }

    func testConstructionStartsWithoutAPendingLoad() {
        XCTAssertNil(PromotionRun<PendingLoad>().pendingLoad)
    }

    func testReplacementReturnsTheExactDisplacedLoad() async throws {
        let run = PromotionRun<PendingLoad>()
        let first = try await makePending()
        let second = try await makePending()

        XCTAssertNil(run.replace(with: first))
        XCTAssertTrue(run.replace(with: second) === first)
        XCTAssertTrue(run.pendingLoad === second)
    }

    func testTakeReturnsExactIdentityClearsAndConsumesOnlyOnce() async throws {
        let run = PromotionRun<PendingLoad>()
        let pending = try await makePending()
        run.replace(with: pending)

        XCTAssertTrue(run.take() === pending)
        XCTAssertNil(run.pendingLoad)
        XCTAssertNil(run.take())
    }

    func testAppStateHoldsTheOwnerWithoutAPendingLoadForwarder() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("promotionRun"))
        XCTAssertFalse(names.contains("pendingLoad"))
    }
}
