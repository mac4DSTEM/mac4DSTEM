import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The window's column contract, in one place (owner direction 2026-09-03:
/// "like Xcode"). Both side columns behave the same — thickness bounds
/// AppKit enforces live during a drag, collapse when dragged past the
/// minimum, a restored width validated against the minimum — and the data
/// pane keeps its floor as a split item's thickness, not a view frame. A
/// narrowing window squeezes the inspector first, then the sidebar, then the
/// data pane (holding priorities).
///
/// What SwiftUI provides and what it does not (measured in a hosted window,
/// 2026-09-03): `NavigationSplitView` is an `NSSplitViewController` whose
/// sidebar item can collapse but carries a 140pt minimum and no maximum
/// whatever `navigationSplitViewColumnWidth` declares; `.inspector` is a
/// second split controller nested in the detail, and there SwiftUI does map
/// `inspectorColumnWidth` onto the item's bounds and lets it collapse; both
/// report a drag-collapse back to the app's navigation flags. Neither floors
/// the data pane. This type adds exactly what is missing.
///
/// History: the SwiftUI declarations alone failed twice (a 144pt restore on
/// 2026-08-06, a 750pt drag on 2026-09-01), so S22d added an AppKit clamp for
/// the sidebar; a hard `.frame(minWidth:)` belt on the sidebar root was
/// removed 2026-09-03 after a constraint-loop crash report (`open-items.md`,
/// Gate D open). This is that clamp, for both sides, as the only enforcement.
@MainActor
enum SplitViewPolicy {
    struct Band: Equatable {
        let minimum: CGFloat
        let ideal: CGFloat
        let maximum: CGFloat
    }

    static let sidebar = Band(minimum: 250, ideal: 292, maximum: 600)
    static let inspector = Band(minimum: 260, ideal: 320, maximum: 600)
    /// The data pane's floor (the 2026-08-05 clipped-edges class).
    static let detailMinimum: CGFloat = 360

    struct Report {
        let sidebar: NSSplitViewItem
        /// The outer controller's trailing item: the detail plus, when shown, the inspector.
        let outerDetail: NSSplitViewItem
        /// The inspector controller's items, present only while the inspector is shown.
        let detail: NSSplitViewItem?
        let inspector: NSSplitViewItem?
        let sidebarWidth: CGFloat?
        let inspectorWidth: CGFloat?
    }

    /// Idempotent. Call once the window is up (after AppKit state
    /// restoration) and again whenever the inspector appears, since its split
    /// controller exists only while it is presented. A column collapsed by a
    /// drag already reaches the navigation flags through SwiftUI's own
    /// bindings (measured 2026-09-03: a sync written here changed nothing),
    /// so the policy adds no observer.
    @discardableResult
    static func apply(to window: NSWindow) -> Report? {
        guard let outer = outermostColumnSplit(in: window.contentView),
              let outerController = outer.delegate as? NSSplitViewController,
              outerController.splitViewItems.count == 2 else { return nil }
        let sidebarItem = outerController.splitViewItems[0]
        let outerDetail = outerController.splitViewItems[1]
        sidebarItem.minimumThickness = sidebar.minimum
        sidebarItem.maximumThickness = sidebar.maximum
        sidebarItem.canCollapse = true

        let inspectorSplit = inspectorColumnSplit(in: outer)
        let inspectorController = inspectorSplit?.delegate as? NSSplitViewController
        let detailItem = inspectorController?.splitViewItems.first
        let inspectorItem = inspectorController.flatMap { $0.splitViewItems.count == 2 ? $0.splitViewItems[1] : nil }
        if let detailItem, let inspectorItem {
            detailItem.minimumThickness = detailMinimum
            // Inside the trailing pair the data pane holds harder than the
            // inspector; between the pair and the sidebar, SwiftUI already
            // lets the pair yield first (sidebar 260 > detail 250).
            detailItem.holdingPriority = NSLayoutConstraint.Priority(inspectorItem.holdingPriority.rawValue + 1)
            inspectorItem.canCollapse = true
        }
        validate(outer, divider: 0, band: sidebar, fromTrailing: false)
        if let inspectorSplit, inspectorItem != nil {
            validate(inspectorSplit, divider: 0, band: inspector, fromTrailing: true)
        }
        return Report(
            sidebar: sidebarItem, outerDetail: outerDetail, detail: detailItem, inspector: inspectorItem,
            sidebarWidth: outer.arrangedSubviews.first?.frame.width,
            inspectorWidth: inspectorItem == nil ? nil : inspectorSplit?.arrangedSubviews.last?.frame.width
        )
    }

    /// A width AppKit restored outside the band is moved back inside it. A
    /// collapsed column (width 0) is a choice and is left alone.
    private static func validate(_ split: NSSplitView, divider: Int, band: Band, fromTrailing: Bool) {
        let views = split.arrangedSubviews
        guard views.count >= 2 else { return }
        let width = (fromTrailing ? views[divider + 1] : views[divider]).frame.width
        guard width > 0 else { return }
        let target: CGFloat
        if width < band.minimum { target = band.ideal }
        else if width > band.maximum { target = band.maximum }
        else { return }
        split.setPosition(fromTrailing ? split.frame.width - target : target, ofDividerAt: divider)
        split.layoutSubtreeIfNeeded()
    }

    /// The window's outermost column split — the widest vertical `NSSplitView`
    /// (the panes' own splitter is narrower because it excludes the sidebar).
    static func outermostColumnSplit(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        var best: NSSplitView?
        func walk(_ v: NSView) {
            if let split = v as? NSSplitView, split.isVertical,
               split.frame.width > (best?.frame.width ?? 0) {
                best = split
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(view)
        return best
    }

    /// The inspector's split: the first vertical split below the outer one
    /// whose delegate is a split controller with a collapsible trailing item.
    /// Absent while the inspector is hidden.
    static func inspectorColumnSplit(in outer: NSSplitView) -> NSSplitView? {
        var found: NSSplitView?
        func walk(_ v: NSView) {
            if found != nil { return }
            if let split = v as? NSSplitView, split !== outer, split.isVertical,
               let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.count == 2, controller.splitViewItems[1].canCollapse {
                found = split; return
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(outer)
        return found
    }
}
