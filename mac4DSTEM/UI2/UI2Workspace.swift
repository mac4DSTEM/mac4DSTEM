import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The detail column: the science, and the two strips along its bottom edge.
///
/// **There is no workspace header.** The old `ProductWorkspaceHeader` repeated
/// the sidebar row's own title and subtitle and cost about 100 pt off the top
/// of both panes; in UI2 the window title carries the task name, the toolbar
/// carries the one action that runs it (`UI2PrimaryActionButton`), and
/// readiness has exactly one owner — the inspector's Settings tab. Nothing
/// here re-creates `TaskPrerequisiteChecklist`.
///
/// The bottom edge is a `safeAreaInset`, so the panes lay out above it and
/// neither strip can ever overprint an image.
struct UI2Workspace: View {
    @Environment(AppState.self) private var appState

    /// The output log's dragged height, remembered for the session. A
    /// `VSplitView` cannot divide the panes from the log — both are greedy,
    /// so it splits them evenly and the panes lose half the window — so the
    /// divider above the log carries the drag itself.
    @State private var logHeight: CGFloat = UI2Metrics.outputLogHeight.ideal

    /// The height the current drag started from. Without it the gesture's
    /// cumulative `translation` is re-applied on every change event and the
    /// strip snaps to a limit after a few points of travel.
    @State private var logHeightAtDragStart: CGFloat?

    /// Grab margin for the log's divider, in points. Not a layout size: it
    /// only widens the hit test, so the 1 pt rule stays 1 pt tall.
    private let dividerGrab: CGFloat = 5

