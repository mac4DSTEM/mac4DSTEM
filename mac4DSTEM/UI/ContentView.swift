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
/// a view under `UI/`. UI reads and drives the shared `App/`, `Session/`
/// and `Core/` logic, and nothing else.
///
/// **The shape** (owner decision, 2026-09-22) is Xcode's:
///
/// - **Left** is navigation and nothing else: five workspaces and their
///   tasks, in a source list narrow enough to stay narrow.
/// - **Centre** owns the breadcrumb/action header, science panes, infobar,
///   and the process area below that draggable bar.
/// - **Right** is the inspector, in two tabs — **Settings**, every control
///   the selected workspace owns, and **Info**, what the dataset and the
///   displayed product actually are.
///
/// The standard toolbar holds the dataset switcher and panel toggles; room
/// actions stay inside the centre header as the side panels come and go.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showExportSheet = false
    @State private var availableWindowWidth: CGFloat = .infinity
    @SceneStorage("workspace.navigatorVisible") private var savedNavigatorVisible = true
    @SceneStorage("workspace.inspectorVisible") private var savedInspectorVisible = true

    private var datasetTypes: [UTType] {
        ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    private var route: WorkspaceRoute { WorkspaceRoute.current(appState.navigation) }

    var body: some View {
        splitWindow
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { updateWindowWidth(geometry.size.width) }
                    .onChange(of: geometry.size.width) { updateWindowWidth(geometry.size.width) }
            }
        }
        .onAppear {
            appState.navigation.showToolsPane = savedNavigatorVisible
            appState.navigation.showInspectorPane = savedInspectorVisible
            collapsePanelsIfNeeded()
        }
        .onChange(of: appState.navigation.showToolsPane) {
            savedNavigatorVisible = appState.navigation.showToolsPane
            collapsePanelsIfNeeded()
        }
        .onChange(of: appState.navigation.showInspectorPane) {
            savedInspectorVisible = appState.navigation.showInspectorPane
            collapsePanelsIfNeeded()
        }
        .onChange(of: appState.resultPresentation.virtualShape) { appState.commitApertureChange() }
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
            handleImport(result)
        }
        .sheet(item: Binding(
            get: { appState.promotionRun.pendingLoad },
            set: { if $0 == nil { appState.discardPendingLoad() } }
        )) { pending in
            LoadConfigurator(pending: pending)
                .environment(appState)
        }
        .sheet(isPresented: $showExportSheet) {
            if let descriptor = appState.descriptor {
                ExportSheet(descriptor: descriptor)
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

    private var splitWindow: some View {
        @Bindable var navigation = appState.navigation

        return NavigationSplitView(columnVisibility: sidebarVisibility) {
            WorkspaceSidebar()
                .navigationSplitViewColumnWidth(
                    min: LayoutPolicy.sidebarWidth.min,
                    ideal: LayoutPolicy.sidebarWidth.ideal,
                    max: LayoutPolicy.sidebarWidth.max
                )
        } detail: {
            WorkspaceView()
        }
        // Phase 1 (window-design.md §4–§6, decided 2026-09-22): `.inspector`
        // moved here, off the detail view, so the column runs from the
        // toolbar to the window's bottom edge exactly the way the sidebar
        // already does. The persistent trailing toggle belongs to the split
        // view's toolbar, so it remains available with the inspector hidden.
        .inspector(isPresented: $navigation.showInspectorPane) {
            WorkspaceInspector()
                .inspectorColumnWidth(
                    min: LayoutPolicy.inspectorWidth.min,
                    ideal: LayoutPolicy.inspectorWidth.ideal,
                    max: LayoutPolicy.inspectorWidth.max
                )
        }
        .navigationTitle(appState.hasDataset ? route.title : "mac4DSTEM")
        .navigationSubtitle(appState.descriptor?.fileName ?? "")
        .toolbar { windowToolbarContent }
    }

    /// The sidebar's visibility rides on the same flag as the Show/Hide Tools
    /// menu item, so the two can never disagree.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.navigation.showToolsPane ? .all : .detailOnly },
            set: { appState.navigation.showToolsPane = ($0 != .detailOnly) }
        )
    }

    private func updateWindowWidth(_ width: CGFloat) {
        guard width >= LayoutPolicy.datasetWindowMinimumSize.width else { return }
        availableWindowWidth = width
        collapsePanelsIfNeeded()
    }

    private func collapsePanelsIfNeeded() {
        let navigation = appState.navigation
        if navigation.showInspectorPane,
           WindowAnatomyPolicy.collapseInspector(
               at: availableWindowWidth, navigatorVisible: navigation.showToolsPane
           ) {
            navigation.showInspectorPane = false
        }
        if navigation.showToolsPane,
           WindowAnatomyPolicy.collapseNavigator(at: availableWindowWidth) {
            navigation.showToolsPane = false
        }
    }

    /// Only window-level controls live here. The split view supplies the
    /// leading navigator toggle; this trailing toggle survives closing the
    /// inspector. ⌥⌘0 and the existing ⌃⌘I menu item reach the same state.
    @ToolbarContentBuilder
    private var windowToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            DatasetMenu()
        }
        ToolbarItem(placement: .primaryAction) {
            if appState.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("An operation is running")
            }
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
            .keyboardShortcut("0", modifiers: [.command, .option])
            .accessibilityIdentifier("toolbar.inspectorToggle")
            .disabled(WindowAnatomyPolicy.collapseInspector(
                at: availableWindowWidth,
                navigatorVisible: appState.navigation.showToolsPane
            ))
        }
    }

    /// The importer's completion, as a method rather than an inline closure:
    /// Xcode 26.6's type checker times out on the closure form ("unable to
    /// type-check this expression in reasonable time", CI 2026-09-14) while
    /// Xcode 27 compiles it. Nothing here changed but the shape.
    private func handleImport(_ result: Result<[URL], Error>) {
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

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
