import Foundation
import DSTEMCore
import XCTest
@testable import mac4DSTEM

final class AnalysisOperationControllerTests: XCTestCase {
    func testReplacementCancelsOldTokenAndRejectsLateFinish() {
        var now = Date(timeIntervalSinceReferenceDate: 100)
        let controller = AnalysisOperationController(now: { now })
        let first = controller.begin(name: "first", totalUnits: 10)
        now.addTimeInterval(2)
        let second = controller.begin(name: "second", totalUnits: 20)

        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(second.isCancelled)
        XCTAssertFalse(controller.isCurrent(first))
        XCTAssertTrue(controller.isCurrent(second))
        XCTAssertFalse(controller.finish(first))
        XCTAssertEqual(controller.name, "second")
        XCTAssertTrue(controller.finish(second))
        XCTAssertFalse(controller.hasActiveOperation)
    }

    func testMetricsUseInjectedClockAndClampProgress() {
        var now = Date(timeIntervalSinceReferenceDate: 200)
        let controller = AnalysisOperationController(now: { now })
        _ = controller.begin(name: "rows", totalUnits: 100)
        now.addTimeInterval(10)

        let halfway = controller.metrics(progress: 0.5)
        XCTAssertEqual(halfway?.elapsed, 10)
        XCTAssertEqual(halfway?.unitsPerSecond, 5)
        XCTAssertEqual(halfway?.eta, 10)

        let complete = controller.metrics(progress: 1.5)
        XCTAssertEqual(complete?.unitsPerSecond, 10)
        XCTAssertEqual(complete?.eta, 0)
    }

    func testCancelAndResetProvideFailureRecoveryBoundary() {
        let controller = AnalysisOperationController()
        let token = controller.begin(name: "recoverable", totalUnits: nil)
        XCTAssertEqual(controller.cancelCurrent(), "recoverable")
        XCTAssertTrue(token.isCancelled)
        XCTAssertNil(controller.cancelCurrent())

        controller.reset()
        XCTAssertFalse(controller.hasActiveOperation)
        XCTAssertNil(controller.metrics(progress: 0.5))

        let replacement = controller.begin(name: "replacement", totalUnits: 1)
        controller.reset()
        XCTAssertTrue(replacement.isCancelled)
        XCTAssertFalse(controller.isCurrent(replacement))
    }
}
