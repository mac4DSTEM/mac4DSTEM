import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import UniformTypeIdentifiers

/// Map's inspector Settings tab: one task's controls at a time, in the
/// pipeline order the science runs in — disks produce the Bragg vectors that
/// strain and ACOM consume.
///
/// This is the surface with the most scientific numbers in the app, so the
/// migration from `MapSidebar` / `DiskDetectionControls` / `ACOMControlsView`
/// is deliberately literal: every threshold, format string, unit, disabled
/// condition, refusal, staleness warning and accessibility identifier is the
/// old one. What changed is presentation only — the old views' `NumericField`
/// is `UI2NumericField`, and the body is a bare set of `Section`s for the
/// inspector's grouped `Form`.
struct UI2MapSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.navigation.analysisMode {
        case .disks:
            Section("Disk detection") {
                UI2DiskDetectionRows()
            }
            UI2AdvancedDiskDetectionSection()
        case .strain:
            UI2StrainSection()
        case .acom:
            UI2ACOMSections()
        default:
            EmptyView()
        }
    }
}

// MARK: - Disk detection

/// Source-faithful controls for py4DSTEM-style Bragg-disk detection: the
/// compact defaults stay visible as rows of the "Disk detection" section; the
/// less commonly changed signal/filter parameters live in the sibling
/// `UI2AdvancedDiskDetectionSection`, a collapsed section of its own.
private struct UI2DiskDetectionRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            Task { await appState.generateProbeKernel() }
        } label: {
            Label("Generate Probe Kernel", systemImage: "circle.circle")
        }
        .disabled(appState.isBusy)
        .accessibilityIdentifier("disk.generateSyntheticKernel")

        Button {
            Task { await appState.generateMeasuredProbeKernel() }
        } label: {
            Label("Use Current CBED / ROI", systemImage: "scope")
        }
        .disabled(appState.isBusy || appState.displayedPattern == nil)
        .accessibilityIdentifier("disk.generateMeasuredKernel")
        .help("Select a vacuum point or real-space ROI, then build the disk-correlation kernel from its displayed diffraction pattern.")

        if let kernel = appState.probeKernel {
            LabeledContent(
                "Kernel",
                value: String(
                    format: "%@ · %.1f px", kernel.source.rawValue, kernel.probeRadius
                )
            )
        }

        ui2ParameterSliderRow(
            title: DiskDetectionParameterID.correlationPower.title,
            value: ui2FloatBinding(
                appState, \.corrPower, in: ui2FloatEditorRange(.correlationPower)
            ),
            range: ui2FloatEditorRange(.correlationPower),
            step: Float(DiskDetectionParameterID.correlationPower.editorStep!),
            valueText: String(format: "%.2f", appState.diskParams.corrPower)
        )
        .help(DiskDetectionParameterID.correlationPower.explanation)

        Picker(
            DiskDetectionParameterID.subpixel.title,
            selection: ui2ParameterBinding(appState, \.subpixel)
        ) {
            ForEach(SubpixelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .help(DiskDetectionParameterID.subpixel.explanation)

        Stepper(value: ui2MaximumPeaksBinding(appState), in: 1...500) {
            Text("\(DiskDetectionParameterID.maximumPeaks.title)  \(appState.diskParams.maxNumPeaks)")
        }
        .help(DiskDetectionParameterID.maximumPeaks.explanation)

        if appState.probeKernel != nil {
            LabeledContent("Current CBED", value: "\(appState.currentPeaks.count) peaks")
                .monospacedDigit()
                .accessibilityIdentifier("disk.currentPeakCount")
            if let diagnostics = appState.currentDiskDiagnostics {
                LabeledContent(
                    "Acceptance funnel",
                    value: "\(diagnostics.localMaximumCount) candidates → \(diagnostics.acceptedCount) accepted"
                )
                .monospacedDigit()
                .help("Edge-qualified local maxima before filters, followed by the final accepted peak count.")
                Text(
                    "absolute \(diagnostics.afterAbsoluteThresholdCount) · relative \(diagnostics.afterRelativeThresholdCount) · spacing \(diagnostics.afterSpacingCount)"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if diagnostics.wasCountLimited {
                    Label(
                        "This pattern was truncated to the configured maximum peak count.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if appState.diskParams.minRelativeIntensity > 0,
                   !diagnostics.relativeReferenceWasAvailable {
                    Label(
                        "The selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        } else {
            Text("Build a probe kernel to preview detections on the current CBED.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(
            Array(appState.diskDetectionValidationIssues.enumerated()), id: \.offset
        ) { _, issue in
            Label(
                issue.message,
                systemImage: issue.severity == .error
                    ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
        }

        Text("Use the toolbar action to run full-scan detection.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if appState.diskDetectionSettingsAreStale {
            Label("Full-scan peaks use earlier settings", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Run Detect All Disks again before using the new settings for strain or ACOM.")
        } else if let count = appState.braggPeakCount {
            LabeledContent("Peaks found", value: "\(count)")
            if let summary = appState.completedDiskSummary {
                LabeledContent(
                    "Per pattern",
                    value: String(
                        format: "median %.1f · range %d–%d",
                        summary.medianPeakCount,
                        summary.minimumPeakCount,
                        summary.maximumPeakCount
                    )
                )
                .monospacedDigit()
                ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// The less commonly changed signal/filter parameters, as their own collapsed
/// section — a sibling of the basic rows, not a child of them.
private struct UI2AdvancedDiskDetectionSection: View {
    @Environment(AppState.self) private var appState
    @State private var showsAdvanced = false

    private var detectorMinimum: Int {
        guard let descriptor = appState.descriptor else { return 1 }
        return max(1, min(descriptor.qx, descriptor.qy))
    }

    private var maximumEdgeBoundary: Int {
        appState.diskDetectionContext?.maximumEdgeBoundary
            ?? max(1, (detectorMinimum - 1) / 2)
    }

    var body: some View {
        Section("Advanced detection", isExpanded: $showsAdvanced) {
            // Signal conditioning.
            ui2ParameterSliderRow(
                title: DiskDetectionParameterID.patternSigma.title,
                value: ui2FloatBinding(
                    appState, \.sigmaDP, in: ui2FloatEditorRange(.patternSigma)
                ),
                range: ui2FloatEditorRange(.patternSigma),
                step: Float(DiskDetectionParameterID.patternSigma.editorStep!),
                valueText: String(format: "%.1f px", appState.diskParams.sigmaDP)
            )
            .help(DiskDetectionParameterID.patternSigma.explanation)

            ui2ParameterSliderRow(
                title: DiskDetectionParameterID.correlationSigma.title,
                value: ui2FloatBinding(
                    appState, \.sigmaCC, in: ui2FloatEditorRange(.correlationSigma)
                ),
                range: ui2FloatEditorRange(.correlationSigma),
                step: Float(DiskDetectionParameterID.correlationSigma.editorStep!),
                valueText: String(format: "%.1f px", appState.diskParams.sigmaCC)
            )
            .help(DiskDetectionParameterID.correlationSigma.explanation)

            // Peak acceptance.
            LabeledContent(DiskDetectionParameterID.minimumAbsoluteIntensity.title) {
                UI2NumericField(
                    DiskDetectionParameterID.minimumAbsoluteIntensity.title,
                    value: ui2NonnegativeFloatBinding(appState, \.minAbsoluteIntensity),
                    format: .number.precision(.significantDigits(1...5)),
                    unit: "CC"
                )
            }
            .help(DiskDetectionParameterID.minimumAbsoluteIntensity.explanation)

            LabeledContent(DiskDetectionParameterID.minimumRelativeIntensity.title) {
                UI2NumericField(
                    DiskDetectionParameterID.minimumRelativeIntensity.title,
                    value: ui2RelativeIntensityPercentBinding(appState),
                    format: .number.precision(.fractionLength(0...3)),
                    unit: "%"
                )
            }
            .help(DiskDetectionParameterID.minimumRelativeIntensity.explanation)

            Stepper(
                value: ui2RelativePeakRankBinding(appState),
                in: 1...max(1, appState.diskParams.maxNumPeaks)
            ) {
                Text("\(DiskDetectionParameterID.relativeReferencePeak.title)  #\(appState.diskParams.relativeToPeak + 1)")
            }
            .help(DiskDetectionParameterID.relativeReferencePeak.explanation)

            Stepper(
                value: ui2FloatBinding(appState, \.minPeakSpacing, in: 0...Float(detectorMinimum)),
                in: 0...Float(detectorMinimum),
                step: 1
            ) {
                Text(String(
                    format: "%@  %.0f px",
                    DiskDetectionParameterID.minimumPeakSpacing.title,
                    appState.diskParams.minPeakSpacing
                ))
            }
            .help(DiskDetectionParameterID.minimumPeakSpacing.explanation)

            Stepper(
                value: ui2IntBinding(appState, \.edgeBoundary, in: 1...maximumEdgeBoundary),
                in: 1...maximumEdgeBoundary
            ) {
                Text("\(DiskDetectionParameterID.edgeBoundary.title)  \(appState.diskParams.edgeBoundary) px")
            }
            .help(DiskDetectionParameterID.edgeBoundary.explanation)

            // Fourier localization.
            if appState.diskParams.subpixel == .multicorr {
                Stepper(
                    value: ui2IntBinding(appState, \.upsampleFactor, in: 4...64),
                    in: 4...64,
                    step: 4
                ) {
                    Text("\(DiskDetectionParameterID.upsampleFactor.title)  \(appState.diskParams.upsampleFactor)×")
                }
                .help(DiskDetectionParameterID.upsampleFactor.explanation)
            }

            Text("Changes update the rings on the current CBED. Run the toolbar's full-scan action to apply them to strain and ACOM.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                appState.resetDiskDetectionParams()
            } label: {
                Label("Reset Recommended Settings", systemImage: "arrow.counterclockwise")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("disk.resetParameters")
        }
        .accessibilityIdentifier("disk.advancedDisclosure")
    }
}

// MARK: - Strain

private struct UI2StrainSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var strain = appState.strain
        Section("Strain") {
            failureRemedy

            Picker("Reference", selection: $strain.referenceMode) {
                ForEach(StrainReferenceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityIdentifier("strain.reference")
            // These two pickers ARE the scientific decision, so they say
            // what they decide rather than only what they are set to.
            Text(appState.strain.referenceMode == .selectedRegion
                 ? "Defines zero strain: the visible \(appState.realSpaceShape.rawValue.lowercased()) ROI around the selected scan point is treated as unstrained."
                 : "Defines zero strain: the whole scan is averaged, so strain is measured relative to the mean lattice.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Basis", selection: $strain.basisMode) {
                ForEach(StrainBasisMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityIdentifier("strain.basis")
            .help("The g₁ / g₂ pair every position is indexed against.")

            if appState.strain.basisMode == .manual {
                // The unit stays *visible* rather than moving to hover:
                // these are bare numbers, and a basis vector read in the
                // wrong unit is a silently wrong strain map. Four rows, one
                // component each.
                UI2ManualBasisRow(title: "g₁ x", value: $strain.g1X)
                UI2ManualBasisRow(title: "g₁ y", value: $strain.g1Y)
                UI2ManualBasisRow(title: "g₂ x", value: $strain.g2X)
                UI2ManualBasisRow(title: "g₂ y", value: $strain.g2Y)
            }

            Button {
                Task { await appState.runStrainMapping() }
            } label: {
                Label("Compute Strain Map", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(appState.isBusy || !appState.hasCurrentBraggVectors)

            if appState.diskDetectionSettingsAreStale {
                Text("Detection settings changed — rerun Detect All Disks before strain.")
                    .font(.caption).foregroundStyle(.orange)
            }

            if appState.strain.map != nil {
                Picker("Component", selection: $strain.component) {
                    ForEach(StrainComponent.allCases) { component in
                        Text(component.rawValue).tag(component)
                    }
                }
                .accessibilityIdentifier("strain.component")
                // The frame the tensor components are expressed in — the map
                // is drawn over scan axes, so a detector-frame εxx read as
                // "along the map's horizontal" is silently wrong under a
                // large R–Q rotation. One wording authority:
                // StrainPresentationFrame.displayLabel.
                Text(appState.strainPresentationFrame.displayLabel)
                    .font(.caption)
                    .foregroundStyle(
                        appState.strainPresentationFrame == .detector
                            ? AnyShapeStyle(.orange)
                            : AnyShapeStyle(.secondary)
                    )
                    .accessibilityIdentifier("strain.frame")
                if let map = appState.strain.map {
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
                    .accessibilityIdentifier("strain.diagnostics.basisSupport")
                    LabeledContent(
                        "Basis fit",
                        value: String(
                            format: "RMS %.3g px · κ %.2f",
                            map.diagnostics.basisResidualPixels,
                            map.diagnostics.basisConditionNumber
                        )
                    )
                    .accessibilityIdentifier("strain.diagnostics.basisFit")
                    LabeledContent(
                        "Local fits",
                        value: String(
                            format: "%.0f%% indexed · median RMS %.3g px",
                            map.indexedFraction * 100,
                            map.diagnostics.localResidualMedianPixels
                        )
                    )
                    .accessibilityIdentifier("strain.diagnostics.localFits")
                    LabeledContent(
                        "Reference inliers",
                        value: "\(map.referencePositionCount)/\(map.diagnostics.referenceCandidateCount)"
                    )
                    .accessibilityIdentifier("strain.diagnostics.referenceInliers")
                }
            }
        }
    }

    /// After a failed strain run, offer the *one* control that addresses the
    /// cause rather than restating both possibilities.
    @ViewBuilder
    private var failureRemedy: some View {
        switch appState.strain.failureCause {
        case .starvedInput(let medianPeaks, let emptyPercent):
            Group {
                Label(
                    String(format: "Too few peaks: median %.1f per pattern, %d%% empty",
                           medianPeaks, emptyPercent),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Text("Indexing needs the direct beam plus two more reflections. "
                     + "Lower the detection thresholds, not the reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Go to Bragg Disks") { appState.changeMode(.disks) }
                    .accessibilityIdentifier("strain.remedy.disks")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strain.remedy")

        case .illConditionedBasis:
            Group {
                Label("No single lattice fits the whole reference",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if appState.strain.referenceMode == .wholeScan {
                    Text("The peak population is healthy. Averaging the whole scan "
                         + "mixes regions with different lattices — pick an "
                         + "unstrained region instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use the current ROI as the reference") {
                        appState.strain.referenceMode = .selectedRegion
                    }
                    .accessibilityIdentifier("strain.remedy.useROI")
                } else {
                    Text("Move or resize the reference region onto an unstrained "
                         + "area, or set g₁ and g₂ manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strain.remedy")

        case nil:
            EmptyView()
        }
    }
}

/// One component of the manual g₁ / g₂ basis. The unit is on screen, not in
/// the tooltip; the tooltip says what frame the number is in.
private struct UI2ManualBasisRow: View {
    let title: String
    @Binding var value: Float

    var body: some View {
        LabeledContent(title) {
            UI2NumericField(
                title,
                value: $value,
                format: .number.precision(.fractionLength(3)),
                unit: "px"
            )
        }
        .help("Detector x/y offsets in calibrated pixels.")
    }
}

// MARK: - ACOM

/// ACOM's complete user-facing contract. Keeping material, scale semantics,
/// work scope, and result diagnostics together prevents a physically labelled
/// output from being assembled out of unrelated controls elsewhere.
private struct UI2ACOMSections: View {
    @Environment(AppState.self) private var appState
    @State private var showCIFImporter = false
    @State private var showsEngine = false

    /// Nothing on a stock macOS declares `.cif`, so this resolves to the
    /// dynamic type `dyn.ah62d4rv4ge80g4pg` — which is also what a `.cif` file
    /// on disk resolves to, so the picker matches it. The fallback must be
    /// `.data`, not `.plainText`: a `.cif` file does *not* conform to
    /// `public.plain-text`, so a `.plainText` fallback would grey out every
    /// CIF in the picker.
    private var cifTypes: [UTType] {
        [UTType(filenameExtension: "cif") ?? .data]
    }

    var body: some View {
        @Bindable var session = appState.acomSession
        Section("ACOM (orientation)") {
            Picker("Phase model", selection: $session.modelSelection) {
                Text("Choose phase…").tag(CrystalModelSelection.none)
                ForEach(CrystalModelLibrary.models) { model in
                    Text(model.displayName).tag(CrystalModelSelection.library(model.id))
                }
                Text("Custom cubic…").tag(CrystalModelSelection.customCubic)
                if !appState.acomSession.importedCrystalModels.isEmpty {
                    Divider()
                    ForEach(appState.acomSession.importedCrystalModels) { model in
                        // "Imported" prefix visually distinguishes a
                        // user-supplied CIF from the vetted built-in library.
                        Text("Imported: \(model.displayName)")
                            .tag(CrystalModelSelection.imported(model.id))
                    }
                }
            }
            .accessibilityIdentifier("acom.material")

            Button {
                showCIFImporter = true
            } label: {
                Label("Import CIF…", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("acom.importCIF")
            .fileImporter(
                isPresented: $showCIFImporter,
                allowedContentTypes: cifTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { appState.importCrystalModel(from: url) }
                case .failure(let error):
                    appState.present(error)
                }
            }

            if let reason = appState.acomModelSelectionIssue {
                Label(reason, systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let model = appState.resolvedACOMModel {
                LabeledContent("Symmetry", value: model.symmetry.displayName)
                if model.source == .imported {
                    LabeledContent("Source", value: "Imported CIF")
                }
                Text("The phase model is selected explicitly; mac4DSTEM never infers it from the dataset name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.acomSession.modelSelection == .customCubic {
                customCrystalEditor
            }

            Picker("Quality", selection: $session.quality) {
                ForEach(ACOMQualityPreset.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            Text(appState.acomSession.quality.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            scopeControls

            LabeledContent("Work", value: appState.acomWorkSummary)
                .accessibilityIdentifier("acom.work")
            LabeledContent("Expected", value: appState.acomEstimatedDurationText)
                .accessibilityIdentifier("acom.expected")
            if let suggestion = appState.acomFullScanSuggestion {
                // The sentence wraps as a caption; the button stays short.
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Use Full Scan") {
                    appState.acomSession.scope = .fullScan
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("acom.suggestFullScan")
            }
        }

        Section("Engine & Q scale", isExpanded: $showsEngine) {
            engineControls
            qScaleControls
        }

        Section("Result") {
            prerequisiteStatus
            resultControls
        }
    }

    @ViewBuilder
    private var customCrystalEditor: some View {
        @Bindable var session = appState.acomSession
        Picker("Element", selection: $session.customZ) {
            ForEach(ScatteringFactors.supportedElements, id: \.self) { z in
                Text("\(ScatteringFactors.symbols[z] ?? "?")  (Z=\(z))").tag(z)
            }
        }
        Picker("Structure", selection: $session.customStructure) {
            ForEach(Crystal.CubicStructure.allCases) { structure in
                Text(structure.rawValue).tag(structure)
            }
        }
        LabeledContent("a") {
            UI2NumericField(
                "Lattice parameter a",
                value: $session.customLatticeA,
                format: .number.precision(.fractionLength(0...4)),
                unit: "Å"
            )
        }
        Text("Custom models are single-element cubic cells; other phases need a validated model.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var scopeControls: some View {
        @Bindable var session = appState.acomSession
        // A menu, not three segments: the segmented row does not fit the
        // column (measured 2026-09-03).
        Picker("Area", selection: $session.scope) {
            ForEach(ACOMRunScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .accessibilityIdentifier("acom.scope")

        if appState.acomSession.scope == .selectedRegion, let descriptor = appState.descriptor {
            Stepper(
                "Center X  \(appState.selectedScan.x)",
                value: Binding(
                    get: { appState.selectedScan.x },
                    set: { appState.selectScan(x: $0, y: appState.selectedScan.y) }
                ),
                in: 0...max(0, descriptor.rx - 1)
            )
            Stepper(
                "Center Y  \(appState.selectedScan.y)",
                value: Binding(
                    get: { appState.selectedScan.y },
                    set: { appState.selectScan(x: appState.selectedScan.x, y: $0) }
                ),
                in: 0...max(0, descriptor.ry - 1)
            )
            Stepper(
                "Half-size  \(appState.acomSession.regionRadius) px",
                value: $session.regionRadius,
                in: 4...max(4, min(descriptor.rx, descriptor.ry) / 2)
            )
            Text("The orange square is matched at full spatial resolution.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if appState.acomSession.scope == .preview {
            Text("Samples at most 32 × 32 positions, then expands coarse blocks for a rapid whole-field check.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var engineControls: some View {
        @Bindable var session = appState.acomSession
        Picker("Engine", selection: $session.backend) {
            ForEach(ACOMMatchingBackend.allCases) { backend in
                Text(backend.rawValue).tag(backend)
            }
        }
        LabeledContent("Will use", value: appState.effectiveACOMBackend.rawValue)
        if appState.acomSession.backend == .automatic {
            Text("Automatic currently uses the real-data-verified Accelerate CPU backend.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var qScaleControls: some View {
        @Bindable var session = appState.acomSession
        let semantics = appState.acomScaleSemantics
        LabeledContent("Interpretation") {
            Text(appState.acomInterpretationLabel)
                .foregroundStyle(semantics.provenance.isPhysical ? Color.green : Color.orange)
        }
        LabeledContent(
            "Q scale",
            value: String(format: "%.6g Å⁻¹/px", semantics.invAngstromPerPixel)
        )
        LabeledContent("Provenance", value: semantics.provenance.displayName)

        // **Prepare owns Q calibration.** What lives here is the read-out —
        // interpretation, Q scale, provenance — because ACOM's results are
        // labelled by it, plus a route to the owner. The link is
        // unconditional: when the scale is *not* physical is exactly when a
        // user most needs to be told where to fix it.
        Button("Review Q Calibration in Prepare") {
            appState.selectWorkspace(.prepare)
        }
        .accessibilityIdentifier("acom.reviewQCalibration")

        if !semantics.provenance.isPhysical {
            // A labelled Slider row, not a LabeledContent: as a trailing
            // value a slider collapses to its knob in this column.
            Slider(value: $session.exploratoryScale, in: 0.001...0.05) {
                Text(String(format: "Exploratory scale, %.4f Å⁻¹/px", appState.acomSession.exploratoryScale))
            }
            Text("This can help inspect correlation, but it is not physical calibration and every result remains Exploratory.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if appState.acomSession.hasOrientationPlan, let plan = appState.acomSession.orientationPlan {
            LabeledContent("Cached plan", value: "\(plan.count) templates")
        }
    }

    @ViewBuilder
    private var prerequisiteStatus: some View {
        if appState.diskDetectionSettingsAreStale {
            Text("Detection settings changed — rerun Detect All Disks before ACOM.")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var resultControls: some View {
        if appState.acomSession.hasOrientationMap {
            if let semantics = appState.acomSession.lastRunSemantics {
                Label(
                    semantics.scale.provenance.isPhysical
                        ? "Physical ACOM result" : "Exploratory ACOM result",
                    systemImage: semantics.scale.provenance.isPhysical
                        ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    semantics.scale.provenance.isPhysical ? Color.green : Color.orange
                )
            }
            // Routed through `selectACOMDisplay` rather than bound directly, so
            // an explicit choice here is recorded and a later completed map
            // never silently promotes IPF·Z over it.
            Picker("Display", selection: Binding(
                get: { appState.acomSession.display },
                set: { appState.selectACOMDisplay($0) }
            )) {
                ForEach(ACOMDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            // "Display" alone collides with a section header of the same
            // name; the accessibility label disambiguates for VoiceOver and
            // label-based automation queries.
            .accessibilityLabel("ACOM display mode")
            .accessibilityIdentifier("acom.display")
            // The IPF colour key is drawn over the image, keyed on the
            // *displayed* result actually being an IPF-Z map — a legend
            // belongs with the pixels it decodes, never here.
            if let text = appState.selectedEulerText {
                LabeledContent(
                    "\(appState.acomSession.orientationMap?.symmetry.displayName ?? "Symmetry") FZ Euler",
                    value: text
                )
                .monospacedDigit()
            }
        }
    }
}

// MARK: - Shared rows and bindings

/// A parameter slider row: the title and current value as the slider's own
/// label. Not a `LabeledContent` — as a trailing value a slider collapses to
/// its knob in a narrow column (measured 2026-09-03).
private func ui2ParameterSliderRow(
    title: String,
    value: Binding<Float>,
    range: ClosedRange<Float>,
    step: Float,
    valueText: String
) -> some View {
    Slider(value: value, in: range, step: step) {
        Text("\(title), \(valueText)")
    }
}

private func ui2FloatEditorRange(
    _ parameter: DiskDetectionParameterID
) -> ClosedRange<Float> {
    let range = parameter.editorRange ?? 0...1
    return Float(range.lowerBound)...Float(range.upperBound)
}

private func ui2ParameterBinding<Value>(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Value>
) -> Binding<Value> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = value
            appState.diskParams = params
        }
    )
}

private func ui2FloatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>,
    in range: ClosedRange<Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskParams = params
        }
    )
}

private func ui2NonnegativeFloatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = value.isFinite ? max(0, value) : 0
            appState.diskParams = params
        }
    )
}

private func ui2IntBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Int>,
    in range: ClosedRange<Int>
) -> Binding<Int> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskParams = params
        }
    )
}

private func ui2MaximumPeaksBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskParams.maxNumPeaks },
        set: { value in
            var params = appState.diskParams
            params.maxNumPeaks = min(max(value, 1), 500)
            params.relativeToPeak = min(params.relativeToPeak, params.maxNumPeaks - 1)
            appState.diskParams = params
        }
    )
}

/// py4DSTEM stores this value as a fraction. Percent is easier to reason
/// about in a compact UI while preserving the exact underlying parameter.
private func ui2RelativeIntensityPercentBinding(_ appState: AppState) -> Binding<Double> {
    Binding(
        get: { Double(appState.diskParams.minRelativeIntensity) * 100 },
        set: { value in
            var params = appState.diskParams
            let finite = value.isFinite ? value : 0
            params.minRelativeIntensity = Float(min(max(finite, 0), 100) / 100)
            appState.diskParams = params
        }
    )
}

private func ui2RelativePeakRankBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskParams.relativeToPeak + 1 },
        set: { rank in
            var params = appState.diskParams
            params.relativeToPeak = min(
                max(0, rank - 1), max(0, params.maxNumPeaks - 1)
            )
            appState.diskParams = params
        }
    )
}
