import SwiftUI

/// D2 (owner decision, 2026-09-01): the permanent status footer. The owner's
/// words — the strip "shows the progress of a process, useful, but … there
/// should be something static as well, info that is currently in the
/// performance status under diagnostics … shown all the time".
///
/// Left: the status line (the former bare inset Text, now on an opaque bar
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
                        .frame(width: 96)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque (R5): the transparent inset drew the status string straight
        // over the log strip's last line.
        .background(.bar)
    }

    private func footerFacts(_ descriptor: DatasetDescriptor) -> String {
        let app = String(format: "%.0f MB app", SystemMonitor.residentMemoryMB())
        let cube = SystemMonitor.byteString(descriptor.byteCountAsFloat32) + " cube"
        return "\(app) · \(cube) · \(appState.residency.summary.lowercased())"
    }
}
