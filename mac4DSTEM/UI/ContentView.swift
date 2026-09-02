import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import SwiftUI
import UniformTypeIdentifiers
import simd

/// Which display controls the sidebar's "Display" section offers, per
/// workspace.
///
/// Extracted so it can be tested. The rendered alternative cannot be: SwiftUI
/// builds a `Picker`'s `NSPopUpButton` menu lazily for a real assistive client,
/// so in-process the button carries no `itemTitles`, no `title`, no
/// `selectedItem` and `numberOfItems == 0` (measured 2026-08-06, the same wall
/// `SidebarLayoutTests` hit for accessibility identifiers). Counting anonymous
/// pop-up buttons would pass just as happily on the wrong one.
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
            get: {
                appState.navigation.showToolsPane && !appState.isLoadingDataset ? .all : .detailOnly
            },
            set: { appState.navigation.showToolsPane = $0 != .detailOnly }
        )) {
            // S22d: publish the column's real width so long sidebar texts can
            // wrap — this List never offers rows a width on its own (see
            // SidebarTextWidth.swift). The 34pt covers the row insets.
            GeometryReader { sidebarGeo in
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
                            for: appState.navigation.workspaceArea,
                            readiness: appState.productWorkflowReadiness,
                            calibrationReady: appState.calibrationSession.readiness.isReady
                        ) {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .sidebarWrapped()
                                .accessibilityIdentifier("workspace.nextStepHint")
                        }
                    }

                    if !appState.navigation.workspaceArea.analysisModes.isEmpty {
                        Section("Task") {
                            let groups = appState.navigation.workspaceArea.taskFamilyGroups
                            let showsLabels = appState.navigation.workspaceArea.showsTaskFamilyLabels
                            ForEach(groups) { group in
                                if showsLabels {
                                    Text(group.family.groupLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier(
                                            "task.group.\(group.family.accessibilitySuffix)"
                                        )
                                }
                                ForEach(group.modes) { taskButton($0) }
                            }
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
                    // D3 (owner decision, 2026-09-01): the colormap and
                    // display options moved ONTO the colorbar chips in the
                    // panes (`ColormapChipMenu`). That dissolves the old
                    // Results-scoping problem this sidebar section spent a
                    // long comment justifying: the chip exists wherever its
                    // image exists, so the control can never be stranded in a
                    // workspace without it.

                    if appState.navigation.workspaceArea == .prepare {
                        PrepareSidebar()   // v2.5 step 7c slice 2
                    }
                    if appState.navigation.workspaceArea == .image {
                        ImageSidebar()   // v2.5 step 7c slice 3
                    }
                    // DPC works from the live CBED too; the compute offer for
                    // its statistics is shared with Prepare and Imaging.
                    if appState.navigation.workspaceArea == .reconstruct
                        && appState.navigation.analysisMode == .dpc {
                        ComputePatternStatisticsSection()
                    }

                    if appState.navigation.workspaceArea == .reconstruct && appState.navigation.analysisMode == .dpc {
                        Section("DPC & iDPC") {
                            // S22b (O2): status first — what "Run DPC" will
                            // produce NOW — then the display choice, then the
                            // per-mode detail. The pane previously opened with
                            // a picker and buried its readiness in orange
                            // paragraphs inside one display branch ("just
                            // useless" — owner, 2026-09-01). The primary
                            // action stays single-homed in the workspace
                            // header, so the two cannot drift.
                            if appState.idpcPhysicalCalibration != nil {
                                Label("Physical iDPC ready — projected phase in rad",
                                      systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                // The true reason, not the requirements
                                // list: when every requirement is met and
                                // the origin FIT is what the gate refuses,
                                // listing requirements that are all
                                // satisfied would misdirect the remedy.
                                // // v2 S7
                                if let refusal = appState.idpcOriginFitRefusal {
                                    Text("Qualitative iDPC — " + refusal)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .sidebarWrapped()
                                } else {
                                    // Status, not a requirements list — the
                                    // readiness panel above the images is the
                                    // single owner of the full enumeration
                                    // (#21); restating it here is the drift
                                    // the ownership rule exists to prevent.
                                    Text("Qualitative iDPC — relative units. The readiness note above the images lists what quantitative iDPC needs.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .sidebarWrapped()
                                }
                                // The remedy lives in Prepare; take the user
                                // there instead of describing the journey.
                                Button("Open Prepare to Calibrate") {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        appState.selectWorkspace(.prepare)
                                    }
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("dpc.openPrepare")
                            }

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
                                    // The qualitative/physical status and its
                                    // reason now lead the section (S22b) —
                                    // only the boundary fact remains per-mode.
                                    LabeledContent("Boundary", value: "Symmetric zero pad · 2×")
                                        .font(.caption)
                                }
                            }
                            if !appState.calibrationSession.calibration.hasFittedOrigin {
                                Text("Tip: calibrate the origin first — DPC shifts are measured against the fitted beam position.")
                                    .font(.caption2).foregroundStyle(.secondary).sidebarWrapped()
                            } else if !appState.calibrationSession.calibration.hasRotation {
                                Text("Tip: calibrate the rotation for meaningful iDPC and vector direction.")
                                    .font(.caption2).foregroundStyle(.secondary).sidebarWrapped()
                            }
                        }
                    }

                    if appState.navigation.workspaceArea == .map {
                        MapSidebar()   // v2.5 step 7c slice 4a
                    }

                    if appState.navigation.workspaceArea == .reconstruct && appState.navigation.analysisMode == .singleslicePtychography {
                        // v2.5 step 7a: its own task, no parallax stage in front of it.
                        Section("Single-slice ptychography") {

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
                    }

                    if appState.navigation.workspaceArea == .reconstruct && appState.navigation.analysisMode == .ptychography {
                        Section("Reconstruction workflow") {
                            reconstructionStage(1, "Prepare preview") {
                                Button {
                                    Task { await appState.prepareParallaxPreview() }
                                } label: {
                                    Label("Prepare Parallax Preview", systemImage: "waveform.path.ecg.rectangle")
                                }
                                .disabled(appState.isBusy)
                            }
                            reconstructionStage(2, "Align bright-field stack") {
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
                            }
                            reconstructionStage(3, "Fit and correct phase") {
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
                                }
                            }
                            reconstructionStage(4, "Inspect or reconstruct products") {
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
                                if appState.parallaxHigherOrderFit != nil {
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
                                // R27 (owner, 2026-09-01): stateful and
                                // SPECIFIC. The generic orange sentence sat
                                // right under a green "Core calibrated"
                                // badge and read as a false alarm — while
                                // the actual gap (ptychography also needs
                                // the R scale and voltage, beyond "core")
                                // stayed invisible. Name what is missing;
                                // go quiet gray when nothing is.
                                let missingForPtycho = ProductWorkflow.prerequisites(
                                    for: .ptychography,
                                    readiness: appState.productWorkflowReadiness
                                )
                                if missingForPtycho.isEmpty {
                                    Text("All reconstruction requirements are met.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .sidebarWrapped()
                                } else {
                                    Text("Still needed: "
                                         + missingForPtycho.joined(separator: " · ")
                                         + ". Missing values are rejected rather than guessed.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .sidebarWrapped()
                                }
                            }
                        }
                    }


                    // v2.5 step 7c: the per-workspace sidebars, one file
                    // each, replace the gated sections above as each slice
                    // lands (plan §11h). Results is the first.
                    if appState.navigation.workspaceArea == .results {
                        ResultsSidebar()
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(
                \.sidebarTextWidth, max(sidebarGeo.size.width - 34, 216)
            )
            // Backlog #16. The symptom (sidebar rows drawn across the traffic
            // lights, top rows inert because the titlebar hit-tests above them)
            // is the sidebar scroll view sitting at clip origin 0 instead of
            // -contentInsets.top — i.e. scrolled one titlebar-height past its
            // own top. Measured: docTopInWindow 923 instead of 871 in a
            // 923pt window with a 52pt titlebar. Elastic overscroll at the top
            // is the remaining candidate for how it gets there, so bouncing is
            // limited to the case where there is genuinely something to scroll.
            .scrollBounceBehavior(.basedOnSize)
            }
            // These sit on the COLUMN'S ROOT VIEW (the GeometryReader), not on
            // the List inside it — attached inside the wrapper, the width
            // declaration stopped reaching NavigationSplitView and the owner
            // dragged the sidebar to ~750pt and ~175pt on 2026-09-01 (S22
            // feedback R1/R2). AppKit-side enforcement is in
            // SplitViewWidthClamp, because the declaration alone has already
            // failed twice (the 144pt restore; the 625pt drag on the PRE-S22
            // build in the owner's original screenshots).
            .navigationTitle("mac4DSTEM")
            .navigationSplitViewColumnWidth(min: 250, ideal: 292, max: 340)
            // Belt for the min: the declaration alone still allowed a hard
            // drag to ~139pt (observed live 2026-09-01 even with the max
            // holding). A hard floor on the column root is the constraint
            // AppKit cannot drag through.
            .frame(minWidth: 250)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if appState.hasDataset && !appState.isLoadingDataset {
                    ProductWorkspaceHeader()
                }

                Group {
                if appState.hasDataset && !appState.isLoadingDataset && appState.navigation.workspaceArea == .results {
                    ResultsWorkspace()
                } else {
                    VStack(spacing: 0) {
                        Group {
                            if appState.hasDataset && !appState.isLoadingDataset {
                                imagePanes
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
                        if appState.navigation.showLogPane && appState.hasDataset && !appState.isLoadingDataset {
                            Divider()
                            logPane
                        }
                    }
                    // Soft floor so the sidebar and inspector cannot crush the
                    // image panes into distorted slivers — the 2026-08-05
                    // clipped-edges class, finally captured on screen
                    // 2026-09-01 (open-items, owner playthrough item 4).
                    .frame(minWidth: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                }
                // A REAL system inspector column (S22a): draggable to
                // 560pt, collapsible, system-animated. The previous
                // hand-rolled HStack member (fixed 220–340pt frame, no
                // drag handle) was the direct cause of "the right panel
                // cannot be resized" and half of the clipped-edges layout
                // regime above. One column for every workspace, Results
                // included; which inspector it holds follows the focused
                // pane (v2.5 step 7c).
                .inspector(isPresented: Bindable(appState.navigation).showInspectorPane) {
                    WorkspaceInspector()
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 560)
                }
                // D2 (owner decision, 2026-09-01): the permanent status
                // footer — status line, live operation progress with Cancel,
                // and the standing memory/cube facts. A STACKED element, not
                // a floating inset (R18/R19): the inset version drew over the
                // log strip's tail and over Results' own export/save row —
                // stacked, nothing can ever render behind it.
                Divider()
                StatusFooterView()
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation { appState.navigation.showToolsPane.toggle() }
                    } label: {
                        Label("Toggle tools", systemImage: "sidebar.leading")
                    }
                    .help("Show or hide the tools panel")
                }
                if appState.navigation.workspaceArea != .results {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.navigation.showLogPane.toggle()
                        } label: {
                            Label("Toggle output", systemImage: "rectangle.bottomthird.inset.filled")
                        }
                        .help("Show or hide the output log below the image panes")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.navigation.showInspectorPane.toggle()
                    } label: {
                        Label("Toggle inspector", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the inspector panel")
                }
            }
        }
        .onAppear {
            // S22d: after AppKit state restoration, clamp a sidebar restored
            // below its declared 250pt minimum (the standing 144pt-restore
            // Track B finding). Deferred one runloop turn so restoration has
            // finished laying out.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.isVisible {
                    SplitViewWidthClamp.enforceSidebarMinimum(in: window)
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
                    // One importer, two destinations. `configureOnOpen` is set
                    // by whichever control opened it, so "Open Dataset…" keeps
                    // loading straight through and only "Open with options…"
                    // stops to ask (release owner, 2026-08-18).
                    if appState.configureOnOpen {
                        appState.openFileForConfiguration(url: url)
                    } else {
                        appState.openFile(url: url)
                    }
                }
            case .failure(let error):
                appState.present(error)
            }
            appState.configureOnOpen = false
        }
        .sheet(item: Binding(
            get: { appState.pendingLoad },
            set: { if $0 == nil { appState.discardPendingLoad() } }
        )) { pending in
            LoadConfiguratorView(pending: pending)
                .environment(appState)
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
        // v2.5 step 4b: the one verdict, shared with the readiness checklist.
        let verdict = appState.calibrationSession.verdict
        let coreCalibrated = verdict.quantitative
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
                    // Axis-labelled on purpose (v2 S18). This line and the
                    // dataset inspector print the same two extents in
                    // OPPOSITE orders — here in display order (across x down),
                    // there in array order as `Scan (Ry x Rx)` beside a
                    // `Shape` row of `ry x rx x qy x qx`. Each is right for
                    // where it sits: the number beside an image should read
                    // the way the image draws, and a row labelled with its own
                    // axes should read the way the array is indexed. What made
                    // it a defect is that this one carried no labels, so the
                    // two contradicted each other on screen with nothing to
                    // reconcile them — the same shape as the readiness row
                    // that disagreed with its own detail line on tag day.
                    // TWO lines, not one wrapped line. The single-line version
                    // truncated at the default sidebar width — it rendered
                    // `12 × 12 scan (Rx × Ry)  ·  64 × 64 detector (…`, so the
                    // `(Qx × Qy)` half never appeared and the card labelled one
                    // axis pair while silently dropping the other. That is the
                    // exact ambiguity this line exists to remove, so a
                    // truncation here is not cosmetic.
                    //
                    // `.fixedSize(horizontal: false, vertical: true)` was tried
                    // first and did NOT fix it — verified on screen, not
                    // assumed. Splitting the string is structural: neither line
                    // is long enough to truncate at any sidebar width the app
                    // allows (min 250pt, `:970`).
                    //
                    // Found by driving the app 2026-08-27. `unit` was green
                    // throughout, including `SidebarLayoutTests`, because those
                    // measure document height and column fit and truncation
                    // changes neither.
                    Text("\(descriptor.rx) × \(descriptor.ry) scan (Rx × Ry)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(descriptor.qx) × \(descriptor.qy) detector (Qx × Qy)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Open Another…") { appState.requestOpenDataset() }
                    // S22e: with a dataset loaded, ⌘N used to be the ONLY
                    // route back to the configured open (Track B drive
                    // finding, 2026-09-01) — the second door now also exists
                    // where the other dataset actions live.
                    Button("Open with Options…") { appState.requestOpenDatasetWithOptions() }
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
                    coreCalibrated ? "Quantitative" : "Not quantitative",
                    systemImage: coreCalibrated
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .foregroundStyle(coreCalibrated ? Color.green : Color.orange)
                .help(verdict.summary)
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

    /// Diffraction left, real space right — always.
    ///
    /// #17a briefly made this axis follow the scan aspect (a 200×50 map fills
    /// far more of a wide, short pane). The release owner rejected it on sight:
    /// the side-by-side arrangement is part of what the app *is*, and having it
    /// change under a dataset is worse than an under-filled pane.
    private var imagePanes: some View {
        HSplitView {
            diffractionPane.frame(minWidth: 170)
            realSpacePane.frame(minWidth: 170)
        }
        // v2.5 step 7c: the pane with the ring claims the inspector's focus
        // whenever what these panes show changes (workspace or task).
        .onChange(of: appState.navigation.workspaceArea, initial: true) { claimPaneFocus() }
        .onChange(of: appState.navigation.analysisMode) { claimPaneFocus() }
    }

    private var diffractionPane: some View {
        DiffractionView()
            .overlay(paneFocusBorder(active: appState.activePane == .diffraction))
            .contentShape(Rectangle())
            .onTapGesture {
                appState.activePane = .diffraction
                claimPaneFocus()
            }
    }

    private var realSpacePane: some View {
        StemImageView()
            .overlay(paneFocusBorder(active: appState.activePane == .realSpace))
            .contentShape(Rectangle())
            .onTapGesture {
                appState.activePane = .realSpace
                claimPaneFocus()
            }
    }

    /// The pane with the focus ring names itself to the inspector
    /// (`FocusedPane`, plan §11g decision 3). `ActivePane` keeps its own job,
    /// the ROI direction.
    private func claimPaneFocus() {
        appState.navigation.focusedPane = FocusedPane.livePane(
            appState.activePane, in: appState.navigation.workspaceArea,
            task: appState.navigation.analysisMode
        )
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
                                appState.navigation.workspaceArea == area ? .semibold : .regular
                            ))
                        // S22c: the ADV marker moved from the workspace to
                        // the one task that earns it (ptychography) — with
                        // DPC in Phase, a workspace-level badge would mark
                        // an everyday analysis as advanced.
                    }
                    // The subtitle stands down once you are past needing it.
                    // It described all five areas permanently, which cost 63pt
                    // of an 871pt column to answer a question asked once. It is
                    // still on the selected row (where it names where you are),
                    // on hover via `help`, and in `accessibilityHint` — so the
                    // fact is demoted, never deleted.
                    if appState.navigation.workspaceArea == area {
                        Text(area.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
        .foregroundStyle(appState.navigation.workspaceArea == area ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .help(area.subtitle)
        .accessibilityLabel(area.title)
        .accessibilityIdentifier("workspace.\(area.rawValue)")
        .accessibilityHint(area.subtitle)
        .accessibilityAddTraits(appState.navigation.workspaceArea == area ? .isSelected : [])
    }

    private func taskButton(_ mode: AnalysisMode) -> some View {
        Button {
            appState.changeMode(mode)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(mode.productTitle)
                            .font(.subheadline.weight(appState.navigation.analysisMode == mode ? .semibold : .regular))
                        if mode.isAdvanced {
                            Text("ADV")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Same rule as `workspaceButton`: on the selected row, on
                    // hover, and in the accessibility hint — not permanently on
                    // every row. See that comment for the reasoning.
                    if appState.navigation.analysisMode == mode {
                        Text(mode.productSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // Backlog #33 + R15 (2026-09-01). Three states, matching the
                // inspector's "Computed this session" glyphs exactly:
                // orange ! = blocked; empty circle = ready but nothing
                // produced; green check = this task HAS produced its product
                // this session. #33 removed the green check for merely-READY
                // because ready≠done was misread; done-as-check is that
                // list's own meaning, so the ambiguity does not return. The
                // owner hit the missing third state on 2026-09-01: 83,929
                // peaks landed and the circle stayed empty.
                let unmet = taskUnmetCount(mode)
                let produced = taskHasProduct(mode)
                Image(systemName: produced
                        ? "checkmark.circle.fill"
                        : (unmet == 0 ? "circle" : "exclamationmark.circle.fill"))
                    .font(.caption)
                    .foregroundStyle(produced
                        ? Color.green
                        : (unmet == 0 ? Color.secondary : Color.orange))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.navigation.analysisMode == mode ? Color.accentColor : Color.primary)
        .padding(.vertical, 3)
        .help(mode.productSubtitle)
        .accessibilityLabel(taskAccessibilityLabel(mode))
        .accessibilityIdentifier("task.\(mode.id)")
        .accessibilityHint(mode.productSubtitle)
        .accessibilityAddTraits(appState.navigation.analysisMode == mode ? .isSelected : [])
    }

    private func taskUnmetCount(_ mode: AnalysisMode) -> Int {
        ProductWorkflow.prerequisites(
            for: mode, readiness: appState.productWorkflowReadiness
        ).count
    }

    /// R15: whether this task has produced its product in this session —
    /// only for the tasks with an unambiguous retained product. Staleness is
    /// deliberately not folded in here; the result pane's own badge carries
    /// it (backlog #34).
    private func taskHasProduct(_ mode: AnalysisMode) -> Bool {
        switch mode {
        case .disks: appState.hasCurrentBraggVectors
        case .strain: appState.strain.map != nil
        case .acom: appState.hasOrientationMap
        // R25 (owner, 2026-09-01): virtual imaging and DPC share the single
        // scalar result slot, so "has produced" is read from the recipe
        // record — it survives the slot being replaced and resets with the
        // dataset.
        case .virtualDetector:
            appState.replay.record.steps.contains { $0.kind == "virtual_detector" }
        case .dpc:
            appState.replay.record.steps.contains { $0.kind == "dpc" }
        case .ptychography, .singleslicePtychography: false
        }
    }

    /// Readiness is folded into the button's own label rather than left on the
    /// glyph: the button sets `accessibilityLabel`, which replaces its
    /// children's, so a label on the image alone would never be announced.
    private func taskAccessibilityLabel(_ mode: AnalysisMode) -> String {
        if taskHasProduct(mode) { return "\(mode.productTitle), computed" }
        let unmet = taskUnmetCount(mode)
        if unmet == 0 { return "\(mode.productTitle), ready" }
        return "\(mode.productTitle), \(unmet) requirement\(unmet == 1 ? "" : "s") missing"
    }

    /// Backlog #39. The Reconstruct sidebar was ~450 lines in a single
    /// `Section` — roughly 20 `TextField`s, 8 toggles and 6 buttons, essentially
    /// all on screen at once once `parallaxHigherOrderFit` existed, in a
    /// 250–340pt column. `reconstructionProgress` already modelled the workflow
    /// as four stages and `primaryActionTitle` already knew which was next; the
    /// controls simply were not grouped by it.
    ///
    /// Each stage is now a disclosure whose header carries the same ✓/number
    /// glyph the old progress block drew, with the controls for that stage
    /// inside it. The stage the workflow is actually on is open; opening
    /// another closes it.
    ///
    /// **Presentation only** — no control changed meaning and none was removed.
    /// The separate `reconstructionProgress` summary went away because the
    /// headers now say the same thing *next to the controls they gate*, which
    /// is #21's "one owner" rule; keeping both would have restated the whole
    /// checklist immediately above itself.
    ///
    /// The displayed-product pickers deliberately stay outside the stages,
    /// because they choose what is on screen right now rather than
    /// parameterising a step. (The accelerating-voltage field, which also
    /// lived outside them, moved to Prepare's Calibration section — S22c.)
    @ViewBuilder
    private func reconstructionStage<Content: View>(
        _ number: Int, _ title: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        // R21 (owner, 2026-09-01): flat rows, no user-managed disclosures —
        // "the weird flapouts … could just be buttons with indication or
        // some mechanism telling the user in which order". Every stage is a
        // visible row with its state; only the ACTIVE stage (the first
        // incomplete one) shows its controls, automatically, so the order
        // explains itself and there is nothing to open or close.
        let complete = reconstructionStageIsComplete(number)
        let active = number == currentReconstructionStage
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(complete ? Color.green
                                     : (active ? Color.accentColor : Color.secondary))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(active ? .semibold : .regular))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(complete ? "Complete" : (active ? "Current step" : "Pending"))
            // v2.5 step 7a (plan §3 item 6): a completed stage keeps its
            // controls — Reset Alignment, the product picker — so the chain is
            // revisitable; only pending stages stay collapsed.
            if active || complete {
                VStack(alignment: .leading, spacing: 6) { content() }
                    .padding(.leading, 22)
            }
        }
        .accessibilityIdentifier("reconstruct.stage.\(number)")
    }

    private func reconstructionStageIsComplete(_ number: Int) -> Bool {
        switch number {
        case 1: appState.parallaxPreprocess != nil
        case 2: appState.parallaxAlignment?.isComplete == true
        case 3: appState.parallaxCorrection != nil
        default:
            appState.singleslicePtychography != nil || appState.parallaxSubpixel != nil
        }
    }

    /// The stage the workflow is on — the first one not yet complete.
    private var currentReconstructionStage: Int {
        (1...4).first { !reconstructionStageIsComplete($0) } ?? 4
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
        appState.calibrationSession.readiness
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
                // Triangle corners as named constants: the one-expression blend
                // exceeds Xcode 26.6's type-checker budget (CI run #1) even
                // though Xcode 27 accepts it.
                let dir001 = SIMD3<Double>(0, 0, 1)
                let dir101 = simd_normalize(SIMD3<Double>(1, 0, 1))
                let dir111 = simd_normalize(SIMD3<Double>(1, 1, 1))
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let blended = dir001 * wl + dir101 * wr + dir111 * wt
                        let direction = simd_normalize(blended)
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
