import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results workspace's inspector Settings tab: the saved-product chooser
/// that was the old `ResultsSidebar`. It moves unchanged in substance — same
/// rows, same wording, same identifiers — from a `.sidebar` List (where
/// `LabeledContent` crushed onto one line) into the inspector's Lightroom-
/// style vocabulary (`UI/InspectorRows.swift`), where it stacks as intended.
struct ResultsSettings: View {
    @Environment(AppState.self) private var appState
    @State private var pendingResultRemoval: SessionResultDescriptor?

    var body: some View {
        InspectorSection("Saved products") {
            if appState.sessionInventory.results.isEmpty {
                InspectorNote("Nothing saved yet. Save to Session keeps the visible result with this dataset, available after reopening.")
                    .accessibilityIdentifier("results.nothingSaved")
            } else {
                ForEach(appState.sessionInventory.results) { result in
                    savedProductRow(result)
                }
            }
            if let controls = appState.selectedSavedControlRehydration {
                Text("Saved settings available")
                    .fontWeight(.medium)
                InspectorNote(controls.summary)
                InspectorNote("Choose Dataset → Apply Saved Controls to use these settings.")
            }
        }
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
                Task { await appState.removeSavedSessionResult(result) }
            }
            Button("Cancel", role: .cancel) { pendingResultRemoval = nil }
        } message: { result in
            Text("This removes \(result.displayName) from the session sidecar.")
        }
    }

    /// The row's main tap target (select this saved result) is left as a
    /// native `Button` — its label is a multi-line composite (name, icon,
    /// dimensions, sampling caption), not a plain string, so the simple-
    /// string row API would drop that structure.
    @ViewBuilder
    private func savedProductRow(_ result: SessionResultDescriptor) -> some View {
        let isCurrent = result.id == appState.sessionInventory.currentResultID
        Button {
            Task { await appState.selectSavedSessionResult(result) }
        } label: {
            LabeledContent {
                if isCurrent {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } label: {
                Label(result.displayName, systemImage: result.storage == .rgba8 ? "paintpalette" : "map")
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text("\(result.width) × \(result.height) · \(result.valueUnits)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sampling = SessionResultPresentation.sampling(
                    row: result.pixelSizeRow, column: result.pixelSizeColumn,
                    units: result.pixelUnits
                ) {
                    Text(sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Displays this saved result")
        .accessibilityIdentifier("session.savedResult")

        InspectorRow("Compare") {
            HStack(spacing: 6) {
                Button("A") { Task { await appState.loadSavedSessionResult(result, into: .a) } }
                    .help("Load into comparison A")
                    .accessibilityLabel("Load \(result.displayName) into comparison A")
                Button("B") { Task { await appState.loadSavedSessionResult(result, into: .b) } }
                    .help("Load into comparison B")
                    .accessibilityLabel("Load \(result.displayName) into comparison B")
            }
            .labelsHidden()
        }
        .controlSize(.small)
        .buttonStyle(.bordered)

        // Its own row: alongside A/B, "Remove" truncated to "Remo…" in the
        // 250pt capture (2026-09-03) — three bordered controls do not fit
        // one Compare row at the column minimum.
        InspectorActionRow {
            InspectorAdaptiveButton("Remove", systemImage: "trash", help: "Remove saved result",
                                     role: .destructive) {
                pendingResultRemoval = result
            }
            // C4(a): removal rebuilds the sidecar too — same gate as the saves.
            .disabled(appState.isBusy || !appState.gates.mayWriteSidecar)
            .accessibilityLabel("Remove \(result.displayName)")
        }
    }
}
