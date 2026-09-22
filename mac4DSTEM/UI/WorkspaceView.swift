import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The detail column: the science, and the infobar + process area along its
/// bottom edge (window-design.md §4, phase 1, decided 2026-09-22; the
/// breadcrumb row above the panes went on 2026-09-22 evening, §8 — the room
/// actions and the file name live in the toolbar).
///
/// **There is no workspace header.** The old `ProductWorkspaceHeader`
/// repeated the sidebar row's own title and cost about 100 pt off the top of
/// both panes; the phase-1 breadcrumb row repeated it again at 34 pt.
/// Readiness has exactly one owner — the inspector's Settings tab.
///
/// **Layout, top to bottom, one `GeometryReader` over the whole column**: the
/// science panes, the infobar (`LayoutPolicy.statusStripHeight`, fixed — the
/// column's own divider, drag gesture and all), the process area.
/// `ProcessAreaLayout.heights(fraction:available:)` turns
/// `appState.navigation.processFraction` into the canvas and process area's
/// shares of what is left after the infobar: 0 hides the process area, 1
/// hides the canvas — the owner's two extremes. The process area's height
/// depends on nothing but that fraction, so switching its tab
/// (`BottomWorkspace`) can never move the bar.
struct WorkspaceView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("workspace.processFraction") private var savedProcessFraction = 0.0
    @SceneStorage("workspace.lastProcessFraction") private var savedLastProcessFraction = LayoutPolicy.processAreaIdealFraction

    /// Gates the process area exactly as the old `showsBottomWorkspace` did:
    /// `navigation.processFraction > 0` (via `showLogPane`) still has to be
    /// true, but a dataset that is absent or still loading forces it shut
    /// regardless of the dragged fraction, which `processFraction` itself is
    /// NOT reset for — reopening the same dataset restores the same split.
    private var showsProcessArea: Bool {
        appState.navigation.showLogPane && appState.hasDataset && !appState.datasetSession.isLoading
    }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.height - LayoutPolicy.statusStripHeight, 0)
            let effectiveFraction = showsProcessArea ? appState.navigation.processFraction : 0
            let heights = ProcessAreaLayout.heights(fraction: effectiveFraction, available: usable)

            VStack(spacing: 0) {
                // Always in the hierarchy, even at fraction 1 where its
                // height is 0: an `if` here tore down both Metal views every
                // time the infobar reached the top and rebuilt them on the
                // way back (2026-09-22). `MetalImageView` already declines to
                // draw without a drawable, so a 0-pt, clipped canvas costs
                // nothing and keeps the panes' state.
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: heights.canvas)
                    .clipped()

                StatusBar(availableHeight: usable)

                if heights.process > 0 {
                    BottomWorkspace()
                        .frame(height: heights.process)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            appState.navigation.lastProcessFraction = savedLastProcessFraction
            appState.navigation.processFraction = savedProcessFraction
        }
        .onChange(of: appState.navigation.processFraction) {
            savedProcessFraction = appState.navigation.processFraction
        }
        .onChange(of: appState.navigation.lastProcessFraction) {
            savedLastProcessFraction = appState.navigation.lastProcessFraction
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.datasetSession.isLoading {
            loadingState
        } else if !appState.hasDataset {
            WelcomeWorkspace()
        } else if appState.navigation.workspaceArea == .results {
            ResultsWorkspace()
        } else {
            // Two scientific panes, side by side, with a divider the user
            // owns. NOT `HSplitView` — see `PaneSplit` for the crash that
            // ruled it out.
            PaneSplit {
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

/// The window-level dataset switcher in the standard toolbar.
struct DatasetMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            Button("Open Dataset…") { appState.requestOpenDataset() }
            Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
            if appState.hasDataset {
                Divider()
                Button("Preprocess & Export…") { appState.requestPreprocessingExport() }
                    .disabled(appState.isBusy)
                Button("Export Diffraction PNG…") { appState.exportDiffractionImage() }
                    .disabled(appState.displayedPattern == nil)
            }
        } label: {
            // The folder is Reveal in Finder's (owner, 2026-09-22 evening);
            // the dataset menu is the cube stack the sidebar already uses.
            Label("Dataset", systemImage: "square.stack.3d.up")
        }
        .help("Open a dataset, or act on the one that is open")
        .accessibilityIdentifier("toolbar.datasetMenu")
    }
}

