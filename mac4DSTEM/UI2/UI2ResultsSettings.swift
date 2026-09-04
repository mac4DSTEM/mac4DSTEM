import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results workspace's inspector Settings tab: the saved-product chooser
/// that was the old `ResultsSidebar`. It moves unchanged in substance — same
/// rows, same wording, same identifiers — from a `.sidebar` List (where
/// `LabeledContent` crushed onto one line) into the inspector's grouped
/// `Form`, where it stacks as intended. Body is bare `Section`s for the
/// caller's `Form`.
struct UI2ResultsSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Saved products") {
            if appState.sessionInventory.results.isEmpty {
                Text("Nothing saved yet. Save to Session keeps the visible result with this dataset, available after reopening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("results.nothingSaved")
            } else {
                ForEach(appState.sessionInventory.results) { result in
                    savedProductRow(result)
                }
            }
            if let controls = appState.selectedSavedControlRehydration {
                Text("Saved settings available")
                    .fontWeight(.medium)
                Text(controls.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Saved Controls") { appState.applySelectedSavedControls() }
                    .disabled(appState.isBusy)
                    .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
            }
        }
    }

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

        LabeledContent("Compare") {
            HStack(spacing: 6) {
                Button("A") { Task { await appState.loadSavedSessionResult(result, into: .a) } }
                    .help("Load into comparison A")
                    .accessibilityLabel("Load \(result.displayName) into comparison A")
                Button("B") { Task { await appState.loadSavedSessionResult(result, into: .b) } }
                    .help("Load into comparison B")
                    .accessibilityLabel("Load \(result.displayName) into comparison B")
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)

        // Its own row: alongside A/B, "Remove" truncated to "Remo…" in the
        // 250pt capture (2026-09-03) — three bordered controls do not fit
        // one Compare row at the column minimum.
        Button(role: .destructive) {
            Task { await appState.removeSavedSessionResult(result) }
        } label: {
            Label("Remove", systemImage: "trash")
        }
        .controlSize(.small)
        .disabled(appState.isBusy)
        .help("Remove saved result")
        .accessibilityLabel("Remove \(result.displayName)")
    }
}
