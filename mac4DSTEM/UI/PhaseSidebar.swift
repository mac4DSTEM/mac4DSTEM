import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Phase's sidebar (v2.5 step 7c slice 5, plan §11d): DPC & iDPC and
/// Single-slice ptychography as one `Section` each; Parallax as its four
/// revisitable stages, each its own `Section` of the column's grouped
/// `Form` (presentation contract rule 2) — independent of the others'
/// state (7a). The stage helpers live here with the only case that uses
/// them. One file per workspace sidebar.
struct PhaseSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var showsRunDetails = false

    var body: some View {
        @Bindable var appState = appState
        switch appState.navigation.analysisMode {
        case .dpc:
            ComputePatternStatisticsSection()   // DPC works from the live CBED
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
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        // Status, not a requirements list — the
                        // readiness panel above the images is the
                        // single owner of the full enumeration
                        // (#21); restating it here is the drift
                        // the ownership rule exists to prevent.
                        Text("Qualitative iDPC — relative units. The readiness note above the images lists what quantitative iDPC needs.")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                        // The qualitative/physical status and its
                        // reason now lead the section (S22b) —
                        // only the boundary fact remains per-mode.
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
        case .singleslicePtychography:
            // v2.5 step 7a: its own task, no parallax stage in front of it.
            Section("Single-slice ptychography") {
                Picker("Method", selection: $appState.ptychographyMethod) {
                    ForEach(SingleslicePtychographyMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                LabeledContent("Iterations") {
                    NumericField(
                        title: "Iterations",
                        value: $appState.ptychographyIterations,
                        format: .number
                    )
                }
                LabeledContent(appState.ptychographyMethod == .gradientDescent ? "Step" : "DM/AP α") {
                    NumericField(
                        title: appState.ptychographyMethod == .gradientDescent
                            ? "Step" : "DM/AP α",
                        value: appState.ptychographyMethod == .gradientDescent
                            ? $appState.ptychographyStepSize
                            : $appState.ptychographyProjectionParameter,
                        format: .number.precision(.fractionLength(0...3))
                    )
                }
                LabeledContent("Norm min") {
                    NumericField(
                        title: "Norm min",
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
                                title: "Support radius",
                                value: $appState.ptychographyProbeAmplitudeRadius,
                                format: .number.precision(.fractionLength(0...3))
                            )
                        }
                        LabeledContent("Edge width") {
                            NumericField(
                                title: "Edge width",
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
        case .ptychography:
            reconstructionStageSection(1, "Prepare preview") {
                Button {
                    Task { await appState.prepareParallaxPreview() }
                } label: {
                    Label("Prepare Parallax Preview", systemImage: "waveform.path.ecg.rectangle")
                }
                .disabled(appState.isBusy)
            }
            reconstructionStageSection(2, "Align bright-field stack") {
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
            reconstructionStageSection(3, "Fit and correct phase") {
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
                            title: "Low-pass",
                            value: $appState.parallaxQLowpassInvAngstrom,
                            format: .number.precision(.fractionLength(0...4)),
                            unit: "Å⁻¹"
                        )
                    }
                    LabeledContent("High-pass") {
                        NumericField(
                            title: "High-pass",
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
            reconstructionStageSection(4, "Inspect or reconstruct products") {
                if appState.parallaxAlignment?.isComplete == true {
                    LabeledContent("Auto factor") {
                        NumericField(
                            title: "Auto factor",
                            value: $appState.parallaxKDEUpsampleFactor,
                            format: .number.precision(.fractionLength(0...3))
                        )
                    }
                    LabeledContent("KDE σ") {
                        NumericField(
                            title: "KDE σ",
                            value: $appState.parallaxKDESigmaPixels,
                            format: .number.precision(.fractionLength(0...3))
                        )
                    }
                    LabeledContent("Lanczos (0=off)") {
                        NumericField(
                            title: "Lanczos (0=off)",
                            value: $appState.parallaxKDELanczosOrder,
                            format: .number
                        )
                    }
                    LabeledContent("Position iters") {
                        NumericField(
                            title: "Position iters",
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
                            title: "Depth start",
                            value: $appState.parallaxDepthStartAngstrom,
                            format: .number.precision(.fractionLength(0...1)),
                            unit: "Å"
                        )
                    }
                    LabeledContent("Depth end") {
                        NumericField(
                            title: "Depth end",
                            value: $appState.parallaxDepthEndAngstrom,
                            format: .number.precision(.fractionLength(0...1)),
                            unit: "Å"
                        )
                    }
                    LabeledContent("Planes") {
                        NumericField(
                            title: "Planes",
                            value: $appState.parallaxDepthPlaneCount,
                            format: .number
                        )
                    }
                    LabeledContent("Info limit") {
                        NumericField(
                            title: "Info limit",
                            value: $appState.parallaxDepthInformationLimit,
                            format: .number.precision(.fractionLength(0...4)),
                            unit: "Å⁻¹"
                        )
                    }
                    LabeledContent("Power") {
                        NumericField(
                            title: "Power",
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

            // The displayed-product pickers deliberately stay outside the
            // stages, because they choose what is on screen right now
            // rather than parameterising a step.
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
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(preview.residentStackByteCount),
                            countStyle: .file
                        )
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
                                value: String(
                                    format: "%.2f°",
                                    fit.rotationRad * 180 / .pi
                                )
                            )
                            LabeledContent(
                                "C1",
                                value: String(format: "%.1f Å", fit.c1Angstrom)
                            )
                            LabeledContent(
                                "C12a / C12b",
                                value: String(
                                    format: "%.1f / %.1f Å",
                                    fit.c12aAngstrom, fit.c12bAngstrom
                                )
                            )
                            LabeledContent(
                                "Shift-fit RMS",
                                value: String(
                                    format: "%.4f Å",
                                    fit.rmsResidualAngstrom
                                )
                            )
                            Text("Diagnostic fit only; calibration and aligned data are unchanged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let higher = appState.parallaxHigherOrderFit {
                                LabeledContent(
                                    "Higher-order fit",
                                    value: "\(higher.terms.count) terms · \(higher.fitMethod.rawValue)"
                                )
                                LabeledContent(
                                    "Higher-order RMS",
                                    value: String(
                                        format: "%.4f Å",
                                        higher.rmsResidualAngstrom
                                    )
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
                                    value: "\(subpixel.croppedBF.height) × \(subpixel.croppedBF.width)"
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Still needed: "
                         + missingForPtycho.joined(separator: " · ")
                         + ". Missing values are rejected rather than guessed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        default:
            EmptyView()
        }
    }

    /// Backlog #39. The Reconstruct sidebar was ~450 lines in a single
    /// `Section` — roughly 20 `TextField`s, 8 toggles and 6 buttons, essentially
    /// all on screen at once once `parallaxHigherOrderFit` existed, in a
    /// 250–340pt column. `reconstructionProgress` already modelled the workflow
    /// as four stages and `primaryActionTitle` already knew which was next; the
    /// controls simply were not grouped by it.
    ///
    /// Each stage is now its own `Section` of the column's grouped `Form`,
    /// whose header carries the same ✓/number glyph the old progress block
    /// drew, with the controls for that stage as the section's own rows.
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
    private func reconstructionStageSection<Content: View>(
        _ number: Int, _ title: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        // R21 (owner, 2026-09-01): flat rows, no user-managed disclosures —
        // "the weird flapouts … could just be buttons with indication or
        // some mechanism telling the user in which order". Every stage's
        // header is always visible with its state; only the ACTIVE stage
        // (the first incomplete one) shows its controls, automatically, so
        // the order explains itself and there is nothing to open or close.
        let complete = reconstructionStageIsComplete(number)
        let active = number == currentReconstructionStage
        Section {
            // v2.5 step 7a (plan §3 item 6): a completed stage keeps its
            // controls — Reset Alignment, the product picker — so the chain is
            // revisitable; only pending stages render nothing.
            if active || complete {
                content()
            }
        } header: {
            Label {
                Text(title)
                    .font(.caption.weight(active ? .semibold : .regular))
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
