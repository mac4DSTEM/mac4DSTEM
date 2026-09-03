import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Guided front end for the bounded canonical DataCube writer. Defaults are
/// deliberately lossless (full scan, Q bin 1); every destructive reduction is
/// visible in the output preview before the save panel appears.
struct PreprocessingExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let descriptor: DatasetDescriptor

    @State private var cropEnabled = false
    @State private var xStart: Int
    @State private var xEnd: Int
    @State private var yStart: Int
    @State private var yEnd: Int
    @State private var qBin = 1
    @State private var showUncalibratedWarning = false

    init(descriptor: DatasetDescriptor) {
        self.descriptor = descriptor
        _xStart = State(initialValue: 0)
        _xEnd = State(initialValue: max(0, descriptor.rx - 1))
        _yStart = State(initialValue: 0)
        _yEnd = State(initialValue: max(0, descriptor.ry - 1))
    }

    private var scanX: Range<Int> {
        cropEnabled ? xStart..<(xEnd + 1) : 0..<descriptor.rx
    }

    private var scanY: Range<Int> {
        cropEnabled ? yStart..<(yEnd + 1) : 0..<descriptor.ry
    }

    private var outputShape: [Int] {
        [scanY.count, scanX.count, descriptor.qy / qBin, descriptor.qx / qBin]
    }

    private var estimatedBytes: Double {
        outputShape.reduce(Double(MemoryLayout<Float>.size)) { $0 * Double($1) }
    }

    private var readiness: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    private var missingCalibrationSummary: String {
        readiness.missingItems.map(\.kind.rawValue).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Preprocess & Export DataCube").font(.headline)
                Text("Canonical py4DSTEM EMD · float32 · chunked · atomic")
                    .font(.caption).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            Form {
                Section("Calibration readiness") {
                    CalibrationReadinessChecklist()
                    if !readiness.isReady {
                        Text("Missing fields are allowed only after an explicit export warning; no value is invented.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Real-space crop") {
                    Toggle("Crop scan", isOn: $cropEnabled)
                    if cropEnabled {
                        Stepper("X start  \(xStart)", value: $xStart,
                                in: 0...max(0, xEnd))
                        Stepper("X end  \(xEnd)", value: $xEnd,
                                in: xStart...max(xStart, descriptor.rx - 1))
                        Stepper("Y start  \(yStart)", value: $yStart,
                                in: 0...max(0, yEnd))
                        Stepper("Y end  \(yEnd)", value: $yEnd,
                                in: yStart...max(yStart, descriptor.ry - 1))
                    }
                }

                Section("Diffraction binning") {
                    Stepper("Integer Q bin  \(qBin)×", value: $qBin,
                            in: 1...max(1, min(descriptor.qy, descriptor.qx)))
                    Text("Bins are summed to preserve detector counts. Incomplete bottom/right blocks are trimmed, matching py4DSTEM bin_Q.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Output preview") {
                    LabeledContent("Shape", value: outputShape.map(String.init).joined(separator: " × "))
                    LabeledContent("Float32 data", value: ByteCountFormatter.string(
                        fromByteCount: Int64(estimatedBytes), countStyle: .file
                    ))
                    if descriptor.qy % qBin != 0 || descriptor.qx % qBin != 0 {
                        Label(
                            "Trims \(descriptor.qy % qBin) detector row(s) and \(descriptor.qx % qBin) column(s)",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Destination…") {
                    if readiness.isReady {
                        beginExport()
                    } else {
                        showUncalibratedWarning = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isBusy)
            }
        }
        .padding(20)
        // A band, not a fixed size (`WindowPolicy`; contract rule 1).
        .frame(
            minWidth: WindowPolicy.exportSheet.min.width,
            idealWidth: WindowPolicy.exportSheet.ideal.width,
            minHeight: WindowPolicy.exportSheet.min.height,
            idealHeight: WindowPolicy.exportSheet.ideal.height
        )
        .alert("Export with missing calibration?", isPresented: $showUncalibratedWarning) {
            Button("Keep Calibrating", role: .cancel) {}
            Button("Export Uncalibrated Anyway", role: .destructive) {
                beginExport()
            }
        } message: {
            Text("Missing: \(missingCalibrationSummary). Values stay in pixels or are omitted.")
        }
    }

    private func beginExport() {
        let options = CalibratedDataCubeExportOptions(
            scanY: scanY, scanX: scanX, qBin: qBin, tileRows: 1
        )
        dismiss()
        appState.exportCalibratedDataCube(options: options)
    }
}
