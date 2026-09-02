import AppKit
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// The split-view contract (owner direction 2026-09-03: "like Xcode"): both
/// side columns behave the same — drag far, collapse when dragged past the
/// minimum, reopen at the width they had — and the data pane keeps a floor.
/// One policy owns it (`SplitViewPolicy`); these are hosted-window tests,
/// the only kind that can see AppKit's split items.
///
/// Written before the policy as pre-registered experiments. Predictions and
/// outcomes (2026-09-03): E1, the inspector is a third item beside the
/// sidebar — refuted, it is a second split controller nested in the detail;
/// E2, a drag-collapse does NOT reach the navigation flags on its own —
/// refuted, SwiftUI's bindings carry it (a sync written for it changed
/// nothing under mutation and was deleted); E3, a toggled column reopens at
/// its last width — confirmed. The tests stay as pins of the properties.
@MainActor
final class SplitViewPolicyTests: XCTestCase {

    private func pump(_ seconds: TimeInterval = 0.45) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeWindow(_ appState: AppState, inspector: Bool) async -> NSWindow {
        await appState.openDemoFixture()
        appState.navigation.showInspectorPane = inspector
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1470, height: 923),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: ContentView().environment(appState))
        window.makeKeyAndOrderFront(nil)
        pump(1.2)
        return window
    }

    /// Pin the shared autosave before moving a divider: `NavigationSplitView`
    /// persists divider positions into the app's defaults domain, and a test
    /// that parks the sidebar at 144pt otherwise hands that width to every
    /// later window (the S17 trap, hit again 2026-09-03).
    private func unpinAutosave(_ split: NSSplitView) { split.autosaveName = "" }

    // E1 refuted, contract kept: the inspector is a second split controller
    // nested in the detail, not a third item beside the sidebar. Both side
    // items still get the same bounds and can collapse; the data pane's
    // floor is a split item's; the holding order is inspector, sidebar, pane.
    func testBothSideColumnsGetTheSameContractAndTheDetailKeepsItsFloor() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }

        let report = try XCTUnwrap(SplitViewPolicy.apply(to: window))
        XCTAssertEqual(report.sidebar.minimumThickness, SplitViewPolicy.sidebar.minimum)
        XCTAssertEqual(report.sidebar.maximumThickness, SplitViewPolicy.sidebar.maximum)
        XCTAssertTrue(report.sidebar.canCollapse, "dragging past the minimum collapses the sidebar")

        let inspector = try XCTUnwrap(report.inspector, "the inspector's split item while it is shown")
        XCTAssertEqual(inspector.minimumThickness, SplitViewPolicy.inspector.minimum)
        XCTAssertEqual(inspector.maximumThickness, SplitViewPolicy.inspector.maximum)
        XCTAssertTrue(inspector.canCollapse, "the inspector collapses the same way")

        let detail = try XCTUnwrap(report.detail)
        XCTAssertEqual(detail.minimumThickness, SplitViewPolicy.detailMinimum,
                       "the data pane's floor is the split item's, not a view frame")
        XCTAssertGreaterThan(detail.holdingPriority.rawValue, inspector.holdingPriority.rawValue,
                             "a narrowing window squeezes the inspector before the data pane")
        XCTAssertGreaterThan(report.sidebar.holdingPriority.rawValue, report.outerDetail.holdingPriority.rawValue,
                             "and the trailing pair gives way before the sidebar")
    }

    // E2: a collapse done by the split view (a drag past the minimum) reaches
    // the navigation flags, so the toggle buttons and menu never lie. SwiftUI
    // provides this; the pin guards the day it stops.
    func testACollapseBySplitViewReachesTheNavigationFlags() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let report = try XCTUnwrap(SplitViewPolicy.apply(to: window))

        try XCTUnwrap(report.sidebar).isCollapsed = true
        pump(0.4)
        XCTAssertFalse(appState.navigation.showToolsPane, "sidebar collapsed by the split view")

        try XCTUnwrap(report.inspector).isCollapsed = true
        pump(0.4)
        XCTAssertFalse(appState.navigation.showInspectorPane, "inspector collapsed by the split view")
    }

    // E3: the toggle reopens a column at the width it had.
    func testAColumnReopensAtTheWidthItHad() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: false)
        defer { window.orderOut(nil) }
        _ = SplitViewPolicy.apply(to: window)
        let split = try XCTUnwrap(SplitViewPolicy.outermostColumnSplit(in: window.contentView))
        unpinAutosave(split)

        split.setPosition(320, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        pump(0.3)
        let before = try XCTUnwrap(split.arrangedSubviews.first).frame.width
        XCTAssertEqual(before, 320, accuracy: 2, "fixture precondition")

        appState.navigation.showToolsPane = false
        pump(0.6)
        appState.navigation.showToolsPane = true
        pump(0.8)
        let after = try XCTUnwrap(split.arrangedSubviews.first).frame.width
        XCTAssertEqual(after, before, accuracy: 2, "the sidebar came back at \(after)pt, not the \(before)pt it had")
    }

    // The restoration clamp, now for both sides: a persisted width below the
    // minimum is corrected rather than shown (the 144pt sidebar of 2026-08-06).
    func testARestoredColumnBelowItsMinimumIsCorrectedOnBothSides() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let outer = try XCTUnwrap(SplitViewPolicy.outermostColumnSplit(in: window.contentView))
        let inner = try XCTUnwrap(SplitViewPolicy.inspectorColumnSplit(in: outer), "the inspector's own split")
        unpinAutosave(outer); unpinAutosave(inner)

        outer.setPosition(144, ofDividerAt: 0)
        inner.setPosition(inner.frame.width - 150, ofDividerAt: 0)
        outer.layoutSubtreeIfNeeded(); inner.layoutSubtreeIfNeeded()
        pump(0.2)

        let report = try XCTUnwrap(SplitViewPolicy.apply(to: window))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(report.sidebarWidth), SplitViewPolicy.sidebar.minimum - 1)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(report.inspectorWidth), SplitViewPolicy.inspector.minimum - 1)
    }
}
