import ShellControls
import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import ShellEDXModel
import ShellSpectroscopy

/// The detail column: the science, and the infobar + process area along its bottom edge. The column's chassis (the
/// divider, its drag, the infobar, the process area and their scene-stored fractions) is ShellLayout's `WorkspaceColumn`
/// (suite task 8, MacEMUI); what stays here is what the canvas shows (the room switch, welcome, loading, the 4D panes, scan
/// stepping) and the words of the run readout, the last run and the glance.
///
/// **There is no workspace header.** The old `ProductWorkspaceHeader`
/// repeated the sidebar row's own title and cost about 100 pt off the top of
/// both panes; the phase-1 breadcrumb row repeated it again at 34 pt.
/// Readiness has exactly one owner — the inspector's Settings tab.
struct WorkspaceView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        WorkspaceColumn(
            navigation: appState.navigation.panels,
            tabs: ProcessTabs.all(activityLog: appState.activityLog),
            // A dataset that is absent or still loading forces the process area shut regardless of the dragged fraction,
            // which is NOT reset for it: reopening the same dataset restores the same split.
            hasDocument: appState.hasDataset && !appState.datasetSession.isLoading,
            statusText: appState.statusText,
            isRunning: showsOperationProgress,
            canvas: { content },
            run: { runSlot },
            glance: { glanceSlot })
    }

    /// Whether the infobar draws the live run. `isBusy` alone was not the right question: during a dataset OPEN it is true
    /// with no metrics and no Cancel, beside a loading column that has its own spinner and Cancel. A load that has started
    /// an analysis inside its bracket still qualifies, because that pass is cancellable.
    private var showsOperationProgress: Bool {
        appState.isBusy && (!appState.datasetSession.isLoading || appState.activeOperation != nil)
    }

    /// The run's numbers while one is in flight (the bar, done / total, the rate, elapsed · ETA and Stop), the last run while idle
    /// (owner decision: the Run tab's numbers belong in the bar).
    @ViewBuilder
    private var runSlot: some View {
        if showsOperationProgress {
            InfobarRunReadout(
                operation: appState.activeOperation,
                progress: appState.progress,
                line: { date in
                    OperationMetricsFormat.runLine(
                        done: appState.operationCenter.unitsDone,
                        total: appState.operationCenter.totalUnits,
                        metrics: appState.activeOperationMetrics(at: date),
                        for: appState.activeOperation)
                },
                onCancel: appState.canCancelActiveOperation ? { appState.cancelActiveOperation() } : nil)
        } else if let last = appState.operationCenter.lastFinished {
            InfobarLastRun(OperationMetricsFormat.lastRun(last.name, elapsed: last.elapsed, cancelled: last.outcome == .cancelled))
        }
    }

    /// The standing facts: the engine, app memory and whether the cube is resident or streamed.
    private var glanceSlot: some View {
        InfobarGlance {
            OperationMetricsFormat.glance(
                engine: SystemMonitor.gpuName,
                residentMB: SystemMonitor.residentMemoryMB() * 1.048576,
                residency: appState.residency.isResident)
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.datasetSession.isLoading {
            loadingState
        } else if !appState.hasDocument {
            WelcomeWorkspace()
        } else if appState.navigation.workspaceArea == .spectroscopy {
            // The EDS room: MacEMUI's shared room, with mac4DSTEM's 4D links (`AppState+EDS`).
            EDXRoom(session: appState.edx, state: appState.edxRoom, actions: appState.edxActions,
                    openExtensions: EDXOpening.readableExtensions)
        } else if appState.isSpectrumOnly {
            // A spectrum image and no cube: Results has nothing of the 4D
            // kind to review, and a 4D room is withheld (`isWorkspaceWithheld`).
            if appState.navigation.workspaceArea == .results {
                SpectrumOnlyResultsPlaceholder()
            } else {
                FourDRoomUnavailable()
            }
        } else if appState.navigation.workspaceArea == .results {
            ResultsWorkspace()
        } else {
            // Two scientific panes, side by side, with a divider the user
            // owns. NOT `HSplitView` — see `PaneSplit` for the crash that
            // ruled it out.
            PaneSplit(resizeLabel: "Resize the diffraction and real-space panes", leadingName: "Diffraction pane") {
                DiffractionPane()
            } trailing: {
                RealSpacePane()
            }
            // Arrow keys step the selected scan position (Shift = 10 px),
            // carried over from the old workspace column. A pane that
            // handles the key itself consumes it before this sees it.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { handleArrowKey($0) }
        }
    }

    // MARK: - Opening a dataset

    /// The open is the longest uninterruptible wait in the product, so it
    /// gets the whole column: what phase is running, how far it has got where
    /// that is a real fraction, and the way out.
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading dataset")
                .font(.headline)
            // Two lines: the measured phase reports patterns AND bytes, and
            // middle-truncating would cut them.
            Text(appState.datasetSession.loadingStatus ?? "Opening dataset…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
            // A determinate bar only where the denominator is real:
            // `datasetSession.loadingProgress` is nil during phases whose duration is
            // not known, and a fake bar there would be a lie about the wait.
            if let progress = appState.datasetSession.loadingProgress {
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
            if appState.datasetSession.canCancelLoad {
                Button("Cancel") { appState.cancelDatasetLoad() }
                    .accessibilityIdentifier("welcome.cancelDatasetLoad")
                    .accessibilityHint("Stops loading this dataset and returns to the welcome screen")
            }
        }
        .frame(maxWidth: LayoutPolicy.readableWidth)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.loadingStatus")
    }

    // MARK: - Keyboard

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
}

