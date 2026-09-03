import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import SwiftUI
import UniformTypeIdentifiers
import simd

/// Which display controls the sidebar's "Display" section offers, per
/// workspace.
///
/// Extracted so it can be tested. The rendered alternative cannot be: SwiftUI
/// builds a `Picker`'s `NSPopUpButton` menu lazily for a real assistive client,
/// so in-process the button carries no `itemTitles`, no `title`, no
/// `selectedItem` and `numberOfItems == 0` (measured 2026-08-06, the same wall
/// `SidebarLayoutTests` hit for accessibility identifiers). Counting anonymous
/// pop-up buttons would pass just as happily on the wrong one.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showPreprocessingExport = false

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

    var body: some View {
        VStack(spacing: 0) {
            // Owner decision 2026-09-03: the columns are AppKit's
            // (`ColumnSplitController`), the way Xcode's are — the divider is
            // the only authority over a column's width and SwiftUI content
            // lays out inside it. See SplitViewPolicy.swift for why.
            WorkspaceColumns(
                sidebar: AnyView(sidebarColumn.environment(appState)),
                content: AnyView(workspaceColumn.environment(appState)),
                inspector: AnyView(WorkspaceInspector().environment(appState)),
                // The loading card hides the tools column itself.
                sidebarVisible: appState.navigation.showToolsPane && !appState.isLoadingDataset,
                inspectorVisible: appState.navigation.showInspectorPane,
                onSidebarCollapsed: { collapsed in
                    // A drag-collapse is the user hiding the column; the
                    // loading card's collapse is not reported back.
                    guard !appState.isLoadingDataset,
                          appState.navigation.showToolsPane == collapsed else { return }
                    appState.navigation.showToolsPane = !collapsed
                },
                onInspectorCollapsed: { collapsed in
                    guard appState.navigation.showInspectorPane == collapsed else { return }
                    appState.navigation.showInspectorPane = !collapsed
                }
            )
            // The hosted controller must take the window's size, not its
            // own intrinsic one (the sum of the column minimums, 610pt —
            // measured 2026-09-03 in a 1470pt window).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // D2 (owner decision, 2026-09-01): the permanent status footer —
            // status line, live operation progress with Cancel, and the
            // standing memory/cube facts. A STACKED element under every
            // column, so nothing can ever render behind it.
            Divider()
            StatusFooterView()
        }
        .navigationTitle("mac4DSTEM")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { appState.navigation.showToolsPane.toggle() }
                } label: {
                    Label("Toggle tools", systemImage: "sidebar.leading")
                }
                .help("Show or hide the tools panel")
            }
            if appState.navigation.workspaceArea != .results {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.navigation.showLogPane.toggle()
                    } label: {
                        Label("Toggle output", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help("Show or hide the output log below the image panes")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.navigation.showInspectorPane.toggle()
                } label: {
                    Label("Toggle inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector panel")
            }
        }
        .onChange(of: appState.virtualShape) {
            appState.commitApertureChange()
        }
        .onChange(of: appState.realSpaceShape) {
            appState.updateRealSpaceRegion()
        }
        .onChange(of: appState.realSpaceRadius) {
            appState.updateRealSpaceRegion()
        }
        .onChange(of: appState.openDatasetRequest) {
            showImporter = true
        }
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
                    // One importer, two destinations. `configureOnOpen` is set
                    // by whichever control opened it, so "Open Dataset…" keeps
                    // loading straight through and only "Open with options…"
                    // stops to ask (release owner, 2026-08-18).
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
            Button("Copy Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appState.errorMessage ?? "", forType: .string)
            }
            Button("Open Another…") {
                appState.errorMessage = nil
                appState.requestOpenDataset()
            }
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    /// The sidebar column: dataset card, workspaces, tasks and the workspace's
    /// own sidebar (one file each). One grouped `Form` on the column's own
    /// material (presentation contract rules 2 and 3, 2026-09-03): rows are
    /// system rows, text wraps at the column's width, and the list draws no
    /// ground of its own — the sidebar list's source-list colour resolved 90%
    /// opaque over AppKit's material (Gate D, `ColumnMaterialTests`).
    private var sidebarColumn: some View {
        Form {
            if let descriptor = appState.descriptor, descriptor.is4D {
                Section {
                    datasetCard(descriptor)
                }
                Section("Workspace") {
                    ForEach(WorkspaceArea.allCases) { area in
                        workspaceButton(area)
                    }
                    if let hint = ProductWorkflow.nextStepHint(
                        for: appState.navigation.workspaceArea,
                        readiness: appState.productWorkflowReadiness,
                        calibrationReady: appState.calibrationSession.readiness.isReady
                    ) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("workspace.nextStepHint")
                    }
                }
                if !appState.navigation.workspaceArea.analysisModes.isEmpty {
                    Section("Task") {
                        let groups = appState.navigation.workspaceArea.taskFamilyGroups
                        let showsLabels = appState.navigation.workspaceArea.showsTaskFamilyLabels
                        ForEach(groups) { group in
                            if showsLabels {
                                Text(group.family.groupLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier(
                                        "task.group.\(group.family.accessibilitySuffix)"
                                    )
                            }
                            ForEach(group.modes) { taskButton($0) }
                        }
                    }
                }
            }

            if !appState.hasDataset {
                Section("Dataset") {
                    Button {
                        appState.requestOpenDataset()
                    } label: {
                        Label("Open Dataset…", systemImage: "folder")
                    }
                }
            }

            if let descriptor = appState.descriptor, descriptor.is4D {
                // D3 (owner decision, 2026-09-01): the colormap and display
                // options live on the colorbar chips in the panes
                // (`ColormapChipMenu`), so no Display section here.
                // v2.5 step 7c: one sidebar per workspace, one file each
                // (plan §11d). This view only composes them.
                switch appState.navigation.workspaceArea {
                case .prepare: PrepareSidebar()
                case .image: ImageSidebar()
                case .map: MapSidebar()
                case .reconstruct: PhaseSidebar()
                case .results: ResultsSidebar()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Backlog #16: bounce only when there is something to scroll, so
        // elastic overscroll can never park the clip origin above the top.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The workspace column: header, the panes or Results, the log strip.
    private var workspaceColumn: some View {
        VStack(spacing: 0) {
        if appState.hasDataset && !appState.isLoadingDataset {
            ProductWorkspaceHeader()
        }

        Group {
        if appState.hasDataset && !appState.isLoadingDataset && appState.navigation.workspaceArea == .results {
            ResultsWorkspace()
        } else {
            VStack(spacing: 0) {
                Group {
                    if appState.hasDataset && !appState.isLoadingDataset {
                        imagePanes
                            .focusable()
                            .focusEffectDisabled()
                            .onKeyPress(phases: .down) { press in
                                handleArrowKey(press)
                            }
                    } else {
                        WelcomeWorkspace()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Output strip: rolling log of operations below the panes.
                if appState.navigation.showLogPane && appState.hasDataset && !appState.isLoadingDataset {
                    Divider()
                    logPane
                }
            }
            // The data pane's floor is the split item's
            // (`SplitViewPolicy.detailMinimum`), not a view frame:
            // a frame here fights the split view during a drag.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        }
        }
    }

    /// Rolling output log below the image panes (auto-scrolls to the latest).
    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(appState.logMessages.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: appState.logMessages.count) {
                proxy.scrollTo(appState.logMessages.count - 1, anchor: .bottom)
            }
        }
        // Presentation contract rule 3 (2026-09-03): no wash of its own; the
        // Divider above and the window's ground are the strip's whole look.
        .frame(height: 100)
    }

    /// Arrow keys step the selected scan position (Shift = 10 px steps).
    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        guard let d = appState.descriptor else { return .ignored }
        let step = press.modifiers.contains(.shift) ? 10 : 1
        var x = appState.selectedScan.x
        var y = appState.selectedScan.y
        switch press.key {
        case .leftArrow:  x -= step
        case .rightArrow: x += step
        case .upArrow:    y -= step
        case .downArrow:  y += step
        default: return .ignored
        }
        appState.selectScan(x: min(max(0, x), d.rx - 1),
                            y: min(max(0, y), d.ry - 1))
        return .handled
    }

    /// Accent border marking the active pane.
    private func paneFocusBorder(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(1)
            .allowsHitTesting(false)
    }

    /// The dataset card: name and extents as the row's label, the actions
    /// menu as its content, then the one verdict shared with the readiness
    /// checklist (v2.5 step 4b) and the saved-product count.
    @ViewBuilder
    private func datasetCard(_ descriptor: DatasetDescriptor) -> some View {
        let verdict = appState.calibrationSession.verdict
        LabeledContent {
            Menu {
                Button("Open Another…") { appState.requestOpenDataset() }
                // S22e: the configured open has a second door beside the
                // other dataset actions, not only ⌘N.
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
            .help("Dataset actions")
        } label: {
            Label {
                Text(descriptor.fileName)
                    .font(.headline)
            } icon: {
                Image(systemName: "circle.grid.cross.fill")
                    .foregroundStyle(Color.accentColor)
            }
            // Two lines, axis-labelled, in display order (v2 S18): one
            // wrapped line truncated its second axis pair at the default
            // width, which is the ambiguity these labels exist to remove.
            Text("\(descriptor.rx) × \(descriptor.ry) scan (Rx × Ry)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(descriptor.qx) × \(descriptor.qy) detector (Qx × Qy)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dataset \(descriptor.fileName)")
        .accessibilityIdentifier("dataset.card")

        LabeledContent("Calibration") {
            Label(
                verdict.quantitative ? "Quantitative" : "Not quantitative",
                systemImage: verdict.quantitative
                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
            .help(verdict.summary)
        }
        if !appState.sessionInventory.results.isEmpty {
            LabeledContent("Saved products", value: "\(appState.sessionInventory.results.count)")
        }
    }

    /// Diffraction left, real space right — always.
    ///
    /// #17a briefly made this axis follow the scan aspect (a 200×50 map fills
    /// far more of a wide, short pane). The release owner rejected it on sight:
    /// the side-by-side arrangement is part of what the app *is*, and having it
    /// change under a dataset is worse than an under-filled pane.
    private var imagePanes: some View {
        HSplitView {
            diffractionPane.frame(minWidth: 170)
            realSpacePane.frame(minWidth: 170)
        }
        // v2.5 step 7c: the pane with the ring claims the inspector's focus
        // whenever what these panes show changes (workspace or task).
        .onChange(of: appState.navigation.workspaceArea, initial: true) { claimPaneFocus() }
        .onChange(of: appState.navigation.analysisMode) { claimPaneFocus() }
    }

    private var diffractionPane: some View {
        DiffractionView()
            .overlay(paneFocusBorder(active: appState.activePane == .diffraction))
            .contentShape(Rectangle())
            .onTapGesture {
                appState.activePane = .diffraction
                claimPaneFocus()
            }
    }

    private var realSpacePane: some View {
        StemImageView()
            .overlay(paneFocusBorder(active: appState.activePane == .realSpace))
            .contentShape(Rectangle())
            .onTapGesture {
                appState.activePane = .realSpace
                claimPaneFocus()
            }
    }

    /// The pane with the focus ring names itself to the inspector
    /// (`FocusedPane`, plan §11g decision 3). `ActivePane` keeps its own job,
    /// the ROI direction.
    private func claimPaneFocus() {
        appState.navigation.focusedPane = FocusedPane.livePane(
            appState.activePane, in: appState.navigation.workspaceArea,
            task: appState.navigation.analysisMode
        )
    }

    private func workspaceButton(_ area: WorkspaceArea) -> some View {
        let selected = appState.navigation.workspaceArea == area
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectWorkspace(area)
            }
        } label: {
            LabeledContent {
                // A count as macOS sidebars carry one: a plain number.
                if area == .results && !appState.sessionInventory.results.isEmpty {
                    Text("\(appState.sessionInventory.results.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label(area.title, systemImage: area.systemImage)
                    .fontWeight(selected ? .semibold : .regular)
                // The subtitle names where you are; elsewhere it is on hover
                // and in the accessibility hint (2026-08-06 density pass).
                if selected {
                    Text(area.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .help(area.subtitle)
        .accessibilityLabel(area.title)
        .accessibilityIdentifier("workspace.\(area.rawValue)")
        .accessibilityHint(area.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func taskButton(_ mode: AnalysisMode) -> some View {
        let selected = appState.navigation.analysisMode == mode
        // Backlog #33 + R15: three states, matching the inspector's
        // "Computed this session" glyphs — orange ! blocked, empty circle
        // ready, green check produced this session.
        let unmet = taskUnmetCount(mode)
        let produced = taskHasProduct(mode)
        return Button {
            appState.changeMode(mode)
        } label: {
            LabeledContent {
                Image(systemName: produced
                        ? "checkmark.circle.fill"
                        : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                    .foregroundStyle(produced
                        ? Color.green
                        : (unmet == 0 ? Color.secondary : Color.orange))
            } label: {
                Label {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mode.productTitle).fontWeight(selected ? .semibold : .regular)
                        // S22c: only ptychography earns the advanced marker.
                        if mode.isAdvanced {
                            Text("Advanced").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: mode.systemImage)
                }
                if selected {
                    Text(mode.productSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .help(mode.productSubtitle)
        .accessibilityLabel(taskAccessibilityLabel(mode))
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func taskUnmetCount(_ mode: AnalysisMode) -> Int {
        ProductWorkflow.prerequisites(
            for: mode, readiness: appState.productWorkflowReadiness
        ).count
    }

    /// R15: whether this task has produced its product in this session —
    /// only for the tasks with an unambiguous retained product. Staleness is
    /// deliberately not folded in here; the result pane's own badge carries
    /// it (backlog #34).
    private func taskHasProduct(_ mode: AnalysisMode) -> Bool {
        switch mode {
        case .disks: appState.hasCurrentBraggVectors
        case .strain: appState.strain.map != nil
        case .acom: appState.acomSession.hasOrientationMap
        // R25 (owner, 2026-09-01): virtual imaging and DPC share the single
        // scalar result slot, so "has produced" is read from the recipe
        // record — it survives the slot being replaced and resets with the
        // dataset.
        case .virtualDetector:
            appState.replay.record.steps.contains { $0.kind == "virtual_detector" }
        case .dpc:
            appState.replay.record.steps.contains { $0.kind == "dpc" }
        case .ptychography, .singleslicePtychography: false
        }
    }

    /// Readiness is folded into the button's own label rather than left on the
    /// glyph: the button sets `accessibilityLabel`, which replaces its
    /// children's, so a label on the image alone would never be announced.
    private func taskAccessibilityLabel(_ mode: AnalysisMode) -> String {
        if taskHasProduct(mode) { return "\(mode.productTitle), computed" }
        let unmet = taskUnmetCount(mode)
        if unmet == 0 { return "\(mode.productTitle), ready" }
        return "\(mode.productTitle), \(unmet) requirement\(unmet == 1 ? "" : "s") missing"
    }

}
