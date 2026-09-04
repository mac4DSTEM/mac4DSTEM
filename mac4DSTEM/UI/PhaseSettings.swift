import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Reconstruct workspace's controls, as the inspector's **Settings** tab
/// renders them: a bare set of `Section`s the caller places inside its own
/// grouped `Form`.
///
/// Migrated from `UI/PhaseSidebar.swift`. Nothing scientific is re-decided
/// here: every number, unit, gate, refusal string and staleness note reads
/// the same `AppState` property and uses the same wording it did before. The
/// three tasks of `WorkspaceArea.reconstruct` each own their own sections —
/// DPC & iDPC, single-slice ptychography, and the four-stage parallax
/// pipeline — exactly as they did.
///
/// Two presentation rules of UI change how the old file *looked*, never what
/// it decided:
///
/// - The old "Pattern" section appeared only while the diffraction pane was
///   the *active* one. UI has no pane focus model, and both panes are on
///   screen at once, so the offer is gated on the statistics being absent and
///   nothing else.
/// - A pending parallax stage used to render no controls at all. Here every
///   stage is visible and its controls carry the same `disabled` conditions
///   the old file already gave them, so the order still explains itself
///   without a stage ever becoming operable early.
struct PhaseSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.navigation.analysisMode {
        case .dpc:
            PatternStatisticsSection()   // DPC works from the live CBED
            DPCSettingsSection()
        case .singleslicePtychography:
            // v2.5 step 7a: its own task, no parallax stage in front of it.
            SingleslicePtychographySection()
        case .ptychography:
            ParallaxStageSections()
            ParallaxProductSection()
            ParallaxRunDetailsSection()
        default:
            EmptyView()
        }
    }
}


// MARK: - DPC & iDPC

