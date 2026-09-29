import SwiftUI
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

        // Bragg Disks does not, so it adopts its one task.
        state.selectWorkspace(.braggDisks)
        XCTAssertEqual(state.navigation.workspaceArea, .braggDisks)
        XCTAssertEqual(state.navigation.analysisMode, .disks,
                       "a task the destination does not own is replaced by its default")

        // Crystal Maps does not own disks either: its first task is strain.
        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.workspaceArea, .map)
        XCTAssertEqual(state.navigation.analysisMode, .strain)

        // ACOM is Crystal Maps' too: arriving again must not reset the user's task.
        state.navigation.analysisMode = .acom
        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.analysisMode, .acom,
                       "re-entering a workspace does not reset a task it owns")
    }

    /// Prepare and Results have no tasks at all (`analysisModes` is empty, so
    /// `defaultAnalysisMode` is nil). Navigating to them must leave the task
    /// alone rather than fall through to some other workspace's default.
    func testATasklessWorkspaceLeavesTheCurrentTaskUntouched() {
        let state = AppState()
        state.selectWorkspace(.braggDisks)
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

    /// `WindowAnatomyPolicy` is retired (2026-09-22): the window's own
    /// minimum width now HAS to cover the ideal columns plus both science
    /// panes at their floor, so nothing collapses a panel to make room
    /// anymore. Pins the derivation itself, and that it stays comfortably
    /// above the 640 pt the old, too-narrow constant used.
    func testDatasetWindowMinimumWidthCoversTheIdealColumnsAndBothSciencePanes() {
        let required = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, required)
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, 900)
    }

    /// The sidebar dragged to its maximum must still leave the inspector and
    /// both science panes their floor at the window's minimum. A saved sidebar
    /// wider than that crashed every launch in the constraint loop at 915 pt
    /// (Gate D 2026-09-28: restored window − sidebar ≤ 639 pt crashed, ≥ 640
    /// launched; the 320-pt maximum was inside the crash region).
    func testTheWidestSidebarStillFitsTheMinimumWindow() {
        let required = LayoutPolicy.sidebarWidth.max + LayoutPolicy.inspectorWidth.min
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertLessThanOrEqual(required, LayoutPolicy.datasetWindowMinimumSize.width)
    }
    // MARK: S6 Frozen Shell (2026-09-30)

    /// The window-width probe answers a finite proposal with itself, whatever
    /// the child needs. Red under the old shape (the split measured directly:
    /// 1190 in a 915-pt window) and under `max(proposal, child)`.
    func testWindowFillingLayoutReportsTheOfferedSizeNotTheRigidChild() {
        let rigid = CGSize(width: 1190, height: 700)
        let reported = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: 915, height: 600), child: rigid)
        XCTAssertEqual(reported.width, 915)
        XCTAssertEqual(reported.height, 600)
        // The sidebar's step-aside line reads that width: 915 < 1095.
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: reported.width, inspectorVisible: true))
    }

    /// An ideal or unbounded query still goes to the child, so the window's
    /// ideal and maximum sizes are unchanged. Red if the layout answered 0 or
    /// infinity for those.
    func testWindowFillingLayoutDefersIdealAndUnboundedQueriesToTheChild() {
        let child = CGSize(width: 1280, height: 800)
        let ideal = WindowFillingLayout.reportedSize(proposal: .unspecified, child: child)
        XCTAssertEqual(ideal, child)
        let unbounded = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: .infinity, height: 500), child: child)
        XCTAssertEqual(unbounded.width, 1280)
        XCTAssertEqual(unbounded.height, 500)
    }

    /// Info's "Unvalidated" note follows the product's own provenance key.
    /// Red if the key is ignored (always false) or the value not compared.
    func testInfoTabFlagsOnlyProductsThatSelfReportNoValidation() {
        XCTAssertTrue(ProductInfoSections.isUnvalidated(provenance: ["validation": "none"]))
        XCTAssertFalse(ProductInfoSections.isUnvalidated(provenance: ["validation": "py4DSTEM"]))
        XCTAssertFalse(ProductInfoSections.isUnvalidated(provenance: [:]))
        XCTAssertTrue(ProductInfoSections.unvalidatedNote.hasPrefix("Unvalidated"))
    }

    /// The renamed inspector-tab key carries a saved choice over exactly once
    /// and never overwrites a value already under the new key.
    func testInspectorTabKeyMigratesOnceAndNeverOverwrites() throws {
        let suite = "NavigationSeamTests.tab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("info", forKey: WorkspaceInspector.legacyTabKey)
        WorkspaceInspector.migrateLegacyTab(in: defaults)
        XCTAssertEqual(defaults.string(forKey: WorkspaceInspector.tabKey), "info")
        XCTAssertNil(defaults.object(forKey: WorkspaceInspector.legacyTabKey))

        defaults.set("settings", forKey: WorkspaceInspector.tabKey)
        defaults.set("info", forKey: WorkspaceInspector.legacyTabKey)
        WorkspaceInspector.migrateLegacyTab(in: defaults)
        XCTAssertEqual(defaults.string(forKey: WorkspaceInspector.tabKey), "settings",
                       "a value under the new key wins")
    }
}
