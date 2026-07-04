//
//  SidebarView.swift
//  Role: Left panel. File opening, the list of discovered datasets, a manual
//        HDF5-path override (for files whose layout we don't auto-detect), the
//        quick detector presets, and the grayed-out ML placeholder.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @Binding var showImporter: Bool
    @State private var manualPath = ""

    var body: some View {
        List {
            // MARK: File
            Section("File") {
                Button {
                    showImporter = true
                } label: {
                    Label("Open .h5 File…", systemImage: "folder")
                }
                if let d = app.descriptor {
                    LabeledContent("Loaded", value: d.fileName)
                        .font(.caption)
                }
            }

            // MARK: Datasets
            if !app.datasets.isEmpty {
                Section("Datasets") {
                    ForEach(app.datasets) { d in
                        Button {
                            app.selectDataset(d)
                        } label: {
                            HStack {
                                Image(systemName: app.descriptor?.id == d.id
                                      ? "checkmark.circle.fill" : "cube")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(shortPath(d.datasetPath))
                                        .lineLimit(1)
                                    Text(d.shapeString)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: Manual path
            Section("Manual dataset path") {
                TextField("/path/inside/the/h5", text: $manualPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Button("Open Path") {
                    let p = manualPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !p.isEmpty { app.openManualPath(p) }
                }
                .disabled(manualPath.isEmpty)
            }

            // MARK: Calibration
            Section("Calibration") {
                Picker("Origin fit", selection: $app.originFitFunction) {
                    ForEach(OriginFitFunction.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                Button {
                    Task { await app.calibrateOrigin() }
                } label: {
                    Label("Calibrate Origin", systemImage: "scope")
                }
                .disabled(!app.hasDataset || app.isBusy)

                if let r = app.calibration.probeRadius {
                    LabeledContent("Probe radius",
                                   value: String(format: "%.1f px", r))
                        .font(.caption)
                }
                if let o = app.calibration.origin {
                    LabeledContent("Fit residual",
                                   value: String(format: "%.3f px RMS", o.rmsResidual))
                        .font(.caption)
                }

                Button {
                    Task { await app.calibrateRotation() }
                } label: {
                    Label("Calibrate Rotation", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .disabled(!app.hasDataset || app.isBusy)
                .help("Find the scan–detector rotation by minimizing the curl "
                      + "of the CoM field. Runs origin calibration first if needed.")

                if let rot = app.calibration.rotationRad {
                    LabeledContent("R–Q rotation",
                                   value: String(format: "%.1f°%@", rot * 180 / .pi,
                                                 (app.calibration.transposeQR ?? false)
                                                 ? " ⊤" : ""))
                        .font(.caption)
                }
            }

            // MARK: Detector geometry
            Section("Virtual detector") {
                Picker("Shape", selection: $app.virtualShape) {
                    ForEach(VirtualShapeMode.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!app.hasDataset)
                .onChange(of: app.virtualShape) {
                    app.commitApertureChange()
                }

                ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                    Button(preset.rawValue) { app.applyDetectorPreset(preset) }
                        .disabled(!app.hasDataset)
                }
            }

            // MARK: Disk detection
            Section("Disk detection") {
                Button {
                    Task { await app.generateProbeKernel() }
                } label: {
                    Label("Generate Probe Kernel", systemImage: "circle.circle")
                }
                .disabled(!app.hasDataset || app.isBusy)
                .help("Synthetic probe from the calibrated radius. "
                      + "Runs origin calibration first if needed.")

                if let k = app.probeKernel {
                    LabeledContent("Kernel",
                                   value: String(format: "r %.1f px, trench %.0f–%.0f",
                                                 k.probeRadius,
                                                 k.trenchRadii.inner, k.trenchRadii.outer))
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "Correlation power  %.2f", app.diskParams.corrPower))
                        .font(.caption)
                    Slider(value: $app.diskParams.corrPower, in: 0...1)
                }
                Picker("Subpixel", selection: $app.diskParams.subpixel) {
                    ForEach(SubpixelMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.menu)
                Stepper(value: $app.diskParams.minPeakSpacing, in: 0...500, step: 1) {
                    Text(String(format: "Min spacing  %.0f px", app.diskParams.minPeakSpacing))
                        .font(.caption)
                }
                Stepper(value: $app.diskParams.maxNumPeaks, in: 1...500, step: 1) {
                    Text("Max peaks  \(app.diskParams.maxNumPeaks)")
                        .font(.caption)
                }

                Button {
                    Task { await app.runDiskDetection() }
                } label: {
                    Label("Detect All Disks", systemImage: "rays")
                }
                .disabled(!app.hasDataset || app.isBusy)

                if let n = app.braggPeakCount {
                    LabeledContent("Peaks found", value: "\(n)")
                        .font(.caption)
                }
            }

            // MARK: DPC
            Section("DPC") {
                Picker("Display", selection: $app.dpcDisplay) {
                    ForEach(DPCDisplayMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!app.hasDataset || app.analysisMode != .dpc)
                if app.analysisMode == .dpc && !app.calibration.hasFittedOrigin {
                    Text("Tip: calibrate the origin first — DPC shifts are then "
                         + "measured against the fitted beam position.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if app.analysisMode == .dpc && !app.calibration.hasRotation {
                    Text("Tip: calibrate the rotation to align detector and "
                         + "scan axes — required for meaningful iDPC.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: ML placeholder
            Section("Machine Learning") {
                Label("ML Analysis (coming soon)", systemImage: "brain")
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    private func shortPath(_ p: String) -> String {
        (p as NSString).lastPathComponent.isEmpty ? p : (p as NSString).lastPathComponent
    }
}
