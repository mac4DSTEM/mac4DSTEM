//
//  DatasetInspector.swift
//  Role: Right panel. A read-only-ish inspector showing dataset metadata
//        (shape, dtype, chunking, accelerating voltage) plus the live scan
//        position and aperture geometry. This is the "what am I looking at"
//        reference while exploring.
//

import SwiftUI

struct DatasetInspector: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            if let d = app.descriptor {
                Section("Dataset") {
                    row("File", d.fileName)
                    row("Path", d.datasetPath, mono: true)
                    row("Shape", d.shapeString, mono: true)
                    row("dtype", d.dtypeDescription, mono: true)
                    row("Chunks", d.chunkShape.map {
                        $0.map(String.init).joined(separator: " × ")
                    } ?? "contiguous", mono: true)
                    row("Size (f32)", byteString(d.byteCountAsFloat32))
                }

                Section("Dimensions") {
                    row("Scan (Ry × Rx)", "\(d.ry) × \(d.rx)")
                    row("Detector (Qy × Qx)", "\(d.qy) × \(d.qx)")
                    if let kV = app.acceleratingVoltage {
                        row("Accel. voltage", String(format: "%.0f kV", kV))
                    }
                }

                Section("Current scan position") {
                    row("x (Rx)", "\(app.selectedScan.x)")
                    row("y (Ry)", "\(app.selectedScan.y)")
                    if let (lo, hi) = app.patternMinMax {
                        row("Pattern min", String(format: "%.3g", lo))
                        row("Pattern max", String(format: "%.3g", hi))
                    }
                }

                Section("Aperture (detector px)") {
                    row("Center x", String(format: "%.1f", app.aperture.centerX))
                    row("Center y", String(format: "%.1f", app.aperture.centerY))
                    row("Inner r", String(format: "%.1f", app.aperture.inner))
                    row("Outer r", String(format: "%.1f", app.aperture.outer))
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
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }
}