struct RevealDatasetButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            guard let path = appState.descriptor?.filePath else { return }
            DatasetLocationActions.reveal(path: path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .help("Reveal the dataset in Finder")
        .disabled(appState.descriptor == nil || appState.datasetSession.isLoading)
        .accessibilityIdentifier("workspace.revealDataset")
    }
}

// MARK: - The one action that runs the task

/// The toolbar's run button, at the head of the trailing group under the
/// inspector where the room's parameters are set (owner, 2026-09-22
/// evening): the single action the selected task runs, and — while it runs —
/// the way to stop it. The run's progress is the toolbar's centre display
/// (`ToolbarRunDisplay`), not this button.
///
/// Titles, hints and enablement are the old `ProductWorkspaceHeader`'s,
/// verbatim, including the parallax staging rule that gates only
/// `.ptychography` and the `ProductWorkflow.readiness` check that the
/// checklist and the replay executor ask the same question of. When the
/// action is disabled by an unmet requirement, the help names the first one,
/// so the disabled state explains itself without a second readiness surface.
struct PrimaryActionButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // The header only ever existed while a dataset was open and settled;
        // the toolbar item follows the same rule, so the load's own progress
        // (centre column) is never shadowed by a second bar up here.
        if appState.hasDataset && !appState.datasetSession.isLoading {
            if appState.isBusy {
                operationProgress
            } else if let actionTitle = primaryActionTitle {
                Button(actionTitle) { runPrimaryAction() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!primaryActionEnabled)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(helpText)
                    .accessibilityHint(primaryActionHint)
                    .accessibilityIdentifier("workspace.primaryAction")
            }
        }
    }

    /// While a run is in flight this slot offers ONE thing: the way to
    /// cancel it. Said "Stop" (Xcode's word) until the owner asked twice,
    /// live, the same day, whether there was a reason it didn't say
    /// "Cancel" — there wasn't one that survived being asked. `Label` with
    /// an icon and `.bordered`, matching every sibling toolbar item
    /// (`SaveResultButton`, `RevealDatasetButton`, `DatasetMenu`), not the
    /// plain unstyled text button this used to be — the plain form is what
    /// read as "collapsed" beside them. The progress bar that once sat here
    /// squeezed the button until its label truncated to "C…" (owner,
    /// 2026-09-04); the bar is the centre display now, so the label has
    /// room.
    @ViewBuilder
    private var operationProgress: some View {
        if appState.canCancelActiveOperation {
            Button(role: .cancel) {
                appState.cancelActiveOperation()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .help(appState.activeOperation ?? appState.statusText)
            .accessibilityLabel("Cancel \(appState.activeOperation ?? "the running operation")")
            .accessibilityIdentifier("workspace.cancelAction")
        } else {
            ProgressView()
                .controlSize(.small)
                .help(appState.activeOperation ?? appState.statusText)
        }
    }

    /// The hint, unless a requirement is what is holding the action back —
    /// then the requirement, because that is the question the user has.
    private var helpText: String {
        if !primaryActionEnabled, let first = appState.unmetRequirements.first {
            return first.title
        }
        return primaryActionHint
    }

    private var primaryActionTitle: String? {
        switch appState.navigation.workspaceArea {
        case .prepare:
            if !appState.calibrationSession.calibration.hasFittedOrigin { "Calibrate Origin" }
            else if !appState.calibrationSession.calibration.hasRotation { "Measure R–Q Rotation" }
            else { nil }
        case .image:
            // C4(a): every other task's title is its own verb — "Detect All
            // Disks", "Compute Strain", "Run DPC" — imaging's was the one
            // holdover generic label.
            "Compute Image"
        case .map:
            switch appState.navigation.analysisMode {
            case .disks: "Detect All Disks"
            case .strain: "Compute Strain"
            case .acom: appState.acomSession.primaryActionTitle
            default: nil
            }
        case .reconstruct:
            if appState.navigation.analysisMode == .dpc { "Run DPC" }
            else if appState.navigation.analysisMode == .singleslicePtychography { "Reconstruct Object" }
            else if appState.phaseContrast.parallaxPreprocess == nil { "Prepare Preview" }
            else if appState.phaseContrast.parallaxAlignment?.isComplete != true { "Align Next Level" }
            else if appState.phaseContrast.parallaxHigherOrderFit == nil { "Fit Aberrations" }
            else if appState.phaseContrast.parallaxCorrection == nil { "Correct Phase" }
            else if appState.phaseContrast.parallaxSubpixel == nil { "Upsample BF" }
            // C4(a): every parallax stage is complete — readiness is already
            // shown by the stage checklist's own checkmarks
            // (`ParallaxStageSections`), so the toolbar offers no button
            // rather than a permanently disabled "Reconstruction Ready" one.
            else { nil }
        case .aiAnalysis:
            appState.navigation.analysisMode == .phaseMapping ? "Map Phases" : "Group Patterns"
        case .results:
            nil
        }
    }

    private var primaryActionHint: String {
        switch appState.navigation.workspaceArea {
        case .prepare:
            appState.calibrationSession.calibration.hasFittedOrigin
                ? "Solves scan-to-detector rotation for quantitative vector output."
                : "Fits the unscattered-beam origin across the scan."
        case .image: "Runs the selected imaging task with the current settings."
        case .map:
            appState.navigation.analysisMode == .acom
                ? "Runs the selected orientation area and quality shown in the tools panel."
                : "Runs the selected whole-scan mapping task."
        case .reconstruct:
            switch appState.navigation.analysisMode {
            case .dpc: "Maps beam deflection across the scan and integrates projected phase."
            case .singleslicePtychography: "Runs the iterative single-slice reconstruction on the full datacube."
            default: "Runs the next incomplete parallax stage."
            }
        case .aiAnalysis:
            appState.navigation.analysisMode == .phaseMapping
                ? "Matches every position's peaks against the phases you named. Unvalidated."
                : "Runs PCA and k-means over every scan position's diffraction pattern."
        case .results: "Adds the visible result to the reusable dataset session."
        }
    }

    private var primaryActionEnabled: Bool {
        guard appState.hasDataset, !appState.isBusy else { return false }
        if appState.navigation.workspaceArea != .prepare && appState.navigation.workspaceArea != .results {
            // v2.5 step 5a: the same answer the checklist and replay get.
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
        Task { await appState.runPrimaryWorkspaceTask() }
    }
}

// MARK: - No dataset open

/// The empty window: the mark, what the app is for, and the doors.
///
/// The three "Prepare / Analyze / Preserve" cards the old welcome carried are
/// gone — brochure copy above the fold, describing the sidebar the user is
/// already looking at. What survives is what a first run needs: a way in, and
/// the one piece of guidance a user cannot infer (a network source costs
/// minutes on every whole-cube pass).
struct WelcomeWorkspace: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.cross.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Turn 4D-STEM data into answers")
                        .font(.largeTitle.weight(.semibold))
                    Text("A native Mac workspace for calibrated imaging, quantitative maps, and phase reconstruction.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: LayoutPolicy.readableWidth)
                }

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

    private var entryPoints: some View {
        HStack(spacing: 12) {
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
                Task { await appState.openDemoFixture() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.isBusy)
            .help("The demo is a small synthetic 4D-STEM dataset — every workspace works, and nothing on disk is touched.")
            .accessibilityIdentifier("welcome.demoButton")
        }
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

// MARK: - The status strip / infobar

/// The permanent status strip along the centre column's bottom edge — one
/// line, `LayoutPolicy.statusStripHeight` tall, nothing taller (ADR 034,
/// owner 2026-09-21: live operational detail moved to the process area's Run
/// tab, so this strip only glances).
///
/// **Phase 1 (window-design.md §4–§6): this IS the centre column's
/// divider.** A `DragGesture` over the whole bar — every pixel of its
/// width, via `.contentShape(Rectangle())` — reads `availableHeight` (the
/// same denominator `WorkspaceView`'s `ProcessAreaLayout.heights` uses) and
/// writes `appState.navigation.processFraction` through
/// `ProcessAreaLayout.fraction(afterDrag:available:from:)`, the same way
/// `PaneSplit`'s divider carries the science panes' resize. No event monitor,
/// AppKit cursor, or hosted split view is involved.
///
/// Left: the status line. Then the live run while one is in flight — the
/// bar, done / total, the rate, elapsed · ETA and Stop — or the last run
/// while idle (owner, 2026-09-22 late, §9.3: the Run tab's numbers belong
/// in the bar). Then the engine · memory · residency glance, always on.
/// Right: Xcode's debug-bar buttons — one per process pane (Output,
/// Lineage) and the area's own toggle — `ProcessAreaLayout.toggled
/// (from:last:)`, the same pure function `WorkspaceNavigation.showLogPane`'s
/// setter reimplements for the ⌃⌘L menu item.
///
/// No bar of its own: a `Divider()` above and below (added by `WorkspaceView`,
/// the one exception the hard rules carve out for the infobar) is its whole
/// look.
struct StatusBar: View {
    @Environment(AppState.self) private var appState
    let availableHeight: CGFloat

    /// The fraction the current drag started from — without it the
    /// gesture's cumulative `translation` re-applies on every change event
    /// and the bar snaps to a limit after a few points of travel, the same
    /// shape `PaneSplit.fractionAtDragStart` and `BottomWorkspace`'s old
    /// `heightAtDragStart` both guarded against.
    @State private var fractionAtDragStart: Double?

    private var processAreaToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.navigation.processFraction > 0 },
            set: { _ in
                appState.navigation.processFraction = ProcessAreaLayout.toggled(
                    from: appState.navigation.processFraction,
                    last: appState.navigation.lastProcessFraction
                )
            }
        )
    }

    /// Xcode's debug-bar buttons (owner, 2026-09-22 late, §9.3): one per
    /// pane, each toggling its pane and, through `toggleProcessPane`, the
    /// area itself when it is the last pane out or the first pane in.
    private func paneBinding(_ pane: WorkspaceNavigation.ProcessPane) -> Binding<Bool> {
        Binding(
            get: {
                switch pane {
                case .output: appState.navigation.showsOutputPane && appState.navigation.showLogPane
                case .lineage: appState.navigation.showsLineagePane && appState.navigation.showLogPane
                }
            },
            set: { _ in appState.navigation.toggleProcessPane(pane) }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard appState.hasDataset, !appState.datasetSession.isLoading else { return }
                let start = fractionAtDragStart ?? appState.navigation.processFraction
                if fractionAtDragStart == nil { fractionAtDragStart = start }
                appState.navigation.processFraction = ProcessAreaLayout.fraction(
                    afterDrag: value.translation.height, available: availableHeight, from: start
                )
            }
            .onEnded { _ in fractionAtDragStart = nil }
    }

    var body: some View {
        HStack(spacing: LayoutPolicy.infobarItemSpacing) {
            // One line, truncating — the message never dictates the bar's
            // height; `.help` carries the rest of a long line.
            Text(appState.statusText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(appState.statusText)
                .accessibilityIdentifier("status.bar")

            Spacer(minLength: LayoutPolicy.infobarItemSpacing)

            // The Run tab's numbers, here (owner, 2026-09-22 late, §9.3):
            // the bar, done / total, the rate, elapsed · ETA and Stop while a
            // run is in flight; the last run while idle.
            if showsOperationProgress {
                runReadout
            } else if let last = appState.operationCenter.lastFinished {
                Text("Last run · " + OperationMetricsFormat.lastRun(
                    last.name, elapsed: last.elapsed, cancelled: last.outcome == .cancelled))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("status.footer.lastRun")
            }

            systemGlance

            if appState.hasDataset && !appState.datasetSession.isLoading {
                Toggle(isOn: paneBinding(.output)) {
                    Image(systemName: "rectangle.leadinghalf.inset.filled")
                }
                .toggleStyle(.button)
                .help("Output pane")
                .accessibilityLabel("Toggle the Output pane")
                .accessibilityIdentifier("status.footer.toggleOutput")
                Toggle(isOn: paneBinding(.lineage)) {
                    Image(systemName: "rectangle.trailinghalf.inset.filled")
                }
                .toggleStyle(.button)
                .help("Lineage pane")
                .accessibilityLabel("Toggle the Lineage pane")
                .accessibilityIdentifier("status.footer.toggleLineage")
                Toggle(isOn: processAreaToggleBinding) {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .toggleStyle(.button)
                .help(appState.navigation.showLogPane
                      ? "Hide the bottom pane" : "Show the bottom pane")
                .accessibilityLabel("Toggle bottom pane")
                .accessibilityIdentifier("status.footer.toggleLog")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.statusStripHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .modifier(ResizePointer(axis: .row))
        .simultaneousGesture(dragGesture)
    }

    /// Whether the strip draws the live run. `isBusy` alone was not the
    /// right question: during a dataset OPEN it is true with no metrics and
    /// no Cancel, beside a loading column that has its own spinner and
    /// Cancel. A load that has started an analysis inside its bracket still
    /// qualifies, because that pass is cancellable.
    private var showsOperationProgress: Bool {
        appState.isBusy && (!appState.datasetSession.isLoading || appState.activeOperation != nil)
    }

    /// The bar, the counts, the rate, elapsed · ETA, Stop — ticking once a
    /// second, in a constant-width slot (`runReadoutWidth`, the
    /// `operationReadoutWidth` rule: a ticking string never resizes its own
    /// container — the 2026-09-04 constraint loop).
    private var runReadout: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: LayoutPolicy.infobarProgressSpacing) {
                ProgressView(value: appState.progress)
                    .frame(width: LayoutPolicy.inlineProgressWidth)
                    .accessibilityLabel(appState.activeOperation ?? "Progress")
                    .accessibilityValue(appState.progress
                        .map { "\(Int($0 * 100)) percent" } ?? "")
                Text(OperationMetricsFormat.runLine(
                    done: appState.operationCenter.unitsDone,
                    total: appState.operationCenter.totalUnits,
                    metrics: appState.activeOperationMetrics(at: context.date),
                    for: appState.activeOperation))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: LayoutPolicy.runReadoutWidth, alignment: .leading)
                    .accessibilityIdentifier("status.footer.metrics")
                if appState.canCancelActiveOperation {
                    // "Cancel", matching the toolbar's own button (owner,
                    // 2026-09-22): both name the same action on the same
                    // run, and read as two different controls when they
                    // disagreed. `.fixedSize()` + `.layoutPriority(1)`:
                    // found on screen the same night — this row's other
                    // items (the progress bar, the fixed-width metrics
                    // text) leave the button no protected space of its own,
                    // and "Cancel" (6 chars) is wide enough that the row
                    // collapsed it to a blank ~9pt pill with no visible
                    // label, over its own fixed width when the metrics text
                    // was near its own longest content. The label wasn't
                    // just visually tight, it rendered with zero width.
                    Button("Cancel", role: .cancel) { appState.cancelActiveOperation() }
                        .fixedSize()
                        .layoutPriority(1)
                        .accessibilityLabel("Cancel \(appState.activeOperation ?? "the running operation")")
                        .accessibilityIdentifier("status.footer.stop")
                }
            }
        }
    }

    /// The standing facts — the engine, app memory and whether the cube is
    /// resident or streamed — always on, in a fixed slot, with the chip
    /// glyph the owner asked for ("some logos if it makes sense").
    private var systemGlance: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Label {
                Text(OperationMetricsFormat.glance(
                    engine: SystemMonitor.gpuName,
                    residentMB: SystemMonitor.residentMemoryMB(),
                    residency: appState.residency.isResident
                ))
            } icon: {
                Image(systemName: "memorychip")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: LayoutPolicy.statusGlanceWidth, alignment: .trailing)
            .accessibilityIdentifier("status.footer.memoryGlance")
        }
    }
}

