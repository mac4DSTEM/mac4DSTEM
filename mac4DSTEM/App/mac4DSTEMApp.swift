import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

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
                let uncalibrated = ProcessInfo.processInfo.arguments.contains(
                    "--demo-uncalibrated"
                )
                await appState.openDemoFixture(calibrated: !uncalibrated)
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
            // The way to rename or relocate the companion once a grant exists.
            // Without it the save panel never reappears and a misplaced
            // sidecar is misplaced forever (Track B F1.3i, 2026-08-19). // v2 S4
            Button("Save Session Sidecar As…") {
                appState?.saveSessionSidecarAs()
            }
            .disabled(appState?.hasDataset != true || appState?.isBusy == true)
        }
        CommandGroup(replacing: .sidebar) {
            Button(appState?.navigation.showToolsPane == true ? "Hide Tools" : "Show Tools") {
                appState?.navigation.showToolsPane.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(appState?.navigation.showInspectorPane == true ? "Hide Inspector" : "Show Inspector") {
                appState?.navigation.showInspectorPane.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            Button(appState?.navigation.showLogPane == true ? "Hide Output" : "Show Output") {
                appState?.navigation.showLogPane.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .control])
            .disabled(appState?.hasDataset != true || appState?.navigation.workspaceArea == .results)
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
        appState?.recents.entry(withID: recovery.datasetID)?.displayName
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
