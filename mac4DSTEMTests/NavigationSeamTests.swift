import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// S22c seam: navigation/selection state (workspace, task, pane visibility)
/// lives on `WorkspaceNavigation`, held by `AppState` as `navigation` — the
/// same no-forwarding contract `StrainProductTests` pins for `strain`, with
/// the same known limit: `Mirror` sees stored properties only, so a computed
/// forwarder is caught by review, not here.
@MainActor
final class NavigationSeamTests: XCTestCase {

    func testAppStateHoldsTheNavigationSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("navigation"), "the facade holds the seam")
        let forbidden = ["workspaceArea", "analysisMode", "showToolsPane",
                         "showLogPane", "showInspectorPane", "showsOutputPane",
                         "showsLineagePane", "processFraction", "lastProcessFraction"]
        let shadows = forbidden.filter(names.contains)
        XCTAssertTrue(
            shadows.isEmpty,
            "navigation state may not shadow the seam on AppState: \(shadows)"
        )
    }

    /// The recovery hook keeps the exact semantics of the stored property's
    /// old didSet: fire on actual task changes, and only on those — a
    /// same-value write persisting recovery on every render would be the
    /// regression this pins against.
    func testModeChangeFiresTheRecoveryHookExactlyOnActualChanges() {
        let nav = WorkspaceNavigation()
        var fires = 0
        nav.onModeChange = { fires += 1 }
        nav.analysisMode = .virtualDetector
        XCTAssertEqual(fires, 0, "a same-value write must not fire the hook")
        nav.analysisMode = .dpc
        XCTAssertEqual(fires, 1, "an actual change fires the hook once")
        nav.analysisMode = .dpc
        XCTAssertEqual(fires, 1, "writing the current value again stays quiet")
    }

    /// `selectWorkspace` is the orchestration the seam deliberately does NOT
    /// own, and until now its only test lived in `FocusedPaneTests`, which
    /// went with the retired pane-focus model (2026-09-04). It has eight
    /// production call sites; this is the replacement, not an addition.
    ///
    /// The contract: moving to a workspace never starts scientific work, and
    /// it only re-points the task when the current one does not belong to the
    /// destination.
    func testSelectingAWorkspaceAdoptsItsDefaultTaskOnlyWhenTheCurrentOneDoesNotBelong() {
        let state = AppState()
        XCTAssertEqual(state.navigation.analysisMode, .virtualDetector)

        // Imaging owns the virtual detector, so the task must survive.
        state.selectWorkspace(.image)
        XCTAssertEqual(state.navigation.workspaceArea, .image)
        XCTAssertEqual(state.navigation.analysisMode, .virtualDetector,
                       "a task the destination owns is kept")

        // Map does not, so it adopts Map's first task — disks, which produce
        // the vectors the other two consume.
        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.workspaceArea, .map)
        XCTAssertEqual(state.navigation.analysisMode, .disks,
                       "a task the destination does not own is replaced by its default")

        // Strain is Map's too: arriving again must not reset the user's task.
        state.navigation.analysisMode = .strain
        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.analysisMode, .strain,
                       "re-entering a workspace does not reset a task it owns")
    }

    /// Prepare and Results have no tasks at all (`analysisModes` is empty, so
    /// `defaultAnalysisMode` is nil). Navigating to them must leave the task
    /// alone rather than fall through to some other workspace's default.
    func testATasklessWorkspaceLeavesTheCurrentTaskUntouched() {
        let state = AppState()
        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.analysisMode, .disks)

        for area in [WorkspaceArea.results, .prepare] {
            state.selectWorkspace(area)
            XCTAssertEqual(state.navigation.workspaceArea, area)
            XCTAssertEqual(state.navigation.analysisMode, .disks,
                           "\(area) owns no task and must not re-point one")
        }
    }

    func testInfobarDragReachesBothExtremesWithoutMovingTheFixedBarHeight() {
        let available: CGFloat = 600
        let hidden = ProcessAreaLayout.heights(fraction: 0, available: available)
        XCTAssertEqual(hidden.canvas, available)
        XCTAssertEqual(hidden.process, 0)

        let full = ProcessAreaLayout.heights(fraction: 1, available: available)
        XCTAssertEqual(full.canvas, 0)
        XCTAssertEqual(full.process, available)

        let draggedUp = ProcessAreaLayout.fraction(afterDrag: -300, available: available, from: 0.25)
        XCTAssertEqual(draggedUp, 0.75, accuracy: 0.001)
        let draggedDown = ProcessAreaLayout.fraction(afterDrag: 300, available: available, from: 0.25)
        XCTAssertEqual(draggedDown, 0, accuracy: 0.001)
    }

    func testProcessAreaToggleRestoresTheLastDraggedFraction() {
        let navigation = WorkspaceNavigation()
        navigation.processFraction = 0.6
        navigation.showLogPane = false
        XCTAssertEqual(navigation.processFraction, 0)
        XCTAssertEqual(navigation.lastProcessFraction, 0.6)
        navigation.showLogPane = true
        XCTAssertEqual(navigation.processFraction, 0.6)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0.6, last: 0.6), 0)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0, last: 0.6), 0.6)
    }

    /// The side panels collapse exactly where two science panes at
    /// `imagePaneMinimum` stop fitting beside columns at their IDEAL widths —
    /// the widths the app sets. Rewritten 2026-09-22 from the maxima it
    /// pinned before: that budget (1143 pt) is the one that hid the inspector
    /// on an 1100-pt window and greyed its toggle (ADR 035).
    func testSidePanelsCollapseBeforeEitherSciencePaneFallsBelowItsMinimum() {
        let columns = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance * 2
        let threshold = columns + WindowAnatomyPolicy.scienceMinimum
        let paneAtThreshold = (threshold - columns - LayoutPolicy.sciencePaneDividerWidth) / 2
        XCTAssertEqual(paneAtThreshold, LayoutPolicy.imagePaneMinimum,
                       "at the threshold both panes sit exactly on the floor")
        XCTAssertFalse(WindowAnatomyPolicy.collapseInspector(at: threshold, navigatorVisible: true))
        XCTAssertTrue(WindowAnatomyPolicy.collapseInspector(at: threshold - 1, navigatorVisible: true))
        XCTAssertFalse(WindowAnatomyPolicy.collapseInspector(at: 1100, navigatorVisible: true),
                       "an 1100-pt window on a 13-inch display keeps its inspector")
        XCTAssertFalse(WindowAnatomyPolicy.collapseNavigator(at: LayoutPolicy.datasetWindowMinimumSize.width),
                       "the navigator never collapses at the window's own minimum width")
    }

    /// 2026-09-22, the first on-screen look at phase 1: an 1100-pt window
    /// closed the inspector and greyed its toggle, and widening to 1280 left
    /// it closed, because the collapse had overwritten the user's intent.
    /// Intent and fit are two questions now.
    func testANarrowWindowHidesTheInspectorWithoutForgettingTheIntentAndWideningRestoresIt() {
        let navigation = WorkspaceNavigation()
        navigation.showToolsPane = true
        navigation.showInspectorPane = true
        XCTAssertTrue(navigation.inspectorIsVisible, "an unmeasured (infinite) width collapses nothing")

        navigation.availableWindowWidth = 900
        XCTAssertFalse(navigation.inspectorFits)
        XCTAssertFalse(navigation.inspectorIsVisible)
        XCTAssertTrue(navigation.showInspectorPane, "the intent survives the collapse")
        XCTAssertTrue(navigation.navigatorIsVisible, "the navigator collapses last")

        navigation.availableWindowWidth = 1280
        XCTAssertTrue(navigation.inspectorIsVisible, "widening brings the inspector back by itself")
    }

    /// The budget is the IDEAL column widths, the ones the app sets: the
    /// maxima demanded 1143 pt and lost the inspector on a 13-inch display.
    func testTheWidthBudgetSumsTheIdealColumnWidthsNotTheMaxima() {
        let both = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + WindowAnatomyPolicy.scienceMinimum + LayoutPolicy.splitColumnDividerAllowance * 2
        XCTAssertEqual(both, 915)
        XCTAssertTrue(WindowAnatomyPolicy.collapseInspector(at: both - 1, navigatorVisible: true))
        XCTAssertFalse(WindowAnatomyPolicy.collapseInspector(at: both, navigatorVisible: true))

        let alone = LayoutPolicy.inspectorWidth.ideal + WindowAnatomyPolicy.scienceMinimum
            + LayoutPolicy.splitColumnDividerAllowance
        XCTAssertTrue(WindowAnatomyPolicy.collapseInspector(at: alone - 1, navigatorVisible: false))
        XCTAssertFalse(WindowAnatomyPolicy.collapseInspector(at: alone, navigatorVisible: false))

        XCTAssertFalse(WindowAnatomyPolicy.collapseNavigator(at: LayoutPolicy.datasetWindowMinimumSize.width),
                       "the navigator never collapses at or above the window's own minimum width")
    }

    /// The inspector's budget counts the navigator only while the navigator
    /// is on screen: hiding the navigator is what makes room.
    func testTheInspectorBudgetCountsOnlyANavigatorThatIsOnScreen() {
        let navigation = WorkspaceNavigation()
        navigation.showInspectorPane = true
        navigation.availableWindowWidth = 700
        navigation.showToolsPane = true
        XCTAssertFalse(navigation.inspectorIsVisible)
        navigation.showToolsPane = false
        XCTAssertTrue(navigation.inspectorIsVisible,
                      "700 pt fits an inspector beside two panes once the navigator is hidden")
    }
}
