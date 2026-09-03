import AppKit
import DSTEMCore
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// Presentation contract rule 3, the half that IS measurable in the NSView
/// tree: the two side columns are AppKit sidebar and inspector items, which
/// put the system material (Liquid Glass on macOS 26) behind the hosted
/// content — and nothing the column hosts may draw an opaque ground over it.
/// Owner finding (d), 2026-09-03: the toolbar had glass, the columns did not.
@MainActor
final class ColumnMaterialTests: XCTestCase {

    private func pump(_ seconds: TimeInterval = 0.45) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeWindow(_ appState: AppState, calibrated: Bool = true) async -> NSWindow {
        SplitViewPolicy.autosaveEnabled = false
        await appState.openDemoFixture(calibrated: calibrated)
        appState.navigation.showInspectorPane = true
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

    // MARK: - Tree description (the Gate D probe, kept: it is the failure message)

    private func line(_ v: NSView, depth: Int) -> String {
        var s = String(repeating: "  ", count: depth) + String(describing: type(of: v))
        s += String(format: " %.0f×%.0f", v.frame.width, v.frame.height)
        s += v.isOpaque ? " OPAQUE" : ""
        if v.wantsLayer, let bg = v.layer?.backgroundColor, bg.alpha > 0 { s += " layerBG(α\(bg.alpha))" }
        if let scroll = v as? NSScrollView {
            s += " drawsBackground=\(scroll.drawsBackground) bg=\(scroll.backgroundColor.description)"
        }
        if let table = v as? NSTableView {
            s += " tableBG=\(table.backgroundColor.description) resolvedα=\(resolvedAlpha(table.backgroundColor, in: table))"
        }
        if let effect = v as? NSVisualEffectView {
            s += " EFFECT material=\(effect.material.rawValue) blend=\(effect.blendingMode.rawValue) state=\(effect.state.rawValue)"
        }
        if let box = v as? NSBox {
            s += " box transparent=\(box.isTransparent) fill=\(box.fillColor.description)"
        }
        return s
    }

    private func resolvedAlpha(_ color: NSColor, in view: NSView) -> CGFloat {
        var alpha: CGFloat = -1
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            alpha = color.usingColorSpace(.sRGB)?.alphaComponent ?? -1
        }
        return alpha
    }

    private func describeSubtree(_ v: NSView, depth: Int = 0, into out: inout [String]) {
        out.append(line(v, depth: depth))
        for sub in v.subviews { describeSubtree(sub, depth: depth + 1, into: &out) }
    }

    private func describeAncestors(_ v: NSView, upTo stop: NSView, into out: inout [String]) {
        var chain: [NSView] = []
        var cursor: NSView? = v
        while let c = cursor, c !== stop { chain.append(c); cursor = c.superview }
        if let c = cursor { chain.append(c) }
        for (i, a) in chain.reversed().enumerated() { out.append(line(a, depth: i)) }
    }

    private func firstTable(_ v: NSView) -> NSTableView? {
        if let t = v as? NSTableView { return t }
        for sub in v.subviews { if let t = firstTable(sub) { return t } }
        return nil
    }

    private func effectViews(_ v: NSView) -> [NSView] {
        var found: [NSView] = []
        if v is NSVisualEffectView || String(describing: type(of: v)).contains("GlassEffectView") { found.append(v) }
        for sub in v.subviews { found += effectViews(sub) }
        return found
    }

    /// The pixel a view draws at a point of its own bounds with nothing of
    /// its subviews there: the ground it paints, or (alpha 0) none.
    private func groundPixel(_ view: NSView, at point: NSPoint) -> String {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return "no rep" }
        view.cacheDisplay(in: bounds, to: rep)
        // Bitmap rows are top-down; a flipped view's y already is.
        let px = Int(point.x * CGFloat(rep.pixelsWide) / bounds.width)
        let py = Int((view.isFlipped ? point.y : bounds.height - point.y) * CGFloat(rep.pixelsHigh) / bounds.height)
        guard let c = rep.colorAt(x: min(max(0, px), rep.pixelsWide - 1), y: min(max(0, py), rep.pixelsHigh - 1)) else { return "no pixel" }
        return String(format: "rgba(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print(text)
    }

