import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The navigation/selection seam (S22c; `../_archive/mac4DSTEM/docs/archive/development-process-2026-08-31.md` §7).
/// Owns which workspace and task the user is in and which panes are
/// visible: pure view-state, no science. `AppState` holds it as
/// `navigation` without forwarding properties — the same contract
/// `StrainProductTests` pins for `strain`.
///
/// The panes (the process area and its fraction, the sidebar and inspector intent, the width collapse) are ShellLayout's
/// `PanelNavigation` (suite task 8, MacEMUI), held as `panels`; the room and the task are this app's.
///
/// Orchestration stays on `AppState` (`selectWorkspace`, `changeMode`):
/// switching tasks touches result bookkeeping and recovery, which are
/// AppState's to coordinate. This type only stores the answer.
@Observable
final class WorkspaceNavigation {
    var workspaceArea: WorkspaceArea = .prepare

    /// Task selection. The recovery hook preserves the exact semantics the
    /// old stored property's `didSet` had on `AppState`: persist the
    /// position whenever the task actually changes, whoever wrote it.
    var analysisMode: AnalysisMode = .virtualDetector {
        didSet { if analysisMode != oldValue { onModeChange?() } }
    }

    /// The panes: the process area (Output, Lineage), the sidebar and the inspector.
    let panels = PanelNavigation()

    @ObservationIgnored var onModeChange: (() -> Void)?
}
