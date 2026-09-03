import AppKit
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The window's column contract, owned by AppKit the way Xcode's is (owner
/// decision 2026-09-03). `NSSplitViewController` holds three items — a
/// sidebar, the workspace, an inspector — with the bounds, collapse and
/// holding order below; each column's SwiftUI content is hosted with
/// `sizingOptions = []`, so it never imposes a size on the split view. That
/// last point is the whole fix: with SwiftUI's `NavigationSplitView` the
/// column's content held a minimum width the divider was allowed to violate
/// (SwiftUI rewrote the item's minimum to 140 pt on every update), and a
/// drag past it produced an unsatisfiable layout and AppKit's constraint-loop
/// exception (`open-items.md`, Gate D 2026-09-03). Here the divider is the
/// only authority over width; content wraps, scrolls or clips inside it.
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
    /// A narrowing window squeezes the inspector first, then the sidebar,
    /// then the data pane.
    static let inspectorHolding = NSLayoutConstraint.Priority(260)
    static let sidebarHolding = NSLayoutConstraint.Priority(261)
    static let detailHolding = NSLayoutConstraint.Priority(262)
    static let autosaveName = "mac4DSTEM.columns"
    /// The grabbable width of each thin divider, centred on the drawn line
    /// (owner finding (c), 2026-09-03: a 1pt zone put the drag on the focus ring).
    static let dividerGrabWidth: CGFloat = 9
    /// Tests turn this off before they make a window, so no position or
    /// collapse state from an earlier run or test can reach them.
    nonisolated(unsafe) static var autosaveEnabled = true

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

    /// The controller behind the window's column split, for tests.
    static func controller(in window: NSWindow) -> ColumnSplitController? {
        outermostColumnSplit(in: window.contentView)?.delegate as? ColumnSplitController
    }
}