    /// `MAC4DSTEM_HOLD_SECONDS`: keep the hosted window on screen, active, so
    /// a shell with a Screen Recording grant can `screencapture -l` it — the
    /// only way to see the composited columns (own-window capture APIs need
    /// the same grant). How the Gate D captures of 2026-09-03 were taken.
    private func holdForCapture(_ window: NSWindow) {
        guard let s = ProcessInfo.processInfo.environment["MAC4DSTEM_HOLD_SECONDS"], let t = TimeInterval(s) else { return }
        window.title = "mac4DSTEM hosted probe"
        // An inactive window draws its sidebar material flat by design.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pump(t)
    }

    /// Each side column: a system material behind it, nothing opaque hosted
    /// over it. The probe's tree description is the failure message, so a red
    /// run says which view painted the ground.
    func testTheSideColumnsLeaveTheirMaterialVisible() async throws {
        let appState = AppState()
        let window = await makeWindow(appState)
        defer { window.orderOut(nil) }
        let controller = try XCTUnwrap(SplitViewPolicy.controller(in: window))
        let split = controller.splitView
        pump(0.6)
        holdForCapture(window)

        for (name, host) in [("sidebar", controller.sidebarHost), ("inspector", controller.inspectorHost)] {
            var report: [String] = ["== \(name): ancestors up to the split view"]
            describeAncestors(host.view, upTo: split, into: &report)
            report.append("== \(name): hosted subtree")
            describeSubtree(host.view, into: &report)

            // Ground pixels: the host view, the scroll view and the table,
            // each sampled in its own left gutter (outside every cell) near
            // the bottom, where the sidebar document has no row.
            report.append("== \(name): ground pixels (left gutter, 4pt from the bottom)")
            let table = firstTable(host.view)
            var probes: [(String, NSView)] = [("host", host.view)]
            if let scroll = table?.enclosingScrollView { probes.append(("scrollView", scroll)) }
            if let table { probes.append(("table", table)) }
            for (label, v) in probes {
                let p = NSPoint(x: 4, y: v.isFlipped ? v.bounds.height - 4 : 4)
                report.append("  \(label): \(groundPixel(v, at: p))")
            }
            let text = report.joined(separator: "\n")
            attach(text, name: "column-material-\(name).txt")

            var ancestorsHaveMaterial = false
            var cursor: NSView? = host.view.superview
            while let c = cursor, c !== split {
                if !effectViews(c).filter({ $0 === c }).isEmpty { ancestorsHaveMaterial = true }
                cursor = c.superview
            }
            XCTAssertTrue(
                ancestorsHaveMaterial,
                "\(name): no material view between the hosted view and the split view — AppKit gave this column no material\n\(text)"
            )
            let hostedEffects = effectViews(host.view)
            XCTAssertTrue(
                hostedEffects.isEmpty,
                "\(name): hosted content brings \(hostedEffects.count) material view(s) of its own over the column's: "
                    + hostedEffects.map { String(describing: type(of: $0)) }.joined(separator: ", ") + "\n\(text)"
            )
            if let table {
                XCTAssertEqual(
                    resolvedAlpha(table.backgroundColor, in: table), 0, accuracy: 0.01,
                    "\(name): the hosted table paints \(table.backgroundColor) over the column's material\n\(text)"
                )
            }
        }
    }

    // MARK: - Both inspectors as grouped Forms (UI rework step 3)

