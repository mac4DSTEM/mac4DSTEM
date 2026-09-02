import AppKit
import DSTEMCore
import DSTEMSession
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// Backlog #16 / #22 — nothing inside the window may be laid out taller than the
/// window.
///
/// **The mechanism, established by bisection on 2026-08-06.** Every wrapping
/// `Text` in `TaskPrerequisiteChecklist` carries
/// `.fixedSize(horizontal: false, vertical: true)` so its explanation is never
/// truncated. Measured at a narrow proposed width those strings wrap to many
/// lines, and `fixedSize(vertical:)` turns that into a *hard minimum height*
/// which propagates up through the detail column, the outer `NSSplitView` and
/// the hosting view — past the window's own height. The sidebar inherits a
/// column taller than the window, its top rows land off-screen, and the titlebar
/// hit-tests over them. That is the whole bug: rows drawn across the traffic
/// lights, and a primary action that "exists but is not hittable".
///
/// **Why the old test did not catch it.**
/// `SidebarLayoutTests.testSidebarContentNeverDrawsOverTheTitlebar` asserts
/// `clipOrigin == -contentInsets.top`, which is **true throughout the collapse**
/// — nothing ever scrolls. Six in-process reproductions failed for the same
/// reason: they all hunted the scroll offset. A frame height is a pure layout
/// property and reproduces in a hosted test immediately, which is why this one
/// needs no screen and no Accessibility grant.
///
/// **Assert against the window, never against `contentView.bounds`** — the
/// content view is the hosting view and it grows *with* the defect, so comparing
/// the two compares the bug to itself and always passes.
@MainActor
final class SplitViewHeightTests: XCTestCase {

    private static let windowHeight: CGFloat = 923

    private func pump(_ seconds: TimeInterval = 0.45) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Pump until the hosting view's height stops changing, rather than for a
    /// fixed duration.
    ///
    /// A fixed pump made these tests **flaky in both directions** — measured
    /// 2026-08-06: at 0.6 s the task-switch case caught the unfixed build and
    /// the sweep did not; at 0.9 s the sweep caught it and the task-switch case
    /// did not. SwiftUI settles this layout over several run-loop turns, so any
    /// single duration is a guess about someone else's machine. Waiting for
    /// quiescence removes the guess.
    private func settle(_ window: NSWindow, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = CGFloat.nan
        var stableTurns = 0
        while Date() < deadline {
            pump(0.15)
            let height = window.contentView?.bounds.height ?? .nan
            stableTurns = (height == previous) ? stableTurns + 1 : 0
            previous = height
            // Three consecutive identical measurements: enough that a mid-
            // animation plateau does not read as settled.
            if stableTurns >= 3 { return }
        }
    }

