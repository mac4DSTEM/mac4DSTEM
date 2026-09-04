import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The app's window: a SwiftUI-only shell. It was `--ui2` until 2026-09-04,
/// when the AppKit-hosted window it replaced was deleted.
///
/// **The frozen rules.** `NavigationSplitView` and the native `.inspector`
/// are the whole window structure — no `NSSplitViewController`, no hosted
/// AppKit shell, no custom pane chrome, no pane focus ring, and no call into
/// a view under `UI/`. UI2 reads and drives the shared `App/`, `Session/`
/// and `Core/` logic, and nothing else.
///
/// **The shape** (owner decision, 2026-09-04) is Xcode's, Pages' and
/// Keynote's, not the old window's:
///
/// - **Left** is navigation and nothing else: five workspaces and their
///   tasks, in a source list narrow enough to stay narrow.
/// - **Centre** is the science: the panes, with the status of the running
///   operation and the output log along the bottom edge.
/// - **Right** is the inspector, in two tabs — **Settings**, every control
///   the selected workspace owns, and **Info**, what the dataset and the
///   displayed product actually are.
///
/// That split is what retires the old column's two failure modes at once:
/// controls no longer compete with navigation for one 250 pt column, and the
/// workspace header that repeated the sidebar's own title is gone — the
/// window title says where you are and the toolbar holds the one action that
/// runs the task.
struct UI2ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showExportSheet = false
    @State private var openedInspectorOnce = false

    private var datasetTypes: [UTType] {
        ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    private var route: UI2Route { UI2Route.current(appState.navigation) }

    var body: some View {
        @Bindable var navigation = appState.navigation

        NavigationSplitView(columnVisibility: sidebarVisibility) {
            UI2Sidebar()
                .navigationSplitViewColumnWidth(
                    min: UI2Metrics.sidebarWidth.min,
                    ideal: UI2Metrics.sidebarWidth.ideal,
                    max: UI2Metrics.sidebarWidth.max
                )
        } detail: {
            UI2Workspace()
                .inspector(isPresented: $navigation.showInspectorPane) {
                    UI2Inspector()
                        .inspectorColumnWidth(
                            min: UI2Metrics.inspectorWidth.min,
                            ideal: UI2Metrics.inspectorWidth.ideal,
                            max: UI2Metrics.inspectorWidth.max
                        )
                }
        }
        .navigationTitle(appState.hasDataset ? route.title : "mac4DSTEM")
        .navigationSubtitle(appState.descriptor?.fileName ?? "")
        .toolbar { toolbarContent }
        .task {
            // The inspector holds the workspace's controls in UI2, so it
            // opens with the window. The flag is `WorkspaceNavigation`'s, so
            // the Show/Hide Inspector menu item keeps working.
            guard !openedInspectorOnce else { return }
            openedInspectorOnce = true
            appState.navigation.showInspectorPane = true
        }
        .onChange(of: appState.virtualShape) { appState.commitApertureChange() }
        .onChange(of: appState.realSpaceShape) { appState.updateRealSpaceRegion() }
        .onChange(of: appState.realSpaceRadius) { appState.updateRealSpaceRegion() }
        .onChange(of: appState.openDatasetRequest) { showImporter = true }
        .onChange(of: appState.preprocessingExportRequest) {
            if appState.hasDataset { showExportSheet = true }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: datasetTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // One importer, two destinations: "Open Dataset…" loads
                    // straight through, and only "Open with Options…" stops
                    // to ask.
                    if appState.configureOnOpen {
                        appState.openFileForConfiguration(url: url)
                    } else {
                        appState.openFile(url: url)
                    }
                }
            case .failure(let error):
                appState.present(error)
            }
            appState.configureOnOpen = false
        }
        .sheet(item: Binding(
            get: { appState.pendingLoad },
            set: { if $0 == nil { appState.discardPendingLoad() } }
        )) { pending in
            UI2LoadConfigurator(pending: pending)
                .environment(appState)
        }
        .sheet(isPresented: $showExportSheet) {
            if let descriptor = appState.descriptor {
                UI2ExportSheet(descriptor: descriptor)
                    .environment(appState)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("Copy Details") { copyToPasteboard(appState.errorMessage ?? "") }
            Button("Open Another…") {
                appState.errorMessage = nil
                appState.requestOpenDataset()
            }
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    /// The sidebar's visibility rides on the same flag as the Show/Hide Tools
    /// menu item, so the two can never disagree.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.navigation.showToolsPane ? .all : .detailOnly },
            set: { appState.navigation.showToolsPane = ($0 != .detailOnly) }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // `NavigationSplitView` contributes the sidebar toggle. Everything
        // UI2 adds sits trailing, where macOS puts affirmative actions: the
        // one action that runs the task, the way to keep its result, the
        // dataset's own menu, and the inspector's toggle. The action was
        // centred (`.principal`) until 2026-09-04; the owner's drive found
        // that the centre slot is too narrow for the busy state, which
        // truncated "Cancel" to "C…".
        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .primaryAction) {
            UI2PrimaryActionButton()
        }

        ToolbarItem(placement: .primaryAction) {
            UI2SaveResultButton()
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Open Dataset…") { appState.requestOpenDataset() }
                Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
                if appState.hasDataset {
                    Divider()
                    Button("Preprocess & Export…") { appState.requestPreprocessingExport() }
                        .disabled(appState.isBusy)
                    Button("Save Calibration") { appState.saveCalibrationToSessionSidecar() }
                        .disabled(appState.isBusy)
                    Button("Export Diffraction PNG…") { appState.exportDiffractionImage() }
                        .disabled(appState.displayedPattern == nil)
                }
            } label: {
                Label("Dataset", systemImage: "folder")
            }
            .help("Open a dataset, or act on the one that is open")
            .accessibilityIdentifier("toolbar.datasetMenu")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.navigation.showInspectorPane.toggle()
            } label: {
                Label(
                    appState.navigation.showInspectorPane ? "Hide Inspector" : "Show Inspector",
                    systemImage: "sidebar.trailing"
                )
            }
            .help(appState.navigation.showInspectorPane
                  ? "Hide the inspector" : "Show the inspector")
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
