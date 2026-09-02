//
//  ReplayExecutionTests.swift
//  v2 S6 — the replay executor through a REAL AppState on the demo fixture
//  (the Gate B-lite F8 lesson: wiring that only file-level tests cover can be
//  deleted with the suite green). These pin the promote-and-replay path: the
//  recorded parameters are applied, the first problem halts the run, the
//  recipe survives its own replay, and detector-reduced recipes refuse.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReplayExecutionTests: XCTestCase {

    private var croppedSpec: LoadSpecification {
        var spec = LoadSpecification()
        // The demo cube is [12, 12, 64, 64]; a SCAN crop only — the detector
        // frame stays identity, which is what makes these recipes replayable.
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        return spec
    }

    // MARK: - The flagship path

    func testPromoteReplaysTheRecordedVirtualDetectorWithItsRecordedParameters() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        XCTAssertFalse(state.loadedView.isFullExtent, "precondition: rehearsing on a crop")

        state.virtualShape = .annulus
        state.aperture = Aperture(centerX: 30, centerY: 29, inner: 2, outer: 9)
        await state.runVirtualDetector()
        XCTAssertEqual(state.replay.record.steps.map(\.kind), ["virtual_detector"],
                       "precondition: the rehearsal recorded its step")

        // Drift the live state after recording: replay must run the RECIPE's
        // parameters, not whatever the session last touched.
        state.aperture = Aperture(centerX: 10, centerY: 10, inner: 0, outer: 25)
        state.virtualShape = .circle

        await state.promoteAndReplayRecipe()

        XCTAssertTrue(state.loadedView.isFullExtent, "The promote half must still promote")
        XCTAssertEqual(state.replayRun.phase, .finished)
        XCTAssertNil(state.replayRun.haltReason,
                     "A coherent one-step recipe must replay to completion")
        guard case .succeeded = state.replayRun.steps.first?.outcome else {
            return XCTFail("The step must be reported as succeeded, got \(String(describing: state.replayRun.steps.first?.outcome))")
        }
        XCTAssertEqual(state.aperture,
                       Aperture(centerX: 30, centerY: 29, inner: 2, outer: 9),
                       "Replay must apply the recorded aperture, not the drifted live one")
        XCTAssertEqual(state.virtualShape, .annulus)
        XCTAssertNotNil(state.resultImage, "The replayed analysis must have published")
        XCTAssertTrue(state.statusText.contains("Promote run finished"),
                      "statusText was: \(state.statusText)")
    }

    func testPromoteWithAnEmptyRecipeIsThePlainS3Promote() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        XCTAssertTrue(state.replay.record.isEmpty, "precondition")

        await state.promoteAndReplayRecipe()

        XCTAssertTrue(state.loadedView.isFullExtent)
        XCTAssertEqual(state.replayRun.phase, .idle,
                       "No recipe, no run — the summary section must not appear")
        XCTAssertNotNil(state.resultImage,
                        "The re-establishing pass must run when nothing will replay")
    }

    // MARK: - Halt honesty

    func testTheFirstProblemHaltsTheRunAndLaterStepsAreNotReached() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        var record = SessionReplayRecord()
        record.record(kind: "future_analysis", parameters: [:],
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "virtual_detector",
                      parameters: ["shape": "Circle", "center_x": "32", "center_y": "32",
                                   "inner": "0", "outer": "9"],
                      at: Date(timeIntervalSince1970: 1))
        state.replay.adopt(record, recordedOn: .detectorIdentity)

        await state.promoteAndReplayRecipe()

        XCTAssertEqual(state.replayRun.phase, .finished)
        XCTAssertNotNil(state.replayRun.haltReason)
        guard case .refused(let reason) = state.replayRun.steps[0].outcome else {
            return XCTFail("The unknown kind must be refused by name")
        }
        XCTAssertTrue(reason.contains("future_analysis"))
        XCTAssertEqual(state.replayRun.steps[1].outcome, .notReached,
                       "Nothing runs past a halt — never silently past a failure")
        // The recipe's virtual-detector step (outer 9) must NOT have run; the
        // re-establishing pass (which DOES run when step 1 is already known
        // to refuse — Gate A findings E1/B2) uses the session's default
        // aperture, so a result on screen is expected and correct.
        XCTAssertNotEqual(state.aperture.outer, 9,
                          "The recipe's step after the halt must not have applied its parameters")
        XCTAssertNotNil(state.resultImage,
                        "A promote whose replay was refused up front still re-establishes the current analysis")
        XCTAssertTrue(state.statusText.contains("Promote run halted"),
                      "statusText was: \(state.statusText)")
    }

    func testAStepThatRunsAndFailsHaltsTheRun() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        var record = SessionReplayRecord()
        // Parses cleanly; the negative spacing is an invalid configuration.
        // v2.5 step 5a: the replay executor asks the one readiness list before
        // running, so this is REFUSED with the checklist's own sentence — the
        // same reason the header button would be disabled — and the run halts.
        record.record(kind: "disk_detection",
                      parameters: ["corr_power": "1.0", "sigma_dp": "0.0",
                                   "sigma_cc": "2.0", "subpixel": "poly",
                                   "upsample_factor": "16",
                                   "min_absolute_intensity": "0.0",
                                   "min_relative_intensity": "0.005",
                                   "relative_to_peak": "0",
                                   "min_peak_spacing": "-5.0",
                                   "edge_boundary": "4", "max_peaks": "70",
                                   "kernel_source": "synthetic"],
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "virtual_detector",
                      parameters: ["shape": "Circle", "center_x": "32", "center_y": "32",
                                   "inner": "0", "outer": "9"],
                      at: Date(timeIntervalSince1970: 1))
        state.replay.adopt(record, recordedOn: .detectorIdentity)

        await state.promoteAndReplayRecipe()

        XCTAssertEqual(state.replayRun.phase, .finished)
        XCTAssertNotNil(state.replayRun.haltReason)
        guard case .refused(let reason) = state.replayRun.steps[0].outcome else {
            return XCTFail("An invalid configuration is refused by the shared readiness list, got \(String(describing: state.replayRun.steps[0].outcome))")
        }
        XCTAssertTrue(reason.contains("Fix the disk-detection settings"), reason)
        XCTAssertEqual(state.replayRun.steps[1].outcome, .notReached)
    }

    func testADPCReferenceTheSessionCannotHonourRefuses() async {
        // The demo fixture carries fitted origin maps, so the dishonourable
        // direction here is a recipe recorded against the GLOBAL CENTER: the
        // session would silently run against calibrated origins instead —
        // a parameter change no summary states. The mirror case (recipe wants
        // fitted origins, session has none) shares the same guard line.
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        XCTAssertTrue(state.calibrationSession.calibration.hasFittedOrigin,
                      "precondition: the fixture provides fitted origins")
        var record = SessionReplayRecord()
        record.record(kind: "dpc",
                      parameters: ["origin_reference": "global center"],
                      at: Date(timeIntervalSince1970: 0))
        state.replay.adopt(record, recordedOn: .detectorIdentity)

        await state.promoteAndReplayRecipe()

        guard case .refused(let reason) = state.replayRun.steps[0].outcome else {
            return XCTFail("Silently substituting the global center would be a parameter change no summary states")
        }
        XCTAssertTrue(reason.contains("origin"), "Reason was: \(reason)")
        XCTAssertFalse(state.statusText.contains("DPC ✓"),
                       "DPC must not have run — a refusal happens BEFORE the entry point")
    }

    // MARK: - The recipe survives its own replay

    func testReplayDoesNotMutateTheRecipeEvenThroughDiskDetectionsInvalidation() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        var record = SessionReplayRecord()
        // Disk detection's success re-recording carries
        // `invalidating: ["strain", "acom"]` — without replay suppression it
        // would DELETE the strain step out of the recipe mid-run.
        record.record(kind: "disk_detection",
                      parameters: ["corr_power": "1.0", "sigma_dp": "0.0",
                                   "sigma_cc": "2.0", "subpixel": "poly",
                                   "upsample_factor": "16",
                                   "min_absolute_intensity": "0.0",
                                   "min_relative_intensity": "0.005",
                                   "relative_to_peak": "0",
                                   "min_peak_spacing": "5.0",
                                   "edge_boundary": "4", "max_peaks": "70",
                                   "kernel_source": "synthetic"],
                      at: Date(timeIntervalSince1970: 0))
        record.record(kind: "strain",
                      parameters: ["reference_mode": "whole-scan",
                                   "basis_mode": "consensus"],
                      at: Date(timeIntervalSince1970: 1))
        state.replay.adopt(record, recordedOn: .detectorIdentity)

        await state.promoteAndReplayRecipe()

        XCTAssertEqual(state.replay.record, record,
                       "Replaying a recipe must not mutate the recipe — a halted replay would otherwise have destroyed it")
    }

    // MARK: - The frame gate

    func testARecipeRecordedOnABinnedDetectorReplaysWithReReferencedParameters() async {
        // The S6 refusal this test used to pin is lifted by S10: the plan
        // re-references the binned-frame aperture into source pixels — the
        // exact inverse of the load-time re-reference — and the run replays
        // with those values, saying so in the run's frame note.
        var binnedSpec = LoadSpecification()
        binnedSpec.detectorBin = 2
        let state = AppState()
        await state.openDemoFixture(specification: binnedSpec)
        XCTAssertFalse(state.loadedView.isFullExtent, "precondition: rehearsing binned")

        state.aperture = Aperture(centerX: 16, centerY: 16, inner: 0, outer: 6)
        await state.runVirtualDetector()
        XCTAssertEqual(state.replay.record.steps.count, 1, "precondition: recorded")
        XCTAssertEqual(state.replay.parameterFrame,
                       .detectorReduced(bin: 2, crop: nil),
                       "precondition: the live recording tracked its frame")

        await state.promoteAndReplayRecipe()

        XCTAssertTrue(state.loadedView.isFullExtent, "The reopen happens")
        guard case .succeeded = state.replayRun.steps[0].outcome else {
            return XCTFail("A binned rehearsal replays since S10; got \(state.replayRun.steps[0].outcome)")
        }
        XCTAssertNil(state.replayRun.haltReason)
        // The aperture the detector actually saw is the RE-REFERENCED one:
        // center 16 → (16+0.5)·2−0.5 = 32.5, radius 6 → 12 — view pixel
        // centres land on source block centres, mid-detector stays
        // mid-detector (the naive 16→32 would shift every position).
        XCTAssertEqual(state.aperture, Aperture(centerX: 32.5, centerY: 32.5,
                                                inner: 0, outer: 12),
                       "The replayed aperture is the rehearsal's, re-expressed in source pixels")
        XCTAssertNotNil(state.resultImage, "The replayed step published")
        XCTAssertNotNil(state.replayRun.frameNote,
                        "The morning summary must say the parameters were re-referenced")
        // The RECIPE keeps its rehearsal (view-frame) values — replay maps at
        // plan time, never by mutating the record (the S6 invariant holds).
        XCTAssertEqual(state.replay.record.steps[0].parameters["center_x"], "16.0",
                       "Mapping must never write back into the recipe")
        XCTAssertEqual(state.replay.record.steps[0].parameters["outer"], "6.0")
    }
}
