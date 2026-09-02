import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// S22d: `NavigationSplitView` restores a persisted sidebar width even when
/// it is narrower than the declared 250pt minimum — the standing Track B row
/// observed a restore at 144pt, which degrades the Calibration section to
/// "Ori… Missing". The SwiftUI declaration is advisory during AppKit state
/// restoration, so this clamps once from the AppKit side after the window is
/// up.
enum SplitViewWidthClamp {
    static let sidebarMinimum: CGFloat = 250
    static let sidebarIdeal: CGFloat = 292

    static let sidebarMaximum: CGFloat = 340

    /// Finds the window's outermost column split (the widest vertical
    /// `NSSplitView` — the panes' own splitter is narrower because it
    /// excludes the sidebar) and, if the sidebar pane restored narrower than
    /// the minimum while visible, moves the divider back to the ideal width.
    /// A collapsed sidebar (width 0) is a user choice and is left alone.
    /// Returns the sidebar width after clamping, nil when no split exists.
    ///
    /// S22 feedback (2026-09-01): the SwiftUI width declaration is not
    /// reliably enforced against user drags either — the owner reached
    /// ~625pt on the pre-S22 build and ~750pt/~175pt after — so this also
    /// pins the AppKit `NSSplitViewItem` thickness bounds, which AppKit DOES
    /// enforce live during a drag.
    @discardableResult
    static func enforceSidebarMinimum(in window: NSWindow) -> CGFloat? {
        if let svc = splitViewController(under: window.contentViewController),
           let sidebarItem = svc.splitViewItems.first {
            sidebarItem.minimumThickness = sidebarMinimum
            sidebarItem.maximumThickness = sidebarMaximum
        }
        guard let split = outermostColumnSplit(in: window.contentView),
              let sidebar = split.arrangedSubviews.first else { return nil }
        let width = sidebar.frame.width
        if width > 0, width < sidebarMinimum {
            split.setPosition(sidebarIdeal, ofDividerAt: 0)
            split.layoutSubtreeIfNeeded()
        } else if width > sidebarMaximum {
            split.setPosition(sidebarMaximum, ofDividerAt: 0)
            split.layoutSubtreeIfNeeded()
        }
        return split.arrangedSubviews.first?.frame.width
    }

    private static func splitViewController(under vc: NSViewController?) -> NSSplitViewController? {
        guard let vc else { return nil }
        if let svc = vc as? NSSplitViewController { return svc }
        for child in vc.children {
            if let svc = splitViewController(under: child) { return svc }
        }
        return nil
    }

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
}
