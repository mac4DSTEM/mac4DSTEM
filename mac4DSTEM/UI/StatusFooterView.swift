import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// D2 (owner decision, 2026-09-01): the permanent status footer. The owner's
/// words — the strip "shows the progress of a process, useful, but … there
/// should be something static as well, info that is currently in the
/// performance status under diagnostics … shown all the time".
///
/// Left: the status line (the former bare inset Text, now a stacked strip
/// so it can never overprint the log — R5). Middle: a slim live progress bar
/// with Cancel whenever a cancellable operation runs, so long computes stay
/// visible and killable from every workspace (the header's busy-swap remains
/// its richer sibling where a header exists). Right: the standing facts —
/// app memory, cube working size, residency — always on. The inspector's
/// Performance block keeps the full detail (GPU name, working-set limit);
/// this is the glanceable subset. Values refresh with ordinary AppState
/// invalidations, which during any operation is continuous; at rest they are
/// as current as the last event, same as the inspector.
struct StatusFooterView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("status.bar")

            Spacer(minLength: 12)

            if appState.isBusy {
                HStack(spacing: 8) {
                    ProgressView(value: appState.progress)
                        .frame(width: WindowPolicy.inlineProgressWidth)
                    if let progress = appState.progress {
                        Text("\(Int(progress * 100)) %")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if appState.canCancelActiveOperation {
                        Button("Cancel", role: .cancel) {
                            appState.cancelActiveOperation()
                        }
                        .controlSize(.mini)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("status.footer.operation")
            }

            if let descriptor = appState.descriptor {
                Text(footerFacts(descriptor))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityIdentifier("status.footer.facts")
            }

            // The log's control lives on the bar the log opens above, the
            // way Xcode's debug area is toggled from its own bar (owner,
            // 2026-09-03). The toolbar button stays as the second door and
            // the keyboard route; both drive the same flag.
            if appState.hasDataset && !appState.isLoadingDataset {
                Button {
                    appState.navigation.showLogPane.toggle()
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .foregroundStyle(appState.navigation.showLogPane
                                         ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(appState.navigation.showLogPane
                      ? "Hide the output log" : "Show the output log")
                .accessibilityLabel("Toggle output log")
                .accessibilityIdentifier("status.footer.toggleLog")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No bar of its own (presentation contract rule 3, 2026-09-03). R5's
        // overprint cannot recur: the footer has been a stacked element under
        // a Divider since D2, never an inset over the log.
    }

    private func footerFacts(_ descriptor: DatasetDescriptor) -> String {
        let app = String(format: "%.0f MB app", SystemMonitor.residentMemoryMB())
        let cube = SystemMonitor.byteString(descriptor.byteCountAsFloat32) + " cube"
        return "\(app) · \(cube) · \(appState.residency.summary.lowercased())"
    }
}
