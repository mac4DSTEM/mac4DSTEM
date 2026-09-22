import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The navigation/selection seam (S22c; `docs/archive/development-process-2026-08-31.md` §7 —
/// one seam per stage, extracted at a green boundary). Owns which workspace
/// and task the user is in and which panes are visible: pure view-state, no
/// science. `AppState` holds it as `navigation` without forwarding
/// properties — the same contract `StrainProductTests` pins for `strain`.
///
/// Orchestration deliberately stays on `AppState` (`selectWorkspace`,
/// `changeMode`): switching tasks touches result bookkeeping and recovery,
/// which are AppState's to coordinate. This type only stores the answer.
@Observable
final class WorkspaceNavigation {
    var workspaceArea: WorkspaceArea = .prepare

    /// Task selection. The recovery hook preserves the exact semantics the
    /// old stored property's `didSet` had on `AppState`: persist the
    /// position whenever the task actually changes, whoever wrote it.
    var analysisMode: AnalysisMode = .virtualDetector {
        didSet { if analysisMode != oldValue { onModeChange?() } }
    }

    /// The process area's share of the centre column (window-design.md §4,
    /// phase 1): 0 hides it, 1 hides the canvas instead — the infobar's two
    /// extremes. `didSet` remembers the last NON-ZERO fraction it saw, so
    /// hiding the area never forgets the height the user dragged it to —
    /// the same shape `PaneSplit`'s `@SceneStorage` fraction protects
    /// against a reset-to-default, here against a reset-to-hidden.
    var processFraction: Double = 0 {
        didSet {
            if processFraction > 0 { lastProcessFraction = processFraction }
        }
    }

    /// What `processFraction` restores to when the process area re-opens.
    /// `LayoutPolicy.processAreaIdealFraction` (UI/) is a same-module,
    /// same-app-target reference, not a package import (`docs/architecture.md`:
    /// `App/` and `UI/` are one compiled unit; only `Session/`/`Core/` are
    /// the enforced package boundary) — so this reads the owner's "default
    /// ideal" from the one place it is named rather than repeating 0.3 here.
    var lastProcessFraction: Double = LayoutPolicy.processAreaIdealFraction

    /// The process area's visibility, as the Bool the ⌃⌘L menu item
    /// (`mac4DSTEMApp.swift`) and `NavigationSeamTests` have always driven.
    /// Not stored: `Mirror` (`NavigationSeamTests`) sees stored properties
    /// only, so a computed forwarder is invisible to it by design (the same
    /// limit that test's own doc comment already states). The setter is the
    /// toggle: shutting remembers nothing extra (`processFraction`'s own
    /// `didSet` already keeps `lastProcessFraction` current), opening
    /// restores it.
    var showLogPane: Bool {
        get { processFraction > 0 }
        set {
            processFraction = newValue ? lastProcessFraction : 0
            // Opening the area with no pane shown shows Output — an open,
            // empty area is not a state (owner, 2026-09-22 late, §9.3).
            if newValue, !showsOutputPane, !showsLineagePane { showsOutputPane = true }
        }
    }

    /// The process area's two panes, Xcode's debug area (owner, 2026-09-22
    /// late, §9.3): Output on the left, Lineage on the right, each with its
    /// own toggle at the infobar's right end. Not persisted, like the tab
    /// they replace.
    var showsOutputPane = true
    var showsLineagePane = false

    enum ProcessPane { case output, lineage }

    /// Toggling a pane: hiding the last visible pane closes the area, and
    /// showing a pane while the area is closed opens it — the two buttons
    /// never leave the area open and empty, or a pane chosen but unseen.
    func toggleProcessPane(_ pane: ProcessPane) {
        switch pane {
        case .output: showsOutputPane.toggle()
        case .lineage: showsLineagePane.toggle()
        }
        if !showsOutputPane && !showsLineagePane {
            showLogPane = false
        } else if !showLogPane {
            showLogPane = true
        }
    }

    /// The user's INTENT for each side panel — what the toggles, the menu
    /// items and the scene storage read and write. What is actually on
    /// screen is `navigatorIsVisible` / `inspectorIsVisible` below: intent
    /// AND the width budget. Keeping the two apart is what lets a panel the
    /// window was too narrow for come back by itself when the window widens
    /// (2026-09-22: the first phase-1 look found the inspector closed at
    /// 1100 pt and still closed at 1280, because the collapse had overwritten
    /// the intent).
    var showToolsPane = true
    var showInspectorPane = false

    /// The window's width as `ContentView` last measured it; `.infinity`
    /// until the first layout pass, so nothing collapses before there is a
    /// number to collapse against. Not persisted — it is measured.
    var availableWindowWidth: CGFloat = .infinity

    var navigatorFits: Bool {
        !WindowAnatomyPolicy.collapseNavigator(at: availableWindowWidth)
    }

    var navigatorIsVisible: Bool { showToolsPane && navigatorFits }

    /// The inspector's budget counts the navigator only when the navigator
    /// is actually on screen.
    var inspectorFits: Bool {
        !WindowAnatomyPolicy.collapseInspector(at: availableWindowWidth, navigatorVisible: navigatorIsVisible)
    }

    var inspectorIsVisible: Bool { showInspectorPane && inspectorFits }

    @ObservationIgnored var onModeChange: (() -> Void)?
}
