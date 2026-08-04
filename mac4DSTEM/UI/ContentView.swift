import AppKit
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
            UTType(filenameExtension: "mib"),
            UTType(filenameExtension: "raw"),
            UTType(filenameExtension: "xml")
        ].compactMap { $0 }
    }

    var body: some View {
        @Bindable var appState = appState
        return NavigationSplitView(columnVisibility: Binding(
            get: { appState.showToolsPane ? .all : .detailOnly },
            set: { appState.showToolsPane = $0 != .detailOnly }
        )) {
            List {
                if let descriptor = appState.descriptor, descriptor.is4D {
                    Section {
                        datasetCard(descriptor)
                    }

                    Section("Workspace") {
                        ForEach(WorkspaceArea.allCases) { area in
                            workspaceButton(area)
                        }
                        if let hint = ProductWorkflow.nextStepHint(
                            for: appState.workspaceArea,
                            readiness: appState.productWorkflowReadiness,
                            calibrationReady: appState.calibrationReadiness.isReady
                        ) {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("workspace.nextStepHint")
                        }
                    }

                    if !appState.workspaceArea.analysisModes.isEmpty {
                        Section("Task") {
                            ForEach(TaskPrerequisiteFamily.allCases) { family in
                                let modes = appState.workspaceArea.analysisModes
                                    .filter { $0.prerequisiteFamily == family }
                                if !modes.isEmpty {
                                    Text(family.groupLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier(
                                            "task.group.\(family.accessibilitySuffix)"
                                        )
                                    ForEach(modes) { taskButton($0) }
                                }
                            }
                            taskReadiness(appState.analysisMode)
                        }
                    }
                }

                if !appState.hasDataset {
                    Section("Dataset") {
                    Button {
                        appState.requestOpenDataset()
                    } label: {
                        Label(appState.hasDataset ? "Open Another…" : "Open Dataset…",
                              systemImage: "folder")
                    }
                    }
                }

                if let descriptor = appState.descriptor, descriptor.is4D {
                    if appState.workspaceArea == .prepare || appState.workspaceArea == .image {
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
                    }

                    if appState.workspaceArea != .results {
                        Section("Display") {
                        Toggle("Log diffraction", isOn: $appState.logScale)
                        if appState.patternScaleMradAvailable {
                            Picker("Q-scale units", selection: $appState.patternScaleUnit) {
                                ForEach(PatternScaleUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .help("Reciprocal shows the calibrated Q pixel units; mrad shows the direct scattering angle (θ ≈ λ·q from the accelerating voltage).")
                        }
                        Picker("Diffraction", selection: $appState.patternColormap) {
                            ForEach(ColormapKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        if appState.resultImage != nil {
                            Picker("Result", selection: $appState.resultColormap) {
                            ForEach(ColormapKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                            }
                        }
                        }
                    }

                    // CBED pattern source (current / mean / max) lives here when
                    // the diffraction pane is the active (blue) one.
                    if (appState.workspaceArea == .prepare || appState.workspaceArea == .image)
                        && appState.activePane == .diffraction {
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

                    if appState.workspaceArea == .prepare {
                        Section("Calibration") {
                            CalibrationReadinessChecklist()
                            CalibrationDetailsView()
                        }
                    }

                    if appState.workspaceArea == .image && appState.analysisMode == .virtualDetector {
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

                    if appState.workspaceArea == .image && appState.analysisMode == .dpc {
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
                            if appState.dpcDisplay == .idpc {
                                if let physical = appState.idpcPhysicalCalibration {
                                    LabeledContent("Output", value: "Projected phase (rad)")
                                        .font(.caption)
                                    LabeledContent(
                                        "Sampling",
                                        value: String(
                                            format: "%.4g Å · Q %.4g Å⁻¹/px",
                                            physical.rowSamplingAngstrom,
                                            physical.reciprocalAngstromPerDetectorPixel
                                        )
                                    )
                                    .font(.caption)
                                    LabeledContent("Boundary", value: "Symmetric zero pad · 2×")
                                        .font(.caption)
                                } else {
                                    Text("Qualitative iDPC: fitted origin maps, R–Q rotation, and calibrated real/reciprocal pixel sizes are required. Q in mrad also needs accelerating voltage.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    LabeledContent("Boundary", value: "Symmetric zero pad · 2×")
                                        .font(.caption)
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

                    if appState.workspaceArea == .map && appState.analysisMode == .disks {
                        Section("Disk detection") {
                            DiskDetectionControls()
                        }
                    }

                    if appState.workspaceArea == .map && appState.analysisMode == .strain {
                        Section("Strain") {
                            Picker("Reference", selection: $appState.strainReferenceMode) {
                                ForEach(StrainReferenceMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .accessibilityIdentifier("strain.reference")
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
                            .accessibilityIdentifier("strain.basis")
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
                            .disabled(appState.isBusy || !appState.hasCurrentBraggVectors)
                            if appState.diskDetectionSettingsAreStale {
                                Text("Detection settings changed — rerun Detect All Disks before strain.")
                                    .font(.caption2).foregroundStyle(.orange)
                            } else if appState.braggVectors == nil {
                                Text("Detect Bragg disks first (Map → Bragg disks).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if appState.strainMap != nil {
                                Picker("Component", selection: $appState.strainComponent) {
                                    ForEach(StrainComponent.allCases) { component in
                                        Text(component.rawValue).tag(component)
                                    }
                                }
                                .accessibilityIdentifier("strain.component")
                                if let map = appState.strainMap {
                                    LabeledContent(
                                        map.diagnostics.automaticBasis
                                            ? "Basis consensus" : "Basis support",
                                        value: String(
                                            format: "%.0f%% · %d/%d peaks",
                                            map.diagnostics.basisSupportFraction * 100,
                                            map.diagnostics.basisSupportCount,
                                            map.diagnostics.basisObservationCount
                                        )
                                    )
                                    .font(.caption)
                                    .accessibilityIdentifier("strain.diagnostics.basisSupport")
                                    LabeledContent(
                                        "Basis fit",
                                        value: String(
                                            format: "RMS %.3g px · κ %.2f",
                                            map.diagnostics.basisResidualPixels,
                                            map.diagnostics.basisConditionNumber
                                        )
                                    )
                                    .font(.caption)
                                    .accessibilityIdentifier("strain.diagnostics.basisFit")
                                    LabeledContent(
                                        "Local fits",
                                        value: String(
                                            format: "%.0f%% indexed · median RMS %.3g px",
                                            map.indexedFraction * 100,
                                            map.diagnostics.localResidualMedianPixels
                                        )
                                    )
                                    .font(.caption)
                                    .accessibilityIdentifier("strain.diagnostics.localFits")
                                    LabeledContent(
                                        "Reference inliers",
                                        value: "\(map.referencePositionCount)/\(map.diagnostics.referenceCandidateCount)"
                                    )
                                    .font(.caption)
                                    .accessibilityIdentifier("strain.diagnostics.referenceInliers")
                                }
                            }
                        }
                    }

                    if appState.workspaceArea == .reconstruct && appState.analysisMode == .ptychography {
                        Section("Reconstruction workflow") {
                            reconstructionProgress
                            Text("Start with a calibrated preview and alignment. Open single-slice ptychography only when you need iterative object/probe recovery.")
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
                                    .accessibilityLabel("Accelerating voltage (kV)")
                                    .accessibilityIdentifier("calibration.acceleratingVoltage")
                                Text("kV")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            DisclosureGroup("Single-slice ptychography") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Picker("Method", selection: $appState.ptychographyMethod) {
                                        ForEach(SingleslicePtychographyMethod.allCases) { method in
                                            Text(method.rawValue).tag(method)
                                        }
                                    }
                                    HStack {
                                        TextField(
                                            "Iterations", value: $appState.ptychographyIterations,
                                            format: .number
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        TextField(
                                            appState.ptychographyMethod == .gradientDescent
                                                ? "Step" : "DM/AP α",
                                            value: appState.ptychographyMethod == .gradientDescent
                                                ? $appState.ptychographyStepSize
                                                : $appState.ptychographyProjectionParameter,
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
                                    Toggle(
                                        "Limit object transmission to 1",
                                        isOn: $appState.ptychographyConstrainObjectAmplitude
                                    )
                                    Toggle(
                                        "Pure-phase object",
                                        isOn: $appState.ptychographyPurePhaseObject
                                    )
                                    .help("Sets reconstructed object amplitude to one after every iteration.")
                                    if !appState.ptychographyFixProbe {
                                        Toggle(
                                            "Recenter probe each iteration",
                                            isOn: $appState.ptychographyFixProbeCenterOfMass
                                        )
                                        Toggle(
                                            "Constrain probe support",
                                            isOn: $appState.ptychographyConstrainProbeAmplitude
                                        )
                                        if appState.ptychographyConstrainProbeAmplitude {
                                            HStack {
                                                TextField(
                                                    "Support radius",
                                                    value: $appState.ptychographyProbeAmplitudeRadius,
                                                    format: .number.precision(.fractionLength(0...3))
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                TextField(
                                                    "Edge width",
                                                    value: $appState.ptychographyProbeAmplitudeWidth,
                                                    format: .number.precision(.fractionLength(0...3))
                                                )
                                                .textFieldStyle(.roundedBorder)
                                            }
                                        }
                                    }
                                    Button {
                                        Task { await appState.runSingleslicePtychography() }
                                    } label: {
                                        Label("Reconstruct Object", systemImage: "circle.hexagongrid")
                                    }
                                    .disabled(appState.isBusy)
                                    .help("Runs the CPU exact-shape, full-batch py4DSTEM \(appState.ptychographyMethod.rawValue) reference engine.")
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
                                        title: "\(iterative.options.method.rawValue) error",
                                        values: iterative.errorHistory,
                                        scale: .logarithmic
                                    )
                                }
                            }

                            if let preview = appState.parallaxPreprocess {
                                DisclosureGroup("Run details") {
                                    VStack(alignment: .leading, spacing: 5) {
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
                                    }
                                }
                            } else {
                                Text("Requires a calibrated origin, R–Q rotation, Q/R pixel sizes, and accelerating voltage. Missing values are rejected rather than guessed.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if appState.workspaceArea == .map && appState.analysisMode == .acom {
                        ACOMControlsView()
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("mac4DSTEM")
            .navigationSplitViewColumnWidth(min: 250, ideal: 292, max: 340)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if appState.hasDataset {
                    ProductWorkspaceHeader()
                }

                if appState.hasDataset && appState.workspaceArea == .results {
                    ResultsWorkspace()
                } else {
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
                            WelcomeWorkspace()
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
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(appState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("status.bar")
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
                if appState.workspaceArea != .results {
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
            Button("Copy Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appState.errorMessage ?? "", forType: .string)
            }
            Button("Open Another…") {
                appState.errorMessage = nil
                appState.requestOpenDataset()
            }
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
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

    private func datasetCard(_ descriptor: DatasetDescriptor) -> some View {
        let readiness = appState.productWorkflowReadiness
        let coreCalibrated = readiness.hasOriginProbe && readiness.hasRotation
            && readiness.hasQScale && readiness.hasRScale && readiness.hasVoltage
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(descriptor.rx) × \(descriptor.ry) scan  ·  \(descriptor.qx) × \(descriptor.qy) detector")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Open Another…") { appState.requestOpenDataset() }
                    Button("Preprocess & Export…") { showPreprocessingExport = true }
                        .disabled(appState.isBusy)
                    Divider()
                    Button("Save Calibration") {
                        appState.saveCalibrationToSessionSidecar()
                    }
                    .disabled(appState.isBusy)
                    Button("Export Diffraction PNG…") {
                        appState.exportDiffractionImage()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Dataset actions")
            }

            HStack(spacing: 6) {
                Label(
                    coreCalibrated ? "Core calibrated" : "Calibration incomplete",
                    systemImage: coreCalibrated
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .foregroundStyle(coreCalibrated ? Color.green : Color.orange)
                Spacer()
                if !appState.sessionInventory.results.isEmpty {
                    Text("\(appState.sessionInventory.results.count) saved")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dataset \(descriptor.fileName)")
        .accessibilityIdentifier("dataset.card")
    }

    private func workspaceButton(_ area: WorkspaceArea) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectWorkspace(area)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: area.systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(area.title)
                            .font(.subheadline.weight(
                                appState.workspaceArea == area ? .semibold : .regular
                            ))
                        if area.isAdvanced {
                            Text("ADV")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(area.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if area == .results && !appState.sessionInventory.results.isEmpty {
                    Text("\(appState.sessionInventory.results.count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.workspaceArea == area ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .accessibilityLabel(area.title)
        .accessibilityIdentifier("workspace.\(area.rawValue)")
        .accessibilityHint(area.subtitle)
        .accessibilityAddTraits(appState.workspaceArea == area ? .isSelected : [])
    }

    private func taskButton(_ mode: AnalysisMode) -> some View {
        Button {
            appState.changeMode(mode)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.productTitle)
                        .font(.subheadline.weight(appState.analysisMode == mode ? .semibold : .regular))
                    Text(mode.productSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.analysisMode == mode ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .accessibilityLabel(mode.productTitle)
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
        .accessibilityAddTraits(appState.analysisMode == mode ? .isSelected : [])
    }

    @ViewBuilder
    private func taskReadiness(_ mode: AnalysisMode) -> some View {
        let missing = ProductWorkflow.prerequisites(
            for: mode,
            readiness: appState.productWorkflowReadiness
        )
        let guidance = ProductWorkflow.guidance(
            for: mode,
            readiness: appState.productWorkflowReadiness
        )
        if missing.isEmpty && guidance.isEmpty {
            Label("Ready with current dataset", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 3)
                .accessibilityLabel("Current task is ready")
        } else if missing.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Ready · limited interpretation", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(guidance, id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Improve in Prepare") { appState.selectWorkspace(.prepare) }
                    .font(.caption)
            }
            .padding(.top, 3)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(missing, id: \.self) { item in
                    Label(item, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if missing.contains(where: { $0.hasPrefix("Choose an ACOM")
                    || $0.hasPrefix("The selected ACOM") }) {
                    Text("Select the material in the ACOM controls below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if missing.contains(where: { $0 != "Detect Bragg disks first" }) {
                    Button("Go to Prepare") { appState.selectWorkspace(.prepare) }
                        .font(.caption)
                } else {
                    Button("Go to Bragg Disks") {
                        appState.changeMode(.disks)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 3)
            .accessibilityElement(children: .contain)
        }
    }

    private var reconstructionProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            reconstructionStep(
                "1", "Prepare preview",
                complete: appState.parallaxPreprocess != nil
            )
            reconstructionStep(
                "2", "Align virtual bright-field stack",
                complete: appState.parallaxAlignment?.isComplete == true
            )
            reconstructionStep(
                "3", "Fit and correct phase",
                complete: appState.parallaxCorrection != nil
            )
            reconstructionStep(
                "4", "Inspect or reconstruct products",
                complete: appState.singleslicePtychography != nil
                    || appState.parallaxSubpixel != nil
            )
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func reconstructionStep(_ number: String, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(complete ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(complete ? "Complete" : "Pending")
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
            .accessibilityLabel("Scan \(label) position")
            .accessibilityValue("\(value) of \(max(0, count - 1))")
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

/// Native 6/mmm key sharing the production hexagonal color function.
struct HexagonalIPFLegendView: View {
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
                                + SIMD3(1.0, 0.0, 0.0) * wr
                                + SIMD3(cos(.pi / 6), sin(.pi / 6), 0.0) * wt
                        )
                        let rgb = HexagonalOrientationSymmetry.ipfColor(direction: direction)
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
                Text("0001")
                Spacer()
                Text("11-20")
                Spacer()
                Text("10-10")
            }
            .font(.caption2.monospacedDigit())
            .frame(width: 142)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hexagonal inverse pole figure color key: 0001 red, 10-10 green, 11-20 blue")
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