// MARK: - The two-pane split

/// Two scientific panes side by side with a divider the user drags.
///
/// **Why this is not `HSplitView`** (Gate D, 2026-09-04). `HSplitView` nested
/// in the `NavigationSplitView` detail is half of a launch crash: with both it
/// and the real panes present the app aborted in AppKit's update-constraints
/// guard ~6 s after launching on the demo fixture, and removing either element
/// removed the crash. Measured, one tree: HSplitView + real panes crashes (and
/// still crashes with every `.frame(minWidth:)` removed, which refuted the
/// first diagnosis); HSplitView + `Color.clear` children survives; `HStack` +
/// real panes survives.
///
/// **What is NOT established is why.** The first written explanation — that
/// `HSplitView` hosts each child in its own `NSHostingView` and loops on a
/// content-derived minimum — was refuted by this repo's own shipping code: the
/// old window (`UI/ContentView.swift`) puts two real scientific panes with
/// explicit minimums inside an `HSplitView` and does not crash. The mechanism
/// that fits every observation, including that one, is the one measured
/// in-process on 2026-09-03 (`UI/SplitViewPolicy.swift`): a minimum
/// travelling between a SwiftUI-owned split and its hosted content. UI stacks
/// three such splits — `NavigationSplitView`, `.inspector`, `HSplitView` — and
/// every surviving probe drops it to two. Two probes would separate the two
/// readings and neither has been run; they are named in `open-items.md`.
///
/// The fix is safe under either reading, which is why it landed on an
/// unfinished explanation: a `GeometryReader` reports the proposal and never
/// consults its children, and `.frame(width:)` terminates each pane's
/// minimum, so this view propagates no minimum upward at all. It is also
/// portable — `HSplitView` is macOS-only.
struct PaneSplit<Leading: View, Trailing: View>: View {
    private let leading: () -> Leading
    private let trailing: () -> Trailing

