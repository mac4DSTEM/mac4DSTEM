import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#338: Map Phases and Find Matrix Zone Axis match vector lengths in Å⁻¹, so the vectors must be centred on a
/// measured beam centre. On Thronsen A two dark-field detectors placed on spots set the fitted origin aside, the vectors were
/// re-centred on the second spot (18 px off the beam), and the zone-axis fit read 26 of 2009 vectors (chance) and the map
/// called θ′ face-on everywhere, with nothing said. Both runs now refuse on such an origin and say how to get the beam back.
@MainActor
final class PhaseMappingOriginGateTests: XCTestCase {

    private var smallCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    /// The demo with its origin fitted, its disks detected and the Al-Mg-Si phase list.
    private func preparedState() async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(specification: smallCrop)
        _ = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        XCTAssertNotNil(state.calibrationSession.calibration.origin, "precondition: fitted maps. \(state.statusText)")
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, state.statusText)
        let beta = try XCTUnwrap(CrystalModelLibrary.model(id: "mg_hcp"))
        state.phaseMapping.applyAlMgSiPreset(precipitate: beta)
        return state
    }

    /// Moves the virtual detector's centre `offset` px off where it is, as a drag or the door's set_virtual_detector does.
    private func moveDetector(_ state: AppState, by offset: Float) {
        var moved = state.aperture
        moved.centerX += offset
        moved.centerY -= offset
        state.updateAperture(moved)
    }

    /// Mutation: the origin refusal dropped from `runPhaseMapping` -> the run publishes a map on the detector's centre -> red.
    func testADetectorMovedOffTheBeamStopsPhaseMappingUntilTheOriginIsBack() async throws {
        let state = try await preparedState()
        XCTAssertNil(state.phaseMappingOriginRefusal, "a fitted origin is a measured beam centre")
        XCTAssertNil(state.matrixZoneAxisRefusal, state.matrixZoneAxisRefusal ?? "")

        moveDetector(state, by: 12)
        XCTAssertTrue(state.canRestoreFittedOrigin, "precondition: the fitted origin was set aside")
        let refusal = try XCTUnwrap(state.phaseMappingOriginRefusal)
        XCTAssertTrue(refusal.contains("Restore Fitted Origin"), refusal)
        XCTAssertEqual(state.matrixZoneAxisRefusal, refusal, "the button is disabled with the same sentence")

        state.navigation.analysisMode = .phaseMapping
        let refused = await state.runPhaseMapping()
        XCTAssertEqual(refused, .failed(refusal))
        XCTAssertNil(state.phaseMapping.map, "nothing is mapped on the detector's centre")
        let zoneAxis = await state.findMatrixZoneAxis()
        XCTAssertEqual(zoneAxis, .failed(refusal))

        state.restoreFittedOrigin()
        XCTAssertNil(state.phaseMappingOriginRefusal)
        let outcome = await state.runPhaseMapping()
        XCTAssertEqual(outcome, .published, state.statusText)
    }

    /// Without any measured centre (no fit, no recorded one) the refusal asks for Calibrate Origin, not for a restore.
    func testNoMeasuredCentreAsksForCalibrateOrigin() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false, specification: smallCrop)
        _ = try XCTUnwrap(state.descriptor, state.statusText)
        state.calibrationSession.calibration.origin = nil
        state.calibrationSession.calibration.recordedOriginX = nil
        state.calibrationSession.calibration.recordedOriginY = nil
        let refusal = try XCTUnwrap(state.phaseMappingOriginRefusal)
        XCTAssertTrue(refusal.contains("Calibrate Origin"), refusal)
        XCTAssertFalse(refusal.contains("Restore"), refusal)
    }
}
