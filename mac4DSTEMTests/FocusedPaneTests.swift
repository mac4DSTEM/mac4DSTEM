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

    func testAWorkspaceSwitchThroughAppStateReachesTheInspectorDecision() {
        let state = AppState()
        state.selectWorkspace(.results)
        XCTAssertEqual(state.navigation.inspectorContent, .product)
        state.changeMode(.virtualDetector)   // moves to Imaging
        XCTAssertEqual(state.navigation.inspectorContent, .dataset)
    }
}