    /// `storageKey` names the scene-storage slot the divider's position lives
    /// in, so the science split and the process area's split (2026-09-22
    /// late) remember their own fractions.
    init(
        storageKey: String = "workspace.paneSplit.fraction",
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leading = leading
        self.trailing = trailing
        self._storedFraction = SceneStorage(wrappedValue: 0.5, storageKey)
    }

    /// The divider's position as a fraction of the usable width. Where a
    /// divider sits is window state, not app state, so it lives in the
    /// scene's own storage: it survives this branch being rebuilt (a load, a
    /// trip to Results) and the window being reopened, and each window keeps
    /// its own. As `@State` it reset to centre on every rebuild — the
    /// `PaneSplit` residual (c) and the first item of the UI polish list
    /// (`open-items.md`), closed 2026-09-05.
    @SceneStorage private var storedFraction: Double
    @State private var fractionAtDragStart: CGFloat?

    private var fraction: CGFloat {
        get { CGFloat(storedFraction) }
        nonmutating set { storedFraction = Double(newValue) }
    }

    private static var dividerWidth: CGFloat { LayoutPolicy.sciencePaneDividerWidth }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - Self.dividerWidth, 1)
            // Science: neither pane is driven below the image floor while
            // there is room for two of them. The clamp lives here, on a
            // number this view already has, rather than as a minimum the
            // panes announce upward — announcing one is what the crash was
            // about. Below 2 x the floor the fraction saturates at 0.5 and
            // both panes go under it: with 300 pt of container there is no
            // arrangement that honours a 180 pt floor twice, so the split
            // divides what it has evenly rather than pretending otherwise.
            let smallest = min(0.5, LayoutPolicy.imagePaneMinimum / usable)
            let clamped = min(max(fraction, smallest), 1 - smallest)
            let leadingWidth = (usable * clamped).rounded()

            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth)
                divider(usable: usable, smallest: smallest)
                trailing()
                    .frame(width: usable - leadingWidth)
            }
        }
    }

    private func divider(usable: CGFloat, smallest: CGFloat) -> some View {
        Divider()
            // The drawn line is 1 pt; the grab zone is the system's 9.
            .contentShape(
                Rectangle().inset(by: -LayoutPolicy.dividerGrabWidth / 2)
            )
            .modifier(ResizePointer(axis: .column))
            // `.global` for the same reason as the infobar's gesture: the
            // divider moves with the drag, and a local translation lags it.
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = fractionAtDragStart ?? fraction
                        fractionAtDragStart = start
                        fraction = min(
                            max(start + value.translation.width / usable, smallest),
                            1 - smallest
                        )
                    }
                    .onEnded { _ in fractionAtDragStart = nil }
            )
            .accessibilityLabel("Resize the diffraction and real-space panes")
    }
}