// MARK: - The toolbar's room actions

/// Row 8c of the Velox sheet (ADR 058): "Preprocess Raw Data…" writes a reduced 4D cube, so a window that holds a spectrum
/// image and no cube does not offer it. Open Dataset… and Open with Options… always stay: they are the way out of such a
/// window. Pure, so it is tested (`ShellGlassTests`); the File menu asks the same question (`DatasetCommands`).
enum DatasetMenuRule {
    static func showsPreprocessRawData(hasSpectrumImage: Bool, hasCube: Bool) -> Bool {
        !(hasSpectrumImage && !hasCube)
    }

    /// The same question asked of a window: the flags the Spectroscopy room itself reads (`isSpectrumOnly`).
    @MainActor static func showsPreprocessRawData(in appState: AppState) -> Bool {
        showsPreprocessRawData(hasSpectrumImage: appState.hasSpectrumImage, hasCube: appState.hasDataset)
    }
}

/// The window-level dataset switcher in the standard toolbar.
struct DatasetMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            Button("Open Dataset…") { appState.requestOpenDataset() }
            Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
            // X3 (owner-accepted mock 2026-10-01): beside Open with Options, with or without a dataset — except in a
            // spectrum-only window (row 8c).
            if DatasetMenuRule.showsPreprocessRawData(in: appState) {
                Button("Preprocess Raw Data…") { appState.requestPreprocessRawData() }
                    .disabled(appState.isBusy)
            }
            if appState.hasDataset {
                Divider()
                Button("Export Diffraction PNG…") { appState.exportDiffractionImage() }
                    .disabled(appState.displayedPattern == nil)
            }
        } label: {
            // The dataset menu uses the cube stack the sidebar already uses.
            Label("Dataset", systemImage: "square.stack.3d.up")
        }
        .help("Open a dataset, or act on the one that is open")
        .accessibilityIdentifier("toolbar.datasetMenu")
    }
}

// MARK: - The one action that runs the task

/// The toolbar's verb, as the shell's plain `PrimaryAction` value (suite task 8): the title, hint, enablement and run logic stay here,
/// the button, its glass styles and Cancel are ShellLayout's `PrimaryActionButton`.
///
/// Titles, hints and enablement follow the parallax staging rule that gates only `.ptychography` and the `ProductWorkflow.readiness`
/// check the checklist and the replay executor ask the same question of. When the action is disabled by an unmet requirement, the
/// help names the first one, so the disabled state explains itself without a second readiness surface.
struct WorkspacePrimaryAction {
    let appState: AppState