    private func makeWindow(_ appState: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1470, height: Self.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "mac4DSTEM"
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: ContentView().environment(appState))
        window.makeKeyAndOrderFront(nil)
        pump(1.2)
        return window
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let s = view as? NSScrollView { found.append(s) }
        for sub in view.subviews { found += scrollViews(sub) }
        return found
    }

    private func sidebar(_ window: NSWindow) -> NSScrollView? {
        scrollViews(window.contentView!).last
    }

    /// The tallest view in the tree, named, so a failure says *what* overflowed
    /// rather than only that something did.
    private func tallest(_ view: NSView) -> (name: String, height: CGFloat) {
        var worst = (String(describing: type(of: view)), view.bounds.height)
        for sub in view.subviews {
            let candidate = tallest(sub)
            if candidate.height > worst.1 { worst = (candidate.name, candidate.height) }
        }
        return worst
    }

    private func assertFitsTheWindow(
        _ window: NSWindow, _ stage: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let available = window.contentRect(forFrameRect: window.frame).height
        let root = window.contentView!
        let worst = tallest(root)
        XCTAssertLessThanOrEqual(
            root.bounds.height, available + 1,
            "\(stage): the hosting view is \(root.bounds.height)pt in a \(available)pt "
                + "window — tallest subview \(worst.name) at \(worst.height)pt. Content "
                + "taller than its window is laid out off the top, where the titlebar "
                + "hit-tests over it (backlog #16/#22).",
            file: file, line: line
        )
        if let scroll = sidebar(window) {
            XCTAssertLessThanOrEqual(
                scroll.bounds.height, available + 1,
                "\(stage): the sidebar scroll view is \(scroll.bounds.height)pt in a "
                    + "\(available)pt window, so its top rows are off-screen. Measured "
                    + "1291.5 vs 923 before the fix.",
                file: file, line: line
            )
        }
    }

    /// The exact reproduction: Image → DPC on a partially calibrated dataset.
    ///
    /// `calibrated: false` is load-bearing. The click only changes the layout
    /// because `ProductWorkflow.guidance(for: .dpc, …)` is non-empty, which is
    /// what mounts the checklist; with a fully calibrated fixture the header
    /// never grows and there is nothing to reproduce.
    func testNothingIsLaidOutTallerThanTheWindowOnATaskSwitch() async throws {
        let appState = AppState()
        await appState.openDemoFixture(calibrated: false)
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        appState.selectWorkspace(.image)
        appState.changeMode(.virtualDetector)
        settle(window)

        XCTAssertFalse(
            ProductWorkflow.guidance(
                for: .dpc, readiness: appState.productWorkflowReadiness
            ).isEmpty,
            "fixture precondition: DPC must have guidance, or the header never grows "
                + "and this test cannot reproduce anything"
        )
        assertFitsTheWindow(window, "baseline · Image / Virtual imaging")

        appState.changeMode(.dpc)
        settle(window)
        assertFitsTheWindow(window, "after the Image → DPC task switch")
    }

    /// Blocked tasks take the *other* branch of the checklist — the summary row
    /// with an unmet requirement and its resolution — and Reconstruct (five
    /// unmet) is where the release owner originally hit this.
    ///
    /// **This is coverage, not a tripwire, and the difference was measured.**
    /// Verified 2026-08-06: it passes 3/3 *with the fix reverted*, so it does
    /// not currently discriminate — these paths do not overflow on their own.
    /// It is kept because the invariant is real and cheap, and because a future
    /// change to the blocked-task header would be caught here; it is documented
    /// as non-discriminating so nobody reads a green run as evidence that #16
    /// is fixed. The tests that do discriminate are
    /// `testNothingIsLaidOutTallerThanTheWindowOnATaskSwitch` and
    /// `testEveryWorkspaceAndTaskFitsTheWindow`, both verified to fail 3/3
    /// without the fix.
    ///
    /// The remaining two `fixedSize` sites (`satisfiedSummary` and the
    /// `.taskPanel` hint) render only once the disclosure is expanded, and
    /// `isExpanded` is private `@State` with no way to drive it from a hosted
    /// test. Widening its access purely for a test is what ROADMAP P3.2 forbids,
    /// so those two are protected by sharing `explanationLineLimit` with the
    /// site this suite *does* exercise — not by an assertion here.
    func testABlockedTaskAlsoFitsTheWindow() async throws {
        let appState = AppState()
        await appState.openDemoFixture(calibrated: false)
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        appState.selectWorkspace(.reconstruct)
        settle(window)

        XCTAssertFalse(
            ProductWorkflow.prerequisites(
                for: .ptychography, readiness: appState.productWorkflowReadiness
            ).isEmpty,
            "fixture precondition: Reconstruct must be blocked, or the checklist "
                + "renders neither the satisfied summary nor a task-panel hint"
        )
        assertFitsTheWindow(window, "Reconstruct, blocked, checklist collapsed")

        appState.selectWorkspace(.map)
        settle(window)
        appState.changeMode(.acom)
        settle(window)
        assertFitsTheWindow(window, "ACOM, blocked on disks and a phase model")
    }

    /// Every workspace and task, so a future view added to the detail column
    /// cannot reintroduce an unbounded height demand unnoticed.
    func testEveryWorkspaceAndTaskFitsTheWindow() async throws {
        let appState = AppState()
        await appState.openDemoFixture(calibrated: false)
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        for area in WorkspaceArea.allCases {
            appState.selectWorkspace(area)
            settle(window)
            assertFitsTheWindow(window, "workspace \(area.title)")
            for mode in area.analysisModes {
                appState.changeMode(mode)
                settle(window)
                assertFitsTheWindow(window, "\(area.title) · \(mode.productTitle)")
            }
        }
    }
}