// MARK: - Keeping a result

/// "Save to Session", in the toolbar beside Reveal (owner, 2026-09-04: "if
/// you generate a result there should be a button for saving this to the
/// results window"; 2026-09-22 evening: always in the toolbar, so it is
/// reachable with both side panels hidden).
///
/// The old window offered this only inside the Results workspace, so keeping
/// a virtual image or a strain map meant leaving the workspace that made it.
/// The action is the same one Results calls — one writer, one sidecar — and
/// the destination is the session sidecar, from which Results reads it.
struct SaveResultButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasDataset, appState.navigation.workspaceArea != .results {
            Button {
                appState.saveCurrentResultToSessionSidecar()
            } label: {
                Label("Save to Session", systemImage: "archivebox")
            }
            // C4(a): was `appState.isBusy` only, so this was enabled and then
            // refused through a modal after the click when the session
            // sidecar could not be rewritten (§4 finding 2).
            .disabled(appState.datasetSession.isLoading || appState.displayedProduct == nil
                      || appState.isBusy || !appState.gates.mayWriteSidecar)
            .help("Save to Session — keeps the displayed result with this dataset, in "
                  + "its session sidecar. It appears in Results and survives reopening.")
            .accessibilityIdentifier("workspace.saveToResults")
        }
    }
}

/// `pointerStyle` is macOS 15+, and it was the second and last thing pinning
/// this app to a high floor (2026-09-04). The resize cursor over a divider is
/// a refinement: below 15 the divider still drags, it just does not change
/// the pointer. A `ViewModifier` rather than an inline `if #available` so
/// both branches keep a single concrete type. `.column` is the pane split's
/// left–right pair; `.row` is the infobar's up–down pair, added 2026-09-22
/// because a bar the brief calls "draggable over its whole width" gave no
/// sign of it (window-design.md §1).
private struct ResizePointer: ViewModifier {
    enum Axis { case column, row }
    let axis: Axis

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            switch axis {
            case .column: content.pointerStyle(.columnResize)
            case .row: content.pointerStyle(.rowResize)
            }
        } else {
            content
        }
    }
}
