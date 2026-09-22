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
    @SceneStorage("workspace.navigatorVisible") private var savedNavigatorVisible = true
    @SceneStorage("workspace.inspectorVisible") private var savedInspectorVisible = true

    private var datasetTypes: [UTType] {
        ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        splitWindow
        .onAppear {
            appState.navigation.showToolsPane = savedNavigatorVisible
            appState.navigation.showInspectorPane = savedInspectorVisible
            // Capture scaffolding, the `--demo-fixture` shape: a launch can
            // force a panel state, so a scripted capture of the hidden or
            // shown toolbar does not depend on whatever state the last window
            // left behind (2026-09-22).
            applyPanelLaunchFlags()
        }
        .task {
            // Once more after the first layout: scene restoration can land
            // after `onAppear` and put the saved state back.
            try? await Task.sleep(for: .milliseconds(500))
            applyPanelLaunchFlags()
        }
        .onChange(of: appState.navigation.showToolsPane) {
            savedNavigatorVisible = appState.navigation.showToolsPane
        }
        .onChange(of: appState.navigation.showInspectorPane) {
            savedInspectorVisible = appState.navigation.showInspectorPane
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
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            WorkspaceSidebar()
                .navigationSplitViewColumnWidth(
                    min: LayoutPolicy.sidebarWidth.min,
                    ideal: LayoutPolicy.sidebarWidth.ideal,
                    max: LayoutPolicy.sidebarWidth.max
                )
        } detail: {
            WorkspaceView()
                // Declared on the detail column, not on the split view.
                // Measured 2026-09-22 on macOS 27: with the title removed,
                // a toolbar declared on the split view laid these
                // `.primaryAction` items out at the content's LEADING edge,
                // beside the sidebar toggle, and a flexible `ToolbarSpacer`
                // (automatic or `.primaryAction` placement) did not move
                // them. Declared here they take the trailing edge — over
                // the inspector when it is open, at the window's edge when
                // it is not — and the toggle stays reachable either way.
                .toolbar { windowToolbarContent }
        }
        // Phase 1 (window-design.md §4–§6, decided 2026-09-22): `.inspector`
        // moved here, off the detail view, so the column runs from the
        // toolbar to the window's bottom edge exactly the way the sidebar
        // already does.
        .inspector(isPresented: inspectorPresented) {
            WorkspaceInspector()
                .inspectorColumnWidth(
                    min: LayoutPolicy.inspectorWidth.min,
                    ideal: LayoutPolicy.inspectorWidth.ideal,
                    max: LayoutPolicy.inspectorWidth.max
                )
                // The inspector's own toolbar carries its Settings · Info
                // picker and its ONE toggle (`WorkspaceInspector`): items
                // declared there stay in the toolbar, once, while the column
                // is hidden — measured 2026-09-22 — so nothing here may add a
                // second toggle (the owner saw two, twice, that evening).
        }
        // The window keeps a title — the dataset, as a document window's is —
        // for the Window menu, Mission Control and accessibility, but the
        // toolbar does not draw it: the centre header's breadcrumb already
        // reads "Prepare › dataset", and the same words 30 pt above it were
        // the duplicate header the 2026-09-04 rebuild had removed, found
        // again on the first phase-1 look (2026-09-22). Xcode's toolbar
        // carries no title either; its jump bar does.
        .navigationTitle(appState.descriptor?.fileName ?? "mac4DSTEM")
        .toolbar(removing: .title)
    }

    /// What the split view shows and what a click writes are both intent
    /// now (`WorkspaceNavigation`) — nothing narrows it further.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { appState.navigation.inspectorIsVisible },
            set: { appState.navigation.showInspectorPane = $0 }
        )
    }

    /// The sidebar's visibility rides on the same flag as the Show/Hide Tools
    /// menu item, so the two can never disagree.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.navigation.navigatorIsVisible ? .all : .detailOnly },
            set: { appState.navigation.showToolsPane = ($0 != .detailOnly) }
        )
    }

    /// Capture scaffolding (see `onAppear`): only a launch flag writes here.
    private func applyPanelLaunchFlags() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--inspector-hidden") { appState.navigation.showInspectorPane = false }
        if arguments.contains("--inspector-shown") { appState.navigation.showInspectorPane = true }
        if arguments.contains("--navigator-hidden") { appState.navigation.showToolsPane = false }
        if arguments.contains("--navigator-shown") { appState.navigation.showToolsPane = true }
        if arguments.contains("--lineage-shown") { appState.navigation.showsLineagePane = true }
        if arguments.contains("--process-area-open") { appState.navigation.showLogPane = true }
    }

    /// Only window-level controls live here. The split view supplies the
    /// leading navigator toggle; this trailing toggle survives closing the
    /// inspector. ⌥⌘0 and the existing ⌃⌘I menu item reach the same state.
    /// The owner's arrangement (2026-09-22 evening, window-design.md §8.1 and
    /// his corrections on his own build): the file, the room and the live
    /// run as a DISPLAY in the centre, never a button (the 2026-09-04 "C…"
    /// trap); over the room at the trailing edge, the run button — Stop
    /// while it runs — then Save to Session, Reveal in Finder and the
    /// dataset menu as icons; only the inspector's toggle over the inspector.
    /// Always there, so the analysis runs with both side panels hidden and
    /// the data at full size. This reverses §6.2 of 2026-09-22 morning; the
    /// breadcrumb row it replaces is gone (`WorkspaceView`).
    @ToolbarContentBuilder
    private var windowToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ToolbarRunDisplay()
        }
        // The flexible spacer alone did NOT hold these items at the trailing
        // edge once the title was removed (two captures, 2026-09-22, with
        // `.automatic` and `.primaryAction` placement); declaring the toolbar
        // on the detail column did (see `splitWindow`). The spacer stays as
        // the new toolbar model's own separator between the centre display
        // and this group.
        ToolbarSpacer(.flexible, placement: .primaryAction)
        // The room's verb heads the trailing group, beside the actions on
        // its result and under the inspector where its parameters are set
        // (owner, 2026-09-22 evening, on his build: "the user changes the
        // parameters of the current workspace on the right" — the mock's
        // Xcode-Run position at the left was wrong for this app). Stop takes
        // its place while a run is in flight. `visibilityPriority` says what
        // overflows first when the window narrows: the run verb and the
        // dataset switcher stay, Save/Reveal go into the overflow menu.
        ToolbarItem(placement: .primaryAction) {
            PrimaryActionButton()
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .primaryAction) {
            SaveResultButton()
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            RevealDatasetButton()
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            DatasetMenu()
        }
        .visibilityPriority(.high)
        // No inspector toggle here: it is the inspector's own (see
        // `.inspector` above).
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


