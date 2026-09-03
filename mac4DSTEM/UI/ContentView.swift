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
        // Owner decision 2026-09-03: the columns are AppKit's
        // (`ColumnSplitController`), the way Xcode's are — the divider is
        // the only authority over a column's width and SwiftUI content
        // lays out inside it. See SplitViewPolicy.swift for why.
        //
        // Owner decision 2026-09-03 (late), superseding D2's "stacked under
        // every column": the split view is the window's whole content, so
        // all three columns run from under the toolbar to the bottom edge,
        // as Xcode's do. Nothing spans beneath them — the status bar is a
        // bottom bar INSIDE the workspace column, where Xcode puts its
        // debug bar and Finder its status bar.
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
        .navigationTitle("mac4DSTEM")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { appState.navigation.showToolsPane.toggle() }
                } label: {
                    Label(
                        appState.navigation.showToolsPane ? "Hide Tools" : "Show Tools",
                        systemImage: "sidebar.leading"
                    )
                }
                .help(appState.navigation.showToolsPane ? "Hide the tools panel" : "Show the tools panel")
            }
            if appState.navigation.workspaceArea != .results {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.navigation.showLogPane.toggle()
                    } label: {
                        Label(
                            appState.navigation.showLogPane ? "Hide Output" : "Show Output",
                            systemImage: "rectangle.bottomthird.inset.filled"
                        )
                    }
                    .help(appState.navigation.showLogPane ? "Hide the output log" : "Show the output log")
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
                .help(appState.navigation.showInspectorPane ? "Hide the inspector panel" : "Show the inspector panel")
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
        // Navigation is a source list, the workspace's controls are a
        // grouped Form, and one column holds both — split vertically by a
        // draggable divider, the way Xcode stacks areas inside a column.
        // Both halves are scroll views, so neither a VStack nor
        // `.layoutPriority` can share the height between them: whichever was
        // favoured took the whole column and the other rendered at zero
        // height (both directions measured on screen, 2026-09-03).
        //
        // The two containers are not interchangeable. `LabeledContent` only
        // stacks a multi-element label vertically inside a Form; in a List
        // row it lays out horizontally, which crushed every calibration row
        // onto one line ("Origin & p… Origin: From fi… From file", measured).
        // The `.sidebar` List does not offer its rows a width, so a long text
        // takes its one-line ideal and truncates; publishing the column's
        // real width is what lets `.sidebarWrapped()` trade width for lines
        // (`SidebarTextWidth.swift`). Deleted by UI rework step 2e on the
        // theory that a grouped Form made it unnecessary — it did, and the
        // Form cost the source list instead. The 34pt covers the row insets.
        GeometryReader { columnGeometry in
            navigationList
                .environment(
                    \.sidebarTextWidth, max(columnGeometry.size.width - 34, 216)
                )
        }
    }

    /// The navigation half of the tools column: what dataset is open, which
    /// workspace, which task. Selection, hover and row metrics are the
    /// source list's.
    private var navigationList: some View {
        List(selection: sidebarSelection) {
            if let descriptor = appState.descriptor, descriptor.is4D {
                Section {
                    datasetCard(descriptor)
                }
                Section("Workspace") {
                    ForEach(WorkspaceArea.allCases) { area in
                        workspaceRow(area).tag(SidebarSelection.workspace(area))
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
                            ForEach(group.modes) { mode in
                                taskRow(mode).tag(SidebarSelection.task(mode))
                            }
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
        // A navigation column is a source list, not a settings pane. The
        // grouped `Form` this replaces (UI rework step 2a) had no
        // `selection:` parameter at all, so the selected workspace could
        // only be drawn by tinting its text — no row capsule, no hover, no
        // arrow-key row navigation, no `AXOutlineRow`, and no row recycling.
        // `.listStyle(.sidebar)` is what Finder, Mail, Notes, Shortcuts and
        // System Settings' own left column use.
        .listStyle(.sidebar)
        // One material per column, and it is AppKit's. The sidebar item
        // already paints the system material behind the whole column,
        // including the strip beside the traffic lights; a `.sidebar` List
        // paints a second one inside the scroll view, which starts below the
        // titlebar inset. Stacked, the two composite differently where only
        // one of them shows, so the column changed colour at the top (owner,
        // 2026-09-03) — and `ColumnMaterialTests` fails on the duplicate.
        // Hiding the scroll background costs nothing visible: the row
        // selection capsule is drawn by the table, not by this background.
        .scrollContentBackground(.hidden)
        // Backlog #16: bounce only when there is something to scroll, so
        // elastic overscroll can never park the clip origin above the top.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// One selection for the whole source list. A workspace with tasks is
    /// represented by its selected task (the way selecting a file, not its
    /// folder, is what highlights in Xcode's navigator); a workspace without
    /// tasks — Prepare, Results — is selected in its own right.
    private enum SidebarSelection: Hashable {
        case workspace(WorkspaceArea)
        case task(AnalysisMode)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
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
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.selectWorkspace(area)
                    }
                case .task(let mode):
                    appState.changeMode(mode)
                case nil:
                    break
                }
            }
        )
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

                // Output strip: rolling log of operations below the panes,
                // its top edge a drag handle.
                if appState.navigation.showLogPane && appState.hasDataset && !appState.isLoadingDataset {
                    logResizeHandle
                    logPane
                }
            }
            // The data pane's floor is the split item's
            // (`SplitViewPolicy.detailMinimum`), not a view frame:
            // a frame here fights the split view during a drag.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        }

        // D2's content (status line, live progress with Cancel, the standing
        // memory/cube facts) in Xcode's place for it: a bottom bar INSIDE
        // this column. Under all three columns it stopped the sidebar and
        // inspector reaching the window's bottom edge, which is the one
        // thing every Mac three-column window does (owner, 2026-09-03 late).
        Divider()
        StatusFooterView()
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
        //
        // Resizable, as Xcode's debug area is (owner, 2026-09-03): the height
        // is dragged on the divider above and remembered for the session.
        // `WindowPolicy.outputStripHeight` is now only where it opens.
        .frame(height: logHeight)
    }

    /// The output strip's dragged height. A `VSplitView` cannot divide the
    /// panes from the log — both are greedy, so it splits them evenly and the
    /// panes lose half the window — so the divider carries the drag itself.
    @State private var logHeight: CGFloat = WindowPolicy.outputStripHeight

    /// The log's top edge, draggable like a split divider.
    private var logResizeHandle: some View {
        Divider()
            .background(Color.clear)
            .contentShape(Rectangle().inset(by: -SplitViewPolicy.dividerGrabWidth / 2))
            .onHover { inside in
                // The cursor names the affordance; without it the divider
                // reads as decoration.
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Up is negative in SwiftUI's coordinate space, and
                        // the strip grows upward.
                        logHeight = min(max(60, logHeight - value.translation.height), 600)
                    }
            )
            .accessibilityLabel("Resize the output log")
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
            diffractionPane.frame(minWidth: 170)   // science: the pane floor
            realSpacePane.frame(minWidth: 170)     // science: the pane floor
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

    /// A source-list row: a `Label`, and a count as macOS carries one — a
    /// `.badge`, which hides itself at zero. Selection, hover, the row
    /// capsule and the `AXOutlineRow` role all come from the List; nothing
    /// here draws them. The subtitle that used to appear under the selected
    /// row is gone: `ProductWorkspaceHeader` prints the same sentence,
    /// larger, a few points to its right.
    private func workspaceRow(_ area: WorkspaceArea) -> some View {
        Label(area.title, systemImage: area.systemImage)
            .badge(area == .results ? appState.sessionInventory.results.count : 0)
            .help(area.subtitle)
            .accessibilityLabel(area.title)
            .accessibilityIdentifier("workspace.\(area.rawValue)")
            .accessibilityHint(area.subtitle)
    }

    private func taskRow(_ mode: AnalysisMode) -> some View {
        // Backlog #33 + R15: three states, matching the inspector's
        // "Computed this session" glyphs — orange ! blocked, empty circle
        // ready, green check produced this session. It is the row's trailing
        // accessory, which in a source list is where a status glyph goes.
        let unmet = taskUnmetCount(mode)
        let produced = taskHasProduct(mode)
        return LabeledContent {
            Image(systemName: produced
                    ? "checkmark.circle.fill"
                    : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                .foregroundStyle(produced
                    ? Color.green
                    : (unmet == 0 ? Color.secondary : Color.orange))
        } label: {
            Label {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mode.productTitle)
                    // S22c: only ptychography earns the advanced marker.
                    if mode.isAdvanced {
                        Text("Advanced").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: mode.systemImage)
            }
        }
        .help(mode.productSubtitle)
        .accessibilityLabel(taskAccessibilityLabel(mode))
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
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
