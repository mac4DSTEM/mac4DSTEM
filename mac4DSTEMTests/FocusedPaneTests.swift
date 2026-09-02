import XCTest
@testable import mac4DSTEM

/// v2.5 step 7c slice 1 (plan §11g decision 3): the focus ring is a value the
/// inspector reads, owned by the navigation seam, never by `AppState`.
/// Decisions are asserted, not renderings (open-items, working method 6).
@MainActor
final class FocusedPaneTests: XCTestCase {

    func testResultsFocusesItsProductPaneOnArrivalAndLeavingReleasesIt() {
        let nav = WorkspaceNavigation()
        XCTAssertNil(nav.focusedPane)
        XCTAssertEqual(nav.inspectorContent, .dataset)

        nav.workspaceArea = .results
        XCTAssertEqual(nav.focusedPane, .result, "Results has one pane; it is focused on arrival")
        XCTAssertEqual(nav.inspectorContent, .product)

        nav.workspaceArea = .prepare
        XCTAssertNil(nav.focusedPane,
                     "a workspace change releases the ring until one of the new panes claims it")
        XCTAssertEqual(nav.inspectorContent, .dataset,
                       "with no claim the column falls back to the dataset inspector (7b conditions)")
    }

    // MARK: - slice 2: Prepare's panes claim their own descriptor

    func testImagingPanesClaimLikePrepare() {   // slice 3
        XCTAssertEqual(
            FocusedPane.livePane(.diffraction, in: .image, task: .virtualDetector),
            .detectorPattern, "the virtual detector is drawn on Imaging's diffraction pane"
        )
        XCTAssertEqual(FocusedPane.livePane(.realSpace, in: .image, task: .virtualDetector), .image)
    }

    func testPreparePanesClaimTheDescriptorOfWhatTheyDraw() {
        XCTAssertEqual(
            FocusedPane.livePane(.diffraction, in: .prepare, task: .virtualDetector),
            .detectorPattern, "Prepare's diffraction pane carries the virtual detector"
        )
        XCTAssertEqual(
            FocusedPane.livePane(.realSpace, in: .prepare, task: .virtualDetector),
            .image
        )
    }

    func testTheDescriptorAloneDecidesTheLiveGroup() {
        XCTAssertTrue(FocusedPane.detectorPattern.showsAperture)
        XCTAssertTrue(FocusedPane.detectorPattern.showsDiffractionHistogram)
        XCTAssertFalse(FocusedPane.detectorPattern.showsRealSpaceHistogram)
        XCTAssertFalse(FocusedPane.image.showsAperture)
        XCTAssertFalse(FocusedPane.image.showsDiffractionHistogram)
        XCTAssertTrue(FocusedPane.image.showsRealSpaceHistogram)
        XCTAssertFalse(FocusedPane.result.showsAperture)
        XCTAssertFalse(FocusedPane.result.showsDiffractionHistogram)
    }

    /// The adapter's expiry, pinned: a workspace whose panes do not claim
    /// yet leaves the claim open so the 7b per-task conditions stand in.
    /// Each of slices 4–5 turns one of these into a real descriptor.
    func testWorkspacesBeforeTheirSliceLeaveTheClaimOpen() {
        XCTAssertNil(FocusedPane.livePane(.diffraction, in: .map, task: .disks))
        XCTAssertNil(FocusedPane.livePane(.realSpace, in: .reconstruct, task: .dpc))
    }

    func testAWorkspaceSwitchThroughAppStateReachesTheInspectorDecision() {
        let state = AppState()
        state.selectWorkspace(.results)
        XCTAssertEqual(state.navigation.inspectorContent, .product)
        state.changeMode(.virtualDetector)   // moves to Imaging
        XCTAssertEqual(state.navigation.inspectorContent, .dataset)
    }
}
