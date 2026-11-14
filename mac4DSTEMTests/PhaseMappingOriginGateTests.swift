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

    /// The calibrated demo (a physical Q scale) with its disks detected, the Al-Mg-Si phase list and fitted origin maps
    /// installed on the beam centre it recorded, as a Calibrate Origin run leaves them.
    private func preparedState() async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(specification: smallCrop)
        let d = try XCTUnwrap(state.descriptor, state.statusText)
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        XCTAssertNotNil(state.resultPresentation.braggVectors, state.statusText)
        let beam = state.calibrationSession.calibration.referenceOrigin(
            detectorQX: d.qx, detectorQY: d.qy, apertureCentre: (x: state.aperture.centerX, y: state.aperture.centerY)).point
        let count = d.rx * d.ry
        state.calibrationSession.calibration.origin = OriginMaps(
            width: d.rx, height: d.ry, measuredX: Array(repeating: beam.x, count: count),
            measuredY: Array(repeating: beam.y, count: count),
            fittedX: Array(repeating: beam.x, count: count), fittedY: Array(repeating: beam.y, count: count))
        state.calibrationSession.calibration.originProvenance = .fitted
        state.aperture.centerX = beam.x
        state.aperture.centerY = beam.y
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

        moveDetector(state, by: 12)
        XCTAssertTrue(state.canRestoreFittedOrigin, "precondition: the fitted origin was set aside")
        let refusal = try XCTUnwrap(state.phaseMappingOriginRefusal)
        XCTAssertTrue(refusal.contains("Restore Fitted Origin"), refusal)
        // Setting the origin aside is an origin step of its own; disks that name the origin they stood on read stale and
        // are refused first. Fresh disks, so the origin is what is left to refuse.
        if state.diskDetectionSettingsAreStale {
            state.navigation.analysisMode = .disks
            _ = await state.runDiskDetection()
            XCTAssertFalse(state.diskDetectionSettingsAreStale, state.statusText)
        }
        XCTAssertEqual(state.matrixZoneAxisRefusal, refusal, "the button is disabled with the same sentence")

        state.navigation.analysisMode = .phaseMapping
        let refused = await state.runPhaseMapping()
        XCTAssertEqual(refused, .failed(refusal))
        XCTAssertNil(state.phaseMapping.map, "nothing is mapped on the detector's centre")
        let zoneAxis = await state.findMatrixZoneAxis()
        XCTAssertEqual(zoneAxis, .failed(refusal))

        state.restoreFittedOrigin()
        XCTAssertNil(state.phaseMappingOriginRefusal, "the restored maps are a measured beam centre again")
        let outcome = await state.runPhaseMapping()
        XCTAssertNotEqual(outcome, .failed(refusal), state.statusText)
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