    /// The value for the toolbar, or nil when the verb does not apply: the header only ever existed while a dataset was open and
    /// settled, so the toolbar item follows the same rule and the load's own progress (centre column) is never shadowed by a second
    /// bar up here.
    @MainActor
    static func current(_ appState: AppState) -> PrimaryAction? {
        let this = WorkspacePrimaryAction(appState: appState)
        guard (appState.hasDataset || this.isSpectroscopyWithImage) && !appState.datasetSession.isLoading else { return nil }
        return PrimaryAction(
            title: this.primaryActionTitle,
            isEnabled: this.primaryActionEnabled,
            help: this.helpText,
            hint: this.primaryActionHint,
            isRunning: appState.isBusy,
            operationName: appState.activeOperation ?? appState.statusText,
            stop: appState.canCancelActiveOperation ? { appState.cancelActiveOperation() } : nil,
            run: { this.runPrimaryAction() })
    }

    /// The hint, unless a requirement is what is holding the action back —
    /// then the requirement, because that is the question the user has.
    private var helpText: String {
        if appState.navigation.workspaceArea == .spectroscopy, !primaryActionEnabled, let why = appState.edx.quantifyBlocker { return why }
        if !primaryActionEnabled, let first = appState.unmetRequirements.first {
            return first.title
        }
        return primaryActionHint
    }

    /// The Spectroscopy room's one verb (ADR 054 item 8). It records a replay
    /// step once WP3 builds the quantification; until then it is shown and
    /// disabled, with the reason on hover.
    static let spectroscopyActionTitle = "Quantify"

    private var primaryActionTitle: String? {
        switch appState.navigation.workspaceArea {
        case .prepare:
            if !appState.calibrationSession.calibration.hasFittedOrigin { "Calibrate Origin" }
            else if !appState.calibrationSession.calibration.hasRotation { "Measure R–Q Rotation" }
            else { nil }
        case .image:
            Self.imagingActionTitle(for: appState.navigation.analysisMode)
        case .braggDisks:
            "Detect All Disks"
        case .map:
            switch appState.navigation.analysisMode {
            case .strain: "Compute Strain"
            case .acom: appState.acomSession.primaryActionTitle
            case .phaseMapping: "Map Phases"
            default: nil
            }
        case .reconstruct:
            if appState.navigation.analysisMode == .dpc {
                // S7(a): once a DPC step is in the replay record (the same
                // test the sidebar's task checkmark uses) the verb is "Re-run".
                Self.dpcActionTitle(hasRun: appState.replay.record.steps.contains { $0.kind == "dpc" })
            }
            else if appState.navigation.analysisMode == .singleslicePtychography { "Reconstruct Object" }
            else if appState.phaseContrast.parallaxPreprocess == nil { "Prepare Preview" }
            else if appState.phaseContrast.parallaxAlignment?.isComplete != true { "Align Next Level" }
            else if appState.phaseContrast.parallaxHigherOrderFit == nil { "Fit Aberrations" }
            else if appState.phaseContrast.parallaxCorrection == nil { "Correct Phase" }
            else if !parallaxStage4IsComplete(appState.phaseContrast) { "Upsample BF" }
            // C4(a): every parallax stage is complete — readiness is already
            // shown by the stage checklist's own checkmarks
            // (`ParallaxStageSections`), so the toolbar offers no button
            // rather than a permanently disabled "Reconstruction Ready" one.
            else { nil }
        case .spectroscopy:
            appState.hasSpectrumImage ? Self.spectroscopyActionTitle : nil
        case .results:
            nil
        }
    }

    static func dpcActionTitle(hasRun: Bool) -> String { hasRun ? "Re-run DPC" : "Run DPC" }

