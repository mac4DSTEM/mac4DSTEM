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
        @Bindable var appState = appState
        return NavigationSplitView(columnVisibility: Binding(
            get: {
                appState.navigation.showToolsPane && !appState.isLoadingDataset ? .all : .detailOnly
            },
            set: { appState.navigation.showToolsPane = $0 != .detailOnly }
        )) {
            // S22d: publish the column's real width so long sidebar texts can
            // wrap — this List never offers rows a width on its own (see
            // SidebarTextWidth.swift). The 34pt covers the row insets.
            GeometryReader { sidebarGeo in
            List {
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
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .sidebarWrapped()
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
                                        .font(.caption2)
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
                        Label(appState.hasDataset ? "Open Another…" : "Open Dataset…",
                              systemImage: "folder")
                    }
                    }
                }

                if let descriptor = appState.descriptor, descriptor.is4D {
                    // D3 (owner decision, 2026-09-01): the colormap and
                    // display options moved ONTO the colorbar chips in the
                    // panes (`ColormapChipMenu`). That dissolves the old
                    // Results-scoping problem this sidebar section spent a
                    // long comment justifying: the chip exists wherever its
                    // image exists, so the control can never be stranded in a
                    // workspace without it.

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
            .listStyle(.sidebar)
            .environment(
                \.sidebarTextWidth, max(sidebarGeo.size.width - 34, 216)
            )
            // Backlog #16. The symptom (sidebar rows drawn across the traffic
            // lights, top rows inert because the titlebar hit-tests above them)
            // is the sidebar scroll view sitting at clip origin 0 instead of
            // -contentInsets.top — i.e. scrolled one titlebar-height past its
            // own top. Measured: docTopInWindow 923 instead of 871 in a
            // 923pt window with a 52pt titlebar. Elastic overscroll at the top
            // is the remaining candidate for how it gets there, so bouncing is
            // limited to the case where there is genuinely something to scroll.
            .scrollBounceBehavior(.basedOnSize)
            }
            // These sit on the COLUMN'S ROOT VIEW (the GeometryReader), not on
            // the List inside it — attached inside the wrapper, the width
            // declaration stopped reaching NavigationSplitView and the owner
            // dragged the sidebar to ~750pt and ~175pt on 2026-09-01 (S22
            // feedback R1/R2). AppKit-side enforcement is in
            // SplitViewWidthClamp, because the declaration alone has already
            // failed twice (the 144pt restore; the 625pt drag on the PRE-S22
            // build in the owner's original screenshots). Do not add a hard
            // `.frame(minWidth:)` here: live divider drags can make SwiftUI and
            // AppKit re-enter window constraint updates until AppKit raises
            // NSGenericException.
            .navigationTitle("mac4DSTEM")
            .navigationSplitViewColumnWidth(min: 250, ideal: 292, max: 340)
            .toolbar(removing: .sidebarToggle)
        } detail: {
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
                    // Soft floor so the sidebar and inspector cannot crush the
                    // image panes into distorted slivers — the 2026-08-05
                    // clipped-edges class, finally captured on screen
                    // 2026-09-01 (open-items, owner playthrough item 4).
                    .frame(minWidth: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                }
                // A REAL system inspector column (S22a): draggable to
                // 560pt, collapsible, system-animated. The previous
                // hand-rolled HStack member (fixed 220–340pt frame, no
                // drag handle) was the direct cause of "the right panel
                // cannot be resized" and half of the clipped-edges layout
                // regime above. One column for every workspace, Results
                // included; which inspector it holds follows the focused
                // pane (v2.5 step 7c).
                .inspector(isPresented: Bindable(appState.navigation).showInspectorPane) {
                    WorkspaceInspector()
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 560)
                }
                // D2 (owner decision, 2026-09-01): the permanent status
                // footer — status line, live operation progress with Cancel,
                // and the standing memory/cube facts. A STACKED element, not
                // a floating inset (R18/R19): the inset version drew over the
                // log strip's tail and over Results' own export/save row —
                // stacked, nothing can ever render behind it.
                Divider()
                StatusFooterView()
            }
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
        }
        .onAppear {
            // S22d: after AppKit state restoration, clamp a sidebar restored
            // below its declared 250pt minimum (the standing 144pt-restore
            // Track B finding). Deferred one runloop turn so restoration has
            // finished laying out.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.isVisible {
                    SplitViewWidthClamp.enforceSidebarMinimum(in: window)
                }
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
        .frame(height: 100)
        .background(Color.black.opacity(0.15))
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

    private func datasetCard(_ descriptor: DatasetDescriptor) -> some View {
        // v2.5 step 4b: the one verdict, shared with the readiness checklist.
        let verdict = appState.calibrationSession.verdict
        let coreCalibrated = verdict.quantitative
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    // Axis-labelled on purpose (v2 S18). This line and the
                    // dataset inspector print the same two extents in
                    // OPPOSITE orders — here in display order (across x down),
                    // there in array order as `Scan (Ry x Rx)` beside a
                    // `Shape` row of `ry x rx x qy x qx`. Each is right for
                    // where it sits: the number beside an image should read
                    // the way the image draws, and a row labelled with its own
                    // axes should read the way the array is indexed. What made
                    // it a defect is that this one carried no labels, so the
                    // two contradicted each other on screen with nothing to
                    // reconcile them — the same shape as the readiness row
                    // that disagreed with its own detail line on tag day.
                    // TWO lines, not one wrapped line. The single-line version
                    // truncated at the default sidebar width — it rendered
                    // `12 × 12 scan (Rx × Ry)  ·  64 × 64 detector (…`, so the
                    // `(Qx × Qy)` half never appeared and the card labelled one
                    // axis pair while silently dropping the other. That is the
                    // exact ambiguity this line exists to remove, so a
                    // truncation here is not cosmetic.
                    //
                    // `.fixedSize(horizontal: false, vertical: true)` was tried
                    // first and did NOT fix it — verified on screen, not
                    // assumed. Splitting the string is structural: neither line
                    // is long enough to truncate at any sidebar width the app
                    // allows (min 250pt, `:970`).
                    //
                    // Found by driving the app 2026-08-27. `unit` was green
                    // throughout, including `SidebarLayoutTests`, because those
                    // measure document height and column fit and truncation
                    // changes neither.
                    Text("\(descriptor.rx) × \(descriptor.ry) scan (Rx × Ry)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(descriptor.qx) × \(descriptor.qy) detector (Qx × Qy)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Open Another…") { appState.requestOpenDataset() }
                    // S22e: with a dataset loaded, ⌘N used to be the ONLY
                    // route back to the configured open (Track B drive
                    // finding, 2026-09-01) — the second door now also exists
                    // where the other dataset actions live.
                    Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
                    Button("Preprocess & Export…") { showPreprocessingExport = true }
                        .disabled(appState.isBusy)
                    Divider()
                    Button("Save Calibration") {
                        appState.saveCalibrationToSessionSidecar()
                    }
                    .disabled(appState.isBusy)
                    Button("Export Diffraction PNG…") {
                        appState.exportDiffractionImage()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Dataset actions")
            }

            HStack(spacing: 6) {
                Label(
                    coreCalibrated ? "Quantitative" : "Not quantitative",
                    systemImage: coreCalibrated
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .foregroundStyle(coreCalibrated ? Color.green : Color.orange)
                .help(verdict.summary)
                Spacer()
                if !appState.sessionInventory.results.isEmpty {
                    Text("\(appState.sessionInventory.results.count) saved")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dataset \(descriptor.fileName)")
        .accessibilityIdentifier("dataset.card")
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
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectWorkspace(area)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: area.systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(area.title)
                            .font(.subheadline.weight(
                                appState.navigation.workspaceArea == area ? .semibold : .regular
                            ))
                        // S22c: the ADV marker moved from the workspace to
                        // the one task that earns it (ptychography) — with
                        // DPC in Phase, a workspace-level badge would mark
                        // an everyday analysis as advanced.
                    }
                    // The subtitle stands down once you are past needing it.
                    // It described all five areas permanently, which cost 63pt
                    // of an 871pt column to answer a question asked once. It is
                    // still on the selected row (where it names where you are),
                    // on hover via `help`, and in `accessibilityHint` — so the
                    // fact is demoted, never deleted.
                    if appState.navigation.workspaceArea == area {
                        Text(area.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if area == .results && !appState.sessionInventory.results.isEmpty {
                    Text("\(appState.sessionInventory.results.count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.navigation.workspaceArea == area ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .help(area.subtitle)
        .accessibilityLabel(area.title)
        .accessibilityIdentifier("workspace.\(area.rawValue)")
        .accessibilityHint(area.subtitle)
        .accessibilityAddTraits(appState.navigation.workspaceArea == area ? .isSelected : [])
    }

    private func taskButton(_ mode: AnalysisMode) -> some View {
        Button {
            appState.changeMode(mode)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(mode.productTitle)
                            .font(.subheadline.weight(appState.navigation.analysisMode == mode ? .semibold : .regular))
                        if mode.isAdvanced {
                            Text("ADV")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Same rule as `workspaceButton`: on the selected row, on
                    // hover, and in the accessibility hint — not permanently on
                    // every row. See that comment for the reasoning.
                    if appState.navigation.analysisMode == mode {
                        Text(mode.productSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // Backlog #33 + R15 (2026-09-01). Three states, matching the
                // inspector's "Computed this session" glyphs exactly:
                // orange ! = blocked; empty circle = ready but nothing
                // produced; green check = this task HAS produced its product
                // this session. #33 removed the green check for merely-READY
                // because ready≠done was misread; done-as-check is that
                // list's own meaning, so the ambiguity does not return. The
                // owner hit the missing third state on 2026-09-01: 83,929
                // peaks landed and the circle stayed empty.
                let unmet = taskUnmetCount(mode)
                let produced = taskHasProduct(mode)
                Image(systemName: produced
                        ? "checkmark.circle.fill"
                        : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                    .font(.caption)
                    .foregroundStyle(produced
                        ? Color.green
                        : (unmet == 0 ? Color.secondary : Color.orange))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.navigation.analysisMode == mode ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .help(mode.productSubtitle)
        .accessibilityLabel(taskAccessibilityLabel(mode))
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
        .accessibilityAddTraits(appState.navigation.analysisMode == mode ? .isSelected : [])
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
