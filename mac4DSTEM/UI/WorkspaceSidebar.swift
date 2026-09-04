import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The left column: navigation and nothing else. Every control that used to
/// share this column with the workspace/task lists (v1's `PrepareSidebar`,
/// `ImageSidebar`, `MapSidebar`, `PhaseSidebar`, `ResultsSidebar`, and the
/// dataset action menu) has moved into `WorkspaceInspector` — this view composes
/// none of them.
///
/// A source list, not a settings pane: selection, hover, the row capsule and
/// `AXOutlineRow` all come from the `List` itself, tagged with `WorkspaceRoute` so
/// selection binds straight onto `appState.workspaceRoute`.
struct WorkspaceSidebar: View {
    @Environment(AppState.self) private var appState

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
                        // takes its one-line ideal and truncates — amended
                        // contract rule 5 says that is the choice, not a
                        // finding, but a hint nobody can finish reading is
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

            SessionSection()
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
        let produced = taskHasProduct(mode)
        return HStack {
            Label {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mode.productTitle)
                    if mode.isAdvanced {
                        Text("Advanced").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: mode.systemImage)
            }
            Spacer()
            Image(systemName: produced
                    ? "checkmark.circle.fill"
                    : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                .foregroundStyle(produced
                    ? Color.green
                    : (unmet == 0 ? Color.secondary : Color.orange))
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

    /// Whether this task has produced its product in this session — only for
    /// the tasks with an unambiguous retained product. Staleness is
    /// deliberately not folded in here; the result pane's own badge carries
    /// it. Virtual imaging and DPC share the single scalar result slot, so
    /// "has produced" is read from the recipe record — it survives the slot
    /// being replaced and resets with the dataset.
    private func taskHasProduct(_ mode: AnalysisMode) -> Bool {
        switch mode {
        case .disks: appState.hasCurrentBraggVectors
        case .strain: appState.strain.map != nil
        case .acom: appState.acomSession.hasOrientationMap
        case .virtualDetector:
            appState.replay.record.steps.contains { $0.kind == "virtual_detector" }
        case .dpc:
            appState.replay.record.steps.contains { $0.kind == "dpc" }
        case .ptychography, .singleslicePtychography: false
        }
    }

    /// Readiness is folded into the label rather than left on the glyph: an
    /// `accessibilityLabel` on a container replaces its children's, so a
    /// label on the image alone would never be announced.
    private func taskAccessibilityLabel(_ mode: AnalysisMode) -> String {
        if taskHasProduct(mode) { return "\(mode.productTitle), computed" }
        let unmet = taskUnmetCount(mode)
        if unmet == 0 { return "\(mode.productTitle), ready" }
        return "\(mode.productTitle), \(unmet) requirement\(unmet == 1 ? "" : "s") missing"
    }
}

// MARK: - What is loaded, and what session it carries

/// The bottom of the source list: which dataset is open and what saved
/// session came with it.
///
/// Owner, 2026-09-04. Two things drove this. The column below the task list
/// was empty, and — the reason it is THIS content and not a decoration — the
/// sidecar warnings sat one tab away in Info, where "an old sidecar loaded
/// with a cube" is exactly the case a user would not think to go looking for.
/// A saved session that cannot be read, or that describes a region this file
/// does not have, or that was computed on a different view, changes what every
/// number on screen means. Those three now sit in permanent view; the detail
/// stays in Info.
///
/// Rows here are List rows, not Form rows, so they stack explicitly —
/// `LabeledContent` would lay them out on one line and truncate.
struct SessionSection: View {
    @Environment(AppState.self) private var appState

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
    /// agree. Each is carried verbatim from the inspector's own wording, so
    /// the two surfaces cannot drift into describing the same state
    /// differently; the full explanation and the way out stay in Info.
    @ViewBuilder
    private var warnings: some View {
        if let reason = appState.sessionSidecar.unreadableReason {
            warning("A saved session beside this dataset could not be read.",
                    detail: reason,
                    identifier: "sidebar.session.unreadable")
        } else if let failure = appState.gates.sidecarRestoreFailure,
                  failure.kind == .doesNotFit {
            warning("The saved session describes a region this file does not have.",
                    detail: failure.message,
                    identifier: "sidebar.session.doesNotFit")
        } else if let recorded = appState.sessionLoadSpecification,
                  recorded != appState.loadedView.specification {
            warning("The saved session was computed on a different view of this file.",
                    detail: "Session: \(recorded.provenanceSummary ?? "whole file") · "
                        + "loaded: \(appState.loadedView.specification.provenanceSummary ?? "whole file")",
                    identifier: "sidebar.session.provenanceMismatch")
        }
    }

