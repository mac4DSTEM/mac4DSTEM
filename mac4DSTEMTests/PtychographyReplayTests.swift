//
//  PtychographyReplayTests.swift
//  Single-slice ptychography in the replay record: the run records a step from
//  what it ran with, the step parses back to the same plan (also through a
//  detector re-reference), the replay's calibration check refuses a session
//  whose calibration differs, and a replayed run records nothing.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PtychographyReplayTests: XCTestCase {

    private typealias Plan = ReplayStepPlan.PtychographyReplayPlan

    private let settings = Plan.Settings(
        iterations: 3, stepSize: 0.25, normalizationMinimum: 0.5, fixProbe: false, constrainObjectAmplitude: true,
        purePhaseObject: false, fixProbeCenterOfMass: true, constrainProbeAmplitude: false,
        probeAmplitudeRadius: 0.4, probeAmplitudeWidth: 0.1, defocusAngstrom: -600, c12aAngstrom: 35, c12bAngstrom: -20)

    private func physical(reciprocal: Double = 0.0125, energyEV: Double = 80_000, originQX: Double = 30,
                          originQY: Double = 31.5, rotation: Double = 0.2, transpose: Bool = false)
        -> ParallaxPhysicalCalibration {
        ParallaxPhysicalCalibration(
            scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: reciprocal, energyEV: energyEV,
            wavelengthAngstrom: 0.0418, originQX: originQX, originQY: originQY, rotationRad: rotation,
            transpose: transpose)
    }

    private func step(_ parameters: [String: String]) -> SessionReplayRecord.Step {
        SessionReplayRecord.Step(kind: "ptychography", parameters: parameters, recorded: Date(timeIntervalSince1970: 0))
    }

    private struct NotAPtychographyPlan: Error {}

    private func plan(from parameters: [String: String]) throws -> Plan {
        guard case .ptychography(let plan) = try ReplayPlanner.parse(step(parameters)).get() else {
            throw NotAPtychographyPlan()
        }
        return plan
    }

    func testTheRecordedStepParsesBackToWhatRan() throws {
        let recorded = Plan.recordedParameters(settings: settings, probeRadiusPixels: 9, calibration: physical())
        let parsed = try plan(from: recorded)
        XCTAssertEqual(parsed.settings, settings)
        XCTAssertEqual(parsed.probeRadiusPixels, 9)
        XCTAssertEqual(parsed.calibration, Plan.Calibration(physical()))
        XCTAssertNil(parsed.calibrationRefusal(against: physical()), "the calibration the run used agrees with itself")
    }

    /// A rehearsal on a ×2-binned, cropped detector: the probe radius and the
    /// origin move into the source frame, the Q sampling halves, the rest stays.
    func testADetectorReReferenceMovesThePixelNumbersAndKeepsTheRest() throws {
        let recorded = Plan.recordedParameters(settings: settings, probeRadiusPixels: 9, calibration: physical())
        let mapped = try ReplayRecordFrameMap.map(step(recorded), through: .viewToSource(bin: 2, xOffset: 3, yOffset: 5)).get()
        let parsed = try plan(from: mapped.parameters)
        let transform = ReplayFrameTransform.viewToSource(bin: 2, xOffset: 3, yOffset: 5)
        XCTAssertEqual(parsed.probeRadiusPixels, 18)
        XCTAssertEqual(parsed.calibration.reciprocalSamplingInvAngstrom, 0.0125 / 2)
        XCTAssertEqual(parsed.calibration.originQY, Double(transform.positionX(31.5)), "the column moves with the x offset")
        XCTAssertEqual(parsed.calibration.originQX, Double(transform.positionY(30)), "the row moves with the y offset")
        XCTAssertEqual(parsed.settings, settings)
        XCTAssertEqual(parsed.calibration.scanSamplingAngstrom, 0.5)
        XCTAssertEqual(parsed.calibration.energyEV, 80_000)
    }

    func testTheReplayRefusesASessionWhoseCalibrationDiffers() throws {
        let parsed = try plan(from: Plan.recordedParameters(settings: settings, probeRadiusPixels: 9,
                                                            calibration: physical()))
        XCTAssertNil(parsed.calibrationRefusal(against: physical(reciprocal: 0.0125 * (1 + 5e-5))),
                     "a Q sampling inside ACOM's derivation tolerance is the same calibration")
        let q = try XCTUnwrap(parsed.calibrationRefusal(against: physical(reciprocal: 0.0125 * 1.01)))
        XCTAssertTrue(q.contains("Q sampling"), q)
        let kv = try XCTUnwrap(parsed.calibrationRefusal(against: physical(energyEV: 300_000)))
        XCTAssertTrue(kv.contains("300 kV"), kv)
        let rotation = try XCTUnwrap(parsed.calibrationRefusal(against: physical(rotation: 0.2 + .pi)))
        XCTAssertTrue(rotation.contains("rotation"), rotation)
        XCTAssertNotNil(parsed.calibrationRefusal(against: physical(transpose: true)))
        let origin = try XCTUnwrap(parsed.calibrationRefusal(against: physical(originQY: 31.6)))
        XCTAssertTrue(origin.contains("origin"), origin)
        XCTAssertNil(parsed.calibrationRefusal(against: physical(originQY: 31.5 + 1e-4)))
    }

    func testTheSettingsRoundTripThroughTheControls() {
        let controls = PtychographySettings()
        controls.apply(settings)
        XCTAssertEqual(controls.replaySettings, settings)
    }

    /// Red before the record: the run published and recorded nothing, so a
    /// promote dropped the reconstruction silently. The step carries what ran,
    /// the run says `.published`, the staleness signature agrees with the step
    /// until a control moves, and a replayed run records nothing.
    func testTheRunRecordsItsStepAndAReplayedRunDoesNot() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        if state.calibrationSession.acceleratingVoltage == nil { state.calibrationSession.acceleratingVoltage = 80 }
        if state.calibrationSession.calibration.rotationRad == nil { state.calibrationSession.calibration.rotationRad = 0 }
        state.changeMode(.singleslicePtychography)
        state.ptychography.iterations = 1
        state.ptychography.defocusAngstrom = -600

        let outcome = await state.runSingleslicePtychography()
        XCTAssertEqual(outcome, .published, state.statusText)
        let recorded = try XCTUnwrap(state.replay.record.steps.first { $0.kind == "ptychography" },
                                     "the run recorded no step")
        let parsed = try plan(from: recorded.parameters)
        XCTAssertEqual(parsed.settings, state.ptychography.replaySettings)
        XCTAssertEqual(parsed.probeRadiusPixels, state.aperture.outer)
        XCTAssertNil(state.replayPtychographyCalibrationRefusal(parsed), "the session's own calibration agrees")

        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: state.recordedReplayStep(for: .singleslicePtychography),
            currentSignature: state.currentReplaySignature(for: .singleslicePtychography), hasProduct: true), .current)
        state.ptychography.iterations = 2
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: state.recordedReplayStep(for: .singleslicePtychography),
            currentSignature: state.currentReplaySignature(for: .singleslicePtychography), hasProduct: true),
            .stale(changedKeys: ["iterations"]))

        let voltage = state.calibrationSession.acceleratingVoltage
        state.calibrationSession.acceleratingVoltage = (voltage ?? 80) + 100
        let refusal = try XCTUnwrap(state.replayPtychographyCalibrationRefusal(parsed))
        XCTAssertTrue(refusal.contains("accelerating voltage"), refusal)
        state.calibrationSession.acceleratingVoltage = voltage

        let before = state.replay.record
        let replayed = await state.runSingleslicePtychography(replaying: true)
        XCTAssertEqual(replayed, .published, state.statusText)
        XCTAssertEqual(state.replay.record, before, "a replayed run records nothing")
    }
}