    /// Imaging's verb: Group Patterns keeps its own, the virtual detector's is "Compute Image" — back on the owner's word
    /// (2026-10-07; lane F had removed it on 2026-10-04 because the live image already runs on every aperture edit, and the
    /// owner wants the button). `AppState.hasPrimaryWorkspaceTask` (⌘R, ⌘↩) is true for both modes.
    static func imagingActionTitle(for mode: AnalysisMode) -> String {
        mode == .diffractionGroups ? "Group Patterns" : "Compute Image"
    }

    private var primaryActionHint: String {
        switch appState.navigation.workspaceArea {
        case .prepare:
            appState.calibrationSession.calibration.hasFittedOrigin
                ? "Solves scan-to-detector rotation for quantitative vector output."
                : "Fits the unscattered-beam origin across the scan."
        case .image:
            appState.navigation.analysisMode == .diffractionGroups
                ? "Runs PCA and k-means over every scan position's diffraction pattern."
                : "Runs the selected imaging task with the current settings."
        case .braggDisks: "Detects Bragg disks at every scan position with the current settings."
        case .map:
            switch appState.navigation.analysisMode {
            case .acom: "Runs the orientation area and quality selected in the inspector."
            case .phaseMapping: "Matches every position's peaks against the phases you named."
            default: "Runs the selected whole-scan mapping task."
            }
        case .reconstruct:
            switch appState.navigation.analysisMode {
            case .dpc: "Maps beam deflection across the scan and integrates projected phase."
            case .singleslicePtychography: "Runs the iterative single-slice reconstruction on the full datacube."
            default: "Runs the next incomplete parallax stage."
            }
        case .spectroscopy: "Fits the selected region's pooled spectrum with the Quantify settings and records the step; the fit then follows every setting."
        case .results: ""   // no verb here (`primaryActionTitle` is nil), so no hint is ever read
        }
    }

    /// The Spectroscopy room with a spectrum image open — the one place the
    /// verb shows without a 4D cube.
    private var isSpectroscopyWithImage: Bool {
        appState.navigation.workspaceArea == .spectroscopy && appState.hasSpectrumImage
    }

    private var primaryActionEnabled: Bool {
        // Quantify (v5.0 R3) needs a spectrum image and an element, not a 4D cube (`AppState.canRunPrimaryWorkspaceTask` agrees).
        if appState.navigation.workspaceArea == .spectroscopy { return !appState.isBusy && appState.canRunPrimaryWorkspaceTask }
        guard appState.hasDataset, !appState.isBusy else { return false }
        if appState.navigation.workspaceArea != .prepare && appState.navigation.workspaceArea != .results {
            // The same answer the checklist and replay get.
            guard case .ready = ProductWorkflow.readiness(
                for: appState.navigation.analysisMode,
                readiness: appState.productWorkflowReadiness
            ) else { return false }
        }
        // C4(a): the parallax-complete special case that lived here is gone
        // with "Reconstruction Ready" — `primaryActionTitle` is nil in
        // exactly that state, so no button reaches this at all, and every
        // reachable parallax title already implies the chain is unfinished.
        return true
    }

    private func runPrimaryAction() {
        PendingEdits.run { await appState.runPrimaryWorkspaceTask() }
    }
}

// MARK: - No dataset open

