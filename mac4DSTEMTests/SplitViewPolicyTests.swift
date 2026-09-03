import AppKit
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// The split-view contract (owner decision 2026-09-03: AppKit's
/// `NSSplitViewController`, the way Xcode does it). Both side columns behave
/// the same — drag far, collapse when dragged past the minimum, reopen at
/// the width they had — the data pane keeps a floor, and a below-minimum
/// position is refused by AppKit itself, not corrected afterwards. Hosted
/// window tests: the only kind that can see the split items.
@MainActor
final class SplitViewPolicyTests: XCTestCase {

    private func pump(_ seconds: TimeInterval = 0.45) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeWindow(_ appState: AppState, inspector: Bool) async -> NSWindow {
        SplitViewPolicy.autosaveEnabled = false
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

    /// The split persists divider positions under `SplitViewPolicy.autosaveName`;
    /// a test that parks a divider must not hand that position to the next
    /// window (the S17 trap, hit again 2026-09-03).
    private func controller(_ window: NSWindow) throws -> ColumnSplitController {
        let c = try XCTUnwrap(SplitViewPolicy.controller(in: window), "the window's column controller")
        c.splitView.autosaveName = ""
        return c
    }

    func testThreeItemsOnOneControllerWithTheSameContractOnBothSides() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let c = try controller(window)
        XCTAssertEqual(c.splitViewItems.count, 3, "sidebar, workspace, inspector")

        XCTAssertEqual(c.sidebarItem.minimumThickness, SplitViewPolicy.sidebar.minimum)
        XCTAssertEqual(c.sidebarItem.maximumThickness, SplitViewPolicy.sidebar.maximum)
        XCTAssertTrue(c.sidebarItem.canCollapse)
        XCTAssertEqual(c.inspectorItem.minimumThickness, SplitViewPolicy.inspector.minimum)
        XCTAssertEqual(c.inspectorItem.maximumThickness, SplitViewPolicy.inspector.maximum)
        XCTAssertTrue(c.inspectorItem.canCollapse)
        XCTAssertEqual(c.contentItem.minimumThickness, SplitViewPolicy.detailMinimum)
        // Owner finding (e), 2026-09-03: the workspace holds least, so a drag
        // on either divider resizes the workspace and never the far column.
        XCTAssertLessThan(c.contentItem.holdingPriority.rawValue, c.inspectorItem.holdingPriority.rawValue)
        XCTAssertLessThan(c.inspectorItem.holdingPriority.rawValue, c.sidebarItem.holdingPriority.rawValue)
        XCTAssertFalse(c.inspectorItem.isCollapsed, "the inspector was asked for — collapsed \(c.splitViewItems.map(\.isCollapsed)), widths \(c.splitView.arrangedSubviews.map { $0.frame.width })")
        for host in [c.sidebarHost, c.contentHost, c.inspectorHost] {
            XCTAssertEqual(host.sizingOptions, [], "SwiftUI content must not size the column — that constraint is the loop")
        }
    }

    func testACollapseBySplitViewReachesTheNavigationFlags() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let c = try controller(window)

        c.sidebarItem.isCollapsed = true
        pump(0.3)
        XCTAssertFalse(appState.navigation.showToolsPane, "a drag-collapse reads as hidden to the toolbar and menu")
        c.inspectorItem.isCollapsed = true
        pump(0.3)
        XCTAssertFalse(appState.navigation.showInspectorPane)
    }

    func testTheFlagsDriveTheColumnsAndAColumnReopensAtTheWidthItHad() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: false)
        defer { window.orderOut(nil) }
        let c = try controller(window)
        XCTAssertTrue(c.inspectorItem.isCollapsed, "not asked for yet")

        c.splitView.setPosition(320, ofDividerAt: 0)
        c.splitView.layoutSubtreeIfNeeded(); pump(0.3)
        let before = c.splitView.arrangedSubviews[0].frame.width
        XCTAssertEqual(before, 320, accuracy: 2, "fixture precondition — split \(c.splitView.frame.width)pt wide, widths \(c.splitView.arrangedSubviews.map { $0.frame.width }), collapsed \(c.splitViewItems.map(\.isCollapsed))")

        appState.navigation.showToolsPane = false
        pump(0.8)
        XCTAssertTrue(c.sidebarItem.isCollapsed, "the toggle collapses the column")
        appState.navigation.showToolsPane = true
        pump(0.9)
        XCTAssertFalse(c.sidebarItem.isCollapsed)
        let after = c.splitView.arrangedSubviews[0].frame.width
        XCTAssertEqual(after, before, accuracy: 2, "the sidebar came back at \(after)pt, not the \(before)pt it had — collapsed \(c.splitViewItems.map(\.isCollapsed)), widths \(c.splitView.arrangedSubviews.map { $0.frame.width })")

        appState.navigation.showInspectorPane = true
        pump(0.9)
        XCTAssertFalse(c.inspectorItem.isCollapsed, "the inspector toggle opens its column")
    }

    /// Owner finding (e): dragging the sidebar divider moved the inspector.
    /// Moving divider 0 must change only the workspace's width.
    func testASidebarDragLeavesTheInspectorWhereItWas() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let c = try controller(window)
        let split = c.splitView
        let inspectorBefore = split.arrangedSubviews[2].frame.width
        let sidebarBefore = split.arrangedSubviews[0].frame.width
        split.setPosition(sidebarBefore + 120, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded(); pump(0.3)
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, sidebarBefore + 120, accuracy: 2, "the sidebar took the drag")
        XCTAssertEqual(split.arrangedSubviews[2].frame.width, inspectorBefore, accuracy: 1,
                       "the inspector moved with a sidebar drag — the workspace must hold least")
    }

    /// The 144pt sidebar of 2026-08-06 and the 92pt sliver of 2026-09-03: a
    /// below-minimum position is never shown — AppKit either holds the
    /// minimum or collapses the column (the drag-past-the-minimum gesture),
    /// on both sides. What it never does is a 144pt column with 305pt of
    /// content in it.
    func testABelowMinimumPositionIsRefusedOnBothSides() async throws {
        let appState = AppState()
        let window = await makeWindow(appState, inspector: true)
        defer { window.orderOut(nil) }
        let c = try controller(window)
        let split = c.splitView

        split.setPosition(144, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded(); pump(0.3)
        let sidebar = split.arrangedSubviews[0].frame.width
        XCTAssertTrue(sidebar >= SplitViewPolicy.sidebar.minimum - 1 || c.sidebarItem.isCollapsed,
                      "sidebar at \(sidebar)pt, collapsed=\(c.sidebarItem.isCollapsed)")

        split.setPosition(split.frame.width - 150, ofDividerAt: 1)
        split.layoutSubtreeIfNeeded(); pump(0.3)
        let inspector = split.arrangedSubviews[2].frame.width
        XCTAssertTrue(inspector >= SplitViewPolicy.inspector.minimum - 1 || c.inspectorItem.isCollapsed,
                      "inspector at \(inspector)pt, collapsed=\(c.inspectorItem.isCollapsed)")
    }
}