    private var showsLog: Bool {
        appState.navigation.showLogPane && appState.hasDataset && !appState.isLoadingDataset
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if showsLog {
                        logResizeHandle
                        outputLog
                    }
                    Divider()
                    UI2StatusBar()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingDataset {
            loadingState
        } else if !appState.hasDataset {
            UI2Welcome()
        } else if appState.navigation.workspaceArea == .results {
            UI2ResultsWorkspace()
        } else {
            // Two scientific panes, side by side, with a divider the user
            // owns. NOT `HSplitView` — see `UI2PaneSplit` for the crash that
            // ruled it out.
            UI2PaneSplit {
                UI2DiffractionPane()
            } trailing: {
                UI2RealSpacePane()
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
            Text(appState.datasetLoadingStatus ?? "Opening dataset…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
            // A determinate bar only where the denominator is real:
            // `datasetLoadingProgress` is nil during phases whose duration is
            // not known, and a fake bar there would be a lie about the wait.
            if let progress = appState.datasetLoadingProgress {
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
            if appState.canCancelDatasetLoad {
                Button("Cancel") { appState.cancelDatasetLoad() }
                    .accessibilityIdentifier("welcome.cancelDatasetLoad")
                    .accessibilityHint("Stops loading this dataset and returns to the welcome screen")
            }
        }
        .frame(maxWidth: UI2Metrics.readableWidth)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.loadingStatus")
    }

    // MARK: - Output log

    /// Rolling output log below the panes, auto-scrolled to the latest line.
    private var outputLog: some View {
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
        // No ground of its own: the divider above it and the window's own
        // material are the strip's whole look.
        .frame(height: logHeight)
    }

    /// The log's top edge, draggable the way a split divider is. Pure
    /// SwiftUI: no cursor push, no event monitor.
    private var logResizeHandle: some View {
        Divider()
            .contentShape(Rectangle().inset(by: -dividerGrab))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = logHeightAtDragStart ?? logHeight
                        if logHeightAtDragStart == nil { logHeightAtDragStart = base }
                        // Up is negative in SwiftUI's coordinate space, and
                        // the strip grows upward.
                        logHeight = min(
                            max(UI2Metrics.outputLogHeight.min, base - value.translation.height),
                            UI2Metrics.outputLogHeight.max
                        )
                    }
                    .onEnded { _ in logHeightAtDragStart = nil }
            )
            .accessibilityLabel("Resize the output log")
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

// MARK: - The one action that runs the task

/// The toolbar's principal item: the single action the selected task runs,
/// and — while it runs — its progress and the way to stop it.
///
/// Titles, hints and enablement are the old `ProductWorkspaceHeader`'s,
/// verbatim, including the parallax staging rule that gates only
/// `.ptychography` and the `ProductWorkflow.readiness` check that the
/// checklist and the replay executor ask the same question of. When the
/// action is disabled by an unmet requirement, the help names the first one,
/// so the disabled state explains itself without a second readiness surface.
struct UI2PrimaryActionButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // The header only ever existed while a dataset was open and settled;
        // the toolbar item follows the same rule, so the load's own progress
        // (centre column) is never shadowed by a second bar up here.
        if appState.hasDataset && !appState.isLoadingDataset {
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

    /// While a run is in flight the toolbar offers ONE thing: the way to stop
    /// it. The progress bar that used to live here was the second copy of the
    /// one in the status bar (owner, 2026-09-04) and it squeezed the Cancel
    /// button until its label truncated to "C…".
    @ViewBuilder
    private var operationProgress: some View {
        if appState.canCancelActiveOperation {
            Button("Cancel", role: .cancel) { appState.cancelActiveOperation() }
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
        if !primaryActionEnabled, let first = appState.ui2UnmetRequirements.first {
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
            "Update Image"
        case .map:
            switch appState.navigation.analysisMode {
            case .disks: "Detect All Disks"
            case .strain: "Compute Strain"
            case .acom: appState.acomPrimaryActionTitle
            default: nil
            }
        case .reconstruct:
            if appState.navigation.analysisMode == .dpc { "Run DPC" }
            else if appState.navigation.analysisMode == .singleslicePtychography { "Reconstruct Object" }
            else if appState.parallaxPreprocess == nil { "Prepare Preview" }
            else if appState.parallaxAlignment?.isComplete != true { "Align Next Level" }
            else if appState.parallaxHigherOrderFit == nil { "Fit Aberrations" }
            else if appState.parallaxCorrection == nil { "Correct Phase" }
            else if appState.parallaxSubpixel == nil { "Upsample BF" }
            else { "Reconstruction Ready" }
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
        if appState.navigation.workspaceArea == .reconstruct,
           appState.navigation.analysisMode == .ptychography {
            // Parallax staging gates only its own chain — DPC is a plain run
            // and must not inherit this.
            return appState.parallaxCorrection == nil || appState.parallaxSubpixel == nil
        }
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
struct UI2Welcome: View {
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
                        .frame(maxWidth: UI2Metrics.readableWidth)
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
                    .frame(maxWidth: UI2Metrics.readableWidth)
                    .accessibilityIdentifier("welcome.localStorageNotice")
                }

                if !appState.recents.entries.isEmpty {
                    recents
                        .frame(maxWidth: UI2Metrics.readableWidth)
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

// MARK: - The bottom strip

/// The permanent status strip along the detail column's bottom edge.
///
/// Left: the status line. Middle: a slim live progress bar with Cancel
/// whenever a cancellable operation runs, so a long compute stays visible and
/// killable from every workspace. Right: the standing facts — app memory,
/// cube working size, residency — always on, plus the log's own control, the
/// way Xcode's debug area is toggled from the bar it opens above. The
/// inspector's Performance block keeps the full detail (GPU name, working-set
/// limit); this is the glanceable subset.
///
/// No bar of its own: the safe-area inset and the divider above it are its
/// whole look.
struct UI2StatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var navigation = appState.navigation

        HStack(spacing: 12) {
            Text(appState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("status.bar")

            Spacer(minLength: 12)

            if appState.isBusy {
                HStack(spacing: 8) {
                    ProgressView(value: appState.progress)
                        .frame(width: UI2Metrics.inlineProgressWidth)
                    if let progress = appState.progress {
                        Text("\(Int(progress * 100)) %")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if appState.canCancelActiveOperation {
                        Button("Cancel", role: .cancel) { appState.cancelActiveOperation() }
                            .controlSize(.mini)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("status.footer.operation")
            }

            if let descriptor = appState.descriptor {
                Text(footerFacts(descriptor))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityIdentifier("status.footer.facts")
            }

            if appState.hasDataset && !appState.isLoadingDataset {
                // A system toggle draws its own on-state, so the strip needs
                // no tint of its own. The toolbar's Show/Hide Output item is
                // the second door onto the same flag.
                Toggle(isOn: $navigation.showLogPane) {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help(appState.navigation.showLogPane
                      ? "Hide the output log" : "Show the output log")
                .accessibilityLabel("Toggle output log")
                .accessibilityIdentifier("status.footer.toggleLog")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerFacts(_ descriptor: DatasetDescriptor) -> String {
        let app = String(format: "%.0f MB app", SystemMonitor.residentMemoryMB())
        let cube = SystemMonitor.byteString(descriptor.byteCountAsFloat32) + " cube"
        return "\(app) · \(cube) · \(appState.residency.summary.lowercased())"
    }
}

// MARK: - The two-pane split

/// Two scientific panes side by side with a divider the user drags.
///
/// **Why this is not `HSplitView`** (Gate D, 2026-09-04). `HSplitView` nested
/// in the `NavigationSplitView` detail hosts each child in its own
/// `NSHostingView` and reacts to its minimum size through
/// `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. A
/// scientific pane's intrinsic minimum is content-derived and NOT constant —
/// the header's badges, pickers and readouts appear and change as a dataset
/// lands — so each change enqueued a layout invalidation, which re-laid out,
/// which produced a new minimum, until AppKit's update-constraints guard threw
/// `NSGenericException` and the app aborted on launch with `--demo-fixture`.
///
/// Measured, all four with the same tree: `HSplitView` + real panes crashes
/// (and still crashes with every explicit `.frame(minWidth:)` removed, which
/// is what refuted the first diagnosis); `HSplitView` + `Color.clear` children
/// survives; `HStack` + real panes survives; neither survives-case is a fix on
/// its own because each drops something the window needs. It is the
/// conjunction that crashes.
///
/// The old window escapes this only because AppKit owns its columns and hosts
/// their content with `sizingOptions = []` and compression resistance 1, which
/// absorbs the demand before any split controller sees it. UI2 has no AppKit
/// shell by contract, so the split itself must not ask its children how wide
/// they would like to be: this one measures the container, hands each pane an
/// explicit width, and propagates no minimum upward. It is also portable —
/// `HSplitView` is macOS-only.
struct UI2PaneSplit<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    /// The divider's position as a fraction of the usable width, remembered
    /// for the session. View-local: it is where a divider sits, not app state.
    @State private var fraction: CGFloat = 0.5
    @State private var fractionAtDragStart: CGFloat?

    private static var dividerWidth: CGFloat { 1 }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - Self.dividerWidth, 1)
            // Science: neither pane may be driven below the image floor. The
            // clamp lives here, on a number this view already has, rather
            // than as a minimum the panes announce upward.
            let floor = min(0.5, UI2Metrics.imagePaneMinimum / usable)
            let clamped = min(max(fraction, floor), 1 - floor)
            let leadingWidth = (usable * clamped).rounded()

            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth)
                divider(usable: usable, floor: floor)
                trailing()
                    .frame(width: usable - leadingWidth)
            }
        }
    }

    private func divider(usable: CGFloat, floor: CGFloat) -> some View {
        Divider()
            // The drawn line is 1 pt; the grab zone is the system's 9.
            .contentShape(
                Rectangle().inset(by: -UI2Metrics.dividerGrabWidth / 2)
            )
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = fractionAtDragStart ?? fraction
                        fractionAtDragStart = start
                        fraction = min(
                            max(start + value.translation.width / usable, floor),
                            1 - floor
                        )
                    }
                    .onEnded { _ in fractionAtDragStart = nil }
            )
            .accessibilityLabel("Resize the diffraction and real-space panes")
    }
}

// MARK: - Keeping a result

/// "Save to Results", in the toolbar beside the action that produced the
/// result (owner, 2026-09-04: "if you generate a result there should be a
/// button for saving this to the results window").
///
/// The old window offered this only inside the Results workspace, so keeping
/// a virtual image or a strain map meant leaving the workspace that made it.
/// The action is the same one Results calls — one writer, one sidecar — and
/// the wording is now the same in both places: the destination the user is
/// thinking of is the Results list, not the file format underneath it.
struct UI2SaveResultButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasDataset, !appState.isLoadingDataset,
           appState.displayedProduct != nil,
           appState.navigation.workspaceArea != .results {
            Button {
                appState.saveCurrentResultToSessionSidecar()
            } label: {
                Label("Save to Results", systemImage: "archivebox")
            }
            .disabled(appState.isBusy)
            .help("Keeps the displayed result with this dataset, in its session "
                  + "sidecar. It appears in Results and survives reopening.")
            .accessibilityIdentifier("workspace.saveToResults")
        }
    }
}
