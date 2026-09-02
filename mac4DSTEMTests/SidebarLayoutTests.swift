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
        window.contentView = NSHostingView(
            rootView: ContentView().environment(appState)
        )
        window.makeKeyAndOrderFront(nil)
        pump(1.2)
        return window
    }

    /// `NavigationSplitView` autosaves its divider position, and a machine that
    /// has run the app can restore a width *below* the 250pt minimum
    /// `ContentView` declares — 144pt was observed on 2026-08-06. The same
    /// strings wrap onto more lines there, so an unpinned width silently makes
    /// every height measurement machine-dependent.
    private func pinSidebarWidth(_ window: NSWindow, to width: CGFloat = 292) {
        func splitViews(_ view: NSView) -> [NSSplitView] {
            var found: [NSSplitView] = []
            if let s = view as? NSSplitView { found.append(s) }
            for sub in view.subviews { found += splitViews(sub) }
            return found
        }
        guard let split = splitViews(window.contentView!).first else { return }
        split.autosaveName = ""
        split.setPosition(width, ofDividerAt: 0)
        pump(0.4)
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
        //
        // The offset is clamped to what the document can *actually* scroll.
        // This used to force a flat 200pt, which was legal while every
        // workspace overflowed its column by 200–350pt. Since the 2026-08-06
        // density pass the calibrated sidebar fits exactly, so a forced 200pt
        // puts the clip view somewhere no scroll gesture can reach — and with
        // nothing scrollable, no event ever fires to re-clamp it. That is a
        // synthetic state, not a regression: asserting on it would be asserting
        // that AppKit recovers from an offset the user cannot produce. Scrolling
        // to the real maximum keeps the original guarantee under test wherever
        // there is still something to scroll, and is a no-op where there is not.
        if let scroll = sidebar(window) {
            let document = scroll.documentView?.bounds.height ?? 0
            let visible = scroll.contentView.bounds.height
            let scrollable = max(0, document - visible)
            scroll.contentView.scroll(
                to: NSPoint(x: 0, y: -scroll.contentInsets.top + min(200, scrollable))
            )
            scroll.reflectScrolledClipView(scroll.contentView)
            pump(0.3)
        }
        for area in [WorkspaceArea.results, .reconstruct] {
            appState.selectWorkspace(area)
            pump(0.4)
            assertSidebarTopIsBelowTheTitlebar("scrolled, then switched to \(area.title)")
        }

        withAnimation { appState.navigation.showToolsPane = false }
        pump(0.3)
        withAnimation { appState.navigation.showToolsPane = true }
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
            // S22c: Phase's default task is DPC, which has no blocking
            // prerequisites by design — the blocked/ready axis this test
            // measures only exists on ptychography, so select it explicitly.
            appState.changeMode(.ptychography)
            pump(0.6)

            let unmet = ProductWorkflow.prerequisites(
                for: appState.navigation.analysisMode, readiness: appState.productWorkflowReadiness
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

    /// Backlog #42 (2026-08-06 polish pass). `testSidebarDocumentRoughlyFitsItsColumn`
    /// below asserts this for **Reconstruct only**, which is how Prepare came to
    /// overflow by 332pt without any test noticing. Measured before the pass, in
    /// a 1470×923 window with the declared 292pt sidebar:
    ///
    /// | workspace   | ready  | blocked |
    /// |-------------|--------|---------|
    /// | Prepare     | 1081   | **1203**|
    /// | Map         | 1000   | 968     |
    /// | Image       | 949    | 917     |
    /// | Reconstruct | 919    | 887     |
    /// | Results     | 871    | 871     |
    ///
    /// against 871pt of column. The stable contract that survived S17 is that
    /// every calibrated workspace, and every uncalibrated workspace except
    /// Prepare, fits the column. Uncalibrated Prepare's old 60pt allowance was
    /// justified with one machine's 49pt measurement, not a product invariant;
    /// its explicit quarantine below records the live geometry on every run.
    func testEveryNonQuarantinedWorkspaceSidebarFitsItsColumn() async throws {
        for calibrated in [true, false] {
            let appState = AppState()
            await appState.openDemoFixture(calibrated: calibrated)
            let window = makeWindow(appState)
            defer { window.orderOut(nil) }
            pinSidebarWidth(window)

            for area in WorkspaceArea.allCases {
                if !calibrated && area == .prepare { continue }
                appState.selectWorkspace(area)
                // S22d made sidebar HEIGHT depend on the published wrap
                // WIDTH — so the width must be pinned at measurement time,
                // not once at window creation: a LIVE app instance
                // autosaving its own sidebar width (250pt at the minimum)
                // into the shared defaults re-restored the harness window
                // to that width after the initial pin, and at 250pt the
                // wrapped rows measure a real 810.5pt (observed twice on
                // 2026-09-01, exactly when the owner's instance was open;
                // green when it was closed). Re-pin per workspace, then wait
                // for the height to hold still.
                pinSidebarWidth(window)
                pump(0.5)
                let scroll = try XCTUnwrap(sidebar(window))
                var document = try XCTUnwrap(scroll.documentView).bounds.height
                for _ in 0..<8 {
                    pump(0.3)
                    let next = try XCTUnwrap(scroll.documentView).bounds.height
                    if next == document { break }
                    document = next
                }
                let available = scroll.bounds.height - scroll.contentInsets.top
                XCTAssertLessThanOrEqual(
                    document, available + 8,
                    "\(area.title) (calibrated=\(calibrated)) sidebar is \(document)pt "
                        + "against \(available)pt of column — it still has to scroll, so the "
                        + "panel still changes shape when you switch to it"
                )
            }
        }
    }

    /// v2 S17 formal quarantine. The former gate allowed uncalibrated Prepare
    /// 60pt of overflow; the all-workspace test justified that already-existing
    /// number with a 2026-08-06 machine's 49pt measurement. It was not a
    /// declared row height or any other stable product property: the same
    /// unchanged tree later measured 62pt locally and failed on a macOS 26 CI
    /// runner. Widening 60 to another observed number would preserve the defect.
    ///
    /// Keep this as a visible skip, rather than silently omitting the case. The
    /// attachment makes every local/CI run an observation with the quantities
    /// S17 needed: document/column geometry, display scale, and WindowServer
    /// state. Track B's default-width sidebar row remains the acceptance gate.
    func testUncalibratedPrepareSidebarHeightHasNoNumericGate() async throws {
        let appState = AppState()
        await appState.openDemoFixture(calibrated: false)
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }
        pinSidebarWidth(window)
        appState.selectWorkspace(.prepare)
        pump(0.5)

        let scroll = try XCTUnwrap(sidebar(window))
        let available = scroll.bounds.height - scroll.contentInsets.top
        let document = try XCTUnwrap(scroll.documentView).bounds.height
        let screen = window.screen
        let insets = scroll.contentInsets
        let session = CGSessionCopyCurrentDictionary() as NSDictionary?
        let onConsole = session?[kCGSessionOnConsoleKey] as? Bool
        let loginDone = session?[kCGSessionLoginDoneKey] as? Bool
        let report = """
        v2 S17 sidebar quarantine observation
        os=\(ProcessInfo.processInfo.operatingSystemVersionString)
        documentHeight=\(document)
        availableHeight=\(available)
        overflow=\(document - available)
        sidebarWidth=\(scroll.bounds.width)
        contentInsets=(top: \(insets.top), left: \(insets.left), bottom: \(insets.bottom), right: \(insets.right))
        backingScaleFactor=\(screen?.backingScaleFactor ?? 0)
        screenFrame=\(NSStringFromRect(screen?.frame ?? .zero))
        visibleFrame=\(NSStringFromRect(screen?.visibleFrame ?? .zero))
        windowIsKey=\(window.isKeyWindow)
        windowIsMain=\(window.isMainWindow)
        windowIsVisible=\(window.isVisible)
        windowOcclusionVisible=\(window.occlusionState.contains(.visible))
        sessionOnConsole=\(onConsole.map(String.init) ?? "unknown")
        sessionLoginDone=\(loginDone.map(String.init) ?? "unknown")
        """
        let attachment = XCTAttachment(string: report)
        attachment.name = "sidebar-s17-geometry.txt"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)

        throw XCTSkip(
            "v2 S17: uncalibrated Prepare measured \(document)pt against "
                + "\(available)pt. The former 60pt allowance was historical, "
                + "not an invariant; see sidebar-s17-geometry.txt "
                + "and Track B's default-width sidebar row."
        )
    }

    /// Backlog #39. Grouping Reconstruct's controls into four collapsible
    /// stages must not take the accelerating-voltage field with them.
    ///
    /// The retired UI automation (deleted 2026-09-02) located that field
    /// *structurally*, by looking for a text field in the row labelled
    /// "Voltage" — it had no identifier in the automation's own lookup path.
    /// Inside a collapsed disclosure the field would not exist, the QC
    /// playthrough would call `recordError` and skip parallax entirely, and the
    /// run would still finish. That is a gate failing quietly, so the field's
    /// presence is pinned here where it fails loudly instead.
    /// The Result colormap must be reachable from Results.
    ///
    /// The 2026-08-06 polish pass hid the whole display section when
    /// `workspaceArea == .results`. The Result picker is gated on
    /// `resultImage != nil`, so the control that recolours a result existed in
    /// every workspace *except* the one built for looking at results: you had
    /// to leave the image to change how it was drawn. The 2026-09-01 UI pair
    /// then made both colormap controls permanent rather than disclosure-bound.
    ///
    /// This asserts the *decision*, not the rendering, and that is deliberate.
    /// A window-based version was written first and could not work: SwiftUI
    /// builds a `Picker`'s `NSPopUpButton` menu lazily for a real assistive
    /// client, so in-process every pop-up in the tree reports `itemTitles ==
    /// []`, `title == ""`, `numberOfItems == 0` and a nil `selectedItem`
    /// (measured 2026-08-06 — the same wall
    /// `testAcceleratingVoltageStaysOutsideTheReconstructStages` documents for
    /// accessibility identifiers). Nothing distinguishes the colormap picker
    /// from any other pop-up, so the only available assertion would be a count
    /// of anonymous controls — which passes just as happily on the wrong one.
    /// Don't retry it.
    // `testDisplaySectionScopesItsContentsRatherThanHidingItself` was
    // RETIRED with the sidebar Display section itself (D3, 2026-09-01): the
    // colormap control now lives on each pane's colorbar chip
    // (`ColormapChipMenu`), so the reachability invariant it pinned — a
    // displayed result's recolour control must exist wherever the result is
    // shown — holds structurally: the chip and the image are the same
    // surface and cannot be scoped apart.

    /// S22 feedback R1 (2026-09-01): the sidebar cannot be forced outside its
    /// declared 250–340pt band AT ALL any more. The hard `minWidth` on the
    /// column root refuses the very position change a stale restoration
    /// (144pt — the standing Track B row) or a hard drag used to achieve;
    /// this test's earlier form PROVED the assertion discriminates, because
    /// with the floor absent the same `setPosition(144)` measured 139–144pt
    /// on screen and in this harness, and with the floor present its
    /// below-minimum precondition became unsatisfiable — that gate failure is
    /// what prompted this rewrite. `SplitViewWidthClamp` stays as a second
    /// belt for restore paths that bypass layout.
    func testTheSidebarRefusesPositionsOutsideItsDeclaredBand() async throws {
        let appState = AppState()
        await appState.openDemoFixture()
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }
        pump(0.6)

        let split = try XCTUnwrap(
            SplitViewWidthClamp.outermostColumnSplit(in: window.contentView),
            "no column split view in the window"
        )
        split.setPosition(144, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        pump(0.2)
        let afterFloorPush = try XCTUnwrap(split.arrangedSubviews.first).frame.width
        XCTAssertGreaterThanOrEqual(
            afterFloorPush, SplitViewWidthClamp.sidebarMinimum - 1,
            "a forced 144pt sidebar must be refused by the floor; got \(afterFloorPush)"
        )

        // The 340pt CEILING is deliberately not asserted here: it is enforced
        // at the gesture level (the declared max resists user drags — held at
        // exactly 340 in the live drive, 2026-09-01) and via the AppKit
        // thickness bounds, which need a contentViewController this harness
        // window does not have. A programmatic setPosition(700) bypasses
        // both intermittently, which made the assertion flaky in the full
        // suite while passing standalone — a timing artifact, not a product
        // property.
    }

    /// S22c moved the accelerating-voltage field to Prepare's Calibration
    /// section — DPC, parallax and ptychography all consume it (pipelines
    /// §7.4), so it lives with the other physical scales rather than inside
    /// one consumer's workflow. Counted as real `NSTextField`s because SwiftUI
    /// puts no accessibility identifiers on the NSView tree (measured
    /// 2026-08-06). Pinned from both sides: Prepare renders an editable field;
    /// Reconstruct → Ptychography renders NONE (its open stage 1 is a button,
    /// collapsed stages render nothing) — a nonzero count there is the field
    /// back in its old home, or duplicated.
    func testAcceleratingVoltageLivesInPrepareNotTheReconstructStages() async throws {
        let appState = AppState()
        await appState.openDemoFixture()
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }
        pinSidebarWidth(window)

        // EDITABLE fields only: AppKit renders some SwiftUI text (for
        // example a Menu label's content, like D3's colorbar chips) as
        // non-editable `NSTextField`s, which are labels, not inputs.
        func textFields(_ view: NSView) -> Int {
            var n = (view as? NSTextField)?.isEditable == true ? 1 : 0
            for sub in view.subviews { n += textFields(sub) }
            return n
        }

        appState.selectWorkspace(.prepare)
        pump(0.8)
        XCTAssertGreaterThanOrEqual(
            textFields(window.contentView!), 1,
            "Prepare must offer the voltage field alongside the other calibration controls"
        )

        appState.selectWorkspace(.reconstruct)
        appState.changeMode(.ptychography)
        pump(0.8)
        XCTAssertEqual(
            textFields(window.contentView!), 0,
            "no editable field belongs in Reconstruct → Ptychography once the "
                + "voltage moved to Prepare — a nonzero count is the field back in "
                + "its old home, or duplicated"
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
