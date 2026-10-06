import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Spectroscopy room's centre column, bound to the window's spectrum image (v5.0 WP2 R2): lane V's content over the
/// controller's model. Edits made in the room (the periodic table, the region picker) reach the controller here.
struct SpectroscopyRoomHost: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasSpectrumImage {
            let controller = appState.spectroscopyRoom
            SpectroscopyRoomContent(model: controller.model)
                .onChange(of: controller.model.elements) { controller.elementsChanged() }
                .onChange(of: controller.model.selectedRegion) { controller.regionPicked() }
                .onChange(of: controller.model.quantify) { controller.quantifySettingsChanged() }
                .onChange(of: appState.hasDataset, initial: true) { _, present in controller.setFourDCube(present) }
                .accessibilityIdentifier("spectroscopy.room")
        } else {
            ContentUnavailableView(
                "No spectrum image",
                systemImage: WorkspaceArea.spectroscopy.systemImage,
                description: Text("Open an EDX spectrum image to work in this room.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("spectroscopy.noSpectrumImage")
        }
    }
}

/// The inspector's Settings tab in the Spectroscopy room: the selected step's controls.
struct SpectroscopyInspectorHost: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let step = appState.spectroscopy.selectedStep
        if appState.hasSpectrumImage {
            InspectorSection(step.title) {
                SpectroscopyStepInspector(step: step, model: appState.spectroscopyRoom.model)
            }
            .accessibilityIdentifier("spectroscopy.inspector.\(step.rawValue)")
        } else {
            InspectorSection(step.title) {
                InspectorNote("Open an EDX spectrum image to set up this step.")
            }
        }
    }
}

/// One step's inspector. Separate from the host so a test can lay it out without an `AppState`.
struct SpectroscopyStepInspector: View {
    let step: SpectroscopyStep
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        switch step {
        case .spectrumImage: SpectrumImageInspector(model: model)
        case .elementsAndMaps: ElementsInspector(model: model)
        case .regions: RegionsInspector(model: model)
        case .quantify: QuantifyInspector(model: model)
        case .export: ExportInspector(model: model)
        }
    }
}
