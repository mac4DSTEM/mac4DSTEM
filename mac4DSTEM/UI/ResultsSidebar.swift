import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results workspace's sidebar (v2.5 step 7c slice 1, plan §11d): the
/// saved-product chooser that was a third column inside the Results detail
/// pane. With Results gaining its own inspector, that column would have made
/// three right-hand panels; the Mac shape is choose here, view in the pane,
/// read the descriptor in the inspector. The comparison view stays with the
/// pane it compares. First of the five workspace sidebars `ContentView`
/// composes; one file each.
struct ResultsSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Saved products") {
            if appState.sessionInventory.results.isEmpty {
                Text("Nothing saved yet. Save to Session keeps the visible result with this dataset, available after reopening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .sidebarWrapped()
                    .accessibilityIdentifier("results.nothingSaved")
            } else {
                ForEach(appState.sessionInventory.results) { result in
                    savedProductRow(result)
                }
            }
            if let controls = appState.selectedSavedControlRehydration {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved settings available")
                        .font(.caption.weight(.medium))
                    Text(controls.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .sidebarWrapped()
                    Button("Apply Saved Controls") { appState.applySelectedSavedControls() }
                        .controlSize(.small)
                        .disabled(appState.isBusy)
                        .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
                }
                .padding(.top, 4)
            }
        }
    }

    private func savedProductRow(_ result: SessionResultDescriptor) -> some View {
        let isCurrent = result.id == appState.sessionInventory.currentResultID
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                Task { await appState.selectSavedSessionResult(result) }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isCurrent ? "eye.fill" : (result.storage == .rgba8 ? "paintpalette" : "map"))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName)
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .lineLimit(2)
                        Text("\(result.width) × \(result.height) · \(result.valueUnits)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let sampling = SessionResultPresentation.sampling(
                            row: result.pixelSizeRow, column: result.pixelSizeColumn,
                            units: result.pixelUnits
                        ) {
                            Text(sampling)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Displays this saved result")

            HStack(spacing: 6) {
                Button("A") { Task { await appState.loadSavedSessionResult(result, into: .a) } }
                    .buttonStyle(.bordered)
                    .help("Load into comparison A")
                    .accessibilityLabel("Load \(result.displayName) into comparison A")
                Button("B") { Task { await appState.loadSavedSessionResult(result, into: .b) } }
                    .buttonStyle(.bordered)
                    .help("Load into comparison B")
                    .accessibilityLabel("Load \(result.displayName) into comparison B")
                Spacer()
                Button(role: .destructive) {
                    Task { await appState.removeSavedSessionResult(result) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isBusy)
                .help("Remove saved result")
                .accessibilityLabel("Remove \(result.displayName)")
            }
            .controlSize(.small)
            .padding(.leading, 26)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.savedResult")
    }
}