/// The split view with a layout hook: a SwiftUI-hosted controller gets no
/// appearance or layout callbacks, and the autosaved collapse state is
/// restored at the first layout, so the app's flags are reapplied from here.
final class ColumnSplitView: NSSplitView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Three AppKit split items around SwiftUI content. Collapsing by a drag is
/// reported through `onSidebarCollapsed` / `onInspectorCollapsed`; collapsing
/// by the app (the toolbar toggles, the loading card) comes in through
/// `setSidebarVisible` / `setInspectorVisible` and is not reported back.
@MainActor
final class ColumnSplitController: NSSplitViewController {
    let sidebarHost: NSHostingController<AnyView>
    let contentHost: NSHostingController<AnyView>
    let inspectorHost: NSHostingController<AnyView>
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var contentItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!
    var onSidebarCollapsed: ((Bool) -> Void)?
    var onInspectorCollapsed: ((Bool) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var settingProgrammatically = false
    /// The app's flags win over the autosaved collapse state: reapplied once
    /// the view is on screen, after AppKit has restored the split.
    private var wantsSidebarVisible = true
    private var wantsInspectorVisible = false
    /// Each side column's last open width, so a column reopened by its
    /// toggle comes back where it was rather than at its minimum (AppKit
    /// redistributes by holding priority after an expand).
    private var lastSidebarWidth: CGFloat = SplitViewPolicy.sidebar.ideal
    private var lastInspectorWidth: CGFloat = SplitViewPolicy.inspector.ideal

    init(sidebar: AnyView, content: AnyView, inspector: AnyView) {
        sidebarHost = NSHostingController(rootView: sidebar)
        contentHost = NSHostingController(rootView: content)
        inspectorHost = NSHostingController(rootView: inspector)
        super.init(nibName: nil, bundle: nil)
        // The columns decide the width; SwiftUI lays out inside them.
        for host in [sidebarHost, contentHost, inspectorHost] { host.sizingOptions = [] }

        let split = ColumnSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        if SplitViewPolicy.autosaveEnabled { split.autosaveName = SplitViewPolicy.autosaveName }
        splitView = split

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = SplitViewPolicy.sidebar.minimum
        sidebarItem.maximumThickness = SplitViewPolicy.sidebar.maximum
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = SplitViewPolicy.sidebarHolding

        contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = SplitViewPolicy.detailMinimum
        contentItem.holdingPriority = SplitViewPolicy.detailHolding

        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        inspectorItem.minimumThickness = SplitViewPolicy.inspector.minimum
        inspectorItem.maximumThickness = SplitViewPolicy.inspector.maximum
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = SplitViewPolicy.inspectorHolding

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)
        inspectorItem.isCollapsed = true

        observations = [
            sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.settingProgrammatically else { return }
                    self.onSidebarCollapsed?(item.isCollapsed)
                }
            },
            inspectorItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.settingProgrammatically else { return }
                    self.onInspectorCollapsed?(item.isCollapsed)
                }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Owner finding (c), 2026-09-03: a thin divider's grab zone is its 1pt
    /// drawn line by default, so the drag landed on the pane's focus ring.
    /// The delegate decides the effective rect; widen it around the line.
    override func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let slop = (SplitViewPolicy.dividerGrabWidth - drawnRect.width) / 2
        return drawnRect.insetBy(dx: -slop, dy: 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (splitView as? ColumnSplitView)?.onLayout = { [weak self] in
            guard let self else { return }
            // The app's flags win over the autosaved collapse state;
            // `set` is a no-op when they already hold.
            self.set(self.sidebarItem, collapsed: !self.wantsSidebarVisible, animated: false)
            self.set(self.inspectorItem, collapsed: !self.wantsInspectorVisible, animated: false)
            self.rememberOpenWidths()
        }
    }

    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        wantsSidebarVisible = visible
        set(sidebarItem, collapsed: !visible, animated: animated)
    }

    func setInspectorVisible(_ visible: Bool, animated: Bool) {
        wantsInspectorVisible = visible
        set(inspectorItem, collapsed: !visible, animated: animated)
    }

    private func rememberOpenWidths() {
        // Not while a collapse or expand is in flight: the expand's own
        // layout hands the column its minimum before the memory is applied.
        let views = splitView.arrangedSubviews
        guard !settingProgrammatically, views.count == 3 else { return }
        if !sidebarItem.isCollapsed, views[0].frame.width >= SplitViewPolicy.sidebar.minimum {
            lastSidebarWidth = views[0].frame.width
        }
        if !inspectorItem.isCollapsed, views[2].frame.width >= SplitViewPolicy.inspector.minimum {
            lastInspectorWidth = views[2].frame.width
        }
    }

    private func set(_ item: NSSplitViewItem, collapsed: Bool, animated: Bool) {
        guard item.isCollapsed != collapsed else { return }
        rememberOpenWidths()
        let target = item === sidebarItem ? lastSidebarWidth : lastInspectorWidth
        settingProgrammatically = true
        defer { settingProgrammatically = false }
        // Assigned directly: an `animator()` collapse never completes in a
        // hosted window (the reopened column stayed at 0pt, 2026-09-03), and
        // Xcode's own columns snap.
        _ = animated
        item.isCollapsed = collapsed
        guard !collapsed else { return }
        splitView.layoutSubtreeIfNeeded()
        if item === sidebarItem {
            splitView.setPosition(target, ofDividerAt: 0)
        } else if item === inspectorItem {
            splitView.setPosition(splitView.frame.width - target, ofDividerAt: 1)
        }
        splitView.layoutSubtreeIfNeeded()
    }
}

/// The SwiftUI face of `ColumnSplitController`: the three columns as views,
/// the visibility flags as inputs, drag-collapses reported back.
struct WorkspaceColumns: NSViewControllerRepresentable {
    let sidebar: AnyView
    let content: AnyView
    let inspector: AnyView
    let sidebarVisible: Bool
    let inspectorVisible: Bool
    let onSidebarCollapsed: (Bool) -> Void
    let onInspectorCollapsed: (Bool) -> Void

    func makeNSViewController(context: Context) -> ColumnSplitController {
        let controller = ColumnSplitController(sidebar: sidebar, content: content, inspector: inspector)
        controller.onSidebarCollapsed = onSidebarCollapsed
        controller.onInspectorCollapsed = onInspectorCollapsed
        controller.setSidebarVisible(sidebarVisible, animated: false)
        controller.setInspectorVisible(inspectorVisible, animated: false)
        return controller
    }

    /// Take whatever SwiftUI proposes: the split view's own fitting size is
    /// the sum of the column minimums (610pt), and without this the columns
    /// sat in a 610pt strip inside a 1470pt window (measured 2026-09-03).
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: ColumnSplitController, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1080, height: proposal.height ?? 640)
    }

    func updateNSViewController(_ controller: ColumnSplitController, context: Context) {
        controller.sidebarHost.rootView = sidebar
        controller.contentHost.rootView = content
        controller.inspectorHost.rootView = inspector
        controller.onSidebarCollapsed = onSidebarCollapsed
        controller.onInspectorCollapsed = onInspectorCollapsed
        controller.setSidebarVisible(sidebarVisible, animated: true)
        controller.setInspectorVisible(inspectorVisible, animated: true)
    }
}
