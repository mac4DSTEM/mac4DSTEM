import SwiftUI

/// Live performance readout. The workspace header is the single progress and
/// cancellation surface; the inspector only provides supporting metrics.
struct PerformanceView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("Status", appState.isBusy
                    ? (appState.activeOperation ?? "Working…") : "Idle")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if let metrics = appState.activeOperationMetrics(at: context.date) {
                        labeled("Elapsed", duration(metrics.elapsed))
                        if let rate = metrics.unitsPerSecond {
                            labeled("Throughput", String(format: "%.1f positions/s", rate))
                        }
                        if let eta = metrics.eta {
                            labeled("ETA", duration(eta))
                        }
                    }
                    labeled("App memory", String(format: "%.0f MB", SystemMonitor.residentMemoryMB()))
                }
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
            // Monospaced digits: these values refresh continuously, and
            // proportional digits make the whole column jitter.
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }
}

/// A file-tree-style view of the source, in-memory products, and supported
/// objects discovered in the stable companion sidecar.
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
            product(
                "Bragg disks",
                done: appState.hasCurrentBraggVectors,
                detail: appState.diskDetectionSettingsAreStale
                    ? "settings changed · rerun"
                    : appState.braggPeakCount.map { "\($0) peaks" }
            )
            product("Strain map", done: appState.strainMap != nil)
            product("Orientation map", done: appState.hasOrientationMap)

            Text("Saved session sidecar")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 6)

            if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
                let sidecar = BraggVectorEMDWriter.sessionSidecarURL(
                    forSourcePath: descriptor.filePath
                )
                treeRow(icon: "externaldrive", text: sidecar.lastPathComponent, indent: 0)
                if appState.sessionInventory.hasCalibration {
                    treeRow(icon: "scope", text: "Calibration", indent: 1)
                }
                if appState.sessionInventory.hasBraggVectors {
                    treeRow(icon: "circle.grid.cross", text: "BraggVectors", indent: 1)
                }
                ForEach(appState.sessionInventory.results) { result in
                    HStack(spacing: 4) {
                        Button {
                            Task { await appState.selectSavedSessionResult(result) }
                        } label: {
                            savedResultRow(
                                result,
                                isCurrent: result.id == appState.sessionInventory.currentResultID
                            )
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            Task { await appState.removeSavedSessionResult(result) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.isBusy)
                        .help("Remove this saved result from the session sidecar")
                    }
                }
                if let controls = appState.selectedSavedControlRehydration {
                    Button {
                        appState.applySelectedSavedControls()
                    } label: {
                        Label("Apply Saved Controls", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appState.isBusy)
                    .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
                }
            } else {
                Text("No companion results saved yet.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func treeRow(icon: String, text: String, indent: Int, mono: Bool = false) -> some View {
        HStack(spacing: 8) {
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
        HStack(spacing: 8) {
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

    private func savedResultRow(_ result: SessionResultDescriptor, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer().frame(width: 12)
            Image(systemName: isCurrent ? "eye.fill" : (result.storage == .rgba8 ? "paintpalette" : "map"))
                .font(.caption2)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName).font(.caption).lineLimit(1)
                Text("\(result.width)×\(result.height) · \(result.storage == .rgba8 ? "RGBA8" : "float32") · \(result.valueUnits)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let sampling = SessionResultPresentation.sampling(
                    row: result.pixelSizeRow, column: result.pixelSizeColumn,
                    units: result.pixelUnits
                ) {
                    Text(sampling)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let provenance = SessionResultPresentation.provenance(result.provenance) {
                    Text(provenance)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .help("\(result.kind) · \(result.id)")
    }
}
