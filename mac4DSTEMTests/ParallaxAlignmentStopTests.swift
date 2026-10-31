//
//  ParallaxAlignmentStopTests.swift
//  A partial parallax alignment replays to the bin it stopped at, not to a
//  level count. The bin schedule comes from the bright-field diameter in
//  detector pixels, so a rehearsal on a binned detector can have one coarse
//  level more or less than the source, and the source has an extra finest
//  level: a count then replays other physical bins than the rehearsal ran.
//  The step records the stopping bin (a detector length, re-referenced with the
//  frame) and the passes made there; the replay stops at the first level of
//  the new schedule with that bin and that pass, or refuses by name.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ParallaxAlignmentStopTests: XCTestCase {

    private typealias Plan = ReplayStepPlan.ParallaxReplayPlan

    private let calibration = Plan.Calibration(
        scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: 0.0125, energyEV: 80_000, rotationRad: 0.2,
        transpose: false)

    /// A partial alignment that completed `bins` of a rehearsal schedule, as the stage records it.
    private func partial(_ bins: [Int]) -> Plan {
        Plan(calibration: calibration, alignmentLevels: bins.count, alignmentComplete: false,
             alignmentStop: .init(completedBins: bins), fitsAberrations: false, subpixel: nil, correction: nil, depth: nil)
    }

    private func step(_ parameters: [String: String]) -> SessionReplayRecord.Step {
        SessionReplayRecord.Step(kind: "parallax", parameters: parameters, recorded: Date(timeIntervalSince1970: 0))
    }

    private struct NotAParallaxPlan: Error {}

    /// The plan the replay runs on the source after a promote from a view binned by `bin`.
    private func promoted(_ plan: Plan, bin: Int) throws -> Plan {
        let mapped = try ReplayRecordFrameMap.map(step(plan.recordedParameters),
                                                  through: .viewToSource(bin: bin, xOffset: 0, yOffset: 0)).get()
        guard case .parallax(let parsed) = try ReplayPlanner.parse(mapped).get() else { throw NotAParallaxPlan() }
        return parsed
    }

    /// The issue case: the ×2 view rounds to one coarse level more than the source ([16, 8, …] in its pixels is 32, 16
    /// physical; the source starts at 16). Two levels stopped at physical bin 16: the source stops after its first level.
    /// A level count would have run the source's 16 and 8.
    func testAPartialAlignmentAcrossADetectorBinStopsAtTheSamePhysicalBin() throws {
        let rehearsal = partial([16, 8])
        XCTAssertEqual(rehearsal.alignmentStop, .init(bin: 8, passes: 1))
        let source = try promoted(rehearsal, bin: 2)
        XCTAssertEqual(source.alignmentStop, .init(bin: 16, passes: 1), "the stopping bin is a detector length")
        XCTAssertEqual(source.replayLevelCount(schedule: [16, 8, 4, 2, 1, 1]), 1)

        // Without the shift the same rule keeps the count: [8, 4] of the ×2 view is 16, 8 physical.
        XCTAssertEqual(try promoted(partial([8, 4]), bin: 2).replayLevelCount(schedule: [16, 8, 4, 2, 1, 1]), 2)
    }

    /// The finest bin repeats: the passes made there decide where the replay stops, in either frame.
    func testThePassesAtTheFinestBinAreCounted() throws {
        XCTAssertEqual(partial([4, 2, 1]).replayLevelCount(schedule: [4, 2, 1, 1]), 3)
        XCTAssertEqual(partial([4, 2, 1, 1]).alignmentStop, .init(bin: 1, passes: 2))
        // The ×2 view's finest passes are the source's bin 2, which the source passes once.
        XCTAssertNil(try promoted(partial([4, 2, 1, 1]), bin: 2).replayLevelCount(schedule: [8, 4, 2, 1, 1]))
        XCTAssertEqual(try promoted(partial([4, 2, 1]), bin: 2).replayLevelCount(schedule: [8, 4, 2, 1, 1]), 3)
    }

    /// No matching physical bin: refused with the stop and the schedule named. A complete alignment and none at all
    /// never need one.
    func testNoMatchingBinRefusesByNameAndCompleteOrNoneNeedsNone() throws {
        let thrice = try promoted(partial([2, 1]), bin: 3)
        XCTAssertNil(thrice.replayLevelCount(schedule: [8, 4, 2, 1, 1]))
        let reason = thrice.alignmentStopRefusal(schedule: [8, 4, 2, 1, 1])
        XCTAssertTrue(reason.contains("bin 3 px") && reason.contains("8, 4, 2, 1, 1"), reason)

        var complete = partial([4, 2, 1, 1])
        complete.alignmentComplete = true
        XCTAssertEqual(complete.replayLevelCount(schedule: [8, 4, 2, 1, 1]), 5)
        XCTAssertEqual(partial([]).replayLevelCount(schedule: [8, 4, 2, 1, 1]), 0)
        XCTAssertNil(partial([]).recordedParameters["alignment_bin"], "no level: no stop")
    }

    /// An export binned ×2 keeps the recipe: a stop at bin 1 becomes 0.5, which matches no level, so only a partial
    /// alignment replayed from it refuses; a complete one still replays to the end.
    func testABinnedExportKeepsTheRecipeAndAFractionalStopMatchesNoLevel() throws {
        let mapped = try ReplayRecordFrameMap.map(step(partial([4, 2, 1]).recordedParameters),
                                                  through: .viewToExport(bin: 2)).get()
        guard case .parallax(let exported) = try ReplayPlanner.parse(mapped).get() else { throw NotAParallaxPlan() }
        XCTAssertEqual(exported.alignmentStop, .init(bin: 0.5, passes: 1))
        XCTAssertNil(exported.replayLevelCount(schedule: [2, 1, 1]))
    }

    /// The stop is required with a level and refused without one.
    func testTheStopKeysComeWithALevelAndOnlyThen() {
        var missing = partial([4, 2]).recordedParameters
        missing["alignment_bin"] = nil
        XCTAssertNotNil(refusal(missing))
        var tooManyPasses = partial([4, 2]).recordedParameters
        tooManyPasses["alignment_bin_passes"] = "3"
        XCTAssertNotNil(refusal(tooManyPasses))
        var strayStop = partial([]).recordedParameters
        strayStop["alignment_bin"] = "4.0"
        strayStop["alignment_bin_passes"] = "1"
        XCTAssertNotNil(refusal(strayStop))
    }

    private func refusal(_ parameters: [String: String]) -> String? {
        if case .failure(let refusal) = ReplayPlanner.parse(step(parameters)) { return refusal.reason }
        return nil
    }

    /// In the app: the recorded step names the bin each stage stopped at, a replay stops at the recorded bin whatever
    /// the level count says, and a bin the schedule lacks refuses without aligning a level.
    func testTheReplayStopsAtTheRecordedBinNotTheCount() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        if state.calibrationSession.acceleratingVoltage == nil { state.calibrationSession.acceleratingVoltage = 80 }
        if state.calibrationSession.calibration.rotationRad == nil { state.calibrationSession.calibration.rotationRad = 0 }
        state.changeMode(.ptychography)

        var outcome = await state.prepareParallaxPreview()
        XCTAssertEqual(outcome, .published, state.statusText)
        outcome = await state.alignParallaxNextLevel()
        XCTAssertEqual(outcome, .published, state.statusText)
        let schedule = try XCTUnwrap(state.phaseContrast.parallaxAlignment?.alignmentSchedule)
        try XCTSkipUnless(schedule.count >= 3, "the demo schedule is too short to tell a count from a bin")
        var plan = try XCTUnwrap(state.phaseContrast.parallaxReplayPlan)
        XCTAssertEqual(plan.alignmentStop, .init(bin: Double(schedule[0]), passes: 1))

        plan.alignmentLevels = 2   // a count that disagrees with the stop: the stop decides
        state.resetParallaxAlignment()
        outcome = await state.runParallaxReplay(plan)
        XCTAssertEqual(outcome, .published, state.statusText)
        XCTAssertEqual(state.phaseContrast.parallaxAlignment?.completedBins, [schedule[0]])

        plan.alignmentStop = .init(bin: 3, passes: 1)
        outcome = await state.runParallaxReplay(plan)
        guard case .failed(let reason) = outcome else { return XCTFail("a bin the schedule lacks replayed: \(outcome)") }
        XCTAssertTrue(reason.contains("bin 3 px"), reason)
    }
}
