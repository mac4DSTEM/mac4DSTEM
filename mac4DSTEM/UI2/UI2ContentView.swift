import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import UniformTypeIdentifiers

/// SwiftUI-native replacement shell, compiled beside the current UI and enabled
/// with `--ui2`. It reuses the existing product/session views while resetting
/// the window structure around system SwiftUI containers.
struct UI2ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showPreprocessingExport = false
    @State private var logHeight: CGFloat = 170

    private var h5Types: [UTType] {
        [
            UTType(filenameExtension: "h5"),
            UTType(filenameExtension: "hdf5"),
            UTType(filenameExtension: "emd"),
            UTType(filenameExtension: "dm4"),
            UTType(filenameExtension: "dm3"),
            UTType(filenameExtension: "mib"),
            UTType(filenameExtension: "raw"),
            UTType(filenameExtension: "xml")
        ].compactMap { $0 }
    }

    private var splitVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.navigation.showToolsPane ? .all : .detailOnly },
            set: { appState.navigation.showToolsPane = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: splitVisibility) {
            UI2Sidebar(showPreprocessingExport: $showPreprocessingExport)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            workspace
                .inspector(isPresented: inspectorPresented) {
                    WorkspaceInspector()
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 520)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("mac4DSTEM")
        .toolbar { toolbarContent }
        .onChange(of: appState.virtualShape) { appState.commitApertureChange() }
        .onChange(of: appState.realSpaceShape) { appState.updateRealSpaceRegion() }
        .onChange(of: appState.realSpaceRadius) { appState.updateRealSpaceRegion() }
        .onChange(of: appState.openDatasetRequest) { showImporter = true }
        .onChange(of: appState.preprocessingExportRequest) {
            if appState.hasDataset { showPreprocessingExport = true }
        }
        .sheet(isPresented: $showPreprocessingExport) {
            if let descriptor = appState.descriptor {
                PreprocessingExportSheet(descriptor: descriptor)
                    .environment(appState)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: h5Types,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
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
            LoadConfiguratorView(pending: pending)
                .environment(appState)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("Open Another…") {
                appState.errorMessage = nil
                appState.requestOpenDataset()
            }
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { appState.navigation.showInspectorPane },
            set: { appState.navigation.showInspectorPane = $0 }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                withAnimation { appState.navigation.showToolsPane.toggle() }
            } label: {
                Label(
                    appState.navigation.showToolsPane ? "Hide Tools" : "Show Tools",
                    systemImage: "sidebar.leading"
                )
            }
            .help(appState.navigation.showToolsPane ? "Hide the tools sidebar" : "Show the tools sidebar")
        }

        ToolbarSpacer(.flexible)

        ToolbarItemGroup(placement: .primaryAction) {
            if appState.hasDataset && appState.navigation.workspaceArea != .results {
                Button {
                    withAnimation { appState.navigation.showLogPane.toggle() }
                } label: {
                    Label(
                        appState.navigation.showLogPane ? "Hide Output" : "Show Output",
                        systemImage: "rectangle.bottomthird.inset.filled"
                    )
                }
                .help(appState.navigation.showLogPane ? "Hide the output log" : "Show the output log")
            }

            Button {
                withAnimation { appState.navigation.showInspectorPane.toggle() }
            } label: {
                Label(
                    appState.navigation.showInspectorPane ? "Hide Inspector" : "Show Inspector",
                    systemImage: "sidebar.trailing"
                )
            }
            .help(appState.navigation.showInspectorPane ? "Hide the inspector" : "Show the inspector")
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if appState.hasDataset && !appState.isLoadingDataset {
                ProductWorkspaceHeader()
            }

            Group {
                if appState.hasDataset && !appState.isLoadingDataset && appState.navigation.workspaceArea == .results {
                    ResultsWorkspace()
                } else if appState.hasDataset && !appState.isLoadingDataset {
                    dataWorkspace
                } else {
                    WelcomeWorkspace()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.navigation.showLogPane && appState.hasDataset && !appState.isLoadingDataset {
                UI2OutputLog(height: $logHeight)
            }

            Divider()
            StatusFooterView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dataWorkspace: some View {
        HSplitView {
            ui2Pane(active: appState.activePane == .diffraction) {
                DiffractionView()
            }
            .frame(minWidth: 220)
            .onTapGesture {
                appState.activePane = .diffraction
                claimPaneFocus()
            }

            ui2Pane(active: appState.activePane == .realSpace) {
                StemImageView()
            }
            .frame(minWidth: 220)
            .onTapGesture {
                appState.activePane = .realSpace
                claimPaneFocus()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleArrowKey($0) }
        .onChange(of: appState.navigation.workspaceArea, initial: true) { claimPaneFocus() }
        .onChange(of: appState.navigation.analysisMode) { claimPaneFocus() }
    }

    private func ui2Pane<Content: View>(
        active: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(active ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
    }

    private func claimPaneFocus() {
        appState.navigation.focusedPane = FocusedPane.livePane(
            appState.activePane,
            in: appState.navigation.workspaceArea,
            task: appState.navigation.analysisMode
        )
    }

    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        guard let descriptor = appState.descriptor else { return .ignored }
        let step = press.modifiers.contains(.shift) ? 10 : 1
        var x = appState.selectedScan.x
        var y = appState.selectedScan.y

        switch press.key {
        case .leftArrow: x -= step
        case .rightArrow: x += step
        case .upArrow: y -= step
        case .downArrow: y += step
        default: return .ignored
        }

        appState.selectScan(
            x: min(max(0, x), descriptor.rx - 1),
            y: min(max(0, y), descriptor.ry - 1)
        )
        return .handled
    }
}

struct UI2Sidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var showPreprocessingExport: Bool

    private var selection: Binding<UI2SidebarSelection?> {
        Binding(
            get: {
                let area = appState.navigation.workspaceArea
                return area.analysisModes.isEmpty
                    ? .workspace(area)
                    : .task(appState.navigation.analysisMode)
            },
            set: { selection in
                switch selection {
                case .workspace(let area):
                    appState.selectWorkspace(area)
                case .task(let mode):
                    appState.changeMode(mode)
                case nil:
                    break
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            if let descriptor = appState.descriptor, descriptor.is4D {
                Section {
                    datasetRow(descriptor)
                }
            }

            Section("Workspace") {
                ForEach(WorkspaceArea.allCases) { area in
                    Label(area.title, systemImage: area.systemImage)
                        .tag(UI2SidebarSelection.workspace(area))
                }
            }

            if !appState.navigation.workspaceArea.analysisModes.isEmpty {
                Section("Task") {
                    ForEach(appState.navigation.workspaceArea.taskFamilyGroups) { group in
                        ForEach(group.modes) { mode in
                            taskRow(mode)
                                .tag(UI2SidebarSelection.task(mode))
                        }
                    }
                }
            }

            if appState.hasDataset && !appState.isLoadingDataset {
                Section("Controls") {
                    controlsForCurrentWorkspace
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func datasetRow(_ descriptor: DatasetDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.cross.fill")
                    .foregroundStyle(Color.accentColor)
                Text(descriptor.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("Open Another…") { appState.requestOpenDataset() }
                    Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
                    Button("Preprocess & Export…") { showPreprocessingExport = true }
                        .disabled(appState.isBusy)
                    Divider()
                    Button("Save Calibration") { appState.saveCalibrationToSessionSidecar() }
                        .disabled(appState.isBusy)
                    Button("Export Diffraction PNG…") { appState.exportDiffractionImage() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text("\(descriptor.rx) x \(descriptor.ry) scan · \(descriptor.qx) x \(descriptor.qy) detector")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Label(
                appState.calibrationSession.verdict.quantitative ? "Quantitative" : "Not quantitative",
                systemImage: appState.calibrationSession.verdict.quantitative
                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(appState.calibrationSession.verdict.quantitative ? Color.green : Color.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func taskRow(_ mode: AnalysisMode) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(mode.productTitle)
                Spacer(minLength: 4)
                taskStatusGlyph(mode)
            }
        } icon: {
            Image(systemName: mode.systemImage)
        }
        .help(mode.productSubtitle)
    }

    private func taskStatusGlyph(_ mode: AnalysisMode) -> some View {
        let unmet = ProductWorkflow.prerequisites(
            for: mode,
            readiness: appState.productWorkflowReadiness
        ).count
        let produced = taskHasProduct(mode)
        return Image(systemName: produced
            ? "checkmark.circle.fill"
            : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
            .foregroundStyle(produced ? Color.green : (unmet == 0 ? Color.secondary : Color.orange))
    }

    private func taskHasProduct(_ mode: AnalysisMode) -> Bool {
        switch mode {
        case .disks:
            appState.hasCurrentBraggVectors
        case .strain:
            appState.strain.map != nil
        case .acom:
            appState.acomSession.hasOrientationMap
        case .virtualDetector:
            appState.replay.record.steps.contains { $0.kind == "virtual_detector" }
        case .dpc:
            appState.replay.record.steps.contains { $0.kind == "dpc" }
        case .ptychography, .singleslicePtychography:
            false
        }
    }

    @ViewBuilder
    private var controlsForCurrentWorkspace: some View {
        switch appState.navigation.workspaceArea {
        case .prepare:
            PrepareSidebar()
        case .image:
            ImageSidebar()
        case .map:
            MapSidebar()
        case .reconstruct:
            PhaseSidebar()
        case .results:
            ResultsSidebar()
        }
    }
}

private enum UI2SidebarSelection: Hashable {
    case workspace(WorkspaceArea)
    case task(AnalysisMode)
}

struct UI2OutputLog: View {
    @Environment(AppState.self) private var appState
    @Binding var height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .contentShape(Rectangle().inset(by: -4))
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            height = min(max(72, height - value.translation.height), 520)
                        }
                )
                .accessibilityLabel("Resize output log")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(appState.logMessages.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: appState.logMessages.count) {
                    proxy.scrollTo(appState.logMessages.count - 1, anchor: .bottom)
                }
            }
        }
        .frame(height: height)
        .background(.bar)
    }
}