/// The empty window: the mark and the doors.
///
/// The three "Prepare / Analyze / Preserve" cards the old welcome carried are
/// gone — brochure copy above the fold, describing the sidebar the user is
/// already looking at — and so are its tagline and subtitle (owner rule: no
/// filler; UI audit 2026-10-14, G5). What survives is what a first run needs: a
/// way in, and the one piece of guidance a user cannot infer (a network source
/// costs minutes on every whole-cube pass).
struct WelcomeWorkspace: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    entryPoints
                    // Guidance, not a warning: analyses stream the whole cube,
                    // so a network source costs minutes on every pass
                    // (measured ~3.3 MB/s over a NAS, latency-dominated).
                    Label(
                        "Work from a local disk. Datasets opened over a network share stream far more slowly on every whole-cube pass.",
                        systemImage: "internaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: LayoutPolicy.readableWidth)
                    .accessibilityIdentifier("welcome.localStorageNotice")
                }

                if !appState.recents.entries.isEmpty {
                    recents
                        .frame(maxWidth: LayoutPolicy.readableWidth)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
    }

    /// One row when the centre column has room, otherwise one column of
    /// equal-width buttons — never "Open Dat…" at the window's minimum
    /// width, the launch state (driven, 2026-09-22).
    private var entryPoints: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { entryButtons }
            VStack(spacing: 8) { entryButtons }
                .buttonSizing(.flexible)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var entryButtons: some View {
        Button("Open Dataset…") { appState.requestOpenDataset() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(appState.isBusy)
        // The configured open is a SECOND door, not a mode on the first.
        Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
            .controlSize(.large)
            .disabled(appState.isBusy)
            .help("Preview the dataset and choose a crop or binning before loading")
            .accessibilityIdentifier("welcome.openWithOptions")
        if appState.recoveryRecord != nil {
            Button("Reopen Last Dataset") { appState.reopenLastDataset() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(appState.isBusy)
        }
        Button("Try Demo Data") {
            PendingEdits.run { await appState.openDemoFixture() }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(appState.isBusy)
        .help("The demo is a small synthetic 4D-STEM dataset — every workspace works, and nothing on disk is touched.")
        .accessibilityIdentifier("welcome.demoButton")
    }

    private var recents: some View {
        // Stored on the seam and recomputed only on mutation, so the O(n²)
        // disambiguation never runs during a redraw.
        let locations = appState.recents.locationLabels
        return GroupBox("Recent datasets") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(appState.recents.entries.prefix(5)) { recent in
                    recentRow(recent, location: locations[recent.id])
                }
            }
            .padding(4)
        }
    }

    private func recentRow(_ recent: RecentDataset, location: String?) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.openRecent(recent)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.tint)
                    // NAME AND LOCATION: the name alone is not an identifier
                    // — two copies of one cube rendered as identical rows.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recent.displayName)
                        if let location {
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(location.map { "\(recent.displayName), on \($0)" } ?? recent.displayName)
            .accessibilityHint("Reopens this dataset and its saved session")

            Button {
                appState.removeRecent(recent)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove from Recents")
            .accessibilityLabel("Remove \(recent.displayName) from Recents")
        }
    }
}

// MARK: - Keeping a result

/// "Save to Session", in the toolbar beside Reveal (owner decision): always
/// available, from any workspace, so a virtual image or a strain map can be
/// kept without leaving the workspace that made it, and it stays reachable
/// with both side panels hidden. The action is the same one Results calls —
/// one writer, one sidecar — and the destination is the session sidecar,
/// from which Results reads it.
struct SaveResultButton: View {
    @Environment(AppState.self) private var appState

    private var saveReason: String? {
        ResultsActionReason.saveToSession(
            isLoading: appState.datasetSession.isLoading, hasDisplayedProduct: appState.displayedProduct != nil,
            isBusy: appState.isBusy, sidecarRefusal: appState.gates.sidecarRewriteRefusal())
    }

    var body: some View {
        if appState.hasDataset, appState.navigation.workspaceArea != .results {
            Button {
                appState.saveCurrentResultToSessionSidecar()
            } label: {
                Label("Save to Session", systemImage: "archivebox")
            }
            // C4(a): this used to gate on `appState.isBusy` only, so it
            // stayed enabled and was refused through a modal after the
            // click when the session sidecar could not be rewritten.
            .disabled(saveReason != nil)
            // Drive 14: it dimmed with no reason. The reason is spoken and on hover; nothing drawn changes.
            .accessibilityValue(saveReason ?? "")
            .help(saveReason ?? "Save to Session — keeps the displayed result with this dataset, in "
                  + "its session sidecar. It appears in Results and survives reopening.")
            .accessibilityIdentifier("workspace.saveToResults")
        }
    }
}
