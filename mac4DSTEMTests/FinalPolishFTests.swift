//
//  FinalPolishFTests.swift
//  Lane F (Slot 4⅞ polish, 2026-10-04): the frozen shell, by the owner's answers.
//  P6b (card Q6 a) — an open bottom area is never drawn under 140 pt, on drag and on every restore; a drag
//        below 70 pt closes it (live: on every drag sample, reversible until release).
//  P6c + P6d-2 (card Q7 a) — Imaging › Virtual detector has no toolbar verb and ⌘R disables with it; Group
//        Patterns keeps both; the detector presets still publish a product.
//  P6d-1 — the Promote caption says nothing about keeping the Mac awake (that is off by default).
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishFTests: XCTestCase {

    // MARK: - P6b: the floor

    /// A sliver the owner reached by dragging (or that a scene stored) draws at the floor, 140 pt.
    /// 836 pt is the usable column at 1470 × 923 (map.json P6b). Above the floor nothing changes.
    /// Mutation: drop `max(share, LayoutPolicy.processAreaMinimumHeight)` in `ProcessAreaLayout.height` -> process 41.8.
    func testAnOpenAreaIsNeverDrawnUnderTheFloor() {
        let usable: CGFloat = 836
        let sliver = ProcessAreaLayout.heights(fraction: 0.05, available: usable)
        XCTAssertEqual(sliver.process, 140, "0.05 × 836 = 41.8 pt would be a header-only sliver")
        XCTAssertEqual(sliver.canvas, usable - 140)
        let tiny = ProcessAreaLayout.heights(fraction: 0.0001, available: usable)
        XCTAssertEqual(tiny.process, 140)

        let ideal = ProcessAreaLayout.heights(fraction: LayoutPolicy.processAreaIdealFraction, available: usable)
        XCTAssertEqual(ideal.process, usable * CGFloat(LayoutPolicy.processAreaIdealFraction), accuracy: 0.001,
                       "above the floor the fraction is exact")
    }

    /// The owner's two extremes survive: 0 hides the area, 1 hides the canvas; a column shorter than the floor
    /// gives the area all of it (as fraction 1 does) and never a negative canvas; a fraction outside 0…1 (no
    /// clamp inside `height` any more) is read by the guard and the cap: below 0 hides, above 1 is the column.
    /// Mutation: drop the `min(…, usable)` cap in `ProcessAreaLayout.height` -> process 140 > the 100-pt column
    /// (and 900 > the 600-pt column at fraction 1.5); `guard share > 0` -> `guard fraction != 0` -> fraction -0.5 draws 140.
    func testTheExtremesAndAShortColumnStayInsideTheColumn() {
        let hidden = ProcessAreaLayout.heights(fraction: 0, available: 600)
        XCTAssertEqual(hidden.process, 0)
        XCTAssertEqual(hidden.canvas, 600)
        let full = ProcessAreaLayout.heights(fraction: 1, available: 600)
        XCTAssertEqual(full.process, 600)
        XCTAssertEqual(full.canvas, 0)
        let over = ProcessAreaLayout.heights(fraction: 1.5, available: 600)
        XCTAssertEqual(over.process, 600, "a fraction over 1 is the whole column")
        XCTAssertEqual(over.canvas, 0)
        let under = ProcessAreaLayout.heights(fraction: -0.5, available: 600)
        XCTAssertEqual(under.process, 0, "a negative fraction hides the area")
        XCTAssertEqual(under.canvas, 600)

        let short = ProcessAreaLayout.heights(fraction: 0.5, available: 100)
        XCTAssertEqual(short.process, 100, "the floor never exceeds the column")
        XCTAssertEqual(short.canvas, 0)
        let none = ProcessAreaLayout.heights(fraction: 0.5, available: 0)
        XCTAssertEqual(none.process, 0)
        XCTAssertEqual(none.canvas, 0)
    }

    /// Both restore paths: the toggle / ⌃⌘L restore of `lastProcessFraction`, and the scene's saved
    /// `processFraction` (an older version stored slivers). Each is drawn at the floor on every window height,
    /// and the floor also holds when the window shrinks under a fraction that was fine before.
    /// Mutation: drop the floor in `ProcessAreaLayout.height` (the same one line as the first test).
    func testARestoredSliverIsNeverDrawnAsOne() {
        let navigation = WorkspaceNavigation()
        navigation.lastProcessFraction = 0.01
        navigation.showLogPane = true   // the toggle's and ⌃⌘L's restore
        XCTAssertTrue(navigation.showLogPane, "the area opens")
        for usable in [CGFloat(554), 836, 1100] {
            XCTAssertGreaterThanOrEqual(
                ProcessAreaLayout.heights(fraction: navigation.processFraction, available: usable).process, 140,
                "restored last fraction at \(usable) pt")
        }

        // The infobar's own button restores the same way.
        let viaToggle = ProcessAreaLayout.toggled(from: 0, last: 0.01)
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: viaToggle, available: 836).process, 140)

        // The scene's saved processFraction.
        let saved = WorkspaceNavigation()
        saved.processFraction = 0.05
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: saved.processFraction, available: 836).process, 140)

        // A window that shrinks: 0.2 is 167 pt at 836 but 111 pt at 554 — drawn at the floor.
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: 0.2, available: 836).process, 167.2, accuracy: 0.001)
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: 0.2, available: 554).process, 140)
    }

    // MARK: - P6b: the drag

    /// A drag below 70 pt closes the area (the bottom edge still hides it); 70 pt and up holds.
    /// 800 pt column, start 0.25 = 200 pt exactly, so 130 pt of downward travel is exactly 70 pt.
    /// Mutation: delete the `proposed < processAreaSnapShutHeight` line in `fraction(afterDrag:)` -> 69 pt holds at the floor.
    func testADragBelowSeventyPointsClosesTheArea() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 131, available: usable, from: 0.25), 0,
                       "69 pt closes")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 130, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "exactly 70 pt holds at the floor")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 600, available: usable, from: 0.25), 0,
                       "dragged to the bottom edge, as before")

        // From closed, an upward drag opens the area only once it has travelled 70 pt, and then at the floor.
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -69, available: usable, from: 0), 0)
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -71, available: usable, from: 0), floorFraction,
                       accuracy: 1e-9)
    }

    /// Between the snap and the floor the area holds at the floor; above it follows the pointer; the top edge hides the canvas.
    /// Mutation: drop `max(proposed, LayoutPolicy.processAreaMinimumHeight)` in `fraction(afterDrag:)` -> 100/800 = 0.125.
    func testADragBetweenTheSnapAndTheFloorHoldsAtTheFloor() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 100, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "100 pt proposed holds at 140")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 60, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "exactly 140 pt")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -100, available: usable, from: 0.25), 0.375,
                       accuracy: 1e-9, "above the floor it follows the pointer: 300 pt")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -2000, available: usable, from: 0.25), 1,
                       "the top edge hides the canvas")
    }

    /// Grabbing a stored sliver starts from what is on screen (the floor), not from the sliver's own height:
    /// no jump on the first pixel, and a 50-pt drag down from the 140-pt area holds instead of closing.
    /// Mutation: start `fraction(afterDrag:)` from `start * available` (the raw stored height) -> 0.05 × 800 = 40 pt closes.
    func testGrabbingAStoredSliverStartsFromTheFloor() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 0.5, available: usable, from: 0.05), floorFraction,
                       accuracy: 1e-9, "the first pixel of travel does not move the bar")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 50, available: usable, from: 0.05), floorFraction,
                       accuracy: 1e-9, "140 − 50 = 90 pt holds at the floor")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 80, available: usable, from: 0.05), 0,
                       "140 − 80 = 60 pt closes")
    }

    /// The snap is LIVE, as the gesture feeds it: `StatusBar` calls `fraction(afterDrag:)` on EVERY drag sample,
    /// from the fraction the drag started at, so the area shuts the moment a sample proposes under 70 pt and comes
    /// back at the floor if the pointer returns before release. `lastProcessFraction` keeps the last OPEN value the
    /// drag passed through, so the toggle and ⌃⌘L reopen at the floor (140 pt), not at the 200 pt the drag started
    /// from. Not a defect: card Q6 a's floor, and what the final drive will see.
    /// Mutation: delete the `proposed < processAreaSnapShutHeight` line in `fraction(afterDrag:)` -> a 60-pt
    /// proposal holds at the floor and the area never closes; or raise the floor to 440 -> the start is drawn at 440.
    func testTheSnapIsLiveAndAfterAClosingDragTheToggleReopensAtTheFloor() {
        let usable: CGFloat = 800
        let navigation = WorkspaceNavigation()
        navigation.processFraction = 0.25   // 200 pt: where the drag starts
        let start = navigation.processFraction
        func sample(_ translation: CGFloat) {   // one drag sample, as StatusBar feeds it
            navigation.processFraction = ProcessAreaLayout.fraction(afterDrag: translation, available: usable, from: start)
        }
        func drawn() -> CGFloat {
            ProcessAreaLayout.heights(fraction: navigation.processFraction, available: usable).process
        }
        for translation in stride(from: CGFloat(0), through: 130, by: 10) {   // down to exactly 70 pt
            sample(translation)
            XCTAssertTrue(navigation.showLogPane, "\(translation) pt of travel leaves the area open")
        }
        sample(140)   // 60 pt proposed, the pointer still held
        XCTAssertFalse(navigation.showLogPane, "closes the moment a sample proposes under 70 pt, before release")
        sample(100)   // the pointer comes back up before release: 100 pt proposed
        XCTAssertTrue(navigation.showLogPane, "reversible until release")
        XCTAssertEqual(drawn(), 140, "reopened by the drag at the floor")
        sample(140)   // closes again, and the gesture ends here
        XCTAssertFalse(navigation.showLogPane)
        navigation.showLogPane = true   // the toggle's and ⌃⌘L's restore
        XCTAssertEqual(drawn(), 140, "reopens at the floor, the last open value the drag passed through — not at 200 pt")
    }

    /// The owner's numbers, and that the floor leaves the science panes (header + 180 pt) their minimum at the
    /// window's own minimum height, so a column cannot be too short for it in the app: 640 − 34 − 140 = 466 pt
    /// of canvas, with 52 pt for the title bar and toolbar and 100 pt of margin still to spare.
    /// Mutation: raise `processAreaMinimumHeight` to 440 -> the canvas beside it falls under a pane's minimum.
    func testTheFloorIsTheOwnersNumbersAndFitsBesideTheCanvasAtTheWindowMinimum() {
        XCTAssertEqual(LayoutPolicy.processAreaMinimumHeight, 140)
        XCTAssertEqual(LayoutPolicy.processAreaSnapShutHeight, 70)
        let canvas = LayoutPolicy.datasetWindowMinimumSize.height - LayoutPolicy.statusStripHeight
            - LayoutPolicy.processAreaMinimumHeight
        XCTAssertGreaterThanOrEqual(canvas, LayoutPolicy.imagePaneMinimum + LayoutPolicy.paneHeaderHeight + 52 + 100)
    }

    // MARK: - P6c + P6d-2: the imaging verb

    /// The toolbar's title: Group Patterns only. Mutation: restore `: "Compute Image"` for the other modes -> red.
    func testOnlyGroupPatternsKeepsAnImagingVerb() {
        XCTAssertNil(PrimaryActionButton.imagingActionTitle(for: .virtualDetector))
        XCTAssertEqual(PrimaryActionButton.imagingActionTitle(for: .diffractionGroups), "Group Patterns")
    }

    /// ⌘R and ⌘↩ disable in step with the toolbar: for EVERY mode, the imaging room has a primary task exactly
    /// when the toolbar shows a title. Mutation: restore `case .image, .braggDisks: return true` in
    /// `AppState.hasPrimaryWorkspaceTask` -> red at the virtual detector.
    func testTheMenuPredicateMirrorsTheToolbarTitleForEveryImagingMode() {
        let state = AppState()
        state.navigation.workspaceArea = .image
        for mode in AnalysisMode.allCases {
            state.navigation.analysisMode = mode
            XCTAssertEqual(state.hasPrimaryWorkspaceTask,
                           PrimaryActionButton.imagingActionTitle(for: mode) != nil, "\(mode)")
        }
        state.navigation.analysisMode = .virtualDetector
        XCTAssertFalse(state.hasPrimaryWorkspaceTask)
        state.navigation.analysisMode = .diffractionGroups
        XCTAssertTrue(state.hasPrimaryWorkspaceTask)
    }

    /// With a dataset open: ⌘R is disabled in the virtual detector and enabled for Group Patterns (the
    /// cube is all it needs); the other rooms' verbs are untouched. Mutation: as above.
    func testRunCurrentTaskIsDisabledInTheVirtualDetectorAndEnabledForGroups() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .virtualDetector
        XCTAssertFalse(state.canRunPrimaryWorkspaceTask, "the image is live; ⌘R has nothing to add")
        state.navigation.analysisMode = .diffractionGroups
        XCTAssertTrue(state.canRunPrimaryWorkspaceTask)
        state.navigation.workspaceArea = .braggDisks
        state.navigation.analysisMode = .disks
        XCTAssertTrue(state.canRunPrimaryWorkspaceTask, "Detect All Disks keeps its verb")
    }

    /// The programmatic run honours the same answer: nothing runs in the virtual detector (no second pass,
    /// so the scan image is not republished). Mutation: restore the `else { await runCurrentAnalysis() }`
    /// in `runPrimaryWorkspaceTask`'s `.image` branch -> `scanNavigationVersion` moves.
    func testRunningThePrimaryTaskInTheVirtualDetectorRunsNothing() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .virtualDetector
        let version = state.scanNavigationVersion
        let status = state.statusText
        await state.runPrimaryWorkspaceTask()
        XCTAssertEqual(state.scanNavigationVersion, version, "no second virtual-detector pass")
        XCTAssertEqual(state.statusText, status)
    }

    /// Without a button the image is still produced: a detector preset runs the detector itself. Mutation:
    /// delete `Task { await runVirtualDetector() }` in `applyDetectorPreset` -> the version never moves.
    func testADetectorPresetStillPublishesAnImageWithNoButton() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.workspaceArea = .image
        state.navigation.analysisMode = .virtualDetector
        let before = state.scanNavigationVersion
        state.applyDetectorPreset(.adf)
        let deadline = Date().addingTimeInterval(20)
        while state.scanNavigationVersion == before, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(state.scanNavigationVersion, before, "the preset's own run published the image")
        XCTAssertEqual(state.resultPresentation.virtualShape, .annulus)
    }

    // MARK: - P6d-1: the Promote caption

    /// The caption makes no promise about the Mac staying awake (keep-awake is off by default).
    /// Mutation: restore ", keeping this Mac awake while it runs (lid open)" in `replaySentence` -> red.
    func testThePromoteCaptionDoesNotPromiseToKeepTheMacAwake() {
        let one = PromoteRunCaption.replaySentence(count: 1, titles: "Virtual detector")
        let many = PromoteRunCaption.replaySentence(count: 3, titles: "Virtual detector, Detect disks, Strain")
        for text in [one, many] {
            XCTAssertFalse(text.lowercased().contains("awake"), text)
            XCTAssertFalse(text.contains("lid"), text)
            XCTAssertTrue(text.hasSuffix("A step that fails halts the run."), text)
        }
        XCTAssertEqual(one, "Then replays this session's 1 recorded analysis in order (Virtual detector). "
                       + "A step that fails halts the run.")
        XCTAssertTrue(many.contains("3 recorded analyses in order (Virtual detector, Detect disks, Strain)"), many)
    }
}
