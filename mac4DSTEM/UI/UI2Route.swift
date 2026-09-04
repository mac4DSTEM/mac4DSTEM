import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// What the sidebar selects and the detail column shows.
///
/// A workspace with tasks is represented by its selected task — selecting a
/// file, not its folder, is what highlights in Xcode's navigator — and a
/// workspace without tasks (Prepare, Results) is selected in its own right.
/// The route is derived from `WorkspaceNavigation`, never stored beside it:
/// UI2 adds no state to `AppState`.
enum UI2Route: Hashable, Identifiable {
    case workspace(WorkspaceArea)
    case task(AnalysisMode)

    var id: String {
        switch self {
        case .workspace(let area): "workspace.\(area.rawValue)"
        case .task(let mode): "task.\(mode.id)"
        }
    }

    /// The workspace this route lives in, whichever kind it is.
    var area: WorkspaceArea {
        switch self {
        case .workspace(let area): area
        case .task(let mode): mode.workspaceArea
        }
    }

    /// The title the window carries while this route is selected. A task
    /// names itself; a workspace without tasks names the workspace.
    var title: String {
        switch self {
        case .workspace(let area): area.title
        case .task(let mode): mode.productTitle
        }
    }

    var subtitle: String {
        switch self {
        case .workspace(let area): area.subtitle
        case .task(let mode): mode.productSubtitle
        }
    }

    var systemImage: String {
        switch self {
        case .workspace(let area): area.systemImage
        case .task(let mode): mode.systemImage
        }
    }

    /// The route currently selected, read from the navigation seam.
    static func current(_ navigation: WorkspaceNavigation) -> UI2Route {
        let area = navigation.workspaceArea
        return area.analysisModes.isEmpty
            ? .workspace(area)
            : .task(navigation.analysisMode)
    }
}

extension AppState {
    /// The sidebar's selection, as a binding onto the navigation seam.
    ///
    /// Reading and writing go through `selectWorkspace` / `changeMode`,
    /// which is where result bookkeeping and recovery live — this binding
    /// stores nothing of its own.
    var ui2Route: Binding<UI2Route?> {
        Binding(
            get: { UI2Route.current(self.navigation) },
            set: { route in
                switch route {
                case .workspace(let area):
                    self.selectWorkspace(area)
                case .task(let mode):
                    if self.navigation.workspaceArea != mode.workspaceArea {
                        self.selectWorkspace(mode.workspaceArea)
                    }
                    self.changeMode(mode)
                case nil:
                    break
                }
            }
        )
    }

    /// What still has to happen before the selected task may run — the same
    /// list that disables the primary action, so the two can never disagree.
    var ui2UnmetRequirements: [TaskPrerequisite] {
        guard !navigation.workspaceArea.analysisModes.isEmpty else { return [] }
        return ProductWorkflow.prerequisiteItems(
            for: navigation.analysisMode, readiness: productWorkflowReadiness
        ).filter { !$0.isSatisfied }
    }

    /// Non-blocking scientific context for the selected task: it may run, and
    /// this is what its numbers will and will not mean.
    var ui2Guidance: [String] {
        guard !navigation.workspaceArea.analysisModes.isEmpty else { return [] }
        return ProductWorkflow.guidance(
            for: navigation.analysisMode, readiness: productWorkflowReadiness
        )
    }
}
