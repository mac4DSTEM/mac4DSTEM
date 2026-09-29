import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The process area beneath the science panes — Xcode's debug area
/// (docs/archive/v4/window-design.md §9.3): two panes side by side, Output
/// on the left and Lineage on the right, each shown or hidden by its own
/// button at the infobar's right end. The live run's numbers, once a Run
/// tab here, are the infobar's. `WorkspaceView` gives this view its exact
/// height; which panes are visible only changes what fills it — nothing
/// here can move the bar: a tab whose content doesn't fill the pane lets
/// the stack recenter it and the bar moves.
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

/// How the session got here, as the run graph (ADR 047, L3): one node per
/// recorded run, layered left to right, the selected run's record in a
/// trailing column (`LineageGraphView`). A session recorded before lineage
/// existed draws in order only, and says so. The displayed product's
/// provenance stays one disclosure below.
private struct LineagePane: View {
    @Environment(AppState.self) private var appState
    @State private var activePathOnly = false
    @State private var showsProvenance = false

    var body: some View {
        let product = appState.displayedProduct
        let model = LineageGraphModel(
            lineage: appState.replay.lineage,
            productKind: product?.kind,
            productStep: product?.provenance["lineage_step"],
            activePathOnly: activePathOnly)
        VStack(spacing: 0) {
            PaneHeader(title: "Lineage") { headerTrailing(model) }
            LineageGraphView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let product {
                Divider()
                provenance(product)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("bottomWorkspace.lineage")
    }

    @ViewBuilder
    private func headerTrailing(_ model: LineageGraphModel) -> some View {
        let total = model.lineage.nodes.count
        if total > 0 {
            Text(model.branchNodeCount > 0
                 ? "\(total) runs · \(model.branchNodeCount) on other branches"
                 : "\(total) run\(total == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if model.branchNodeCount > 0 || activePathOnly {
                Toggle("Active path only", isOn: $activePathOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityIdentifier("bottomWorkspace.lineage.activePathOnly")
            }
        }
    }

    private func provenance(_ product: DisplayedProduct) -> some View {
        DisclosureGroup(isExpanded: $showsProvenance) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(product.provenance.sorted { $0.key < $1.key }, id: \.key) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: LayoutPolicy.inspectorRowSpacing) {
                            Text(entry.key).foregroundStyle(.secondary)
                            Text(entry.value).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .font(.caption.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: LineageGraphMetrics.provenanceMaxHeight)
        } label: {
            Text("Provenance — \(product.displayName)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .padding(.vertical, 4)
    }
}
