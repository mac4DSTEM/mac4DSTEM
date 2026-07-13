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
                        HistogramView(pixels: image.pixels, version: appState.resultVersion,
                                      rangeLo: Bindable(appState).displayRangeLo,
                                      rangeHi: Bindable(appState).displayRangeHi)
                        Text("Drag the handles to clip which intensities map into the image.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        gammaControl("Gamma", value: Bindable(appState).resultGamma)
                    }
                }

                if let pattern = appState.displayedPattern {
                    Section("Histogram (diffraction)") {
                        HistogramView(
                            pixels: pattern.contrastPixels(useLog: appState.logScale),
                            version: appState.patternVersion,
                            rangeLo: Bindable(appState).patternDisplayRangeLo,
                            rangeHi: Bindable(appState).patternDisplayRangeHi
                        )
                        Text(appState.logScale
                             ? "Contrast is selected on the log10(1 + intensity) axis."
                             : "Drag the handles to set the CBED intensity window.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        gammaControl("Gamma", value: Bindable(appState).patternGamma)
                    }
                }

                if let rotation = appState.lastRotationResult {
                    Section("Rotation diagnostics") {
                        RotationCurveView(result: rotation)
                            .frame(height: 90)
                        Text("Mean |curl| vs angle — solid: as-is, dashed: transposed. The marker is the chosen minimum.")
                            .font(.caption2).foregroundStyle(.tertiary)
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

    private func gammaControl(_ label: String, value: Binding<Float>) -> some View {
        HStack {
            Text(label).font(.caption)
            Slider(value: value, in: 0.2...3)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
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

/// Line plot of the rotation-calibration objective curves — the data was
/// always computed by RotationCalibration.solve; now it's actually shown, so
/// a flat or multi-minimum curve (an untrustworthy calibration) is visible.
struct RotationCurveView: View {
    let result: RotationCalibration.Result

    var body: some View {
        Canvas { context, size in
            let all = result.objectiveCurve + result.objectiveCurveTransposed
            guard let lo = all.min(), let hi = all.max(), hi > lo,
                  result.anglesDeg.count > 1 else { return }
            let n = result.anglesDeg.count

            func path(_ curve: [Float]) -> Path {
                Path { p in
                    for i in 0..<n {
                        let x = CGFloat(i) / CGFloat(n - 1) * size.width
                        let y = size.height * (1 - CGFloat((curve[i] - lo) / (hi - lo)))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y))
                               : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            context.stroke(path(result.objectiveCurve),
                           with: .color(.accentColor), lineWidth: 1.2)
            context.stroke(path(result.objectiveCurveTransposed),
                           with: .color(.secondary),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            // Marker at the chosen angle.
            let chosenDeg = result.rotationRad * 180 / .pi
            if let first = result.anglesDeg.first, let last = result.anglesDeg.last, last > first {
                let fx = CGFloat((chosenDeg - first) / (last - first)) * size.width
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: fx, y: 0))
                        p.addLine(to: CGPoint(x: fx, y: size.height))
                    },
                    with: .color(.red.opacity(0.7)), lineWidth: 1)
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
    }
}
