import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The left column: navigation and nothing else. Every control that used to
/// share this column with the workspace/task lists (v1's `PrepareSidebar`,
/// `ImageSidebar`, `MapSidebar`, `PhaseSidebar`, `ResultsSidebar`, and the
/// dataset action menu) has moved into `UI2Inspector` — this view composes
/// none of them.
///
/// A source list, not a settings pane: selection, hover, the row capsule and
/// `AXOutlineRow` all come from the `List` itself, tagged with `UI2Route` so
/// selection binds straight onto `appState.ui2Route`.
struct UI2Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: appState.ui2Route) {
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
                    workspaceRow(area).tag(UI2Route.workspace(area))
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
                            taskRow(mode).tag(UI2Route.task(mode))
                        }
                    }
                }
            }

            UI2SessionSection()
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
struct UI2SessionSection: View {
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

    @ViewBuilder
    private var inventory: some View {
        if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
            let sidecar = appState.sessionSidecar.location(for: descriptor)
            VStack(alignment: .leading, spacing: 2) {
                Label(sidecar.lastPathComponent, systemImage: "externaldrive")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(contents)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(sidecar.lastPathComponent)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sidebar.session.sidecar")
        } else {
            Text("Nothing saved with this dataset yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sidebar.session.empty")
        }
    }

    /// What the sidecar actually holds — named, not counted, because
    /// "calibration" and "BraggVectors" are the two a reader cares whether
    /// they were restored.
    private var contents: String {
        var parts: [String] = []
        if appState.sessionInventory.hasCalibration { parts.append("calibration") }
        if appState.sessionInventory.hasBraggVectors { parts.append("BraggVectors") }
        let results = appState.sessionInventory.results.count
        if results > 0 { parts.append("\(results) result\(results == 1 ? "" : "s")") }
        return parts.isEmpty ? "no saved objects" : parts.joined(separator: " · ")
    }
}