    private func warning(
        _ headline: String, detail: String, identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(headline, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .help("\(headline)\n\n\(detail)\n\nThe Info tab carries the full explanation.")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// What the sidecar holds, and the actions on it. Moved here from the
    /// Info panel on 2026-09-04 (owner): after loading a dataset the user
    /// should see on the LEFT what came with it. Info keeps the two sections
    /// that explain a sidecar the app could not read or could not fit — that
    /// is the half of the split the comment above deliberately kept there.
    ///
    /// Every row takes the `.sidebar` List's one-line ideal and truncates, so
    /// the detail a row cannot show is on `.help`, the same choice the
    /// next-step hint makes. Nothing here uses `.fixedSize()`: a split column
    /// may not change its own minimum (`docs/open-items.md`).
    @ViewBuilder
    private var inventory: some View {
        if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
            // Through the seam: this once derived the path itself, so a
            // bookmark resolving to a sidecar the user had RENAMED made the
            // app name a file it was not reading.
            let sidecar = appState.sessionSidecar.location(for: descriptor)
            // What this section IS, said once: the owner's note on first
            // seeing it was that nothing tells you these came from a file
            // loaded beside the cube rather than from this session's work.
            // Short enough to survive a sidebar row's one-line width; the
            // full sentence is on hover, the same choice the next-step hint
            // makes.
            Text("Loaded with the dataset — from earlier analysis")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("A session sidecar saved beside this dataset. It carries "
                      + "the calibration and results of earlier analysis, and was "
                      + "restored when the dataset was opened — nothing here was "
                      + "computed in this session.")
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
                Label("Calibration", systemImage: "scope")
                    .font(.caption)
                    .imageScale(.small)
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
            if let controls = appState.selectedSavedControlRehydration {
                Button {
                    appState.applySelectedSavedControls()
                } label: {
                    Label("Apply Saved Controls", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .imageScale(.small)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(appState.isBusy)
                .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
                .accessibilityIdentifier("sidebar.session.applySavedControls")
            }
            // Rename/relocate, offered where the user is already looking at
            // the filename — once a grant exists the save panel never
            // reappears on its own.
            Button {
                appState.saveSessionSidecarAs()
            } label: {
                Label("Change…", systemImage: "pencil")
                    .font(.caption)
                    .imageScale(.small)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(appState.isBusy)
            .help("Choose a new name or location for the session sidecar. Existing saved results are copied across.")
            .accessibilityIdentifier("sidebar.session.changeSidecar")
            Button {
                appState.reopenIgnoringSessionSidecar()
            } label: {
                Label("Ignore…", systemImage: "eye.slash")
                    .font(.caption)
                    .imageScale(.small)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Reopen this dataset without restoring the saved session; the sidecar file stays on disk")
            .accessibilityIdentifier("sidebar.session.reopenWithoutSession")
        } else {
            Text("Nothing saved with this dataset yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sidebar.session.empty")
        }
    }

    /// A saved result as a source-list row. The Info panel's version stacked
    /// three caption lines and a trailing sampling value under the name; a
    /// `.sidebar` row has no width to spend on them, so one caption line
    /// survives and the rest is on `.help`.
    ///
    /// Remove is in the row's context menu, NOT a second visible row per
    /// result as Info had it: two rows per saved result fills this column,
    /// and a right-click is the source-list idiom for acting on a row. This
    /// is the one judgement call in the move — it is placement, and it is the
    /// owner's to overrule on screen.
    @ViewBuilder
    private func savedResultRow(_ result: SessionResultDescriptor, isCurrent: Bool) -> some View {
        Button {
            Task { await appState.selectSavedSessionResult(result) }
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
                Task { await appState.removeSavedSessionResult(result) }
            } label: {
                Label("Remove \(result.displayName)", systemImage: "trash")
            }
            .disabled(appState.isBusy)
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
