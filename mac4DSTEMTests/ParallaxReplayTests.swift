//
//  ParallaxReplayTests.swift
//  Parallax in the replay record: every stage rewrites the task's one step
//  from what is held, the step parses back to the same plan (also through a
//  detector re-reference), a stage group is all or nothing and needs the
//  stages it stands on, the replay's calibration check refuses a session whose
//  calibration differs, and a replayed run records nothing.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ParallaxReplayTests: XCTestCase {

    private typealias Plan = ReplayStepPlan.ParallaxReplayPlan

    private let calibration = Plan.Calibration(
        scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: 0.0125, energyEV: 80_000, rotationRad: 0.2,
        transpose: false)

    private var fullPlan: Plan {
        Plan(calibration: calibration, alignmentLevels: 3, alignmentComplete: true, fitsAberrations: true,
             subpixel: .init(upsampleFactor: 2.5, kdeSigmaPixels: 0.25, lowpass: true, lanczosOrder: 3,
                             positionCorrectionIterations: 4, positionCorrectionCheckerboard: true),
             correction: .init(qLowpassInvAngstrom: 1.5, qHighpassInvAngstrom: 0.05),
             depth: .init(startAngstrom: -100, endAngstrom: 120, planeCount: 12, useFullFit: false,
                          informationLimitInvAngstrom: 1.2, informationPower: 2))
    }

    private func physical(reciprocal: Double = 0.0125, energyEV: Double = 80_000, originQX: Double = 30,
                          rotation: Double = 0.2, transpose: Bool = false) -> ParallaxPhysicalCalibration {
        ParallaxPhysicalCalibration(
            scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: reciprocal, energyEV: energyEV,
            wavelengthAngstrom: 0.0418, originQX: originQX, originQY: 31.5, rotationRad: rotation,
            transpose: transpose)
    }

    private func step(_ parameters: [String: String]) -> SessionReplayRecord.Step {
        SessionReplayRecord.Step(kind: "parallax", parameters: parameters, recorded: Date(timeIntervalSince1970: 0))
    }

    private struct NotAParallaxPlan: Error {}

    private func plan(from parameters: [String: String]) throws -> Plan {
        guard case .parallax(let plan) = try ReplayPlanner.parse(step(parameters)).get() else {
            throw NotAParallaxPlan()
        }
        return plan
    }

    private func refusal(_ parameters: [String: String]) -> String? {
        if case .failure(let refusal) = ReplayPlanner.parse(step(parameters)) { return refusal.reason }
        return nil
    }

    func testTheRecordedStepParsesBackToWhatRan() throws {
        XCTAssertEqual(try plan(from: fullPlan.recordedParameters), fullPlan)
        let preprocessedOnly = Plan(calibration: calibration, alignmentLevels: 0, alignmentComplete: false,
                                    fitsAberrations: false, subpixel: nil, correction: nil, depth: nil)
        XCTAssertEqual(try plan(from: preprocessedOnly.recordedParameters), preprocessedOnly)
        XCTAssertNil(preprocessedOnly.recordedParameters["kde_sigma_px"], "a stage not reached writes no keys")
    }

    /// A stage's keys come together, and a stage needs what it stands on.
    func testAStageIsAllOrNothingAndNeedsItsUpstream() {
        var partial = fullPlan.recordedParameters
        partial["kde_lowpass"] = nil
        XCTAssertEqual(refusal(partial)?.contains("kde_lowpass"), true, refusal(partial) ?? "parsed")

        var kdeOnPartialAlignment = fullPlan
        kdeOnPartialAlignment.alignmentComplete = false
        XCTAssertEqual(refusal(kdeOnPartialAlignment.recordedParameters)?.contains("KDE"), true)

        var depthWithoutFit = fullPlan
        depthWithoutFit.fitsAberrations = false
        depthWithoutFit.correction = nil
        XCTAssertEqual(refusal(depthWithoutFit.recordedParameters)?.contains("depth"), true)

        var fitWithoutAlignment = fullPlan
        fitWithoutAlignment.alignmentLevels = 0
        fitWithoutAlignment.alignmentComplete = false
        fitWithoutAlignment.subpixel = nil
        XCTAssertNotNil(refusal(fitWithoutAlignment.recordedParameters))
    }

    /// A rehearsal on a ×2-binned, cropped detector: the Q sampling halves,
    /// every other key (scan pixels, Å, Å⁻¹, counts) stays.
    func testADetectorReReferenceHalvesTheQSamplingAndKeepsTheRest() throws {
        let mapped = try ReplayRecordFrameMap.map(step(fullPlan.recordedParameters),
                                                  through: .viewToSource(bin: 2, xOffset: 3, yOffset: 5)).get()
        var expected = fullPlan
        expected.calibration.reciprocalSamplingInvAngstrom = 0.0125 / 2
        XCTAssertEqual(try plan(from: mapped.parameters), expected)
    }

    func testTheReplayRefusesASessionWhoseCalibrationDiffers() throws {
        let parsed = try plan(from: fullPlan.recordedParameters)
        XCTAssertNil(parsed.calibrationRefusal(against: physical()))
        XCTAssertNil(parsed.calibrationRefusal(against: physical(originQX: 12)), "parallax never reads the origin")
        XCTAssertNil(parsed.calibrationRefusal(against: physical(reciprocal: 0.0125 * (1 + 5e-5))))
        let q = try XCTUnwrap(parsed.calibrationRefusal(against: physical(reciprocal: 0.0125 * 1.01)))
        XCTAssertTrue(q.contains("Q sampling") && q.contains("run parallax by hand"), q)
        let kv = try XCTUnwrap(parsed.calibrationRefusal(against: physical(energyEV: 300_000)))
        XCTAssertTrue(kv.contains("300 kV"), kv)
        XCTAssertNotNil(parsed.calibrationRefusal(against: physical(rotation: 0.2 + .pi)))
        XCTAssertNotNil(parsed.calibrationRefusal(against: physical(transpose: true)))
    }

    func testTheControlsRoundTripAndAStageNotReachedKeepsItsFields() {
        let product = PhaseContrastProduct()
        product.apply(fullPlan)
        XCTAssertEqual(product.parallaxSubpixelSettings, fullPlan.subpixel)
        XCTAssertEqual(product.parallaxCorrectionSettings, fullPlan.correction)
        XCTAssertEqual(product.parallaxDepthSettings, fullPlan.depth)

        let fresh = PhaseContrastProduct()
        let before = fresh.parallaxDepthSettings
        fresh.apply(Plan(calibration: calibration, alignmentLevels: 1, alignmentComplete: false,
                         fitsAberrations: false, subpixel: nil, correction: nil, depth: nil))
        XCTAssertEqual(fresh.parallaxDepthSettings, before)
        XCTAssertEqual(fresh.parallaxCurrentSignature, [:], "no later stage held: nothing to compare")
    }

    /// Red before the record: parallax recorded nothing, so a promote dropped
    /// it silently. Each stage rewrites the one step; the staleness signature
    /// agrees with it; a replay runs the stages again and records nothing.
    func testEachStageRewritesTheStepAndAReplayedRunDoesNot() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        if state.calibrationSession.acceleratingVoltage == nil { state.calibrationSession.acceleratingVoltage = 80 }
        if state.calibrationSession.calibration.rotationRad == nil { state.calibrationSession.calibration.rotationRad = 0 }
        state.changeMode(.ptychography)

        func recorded() throws -> Plan {
            let steps = state.replay.record.steps.filter { $0.kind == "parallax" }
            XCTAssertEqual(steps.count, 1, "one step for the task")
            return try plan(from: try XCTUnwrap(steps.first, "no parallax step").parameters)
        }

        var outcome = await state.prepareParallaxPreview()
        XCTAssertEqual(outcome, .published, state.statusText)
        var step = try recorded()
        XCTAssertEqual(step.alignmentLevels, 0)
        XCTAssertFalse(step.fitsAberrations)
        XCTAssertNil(state.replayParallaxCalibrationRefusal(step), "the session's own calibration agrees")

        outcome = await state.alignParallaxNextLevel()
        XCTAssertEqual(outcome, .published, state.statusText)
        step = try recorded()
        XCTAssertEqual(step.alignmentLevels, 1)
        XCTAssertEqual(step.alignmentComplete, state.phaseContrast.parallaxAlignment?.isComplete)

        while state.phaseContrast.parallaxAlignment?.isComplete != true {
            outcome = await state.alignParallaxNextLevel()
            guard outcome == .published else { return XCTFail(state.statusText) }
        }
        XCTAssertEqual(state.fitParallaxAberrations(), .published, state.statusText)
        state.phaseContrast.parallaxDepthPlaneCount = 3
        outcome = await state.computeParallaxDepthSections()
        XCTAssertEqual(outcome, .published, state.statusText)
        step = try recorded()
        XCTAssertTrue(step.alignmentComplete)
        XCTAssertTrue(step.fitsAberrations)
        XCTAssertEqual(step.depth, state.phaseContrast.parallaxDepthSettings)
        XCTAssertNil(step.subpixel, "KDE did not run")

        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: state.recordedReplayStep(for: .ptychography),
            currentSignature: state.currentReplaySignature(for: .ptychography), hasProduct: true), .current)
        state.phaseContrast.parallaxDepthPlaneCount = 5
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: state.recordedReplayStep(for: .ptychography),
            currentSignature: state.currentReplaySignature(for: .ptychography), hasProduct: true),
            .stale(changedKeys: ["depth_plane_count"]))

        let before = state.replay.record
        state.phaseContrast.apply(step)
        outcome = await state.runParallaxReplay(step)
        XCTAssertEqual(outcome, .published, state.statusText)
        XCTAssertEqual(state.replay.record, before, "a replayed run records nothing")
        XCTAssertEqual(state.phaseContrast.parallaxDepth?.planeCount, 3, "the recorded controls ran")

        // Reset drops every later stage with no stage publishing: the step follows.
        state.resetParallaxAlignment()
        step = try recorded()
        XCTAssertEqual(step.alignmentLevels, 0)
        XCTAssertFalse(step.fitsAberrations)
        XCTAssertNil(step.depth)
    }
}
