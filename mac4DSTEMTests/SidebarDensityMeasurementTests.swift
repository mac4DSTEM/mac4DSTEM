import AppKit
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// **Measurement harness, not a gate.** Written for the 2026-08-06 UI polish
/// pass to cost the "it explains itself permanently" complaint the same way
/// #21 was costed before it was designed: real numbers from a real window,
/// printed, so a direction can be chosen against them rather than by taste.
///
/// Every test here prints and asserts nothing meaningful. Once a direction is
/// chosen, the surviving invariants move into `SidebarLayoutTests`.
@MainActor
final class SidebarDensityMeasurementTests: XCTestCase {

    /// `xcodebuild` does not forward a hosted test's stdout, and the app target
    /// is sandboxed, so measurements are appended to a file in the app's own
    /// container where the caller can read them back.
    private static let reportURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mac4dstem-density-measurements.txt")

    private func report(_ line: String) {
        print(line)
        let url = Self.reportURL
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

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
        // `NavigationSplitView` autosaves its divider, and this machine's saved
        // state restores 144pt — *below* the 250pt minimum ContentView declares.
        // Measuring at 144pt inflates every height, because the same strings
        // wrap onto more lines. Pin the declared ideal so numbers describe the
        // app as designed rather than as one machine happens to have left it.
        if let split = splitViews(window.contentView!).first {
            split.autosaveName = ""
            split.setPosition(292, ofDividerAt: 0)
            pump(0.4)
        }
        return window
    }

