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
    /// A File-menu action asked for while no window was focused (`MenuActionRelay`).
    let menuRelay: MenuActionRelay
    /// The window's `AppState`, made on the first read in `body` and never again (`LazyAppState`): this view's `init`
    /// runs every time the scene's content is evaluated, and used to build a whole state graph each time to keep one.
    @State private var holder: LazyAppState
    private var appState: AppState { holder.state }
    @State private var loadedLaunchFixture = false
    /// A file is being dragged over the window (File > drop-to-open).
    @State private var dropTargeted = false
    @Environment(\.openWindow) private var openWindow

    /// `preferences` is handed in (not `AppPreferences()` as a default, the
    /// `materialsProject`/`sessionSidecar` shape) because it must be the
    /// SAME instance the app's `Settings` scene edits — a `didSet` on a
    /// second instance backed by the same `UserDefaults` domain would still
    /// read the right values, but would never observe THIS window's live
    /// changes while Settings is open, which is the whole point of
    /// `@Observable` here. See `AppState.preferences`'s own doc for why
    /// `AppState` needs it at all rather than reading it only from views.
    init(preferences: AppPreferences, recents: RecentDatasets, menuRelay: MenuActionRelay) {
        self.preferences = preferences
        self.recents = recents
        self.menuRelay = menuRelay
        _holder = State(initialValue: LazyAppState { AppState(preferences: preferences, recents: recents) })
    }

    var body: some View {
        ContentView()
            .environment(appState)
            .environment(preferences)
            .environment(recents)
            .preferredColorScheme(preferences.appearance.colorScheme)
            // Drop a dataset on the window to open it (UI audit 2026-10-14, F; HIG, Drag and drop). SwiftUI's own
            // `dropDestination`: the open is `openFile`, the one funnel every other door uses, so a drop meets
            // the same refusals (a load in flight, a sidecar save, a dataset another window holds).
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = DropToOpen.dataset(in: urls) else { return false }
                appState.openFile(url: url)
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // "Ignore Session Sidecar…" / "Reopen Without This Session" ask before they act (owner card Q2 a).
            .reopenWithoutSessionDialog(appState)
        .focusedSceneValue(\.appState, appState)
        // Info.plist declares CFBundleDocumentTypes, which puts mac4DSTEM in
        // Finder's "Open With" — this is the handler that requires.
        // `openFile` refuses a second load while one is in flight, so a
        // double-click during a load is declined with a reason rather than
        // reaching HDF5 twice.
        // UNVERIFIED ON SCREEN: not yet driven from Finder.
        .onOpenURL { appState.openFile(url: $0) }
        // Review a6 / owner card D2 (a): a closed window lets go of its dataset at once, even if something still
        // retains its state; a window that appears again is known again (`OpenDatasetRegistry`).
        .onAppear {
            appState.enrollInOpenDatasetRegistry()
            // A 4D file opened while this window holds only a spectrum image goes to a new window
            // (`AppState.routesOpenToNewWindow`), which takes it through the relay as a menu action.
            appState.openInNewWindow = { [menuRelay, openWindow] url, configure in
                menuRelay.request(.openFile(url, configure: configure))
                openWindow(id: "dataset")
            }
        }
        // The same event stops the window's running job (`windowClosed`): a closed window must not keep computing
        // for a dataset nobody can see. `onDisappear` fires when the hosting view leaves its window; a window
        // that merely hides, minimises or loses focus keeps its content in place and does not fire it.
        .onDisappear {
            OpenDatasetRegistry.withdraw(appState)
            appState.windowClosed()
        }
        .frame(minWidth: LayoutPolicy.datasetWindowMinimumSize.width,
               minHeight: LayoutPolicy.datasetWindowMinimumSize.height)
        // "Open Dataset…" / "Preprocess Raw Data…" chosen with no window focused opened this one; a
        // `.task`, so the content's own request observers exist before the action fires.
        .task {
            if let action = menuRelay.take() { MenuActionRelay.run(action, in: appState) }
        }
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
        #if DEBUG
        // The spectrum-only window, before the readers land (v5.0 WP2): metadata only.
        // Once per PROCESS, not per window: a second window (a 4D file opened from the
        // spectrum-only one goes to a new window) must not become spectrum-only too and
        // route its own open onward again.
        .task {
            guard !DemoSpectrumImageSource.openedAtLaunch,
                  ProcessInfo.processInfo.arguments.contains("--demo-spectrum-fixture") else { return }
            DemoSpectrumImageSource.openedAtLaunch = true
            appState.openSpectrumImage(DemoSpectrumImageSource.make(beamEnergyKeV: 200))
        }
        #endif
    }
}

