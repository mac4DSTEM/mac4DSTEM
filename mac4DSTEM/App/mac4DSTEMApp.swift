import SwiftUI

private struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

/// Owns one state graph per window. Keeping this below WindowGroup (rather
/// than on App) prevents a second dataset window from replacing the first
/// window's reader, calibration, cancellation token, or results.
private struct DatasetWindow: View {
    @State private var appState = AppState()
    @State private var loadedLaunchFixture = false

    var body: some View {
        ContentView()
            .environment(appState)
            .focusedSceneValue(\.appState, appState)
            .frame(minWidth: 1080, minHeight: 640)
            .task {
                guard !loadedLaunchFixture,
                      ProcessInfo.processInfo.arguments.contains("--demo-fixture") else {
                    return
                }
                loadedLaunchFixture = true
                await appState.openDemoFixture()
            }
    }
}

private struct DatasetCommands: Commands {
    @FocusedValue(\.appState) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Dataset Window") { openWindow(id: "dataset") }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open Dataset…") { appState?.requestOpenDataset() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState == nil)
            if let recovery = appState?.recoveryRecord {
                Button("Reopen \(recoveryName(recovery))") { appState?.reopenLastDataset() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Result Image…") { appState?.exportResultImage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState?.resultImage == nil && appState?.resultRGBA == nil)
            Button("Export Diffraction Pattern…") { appState?.exportDiffractionImage() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(appState?.displayedPattern == nil)
            Button("Preprocess & Export DataCube…") { appState?.requestPreprocessingExport() }
                .disabled(appState?.hasDataset != true || appState?.isBusy == true)
            Divider()
            Button("Save Current Result to Session Sidecar") {
                appState?.saveCurrentResultToSessionSidecar()
            }
            .disabled((appState?.resultImage == nil && appState?.resultRGBA == nil)
                      || appState?.isBusy == true)
            Button("Save Calibration to Session Sidecar") {
                appState?.saveCalibrationToSessionSidecar()
            }
            .disabled(appState?.hasDataset != true || appState?.isBusy == true)
        }
        CommandGroup(replacing: .sidebar) {
            Button(appState?.showToolsPane == true ? "Hide Tools" : "Show Tools") {
                appState?.showToolsPane.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(appState?.showInspectorPane == true ? "Hide Inspector" : "Show Inspector") {
                appState?.showInspectorPane.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            Button(appState?.showLogPane == true ? "Hide Output" : "Show Output") {
                appState?.showLogPane.toggle()
            }
                .keyboardShortcut("l", modifiers: [.command, .control])
        }
        CommandMenu("Analysis") {
            Button("Run Current Task") {
                if let appState { Task { await appState.runPrimaryWorkspaceTask() } }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState?.hasDataset != true || appState?.isBusy == true)
            Button("Cancel Analysis") { appState?.cancelActiveOperation() }
                .keyboardShortcut(.cancelAction)
                .disabled(appState?.canCancelActiveOperation != true)
        }
        CommandMenu("Workspace") {
            workspaceCommand(.prepare, key: "1")
            workspaceCommand(.image, key: "2")
            workspaceCommand(.map, key: "3")
            workspaceCommand(.reconstruct, key: "4")
            workspaceCommand(.results, key: "5")
        }
    }

    private func recoveryName(_ recovery: DatasetRecoveryRecord) -> String {
        appState?.recentDatasets.first(where: { $0.id == recovery.datasetID })?.displayName
            ?? "Last Dataset"
    }

    private func workspaceCommand(_ area: WorkspaceArea, key: KeyEquivalent) -> some View {
        Button("Go to \(area.title)") { appState?.selectWorkspace(area) }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(appState?.hasDataset != true)
    }
}

@main
struct mac4DSTEMApp: App {
    var body: some Scene {
        WindowGroup("mac4DSTEM", id: "dataset") { DatasetWindow() }
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands { DatasetCommands() }
    }
}
