//
//  SpectroscopyDriveL6Tests.swift
//  Lane L6 (the owner's drive findings, 2026-10-07): "Compute Image should be back!" — Imaging › Virtual detector has its
//  toolbar verb again ("Compute Image"), ⌘R / ⌘↩ follow it, and the verb runs the full-detector pass and records its recipe
//  step. Group Patterns keeps its own verb. The shell's flat/glass state (panes flat, buttons glass) is a material and is
//  blind to a hosted-layout test: it is held by review and the drive. Each test names its mutation.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SpectroscopyDriveL6Tests: XCTestCase {

    /// Mutation: return nil for `.virtualDetector` -> red. Mutation: return "Compute Image" for both modes -> the second line goes red.
    func testTheImagingVerbIsComputeImageAndGroupPatterns() {
        XCTAssertEqual(PrimaryActionButton.imagingActionTitle(for: .virtualDetector), "Compute Image")
        XCTAssertEqual(PrimaryActionButton.imagingActionTitle(for: .diffractionGroups), "Group Patterns")
    }

    /// Every imaging mode has a verb, and only the imaging room's answer moved: Results still has none, Prepare keeps its own.
    /// Mutation: `return false` in the `.image` arm of `AppState.hasPrimaryWorkspaceTask` -> red.
    func testEveryImagingModeHasAPrimaryTaskAndResultsStillHasNone() {
        let state = AppState()
        state.navigation.workspaceArea = .image
        for mode in AnalysisMode.allCases where WorkspaceArea.image.analysisModes.contains(mode) {
            state.navigation.analysisMode = mode
            XCTAssertTrue(state.hasPrimaryWorkspaceTask, "\(mode)")
        }
        XCTAssertTrue(WorkspaceArea.image.analysisModes.contains(.virtualDetector), "premise: the room holds the detector")
        state.navigation.workspaceArea = .results
        XCTAssertFalse(state.hasPrimaryWorkspaceTask)
    }

    /// The verb computes the image AND records the recipe step, as before 2026-10-04.
    /// Mutation: delete the `runVirtualDetector()` call in `runPrimaryWorkspaceTask`'s `.image` branch -> no step, red.
    func testComputeImageRecordsTheVirtualDetectorStep() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .virtualDetector
        let before = state.replay.record.steps.filter { $0.kind == "virtual_detector" }.count
        let version = state.scanNavigationVersion
        await state.runPrimaryWorkspaceTask()
        XCTAssertGreaterThan(state.scanNavigationVersion, version)
        XCTAssertTrue(state.replay.record.steps.contains { $0.kind == "virtual_detector" })
        XCTAssertGreaterThanOrEqual(state.replay.record.steps.filter { $0.kind == "virtual_detector" }.count, before)
    }

    /// Group Patterns still runs groups, not the detector: the groups verb does not publish a virtual-detector step.
    /// Mutation: route `.diffractionGroups` to `runVirtualDetector()` as well -> a virtual_detector step appears, red.
    func testGroupPatternsDoesNotRunTheDetector() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .diffractionGroups
        let steps = state.replay.record.steps.filter { $0.kind == "virtual_detector" }.count
        await state.runPrimaryWorkspaceTask()
        XCTAssertEqual(state.replay.record.steps.filter { $0.kind == "virtual_detector" }.count, steps)
    }
}
