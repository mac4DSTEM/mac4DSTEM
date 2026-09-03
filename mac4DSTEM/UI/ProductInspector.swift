import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results inspector (v2.5 step 7c, plan §11g decision 2): what the
/// displayed product IS — units, frame, sampling, validity, quality fields,
/// provenance, origin — then the session inventory and the same Diagnostics
/// group the dataset inspector shows. Rendered by `WorkspaceInspector` while
/// the Results product pane holds the focus ring. Its own file because it is
/// a sibling of `DatasetInspector`, not a section of it.
struct ProductInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Product") {
                if let product = appState.displayedProduct {
                    productSummaryRows(product)
                } else {
                    Text("No result displayed")
                        .foregroundStyle(.secondary)
                    Text("Create an image, map or reconstruction; it appears here with its units, frame and provenance.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("inspector.product")
            if let product = appState.displayedProduct {
                qualityFieldsSection(product)
                overlaysSection(product)
                provenanceSection(product)
            }
            ProductsView()
            InspectorDiagnosticsGroup()
        }
        .formStyle(.grouped)
        // Contract rule 3: the grouped Form draws no ground over the
        // column's material (Gate D 2026-09-03, `ColumnMaterialTests`).
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func productSummaryRows(_ product: DisplayedProduct) -> some View {
        row("Name", product.displayName)
        row("Kind", product.kind.replacingOccurrences(of: "_", with: " "))
        row("Origin", product.origin == .computed
            ? "Computed this session" : "Restored from the session sidecar")
        row("Size", "\(product.width) × \(product.height) px", mono: true)
        row("Frame", Self.frameLabel(product.domain))
        row("Values", product.valueUnits)
        row("Status", Self.statusLabel(product.quantitativeStatus))
        // One wording authority for sampling, shared with the saved-result
        // rows: a product's pixel size reads the same everywhere it appears.
        row("Sampling",
            SessionResultPresentation.sampling(
                row: product.sampling.row, column: product.sampling.column,
                units: product.sampling.units
            ) ?? "not calibrated",
            mono: true)
        row("Valid", Self.validityLabel(product))
    }

    @ViewBuilder
    private func qualityFieldsSection(_ product: DisplayedProduct) -> some View {
        if !product.qualityFields.isEmpty {
            Section("Quality fields") {
                ForEach(product.qualityFields, id: \.name) { field in
                    row(field.name, field.units, mono: true)
                }
            }
        }
    }

    @ViewBuilder
    private func overlaysSection(_ product: DisplayedProduct) -> some View {
        if !product.overlays.isEmpty {
            Section("Overlays") {
                ForEach(product.overlays, id: \.kind) { overlay in
                    row(overlay.kind.replacingOccurrences(of: "_", with: " "), overlay.provenance)
                }
            }
        }
    }

    @ViewBuilder
    private func provenanceSection(_ product: DisplayedProduct) -> some View {
        Section("Provenance") {
            ForEach(product.provenance.keys.sorted(), id: \.self) { key in
                row(key, product.provenance[key] ?? "", mono: true)
            }
        }
    }

    static func frameLabel(_ domain: ProductDomain) -> String {
        switch domain {
        case .scan: "Scan (real space)"
        case .detector: "Detector (diffraction)"
        case .reconstruction: "Reconstruction"
        }
    }

    static func statusLabel(_ status: ProductQuantitativeStatus) -> String {
        switch status {
        case .quantitative: "Quantitative"
        case .relative: "Relative units"
        case .exploratory: "Exploratory"
        case .categorical: "Categorical"
        }
    }

    /// "N of M positions" — the validity mask is the product's own statement
    /// of where it has a value; an all-valid product says so in one word.
    static func validityLabel(_ product: DisplayedProduct) -> String {
        let total = product.validityMask.count
        let valid = product.validityMask.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard total > 0 else { return "no positions" }
        if valid == total { return "all \(total) positions" }
        return String(format: "%d of %d positions (%.0f%%)", valid, total,
                      Double(valid) / Double(total) * 100)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        inspectorRow(label, value, mono: mono)
    }
}
