import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Xcode-style bottom workspace beneath the science panes (ADR 034, owner
/// 2026-09-21): "the inspector holds durable state and settings; the bottom
/// pane holds LIVE operational state." Three tabs — Output (the rolling log,
/// unchanged from the old always-on strip), Run (the live operation monitor,
/// replacing the inspector's deleted `PerformanceRows`), and Lineage (the
/// read-only record of what produced the product on screen).
///
/// `WorkspaceView` owns the infobar drag and gives this view its exact height.
/// Changing tabs only changes the content within that height.
struct BottomWorkspace: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab bar

    /// Left: the Output / Run / Lineage picker. Right: the one action each
    /// tab offers at this level — today only Output's "Clear".
    private var tabBar: some View {
        @Bindable var navigation = appState.navigation
        return HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
            Picker("Bottom workspace tab", selection: $navigation.bottomWorkspaceTab) {
                ForEach(BottomWorkspaceTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("bottomWorkspace.tabPicker")

            Spacer(minLength: 8)

            if navigation.bottomWorkspaceTab == .output {
                Button("Clear") { appState.activityLog.clear() }
                    .controlSize(.small)
                    .disabled(appState.activityLog.messages.isEmpty)
                    .help("Clears the output log")
                    .accessibilityIdentifier("bottomWorkspace.output.clear")
            }
        }
        .padding(.horizontal, LayoutPolicy.inspectorRowSpacing)
        .frame(height: LayoutPolicy.bottomTabBarHeight)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch appState.navigation.bottomWorkspaceTab {
        case .output: OutputTab()
        case .run: RunMonitorTab()
        case .lineage: LineageTab()
        }
    }
}

private extension BottomWorkspaceTab {
    var title: String {
        switch self {
        case .output: "Output"
        case .run: "Run"
        case .lineage: "Lineage"
        }
    }
}

// MARK: - Output tab

/// The rolling output log, auto-scrolled to the latest line — the old
/// always-on strip's `outputLog`, unchanged in behaviour (ADR 034: copy,
/// search and filter are later work, not this session's).
private struct OutputTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(appState.activityLog.messages.enumerated()), id: \.offset) { index, line in
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
            .onChange(of: appState.activityLog.messages.count) {
                if let target = ActivityLog.scrollTarget(forCount: appState.activityLog.messages.count) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
            .onAppear {
                // `.onChange` never fires the first time the panel appears,
                // so without this the tab opens scrolled to its top. The rows
                // from `ForEach` may not exist yet on this same tick, so the
                // scroll is deferred a runloop turn rather than run inline.
                guard let target = ActivityLog.scrollTarget(forCount: appState.activityLog.messages.count) else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Run tab

/// The live operation monitor, replacing the inspector's deleted
/// `PerformanceRows` (agent B, this session) as the one place the app's own
/// residency readout lives. Busy: every row ticks 1 s via `TimelineView`.
/// Idle: a static two-line view — `PerformanceRows` never expressed an
/// idle/busy distinction and always drew every row, which is why moving
/// residency here rather than restoring that struct.
private struct RunMonitorTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isBusy {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    busyRows(metrics: appState.activeOperationMetrics(at: context.date))
                }
            } else {
                idleRows
            }
        }
        .padding(LayoutPolicy.inspectorRowSpacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var idleRows: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            row("Step", "Idle")
            row("Engine", SystemMonitor.gpuName)
            if let last = appState.operationCenter.lastFinished {
                row("Last run", OperationMetricsFormat.lastRun(
                    last.name, elapsed: last.elapsed, cancelled: last.outcome == .cancelled))
            } else {
                Text("No runs yet this session.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func busyRows(metrics: AnalysisOperationMetrics?) -> some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            row("Step", appState.activeOperation ?? "Idle")
            row("Positions", positionsText)
            row("Throughput", metrics?.unitsPerSecond
                .map { OperationMetricsFormat.throughput($0, for: appState.activeOperation) } ?? "—")
            row("Streamed", appState.operationCenter.bytesStreamed
                .map { SystemMonitor.byteString(Int($0)) } ?? "—")
            row("Elapsed", metrics.map { OperationMetricsFormat.duration($0.elapsed) } ?? "—")
            // An explicit closure, not the point-free `.map(OperationMetricsFormat.duration)`
            // — the bare method reference tripped the actor-isolation checker
            // (measured in the scratch build), where every other call here
            // wraps the same static function in a closure without it.
            row("ETA", metrics?.eta.map { OperationMetricsFormat.duration($0) } ?? "—")
            row("Residency", residencyText)
            // The deleted inspector `PerformanceRows`' GPU fact (G5,
            // Gate-B): the Run tab is now the only place it is shown, read
            // from the same `SystemMonitor.gpuName` source that row read.
            row("Engine", SystemMonitor.gpuName)
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { appState.cancelActiveOperation() }
                    .disabled(!appState.canCancelActiveOperation)
                    .controlSize(.small)
                    .accessibilityIdentifier("bottomWorkspace.run.cancel")
            }
        }
    }