private struct DatasetCommands: Commands {
    @FocusedValue(\.appState) private var appState
    @Environment(\.openWindow) private var openWindow
    let menuRelay: MenuActionRelay
    /// The app-wide list behind File > Open Recent. Also on the focused window's state, but a menu with no window
    /// focused (the last one closed) still has the list.
    let recents: RecentDatasets

    init(menuRelay: MenuActionRelay, recents: RecentDatasets) {
        self.menuRelay = menuRelay
        self.recents = recents
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Disabled while this window is loading, and never while the other
            // window might be. A second window gets its own AppState and so its
            // own H5Reader over the one process-wide, NON-THREAD-SAFE libhdf5
            // (`_H5E_stack_g` is a plain global; see `openFile`). This is the
            // cheap half of that defect — it removes the advertised gesture
            // that reaches it fastest, and does not make concurrent HDF5 safe.
            // The real fix is a single actor owning the library handle
            // (`docs/open-items.md`).
            Button("New Dataset Window") { openWindow(id: "dataset") }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState?.datasetSession.isLoading ?? false)
            // Also closed while a sidecar save runs: opening another dataset cancels it before it is written, and the
            // labels it carried exist nowhere else (review 2026-10-02 c4). `isBusy` is read first so the menu
            // re-evaluates when the operation starts and ends.
            // With no window focused (none open, or Settings / the object table key) it opens one and
            // runs there (`MenuActionRelay`), so it is enabled then too.
            Button("Open Dataset…") { perform(.openDataset) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!MenuActionRelay.isEnabled(
                    hasFocusedWindow: appState != nil,
                    blocked: appState?.datasetSession.isLoading == true || sidecarSaveInFlight))
            // The toolbar-only doors, in the menu where a Mac user looks for them (UI audit 2026-10-14, F).
            Button("Open with Options…") { perform(.openWithOptions) }
                .disabled(!MenuActionRelay.isEnabled(
                    hasFocusedWindow: appState != nil,
                    blocked: appState?.datasetSession.isLoading == true || sidecarSaveInFlight))
            // Recents are on the Welcome screen only while no dataset is open; this keeps them reachable after.
            Menu("Open Recent") {
                ForEach(recents.entries) { recent in
                    Button(recentMenuTitle(recent)) { perform(.openRecent(recent)) }
                }
                Divider()
                Button("Clear Menu") { recents.clearAll() }
            }
            .disabled(recents.entries.isEmpty
                      || !MenuActionRelay.isEnabled(
                          hasFocusedWindow: appState != nil,
                          blocked: appState?.datasetSession.isLoading == true || sidecarSaveInFlight))
            if let recovery = appState?.recoveryRecord {
                Button("Reopen \(recoveryName(recovery))") { appState?.reopenLastDataset() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(sidecarSaveInFlight)
            }
            Divider()
            Button("Show in Finder") {
                if let path = appState?.descriptor?.filePath { DatasetLocationActions.reveal(path: path) }
            }
            .disabled(appState?.descriptor == nil || appState?.datasetSession.isLoading == true)
        }
        CommandGroup(replacing: .importExport) {
            // One name per export, the toolbar's too: "Export <what> PNG…". The figure is exported from the Results inspector, where its
            // images are ticked (SwiftUI's export panel needs a view to present from, and a menu command has none).
            Button("Export Result PNG…") { appState?.exportResultImage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState?.resultPresentation.resultImage == nil
                          && appState?.resultPresentation.resultRGBA == nil)
            Button("Export Diffraction PNG…") { appState?.exportDiffractionImage() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(appState?.displayedPattern == nil)
            // One sheet for a raw file and for the open dataset's current view
            // (X3): with a cube open it is pre-filled with that view.
            Button("Preprocess Raw Data…") { perform(.preprocess) }
                .disabled(!MenuActionRelay.isEnabled(
                    hasFocusedWindow: appState != nil,
                    blocked: appState?.isBusy == true || appState?.datasetSession.isLoading == true)
                    // Row 8c (ADR 058): a 4D verb has nothing to act on in a spectrum-only window (`DatasetMenuRule`).
                    || appState.map { !DatasetMenuRule.showsPreprocessRawData(in: $0) } == true)
            // The Spectroscopy room's exports, in the menu bar while that room is on screen (UI audit 2026-10-14, The menu bar);
            // enabled by the inspector buttons' own rules (`SpectroscopyMenuRule`).
            if let room = spectroscopyRoomModel {
                Divider()
                Button("Export Spectrum CSV\u{2026}") { SpectroscopyMenuRule.exportSpectrum(room) }
                    .disabled(!SpectroscopyMenuRule.canExportSpectrum(room))
                Button("Export Maps\u{2026}") { SpectroscopyMenuRule.exportMaps(room) }
                    .disabled(!SpectroscopyMenuRule.canExportMaps(room))
                Button("Export Results CSV\u{2026}") { SpectroscopyMenuRule.exportResults(room) }
                    .disabled(!SpectroscopyMenuRule.canExportResults(room))
                Button("Export Method JSON\u{2026}") { SpectroscopyMenuRule.exportMethod(room) }
                    .disabled(!SpectroscopyMenuRule.canExportMethod(room))
            }
        }
        CommandGroup(replacing: .sidebar) {
            // Labels follow what is on screen, and the action acts on it too
            // (`toggleNavigator`): a sidebar the narrow window stepped aside
            // reads "Show Sidebar", and showing it keeps it shown. No
            // enablement check: the window's minimum fits both panels open.
            Button(appState?.navigation.navigatorIsVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                appState?.navigation.toggleNavigator()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(appState?.navigation.inspectorIsVisible == true ? "Hide Inspector" : "Show Inspector") {
                appState?.navigation.showInspectorPane.toggle()
            }
            // The one key, also the toolbar button's (`InspectorToggleButton`): Opt-Cmd-I, as Mac apps with an
            // inspector have it (HIG, Keyboards). It was Ctrl-Cmd-I here and a hidden Opt-Cmd-0 on the button.
            .keyboardShortcut("i", modifiers: [.command, .option])
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
            // Review e6: the toolbar's own readiness, so ⌘R is never a dead key.
            .disabled(appState?.canRunPrimaryWorkspaceTask != true)
            // Cmd-. is the Mac's cancel (HIG, Keyboards); Esc stays with the sheets and panels that own it.
            Button("Cancel Analysis") { appState?.cancelActiveOperation() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(appState?.canCancelActiveOperation != true)
            if let room = spectroscopyRoomModel {
                Divider()
                // The region tool, from the keyboard (the header row's chips are the pointer's way): Ctrl-Cmd-1 to 3.
                Button("Rectangle Region Tool") { room.drawTool = .rectangle }.keyboardShortcut("1", modifiers: [.command, .control])
                Button("Ellipse Region Tool") { room.drawTool = .ellipse }.keyboardShortcut("2", modifiers: [.command, .control])
                Button("Polygon Region Tool") { room.drawTool = .polygon }.keyboardShortcut("3", modifiers: [.command, .control])
                Button("Pin Region") { SpectroscopyMenuRule.pin(room) }
                    .disabled(!SpectroscopyMenuRule.canPin(room))
            }
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
            Button("Allow Access to Session Sidecar…") {
                appState?.allowAccessToSessionSidecar()
            }
            .disabled(appState?.hasDataset != true
                      || appState?.isBusy == true
                      || appState?.sessionSidecar.unreadableReason == nil)
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
            // ⌘1…⌘7 in list order: the rooms follow the pipeline,
            // Spectroscopy is ⌘6 and Results stays last, ⌘7 (ADR 053 item 3).
            ForEach(WorkspaceArea.allCases) { area in
                workspaceCommand(area, key: KeyEquivalent(area.shortcutDigit))
            }
        }
    }

    /// The Spectroscopy room's model while that room is on screen in the focused window; its commands exist only then.
    private var spectroscopyRoomModel: SpectroscopyRoomModel? {
        guard let appState,
              SpectroscopyMenuRule.showsItems(area: appState.navigation.workspaceArea, hasSpectrumImage: appState.hasSpectrumImage) else { return nil }
        return appState.spectroscopyRoom.model
    }

    /// Runs `action` in the focused window, or — with none — asks for it and opens a window that takes it.
    private func perform(_ action: MenuActionRelay.Action) {
        if let appState {
            MenuActionRelay.run(action, in: appState)
        } else {
            menuRelay.request(action)
            openWindow(id: "dataset")
        }
    }

    /// A session-sidecar save is running (review 2026-10-02 c4) — see the Open commands above.
    private var sidecarSaveInFlight: Bool {
        appState?.isBusy == true && SessionSidecarLocator.isSaveInFlight(appState?.activeOperation)
    }

    /// The Open Recent title: the dataset's name, with where it lives only when another recent has the same name.
    private func recentMenuTitle(_ recent: RecentDataset) -> String {
        let sameName = recents.entries.filter { $0.displayName == recent.displayName }.count > 1
        guard sameName, let location = recents.locationLabels[recent.id] else { return recent.displayName }
        return "\(recent.displayName) — \(location)"
    }

    private func recoveryName(_ recovery: DatasetRecoveryRecord) -> String {
        appState?.recents.entry(withID: recovery.datasetID)?.displayName
            ?? "Last Dataset"
    }

    private func workspaceCommand(_ area: WorkspaceArea, key: KeyEquivalent) -> some View {
        Button("Go to \(area.title)") { appState?.selectWorkspace(area) }
            .keyboardShortcut(key, modifiers: .command)
            // A spectrum-only window offers Spectroscopy and Results; with a
            // 4D cube every room; with nothing open, none (as before).
            .disabled(appState?.isWorkspaceAvailable(area) != true)
    }
}

@main
struct mac4DSTEMApp: App {
    // ONE instance for the whole process, shared by every dataset window and
    // the Settings scene — `UserDefaults` would make a second instance read
    // the same values, but only this one is `@Observable`-linked to what
    // Settings edits live (`DatasetWindow.init`'s doc explains why that
    // matters). See `ROADMAP.md` "Settings window, Xcode-style sidebar".
    @State private var preferences = AppPreferences()
    @State private var recents = RecentDatasets()
    // The object table's selection, read by every dataset window's scan pane
    // (`PrecipitateTableSelection`). App-scoped because the table is a separate
    // scene holding a snapshot, not a link to any one window's AppState.
    @State private var tableSelection = PrecipitateTableSelection()
    init() {
        UITestingLaunch.resetSavedState()
    }
    // File-menu actions asked for while no dataset window is focused (`MenuActionRelay`): read by the
    // commands, taken by the window they open.
    @State private var menuRelay = MenuActionRelay()

    var body: some Scene {
        WindowGroup("mac4DSTEM", id: "dataset") {
            DatasetWindow(preferences: preferences, recents: recents, menuRelay: menuRelay)
                .environment(tableSelection)
        }
            .defaultSize(width: UITestingLaunch.isActive ? UITestingLaunch.windowWidth : LayoutPolicy.datasetWindowIdealSize.width,
                         height: UITestingLaunch.isActive ? UITestingLaunch.windowHeight : LayoutPolicy.datasetWindowIdealSize.height)
            // `--ui-testing` (UI test target): one 1440 x 900 window (or the `--ui-window-width`); windows are not restored by the test's own launch.
            // A launch always presents the window (a UI test's launch has no restored state to present it).
            .defaultLaunchBehavior(.presented)
            .handlesExternalEvents(matching: ["*"])   // a launch event from the test runner opens this window, as macTEM's does
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands {
                DatasetCommands(menuRelay: menuRelay, recents: recents)
                ZoomCommands()   // View > Zoom In / Zoom Out / Zoom to Fit (lane H1, UI/ZoomCommands.swift)
            }
        // The object table (`UI/PrecipitateObjectsWindow.swift`): a snapshot
        // value, so it needs no reference to the dataset window's AppState and
        // can stay open beside the map. Opened from the Precipitates section.
        WindowGroup("Precipitate Objects", for: PrecipitateObjectReport.self) { $report in
            if let report {
                PrecipitateObjectsWindow(report: report)
                    .environment(tableSelection)
                    .preferredColorScheme(preferences.appearance.colorScheme)
            }
        }
            .defaultSize(width: 1180, height: 680)
            .windowToolbarStyle(.unified)
            // A snapshot of a run in a session that is gone: reopened at launch
            // it would sit detached from any map, its selection matching no run.
            .restorationBehavior(.disabled)
        // `UI/SettingsWindow.swift`'s sidebared `NavigationSplitView` hosts
        // this; its Materials Project section is the original `Form`
        // section, moved rather than rewritten (see its own header).
        Settings {
            SettingsWindow()
                .environment(preferences)
                .environment(recents)
        }
    }
}