    // Copied locally from `SidebarLayoutTests` rather than shared: each
    // hosted-window test file keeps its own probes so a change to one
    // column's gate cannot silently loosen the other's.

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let s = view as? NSScrollView { found.append(s) }
        for sub in view.subviews { found += scrollViews(sub) }
        return found
    }

    private func controls(_ view: NSView) -> [NSControl] {
        var found: [NSControl] = []
        if let c = view as? NSControl, !c.isHiddenOrHasHiddenAncestor, c.frame.width > 0 { found.append(c) }
        for sub in view.subviews { found += controls(sub) }
        return found
    }

    /// Off-screen render of a view (no Screen Recording grant needed; Metal
    /// panes come out empty) attached to the result bundle when
    /// `MAC4DSTEM_CAPTURE` is set — the review images for a UI step.
    private func attachPNG(_ view: NSView, name: String) {
        guard ProcessInfo.processInfo.environment["MAC4DSTEM_CAPTURE"] != nil else { return }
        view.layoutSubtreeIfNeeded()
        pump(0.5)
        view.display()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The inspector column's divider is index 1 (sidebar | workspace |
    /// inspector); its position is measured from the trailing edge.
    private func pinInspectorWidth(_ window: NSWindow, to width: CGFloat) {
        guard let split = SplitViewPolicy.controller(in: window)?.splitView else { return }
        split.autosaveName = ""
        split.setPosition(split.frame.width - width, ofDividerAt: 1)
        pump(0.4)
    }

    /// Contract rule 5 applied to `DatasetInspector` and `ProductInspector`
    /// (step 3): each survives the inspector column's whole range — no
    /// horizontal overflow of the document, and every AppKit control inside
    /// the column at its minimum, ideal and maximum width. Calibrated and
    /// not, dataset and product.
    func testEveryInspectorSurvivesItsWholeColumnRange() async throws {
        let band = SplitViewPolicy.inspector
        for calibrated in [true, false] {
            let appState = AppState()
            let window = await makeWindow(appState, calibrated: calibrated)
            defer { window.orderOut(nil) }

            func assertColumnFits(_ stage: String, width: CGFloat) throws {
                let controller = try XCTUnwrap(SplitViewPolicy.controller(in: window))
                let column = controller.inspectorHost.view
                let scroll = try XCTUnwrap(scrollViews(column).first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertEqual(
                    column.bounds.width, width, accuracy: 2,
                    "\(stage): the column is not at the requested width"
                )
                // SwiftUI can lay the hosted form out wider than its column
                // and hang it past the edge (measured 283pt in a 250pt
                // sidebar column, 2026-09-03): the scroll view and its
                // document must both fit the column.
                XCTAssertLessThanOrEqual(
                    scroll.frame.width, column.bounds.width + 1,
                    "\(stage): the inspector's scroll view is \(scroll.frame.width)pt wide in a \(column.bounds.width)pt column — a control inside forces the width"
                )
                XCTAssertLessThanOrEqual(
                    document.frame.width, scroll.contentSize.width + 1,
                    "\(stage): the inspector document is \(document.frame.width)pt wide in a \(scroll.contentSize.width)pt column"
                )
                for control in controls(document) {
                    let r = control.convert(control.bounds, to: scroll)
                    let title = (control as? NSButton)?.title ?? (control as? NSTextField)?.stringValue ?? ""
                    XCTAssertTrue(
                        r.minX >= -1 && r.maxX <= scroll.bounds.width + 1,
                        "\(stage): \(type(of: control)) '\(title)' spans x \(Int(r.minX))–\(Int(r.maxX)) in a \(Int(scroll.bounds.width))pt column"
                    )
                    if control is NSSlider {
                        XCTAssertGreaterThanOrEqual(r.width, 80, "\(stage): a slider is \(Int(r.width))pt wide — collapsed to its knob")
                    }
                }
                attachPNG(document, name: stage)
            }

            // The dataset inspector is shown on any live workspace.
            appState.selectWorkspace(.prepare)
            for width in [band.minimum, band.ideal, band.maximum] {
                pinInspectorWidth(window, to: width)
                pump(0.5)
                try assertColumnFits("inspector-dataset-\(calibrated ? "ready" : "blocked")-\(Int(width))", width: width)
            }

            // The product inspector takes over once a product is displayed
            // and Results claims the focus ring (`FocusedPane.result`).
            appState.publishProduct(
                kind: "virtual_annulus", displayName: "Virtual detector · Annulus", valueUnits: "intensity",
                payload: .scalar(FloatImage(width: 200, height: 50, pixels: [Float](repeating: 0.5, count: 200 * 50))))
            appState.selectWorkspace(.results)
            pump(0.6)
            for width in [band.minimum, band.ideal, band.maximum] {
                pinInspectorWidth(window, to: width)
                pump(0.5)
                try assertColumnFits("inspector-product-\(calibrated ? "ready" : "blocked")-\(Int(width))", width: width)
            }
        }
    }
}
