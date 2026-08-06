import AppKit
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// Layout regressions that only a real window can catch.
///
/// `mac4DSTEMTests` is a *hosted* target, so these run in-process with the app
/// and can build a real `NSWindow` around the real `ContentView` and measure
/// the AppKit view tree. That is how backlog #16 was pinned down: the symptom
/// is numeric, and no unit test on `ProductWorkflow` could ever see it.
@MainActor
final class SidebarLayoutTests: XCTestCase {

    private func pump(_ seconds: TimeInterval = 0.45) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeWindow(_ appState: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1470, height: 923),
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

    /// The sidebar is the deepest/last scroll view in the tree; the detail
    /// column's own scroll views (inspector, log) appear earlier.
    private func sidebar(_ window: NSWindow) -> NSScrollView? {
        scrollViews(window.contentView!).last
    }

    private func metalPanes(_ view: NSView) -> [NSView] {
        var found: [NSView] = []
        let name = String(describing: type(of: view))
        if name.contains("MTK") || name.contains("Metal") { found.append(view) }
        for sub in view.subviews { found += metalPanes(sub) }
        return found
    }

    /// Backlog #16. The reported symptom — sidebar rows drawn across the
    /// traffic lights, and the top rows inert because the titlebar hit-tests
    /// above them — is exactly one condition: the sidebar scroll view sitting
    /// at clip origin 0 instead of `-contentInsets.top`, i.e. scrolled one
    /// titlebar-height past its own top.
    ///
    /// Measured broken:  docTopInWindow 923, visibleOriginY  0
    /// Measured healthy: docTopInWindow 871, visibleOriginY -52
    ///
    /// This asserts the healthy relationship holds after every transition that
    /// was a candidate trigger, so a future change cannot silently reintroduce
    /// the state that swallows clicks.
    func testSidebarContentNeverDrawsOverTheTitlebar() async throws {
        let appState = AppState()
        await appState.openDemoFixture()
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        func assertSidebarTopIsBelowTheTitlebar(_ stage: String) {
            guard let scroll = sidebar(window) else {
                return XCTFail("no sidebar scroll view at stage: \(stage)")
            }
            let inset = scroll.contentInsets.top
            XCTAssertGreaterThan(
                inset, 0,
                "\(stage): sidebar lost its titlebar accommodation entirely"
            )
            XCTAssertEqual(
                scroll.contentView.bounds.origin.y, -inset, accuracy: 0.5,
                "\(stage): sidebar clip origin is \(scroll.contentView.bounds.origin.y), "
                    + "expected \(-inset). At origin 0 the first rows render under the "
                    + "titlebar, which hit-tests above them and swallows their clicks."
            )
            // The clip-origin assertion above is NOT sufficient, and believing it
            // was cost this bug five months. #16's real mechanism turned out to
            // be the sidebar's *frame* growing taller than the window while its
            // clip origin stayed perfectly correct — so every assertion here
            // passed with the collapse on screen. Measured 2026-08-06: 1291.5pt
            // of scroll view in a 923pt window. `SplitViewHeightTests` owns this
            // invariant properly; this is the tripwire on the path that was
            // already being driven.
            let available = window.contentRect(forFrameRect: window.frame).height
            XCTAssertLessThanOrEqual(
                scroll.bounds.height, available + 1,
                "\(stage): sidebar scroll view is \(scroll.bounds.height)pt inside a "
                    + "\(available)pt window — a correct clip origin inside an "
                    + "oversized frame still puts the top rows off-screen (#16/#22)."
            )
        }

        assertSidebarTopIsBelowTheTitlebar("baseline · Prepare")

        for area in [WorkspaceArea.map, .reconstruct, .results, .reconstruct, .image, .prepare] {
            appState.selectWorkspace(area)
            pump(0.3)
            assertSidebarTopIsBelowTheTitlebar("after switching to \(area.title)")
        }

        // Scrolled down, then switched to a workspace with a shorter sidebar
        // document — AppKit must re-clamp to the inset-aware floor, not to 0.
        if let scroll = sidebar(window) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top + 200))
            scroll.reflectScrolledClipView(scroll.contentView)
            pump(0.3)
        }
        for area in [WorkspaceArea.results, .reconstruct] {
            appState.selectWorkspace(area)
            pump(0.4)
            assertSidebarTopIsBelowTheTitlebar("scrolled, then switched to \(area.title)")
        }

        withAnimation { appState.showToolsPane = false }
        pump(0.3)
        withAnimation { appState.showToolsPane = true }
        pump(0.4)
        assertSidebarTopIsBelowTheTitlebar("after an animated tools-pane round trip")

        window.setContentSize(NSSize(width: 1180, height: 700))
        pump(0.4)
        assertSidebarTopIsBelowTheTitlebar("after resizing the window")
    }

    /// Backlog #21. A blocked task used to spend 191pt of the main pane
    /// restating requirements the sidebar was already listing, which shrank the
    /// image panes from 646×646 to 516×516 — a 36% loss of image area on the
    /// one screen where the user is trying to see their data.
    ///
    /// Readiness now has a single owner (the checklist) at a density
    /// proportional to how blocked you are, so being blocked must no longer
    /// cost image area.
    func testBeingBlockedDoesNotShrinkTheImagePanes() async throws {
        var paneSize: [Bool: CGFloat] = [:]

        for calibrated in [true, false] {
            let appState = AppState()
            await appState.openDemoFixture(calibrated: calibrated)
            let window = makeWindow(appState)
            defer { window.orderOut(nil) }

            appState.selectWorkspace(.reconstruct)
            pump(0.6)

            let unmet = ProductWorkflow.prerequisites(
                for: appState.analysisMode, readiness: appState.productWorkflowReadiness
            ).count
            XCTAssertEqual(
                unmet == 0, calibrated,
                "fixture precondition: calibrated=\(calibrated) should decide blockedness"
            )

            let pane = try XCTUnwrap(
                metalPanes(window.contentView!).first, "no Metal pane on Reconstruct"
            )
            paneSize[calibrated] = pane.bounds.height
        }

        let ready = try XCTUnwrap(paneSize[true])
        let blocked = try XCTUnwrap(paneSize[false])
        XCTAssertEqual(
            blocked, ready, accuracy: 1,
            "a blocked Reconstruct renders its image panes at \(blocked)pt against "
                + "\(ready)pt when ready — the prerequisite list is eating image area again"
        )
    }

    /// Backlog #17b. The image is drawn by `MetalImageView`, an NSView-backed
    /// representable, so it is worth proving the SwiftUI `rotationEffect`
    /// actually reaches it rather than assuming: a quarter turn on a 200×50
    /// result must make the pane's on-screen footprint tall instead of wide.
    func testAQuarterTurnActuallyReorientsTheRenderedPane() async throws {
        let appState = AppState()
        await appState.openDemoFixture()
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        // A wide, short scan-domain result — the Si_SiGe strain-map shape.
        appState.resultImage = FloatImage(
            width: 200, height: 50, pixels: [Float](repeating: 0.5, count: 200 * 50)
        )
        appState.selectWorkspace(.results)
        pump(0.8)

        func paneFootprint() throws -> CGRect {
            let pane = try XCTUnwrap(
                metalPanes(window.contentView!).first, "no Metal pane in Results"
            )
            return pane.convert(pane.bounds, to: nil)
        }

        appState.realSpaceDisplayOrientation = .identity
        pump(0.5)
        let upright = try paneFootprint()
        XCTAssertGreaterThan(
            upright.width, upright.height,
            "a 200×50 result should render wider than it is tall"
        )

        appState.realSpaceDisplayOrientation = .quarterTurn
        pump(0.5)
        let turned = try paneFootprint()
        XCTAssertGreaterThan(
            turned.height, turned.width,
            "after a quarter turn the same result must render taller than it is wide "
                + "— the rotation is not reaching the Metal-backed pane"
        )

        // The turn is exact, so the footprint's aspect must simply invert.
        XCTAssertEqual(
            turned.height / turned.width, upright.width / upright.height,
            accuracy: 0.05,
            "a quarter turn must invert the aspect exactly, not merely change it"
        )
    }

    /// The sidebar column must be able to hold its own content: every point it
    /// overflows is a point the user has to scroll, and scrolling is the only
    /// way into #16's bad state. Blocked Reconstruct was the worst case at
    /// 1040pt against 871pt available.
    func testSidebarDocumentRoughlyFitsItsColumn() async throws {
        let appState = AppState()
        await appState.openDemoFixture(calibrated: false)
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        appState.selectWorkspace(.reconstruct)
        pump(0.6)

        let scroll = try XCTUnwrap(sidebar(window))
        let available = scroll.bounds.height - scroll.contentInsets.top
        let document = try XCTUnwrap(scroll.documentView).bounds.height
        XCTAssertLessThan(
            document, available + 60,
            "blocked Reconstruct sidebar is \(document)pt against \(available)pt of column "
                + "— it overflowed by 169pt before the duplicate readiness block was removed"
        )
    }
}