/// The toolbar's centre — Xcode's activity viewer (owner, 2026-09-22
/// evening: "the dataset's name … and the current process" in the toolbar).
/// Idle: the file, the room and the scan size, one line, middle-truncating.
/// Busy: the running operation, its bar and its elapsed/ETA, ticking once a
/// second. A display, never a button, at a constant width
/// (`LayoutPolicy.toolbarDisplayWidth`) so a ticking string never reflows the
/// toolbar (011). Absent without a dataset, like every room action.
struct ToolbarRunDisplay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let descriptor = appState.descriptor, !appState.datasetSession.isLoading {
            Group {
                if appState.isBusy {
                    busy
                } else {
                    Text(ToolbarDisplayFormat.idle(
                        file: descriptor.fileName,
                        room: WorkspaceRoute.current(appState.navigation).title,
                        positions: descriptor.rx * descriptor.ry
                    ))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(descriptor.filePath)
                    .accessibilityIdentifier("toolbar.display.idle")
                }
            }
            .frame(minWidth: LayoutPolicy.toolbarDisplayMinimumWidth,
                   maxWidth: LayoutPolicy.toolbarDisplayWidth)
        }
    }

    /// Name and elapsed time only: the bar, the counts, the rate, the ETA
    /// and Stop are the infobar's (owner, 2026-09-22 late, §9.3) — one
    /// progress bar on screen, never two (010).
    private var busy: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text([appState.activeOperation ?? appState.statusText,
                  appState.activeOperationMetrics(at: context.date).map { OperationMetricsFormat.duration($0.elapsed) }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("toolbar.display.busy")
        }
    }
}

/// How the toolbar's idle display is worded, in one place, tested.
enum ToolbarDisplayFormat {
    /// "Demo.h5 · Prepare · 144 positions" — the file first (it is the
    /// window's subject), the room, then the scan size.
    static func idle(file: String, room: String, positions: Int) -> String {
        "\(file) · \(room) · \(SystemMonitor.count(positions)) positions"
    }
}