    private func splitViews(_ view: NSView) -> [NSSplitView] {
        var found: [NSSplitView] = []
        if let s = view as? NSSplitView { found.append(s) }
        for sub in view.subviews { found += splitViews(sub) }
        return found
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

    private func metalPanes(_ view: NSView) -> [NSView] {
        var found: [NSView] = []
        let name = String(describing: type(of: view))
        if name.contains("MTK") || name.contains("Metal") { found.append(view) }
        for sub in view.subviews { found += metalPanes(sub) }
        return found
    }

    /// Renders the whole window's view tree to a PNG **offscreen**, via
    /// `cacheDisplay`, so it needs no Screen Recording grant — unlike
    /// `XCUIScreenshot`, which is what blocks the QC playthrough. Metal-backed
    /// image panes do not draw into a cached bitmap, so they come out empty;
    /// this is a chrome/layout capture, not a data capture.
    private func writePNG(_ view: NSView?, name: String) {
        guard let view else { return }
        view.layoutSubtreeIfNeeded()
        // SwiftUI text is drawn asynchronously into the layer tree; capturing
        // straight after a layout pass yields a bitmap with the boxes but not
        // the glyphs. Give the run loop a turn, then force a synchronous draw.
        pump(1.0)
        view.displayIfNeeded()
        view.display()
        pump(0.25)
        view.display()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac4dstem-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Captures every workspace, ready and blocked, as layout evidence for the
    /// polish pass. Named with a stage prefix so before/after sets can sit side
    /// by side.
    func testCaptureEveryWorkspace() async throws {
        let stage = ProcessInfo.processInfo.environment["MAC4DSTEM_SHOT_STAGE"] ?? "before"
        for calibrated in [true, false] {
            let appState = AppState()
            await appState.openDemoFixture(calibrated: calibrated)
            let window = makeWindow(appState)
            defer { window.orderOut(nil) }
            let suffix = calibrated ? "ready" : "blocked"
            for area in WorkspaceArea.allCases {
                appState.selectWorkspace(area)
                pump(0.6)
                // The sidebar's *document* view, not the window: it renders at
                // full document height, so an overflowing column is visible in
                // the capture instead of being clipped away by the scroller.
                writePNG(sidebar(window)?.documentView,
                         name: "\(stage)-sidebar-\(area.rawValue)-\(suffix)")
                writePNG(window.contentView, name: "\(stage)-window-\(area.rawValue)-\(suffix)")
            }
        }
        report("\n=== wrote \(stage) captures to \(NSTemporaryDirectory())mac4dstem-shots ===")
    }

    /// Measures an isolated view's laid-out height at the sidebar's real width.
    private func height<V: View>(of view: V, width: CGFloat = 292) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    // MARK: - 1. What the sidebar costs, per workspace

    /// The "panel jumps" complaint, quantified: how much the sidebar document
    /// height changes as you move between workspaces, and how much of the
    /// column each one overflows.
    func testMeasureSidebarDocumentHeightPerWorkspace() async throws {
        for calibrated in [true, false] {
            let appState = AppState()
            await appState.openDemoFixture(calibrated: calibrated)
            let window = makeWindow(appState)
            defer { window.orderOut(nil) }

            report("\n=== sidebar document height · calibrated=\(calibrated) ===")
            var heights: [String: CGFloat] = [:]
            for area in WorkspaceArea.allCases {
                appState.selectWorkspace(area)
                pump(0.5)
                guard let scroll = sidebar(window) else { continue }
                let available = scroll.bounds.height - scroll.contentInsets.top
                let document = (scroll.documentView?.bounds.height ?? 0)
                heights[area.title] = document
                let pane = metalPanes(window.contentView!).first?.bounds.height ?? 0
                report(String(
                    format: "%-12@  doc %7.1f pt   column %7.1f pt   overflow %7.1f pt   pane %6.1f pt",
                    area.title as NSString, document, available, document - available, pane
                ))
            }
            let values = heights.values.sorted()
            if let lo = values.first, let hi = values.last {
                report(String(format: "  → shape change across workspaces: %.1f pt (%.1f → %.1f)",
                             hi - lo, lo, hi))
            }
        }
    }

    /// Costs the individual blocks Prepare is made of, so the remaining
    /// overflow can be aimed at rather than guessed at.
    func testMeasurePrepareSectionCosts() async throws {
        for calibrated in [true, false] {
            let appState = AppState()
            await appState.openDemoFixture(calibrated: calibrated)
            _ = makeWindow(appState)

            report("\n=== Prepare block costs · calibrated=\(calibrated) ===")
            let blocks: [(String, AnyView)] = [
                ("CalibrationReadinessChecklist",
                 AnyView(CalibrationReadinessChecklist().environment(appState))),
                ("CalibrationDetailsView",
                 AnyView(CalibrationDetailsView().environment(appState))),
                ("TaskPrerequisiteChecklist-ish",
                 AnyView(CalibrationReadinessChecklist(showsCompletionMessage: false)
                     .environment(appState))),
            ]
            for (name, view) in blocks {
                report(String(format: "  %-32@ %7.1f pt", name as NSString, height(of: view)))
            }
        }
    }

    /// Reproduces the three quantities `SidebarLayoutTests`'s #16 tripwire
    /// asserts on, at every stage it walks, so a failure can be read as numbers
    /// rather than inferred.
    func testMeasureTitlebarTripwireQuantities() async throws {
        let appState = AppState()
        await appState.openDemoFixture()
        let window = makeWindow(appState)
        defer { window.orderOut(nil) }

        func snapshot(_ stage: String) {
            guard let scroll = sidebar(window) else {
                return report("  \(stage): NO SIDEBAR SCROLL VIEW")
            }
            let available = window.contentRect(forFrameRect: window.frame).height
            report(String(
                format: "  %-44@ inset %6.1f  clipY %8.1f  scrollH %8.1f  windowH %7.1f  %@",
                stage as NSString, scroll.contentInsets.top,
                scroll.contentView.bounds.origin.y, scroll.bounds.height, available,
                (abs(scroll.contentView.bounds.origin.y + scroll.contentInsets.top) < 0.5
                 && scroll.bounds.height <= available + 1) ? "OK" : "*** VIOLATION ***" as NSString
            ))
        }

        report("\n=== #16 tripwire quantities ===")
        snapshot("baseline · Prepare")
        for area in [WorkspaceArea.map, .reconstruct, .results, .reconstruct, .image, .prepare] {
            appState.selectWorkspace(area)
            pump(0.3)
            snapshot("after switching to \(area.title)")
        }
        if let scroll = sidebar(window) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top + 200))
            scroll.reflectScrolledClipView(scroll.contentView)
            pump(0.3)
        }
        for area in [WorkspaceArea.results, .reconstruct] {
            appState.selectWorkspace(area)
            pump(0.4)
            snapshot("scrolled, then switched to \(area.title)")
        }
        withAnimation { appState.showToolsPane = false }
        pump(0.3)
        withAnimation { appState.showToolsPane = true }
        pump(0.4)
        snapshot("after an animated tools-pane round trip")
        window.setContentSize(NSSize(width: 1180, height: 700))
        pump(0.4)
        snapshot("after resizing the window")
    }

    // MARK: - 2. What the permanent captions cost

    /// The per-row cost of the always-on subtitle, measured by laying out the
    /// same row with and without it. This is the number the polish pass is
    /// trading against.
    func testMeasurePermanentCaptionCostPerRow() throws {
        func row(title: String, subtitle: String?, symbol: String) -> some View {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline)
                    if let subtitle {
                        Text(subtitle).font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
        }

        report("\n=== permanent-caption cost per row (292pt column) ===")

        var workspaceWith: CGFloat = 0, workspaceWithout: CGFloat = 0
        for area in WorkspaceArea.allCases {
            let w = height(of: row(title: area.title, subtitle: area.subtitle,
                                   symbol: area.systemImage))
            let wo = height(of: row(title: area.title, subtitle: nil,
                                    symbol: area.systemImage))
            workspaceWith += w; workspaceWithout += wo
            report(String(format: "  workspace %-12@ with %5.1f   without %5.1f   Δ %4.1f",
                         area.title as NSString, w, wo, w - wo))
        }
        report(String(format: "  → 5 workspace rows: %.1f pt with, %.1f pt without, Δ %.1f pt",
                     workspaceWith, workspaceWithout, workspaceWith - workspaceWithout))

        for area in WorkspaceArea.allCases where !area.analysisModes.isEmpty {
            var with: CGFloat = 0, without: CGFloat = 0
            for mode in area.analysisModes {
                with += height(of: row(title: mode.productTitle,
                                       subtitle: mode.productSubtitle,
                                       symbol: mode.systemImage))
                without += height(of: row(title: mode.productTitle, subtitle: nil,
                                          symbol: mode.systemImage))
            }
            report(String(
                format: "  → %@ task rows (%d): %.1f pt with, %.1f pt without, Δ %.1f pt",
                area.title as NSString, area.analysisModes.count,
                with, without, with - without
            ))
        }
    }

    /// How much of the sidebar's vertical budget is spent on text that never
    /// changes and never stands down, versus everything else.
    func testMeasureStandaloneCaptionBlocks() throws {
        report("\n=== standalone caption blocks (292pt column) ===")
        let blocks: [(String, String)] = [
            ("Detector → real space",
             "Drag the detector on the diffraction pane; the real-space image updates live."),
            ("Strain basis",
             "The g₁ / g₂ pair every position is indexed against."),
            ("DPC offsets", "Detector x/y offsets in calibrated pixels."),
            ("Reconstruct intro",
             "Start with a calibrated preview and alignment. Open single-slice ptychography only when you need iterative object/probe recovery."),
            ("Pattern stats",
             "One pass over the cube; also computed by origin calibration."),
            ("Ptycho requirements",
             "Requires a calibrated origin, R–Q rotation, Q/R pixel sizes, and accelerating voltage. Missing values are rejected rather than guessed."),
        ]
        var total: CGFloat = 0
        for (name, text) in blocks {
            let h = height(of: Text(text).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true))
            total += h
            report(String(format: "  %-24@ %5.1f pt   %@", name as NSString, h,
                         String(text.prefix(40)) as NSString))
        }
        report(String(format: "  → %d always-on explanatory blocks: %.1f pt total",
                     blocks.count, total))
    }

    // MARK: - 3. Where the guidance already exists on demand

    /// Nothing is lost by demoting a visible caption if the same string is
    /// already reachable. This records which surfaces already carry it.
    func testRecordExistingOnDemandChannels() throws {
        report("\n=== guidance already reachable without the visible caption ===")
        for area in WorkspaceArea.allCases {
            report("  workspace.\(area.rawValue): accessibilityHint = \"\(area.subtitle)\"")
        }
        for mode in AnalysisMode.allCases {
            report("  task.\(mode.id): accessibilityHint = \"\(mode.productSubtitle)\"")
        }
    }
}
