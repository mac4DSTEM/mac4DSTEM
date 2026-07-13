import SwiftUI

@main
struct mac4DSTEMApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1080, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Dataset…") { appState.requestOpenDataset() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .importExport) {
                Button("Export Result Image…") { appState.exportResultImage() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(appState.resultImage == nil && appState.resultRGBA == nil)
                Button("Export Diffraction Pattern…") { appState.exportDiffractionImage() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(appState.displayedPattern == nil)
                Button("Preprocess & Export DataCube…") {
                    appState.requestPreprocessingExport()
                }
                .disabled(!appState.hasDataset || appState.isBusy)
                Divider()
                Button("Save Current Result to Session Sidecar") {
                    appState.saveCurrentResultToSessionSidecar()
                }
                .disabled((appState.resultImage == nil && appState.resultRGBA == nil)
                          || appState.isBusy)
                Button("Save Calibration to Session Sidecar") {
                    appState.saveCalibrationToSessionSidecar()
                }
                .disabled(!appState.hasDataset || appState.isBusy)
            }
            CommandGroup(replacing: .sidebar) {
                Button(appState.showToolsPane ? "Hide Tools" : "Show Tools") {
                    appState.showToolsPane.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(appState.showInspectorPane ? "Hide Inspector" : "Show Inspector") {
                    appState.showInspectorPane.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .control])
                Button(appState.showLogPane ? "Hide Output" : "Show Output") {
                    appState.showLogPane.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
            }
        }
    }
}
