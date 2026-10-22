import ShellLayout
import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
#endif

/// The app's window: a SwiftUI-only shell. The skeleton (the split view, the inspector, where the toolbar is declared, the width at
/// which the sidebar steps aside, the scene-stored panel intent and the launch flags) is ShellLayout's `ShellWindow` (suite task 8,
/// MacEMUI); this file adds what is the app's: the importer, the sheets, the alert and the observers of app state, the toolbar's
/// content, and the `--lineage-shown` flag (the Lineage pane is this app's).
///
/// **The frozen rules** (ADR 035). `NavigationSplitView` and the native `.inspector` are the whole window structure — no
/// `NSSplitViewController`, no hosted AppKit shell, no custom pane chrome, no pane focus ring, and no call into a view under `UI/`.
///
/// **The shape** is Xcode's: left, navigation and nothing else (seven workspaces and their tasks); centre, the science panes, the
/// infobar and the process area; right, the inspector in two tabs, Settings and Info. The toolbar holds the activity display, the
/// room's verb, Save to Session and the dataset menu.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showExportSheet = false

    private var datasetTypes: [UTType] {
        ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        ShellWindow(
            navigation: appState.navigation.panels,
            title: appState.descriptor?.fileName ?? appState.spectroscopy.metadata?.fileName ?? "mac4DSTEM",
            sidebar: { WorkspaceSidebar() },
            canvas: { WorkspaceView() },
            inspector: { WorkspaceInspector() },
            toolbar: { windowToolbarContent })
        .onAppear { applyLineageLaunchFlag() }
        .task {
            // Once more after the first layout, as the shell does for the panels: scene restoration can land after `onAppear`.
            try? await Task.sleep(for: .milliseconds(500))
            applyLineageLaunchFlag()
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
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    /// Capture scaffolding: the Lineage pane is this app's, so its launch flag is too (the panel flags are the shell's).
    private func applyLineageLaunchFlag() {
        if ProcessInfo.processInfo.arguments.contains("--lineage-shown") {
            appState.navigation.panels.shownProcessPanes.insert(.lineage)
        }
    }

    /// The arrangement (ADR 036): the file, the room and the live run as a DISPLAY in the centre, never a button (the 2026-09-04
    /// "C…" trap); over the room at the trailing edge, the run button — Stop while it runs — then Save to Session and the dataset menu
    /// as icons (Reveal in Finder is File > Show in Finder, owner decision 2026-10-22); only the inspector's toggle over the
    /// inspector (the shell's). Always there, so the analysis runs with both side panels hidden and the data at full size.
    @ToolbarContentBuilder
    private var windowToolbarContent: some ToolbarContent {
        ShellToolbar(
            display: { ToolbarRunDisplay(toolbarDisplay) },
            verb: { PrimaryActionButton(WorkspacePrimaryAction.current(appState)) },
            utility: {
                ToolbarItem(placement: .primaryAction) {
                    SaveResultButton()
                }
                .visibilityPriority(.low)
            },
            documentMenu: { DatasetMenu() })
    }

    /// What the toolbar's centre shows: nothing without a document or while it loads; the running operation and its clock while busy;
    /// else "file · room · size".
    private var toolbarDisplay: ToolbarDisplayState? {
        guard !appState.datasetSession.isLoading else { return nil }
        let room = WorkspaceRoute.current(appState.navigation).title
        if let descriptor = appState.descriptor {
            if appState.isBusy {
                return .busy(operation: appState.activeOperation ?? appState.statusText, progress: appState.progress,
                             metrics: { date in
                                 appState.activeOperationMetrics(at: date).map { ($0.elapsed, nil) }
                             })
            }
            let positions = descriptor.rx * descriptor.ry
            return .idle(file: descriptor.fileName, room: room,
                         detail: "\(SystemMonitor.count(positions)) \(positions == 1 ? "position" : "positions")",
                         help: descriptor.filePath)
        }
        if let metadata = appState.spectroscopy.metadata {
            // A spectrum-only window (v5.0 WP2): the same display, its grid in pixels.
            return .idle(file: metadata.fileName, room: room, detail: "\(metadata.scanWidth) × \(metadata.scanHeight) px", help: metadata.filePath)
        }
        return nil
    }

    /// The importer's completion, as a method rather than an inline closure:
    /// Xcode 26.6's type checker times out on the closure form ("unable to
    /// type-check this expression in reasonable time" in CI) while Xcode 27
    /// compiles it. Nothing here changed but the shape.
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
