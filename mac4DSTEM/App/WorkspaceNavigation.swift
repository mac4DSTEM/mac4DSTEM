import SwiftUI
import DSTEMCore
import DSTEMSession

/// The navigation/selection seam (S22c; `docs/development-process.md` §7 —
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

    @ObservationIgnored var onModeChange: (() -> Void)?
}
