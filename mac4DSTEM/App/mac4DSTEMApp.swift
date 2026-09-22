import SwiftUI
import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Finder integration stays in App/; the window and its controls stay SwiftUI.
@MainActor enum DatasetLocationActions {
    static func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

extension AppAppearance {
    /// The one place this maps to SwiftUI: `Session/AppPreferences.swift`
    /// declares the enum but imports no SwiftUI (`docs/architecture.md`:
    /// "Session/ … no SwiftUI"), so the mapping lives here, in the one file
    /// that applies it (`DatasetWindow.body`, below). `nil` for `.system`
    /// lets the OS decide, exactly as if `.preferredColorScheme` were never
    /// called — a pure function, `AppPreferencesTests` pins all three cases.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Owns one state graph per window. Keeping this below WindowGroup (rather
/// than on App) prevents a second dataset window from replacing the first
/// window's reader, calibration, cancellation token, or results.
private struct DatasetWindow: View {
    let preferences: AppPreferences
    let recents: RecentDatasets
    @State private var appState: AppState
    @State private var loadedLaunchFixture = false

    /// `preferences` is handed in (not `AppPreferences()` as a default, the
    /// `materialsProject`/`sessionSidecar` shape) because it must be the
    /// SAME instance the app's `Settings` scene edits — a `didSet` on a
    /// second instance backed by the same `UserDefaults` domain would still
    /// read the right values, but would never observe THIS window's live
    /// changes while Settings is open, which is the whole point of
    /// `@Observable` here. See `AppState.preferences`'s own doc for why
    /// `AppState` needs it at all rather than reading it only from views.
    init(preferences: AppPreferences, recents: RecentDatasets) {
        self.preferences = preferences
        self.recents = recents
        _appState = State(initialValue: AppState(preferences: preferences, recents: recents))
    }

    var body: some View {
        ContentView()
            .environment(appState)
            .environment(preferences)
            .environment(recents)
            .preferredColorScheme(preferences.appearance.colorScheme)
        .focusedSceneValue(\.appState, appState)
        // Info.plist has declared CFBundleDocumentTypes since 2026-09-09, which
        // put mac4DSTEM in Finder's "Open With" — but nothing received the URL,
        // so a double-click launched the app to an empty window. This is the
        // handler that declaration always needed. `openFile` refuses a second
        // load while one is in flight, so a double-click during a load is
        // declined with a reason rather than reaching HDF5 twice.
        // UNVERIFIED ON SCREEN: added 2026-09-11, not yet driven from Finder.
        .onOpenURL { appState.openFile(url: $0) }
        .frame(minWidth: LayoutPolicy.datasetWindowMinimumSize.width,
               minHeight: LayoutPolicy.datasetWindowMinimumSize.height)
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
            // Disabled while this window is loading, and never while the other
            // window might be. A second window gets its own AppState and so its
            // own H5Reader over the one process-wide, NON-THREAD-SAFE libhdf5
            // (`_H5E_stack_g` is a plain global; see `openFile`). This is the
            // cheap half of that defect — it removes the advertised gesture
            // that reaches it fastest, and does not make concurrent HDF5 safe.
            // The real fix is a single actor owning the library handle
            // (`docs/open-items.md`, 2026-09-11).
            Button("New Dataset Window") { openWindow(id: "dataset") }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState?.datasetSession.isLoading ?? false)
            Button("Open Dataset…") { appState?.requestOpenDataset() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState == nil || appState?.datasetSession.isLoading == true)
            if let recovery = appState?.recoveryRecord {
                Button("Reopen \(recoveryName(recovery))") { appState?.reopenLastDataset() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Result Image…") { appState?.exportResultImage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState?.resultPresentation.resultImage == nil
                          && appState?.resultPresentation.resultRGBA == nil)
            Button("Export Diffraction Pattern…") { appState?.exportDiffractionImage() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(appState?.displayedPattern == nil)
            Button("Preprocess & Export DataCube…") { appState?.requestPreprocessingExport() }
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
            Button(appState?.navigation.showLogPane == true ? "Hide Bottom Pane" : "Show Bottom Pane") {
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
        CommandMenu("Dataset") {
            Button("Save Current Result to Session Sidecar") {
                appState?.saveCurrentResultToSessionSidecar()
            }
            .disabled((appState?.resultPresentation.resultImage == nil
                       && appState?.resultPresentation.resultRGBA == nil)
                      || appState?.isBusy == true
                      || appState?.gates.mayWriteSidecar != true)
            Button("Save Calibration to Session Sidecar") {
                appState?.saveCalibrationToSessionSidecar()
            }
            .disabled(appState?.hasDataset != true
                      || appState?.isBusy == true
                      || appState?.gates.mayWriteSidecar != true)
            Divider()
            Button("Change Session Sidecar…") {
                appState?.saveSessionSidecarAs()
            }
            .disabled(appState?.hasDataset != true
                      || appState?.isBusy == true)
            Button("Ignore Session Sidecar…") {
                appState?.reopenIgnoringSessionSidecar()
            }
            .disabled(appState?.hasDataset != true || appState?.isBusy == true)
            if let controls = appState?.selectedSavedControlRehydration {
                Divider()
                Button("Apply Saved Controls") {
                    appState?.applySelectedSavedControls()
                }
                .disabled(appState?.isBusy == true)
                .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
            }
        }
        CommandMenu("Workspace") {
            workspaceCommand(.prepare, key: "1")
            workspaceCommand(.image, key: "2")
            workspaceCommand(.map, key: "3")
            workspaceCommand(.reconstruct, key: "4")
            workspaceCommand(.aiAnalysis, key: "5")
            // Results moves to 6. The owner accepted this when he chose the
            // sixth room (docs/decisions.md, 2026-09-11): the rooms are ordered
            // by the pipeline, and Results is last.
            workspaceCommand(.results, key: "6")
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
    // ONE instance for the whole process, shared by every dataset window and
    // the Settings scene — `UserDefaults` would make a second instance read
    // the same values, but only this one is `@Observable`-linked to what
    // Settings edits live (`DatasetWindow.init`'s doc explains why that
    // matters). Session S21, `ROADMAP.md` "Settings window, Xcode-style
    // sidebar".
    @State private var preferences = AppPreferences()
    @State private var recents = RecentDatasets()

    var body: some Scene {
        WindowGroup("mac4DSTEM", id: "dataset") {
            DatasetWindow(preferences: preferences, recents: recents)
        }
            .defaultSize(width: LayoutPolicy.datasetWindowIdealSize.width,
                         height: LayoutPolicy.datasetWindowIdealSize.height)
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands { DatasetCommands() }
        // Session S5 opened this as one `Form` section; S21 grew it into a
        // sidebared `NavigationSplitView` (`UI/SettingsWindow.swift`), whose
        // Materials Project section is that original view, moved rather than
        // rewritten (see its own header).
        Settings {
            SettingsWindow()
                .environment(preferences)
                .environment(recents)
        }
    }
}
