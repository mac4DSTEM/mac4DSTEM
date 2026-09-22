import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The process area beneath the science panes — Xcode's debug area (owner,
/// 2026-09-22 late, window-design.md §9.3): two panes side by side, Output
/// on the left and Lineage on the right, each shown or hidden by its own
/// button at the infobar's right end. The live run's numbers, once a Run
/// tab here, are the infobar's. `WorkspaceView` gives this view its exact
/// height; which panes are visible only changes what fills it — nothing here
/// can move the bar (the 2026-09-21 finding: the tab bar moved because a
/// tab's content did not fill the pane and the stack centred it).
struct BottomWorkspace: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let navigation = appState.navigation
        Group {
            if navigation.showsOutputPane && navigation.showsLineagePane {
                PaneSplit(storageKey: "workspace.processSplit.fraction") {
                    OutputPane()
                } trailing: {
                    LineagePane()
                }
            } else if navigation.showsLineagePane {
                LineagePane()
            } else {
                OutputPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A pane's header row: its name at the left, its one action at the right.
private struct PaneHeader<Action: View>: View {
    let title: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            action()
        }
        .controlSize(.small)
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.bottomTabBarHeight)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Output

/// The rolling output log, auto-scrolled to the latest line (ADR 034: copy,
/// search and filter are later work).
private struct OutputPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Output") {
                Button("Clear") { appState.activityLog.clear() }
                    .disabled(appState.activityLog.messages.isEmpty)
                    .help("Clears the output log")
                    .accessibilityIdentifier("bottomWorkspace.output.clear")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(appState.activityLog.messages.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
                    .padding(.vertical, 4)
                }
                .onChange(of: appState.activityLog.messages.count) {
                    if let target = ActivityLog.scrollTarget(forCount: appState.activityLog.messages.count) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
                .onAppear {
                    // `.onChange` never fires the first time the panel
                    // appears; the rows may not exist yet on this tick, so
                    // the scroll is deferred a runloop turn.
                    guard let target = ActivityLog.scrollTarget(forCount: appState.activityLog.messages.count) else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("bottomWorkspace.output")
    }
}

// MARK: - Lineage

/// The record of how the session got here, drawn as a chain — one node per
/// recorded step, in order, then the displayed product's provenance. A
/// chain, not yet a graph: the replay record is linear and carries no input
/// edges; the graph with rewind follows the record (ROADMAP, owner
/// 2026-09-22: "a graph view of some sort — open to discuss the details").
private struct LineagePane: View {
    @Environment(AppState.self) private var appState

    private static let recordedFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day().hour().minute()

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Lineage") {
                Text("Linear record — the graph with rewind follows the record")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
                    chain
                    provenance
                }
                .padding(LayoutPolicy.infobarHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("bottomWorkspace.lineage")
    }

    @ViewBuilder
    private var chain: some View {
        let steps = appState.replaySteps
        if steps.isEmpty {
            Text("No steps recorded yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: LayoutPolicy.inspectorRowSpacing) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                                .padding(.top, LayoutPolicy.inspectorRowSpacing)
                                .accessibilityHidden(true)
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.kind).font(.callout.weight(.medium))
                                Text(step.recorded, format: Self.recordedFormat)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !step.parameters.isEmpty {
                                    Text(step.parameters.sorted { $0.key < $1.key }
                                        .map { "\($0.key) = \($0.value)" }
                                        .joined(separator: "\n"))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1), \(step.kind)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var provenance: some View {
        if let product = appState.displayedProduct {
            Text("Provenance — \(product.displayName)")
                .font(.callout.weight(.semibold))
            ForEach(product.provenance.sorted { $0.key < $1.key }, id: \.key) { entry in
                HStack(alignment: .firstTextBaseline, spacing: LayoutPolicy.inspectorRowSpacing) {
                    Text(entry.key).foregroundStyle(.secondary)
                    Text(entry.value).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .font(.caption.monospaced())
            }
        } else {
            Text("No product is displayed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
