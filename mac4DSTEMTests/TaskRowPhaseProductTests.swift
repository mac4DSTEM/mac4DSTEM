//
//  TaskRowPhaseProductTests.swift
//  The sidebar task row judges a held parallax or single-slice ptychography
//  product (`AppState.taskProductState(for:)`): current right after the run,
//  stale once a control the step records moves. Red before: `taskHasProduct`
//  returned false for both tasks, so the row read `.none` whatever was held.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class TaskRowPhaseProductTests: XCTestCase {

    private func demo() async -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        if state.calibrationSession.acceleratingVoltage == nil { state.calibrationSession.acceleratingVoltage = 80 }
        if state.calibrationSession.calibration.rotationRad == nil { state.calibrationSession.calibration.rotationRad = 0 }
        return state
    }

    func testAHeldParallaxDepthReadsStaleInTheTaskRowWhenItsPlaneCountMoves() async throws {
        let state = await demo()
        state.changeMode(.ptychography)
        XCTAssertEqual(state.taskProductState(for: .ptychography), .none, "nothing held before the preprocess")

        var outcome = await state.prepareParallaxPreview()
        XCTAssertEqual(outcome, .published, state.statusText)
        while state.phaseContrast.parallaxAlignment?.isComplete != true {
            outcome = await state.alignParallaxNextLevel()
            guard outcome == .published else { return XCTFail(state.statusText) }
        }
        XCTAssertEqual(state.fitParallaxAberrations(), .published, state.statusText)
        state.phaseContrast.parallaxDepthPlaneCount = 3
        outcome = await state.computeParallaxDepthSections()
        XCTAssertEqual(outcome, .published, state.statusText)
        XCTAssertEqual(state.taskProductState(for: .ptychography), .current, "the row reads the held run as current")

        state.phaseContrast.parallaxDepthPlaneCount = 5
        let reason = try XCTUnwrap(state.taskProductState(for: .ptychography).staleReason,
                                   "a moved depth control does not read stale in the task row")
        XCTAssertFalse(reason.isEmpty)
    }

    func testAHeldPtychographyReadsStaleInTheTaskRowWhenItsIterationsMove() async throws {
        let state = await demo()
        state.changeMode(.singleslicePtychography)
        XCTAssertEqual(state.taskProductState(for: .singleslicePtychography), .none, "nothing held before the run")
        state.ptychography.iterations = 1
        state.ptychography.defocusAngstrom = -600

        let outcome = await state.runSingleslicePtychography()
        XCTAssertEqual(outcome, .published, state.statusText)
        XCTAssertEqual(state.taskProductState(for: .singleslicePtychography), .current,
                       "the row reads the held reconstruction as current")

        state.ptychography.iterations = 2
        let reason = try XCTUnwrap(state.taskProductState(for: .singleslicePtychography).staleReason,
                                   "a moved iteration count does not read stale in the task row")
        XCTAssertFalse(reason.isEmpty)
    }
}
