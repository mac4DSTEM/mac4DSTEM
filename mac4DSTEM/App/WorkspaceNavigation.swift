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
        set { processFraction = newValue ? lastProcessFraction : 0 }
    }

    var showToolsPane = true
    var showInspectorPane = false

    /// Which tab the bottom workspace shows (ADR 034, owner 2026-09-21).
    /// Defaults to Output — the rolling log a session has always opened to.
    var bottomWorkspaceTab: BottomWorkspaceTab = .output

    @ObservationIgnored var onModeChange: (() -> Void)?
}

/// The bottom workspace's three rooms: the rolling log, the live operation
/// monitor, and the read-only record of what produced the product on screen.
/// `Codable` so a future scene-restore can carry it the way `WorkspaceArea`
/// does; today it is a plain `WorkspaceNavigation` property, not persisted.
enum BottomWorkspaceTab: String, CaseIterable, Codable {
    case output
    case run
    case lineage
}
