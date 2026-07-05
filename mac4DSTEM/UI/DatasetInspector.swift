import SwiftUI

struct DatasetInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let descriptor = appState.descriptor {
                Section("Dataset") {
                    row("File", descriptor.fileName)
                    row("Path", descriptor.datasetPath, mono: true)
                    row("Shape", descriptor.shapeString, mono: true)
                    row("dtype", descriptor.dtypeDescription, mono: true)
                    row(
                        "Chunks",
                        descriptor.chunkShape.map { $0.map(String.init).joined(separator: " x ") } ?? "contiguous",
                        mono: true
                    )
                    row("Size (f32)", byteString(descriptor.byteCountAsFloat32))
                }

                Section("Dimensions") {
                    row("Scan (Ry x Rx)", "\(descriptor.ry) x \(descriptor.rx)")
                    row("Detector (Qy x Qx)", "\(descriptor.qy) x \(descriptor.qx)")
                    if let acceleratingVoltage = appState.acceleratingVoltage {
                        row("Accel. voltage", String(format: "%.0f kV", acceleratingVoltage))
                    }
                }

                Section("Current scan position") {
                    row("x (Rx)", "\(appState.selectedScan.x)")
                    row("y (Ry)", "\(appState.selectedScan.y)")
                    if let (lowerBound, upperBound) = appState.patternMinMax {
                        row("Pattern min", String(format: "%.3g", lowerBound))
                        row("Pattern max", String(format: "%.3g", upperBound))
                    }
                }

                Section("Aperture (detector px)") {
                    row("Center x", String(format: "%.1f", appState.aperture.centerX))
                    row("Center y", String(format: "%.1f", appState.aperture.centerY))
                    row("Inner r", String(format: "%.1f", appState.aperture.inner))
                    row("Outer r", String(format: "%.1f", appState.aperture.outer))
                }

                if let image = appState.resultImage {
                    Section("Histogram (real space)") {
                        HistogramView(pixels: image.pixels, version: appState.resultVersion)
                    }
                }

                Section("Performance") {
                    PerformanceView()
                }

                Section("Files & products") {
                    ProductsView()
                }
            } else {
                Text("No dataset loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 240)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(mono ? .caption.monospaced() : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func byteString(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 {
            return String(format: "%.2f GB", megabytes / 1024)
        }
        return String(format: "%.1f MB", megabytes)
    }
}
