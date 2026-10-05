import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The selected task's controls in the inspector's Settings tab — the one
/// place a (workspace, task) pair picks its room file, so the width budget
/// (`InspectorWidthBudgetTests`) can host exactly what the inspector shows.
///
/// Each room file produces bare `Section`s of its own. Each task's controls
/// get their own `inspectorScope`, so an `InspectorSection` titled "Result" in
/// two tasks remembers its expansion separately rather than sharing one
/// `@SceneStorage` key. Where a workspace holds tasks from two room files
/// (ADR 046: diffraction groups in Imaging, phase mapping in Crystal Maps),
/// the task picks the file.
struct WorkspaceSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let mode = appState.navigation.analysisMode
        switch appState.navigation.workspaceArea {
        case .prepare: PrepareSettings().environment(\.inspectorScope, "settings.prepare")
        case .image:
            if mode == .diffractionGroups {
                DiffractionGroupsSection().environment(\.inspectorScope, "settings.groups")
            } else {
                ImagingSettings().environment(\.inspectorScope, "settings.image")
            }
        case .braggDisks: MapSettings().environment(\.inspectorScope, "settings.map")
        case .map:
            if mode == .phaseMapping {
                PhaseMappingSections().environment(\.inspectorScope, "settings.phaseMapping")
            } else {
                MapSettings().environment(\.inspectorScope, "settings.map")
            }
        case .reconstruct: ReconstructionSettings().environment(\.inspectorScope, "settings.phase")
        // v5.0 WP2: lane V's step inspectors replace the placeholder (R2).
        case .spectroscopy: SpectroscopyInspectorPlaceholder().environment(\.inspectorScope, "settings.spectroscopy")
        case .results: ResultsSettings().environment(\.inspectorScope, "settings.results")
        }
    }
}
