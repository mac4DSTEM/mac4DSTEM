//
//  FCRow27LearnedThresholdCaptureTests.swift
//  Cloud review row 27 (Gate D): the learned run used the threshold captured before
//  the detach, but its recorded step read the live threshold afterwards.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FCRow27LearnedThresholdCaptureTests: XCTestCase {

    /// Mutation it catches: the step recorded from the live `threshold` (0.9, typed
    /// during the run) instead of the one the run used (0.5).
    func testRecordedLearnedThresholdIsTheOneTheRunUsed() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        state.navigation.analysisMode = .disks
        await state.generateProbeKernel()
        XCTAssertNotNil(state.learnedDetection.probeReference, "precondition: a probe reference")
        state.learnedDetection.detectorClass = .learned
        state.learnedDetection.threshold = 0.5

        let run = Task { await state.runDiskDetection() }
        // The operation begins in the same main-actor turn that captures the threshold.
        var spins = 0
        while !state.isBusy, spins < 100_000 { await Task.yield(); spins += 1 }
        XCTAssertTrue(state.isBusy, "precondition: the learned run is in flight: \(state.statusText)")
        state.learnedDetection.threshold = 0.9   // typed during Detect All
        let outcome = await run.value
        XCTAssertEqual(outcome, .published, state.statusText)

        let step = try XCTUnwrap(state.replay.record.steps.last { $0.kind == "disk_detection" })
        XCTAssertEqual(step.parameters["learned_threshold"], "0.5",
                       "the recorded step must carry the threshold the run used: \(step.parameters)")
    }
}
