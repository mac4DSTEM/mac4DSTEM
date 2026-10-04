import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The left column: navigation and session context only. Controls that used to
/// share this column with the workspace/task lists (v1's `PrepareSidebar`,
/// `ImageSidebar`, `MapSidebar`, `PhaseSidebar`, `ResultsSidebar`, and the
/// sidecar actions) now live in their owning inspector or the Dataset menu.
///
/// A source list, not a settings pane: selection, hover, the row capsule and
/// `AXOutlineRow` all come from the `List` itself, tagged with `WorkspaceRoute` so
/// selection binds straight onto `appState.workspaceRoute`.
struct WorkspaceSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var pendingResultRemoval: SessionResultDescriptor?

    var body: some View {
        List(selection: appState.workspaceRoute) {
            if !appState.hasDataset {
                Section("Dataset") {
                    Button {
                        appState.requestOpenDataset()
                    } label: {
                        Label("Open Dataset…", systemImage: "folder")
                    }
                    Button {
                        appState.requestOpenDatasetWithOptions()
                    } label: {
                        Label("Open with Options…", systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        appState.requestPreprocessRawData()
                    } label: {
                        Label("Preprocess…", systemImage: "gearshape")
                    }
                    .help("Preprocess Raw Data…")
                }
            }

            Section("Workspace") {
                ForEach(WorkspaceArea.allCases) { area in
                    workspaceRow(area).tag(WorkspaceRoute.workspace(area))
                }
                if let hint = ProductWorkflow.nextStepHint(
                    for: appState.navigation.workspaceArea,
                    readiness: appState.productWorkflowReadiness,
                    calibrationReady: appState.calibrationSession.readiness.isReady
                ) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // A `.sidebar` List gives its rows no width, so this
                        // takes its one-line ideal and truncates — UI
                        // contract rule 5 says that's the choice, not a
                        // finding — but a hint nobody can finish reading is
                        // useless, so the full sentence is on hover.
                        .help(hint)
                        .accessibilityIdentifier("workspace.nextStepHint")
                }
            }

            let area = appState.navigation.workspaceArea
            if !area.analysisModes.isEmpty {
                Section(area.title) {
                    let groups = area.taskFamilyGroups
                    let showsLabels = area.showsTaskFamilyLabels
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
                            taskRow(mode).tag(WorkspaceRoute.task(mode))
                        }
                    }
                }
            }

            SessionSection(pendingResultRemoval: $pendingResultRemoval)
        }
        .listStyle(.sidebar)
        // One material per column, and it is AppKit's — a `.sidebar` List
        // paints a second one inside the scroll view that composites
        // differently where the sidebar item's own material already shows
        // (`ColumnMaterialTests`). The row selection capsule is drawn by the
        // table, not by this background, so hiding it costs nothing visible.
        .scrollContentBackground(.hidden)
        // Bounce only when there is something to scroll, so elastic
        // overscroll can never park the clip origin above the top.
        .scrollBounceBehavior(.basedOnSize)
        .confirmationDialog(
            "Remove Saved Result?",
            isPresented: Binding(
                get: { pendingResultRemoval != nil },
                set: { if !$0 { pendingResultRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingResultRemoval
        ) { result in
            Button("Remove \(result.displayName)", role: .destructive) {
                pendingResultRemoval = nil
                PendingEdits.run { await appState.removeSavedSessionResult(result) }
            }
            Button("Cancel", role: .cancel) { pendingResultRemoval = nil }
        } message: { result in
            Text("This removes \(result.displayName) from the session sidecar.")
        }
    }

    /// A source-list row: a `Label`, and a count as macOS carries one — a
    /// `.badge`, which hides itself at zero.
    private func workspaceRow(_ area: WorkspaceArea) -> some View {
        Label(area.title, systemImage: area.systemImage)
            .badge(area == .results ? appState.sessionInventory.results.count : 0)
            .help(area.subtitle)
            .accessibilityLabel(area.title)
            .accessibilityIdentifier("workspace.\(area.rawValue)")
            .accessibilityHint(area.subtitle)
    }

    /// Three states, matching the inspector's own "Computed this session"
    /// glyphs — orange `!` blocked, empty circle ready, green check produced
    /// this session. In a `.sidebar` List a trailing glyph goes in an
    /// `HStack` with a `Spacer`, not in a `LabeledContent`: `LabeledContent`
    /// only stacks its label vertically inside a `Form`, and in a List row it
    /// lays out horizontally and crushes the row onto one truncated line.
    private func taskRow(_ mode: AnalysisMode) -> some View {
        let unmet = taskUnmetCount(mode)
        let state = taskProductState(mode)
        let produced = state.isProduced
        return HStack {
            Label {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Short in the narrow sidebar; the full title is on hover.
                    Text(mode == .diffractionGroups ? "Groups" : mode.productTitle)
                        .lineLimit(1)
                    if mode.isAdvanced {
                        Text("Advanced").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: mode.systemImage)
            }
            Spacer()
            if let reason = state.staleReason {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.orange)
                    .help(reason)
                    .accessibilityIdentifier("task.\(mode.id).stale")
            } else {
                Image(systemName: produced
                        ? "checkmark.circle.fill"
                        : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                    .foregroundStyle(produced
                        ? Color.green
                        : (unmet == 0 ? Color.secondary : Color.orange))
            }
        }
        .help(state.staleReason ?? "\(mode.productTitle) — \(mode.productSubtitle)")
        .accessibilityLabel(taskAccessibilityLabel(mode))
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
    }

    private func taskUnmetCount(_ mode: AnalysisMode) -> Int {
        ProductWorkflow.prerequisites(
            for: mode, readiness: appState.productWorkflowReadiness
        ).count
    }

    /// The state of this task's retained product — the same rule the
    /// inspector's "Computed this session" rows apply, so the two surfaces
    /// cannot give different verdicts on staleness: any task's own recipe
    /// step, compared to what current settings would record (C4(b)).
    private func taskProductState(_ mode: AnalysisMode) -> TaskProductState {
        ProductWorkflow.productState(
            for: mode, hasProduct: taskHasProduct(mode),
            recordedStep: appState.recordedReplayStep(for: mode),
            currentSignature: appState.currentReplaySignature(for: mode))
    }

    /// Whether this task has produced its product in this session — only for
    /// the tasks with an unambiguous retained product. Staleness is judged by
    /// `taskProductState`, on top of this. Virtual imaging and DPC share the
    /// single scalar result slot, so "has produced" is read from the recipe
    /// record — it survives the slot being replaced and resets with the dataset.
    private func taskHasProduct(_ mode: AnalysisMode) -> Bool {
        switch mode {
        case .disks: appState.resultPresentation.braggVectors != nil
        case .strain: appState.strain.map != nil
        case .acom: appState.acomSession.hasOrientationMap
        case .virtualDetector:
            appState.replay.record.steps.contains { $0.kind == "virtual_detector" }
        case .dpc:
            appState.replay.record.steps.contains { $0.kind == "dpc" }
        case .diffractionGroups: appState.diffractionGroups.result != nil
        case .phaseMapping: appState.phaseMapping.map != nil
        case .ptychography, .singleslicePtychography: false
        }
    }

    /// Readiness is folded into the label rather than left on the glyph: an
    /// `accessibilityLabel` on a container replaces its children's, so a
    /// label on the image alone would never be announced.
    private func taskAccessibilityLabel(_ mode: AnalysisMode) -> String {
        switch taskProductState(mode) {
        case .current: return "\(mode.productTitle), computed"
        case .stale: return "\(mode.productTitle), computed with earlier settings"
        case .none: break
        }
        let unmet = taskUnmetCount(mode)
        if unmet == 0 { return "\(mode.productTitle), ready" }
        return "\(mode.productTitle), \(unmet) requirement\(unmet == 1 ? "" : "s") missing"
    }
}

// MARK: - What is loaded, and what session it carries

/// The bottom of the source list: which dataset is open and what saved
/// session came with it. The sidecar warnings live here, not only in Info,
/// because a saved session that cannot be read, describes a region this
/// file doesn't have, or was computed on a different view changes what
/// every number on screen means — that has to sit in permanent view, not
/// one tab away where a user would not think to look; the detail stays in
/// Info.
///
/// Rows here are List rows, not Form rows, so they stack explicitly —
/// `LabeledContent` would lay them out on one line and truncate.
struct SessionSection: View {
    @Environment(AppState.self) private var appState
    @Binding var pendingResultRemoval: SessionResultDescriptor?

    var body: some View {
        if let descriptor = appState.descriptor, descriptor.is4D {
            Section("Dataset") {
                VStack(alignment: .leading, spacing: 2) {
                    Label(descriptor.fileName, systemImage: "cube.transparent")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(descriptor.rx) × \(descriptor.ry) scan · \(descriptor.qx) × \(descriptor.qy) detector")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    // Residency, not telemetry: resident and streaming produce
                    // identical numbers, so nothing else on screen tells a user
                    // which path their analyses took, which makes this
                    // provenance — it belongs beside the dataset it describes,
                    // not four interactions deep in a collapsible inspector.
                    // App resident memory and the cube's byte count stay out:
                    // one is a debugger readout, the other a static file
                    // property, and Info › Performance carries both.
                    Text(appState.residency.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .help(descriptor.fileName)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sidebar.dataset")
            }

            Section("Session") {
                warnings
                inventory
            }
            // Contents, not navigation. NOTE: a `.sidebar` List re-applies its
            // own font to every Label, so a `.font()` here does nothing — it
            // has to go on each row, which is why they carry it individually.
            .accessibilityIdentifier("sidebar.session")
        }
    }

    /// The three states in which the saved session and the loaded data do not
    /// agree. The headline names the state; the line under it is the way out
    /// (`SessionSidebarWording`, one short line, owner card Q4 d), and the full
    /// refusal is on hover — the Info tab does not carry it.
    @ViewBuilder
    private var warnings: some View {
        if let reason = appState.sessionSidecar.unreadableReason {
            let text = SessionSidebarWording.unreadableDetail(reason: reason)
            warning(SessionSidebarWording.unreadableHeadline,
                    detail: text.shown, fullDetail: text.full,
                    identifier: "sidebar.session.unreadable")
            // The way out, where the warning is (2026-09-30): the sandbox grant the app lacks for a sibling it
            // never saved from this Mac. One open panel at the file, then the dataset reopens with its session.
            Button(SessionSidebarWording.allowAccessTitle) { appState.allowAccessToSessionSidecar() }
                .controlSize(.small)
                .disabled(appState.isBusy)
                .help("Choose the session file beside this dataset so mac4DSTEM may read it; the dataset then reopens with its session.")
                .accessibilityIdentifier("sidebar.session.allowAccess")
        } else if let failure = appState.gates.sidecarRestoreFailure,
                  failure.kind == .doesNotFit {
            warning(SessionSidebarWording.doesNotFitHeadline,
                    detail: failure.message,
                    fullDetail: failure.message,
                    identifier: "sidebar.session.doesNotFit")
        } else if let recorded = appState.sessionLoadSpecification,
                  recorded != appState.loadedView.specification {
            // When saving is refused because of it (owner card D3 a), the refusal is on hover and the line shown
            // is its remedy (owner card Q4 d) — the disabled Save controls themselves carry no reason (review
            // lane I refuter, 2026-10-02). In this branch the refusal is the carried-view one: a failed restore
            // leaves `sessionLoadSpecification` nil, or is the branch above.
            let text = SessionSidebarWording.differentViewDetail(
                refusal: appState.gates.sidecarRewriteRefusal(),
                saved: recorded.provenanceSummary ?? "whole file",
                loaded: appState.loadedView.specification.provenanceSummary ?? "whole file")
            warning(SessionSidebarWording.differentViewHeadline,
                    detail: text.shown, fullDetail: text.full,
                    identifier: "sidebar.session.provenanceMismatch")
        }
    }

    /// `detail` is the one short line shown; `fullDetail` is the whole text, on hover with the headline.
    /// The headline is uncapped (it wraps, at most 64 characters — `SessionSidebarWording`); the detail keeps
    /// three caption lines so the row cannot grow past them.
    private func warning(
        _ headline: String, detail: String, fullDetail: String, identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(headline, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(nil)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .help(SessionSidebarWording.warningHelp(headline: headline, detail: fullDetail))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// What the sidecar holds — on the left, so the user sees what came
    /// with the dataset right after loading it. Info keeps the two sections
    /// that explain a sidecar the app could not read or could not fit;
    /// that's the half of the split the comment above deliberately kept
    /// there.
    ///
    /// Every row takes the `.sidebar` List's one-line ideal and truncates, so
    /// the detail a row cannot show is on `.help`, the same choice the
    /// next-step hint makes. Nothing here uses `.fixedSize()`: a split column
    /// may not change its own minimum (`docs/open-items.md`).
    @ViewBuilder
    private var inventory: some View {
        if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
            // Goes through the seam rather than deriving the path itself: a
            // bookmark resolving to a sidecar the user had renamed once made
            // the app name a file it wasn't reading.
            let sidecar = appState.sessionSidecar.location(for: descriptor)
            // States plainly that these results came from a file loaded
            // beside the cube, not from this session's work — short enough
            // to survive a sidebar row's one-line width; the full sentence
            // is on hover, the same choice the next-step hint makes.
            let wording = SessionSidebarWording.explainer(
                savedThisSession: appState.sessionSidecar.wroteThisSession)
            Text(wording.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(wording.help)
                .accessibilityIdentifier("sidebar.session.explainer")

            // No summary line: the rows below name the same objects it counted.
            Label(sidecar.lastPathComponent, systemImage: "externaldrive")
                .font(.caption)
                .imageScale(.small)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(sidecar.lastPathComponent)
                .accessibilityIdentifier("sidebar.session.sidecar")

            if appState.sessionInventory.hasCalibration {
                // A calibration the session refused for this view is in the file
                // and not in use: the row must not read as loaded (drive 2B f2).
                let refused = CalibrationCarryNotes.sessionCalibrationRefused(
                    appState.loadedView.invalidatedCalibration)
                Label(SessionSidebarWording.calibrationRowTitle(refusedForThisView: refused),
                      systemImage: "scope")
                    .font(.caption)
                    .imageScale(.small)
                    .foregroundStyle(refused ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .help(refused
                          ? "The saved calibration was not applied to this view — Info › Not carried into this view says why."
                          : "")
                    .accessibilityIdentifier("sidebar.session.calibration")
            }
            if appState.sessionInventory.hasBraggVectors {
                Label("BraggVectors", systemImage: "circle.grid.cross")
                    .font(.caption)
                    .imageScale(.small)
                    .accessibilityIdentifier("sidebar.session.braggVectors")
            }
            ForEach(appState.sessionInventory.results) { result in
                savedResultRow(
                    result, isCurrent: result.id == appState.sessionInventory.currentResultID
                )
            }
        } else if appState.sessionSidecar.mayClaimNothingSaved(hasSidecar: appState.sessionInventory.hasSidecar) {
            // Not under "could not be read": a session IS saved there (review 2026-10-02 e10).
            Text("Nothing saved yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Nothing is saved with this dataset yet.")
                .accessibilityIdentifier("sidebar.session.empty")
        }
    }

    /// A saved result as a source-list row. The Info panel's version stacked
    /// three caption lines and a trailing sampling value under the name; a
    /// `.sidebar` row has no width to spend on them, so one caption line
    /// survives and the rest is on `.help`.
    ///
    /// Remove lives in the row's context menu, not a second visible row per
    /// result as Info had it: two rows per saved result fills this column,
    /// and a right-click is the source-list idiom for acting on a row. This
    /// is placement, and the owner's to overrule on screen.
    @ViewBuilder
    private func savedResultRow(_ result: SessionResultDescriptor, isCurrent: Bool) -> some View {
        Button {
            PendingEdits.run { await appState.selectSavedSessionResult(result) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(
                    result.displayName,
                    systemImage: isCurrent
                        ? "eye.fill"
                        : (result.storage == .rgba8 ? "paintpalette" : "map")
                )
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                Text(resultDetail(result))
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(resultHelp(result))
        .contextMenu {
            Button(role: .destructive) {
                pendingResultRemoval = result
            } label: {
                Label("Remove \(result.displayName)", systemImage: "trash")
            }
            // C4(a): removal rebuilds the sidecar too — same gate as the saves, asked for this removal (review a5:
            // removing the last result saved on another view stays possible, it is the remedy).
            .disabled(appState.isBusy || !appState.gates.mayRemoveFromSidecar(kind: result.kind))
        }
        .accessibilityIdentifier("sidebar.session.result")
    }

    /// The one caption line a sidebar row can show.
    private func resultDetail(_ result: SessionResultDescriptor) -> String {
        "\(result.width)×\(result.height) · "
            + (result.storage == .rgba8 ? "RGBA8" : "float32")
            + " · \(result.valueUnits)"
    }

    /// Everything the row had to drop, plus what Info's version carried in
    /// its tooltip.
    private func resultHelp(_ result: SessionResultDescriptor) -> String {
        var lines = ["\(result.displayName) — \(resultDetail(result))"]
        if let sampling = SessionResultPresentation.sampling(
            row: result.pixelSizeRow, column: result.pixelSizeColumn,
            units: result.pixelUnits
        ) {
            lines.append(sampling)
        }
        if let provenance = SessionResultPresentation.provenance(result.provenance) {
            lines.append(provenance)
        }
        lines.append("\(result.kind) · \(result.id)")
        return lines.joined(separator: "\n")
    }

}

/// The Session section's sentences that depend on state, as pure functions
/// (a view describes UI only).
enum SessionSidebarWording {
    // The three warning headlines. At most 64 characters each: they wrap, uncapped, at the narrowest sidebar
    // (a 64-character one needs four lines there; the old three-line cap cut it at "different view of thi…").
    static let unreadableHeadline = "A saved session beside this dataset could not be read."
    static let doesNotFitHeadline = "The saved session describes a region this file does not have."
    static let differentViewHeadline = "The saved session was computed on a different view of this file."

    /// The title of the sidebar button that grants access to the sidecar — the one the warning's line points at.
    static let allowAccessTitle = "Allow Access…"

    /// The sidebar's line for a session saved on another view, `shown` under the headline and `full` on hover.
    /// With saving refused (`refusal` is `SessionGates.sidecarRewriteRefusal()`, about 350 characters whose
    /// remedy sits at the END and was cut off at three lines) the remedy comes first, in one line, and the
    /// refusal is the hover; without a refusal it is the two views. The owner's wording (card Q4 d, 2026-10-04).
    static func differentViewDetail(refusal: String?, saved: String, loaded: String) -> (shown: String, full: String) {
        guard let refusal else {
            let views = "Session: \(saved) · loaded: \(loaded)"
            return (views, views)
        }
        return ("Saving is off here. Reopen the dataset, or remove the saved result in Results.", refusal)
    }

    /// The line under "could not be read". A sandbox refusal — `SessionSidecarReadFailure.notPermitted`'s
    /// sentence, which names `allowAccessTitle` — shows the remedy alone (the button is right below) and the
    /// sentence on hover; any other failure keeps its own text, the only clue there is.
    static func unreadableDetail(reason: String) -> (shown: String, full: String) {
        guard reason.contains(allowAccessTitle) else { return (reason, reason) }
        return ("Not granted access by macOS. Choose \(allowAccessTitle) below and pick that file.", reason)
    }

    /// The hover: the headline and the whole text. (It used to end "The Info tab carries the full
    /// explanation." — false: Info holds neither the refusal nor its remedy.)
    static func warningHelp(headline: String, detail: String) -> String {
        "\(headline)\n\n\(detail)"
    }

    /// The line above the sidecar's rows. `savedThisSession` is the sidecar
    /// seam's own `wroteThisSession`: this app wrote the file since the dataset
    /// was opened, so "Loaded ... from earlier analysis" would be wrong (drives
    /// 1 and 2B) — including after a reopen-continue-save. The file may still
    /// carry earlier analysis; the help says so.
    static func explainer(savedThisSession: Bool) -> (text: String, help: String) {
        if savedThisSession {
            return ("Saved with the dataset",
                    "A session sidecar written beside this dataset in this session. "
                    + "It may also carry earlier analysis restored when the dataset was "
                    + "opened. It is restored the next time the dataset is opened.")
        }
        return ("Loaded with the dataset — from earlier analysis",
                "A session sidecar saved beside this dataset. It carries "
                + "the calibration and results of earlier analysis, and was "
                + "restored when the dataset was opened — nothing here was "
                + "computed in this session.")
    }

    /// The Calibration row's title: a calibration the file holds but this view
    /// refused is not "loaded".
    static func calibrationRowTitle(refusedForThisView: Bool) -> String {
        refusedForThisView ? "Calibration — not used in this view" : "Calibration"
    }
}
