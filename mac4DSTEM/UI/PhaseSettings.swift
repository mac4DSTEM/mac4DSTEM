import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Reconstruct workspace's controls, as the inspector's **Settings** tab
/// renders them: a sequence of `InspectorSection`s the caller places inside
/// its own scroll container.
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
        Group {
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
        .disabledWhileRunning(appState)
    }
}


// MARK: - DPC & iDPC

private struct DPCSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        @Bindable var dpc = appState.dpc
        InspectorSection("DPC & iDPC") {
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
                InspectorActionRow {
                    Button("Open Prepare to Calibrate") {
                        appState.selectWorkspace(.prepare)
                    }
                    .accessibilityIdentifier("dpc.openPrepare")
                }
            }

            InspectorRow("Display") {
                Picker("Display", selection: $dpc.dpcDisplay) {
                    ForEach(DPCDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
            }

            if dpc.dpcDisplay == .magnitudeMrad {
                if let scale = appState.dpcMilliradiansPerDetectorPixel {
                    InspectorValueRow(
                        "Angular scale",
                        String(format: "%.5g mrad / detector px", scale)
                    )
                } else {
                    Text("mrad needs accelerating voltage and Q pixel calibration.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if dpc.dpcDisplay == .idpc {
                if let physical = appState.idpcPhysicalCalibration {
                    InspectorValueRow("Output", "Projected phase (rad)")
                    InspectorValueRow(
                        "Sampling",
                        String(
                            format: "%.4g Å · Q %.4g Å⁻¹/px",
                            physical.rowSamplingAngstrom,
                            physical.reciprocalAngstromPerDetectorPixel
                        )
                    )
                    InspectorValueRow("Boundary", "Symmetric zero pad · 2×")
                } else {
                    // The qualitative/physical status and its reason lead the
                    // section (S22b) — only the boundary fact is per-mode.
                    InspectorValueRow("Boundary", "Symmetric zero pad · 2×")
                }
            }
            if !appState.calibrationSession.calibration.hasFittedOrigin {
                InspectorNote("Tip: calibrate the origin first — DPC shifts are measured against the fitted beam position.")
            } else if !appState.calibrationSession.calibration.hasRotation {
                InspectorNote("Tip: calibrate the rotation for meaningful iDPC and vector direction.")
            }
        }
    }
}

// MARK: - Single-slice ptychography

private struct SingleslicePtychographySection: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("phase.settings.ptychographyAdvanced.isExpanded") private var showsAdvanced = false

    var body: some View {
        @Bindable var ptychography = appState.ptychography
        let isGradientDescent = ptychography.method == .gradientDescent
        InspectorSection("Single-slice ptychography") {
            InspectorRow("Method") {
                Picker("Method", selection: $ptychography.method) {
                    ForEach(SingleslicePtychographyMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
            }
            InspectorActionRow {
                Button {
                    Task { await appState.runSingleslicePtychography() }
                } label: {
                    Label("Reconstruct Object", systemImage: "circle.hexagongrid")
                }
                .disabled(!ProductWorkflow.mayRun(
                    .singleslicePtychography,
                    readiness: appState.productWorkflowReadiness, isBusy: appState.isBusy
                ))
                .help("Runs the CPU exact-shape, full-batch py4DSTEM \(ptychography.method.rawValue) reference engine.")
            }
            DisclosureGroup("Advanced ptychography", isExpanded: $showsAdvanced) {
            InspectorRow("Iterations") {
                NumericField(
                    "Iterations",
                    value: $ptychography.iterations,
                    format: .number
                )
                .labelsHidden()
            }
            InspectorRow(isGradientDescent ? "Step" : "DM/AP α") {
                NumericField(
                    isGradientDescent ? "Step" : "DM/AP α",
                    value: isGradientDescent
                        ? $ptychography.stepSize
                        : $ptychography.projectionParameter,
                    format: .number.precision(.fractionLength(0...3))
                )
                .labelsHidden()
            }
            InspectorRow("Norm min") {
                NumericField(
                    "Norm min",
                    value: $ptychography.normalizationMinimum,
                    format: .number.precision(.fractionLength(0...3))
                )
                .labelsHidden()
            }
            InspectorRow("Fix probe") {
                Toggle("Fix probe", isOn: $ptychography.fixProbe)
                    .labelsHidden()
            }
            InspectorRow("Limit object transmission to 1") {
                Toggle(
                    "Limit object transmission to 1",
                    isOn: $ptychography.constrainObjectAmplitude
                )
                .labelsHidden()
            }
            InspectorRow("Pure-phase object") {
                Toggle(
                    "Pure-phase object",
                    isOn: $ptychography.purePhaseObject
                )
                .labelsHidden()
            }
            .help("Sets reconstructed object amplitude to one after every iteration.")
            if !ptychography.fixProbe {
                InspectorRow("Recenter probe each iteration") {
                    Toggle(
                        "Recenter probe each iteration",
                        isOn: $ptychography.fixProbeCenterOfMass
                    )
                    .labelsHidden()
                }
                InspectorRow("Constrain probe support") {
                    Toggle(
                        "Constrain probe support",
                        isOn: $ptychography.constrainProbeAmplitude
                    )
                    .labelsHidden()
                }
                if ptychography.constrainProbeAmplitude {
                    InspectorRow("Support radius") {
                        NumericField(
                            "Support radius",
                            value: $ptychography.probeAmplitudeRadius,
                            format: .number.precision(.fractionLength(0...3))
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Edge width") {
                        NumericField(
                            "Edge width",
                            value: $ptychography.probeAmplitudeWidth,
                            format: .number.precision(.fractionLength(0...3))
                        )
                        .labelsHidden()
                    }
                }
            }
        }
        }
    }
}

// MARK: - Parallax: the four stages

/// Backlog #39, v2.5 step 7a. The four stages of the staged bright-field
/// reconstruction, one `InspectorSection` each, carrying a status glyph
/// (the same ✓/number glyph the old progress block drew) as the section's
/// first element, and the controls for that stage as its rows. A completed
/// stage keeps its controls — Reset Alignment, the fields — so the chain
/// stays revisitable.
///
/// Every control here already carried its own prerequisite in `disabled(…)`
/// or an enclosing `if`, so a later stage is visible and inert rather than
/// absent: no gate is loosened by showing it.
private struct ParallaxStageSections: View {
    @Environment(AppState.self) private var appState
    @State private var showsResetAlignmentConfirmation = false
    @SceneStorage("phase.settings.parallaxAdvancedReconstruction.isExpanded") private var showsAdvancedReconstruction = false
    @SceneStorage("phase.settings.parallaxAdvancedDepth.isExpanded") private var showsAdvancedDepth = false

    var body: some View {
        @Bindable var appState = appState
        // `phaseContrast` is a `let` on AppState (seam 1, no forwarding
        // properties), so a chained `$phaseContrast.…` binding has
        // no writable key path; bind the owner itself, as `PhaseSettings`
        // already does for `appState.ptychography` below.
        @Bindable var phaseContrast = appState.phaseContrast
        stageSection(1, "Prepare preview") {
            InspectorActionRow {
                Button {
                    Task { await appState.prepareParallaxPreview() }
                } label: {
                    Label("Prepare Parallax Preview", systemImage: "waveform.path.ecg.rectangle")
                }
                // C4(a): was `appState.isBusy` only — this entry point bypassed
                // the same five-calibration gate the toolbar asks for
                // `.ptychography` (§4 finding 2); every later stage guards on the
                // previous stage's own in-memory product, which cannot exist
                // unless this one already ran with calibration satisfied.
                .disabled(!ProductWorkflow.mayRun(
                    .ptychography, readiness: appState.productWorkflowReadiness, isBusy: appState.isBusy
                ))
            }
        }
        stageSection(2, "Align bright-field stack") {
            InspectorActionRow {
                Button {
                    Task { await appState.alignParallaxNextLevel() }
                } label: {
                    Label("Align Next Level", systemImage: "align.horizontal.center")
                }
                .disabled(
                    appState.isBusy
                        || appState.phaseContrast.parallaxPreprocess == nil
                        || appState.phaseContrast.parallaxAlignment?.isComplete == true
                )
                .help("Runs the next py4DSTEM coarse-to-fine alignment bin with factor-8 matrix-DFT subpixel correlation.")

                if appState.phaseContrast.parallaxAlignment != nil {
                    Button("Reset Alignment") {
                        showsResetAlignmentConfirmation = true
                    }
                    .disabled(appState.isBusy)
                    .help("Discard completed alignment levels and return to the immutable preprocessed preview.")
                }
            }
        }
        stageSection(3, "Fit and correct phase") {
            InspectorActionRow {
                Button {
                    appState.fitParallaxAberrations()
                } label: {
                    Label("Fit Aberrations", systemImage: "waveform.path")
                }
                .disabled(
                    appState.isBusy
                        || appState.phaseContrast.parallaxAlignment?.isComplete != true
                )
                .help("Fits py4DSTEM's low-order polar decomposition and default recursive higher-order gradient basis without changing calibration.")
            }
            if appState.phaseContrast.parallaxHigherOrderFit != nil {
                InspectorRow("Low-pass") {
                    NumericField(
                        "Low-pass",
                        value: $phaseContrast.parallaxQLowpassInvAngstrom,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
                    .labelsHidden()
                }
                InspectorRow("High-pass") {
                    NumericField(
                        "High-pass",
                        value: $phaseContrast.parallaxQHighpassInvAngstrom,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
                    .labelsHidden()
                }
                InspectorActionRow {
                    Button {
                        Task { await appState.correctParallaxPhase() }
                    } label: {
                        Label("Correct Phase", systemImage: "wand.and.stars")
                    }
                    .disabled(appState.isBusy)
                    .help("Applies the fitted even/odd aberration CTF. Zero cutoff values disable the corresponding Butterworth filter.")
                }
            }
        }
        stageSection(4, "Inspect or reconstruct products") {
            if appState.phaseContrast.parallaxAlignment?.isComplete == true {
                InspectorRow("KDE σ") {
                    NumericField(
                        "KDE σ",
                        value: $phaseContrast.parallaxKDESigmaPixels,
                        format: .number.precision(.fractionLength(0...3)),
                        unit: "px"
                    )
                    .labelsHidden()
                }
                DisclosureGroup("Advanced reconstruction", isExpanded: $showsAdvancedReconstruction) {
                    InspectorRow("Auto factor") {
                        NumericField(
                            "Auto factor",
                            value: $phaseContrast.parallaxKDEUpsampleFactor,
                            format: .number.precision(.fractionLength(0...3))
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Lanczos (0=off)") {
                        NumericField(
                            "Lanczos (0=off)",
                            value: $phaseContrast.parallaxKDELanczosOrder,
                            format: .number
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Position iters") {
                        NumericField(
                            "Position iters",
                            value: $phaseContrast.parallaxPositionCorrectionIterations,
                            format: .number
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Sinc low-pass") {
                        Toggle("Sinc low-pass", isOn: $phaseContrast.parallaxKDELowpass)
                            .labelsHidden()
                    }
                    if appState.phaseContrast.parallaxPositionCorrectionIterations > 0 {
                        InspectorRow("Checkerboard position steps") {
                            Toggle(
                                "Checkerboard position steps",
                                isOn: $phaseContrast.parallaxPositionCorrectionCheckerboard
                            )
                            .labelsHidden()
                        }
                    }
                }
                InspectorActionRow {
                    Button {
                        Task { await appState.upsampleParallaxBF() }
                    } label: {
                        Label("Upsample BF", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(appState.isBusy)
                    .help("Zero factor selects py4DSTEM's BF/DF sampling heuristic; σ is specified in input pixels.")
                }
            }
            if appState.phaseContrast.parallaxHigherOrderFit != nil {
                InspectorRow("Depth start") {
                    NumericField(
                        "Depth start",
                        value: $phaseContrast.parallaxDepthStartAngstrom,
                        format: .number.precision(.fractionLength(0...1)),
                        unit: "Å"
                    )
                    .labelsHidden()
                }
                InspectorRow("Depth end") {
                    NumericField(
                        "Depth end",
                        value: $phaseContrast.parallaxDepthEndAngstrom,
                        format: .number.precision(.fractionLength(0...1)),
                        unit: "Å"
                    )
                    .labelsHidden()
                }
                InspectorRow("Info limit") {
                    NumericField(
                        "Info limit",
                        value: $phaseContrast.parallaxDepthInformationLimit,
                        format: .number.precision(.fractionLength(0...4)),
                        unit: "Å⁻¹"
                    )
                    .labelsHidden()
                }
                DisclosureGroup("Advanced depth settings", isExpanded: $showsAdvancedDepth) {
                    InspectorRow("Planes") {
                        NumericField(
                            "Planes",
                            value: $phaseContrast.parallaxDepthPlaneCount,
                            format: .number
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Power") {
                        NumericField(
                            "Power",
                            value: $phaseContrast.parallaxDepthInformationPower,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .labelsHidden()
                    }
                    InspectorRow("Use full fitted CTF") {
                        Toggle("Use full fitted CTF", isOn: $phaseContrast.parallaxDepthUseFullFit)
                            .labelsHidden()
                    }
                }
                InspectorActionRow {
                    Button {
                        Task { await appState.computeParallaxDepthSections() }
                    } label: {
                        Label("Compute Depth Stack", systemImage: "square.3.layers.3d")
                    }
                    .disabled(appState.isBusy)
                }
            }
        }
        .confirmationDialog(
            "Reset alignment?",
            isPresented: $showsResetAlignmentConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Alignment", role: .destructive) {
                appState.resetParallaxAlignment()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The completed alignment levels will be discarded and the prepared preview retained.")
        }
    }

    @ViewBuilder
    private func stageSection<Content: View>(
        _ number: Int, _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        let complete = stageIsComplete(number)
        let active = number == currentStage
        // The status glyph — a filled checkmark once complete, the stage
        // number while pending or current — is always visible in the
        // header, not a row inside it, and the title reads emphasized while
        // this is the active stage: the pipeline's order is enforced HERE
        // and nowhere else (`upsampleParallaxBF()` guards only on a complete
        // alignment, `computeParallaxDepthSections()` only on the
        // higher-order fit, so Core would happily run stage 4 before Correct
        // Phase), and a collapsed, unemphasized, unmarked section would lose
        // the one place that order is explained. The old sidebar enforced it
        // by rendering nothing for a pending stage; UI shows every stage and
        // disables it instead, which is no looser.
        InspectorSection(
            title,
            icon: Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle"),
            emphasized: active
        ) {
            content()
                .disabled(!(active || complete))
        }
        .accessibilityValue(complete ? "Complete" : (active ? "Current step" : "Pending"))
        .accessibilityIdentifier("reconstruct.stage.\(number)")
    }

    private func stageIsComplete(_ number: Int) -> Bool {
        switch number {
        case 1: appState.phaseContrast.parallaxPreprocess != nil
        case 2: appState.phaseContrast.parallaxAlignment?.isComplete == true
        case 3: appState.phaseContrast.parallaxCorrection != nil
        default:
            appState.phaseContrast.singleslicePtychography != nil || appState.phaseContrast.parallaxSubpixel != nil
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
            // Untitled at HEAD (a bare `Section`), and left that way: this
            // picker isn't a group of settings with a name of its own, and
            // "Product" collided with the Info tab's own "Product" section
            // before `inspectorScope` scoped the two apart (F1) — moot now,
            // but a title here would still invent a name this picker never
            // had (F6, `InspectorGroup`).
            InspectorGroup {
                InspectorRow("Displayed product") {
                    Picker(
                        "Displayed product",
                        selection: Binding(
                            get: { appState.phaseContrast.parallaxResultProduct },
                            set: appState.showParallaxProduct
                        )
                    ) {
                        ForEach(appState.availableParallaxProducts) { product in
                            Text(product.rawValue).tag(product)
                        }
                    }
                    .labelsHidden()
                }
                if let depth = appState.phaseContrast.parallaxDepth {
                    InspectorRow("Depth plane") {
                        Picker(
                            "Depth plane",
                            selection: Binding(
                                get: { appState.phaseContrast.parallaxDepthSelectedIndex },
                                set: appState.selectParallaxDepthPlane
                            )
                        ) {
                            ForEach(depth.depthsAngstrom.indices, id: \.self) { index in
                                Text(String(format: "%.1f Å", depth.depthsAngstrom[index]))
                                    .tag(index)
                            }
                        }
                        .labelsHidden()
                    }
                }
                if let iterative = appState.phaseContrast.singleslicePtychography {
                    InspectorValueRow(
                        "Ptychography",
                        "\(iterative.errorHistory.count) iterations"
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
    @SceneStorage("phase.settings.runDetails.isExpanded") private var showsRunDetails = false

    var body: some View {
        if let preview = appState.phaseContrast.parallaxPreprocess {
            InspectorSection("Run details", expanded: $showsRunDetails) {
                InspectorValueRow("BF detector pixels",
                                   "\(preview.brightFieldPixelCount)")
                InspectorValueRow(
                    "Stack",
                    "\(preview.brightFieldPixelCount) × \(preview.stackHeight) × \(preview.stackWidth)"
                )
                InspectorValueRow(
                    "Stack memory",
                    displayByteString(preview.residentStackByteCount)
                )
                InspectorValueRow(
                    "Electron wavelength",
                    String(format: "%.5f Å", preview.calibration.wavelengthAngstrom)
                )
                InspectorValueRow(
                    "Probe-angle extent",
                    String(format: "%.2f mrad", preview.maximumProbeAngleMrad)
                )
                InspectorValueRow(
                    "Initial mismatch",
                    String(format: "%.4f", preview.initialError)
                )
                if let alignment = appState.phaseContrast.parallaxAlignment {
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
            InspectorSection("Run details") {
                if missingForPtycho.isEmpty {
                    InspectorNote("All reconstruction requirements are met.")
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
        InspectorValueRow(
            "Aligned level",
            "\(alignment.completedBins.count)/\(alignment.alignmentSchedule.count) · bin \(alignment.alignmentBin) · \(alignment.groups.count) groups"
        )
        InspectorValueRow(
            "Bin schedule",
            alignment.alignmentSchedule
                .map(String.init).joined(separator: " → ")
        )
        InspectorValueRow(
            "Correlation",
            "matrix DFT ×\(alignment.upsampleFactor)"
        )
        InspectorValueRow(
            "Maximum shift",
            String(format: "%.2f px", alignment.maximumShiftPixels)
        )
        InspectorValueRow(
            "Aligned mismatch",
            String(format: "%.4f", alignment.currentError)
        )
        ScientificHistoryPlot(
            title: "Alignment mismatch",
            values: alignment.errorHistory,
            scale: .logarithmic
        )
        InspectorNote(alignment.isComplete
             ? "Coarse-to-fine alignment schedule complete; aberration fitting and correction remain pending."
             : "Continue with the next bin; cancellation retains this completed level.")
        if let fit = appState.phaseContrast.parallaxAberrationFit {
            InspectorValueRow(
                "Fitted rotation",
                String(format: "%.2f°", fit.rotationRad * 180 / .pi)
            )
            InspectorValueRow("C1", String(format: "%.1f Å", fit.c1Angstrom))
            InspectorValueRow(
                "C12a / C12b",
                String(
                    format: "%.1f / %.1f Å",
                    fit.c12aAngstrom, fit.c12bAngstrom
                )
            )
            InspectorValueRow(
                "Shift-fit RMS",
                String(format: "%.4f Å", fit.rmsResidualAngstrom)
            )
            InspectorNote("Diagnostic fit only; calibration and aligned data are unchanged.")
            ParallaxFitDetails()
        }
    }
}

/// The higher-order fit, the correction and the KDE reconstruction — the
/// rows the old file nested three deep inside the aberration-fit branch.
private struct ParallaxFitDetails: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let higher = appState.phaseContrast.parallaxHigherOrderFit {
            InspectorValueRow(
                "Higher-order fit",
                "\(higher.terms.count) terms · \(higher.fitMethod.rawValue)"
            )
            InspectorValueRow(
                "Higher-order RMS",
                String(format: "%.4f Å", higher.rmsResidualAngstrom)
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
        if let correction = appState.phaseContrast.parallaxCorrection {
            InspectorValueRow(
                "Phase correction",
                correction.usedFullFit
                    ? "full CTF · DC removed"
                    : "C1 fallback · DC removed"
            )
        }
        if let subpixel = appState.phaseContrast.parallaxSubpixel {
            InspectorValueRow(
                "KDE reconstruction",
                String(
                    format: "×%.2f · %.4f Å/px",
                    subpixel.upsampleFactor,
                    subpixel.outputSamplingAngstrom
                )
            )
            InspectorValueRow(
                "KDE output",
                // Width × height, UI's one order for a shape.
                "\(subpixel.croppedBF.width) × \(subpixel.croppedBF.height)"
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
