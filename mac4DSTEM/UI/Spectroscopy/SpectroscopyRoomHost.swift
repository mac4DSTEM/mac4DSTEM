import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Spectroscopy room's centre column, bound to the window's spectrum image (v5.0 WP2 R2): the room's content over the
/// controller's model. Edits made in the room (the periodic table, the region picker, the map mode) reach the controller here.
struct SpectroscopyRoomHost: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasSpectrumImage {
            let controller = appState.spectroscopyRoom
            SpectroscopyRoomContent(model: controller.model)
                .onChange(of: controller.model.elements) { controller.elementsChanged() }
                .onChange(of: controller.model.selectedRegion) { controller.regionPicked() }
                .onChange(of: controller.model.quantify) { controller.quantifySettingsChanged() }
                .onChange(of: controller.model.mapMode) { controller.refresh() }
                .onChange(of: controller.model.compare) { controller.refresh() }
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

/// The inspector's Settings tab in the Spectroscopy room: the room's sections, or one line when there is no image.
struct SpectroscopyInspectorHost: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasSpectrumImage {
            SpectroscopyInspectorSections(model: appState.spectroscopyRoom.model)
                .accessibilityIdentifier("spectroscopy.inspector")
        } else {
            InspectorSection("Elements") {
                InspectorNote("Open an EDX spectrum image to set up the room.")
            }
        }
    }
}