    private var positionsText: String {
        guard let done = appState.operationCenter.unitsDone, let total = appState.operationCenter.totalUnits else {
            return "—"
        }
        return "\(SystemMonitor.count(done)) / \(SystemMonitor.count(total))"
    }

    /// The full-sentence twin of the status strip's `memoryGlance` — same two
    /// facts (app resident memory, cube residency), spelled out rather than
    /// abbreviated to a fixed slot.
    private var residencyText: String {
        "\(appState.residency.summary) · \(String(format: "%.0f MB", SystemMonitor.residentMemoryMB())) app memory"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutPolicy.inspectorRowSpacing) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: LayoutPolicy.runMonitorLabelWidth, alignment: .trailing)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

// MARK: - Lineage tab

/// The read-only record of how the current session got here: the recorded
/// replay pipeline, then the provenance of whatever product is on screen.
/// Explicitly NOT the lineage graph with rewind the owner wants
/// (2026-09-21 interest note) — that is phased work behind the drive
/// clearing (ROADMAP.md); this is the linear record that exists today.
private struct LineageTab: View {
    @Environment(AppState.self) private var appState

    private static let recordedFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day().hour().minute()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
                stepsSection
                Divider()
                productSection
                Text("Linear record — the lineage graph with rewind follows (ROADMAP).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(LayoutPolicy.inspectorRowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Below: every row/detail rhythm in this tab is named from LayoutPolicy
    // (Gate-B G4) rather than left as a bare number. `inspectorRowSpacing`
    // (6 pt) is the closest existing constant to several of these — this
    // file has no exact match for a 2, 4 or 8 pt gap — so it is reused as
    // the nearest fit rather than left unnamed; see the session report for
    // the pt deltas that approximation costs at each site.

    @ViewBuilder
    private var stepsSection: some View {
        let steps = appState.replaySteps
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            Text("Recorded pipeline").font(.caption.weight(.semibold))
            if steps.isEmpty {
                Text("No steps recorded yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                        HStack {
                            Text(step.kind).font(.caption.weight(.medium))
                            Spacer()
                            Text(step.recorded, format: Self.recordedFormat)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !step.parameters.isEmpty {
                            Text(step.parameters.sorted { $0.key < $1.key }
                                .map { "\($0.key) = \($0.value)" }
                                .joined(separator: ", "))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var productSection: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            if let product = appState.displayedProduct {
                Text("Provenance — \(product.displayName)")
                    .font(.caption.weight(.semibold))
                ForEach(product.provenance.sorted { $0.key < $1.key }, id: \.key) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: LayoutPolicy.inspectorRowSpacing) {
                        Text(entry.key).foregroundStyle(.secondary)
                        Text(entry.value).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .font(.caption2.monospaced())
                }
            } else {
                Text("Provenance").font(.caption.weight(.semibold))
                Text("No product is displayed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
