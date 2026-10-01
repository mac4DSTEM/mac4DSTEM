import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane CR1: code-review findings (2026-10-01).
@MainActor
final class CR1ReviewFixTests: XCTestCase {

    private func openedState() async -> AppState {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        return state
    }

    /// Mutation: `recordReplayStep`'s skipped branch not unstamping -- the replayed
    /// product keeps the previous run's `lineage_step`.
    func testReplayedVirtualDetectorProductNeverCarriesAnotherRunsStep() async throws {
        let state = await openedState()
        state.navigation.analysisMode = .virtualDetector
        state.resultPresentation.virtualShape = .circle
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 9)
        let r = await state.runVirtualDetector()
        XCTAssertEqual(r, .published)
        let stepA = try XCTUnwrap(state.resultPresentation.product?.provenance["lineage_step"])
        // A saved product ends the run's collapsibility (R3); otherwise B folds into A's node.
        state.replay.markProduct(step: stepA, as: "saved_a")
        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 5)
        let r2 = await state.runVirtualDetector()
        XCTAssertEqual(r2, .published)
        let stepB = try XCTUnwrap(state.resultPresentation.product?.provenance["lineage_step"])
        XCTAssertNotEqual(stepA, stepB)

        state.aperture = Aperture(centerX: 32, centerY: 32, inner: 0, outer: 9)
        let r3 = await state.runVirtualDetector(replaying: true)
        XCTAssertEqual(r3, .published)
        XCTAssertNotEqual(state.resultPresentation.product?.provenance["lineage_step"], stepB,
                          "the replayed product carries run B's step")
    }

    /// Mutation: `deliverWriteProgress` without the `isCurrentOperation` guard.
    func testLateProgressAfterTheOperationFinishedIsDropped() {
        let state = AppState()
        let token = state.beginCancellableOperation("t", status: "s", totalUnits: 4)
        var seen: [Double] = []
        state.deliverWriteProgress(token, 0.5) { seen.append($0) }
        XCTAssertEqual(seen, [0.5], "a live operation delivers")
        state.finishCancellableOperation(token)
        state.deliverWriteProgress(token, 0.9) { seen.append($0) }
        XCTAssertEqual(seen, [0.5], "a late tick re-armed the sheet")
    }

    /// Mutation: dropping the same-unit guard in `setManualQPixelUnits`.
    func testSettingTheSameQUnitsAgainChangesNothing() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.setManualQPixelSize(0.12)
        state.setManualQPixelUnits("Å⁻¹")
        state.calibrationSession.provenance.qScale = nil   // a marker the guard must leave alone
        state.setManualQPixelUnits("Å⁻¹")
        XCTAssertNil(state.calibrationSession.provenance.qScale, "an unchanged unit flipped provenance to manual")
    }

    /// Mutation: removing the finite guard.
    func testNonFiniteAngleIsNotPrintedAsZero() {
        XCTAssertEqual(RQRotationConvention.degreesText(.nan), "—")
        XCTAssertEqual(RQRotationConvention.degreesText(.infinity), "—")
        XCTAssertEqual(RQRotationConvention.degreesText(12.34), "12.3°")
    }
}
