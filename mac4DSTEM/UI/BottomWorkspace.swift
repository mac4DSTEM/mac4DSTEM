import ShellControls
import ShellInspector
import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
/// The app's registration of the process area's panes (suite task 8: the area, its toggles and its split are ShellLayout's
/// `WorkspaceColumn`; Output is the shared pane, Lineage is this app's). Output on the left, Lineage on the right, each shown or hidden
/// by its own button at the infobar's right end.
extension ProcessPaneID {
    static let lineage = ProcessPaneID("lineage")
}

enum ProcessTabs {
    @MainActor static func all(activityLog: ActivityLog) -> [ProcessTab] {
        [ProcessTab.output { OutputPane(log: activityLog) },
         ProcessTab(id: .lineage, title: "Lineage", systemImage: "rectangle.trailinghalf.inset.filled") { LineagePane() }]
    }
}

// MARK: - Lineage

/// How the session got here, as the run graph (ADR 047, L3): one node per
/// recorded run, layered left to right, the selected run's record in a
/// trailing column (`LineageGraphView`). A session recorded before lineage
/// existed draws in order only, and says so. The displayed product's
/// provenance stays one disclosure below.
struct LineagePane: View {
    @Environment(AppState.self) private var appState
    @State private var activePathOnly = false
    @State private var showsProvenance = false

    var body: some View {
        let product = appState.displayedProduct
        let model = LineageGraphModel(
            lineage: appState.replay.lineage,
            productKind: product?.kind,
            productStep: product?.provenance["lineage_step"],
            activePathOnly: activePathOnly,
            producedSteps: appState.replay.producedStep)
        VStack(spacing: 0) {
            ProcessPaneHeader(title: "Lineage") { headerTrailing(model) }
            LineageGraphView(model: model, rewind: { step in
                Task { await appState.rewindLineage(to: step) }
            })
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
                    ForEach(product.provenance.filter { !ProvenanceKeyLabel.hiddenKeys.contains($0.key) }.sorted { $0.key < $1.key }, id: \.key) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: LayoutPolicy.inspectorRowSpacing) {
                            Text(ProvenanceKeyLabel.text(entry.key)).foregroundStyle(.secondary)
                                .help(entry.key)
                            Text(ProvenanceValueText.display(entry.value)).selectableText(ProvenanceValueText.display(entry.value)).help(entry.value)
                                .accessibilityValue(RoomAccessibilityText.exactValue(
                                    raw: entry.value, displayed: ProvenanceValueText.display(entry.value)) ?? "")
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

/// A provenance key as a person reads it. The keys are a data contract (they are written into
/// exports and sidecars as they are), so the raw key stays in the row's help and only the
/// label changes: `analysis_mode` reads "Analysis mode"; the phase-map counts
/// (`count_0_Aluminium (FCC)`) read "Positions: Aluminium (FCC)". A phase name keeps its own
/// spelling.
enum ProvenanceKeyLabel {
    /// Keys a reader is not shown (owner, 2026-10-06: no hash or JSON "in the user's face"): the quantification method's JSON
    /// and its full hash stay in the record for the restore and the export; the short `method` key still names the run.
    static let hiddenKeys: Set<String> = ["method_json", "method_hash"]
    static func text(_ key: String) -> String {
        if key == "count_not_indexed" { return "Positions: not indexed" }
        if key == "count_no_peaks" { return "Positions: no peaks" }
        if key.hasPrefix("count_") {
            let rest = key.dropFirst("count_".count)
            if let underscore = rest.firstIndex(of: "_"), Int(rest[..<underscore]) != nil {
                return "Positions: " + rest[rest.index(after: underscore)...]
            }
        }
        var stem = key
        var unit = ""
        for (suffix, symbol) in unitSuffixes where stem.hasSuffix(suffix) {
            stem = String(stem.dropLast(suffix.count))
            unit = " (\(symbol))"
            break
        }
        let spaced = stem.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst() + unit
    }

    /// Unit words at the end of a key, longest first, as the symbol a reader
    /// expects: `probe_defocus_angstrom` reads "Probe defocus (Å)".
    static let unitSuffixes: [(String, String)] = [
        ("_angstrom_cubed", "Å³"), ("_inv_angstrom", "Å⁻¹"), ("_inv_a", "Å⁻¹"),
        ("_angstrom", "Å"), ("_mrad", "mrad"), ("_nm", "nm"), ("_kev", "keV"), ("_deg", "°"), ("_rad", "rad"),
        ("_px", "px"),
    ]
}
