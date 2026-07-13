import SwiftUI
import UniformTypeIdentifiers
import simd

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showPreprocessingExport = false

    private var h5Types: [UTType] {
        [
            UTType(filenameExtension: "h5"),
            UTType(filenameExtension: "hdf5"),
            UTType(filenameExtension: "emd"),
            UTType(filenameExtension: "dm4"),
            UTType(filenameExtension: "dm3"),
            .data
        ].compactMap { $0 }
    }

    var body: some View {
        @Bindable var appState = appState
        // The analysis-mode switcher lives in the toolbar (always visible), so
        // the sidebar is free to hold just the active mode's controls — and can
        // now be hidden without losing mode switching.
        return NavigationSplitView(columnVisibility: Binding(
            get: { appState.showToolsPane ? .all : .detailOnly },
            set: { appState.showToolsPane = $0 != .detailOnly }
        )) {
            List {
                Section("File") {
                    Button {
                        appState.requestOpenDataset()
                    } label: {
                        Label("Open Dataset…", systemImage: "folder")
                    }
                    if appState.hasDataset {
                        Button {
                            showPreprocessingExport = true
                        } label: {
                            Label("Preprocess & Export…", systemImage: "shippingbox")
                        }
                        .disabled(appState.isBusy)
                        Menu {
                            Button("Result Image as PNG…") { appState.exportResultImage() }
                            Button("Save Current Result to Session Sidecar") {
                                appState.saveCurrentResultToSessionSidecar()
                            }
                            .disabled((appState.resultImage == nil && appState.resultRGBA == nil)
                                      || appState.isBusy)
                            Button("Save Calibration to Session Sidecar") {
                                appState.saveCalibrationToSessionSidecar()
                            }
                            .disabled(appState.isBusy)
                            Divider()
                            Button("Diffraction Pattern as PNG…") { appState.exportDiffractionImage() }
                            Button("Bragg Peaks as CSV…") { appState.exportBraggPeaksCSV() }
                                .disabled(appState.braggVectors == nil)
                            Button("py4DSTEM BraggVectors Sidecar…") {
                                appState.exportBraggVectorsEMD()
                            }
                            .disabled(appState.braggVectors == nil || appState.isBusy)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let descriptor = appState.descriptor, descriptor.is4D {
                    Section("Scan position") {
                        scanSlider(label: "X", value: appState.selectedScan.x,
                                   count: descriptor.rx) { x in
                            appState.selectScan(x: x, y: appState.selectedScan.y)
                        }
                        scanSlider(label: "Y", value: appState.selectedScan.y,
                                   count: descriptor.ry) { y in
                            appState.selectScan(x: appState.selectedScan.x, y: y)
                        }
                    }

                    Section("Display") {
                        Toggle("Log scale", isOn: $appState.logScale)
                        Picker("Colormap", selection: $appState.colormap) {
                            ForEach(ColormapKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                    }

                    // CBED pattern source (current / mean / max) lives here when
                    // the diffraction pane is the active (blue) one.
                    if appState.activePane == .diffraction {
                        Section("Pattern") {
                            if appState.meanPattern != nil {
                                Picker("Show", selection: $appState.patternDisplayMode) {
                                    ForEach(PatternDisplayMode.allCases) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .pickerStyle(.segmented)
                            } else {
                                Button {
                                    Task { await appState.computeDPStatistics() }
                                } label: {
                                    Label("Compute Mean / Max", systemImage: "sum")
                                }
                                .disabled(appState.isBusy)
                                Text("One pass over the cube; also computed by origin calibration.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Calibration") {
                        LabeledContent("Aperture center",
                                       value: appState.calibration.originProvenance.displayName)
                            .font(.caption)
                            .help("Source of the center used by the virtual-detector aperture. Per-position fitted origins are reported separately.")

                        Picker("Origin fit", selection: $appState.originFitFunction) {
                            ForEach(OriginFitFunction.allCases) { fit in
                                Text(fit.rawValue).tag(fit)
                            }
                        }
                        Button {
                            Task { await appState.calibrateOrigin() }
                        } label: {
                            Label("Calibrate Origin", systemImage: "scope")
                        }
                        .disabled(appState.isBusy)
                        Button {
                            Task { await appState.calibrateRotation() }
                        } label: {
                            Label("Calibrate Rotation", systemImage: "rotate.3d")
                        }
                        .disabled(appState.isBusy)

                        if let radius = appState.calibration.probeRadius {
                            LabeledContent("Probe radius",
                                           value: String(format: "%.1f px", radius))
                                .font(.caption)
                        }
                        if let residual = appState.calibration.origin?.rmsResidual {
                            LabeledContent("Fit residual",
                                           value: String(format: "%.3f px RMS", residual))
                                .font(.caption)
                        }
                        if let rotation = appState.calibration.rotationRad {
                            let transposed = (appState.calibration.transposeQR ?? false) ? " ⊤" : ""
                            LabeledContent("R–Q rotation",
                                           value: String(format: "%.1f°%@", rotation * 180 / .pi, transposed))
                                .font(.caption)
                            Button {
                                appState.flipRotation180()
                            } label: {
                                Label("Flip 180°", systemImage: "arrow.uturn.left.circle")
                            }
                                .help("The curl method can't tell θ from θ + 180°. If iDPC contrast is inverted, flip it here.")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ellipse fit annulus").font(.caption)
                            HStack {
                                TextField(
                                    "inner",
                                    value: $appState.ellipseFitInnerRadius,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                                Text("to").font(.caption2).foregroundStyle(.secondary)
                                TextField(
                                    "outer",
                                    value: $appState.ellipseFitOuterRadius,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                                Text("px").font(.caption2).foregroundStyle(.secondary)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            Task { await appState.calibrateEllipse() }
                        } label: {
                            Label("Fit Ellipse", systemImage: "oval")
                        }
                        .disabled(appState.isBusy)
                        .help("Fits the detector-shaped Bragg map when displayed; otherwise fits the scan-mean diffraction pattern. The annulus must contain a ring with broad angular coverage.")
                        if appState.calibration.hasEllipse,
                           let a = appState.calibration.ellipseA,
                           let b = appState.calibration.ellipseB,
                           let theta = appState.calibration.ellipseTheta {
                            LabeledContent(
                                "Ellipse correction",
                                value: String(format: "a %.4g · b %.4g · θ %.1f°",
                                              a, b, theta * 180 / .pi)
                            )
                            .font(.caption)
                            .help("Applied to calibrated Bragg maps, strain, and ACOM in py4DSTEM's qx/qy convention.")
                            if let fit = appState.lastEllipseFit {
                                LabeledContent(
                                    "Ellipse residual",
                                    value: String(format: "%.3f · %d/36 sectors",
                                                  fit.normalizedResidual,
                                                  fit.occupiedAngularBins)
                                )
                                .font(.caption)
                            }
                        }

                        // Pixel sizes: auto-filled from DM4 metadata, editable
                        // (and the only way in for plain HDF5). Drives the
                        // scale bars; 0 = uncalibrated (bars show px).
                        pixelSizeField("r px size",
                                       value: appState.calibration.rPixelSize,
                                       units: appState.calibration.rPixelUnits,
                                       defaultUnits: "nm",
                                       onChange: appState.setManualRPixelSize)
                        pixelSizeField("q px size",
                                       value: appState.calibration.qPixelSize,
                                       units: appState.calibration.qPixelUnits,
                                       defaultUnits: "1/nm",
                                       onChange: appState.setManualQPixelSize)
                    }

                    if appState.analysisMode == .virtualDetector {
                        if appState.activePane == .diffraction {
                            Section("Detector → real space") {
                                Picker("Shape", selection: $appState.virtualShape) {
                                    ForEach(VirtualShapeMode.allCases) { shape in
                                        Text(shape.rawValue).tag(shape)
                                    }
                                }
                                .pickerStyle(.segmented)

                                ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                                    Button(preset.rawValue) {
                                        appState.applyDetectorPreset(preset)
                                    }
                                }
                                Text("Drag the detector on the diffraction pane; the real-space image updates live.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Section("Region → diffraction") {
                                Picker("Shape", selection: $appState.realSpaceShape) {
                                    ForEach(RegionShape.allCases) { shape in
                                        Text(shape.rawValue).tag(shape)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if appState.realSpaceShape != .point, let d = appState.descriptor {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Radius  \(Int(appState.realSpaceRadius)) px").font(.caption)
                                        Slider(value: $appState.realSpaceRadius,
                                               in: 1...Float(max(d.rx, d.ry) / 2))
                                    }
                                }
                                Text(appState.realSpaceShape == .point
                                     ? "Drag on the real-space image to scrub the diffraction pattern."
                                     : "Drag the region on the real-space image; the summed pattern updates live.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if appState.analysisMode == .dpc {
                        Section("DPC") {
                            Picker("Display", selection: $appState.dpcDisplay) {
                                ForEach(DPCDisplayMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }

                            if appState.dpcDisplay == .magnitudeMrad {
                                if let scale = appState.dpcMilliradiansPerDetectorPixel {
                                    LabeledContent(
                                        "Angular scale",
                                        value: String(format: "%.5g mrad / detector px", scale)
                                    )
                                    .font(.caption)
                                } else {
                                    Text("mrad needs accelerating voltage and Q pixel calibration.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !appState.calibration.hasFittedOrigin {
                                Text("Tip: calibrate the origin first — DPC shifts are measured against the fitted beam position.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if !appState.calibration.hasRotation {
                                Text("Tip: calibrate the rotation for meaningful iDPC and vector direction.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if appState.analysisMode == .disks {
                        Section("Disk detection") {
                            Button {
                                Task { await appState.generateProbeKernel() }
                            } label: {
                                Label("Generate Probe Kernel", systemImage: "circle.circle")
                            }
                            .disabled(appState.isBusy)
                            Button {
                                Task { await appState.generateMeasuredProbeKernel() }
                            } label: {
                                Label("Use Current CBED / ROI", systemImage: "scope")
                            }
                            .disabled(appState.isBusy || appState.displayedPattern == nil)
                            .help("Select a vacuum point or real-space ROI, then build the disk-correlation kernel from its displayed diffraction pattern.")
                            if let kernel = appState.probeKernel {
                                LabeledContent("Kernel",
                                               value: String(format: "%@ · %.1f px",
                                                             kernel.source.rawValue, kernel.probeRadius))
                                    .font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Correlation power  %.2f", appState.diskParams.corrPower))
                                    .font(.caption)
                                Slider(value: $appState.diskParams.corrPower, in: 0...1)
                            }
                            Picker("Subpixel", selection: $appState.diskParams.subpixel) {
                                ForEach(SubpixelMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Stepper(value: $appState.diskParams.maxNumPeaks, in: 1...500) {
                                Text("Max peaks  \(appState.diskParams.maxNumPeaks)").font(.caption)
                            }

                            Button {
                                Task { await appState.runDiskDetection() }
                            } label: {
                                Label("Detect All Disks", systemImage: "rays")
                            }
                            .disabled(appState.isBusy)
                            if let count = appState.braggPeakCount {
                                LabeledContent("Peaks found", value: "\(count)").font(.caption)
                            }
                        }
                    }

                    if appState.analysisMode == .strain {
                        Section("Strain") {
                            Picker("Reference", selection: $appState.strainReferenceMode) {
                                ForEach(StrainReferenceMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            if appState.strainReferenceMode == .selectedRegion {
                                Text("The visible \(appState.realSpaceShape.rawValue.lowercased()) ROI around the selected scan point is treated as unstrained.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Picker("Basis", selection: $appState.strainBasisMode) {
                                ForEach(StrainBasisMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            if appState.strainBasisMode == .manual {
                                HStack {
                                    Text("g₁").frame(width: 18, alignment: .leading)
                                    TextField("x", value: $appState.strainG1X,
                                              format: .number.precision(.fractionLength(3)))
                                    TextField("y", value: $appState.strainG1Y,
                                              format: .number.precision(.fractionLength(3)))
                                }
                                HStack {
                                    Text("g₂").frame(width: 18, alignment: .leading)
                                    TextField("x", value: $appState.strainG2X,
                                              format: .number.precision(.fractionLength(3)))
                                    TextField("y", value: $appState.strainG2Y,
                                              format: .number.precision(.fractionLength(3)))
                                }
                                Text("Detector x/y offsets in calibrated pixels.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await appState.runStrainMapping() }
                            } label: {
                                Label("Compute Strain Map", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            .disabled(appState.isBusy || appState.braggVectors == nil)
                            if appState.braggVectors == nil {
                                Text("Detect Bragg disks first (Disks mode → Detect All Disks).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if appState.strainMap != nil {
                                Picker("Component", selection: $appState.strainComponent) {
                                    ForEach(StrainComponent.allCases) { component in
                                        Text(component.rawValue).tag(component)
                                    }
                                }
                            }
                        }
                    }

                    if appState.analysisMode == .ptychography {
                        Section("Parallax preprocessing") {
                            Text("Builds py4DSTEM's normalized virtual bright-field stack, aligns it, and can publish a sampling-limited KDE reconstruction.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("Voltage").font(.caption)
                                Spacer()
                                TextField("0", value: Binding(
                                    get: { appState.acceleratingVoltage ?? 0 },
                                    set: appState.setManualAcceleratingVoltage
                                ), format: .number.precision(.fractionLength(0...2)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Text("kV")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            GroupBox("Single-slice ptychography") {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        TextField(
                                            "Iterations", value: $appState.ptychographyIterations,
                                            format: .number
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        TextField(
                                            "Step", value: $appState.ptychographyStepSize,
                                            format: .number.precision(.fractionLength(0...3))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        TextField(
                                            "Norm min", value: $appState.ptychographyNormalizationMinimum,
                                            format: .number.precision(.fractionLength(0...3))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                    }
                                    Toggle("Fix probe", isOn: $appState.ptychographyFixProbe)
                                    Button {
                                        Task { await appState.runSingleslicePtychography() }
                                    } label: {
                                        Label("Reconstruct Object", systemImage: "circle.hexagongrid")
                                    }
                                    .disabled(appState.isBusy)
                                    .help("Runs the CPU exact-shape, full-batch py4DSTEM gradient-descent reference engine.")
                                }
                            }

                            if appState.parallaxAlignment?.isComplete == true {
                                HStack {
                                    TextField(
                                        "Auto factor", value: $appState.parallaxKDEUpsampleFactor,
                                        format: .number.precision(.fractionLength(0...3))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    TextField(
                                        "KDE σ", value: $appState.parallaxKDESigmaPixels,
                                        format: .number.precision(.fractionLength(0...3))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }
                                HStack {
                                    TextField(
                                        "Lanczos (0=off)", value: $appState.parallaxKDELanczosOrder,
                                        format: .number
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    TextField(
                                        "Position iters", value: $appState.parallaxPositionCorrectionIterations,
                                        format: .number
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }
                                Toggle("Sinc low-pass", isOn: $appState.parallaxKDELowpass)
                                if appState.parallaxPositionCorrectionIterations > 0 {
                                    Toggle(
                                        "Checkerboard position steps",
                                        isOn: $appState.parallaxPositionCorrectionCheckerboard
                                    )
                                }
                                Button {
                                    Task { await appState.upsampleParallaxBF() }
                                } label: {
                                    Label("Upsample BF", systemImage: "arrow.up.left.and.arrow.down.right")
                                }
                                .disabled(appState.isBusy)
                                .help("Zero factor selects py4DSTEM's BF/DF sampling heuristic; σ is specified in input pixels.")
                            }

                            Button {
                                Task { await appState.prepareParallaxPreview() }
                            } label: {
                                Label("Prepare Parallax Preview", systemImage: "waveform.path.ecg.rectangle")
                            }
                            .disabled(appState.isBusy)

                            HStack {
                                Button {
                                    Task { await appState.alignParallaxNextLevel() }
                                } label: {
                                    Label("Align Next Level", systemImage: "align.horizontal.center")
                                }
                                .disabled(
                                    appState.isBusy
                                        || appState.parallaxPreprocess == nil
                                        || appState.parallaxAlignment?.isComplete == true
                                )
                                .help("Runs the next py4DSTEM coarse-to-fine alignment bin with factor-8 matrix-DFT subpixel correlation.")

                                if appState.parallaxAlignment != nil {
                                    Button("Reset Alignment") {
                                        appState.resetParallaxAlignment()
                                    }
                                    .disabled(appState.isBusy)
                                    .help("Discard completed alignment levels and return to the immutable preprocessed preview.")
                                }
                            }

                            Button {
                                appState.fitParallaxAberrations()
                            } label: {
                                Label("Fit Aberrations", systemImage: "waveform.path")
                            }
                            .disabled(
                                appState.isBusy
                                    || appState.parallaxAlignment?.isComplete != true
                            )
                            .help("Fits py4DSTEM's low-order polar decomposition and default recursive higher-order gradient basis without changing calibration.")

                            if appState.parallaxHigherOrderFit != nil {
                                HStack {
                                    TextField("Low-pass", value: $appState.parallaxQLowpassInvAngstrom,
                                              format: .number.precision(.fractionLength(0...4)))
                                        .textFieldStyle(.roundedBorder)
                                    TextField("High-pass", value: $appState.parallaxQHighpassInvAngstrom,
                                              format: .number.precision(.fractionLength(0...4)))
                                        .textFieldStyle(.roundedBorder)
                                    Text("Å⁻¹")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    Task { await appState.correctParallaxPhase() }
                                } label: {
                                    Label("Correct Phase", systemImage: "wand.and.stars")
                                }
                                .disabled(appState.isBusy)
                                .help("Applies the fitted even/odd aberration CTF. Zero cutoff values disable the corresponding Butterworth filter.")

                                HStack {
                                    TextField(
                                        "Depth start Å", value: $appState.parallaxDepthStartAngstrom,
                                        format: .number.precision(.fractionLength(0...1))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    TextField(
                                        "Depth end Å", value: $appState.parallaxDepthEndAngstrom,
                                        format: .number.precision(.fractionLength(0...1))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    TextField(
                                        "Planes", value: $appState.parallaxDepthPlaneCount,
                                        format: .number
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }
                                HStack {
                                    TextField(
                                        "Info limit Å⁻¹", value: $appState.parallaxDepthInformationLimit,
                                        format: .number.precision(.fractionLength(0...4))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    TextField(
                                        "Power", value: $appState.parallaxDepthInformationPower,
                                        format: .number.precision(.fractionLength(0...2))
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }
                                Toggle("Use full fitted CTF", isOn: $appState.parallaxDepthUseFullFit)
                                Button {
                                    Task { await appState.computeParallaxDepthSections() }
                                } label: {
                                    Label("Compute Depth Stack", systemImage: "square.3.layers.3d")
                                }
                                .disabled(appState.isBusy)
                            }

                            if !appState.availableParallaxProducts.isEmpty {
                                Picker(
                                    "Displayed product",
                                    selection: Binding(
                                        get: { appState.parallaxResultProduct },
                                        set: appState.showParallaxProduct
                                    )
                                ) {
                                    ForEach(appState.availableParallaxProducts) { product in
                                        Text(product.rawValue).tag(product)
                                    }
                                }
                                if let depth = appState.parallaxDepth {
                                    Picker(
                                        "Depth plane",
                                        selection: Binding(
                                            get: { appState.parallaxDepthSelectedIndex },
                                            set: appState.selectParallaxDepthPlane
                                        )
                                    ) {
                                        ForEach(depth.depthsAngstrom.indices, id: \.self) { index in
                                            Text(String(format: "%.1f Å", depth.depthsAngstrom[index]))
                                                .tag(index)
                                        }
                                    }
                                }
                                if let iterative = appState.singleslicePtychography {
                                    LabeledContent(
                                        "Ptychography",
                                        value: "\(iterative.errorHistory.count) iterations"
                                    )
                                    .font(.caption)
                                    ScientificHistoryPlot(
                                        title: "Ptychography GD error",
                                        values: iterative.errorHistory,
                                        scale: .logarithmic
                                    )
                                }
                            }

                            if let preview = appState.parallaxPreprocess {
                                LabeledContent("BF detector pixels",
                                               value: "\(preview.brightFieldPixelCount)")
                                    .font(.caption)
                                LabeledContent(
                                    "Stack",
                                    value: "\(preview.brightFieldPixelCount) × \(preview.stackHeight) × \(preview.stackWidth)"
                                )
                                .font(.caption)
                                LabeledContent(
                                    "Stack memory",
                                    value: ByteCountFormatter.string(
                                        fromByteCount: Int64(preview.residentStackByteCount),
                                        countStyle: .file
                                    )
                                )
                                .font(.caption)
                                LabeledContent(
                                    "Electron wavelength",
                                    value: String(format: "%.5f Å", preview.calibration.wavelengthAngstrom)
                                )
                                .font(.caption)
                                LabeledContent(
                                    "Probe-angle extent",
                                    value: String(format: "%.2f mrad", preview.maximumProbeAngleMrad)
                                )
                                .font(.caption)
                                LabeledContent(
                                    "Initial mismatch",
                                    value: String(format: "%.4f", preview.initialError)
                                )
                                .font(.caption)
                                if let alignment = appState.parallaxAlignment {
                                    Divider()
                                    LabeledContent(
                                        "Aligned level",
                                        value: "\(alignment.completedBins.count)/\(alignment.alignmentSchedule.count) · bin \(alignment.alignmentBin) · \(alignment.groups.count) groups"
                                    )
                                    .font(.caption)
                                    LabeledContent(
                                        "Bin schedule",
                                        value: alignment.alignmentSchedule
                                            .map(String.init).joined(separator: " → ")
                                    )
                                    .font(.caption)
                                    LabeledContent(
                                        "Correlation",
                                        value: "matrix DFT ×\(alignment.upsampleFactor)"
                                    )
                                    .font(.caption)
                                    LabeledContent(
                                        "Maximum shift",
                                        value: String(format: "%.2f px", alignment.maximumShiftPixels)
                                    )
                                    .font(.caption)
                                    LabeledContent(
                                        "Aligned mismatch",
                                        value: String(format: "%.4f", alignment.currentError)
                                    )
                                    .font(.caption)
                                    ScientificHistoryPlot(
                                        title: "Alignment mismatch",
                                        values: alignment.errorHistory,
                                        scale: .logarithmic
                                    )
                                    Text(alignment.isComplete
                                         ? "Coarse-to-fine alignment schedule complete; aberration fitting and correction remain pending."
                                         : "Continue with the next bin; cancellation retains this completed level.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let fit = appState.parallaxAberrationFit {
                                        Divider()
                                        LabeledContent(
                                            "Fitted rotation",
                                            value: String(
                                                format: "%.2f°",
                                                fit.rotationRad * 180 / .pi
                                            )
                                        )
                                        .font(.caption)
                                        LabeledContent(
                                            "C1",
                                            value: String(format: "%.1f Å", fit.c1Angstrom)
                                        )
                                        .font(.caption)
                                        LabeledContent(
                                            "C12a / C12b",
                                            value: String(
                                                format: "%.1f / %.1f Å",
                                                fit.c12aAngstrom, fit.c12bAngstrom
                                            )
                                        )
                                        .font(.caption)
                                        LabeledContent(
                                            "Shift-fit RMS",
                                            value: String(
                                                format: "%.4f Å",
                                                fit.rmsResidualAngstrom
                                            )
                                        )
                                        .font(.caption)
                                        Text("Diagnostic fit only; calibration and aligned data are unchanged.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let higher = appState.parallaxHigherOrderFit {
                                            LabeledContent(
                                                "Higher-order fit",
                                                value: "\(higher.terms.count) terms · \(higher.fitMethod.rawValue)"
                                            )
                                            .font(.caption)
                                            LabeledContent(
                                                "Higher-order RMS",
                                                value: String(
                                                    format: "%.4f Å",
                                                    higher.rmsResidualAngstrom
                                                )
                                            )
                                            .font(.caption)
                                            Text(
                                                zip(higher.terms, higher.coefficientsAngstrom)
                                                    .map { term, coefficient in
                                                        "C\(term.radialOrder)\(term.angularOrder)\(term.component == 0 ? "a" : "b") \(String(format: "%.1f", coefficient))"
                                                    }
                                                    .joined(separator: " · ")
                                            )
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        }
                                        if let correction = appState.parallaxCorrection {
                                            LabeledContent(
                                                "Phase correction",
                                                value: correction.usedFullFit
                                                    ? "full CTF · DC removed"
                                                    : "C1 fallback · DC removed"
                                            )
                                            .font(.caption)
                                        }
                                        if let subpixel = appState.parallaxSubpixel {
                                            LabeledContent(
                                                "KDE reconstruction",
                                                value: String(
                                                    format: "×%.2f · %.4f Å/px",
                                                    subpixel.upsampleFactor,
                                                    subpixel.outputSamplingAngstrom
                                                )
                                            )
                                            .font(.caption)
                                            LabeledContent(
                                                "KDE output",
                                                value: "\(subpixel.croppedBF.height) × \(subpixel.croppedBF.width)"
                                            )
                                            .font(.caption)
                                            if !subpixel.positionCorrectionScores.isEmpty {
                                                ScientificHistoryPlot(
                                                    title: "Position correction score",
                                                    values: subpixel.positionCorrectionScores
                                                )
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text("Requires a calibrated origin, R–Q rotation, Q/R pixel sizes, and accelerating voltage. Missing values are rejected rather than guessed.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if appState.analysisMode == .acom {
                        Section("ACOM (orientation)") {
                            Picker("Crystal", selection: $appState.acomCrystal) {
                                ForEach(CrystalChoice.allCases) { choice in
                                    Text(choice.rawValue).tag(choice)
                                }
                            }
                            if appState.acomCrystal == .custom {
                                Picker("Element", selection: $appState.customZ) {
                                    ForEach(ScatteringFactors.supportedElements, id: \.self) { z in
                                        Text("\(ScatteringFactors.symbols[z] ?? "?")  (Z=\(z))").tag(z)
                                    }
                                }
                                Picker("Structure", selection: $appState.customStructure) {
                                    ForEach(Crystal.CubicStructure.allCases) { s in
                                        Text(s.rawValue).tag(s)
                                    }
                                }
                                HStack {
                                    Text("a (Å)").font(.caption)
                                    TextField("a", value: $appState.customLatticeA,
                                              format: .number.precision(.fractionLength(0...4)))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                            }
                            Button {
                                Task { await appState.generateOrientationPlan() }
                            } label: {
                                Label("Generate Plan", systemImage: "cube.transparent")
                            }
                            .disabled(appState.isBusy)
                            if appState.hasOrientationPlan, let plan = appState.orientationPlan {
                                LabeledContent("Templates", value: "\(plan.count)").font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Å⁻¹ / pixel  %.4f", appState.acomScale)).font(.caption)
                                Slider(value: $appState.acomScale, in: 0.001...0.05)
                            }
                            Button {
                                Task { await appState.calibrateQFromCrystal() }
                            } label: {
                                Label("Calibrate Q from Crystal", systemImage: "ruler")
                            }
                            .disabled(appState.isBusy || appState.braggVectors == nil)
                            .help("Uses the median innermost detected Bragg radius and the selected crystal's first allowed reflection.")

                            Button {
                                Task { await appState.runACOM() }
                            } label: {
                                Label("Run ACOM", systemImage: "circle.grid.cross")
                            }
                            .disabled(appState.isBusy || appState.braggVectors == nil)
                            if appState.braggVectors == nil {
                                Text("Detect Bragg disks first (Disks → Detect All Disks).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if appState.hasOrientationMap {
                                Picker("Display", selection: $appState.acomDisplay) {
                                    ForEach(ACOMDisplayMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                if appState.acomDisplay == .ipfZ {
                                    CubicIPFLegendView()
                                }
                                if let text = appState.selectedEulerText {
                                    LabeledContent("Cubic FZ Euler", value: text)
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("mac4DSTEM")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        if appState.hasDataset {
                            HSplitView {
                                DiffractionView()
                                    .overlay(paneFocusBorder(active: appState.activePane == .diffraction))
                                    .contentShape(Rectangle())
                                    .onTapGesture { appState.activePane = .diffraction }
                                    .frame(minWidth: 220)
                                StemImageView()
                                    .overlay(paneFocusBorder(active: appState.activePane == .realSpace))
                                    .contentShape(Rectangle())
                                    .onTapGesture { appState.activePane = .realSpace }
                                    .frame(minWidth: 220)
                            }
                            .focusable()
                            .focusEffectDisabled()
                            .onKeyPress(phases: .down) { press in
                                handleArrowKey(press)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text("mac4DSTEM").font(.title)
                                Text(appState.statusText).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Output strip: rolling log of operations below the panes.
                    if appState.showLogPane && appState.hasDataset {
                        Divider()
                        logPane
                    }
                }
                // Hard floor so dragging the sidebar/inspector can't crush the
                // image panes into distorted slivers.
                .frame(minWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Inspector as an explicit, independent panel so it coexists
                // with the tools sidebar (both can be open at once).
                if appState.showInspectorPane {
                    Divider()
                    DatasetInspector()
                        .frame(width: 300)
                        .background(.background)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(appState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation { appState.showToolsPane.toggle() }
                    } label: {
                        Label("Toggle tools", systemImage: "sidebar.leading")
                    }
                    .help("Show or hide the tools panel")
                }
                ToolbarItem(placement: .principal) {
                    Picker("Analysis mode", selection: $appState.analysisMode) {
                        ForEach(AnalysisMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(!appState.hasDataset)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showLogPane.toggle()
                    } label: {
                        Label("Toggle output", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help("Show or hide the output log below the image panes")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showInspectorPane.toggle()
                    } label: {
                        Label("Toggle inspector", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the inspector panel")
                }
            }
        }
        .onChange(of: appState.analysisMode) {
            Task { await appState.runCurrentAnalysis() }
        }
        .onChange(of: appState.virtualShape) {
            appState.commitApertureChange()
        }
        .onChange(of: appState.realSpaceShape) {
            appState.updateRealSpaceRegion()
        }
        .onChange(of: appState.realSpaceRadius) {
            appState.updateRealSpaceRegion()
        }
        .onChange(of: appState.openDatasetRequest) {
            showImporter = true
        }
        .onChange(of: appState.preprocessingExportRequest) {
            if appState.hasDataset { showPreprocessingExport = true }
        }
        .sheet(isPresented: $showPreprocessingExport) {
            if let descriptor = appState.descriptor {
                PreprocessingExportSheet(descriptor: descriptor)
                    .environment(appState)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: h5Types,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appState.openFile(url: url)
                }
            case .failure(let error):
                appState.present(error)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    /// One pixel-size calibration row: numeric field + units label.
    /// Entering a value > 0 calibrates (setting default units if none);
    /// clearing to 0 returns to uncalibrated ("px" scale bars).
    private func pixelSizeField(_ label: String,
                                value: Double?,
                                units: String?,
                                defaultUnits: String,
                                onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            TextField("0", value: Binding(
                get: { value ?? 0 },
                set: onChange
            ), format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            Text(units ?? defaultUnits)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    /// Rolling output log below the image panes (auto-scrolls to the latest).
    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(appState.logMessages.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: appState.logMessages.count) {
                proxy.scrollTo(appState.logMessages.count - 1, anchor: .bottom)
            }
        }
        .frame(height: 100)
        .background(Color.black.opacity(0.15))
    }

    /// Arrow keys step the selected scan position (Shift = 10 px steps).
    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        guard let d = appState.descriptor else { return .ignored }
        let step = press.modifiers.contains(.shift) ? 10 : 1
        var x = appState.selectedScan.x
        var y = appState.selectedScan.y
        switch press.key {
        case .leftArrow:  x -= step
        case .rightArrow: x += step
        case .upArrow:    y -= step
        case .downArrow:  y += step
        default: return .ignored
        }
        appState.selectScan(x: min(max(0, x), d.rx - 1),
                            y: min(max(0, y), d.ry - 1))
        return .handled
    }

    /// Accent border marking the active pane.
    private func paneFocusBorder(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(1)
            .allowsHitTesting(false)
    }

    /// A labelled slider that scrubs one scan axis. `count` is the axis length;
    /// the callback receives the clamped integer index.
    private func scanSlider(label: String, value: Int, count: Int,
                            onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text("\(label) \(value)")
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...Double(max(count - 1, 1)),
                step: 1
            )
        }
    }
}

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
        appState.calibrationReadiness
    }

    private var missingCalibrationSummary: String {
        readiness.missingItems.map(\.kind.rawValue).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Preprocess & Export DataCube").font(.headline)
                    Text("Canonical py4DSTEM EMD · float32 · chunked · atomic")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Form {
                Section("Calibration readiness") {
                    ForEach(readiness.items) { item in
                        readinessRow(item)
                    }
                    if readiness.isReady {
                        Label("All calibration fields will be written to the DataCube.",
                              systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Missing fields are allowed only after an explicit export warning; no value is invented.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Real-space crop") {
                    Toggle("Crop scan", isOn: $cropEnabled)
                    if cropEnabled {
                        HStack {
                            Stepper("X start  \(xStart)", value: $xStart,
                                    in: 0...max(0, xEnd))
                            Stepper("X end  \(xEnd)", value: $xEnd,
                                    in: xStart...max(xStart, descriptor.rx - 1))
                        }
                        HStack {
                            Stepper("Y start  \(yStart)", value: $yStart,
                                    in: 0...max(0, yEnd))
                            Stepper("Y end  \(yEnd)", value: $yEnd,
                                    in: yStart...max(yStart, descriptor.ry - 1))
                        }
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
        .frame(width: 620, height: 720)
        .alert("Export with missing calibration?", isPresented: $showUncalibratedWarning) {
            Button("Keep Calibrating", role: .cancel) {}
            Button("Export Uncalibrated Anyway", role: .destructive) {
                beginExport()
            }
        } message: {
            Text("Missing: \(missingCalibrationSummary). Those fields will remain in pixel coordinates or be omitted from the output metadata.")
        }
    }

    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    item.kind.rawValue,
                    systemImage: item.status.isReady
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
                Spacer()
                Text(item.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
            }
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !item.status.isReady {
                readinessAction(for: item.kind)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func readinessAction(for kind: CalibrationReadinessKind) -> some View {
        switch kind {
        case .originProbe:
            Button("Measure Origin & Probe") {
                Task { await appState.calibrateOrigin() }
            }
            .disabled(appState.isBusy)
        case .ellipse:
            Button("Fit Detector Ellipse") {
                Task { await appState.calibrateEllipse() }
            }
            .disabled(appState.isBusy)
        case .rotation:
            Button("Measure R–Q Rotation") {
                Task { await appState.calibrateRotation() }
            }
            .disabled(appState.isBusy)
        case .qScale:
            HStack {
                if appState.braggVectors != nil {
                    Button("Calibrate from \(appState.acomCrystal.rawValue)") {
                        Task { await appState.calibrateQFromCrystal() }
                    }
                    .disabled(appState.isBusy)
                }
                manualScaleField(
                    value: appState.calibration.qPixelSize,
                    units: appState.calibration.qPixelUnits ?? "1/nm",
                    onChange: appState.setManualQPixelSize
                )
            }
        case .rScale:
            manualScaleField(
                value: appState.calibration.rPixelSize,
                units: appState.calibration.rPixelUnits ?? "nm",
                onChange: appState.setManualRPixelSize
            )
        }
    }

    private func manualScaleField(
        value: Double?, units: String, onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text("Manual")
                .font(.caption)
            TextField("0", value: Binding(
                get: { value ?? 0 }, set: onChange
            ), format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            Text("\(units)/px")
                .font(.caption)
                .foregroundStyle(.secondary)
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

/// Compact sampled m-3m inverse-pole-figure key. The map and legend share the
/// same color function, keeping the on-screen key aligned with exported pixels.
struct CubicIPFLegendView: View {
    var body: some View {
        VStack(spacing: 1) {
            Canvas { context, size in
                let left = SIMD2<Double>(4, Double(size.height - 3))
                let right = SIMD2<Double>(Double(size.width - 4), Double(size.height - 3))
                let top = SIMD2<Double>(Double(size.width / 2), 3)
                let steps = 36
                let radius = max(1.4, Double(size.width) / Double(steps) * 0.65)
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let direction = simd_normalize(
                            SIMD3(0.0, 0.0, 1.0) * wl
                                + simd_normalize(SIMD3(1.0, 0.0, 1.0)) * wr
                                + simd_normalize(SIMD3(1.0, 1.0, 1.0)) * wt
                        )
                        let rgb = CubicOrientationSymmetry.ipfColor(direction: direction)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(
                            red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)
                        )))
                    }
                }
            }
            .frame(width: 116, height: 62)
            HStack {
                Text("001")
                Spacer()
                Text("111")
                Spacer()
                Text("101")
            }
            .font(.caption2.monospacedDigit())
            .frame(width: 132)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cubic inverse pole figure color key: 001 red, 101 green, 111 blue")
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
