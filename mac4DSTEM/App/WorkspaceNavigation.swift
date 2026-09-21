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

    var showLogPane = false
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
