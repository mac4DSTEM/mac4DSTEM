import SwiftUI

/// Live performance readout: the running operation + progress, process memory
/// (refreshed on a timeline), the resident-cube size, and GPU budget.
struct PerformanceView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isBusy {
                Text(appState.activeOperation ?? "Working…")
                    .font(.caption)
                if let progress = appState.progress {
                    ProgressView(value: progress) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(Int(progress * 100)) %").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().progressViewStyle(.linear)   // indeterminate
                }
            } else {
                labeled("Status", "Idle")
            }

            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                labeled("App memory", String(format: "%.0f MB", SystemMonitor.residentMemoryMB()))
            }
            if let descriptor = appState.descriptor {
                labeled("Cube (f32)", SystemMonitor.byteString(descriptor.byteCountAsFloat32))
            }
            labeled("GPU", SystemMonitor.gpuName)
            labeled("GPU budget", String(format: "%.0f MB", SystemMonitor.gpuWorkingSetMB))
        }
        .padding(.vertical, 2)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A file-tree-style view of the source dataset and what's been computed. Once
/// results persist to a companion `.h5`, this becomes the on-disk tree; for now
/// it shows the source plus in-memory products (provenance).
struct ProductsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let descriptor = appState.descriptor {
                treeRow(icon: "doc.text", text: descriptor.fileName, indent: 0)
                treeRow(icon: "cylinder", text: descriptor.datasetPath, indent: 1, mono: true)
            }

            Text("Computed this session")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 6)

            product("Origin calibration", done: appState.calibration.hasFittedOrigin)
            product("R–Q rotation", done: appState.calibration.hasRotation)
            product("Bragg disks", done: appState.braggVectors != nil,
                    detail: appState.braggPeakCount.map { "\($0) peaks" })
            product("Strain map", done: appState.strainMap != nil)
            product("Orientation map", done: appState.hasOrientationMap)

            Text("Saving results to a companion .h5 is planned.")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(.vertical, 2)
    }

    private func treeRow(icon: String, text: String, indent: Int, mono: Bool = false) -> some View {
        HStack(spacing: 6) {
            if indent > 0 { Spacer().frame(width: CGFloat(indent) * 12) }
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(text)
                .font(mono ? .caption2.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
    }

    private func product(_ name: String, done: Bool, detail: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.5))
            Text(name).font(.caption)
            Spacer()
            if let detail {
                Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