private struct DPCSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Section("DPC & iDPC") {
            // S22b (O2): status first — what running DPC will produce NOW —
            // then the display choice, then the per-mode detail.
            if appState.idpcPhysicalCalibration != nil {
                Label("Physical iDPC ready — projected phase in rad",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // The true reason, not the requirements list: when every
                // requirement is met and the origin FIT is what the gate
                // refuses, listing requirements that are all satisfied would
                // misdirect the remedy. // v2 S7
                if let refusal = appState.idpcOriginFitRefusal {
                    Text("Qualitative iDPC — " + refusal)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    // Status, not a requirements list — the readiness panel
                    // is the single owner of the full enumeration (#21);
                    // restating it here is the drift the ownership rule
                    // exists to prevent.
                    Text("Qualitative iDPC — relative units. The Requirements section at the top of this inspector lists what quantitative iDPC needs.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                // The remedy lives in Prepare; take the user there instead of
                // describing the journey.
                Button("Open Prepare to Calibrate") {
                    appState.selectWorkspace(.prepare)
                }
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
                } else {
                    Text("mrad needs accelerating voltage and Q pixel calibration.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if appState.dpcDisplay == .idpc {
                if let physical = appState.idpcPhysicalCalibration {
                    LabeledContent("Output", value: "Projected phase (rad)")
                    LabeledContent(
                        "Sampling",
                        value: String(
                            format: "%.4g Å · Q %.4g Å⁻¹/px",
                            physical.rowSamplingAngstrom,
                            physical.reciprocalAngstromPerDetectorPixel
                        )
                    )
                    LabeledContent("Boundary", value: "Symmetric zero pad · 2×")
                } else {
                    // The qualitative/physical status and its reason lead the
                    // section (S22b) — only the boundary fact is per-mode.
                    LabeledContent("Boundary", value: "Symmetric zero pad · 2×")
                }
            }
            if !appState.calibrationSession.calibration.hasFittedOrigin {
                Text("Tip: calibrate the origin first — DPC shifts are measured against the fitted beam position.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !appState.calibrationSession.calibration.hasRotation {
                Text("Tip: calibrate the rotation for meaningful iDPC and vector direction.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Single-slice ptychography

private struct SingleslicePtychographySection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let isGradientDescent = appState.ptychographyMethod == .gradientDescent
        Section("Single-slice ptychography") {
            Picker("Method", selection: $appState.ptychographyMethod) {
                ForEach(SingleslicePtychographyMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            LabeledContent("Iterations") {
                NumericField(
                    "Iterations",
                    value: $appState.ptychographyIterations,
                    format: .number
                )
            }
            LabeledContent(isGradientDescent ? "Step" : "DM/AP α") {
                NumericField(
                    isGradientDescent ? "Step" : "DM/AP α",
                    value: isGradientDescent
                        ? $appState.ptychographyStepSize
                        : $appState.ptychographyProjectionParameter,
                    format: .number.precision(.fractionLength(0...3))
                )
            }
            LabeledContent("Norm min") {
                NumericField(
                    "Norm min",
                    value: $appState.ptychographyNormalizationMinimum,
                    format: .number.precision(.fractionLength(0...3))
                )
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
                    LabeledContent("Support radius") {
                        NumericField(
                            "Support radius",
                            value: $appState.ptychographyProbeAmplitudeRadius,
                            format: .number.precision(.fractionLength(0...3))
                        )
                    }
                    LabeledContent("Edge width") {
                        NumericField(
                            "Edge width",
                            value: $appState.ptychographyProbeAmplitudeWidth,
                            format: .number.precision(.fractionLength(0...3))
                        )
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

// MARK: - Parallax: the four stages

/// Backlog #39, v2.5 step 7a. The four stages of the staged bright-field
/// reconstruction, one `Section` each, the header carrying the same ✓/number
/// glyph the old progress block drew and the controls for that stage as its
/// rows. A completed stage keeps its controls — Reset Alignment, the fields —
/// so the chain stays revisitable.
///
/// Every control here already carried its own prerequisite in `disabled(…)`
/// or an enclosing `if`, so a later stage is visible and inert rather than
/// absent: no gate is loosened by showing it.
private struct ParallaxStageSections: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        stageSection(1, "Prepare preview") {
            Button {
                Task { await appState.prepareParallaxPreview() }
            } label: {
                Label("Prepare Parallax Preview", systemImage: "waveform.path.ecg.rectangle")
            }
            .disabled(appState.isBusy)
        }
        stageSection(2, "Align bright-field stack") {
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
        stageSection(3, "Fit and correct phase") {
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
                LabeledContent("Low-pass") {
                    NumericField(
                        "Low-pass",
                        value: $appState.parallaxQLowpassInvAngstrom,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
                }
                LabeledContent("High-pass") {
                    NumericField(
                        "High-pass",
                        value: $appState.parallaxQHighpassInvAngstrom,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
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
        stageSection(4, "Inspect or reconstruct products") {
            if appState.parallaxAlignment?.isComplete == true {
                LabeledContent("Auto factor") {
                    NumericField(
                        "Auto factor",
                        value: $appState.parallaxKDEUpsampleFactor,
                        format: .number.precision(.fractionLength(0...3))
                    )
                }
                LabeledContent("KDE σ") {
                    NumericField(
                        "KDE σ",
                        value: $appState.parallaxKDESigmaPixels,
                        format: .number.precision(.fractionLength(0...3))
                    )
                }
                LabeledContent("Lanczos (0=off)") {
                    NumericField(
                        "Lanczos (0=off)",
                        value: $appState.parallaxKDELanczosOrder,
                        format: .number
                    )
                }
                LabeledContent("Position iters") {
                    NumericField(
                        "Position iters",
                        value: $appState.parallaxPositionCorrectionIterations,
                        format: .number
                    )
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
                LabeledContent("Depth start") {
                    NumericField(
                        "Depth start",
                        value: $appState.parallaxDepthStartAngstrom,
                        format: .number.precision(.fractionLength(0...1)),
                        unit: "Å"
                    )
                }
                LabeledContent("Depth end") {
                    NumericField(
                        "Depth end",
                        value: $appState.parallaxDepthEndAngstrom,
                        format: .number.precision(.fractionLength(0...1)),
                        unit: "Å"
                    )
                }
                LabeledContent("Planes") {
                    NumericField(
                        "Planes",
                        value: $appState.parallaxDepthPlaneCount,
                        format: .number
                    )
                }
                LabeledContent("Info limit") {
                    NumericField(
                        "Info limit",
                        value: $appState.parallaxDepthInformationLimit,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
                }
                LabeledContent("Power") {
                    NumericField(
                        "Power",
                        value: $appState.parallaxDepthInformationPower,
                        format: .number.precision(.fractionLength(0...2))
                    )
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
    }

    @ViewBuilder
    private func stageSection<Content: View>(
        _ number: Int, _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        let complete = stageIsComplete(number)
        let active = number == currentStage
        Section {
            // The pipeline's order is enforced HERE and nowhere else:
            // `upsampleParallaxBF()` guards only on a complete alignment and
            // `computeParallaxDepthSections()` only on the higher-order fit,
            // so Core would happily run stage 4 before Correct Phase. The old
            // sidebar enforced it by rendering nothing for a pending stage;
            // UI shows the stage so the chain explains itself and disables
            // it instead, which is no looser.
            content()
                .disabled(!(active || complete))
        } header: {
            Label {
                Text(title).fontWeight(active ? .semibold : .regular)
            } icon: {
                Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(complete ? Color.green
                                     : (active ? Color.accentColor : Color.secondary))
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(complete ? "Complete" : (active ? "Current step" : "Pending"))
            .accessibilityIdentifier("reconstruct.stage.\(number)")
        }
    }

    private func stageIsComplete(_ number: Int) -> Bool {
        switch number {
        case 1: appState.parallaxPreprocess != nil
        case 2: appState.parallaxAlignment?.isComplete == true
        case 3: appState.parallaxCorrection != nil
        default:
            appState.singleslicePtychography != nil || appState.parallaxSubpixel != nil
        }
    }

    /// The stage the workflow is on — the first one not yet complete.
    private var currentStage: Int {
        (1...4).first { !stageIsComplete($0) } ?? 4
    }
}

// MARK: - Parallax: what is on screen

/// The displayed-product pickers deliberately stay outside the stages,
/// because they choose what is on screen right now rather than
/// parameterising a step.
private struct ParallaxProductSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.availableParallaxProducts.isEmpty {
            Section {
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
                    ScientificHistoryPlot(
                        title: "\(iterative.options.method.rawValue) error",
                        values: iterative.errorHistory,
                        scale: .logarithmic
                    )
                }
            }
        }
    }
}

// MARK: - Parallax: run details

private struct ParallaxRunDetailsSection: View {
    @Environment(AppState.self) private var appState
    @State private var showsRunDetails = false

    var body: some View {
        if let preview = appState.parallaxPreprocess {
            Section("Run details", isExpanded: $showsRunDetails) {
                LabeledContent("BF detector pixels",
                               value: "\(preview.brightFieldPixelCount)")
                LabeledContent(
                    "Stack",
                    value: "\(preview.brightFieldPixelCount) × \(preview.stackHeight) × \(preview.stackWidth)"
                )
                LabeledContent(
                    "Stack memory",
                    value: displayByteString(preview.residentStackByteCount)
                )
                LabeledContent(
                    "Electron wavelength",
                    value: String(format: "%.5f Å", preview.calibration.wavelengthAngstrom)
                )
                LabeledContent(
                    "Probe-angle extent",
                    value: String(format: "%.2f mrad", preview.maximumProbeAngleMrad)
                )
                LabeledContent(
                    "Initial mismatch",
                    value: String(format: "%.4f", preview.initialError)
                )
                if let alignment = appState.parallaxAlignment {
                    ParallaxAlignmentDetails(alignment: alignment)
                }
            }
        } else {
            // R27 (owner, 2026-09-01): stateful and SPECIFIC. The generic
            // orange sentence sat under a green "Core calibrated" badge and
            // read as a false alarm — while the actual gap (ptychography also
            // needs the R scale and voltage, beyond "core") stayed invisible.
            // Name what is missing; go quiet gray when nothing is.
            let missingForPtycho = ProductWorkflow.prerequisites(
                for: .ptychography,
                readiness: appState.productWorkflowReadiness
            )
            Section {
                if missingForPtycho.isEmpty {
                    Text("All reconstruction requirements are met.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // The enumeration itself belongs to Requirements at the
                    // top of this same column (#21, one owner). What is NOT
                    // said there, and is the scientific point, is that the
                    // missing values are refused rather than assumed.
                    Text("Missing values are rejected rather than guessed — see Requirements above.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// The alignment half of "Run details", split out so the type-checker sees
/// two modest bodies rather than one very large one.
private struct ParallaxAlignmentDetails: View {
    @Environment(AppState.self) private var appState
    let alignment: ParallaxAlignmentResult

    var body: some View {
        LabeledContent(
            "Aligned level",
            value: "\(alignment.completedBins.count)/\(alignment.alignmentSchedule.count) · bin \(alignment.alignmentBin) · \(alignment.groups.count) groups"
        )
        LabeledContent(
            "Bin schedule",
            value: alignment.alignmentSchedule
                .map(String.init).joined(separator: " → ")
        )
        LabeledContent(
            "Correlation",
            value: "matrix DFT ×\(alignment.upsampleFactor)"
        )
        LabeledContent(
            "Maximum shift",
            value: String(format: "%.2f px", alignment.maximumShiftPixels)
        )
        LabeledContent(
            "Aligned mismatch",
            value: String(format: "%.4f", alignment.currentError)
        )
        ScientificHistoryPlot(
            title: "Alignment mismatch",
            values: alignment.errorHistory,
            scale: .logarithmic
        )
        Text(alignment.isComplete
             ? "Coarse-to-fine alignment schedule complete; aberration fitting and correction remain pending."
             : "Continue with the next bin; cancellation retains this completed level.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let fit = appState.parallaxAberrationFit {
            LabeledContent(
                "Fitted rotation",
                value: String(format: "%.2f°", fit.rotationRad * 180 / .pi)
            )
            LabeledContent("C1", value: String(format: "%.1f Å", fit.c1Angstrom))
            LabeledContent(
                "C12a / C12b",
                value: String(
                    format: "%.1f / %.1f Å",
                    fit.c12aAngstrom, fit.c12bAngstrom
                )
            )
            LabeledContent(
                "Shift-fit RMS",
                value: String(format: "%.4f Å", fit.rmsResidualAngstrom)
            )
            Text("Diagnostic fit only; calibration and aligned data are unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ParallaxFitDetails()
        }
    }
}

/// The higher-order fit, the correction and the KDE reconstruction — the
/// rows the old file nested three deep inside the aberration-fit branch.
private struct ParallaxFitDetails: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let higher = appState.parallaxHigherOrderFit {
            LabeledContent(
                "Higher-order fit",
                value: "\(higher.terms.count) terms · \(higher.fitMethod.rawValue)"
            )
            LabeledContent(
                "Higher-order RMS",
                value: String(format: "%.4f Å", higher.rmsResidualAngstrom)
            )
            Text(
                zip(higher.terms, higher.coefficientsAngstrom)
                    .map { term, coefficient in
                        "C\(term.radialOrder)\(term.angularOrder)\(term.component == 0 ? "a" : "b") \(String(format: "%.1f", coefficient))"
                    }
                    .joined(separator: " · ")
            )
            .font(.caption.monospacedDigit())
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
            LabeledContent(
                "KDE output",
                // Width × height, UI's one order for a shape.
                value: "\(subpixel.croppedBF.width) × \(subpixel.croppedBF.height)"
            )
            if !subpixel.positionCorrectionScores.isEmpty {
                ScientificHistoryPlot(
                    title: "Position correction score",
                    values: subpixel.positionCorrectionScores
                )
            }
        }
    }
}

// MARK: - Diagnostic history plot

/// Compact interactive plot for a retained analysis history — the alignment
/// mismatch, the ptychography error, the position-correction score.
///
/// Scientific drawing, so it draws: dragging selects an existing finite
/// sample, and gaps stay visible where a sample is not finite (or not
/// positive on a log scale) rather than being interpolated over. The geometry
/// itself is `Core`'s `ScientificSeriesGeometry`, so what is plotted is
/// decided outside the view. Its one height comes from `LayoutPolicy`.
private struct ScientificHistoryPlot: View {
    let title: String
    let values: [Float]
    var scale: ScientificSeriesScale = .linear
    @State private var selectedIndex: Int?

    private var geometry: ScientificSeriesGeometry {
        ScientificSeriesGeometry.make(values: values, scale: scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(selectionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Canvas { context, size in
                    let inset = CGRect(x: 3, y: 3, width: max(0, size.width - 6),
                                       height: max(0, size.height - 6))
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = inset.maxY - inset.height * fraction
                        context.stroke(Path { path in
                            path.move(to: CGPoint(x: inset.minX, y: y))
                            path.addLine(to: CGPoint(x: inset.maxX, y: y))
                        }, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                    }
                    for segment in geometry.segments where !segment.isEmpty {
                        let path = Path { path in
                            for (offset, point) in segment.enumerated() {
                                let mapped = CGPoint(
                                    x: inset.minX + inset.width * point.x,
                                    y: inset.maxY - inset.height * point.y
                                )
                                offset == 0 ? path.move(to: mapped) : path.addLine(to: mapped)
                            }
                        }
                        context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
                    }
                    if let point = geometry.point(at: effectiveSelection) {
                        let center = CGPoint(x: inset.minX + inset.width * point.x,
                                             y: inset.maxY - inset.height * point.y)
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3,
                                                   width: 6, height: 6)),
                            with: .color(.accentColor)
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let x = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                    selectedIndex = geometry.nearestIndex(toUnitX: x)
                })
            }
            .frame(height: LayoutPolicy.diagnosticPlotHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(selectionLabel)
            .accessibilityHint("Adjust to inspect finite samples")
            .accessibilityAdjustableAction { direction in
                let indices = geometry.points.map(\.index)
                guard !indices.isEmpty else { return }
                let current = effectiveSelection ?? indices[indices.count - 1]
                let position = indices.firstIndex(of: current) ?? indices.count - 1
                switch direction {
                case .increment: selectedIndex = indices[min(indices.count - 1, position + 1)]
                case .decrement: selectedIndex = indices[max(0, position - 1)]
                @unknown default: break
                }
            }
            HStack {
                Text(scale == .logarithmic ? "log₁₀ scale" : "linear scale")
                Spacer()
                Text("\(geometry.points.count) samples")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .onChange(of: values) { selectedIndex = nil }
    }

    private var effectiveSelection: Int? { selectedIndex ?? geometry.points.last?.index }

    private var selectionLabel: String {
        guard let point = geometry.point(at: effectiveSelection) else { return "No finite samples" }
        return "#\(point.index)  \(String(format: "%.5g", point.value))"
    }
}
