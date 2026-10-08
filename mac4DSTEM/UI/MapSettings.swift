import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import DSTEMTraining
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
/// is `NumericField`, and the body is `InspectorSection`s of `InspectorRow`s
/// (`UI/InspectorRows.swift`), the utility-pane vocabulary the whole
/// inspector shares (034).
/// What the ring-hint task reads, as a cheap `Hashable` identity: the mean
/// pattern's dimensions and a strided sample of its pixels, plus the
/// descriptor dimensions it is checked against. The task used to be keyed on
/// `AppState.patternVersion`, which colormap, log scale, display mode and the
/// region radius also bump, so each of those re-ran the ring search on the
/// whole mean pattern for nothing.
///
/// Safe because a stale key can only keep a hint the pattern still earns:
/// the mean pattern is replaced only by a recomputation (same data, same
/// pixels, same hint) and is set to nil on every dataset change, which moves
/// the key to nil and back before any new pattern is keyed. A collision would
/// need a different mean pattern of the same size agreeing on every sampled
/// pixel, and even then the hint is only an offer the user clicks.
struct ProbeRingHintKey: Hashable {
    let qy: Int
    let qx: Int
    let sampleDigest: Int

    /// Nil when the hint cannot be computed (no mean pattern, no descriptor,
    /// or the two disagree on shape) — the same condition the task checks.
    static func make(mean: DiffractionPattern?, descriptorQy: Int?, descriptorQx: Int?) -> ProbeRingHintKey? {
        guard let mean, let descriptorQy, let descriptorQx,
              mean.qy == descriptorQy, mean.qx == descriptorQx else { return nil }
        var hasher = Hasher()
        let count = mean.pixels.count
        hasher.combine(count)
        let stride = max(1, count / 256)
        var i = 0
        while i < count {
            hasher.combine(mean.pixels[i].bitPattern)
            i += stride
        }
        if count > 0 { hasher.combine(mean.pixels[count - 1].bitPattern) }
        return ProbeRingHintKey(qy: mean.qy, qx: mean.qx, sampleDigest: hasher.finalize())
    }
}

struct MapSettings: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("map.settings.trainingLabels.isExpanded") private var showsTrainingLabels = false

    var body: some View {
        Group {
            switch appState.navigation.analysisMode {
            case .disks:
                // Three jobs, three sections: the kernel, the detection it
                // drives, and the hand-labelled centres that train the
                // learned detector — the last one collapsed, since most
                // runs never touch it.
                InspectorSection("Probe kernel") {
                    DiskDetectionRows(part: .kernel)
                }
                InspectorSection("Disk detection") {
                    DiskDetectionRows(part: .detection)
                }
                AdvancedDiskDetectionSection()
                InspectorSection("Training labels", expanded: $showsTrainingLabels) {
                    DiskCentreLabelsRows()
                }
            case .strain:
                StrainSection()
            case .acom:
                ACOMSections()
            default:
                EmptyView()
            }
        }
        .disabledWhileRunning(appState)
        // The fine-tuning comparison (C4b): opens when a run finishes; Keep Current Model is the default.
        .sheet(item: Binding(
            get: { appState.detectorTraining.review },
            set: { if $0 == nil { appState.discardFineTunedReview() } }
        )) { review in
            DetectorTrainingReviewSheet(review: review)
                .environment(appState)
        }
    }
}

// MARK: - Disk detection

/// Source-faithful controls for py4DSTEM-style Bragg-disk detection: the
/// compact defaults stay visible as rows of the "Disk detection" section; the
/// less commonly changed signal/filter parameters live in the sibling
/// `AdvancedDiskDetectionSection`, a collapsed section of its own.
/// Where the probe kernel comes from is a view choice (owner decision), not
/// app state: the kernel that results records its own source in provenance
/// (`ProbeKernel.source`). Each
/// case carries the old standalone button's icon, help text and
/// accessibility identifier so collapsing four buttons into one changes
/// presentation only, not the four code paths behind them.
private enum KernelSource: String, CaseIterable, Identifiable {
    case synthetic = "Synthetic"
    case currentCBED = "Current CBED / ROI"
    case fileProbe = "File's probe"
    case vacuumScan = "Vacuum scan…"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .synthetic: "circle.circle"
        case .currentCBED: "scope"
        case .fileProbe: "doc.viewfinder"
        case .vacuumScan: "square.stack.3d.up"
        }
    }

    var help: String {
        switch self {
        case .synthetic:
            "Build a synthetic bullseye/trench kernel from the detector geometry — no measured probe needed."
        case .currentCBED:
            "Select a vacuum point or real-space ROI, then build the disk-correlation kernel from its displayed diffraction pattern."
        case .fileProbe:
            "Build the kernel from a probe image stored in the file (py4DSTEM's probe or probe_template) on this detector grid. The status bar says when the file carries none."
        case .vacuumScan:
            "Build the kernel from a SEPARATE vacuum scan file — the fix for a sample with no vacuum region in frame. Its mean pattern is the probe; it must be on the same detector as the loaded data."
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .synthetic: "disk.generateSyntheticKernel"
        case .currentCBED: "disk.generateMeasuredKernel"
        case .fileProbe: "disk.generateFileProbeKernel"
        case .vacuumScan: "disk.generateVacuumProbeKernel"
        }
    }
}

private struct DiskDetectionRows: View {
    enum Part { case kernel, detection }
    let part: Part
    @Environment(AppState.self) private var appState
    /// "Offer the learned (neural net) detector"
    /// (`Session/AppPreferences.swift`) — hides the `.learned` case from the
    /// picker below when off. It never touches the asset, the threshold, or
    /// any other per-dataset setting; only whether the option is offered.
    @Environment(AppPreferences.self) private var preferences
    /// How a MEASURED probe becomes a kernel. A view choice, not app state:
    /// the kernel that results records its own mode in provenance. Flat by
    /// default: the trench needs a correct probe radius, and the estimator
    /// reads structured probes small — the trench default once rebuilt the
    /// failing bullseye kernel on the first click (Gate B).
    @State private var measuredKernelMode: ProbeKernelMode = .flat
    @State private var confirmingModelRemoval = false
    @State private var showVacuumImporter = false
    /// The picked kernel source (see `KernelSource`). Synthetic by default —
    /// the old first button, "Generate Probe Kernel".
    @State private var kernelSource: KernelSource = .synthetic
    /// The ring-shaped-probe hint (`ProbeRingHint`): DERIVED from the mean
    /// pattern, owned by this view and recomputed when the pattern changes —
    /// never stored on AppState, never a default.
    @State private var ringHint: ProbeRingHint.Result?

    private var offeredDetectorClasses: [DetectorClass] {
        preferences.offerLearnedDetector ? DetectorClass.allCases : [.classical]
    }

    private var datasetTypes: [UTType] {
        ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        switch part {
        case .kernel: kernelRows
        case .detection: detectionRows
        }
    }

    /// Whether the one Build Kernel button is disabled for the currently
    /// picked source — `appState.isBusy` (every source) plus that source's
    /// own old per-button condition.
    private var isBuildKernelDisabled: Bool {
        if appState.isBusy { return true }
        switch kernelSource {
        case .synthetic: return false
        case .currentCBED: return appState.displayedPattern == nil
        case .fileProbe: return false
        case .vacuumScan: return !appState.hasDataset
        }
    }

    @ViewBuilder
    private var kernelRows: some View {

        InspectorRow("Source") {
            Picker("Source", selection: $kernelSource) {
                ForEach(KernelSource.allCases) { source in
                    Text(source.rawValue).tag(source).help(source.help)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("disk.kernelSource")
        }
        .task(id: ProbeRingHintKey.make(mean: appState.meanPattern,
                                        descriptorQy: appState.descriptor?.qy,
                                        descriptorQx: appState.descriptor?.qx)) {
            guard let mean = appState.meanPattern, let d = appState.descriptor,
                  mean.qy == d.qy, mean.qx == d.qx else { ringHint = nil; return }
            let (pixels, qy, qx) = (mean.pixels, mean.qy, mean.qx)
            // The compute is synchronous CPU, so it leaves the main actor;
            // `Task.detached` does not inherit this task's cancellation, so
            // it is forwarded by hand and re-checked before the write.
            let work = Task.detached(priority: .utility) {
                ProbeRingHint.outerEdge(meanDP: pixels, qy: qy, qx: qx)
            }
            let hint = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            ringHint = hint
        }
        // The ring-probe warning below appears without any focus change: say so. On the row above, which stays on screen.
        .announcing(ringHint.flatMap { hint in
            appState.calibrationSession.calibration.probeRadius.flatMap {
                ProbeRingHint.isWorthOffering(hint, current: $0)
                    ? RoomAccessibilityText.ringProbe(outerRadius: Double(hint.outerRadius)) : nil
            }
        })

        if kernelSource != .synthetic {
            InspectorRow("Measured kernel mode") {
                Picker("Measured kernel mode", selection: $measuredKernelMode) {
                    ForEach(ProbeKernelMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .tooltip("Flat uses the probe as it is — py4DSTEM's recommendation for bullseye and other structured probes, and it needs no radius. Sigmoid trench subtracts a ring from the probe radius to twice it so the correlation responds to the disk edge; it is only as good as that radius.",
                         hint: "Flat uses the probe as it is; sigmoid trench follows the disk edge")
                .accessibilityIdentifier("disk.measuredKernelMode")
            }
        }

        if let hint = ringHint, let now = appState.calibrationSession.calibration.probeRadius,
           ProbeRingHint.isWorthOffering(hint, current: now) {
            InspectorWarning(
                String(format: "Ring-shaped probe: its outer edge is at %.0f px (now %.1f px)", hint.outerRadius, now),
                systemImage: "circle.dashed")
                .help("The probe-size estimate stops at the first ring. A trench kernel built at the outer edge finds the beam on a ring-structured probe; Train Model uses the same radius.")
            InspectorActionRow {
                InspectorAdaptiveButton(
                    String(format: "Use %.0f px", hint.outerRadius), systemImage: "circle.dashed",
                    help: "Sets the probe radius to the ring's outer edge and rebuilds a synthetic kernel. Nothing changes unless you click."
                ) {
                    PendingEdits.run { await appState.useProbeRadius(hint.outerRadius) }
                }
                .accessibilityIdentifier("disk.useRingRadius")
            }
        }

        InspectorActionRow {
            InspectorAdaptiveButton(
                "Build Kernel", systemImage: kernelSource.systemImage,
                help: kernelSource.help
            ) {
                switch kernelSource {
                case .synthetic:
                    PendingEdits.run { await appState.generateProbeKernel() }
                case .currentCBED:
                    PendingEdits.run { await appState.generateMeasuredProbeKernel(mode: measuredKernelMode) }
                case .fileProbe:
                    PendingEdits.run { await appState.generateFileProbeKernel(mode: measuredKernelMode) }
                case .vacuumScan:
                    showVacuumImporter = true
                }
            }
            .disabled(isBuildKernelDisabled)
            .accessibilityIdentifier(kernelSource.accessibilityIdentifier)
            .fileImporter(
                isPresented: $showVacuumImporter,
                allowedContentTypes: datasetTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        PendingEdits.run { await appState.generateVacuumProbeKernel(fromScan: url, mode: measuredKernelMode) }
                    }
                case .failure(let error):
                    appState.present(error)
                }
            }
        }

        if let kernel = appState.probeKernel {
            InspectorValueRow(
                "Kernel",
                String(
                    format: "%@ · %@ · %.1f px", kernel.source.rawValue,
                    kernel.mode.rawValue.lowercased(), kernel.probeRadius
                )
            )
        }
    }

    @ViewBuilder
    private var detectionRows: some View {
        @Bindable var learned = appState.learnedDetection

        InspectorRow("Detector") {
            Picker("Detector", selection: $learned.detectorClass) {
                ForEach(offeredDetectorClasses) { detectorClass in
                    Text(detectorClass.rawValue).tag(detectorClass)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("disk.detectorClass")
            .tooltip("The neural net proposes candidate positions on the whole pattern; the classical refinement still measures every one.",
                     hint: "The neural net proposes candidates; classical refinement measures each")
            .onChange(of: learned.detectorClass) { _, _ in PendingEdits.run { await appState.detectCurrentPattern() } }
            .onChange(of: learned.threshold) { _, _ in PendingEdits.run { await appState.detectCurrentPattern() } }
            .onChange(of: preferences.offerLearnedDetector) { _, offered in
                guard !offered, learned.detectorClass == .learned else { return }
                learned.detectorClass = .classical
            }
        }

        if learned.detectorClass == .learned {
            InspectorRow("Threshold") {
                NumericField(
                    "Threshold", value: learnedThresholdBinding(appState),
                    format: .number.precision(.fractionLength(2))
                )
                .accessibilityHint("Pick threshold on the heatmap, 0.3 to 0.99; lower accepts more")
            }
            .accessibilityIdentifier("disk.learnedThreshold")
            .help("The pick threshold on the neural net's heatmap, 0.3–0.99. Lower accepts more candidates; the classical refinement still filters them.")

            InspectorRow("Model") {
                Picker("Model", selection: Binding(
                    get: {
                        // A stored model that is no longer listed reads as Bundled, never as a blank picker.
                        let sha = appState.learnedDetection.activeModel?.sha256 ?? ""
                        return appState.detectorTraining.entries.contains { $0.record.sha256 == sha } ? sha : ""
                    },
                    set: { appState.selectDetectorModel(sha256: $0) }
                )) {
                    Text("Bundled").tag("")
                    ForEach(appState.detectorTraining.entries, id: \.record.sha256) { entry in
                        Text("Fine-tuned \(entry.sha8)").tag(entry.record.sha256)
                    }
                }
                .labelsHidden()
                .disabled(appState.isBusy)
                .accessibilityIdentifier("disk.learnedModel")
                .help("The neural-net model every detection uses, app-wide: the bundled one, or a model you fine-tuned on your own labels (Training labels). Each result records which model made it.")
            }
            InspectorValueRow("Model ID", learnedModelStatus(learned))
            if learned.activeModel != nil {
                InspectorActionRow {
                    InspectorAdaptiveButton(
                        "Remove Fine-Tuned Model…", systemImage: "trash",
                        help: "Move the active fine-tuned model to the Trash and go back to the bundled model. Results already made keep their record of which model made them.",
                        role: .destructive
                    ) {
                        confirmingModelRemoval = true
                    }
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("disk.learnedModel.remove")
                }
                .confirmationDialog(
                    "Remove the fine-tuned model?", isPresented: $confirmingModelRemoval, titleVisibility: .visible
                ) {
                    Button("Move to Trash", role: .destructive) { appState.removeActiveFineTunedModel() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It moves to the Trash and the bundled model becomes active. Results already made keep their record of which model made them.")
                }
            }
        }

        if learned.canCompare {
            InspectorActionRow {
                InspectorAdaptiveButton(
                    "Compare Detectors", systemImage: "arrow.left.arrow.right",
                    help: "Publish a scan map of the peaks the neural net and the classical detector do not share at each position, paired within 2 px. Appears once Detect All Disks has run with each detector on this dataset."
                ) {
                    appState.runDiskDisagreement()
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("disk.compareDetectors")
            }
        }

        if appState.probeKernel != nil {
            InspectorValueRow("Current CBED", "\(appState.currentPeaks.count) peaks")
                .accessibilityIdentifier("disk.currentPeakCount")
            if let diagnostics = appState.currentDiskDiagnostics {
                InspectorValueRow(
                    "Acceptance funnel",
                    "\(diagnostics.localMaximumCount) candidates → \(diagnostics.acceptedCount) accepted"
                )
                .help("Edge-qualified local maxima before filters, followed by the final accepted peak count.")
                InspectorNote(
                    "\(diagnostics.afterAbsoluteThresholdCount) pass the absolute threshold → \(diagnostics.afterRelativeThresholdCount) the relative → \(diagnostics.afterSpacingCount) after spacing"
                )
                if diagnostics.wasCountLimited {
                    InspectorWarning("This pattern was truncated to the configured maximum peak count.")
                }
                if appState.diskDetection.diskParams.minRelativeIntensity > 0,
                   !diagnostics.relativeReferenceWasAvailable {
                    InspectorWarning("The selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated.")
                }
            }
        } else {
            InspectorNote("Build a probe kernel to preview detections on the current CBED.")
        }

        ForEach(
            Array(appState.diskDetectionValidationIssues.enumerated()), id: \.offset
        ) { i, issue in
            Label(
                issue.message,
                systemImage: issue.severity == .error
                    ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            // Keyed by text too: a row kept by place kept a stale accessibility value (seen on the Method warnings, drive 8).
            .id("\(i)\u{1F}\(issue.message)")
        }

        InspectorNote("Use the toolbar action to run full-scan detection.")

        if appState.diskDetectionSettingsAreStale {
            DetectionSettingsStaleWarning(reason: "before using the new settings for strain or ACOM")
        } else if let count = appState.resultPresentation.braggPeakCount {
            InspectorValueRow("Peaks found", SystemMonitor.count(count))
            if let summary = appState.completedDiskSummary {
                // Warnings come first: a green "Disks ✓" peak count can be
                // followed by a median ≤ 1 warning that means one peak per
                // pattern, the direct beam only — the reader needs the
                // caveat before the number it qualifies, not scrolled past
                // it (`docs/open-items.md`).
                ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                    InspectorWarning(warning)
                }
                InspectorValueRow(
                    "Per pattern",
                    String(
                        format: "median %.1f · range %d–%d",
                        summary.medianPeakCount,
                        summary.minimumPeakCount,
                        summary.maximumPeakCount
                    )
                )
            }
        }
    }
}

/// Hand-clicked disk-centre labels (C7 session 4): the click-mode toggle,
/// this position's and the dataset's counts, and the three actions that read
/// or write them. State lives in `AppState.diskCentreLabels`
/// (`DiskCentreLabelStore`); every effect here goes back through an AppState
/// method, per the view/Core split.
private struct DiskCentreLabelsRows: View {
    @Environment(AppState.self) private var appState
    @State private var importingLabels = false

    var body: some View {
        @Bindable var labels = appState.diskCentreLabels
        let ry = appState.selectedScan.y, rx = appState.selectedScan.x
        let thisPosition = labels.centres(ry: ry, rx: rx).count

        InspectorRow("Label centres on click") {
            Toggle("Label centres on click", isOn: $labels.labelling)
                .labelsHidden()
                .disabled(appState.descriptor == nil || appState.patternDisplayMode != .current)
                .accessibilityIdentifier("disk.labels.toggle")
                .help("While on, click the diffraction pane to add a hand-clicked disk centre at the current scan position, or click near an existing one to remove it. Only available on the Current pattern display, where there is one scan position to label.")
        }

        InspectorValueRow("This position", "\(thisPosition) centres")
            .accessibilityIdentifier("disk.labels.thisPosition")

        InspectorValueRow(
            "Labelled",
            "\(labels.labelledPositionCount) positions · \(labels.centreCount) centres"
        )
        .accessibilityIdentifier("disk.labels.total")

        InspectorActionRow {
            InspectorAdaptiveButton(
                "Clear This Position", systemImage: "xmark.circle",
                help: "Remove every hand-clicked centre at the current scan position."
            ) {
                labels.clear(ry: ry, rx: rx)
            }
            .disabled(thisPosition == 0)
            .accessibilityIdentifier("disk.labels.clearPosition")

            // Gated like every other sidecar rewrite (review 2026-10-02 e5), and closed while the sidecar holds labels
            // this view did not restore — saving would replace them (a3). The help says which.
            InspectorAdaptiveButton(
                "Save to Sidecar", systemImage: "square.and.arrow.down",
                help: labels.sidecarHoldsUnrestoredLabels
                    ? "The sidecar holds disk-centre labels this view did not restore; saving would replace them. Export Labels… saves these to a file."
                    : (appState.gates.sidecarRewriteRefusal()
                        ?? "Labels ride with the session calibration save — this writes them to the sidecar beside the dataset, alongside calibration.")
            ) {
                appState.saveCalibrationToSessionSidecar()
            }
            .disabled(labels.isEmpty || appState.isBusy || !appState.gates.mayWriteSidecar
                      || labels.sidecarHoldsUnrestoredLabels)
            .accessibilityIdentifier("disk.labels.save")

            InspectorAdaptiveButton(
                "Export Labels…", systemImage: "square.and.arrow.up",
                help: "Write the current labels to a JSON file you choose, in the format tools/disk-detector/label_centres.py writes."
            ) {
                _ = appState.exportDiskCentreLabels()
            }
            .disabled(labels.isEmpty)
            .accessibilityIdentifier("disk.labels.export")

            InspectorAdaptiveButton(
                "Import Labels…", systemImage: "square.and.arrow.down.on.square",
                help: "Read a labels file (the JSON Export Labels… writes) and REPLACE the current labels with it. Refused, changing nothing, if the file labels another dataset or a position lies outside this scan."
            ) {
                importingLabels = true
            }
            .disabled(appState.descriptor == nil)
            .accessibilityIdentifier("disk.labels.import")
            .fileImporter(
                isPresented: $importingLabels,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first, let descriptor = appState.descriptor {
                        appState.importDiskCentreLabels(from: url, descriptor: descriptor)
                    }
                case .failure(let error):
                    appState.present(error)
                }
            }
        }
        if let refusal = labels.importRefusal { InspectorWarning(refusal) }

        // Fine-tune the neural net on these labels (C4b, ADR 048): the split is by a hash of the scan
        // position, so new labels never move a position; the model is judged on the held-out ones.
        let refusal = appState.trainModelRefusal
        InspectorValueRow("Split", TrainingPolicy.splitRowText(appState.trainingSplit))
            .accessibilityHint("About 30 percent of labelled positions are held out to judge the model")
            .help("Positions with at least one centre are split by a hash of the scan position (about 30 % held out), never by centre, so adding labels never moves a position between the sets. The held-out positions judge the fine-tuned model; they never train it.")
            .accessibilityIdentifier("disk.labels.split")

        InspectorActionRow {
            InspectorAdaptiveButton(
                "Train Model…", systemImage: "brain",
                help: refusal ?? "Fine-tune the bundled neural-net model on the training positions (about a minute on the GPU), then judge it against the active model on the held-out positions with the current settings. It is offered only if it is at least as good on recall and precision and better on one. Needs at least \(TrainingPolicy.minimumHeldOutPositions) held-out positions (a floor not yet measured on the data; the count is always shown)."
            ) {
                PendingEdits.run { await appState.trainDetectorModel() }
            }
            .disabled(refusal != nil)
            .accessibilityIdentifier("disk.labels.train")
        }
        if let refusal { InspectorNote(refusal) }
    }
}

/// The less commonly changed signal/filter parameters, as their own collapsed
/// section — a sibling of the basic rows, not a child of them.
private struct AdvancedDiskDetectionSection: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("map.settings.advancedDetection.isExpanded") private var showsAdvanced = false
    @State private var showsResetConfirmation = false

    private var detectorMinimum: Int {
        guard let descriptor = appState.descriptor else { return 1 }
        return max(1, min(descriptor.qx, descriptor.qy))
    }

    private var maximumEdgeBoundary: Int {
        appState.diskDetectionContext?.maximumEdgeBoundary
            ?? max(1, (detectorMinimum - 1) / 2)
    }

    var body: some View {
        InspectorSection("Advanced detection", expanded: $showsAdvanced) {
            // These are py4DSTEM algorithm kwargs without a physical unit:
            // keep them together behind the remembered Advanced disclosure.
            AdjustmentSlider(
                DiskDetectionParameterID.correlationPower.title,
                value: doubleBinding(floatBinding(
                    appState, \.corrPower, in: floatEditorRange(.correlationPower)
                )),
                in: DiskDetectionParameterID.correlationPower.editorRange ?? 0...1,
                step: DiskDetectionParameterID.correlationPower.editorStep,
                format: .number.precision(.fractionLength(2))
            )
            .help(DiskDetectionParameterID.correlationPower.explanation)

            InspectorRow(DiskDetectionParameterID.subpixel.title) {
                Picker(
                    DiskDetectionParameterID.subpixel.title,
                    selection: parameterBinding(appState, \.subpixel)
                ) {
                    ForEach(SubpixelMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .help(DiskDetectionParameterID.subpixel.explanation)
            }

            InspectorRow(DiskDetectionParameterID.maximumPeaks.title) {
                Stepper(value: maximumPeaksBinding(appState), in: 1...500) {
                    Text("\(appState.diskDetection.diskParams.maxNumPeaks)")
                }
                .accessibilityLabel(DiskDetectionParameterID.maximumPeaks.title)
                .accessibilityValue("\(appState.diskDetection.diskParams.maxNumPeaks)")
            }
            .help(DiskDetectionParameterID.maximumPeaks.explanation)

            // Signal conditioning.
            AdjustmentSlider(
                DiskDetectionParameterID.patternSigma.title,
                value: doubleBinding(floatBinding(
                    appState, \.sigmaDP, in: floatEditorRange(.patternSigma)
                )),
                in: DiskDetectionParameterID.patternSigma.editorRange ?? 0...1,
                step: DiskDetectionParameterID.patternSigma.editorStep,
                format: .number.precision(.fractionLength(1)),
                unit: "px"
            )
            .help(DiskDetectionParameterID.patternSigma.explanation)

            AdjustmentSlider(
                DiskDetectionParameterID.correlationSigma.title,
                value: doubleBinding(floatBinding(
                    appState, \.sigmaCC, in: floatEditorRange(.correlationSigma)
                )),
                in: DiskDetectionParameterID.correlationSigma.editorRange ?? 0...1,
                step: DiskDetectionParameterID.correlationSigma.editorStep,
                format: .number.precision(.fractionLength(1)),
                unit: "px"
            )
            .help(DiskDetectionParameterID.correlationSigma.explanation)

            // Peak acceptance.
            InspectorRow(DiskDetectionParameterID.minimumAbsoluteIntensity.title) {
                NumericField(
                    DiskDetectionParameterID.minimumAbsoluteIntensity.title,
                    value: nonnegativeFloatBinding(appState, \.minAbsoluteIntensity),
                    format: .number.precision(.significantDigits(1...5)),
                    unit: "CC"
                )
            }
            .help(DiskDetectionParameterID.minimumAbsoluteIntensity.explanation)

            InspectorRow(DiskDetectionParameterID.minimumRelativeIntensity.title) {
                NumericField(
                    DiskDetectionParameterID.minimumRelativeIntensity.title,
                    value: relativeIntensityPercentBinding(appState),
                    format: .number.precision(.fractionLength(0...3)),
                    unit: "%"
                )
            }
            .help(DiskDetectionParameterID.minimumRelativeIntensity.explanation)

            InspectorRow(DiskDetectionParameterID.relativeReferencePeak.title) {
                Stepper(
                    value: relativePeakRankBinding(appState),
                    in: 1...max(1, appState.diskDetection.diskParams.maxNumPeaks)
                ) {
                    Text("#\(appState.diskDetection.diskParams.relativeToPeak + 1)")
                }
                .accessibilityLabel(DiskDetectionParameterID.relativeReferencePeak.title)
                .accessibilityValue(RoomAccessibilityText.referencePeak(
                    zeroBasedIndex: appState.diskDetection.diskParams.relativeToPeak))
            }
            .help(DiskDetectionParameterID.relativeReferencePeak.explanation)

            // On a pattern whose direct beam saturates, "0.5% of the
            // maximum" is 0.5% of a plateau. The reference can exclude the
            // beam; 0 keeps py4DSTEM's rule and nothing shipped moves.
            InspectorRow(DiskDetectionParameterID.relativeReferenceMinimumRadius.title) {
                Stepper(
                    value: floatBinding(appState, \.relativeReferenceMinimumRadiusPx, in: 0...Float(detectorMinimum)),
                    in: 0...Float(detectorMinimum),
                    step: 1
                ) {
                    Text(String(
                        format: "%.0f px",
                        appState.diskDetection.diskParams.relativeReferenceMinimumRadiusPx
                    ))
                }
                .accessibilityLabel(DiskDetectionParameterID.relativeReferenceMinimumRadius.title)
                .accessibilityValue(RoomAccessibilityText.pixels(
                    Double(appState.diskDetection.diskParams.relativeReferenceMinimumRadiusPx.rounded())))
            }
            .help(DiskDetectionParameterID.relativeReferenceMinimumRadius.explanation)

            InspectorRow(DiskDetectionParameterID.minimumPeakSpacing.title) {
                Stepper(
                    value: floatBinding(appState, \.minPeakSpacing, in: 0...Float(detectorMinimum)),
                    in: 0...Float(detectorMinimum),
                    step: 1
                ) {
                    Text(String(
                        format: "%.0f px",
                        appState.diskDetection.diskParams.minPeakSpacing
                    ))
                }
                .accessibilityLabel(DiskDetectionParameterID.minimumPeakSpacing.title)
                .accessibilityValue(RoomAccessibilityText.pixels(
                    Double(appState.diskDetection.diskParams.minPeakSpacing.rounded())))
            }
            .help(DiskDetectionParameterID.minimumPeakSpacing.explanation)

            InspectorRow(DiskDetectionParameterID.edgeBoundary.title) {
                Stepper(
                    value: intBinding(appState, \.edgeBoundary, in: 1...maximumEdgeBoundary),
                    in: 1...maximumEdgeBoundary
                ) {
                    Text("\(appState.diskDetection.diskParams.edgeBoundary) px")
                }
                .accessibilityLabel(DiskDetectionParameterID.edgeBoundary.title)
                .accessibilityValue(RoomAccessibilityText.pixels(Double(appState.diskDetection.diskParams.edgeBoundary)))
            }
            .help(DiskDetectionParameterID.edgeBoundary.explanation)

            // Fourier localization.
            if appState.diskDetection.diskParams.subpixel == .multicorr {
                InspectorRow(DiskDetectionParameterID.upsampleFactor.title) {
                    Stepper(
                        value: intBinding(appState, \.upsampleFactor, in: 4...64),
                        in: 4...64,
                        step: 4
                    ) {
                        Text("\(appState.diskDetection.diskParams.upsampleFactor)×")
                    }
                    .accessibilityLabel(DiskDetectionParameterID.upsampleFactor.title)
                    .accessibilityValue(RoomAccessibilityText.upsampleFactor(appState.diskDetection.diskParams.upsampleFactor))
                }
                .help(DiskDetectionParameterID.upsampleFactor.explanation)
            }

            InspectorNote("Changes update the rings on the current CBED. Run the toolbar's full-scan action to apply them to strain and ACOM.")

            InspectorActionRow {
                InspectorAdaptiveButton("Reset Recommended Settings", systemImage: "arrow.counterclockwise") {
                    showsResetConfirmation = true
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("disk.resetParameters")
            }
        }
        .accessibilityIdentifier("disk.advancedDisclosure")
        .confirmationDialog(
            "Reset recommended detection settings?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Recommended Settings", role: .destructive) {
                appState.resetDiskDetectionParams()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current disk detection parameters will be replaced with the recommended defaults.")
        }
    }
}

// MARK: - Strain

private struct StrainSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var strain = appState.strain
        InspectorSection("Strain") {
            failureRemedy

            InspectorRow("Reference") {
                Picker("Reference", selection: $strain.referenceMode) {
                    ForEach(StrainReferenceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("strain.reference")
            }
            // These two pickers ARE the scientific decision, so they say
            // what they decide rather than only what they are set to.
            InspectorNote(appState.strain.referenceMode == .selectedRegion
                 ? "Defines zero strain: the visible \(appState.realSpaceShape.rawValue.lowercased()) ROI around the selected scan point is treated as unstrained."
                 : "Defines zero strain: the whole scan is averaged, so strain is measured relative to the mean lattice.")

            InspectorRow("Basis") {
                Picker("Basis", selection: $strain.basisMode) {
                    ForEach(StrainBasisMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("strain.basis")
                .help("The g₁ / g₂ pair every position is indexed against.")
            }

            if appState.strain.basisMode == .manual {
                // The unit stays *visible* rather than moving to hover:
                // these are bare numbers, and a basis vector read in the
                // wrong unit is a silently wrong strain map. Four rows, one
                // component each.
                ManualBasisRow(title: "g₁ x", value: $strain.g1X)
                ManualBasisRow(title: "g₁ y", value: $strain.g1Y)
                ManualBasisRow(title: "g₂ x", value: $strain.g2X)
                ManualBasisRow(title: "g₂ y", value: $strain.g2Y)
            }

            InspectorActionRow {
                InspectorAdaptiveButton(
                    "Compute Strain Map", systemImage: "arrow.up.left.and.arrow.down.right"
                ) {
                    PendingEdits.run { await appState.runStrainMapping() }
                }
                // C4(a): was `appState.isBusy || !appState.hasCurrentBraggVectors`
                // — `hasCurrentBraggVectors` is exactly the readiness this button
                // now asks for instead, so the two paths cannot drift again.
                .disabled(!ProductWorkflow.mayRun(
                    .strain, readiness: appState.productWorkflowReadiness, isBusy: appState.isBusy
                ))
            }

            if appState.diskDetectionSettingsAreStale {
                DetectionSettingsStaleWarning(reason: "before strain")
            }

            if appState.strain.map != nil {
                InspectorRow("Component") {
                    Picker("Component", selection: $strain.component) {
                        ForEach(StrainComponent.allCases) { component in
                            Text(component.rawValue).tag(component)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("strain.component")
                }
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
                    InspectorValueRow(
                        map.diagnostics.automaticBasis
                            ? "Basis consensus" : "Basis support",
                        String(
                            format: "%.0f%% · %d/%d peaks",
                            map.diagnostics.basisSupportFraction * 100,
                            map.diagnostics.basisSupportCount,
                            map.diagnostics.basisObservationCount
                        )
                    )
                    .accessibilityIdentifier("strain.diagnostics.basisSupport")
                    InspectorValueRow(
                        "Basis fit",
                        String(
                            format: "RMS %.3g px · κ %.2f",
                            map.diagnostics.basisResidualPixels,
                            map.diagnostics.basisConditionNumber
                        )
                    )
                    .accessibilityIdentifier("strain.diagnostics.basisFit")
                    InspectorValueRow(
                        "Local fits",
                        String(
                            format: "%.0f%% indexed · median RMS %.3g px",
                            map.indexedFraction * 100,
                            map.diagnostics.localResidualMedianPixels
                        )
                    )
                    .accessibilityIdentifier("strain.diagnostics.localFits")
                    InspectorValueRow(
                        "Reference inliers",
                        "\(map.referencePositionCount)/\(map.diagnostics.referenceCandidateCount)"
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
                InspectorNote("Indexing needs the direct beam plus two more reflections. "
                     + "Lower the detection thresholds, not the reference.")
                InspectorActionRow {
                    InspectorAdaptiveButton("Go to Bragg Disks", systemImage: "circle.grid.cross") {
                        appState.changeMode(.disks)
                    }
                    .accessibilityIdentifier("strain.remedy.disks")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strain.remedy")

        case .illConditionedBasis:
            Group {
                Label("No single lattice fits the whole reference",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if appState.strain.referenceMode == .wholeScan {
                    InspectorNote("The peak population is healthy. Averaging the whole scan "
                         + "mixes regions with different lattices — pick an "
                         + "unstrained region instead.")
                    InspectorActionRow {
                        InspectorAdaptiveButton("Use the current ROI as the reference", systemImage: "viewfinder") {
                            appState.strain.referenceMode = .selectedRegion
                        }
                        .accessibilityIdentifier("strain.remedy.useROI")
                    }
                } else {
                    InspectorNote("Move or resize the reference region onto an unstrained "
                         + "area, or set g₁ and g₂ manually.")
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
private struct ManualBasisRow: View {
    let title: String
    @Binding var value: Float

    var body: some View {
        InspectorRow(title) {
            NumericField(
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

/// The ACOM "Source" row's label for a resolved phase model. Exhaustive over
/// `CrystalModelSource` on purpose: `.builtIn` and `.custom` used to fall
/// through to `EmptyView()` in the row's own `switch`, so a session restored
/// from a recipe that resolved to a built-in or custom-cubic model (still
/// live for replay — see `CrystalModelLibrary`'s doc comment — even though
/// neither is offered from the picker any more) showed no Source line at
/// all. `internal` (not `private`), so `ACOMPhaseModelSourceLabelTests` can
/// pin every case directly rather than through the view.
func acomPhaseModelSourceLabel(source: CrystalModelSource, id: String) -> String {
    switch source {
    case .imported: return "Imported CIF"
    case .materialsProject: return "Materials Project \(id)"
    case .builtIn: return "Built-in library"
    case .custom: return "Custom cell"
    }
}

/// ACOM's complete user-facing contract. Keeping material, scale semantics,
/// work scope, and result diagnostics together prevents a physically labelled
/// output from being assembled out of unrelated controls elsewhere.
private struct ACOMSections: View {
    @Environment(AppState.self) private var appState
    @State private var showCIFImporter = false
    @State private var showMaterialsProjectSheet = false
    @SceneStorage("map.settings.acomEngine.isExpanded") private var showsEngine = false

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
        InspectorSection("ACOM (orientation)") {
            // Materials Project is the default phase source (owner
            // decision); the built-in library and "Custom cubic…" are no
            // longer offered here — see the doc comment on
            // `CrystalModelLibrary.models`. A picker whose only choices
            // were "Choose phase…" and already-imported models added
            // nothing over the buttons below, so it's gone: the row is
            // just the current selection's name, and the two buttons are
            // the only way to choose a phase model. Switching between
            // already-imported models still works, as the `Menu` case of
            // `phaseModelValue`.
            InspectorRow("Phase model") {
                phaseModelValue
            }

            InspectorActionRow {
                InspectorAdaptiveButton("Materials Project…", systemImage: "network") {
                    showMaterialsProjectSheet = true
                }
                .accessibilityIdentifier("acom.materialsProject")

                InspectorAdaptiveButton("Import CIF…", systemImage: "square.and.arrow.down") {
                    showCIFImporter = true
                }
                .accessibilityIdentifier("acom.importCIF")
            }
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
            .sheet(isPresented: $showMaterialsProjectSheet) {
                MaterialsProjectImportSheet(addsToPhaseMapping: false)
                    .environment(appState)
            }

            if appState.acomSession.modelSelection == .none {
                // The Requirements list already says "choose a phase model".
            } else if let reason = appState.acomSession.modelSelectionIssue {
                InspectorWarning(reason, systemImage: "nosign")
            } else if let model = appState.resolvedACOMModel {
                InspectorValueRow("Symmetry", model.symmetry.displayName)
                InspectorValueRow("Source", acomPhaseModelSourceLabel(source: model.source, id: model.id))
                InspectorNote("The phase model is selected explicitly; mac4DSTEM never infers it from the dataset name.")
            }

            if appState.acomSession.modelSelection == .customCubic {
                customCrystalEditor
            }

            InspectorRow("Quality") {
                Picker("Quality", selection: $session.quality) {
                    ForEach(ACOMQualityPreset.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .labelsHidden()
            }
            InspectorNote(appState.acomSession.quality.detail)
            // The app's only measured figure for how well it orients, so a
            // user reads it before trusting a zone axis to the degree.
            // Planted aluminium patterns, measured 2026-09-15 with the since
            // retired `tools/acom-groundtruth` (restore: docs/archive/v4/
            // tools-retired-2026-09-23.md); no other phase has been measured.
            // Static on purpose: a number with its date and scope, not a promise.
            InspectorNote("Orientation accuracy, measured on aluminium at 200 templates: exact to the bank's spacing on most zone axes, up to 1.9° off on ⟨011⟩ and 13.6° off on ⟨122⟩. Not measured for other phases; more templates measured worse.")
                .help("Measured on 136 planted aluminium patterns across nine zone axes and two azimuthal bins of in-plane rotation (2026-09-15). The angles are the total error against the planted axis: the template bank's own spacing accounts for at most 0.8° of the 13.6°; the rest comes from the score preferring a wrong template when the true one's ring groups straddle an azimuthal bin.")

            scopeControls

            InspectorValueRow("Work", appState.acomWorkSummary)
                .accessibilityIdentifier("acom.work")
            InspectorValueRow("Expected", appState.acomEstimatedDurationText)
                .accessibilityIdentifier("acom.expected")
            if let suggestion = appState.acomFullScanSuggestion {
                // The sentence wraps as a caption; the button stays short.
                InspectorNote(suggestion)
                InspectorActionRow {
                    InspectorAdaptiveButton("Use Full Scan", systemImage: "square.grid.3x3") {
                        appState.acomSession.scope = .fullScan
                    }
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("acom.suggestFullScan")
                }
            }
        }

        InspectorSection("Engine & Q scale", expanded: $showsEngine) {
            engineControls
            qScaleControls
        }

        InspectorSection("Result") {
            prerequisiteStatus
            resultControls
        }
    }

    /// The "Phase model" row's value: the current selection's name (via
    /// `selectedModelForDisplay`, so a `.library`/`.customCubic` selection —
    /// never offered below, but still resolvable for replay/tests — still
    /// reads correctly), wrapped in a `Menu` once there is more than one
    /// already-imported model to switch between. "None chosen" is plain
    /// text, not a control: nothing is chosen from this row any more, only
    /// from the "Materials Project…" / "Import CIF…" buttons below.
    @ViewBuilder
    private var phaseModelValue: some View {
        let imported = appState.acomSession.importedCrystalModels
        if let model = selectedModelForDisplay {
            if imported.count >= 2 {
                Menu {
                    ForEach(imported) { candidate in
                        Button(importedCrystalModelLabel(candidate)) {
                            appState.acomSession.modelSelection = .imported(candidate.id)
                        }
                    }
                } label: {
                    Text(acomPhaseModelValueText(model))
                }
                .accessibilityLabel("Phase model")
                .accessibilityValue(acomPhaseModelValueText(model))
                .accessibilityIdentifier("acom.phaseModelName")
            } else {
                Text(acomPhaseModelValueText(model))
                    .accessibilityIdentifier("acom.phaseModelName")
            }
        } else {
            Text("None chosen")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("acom.phaseModelName")
        }
    }

    /// Resolves `modelSelection` to a `CrystalModel` for display only —
    /// unlike `AppState.resolvedACOMModel`, this does NOT gate on `isUsable`
    /// / `supportsOrientationMapping`, because an unusable or non-mappable
    /// selection still has a name to show; `modelSelectionIssue` (below,
    /// unchanged) is what tells the user it can't be used.
    private var selectedModelForDisplay: CrystalModel? {
        switch appState.acomSession.modelSelection {
        case .none:
            return nil
        case .library(let id):
            return CrystalModelLibrary.model(id: id)
        case .customCubic:
            return CrystalModelLibrary.customCubic(
                structure: appState.acomSession.customStructure,
                latticeA: appState.acomSession.customLatticeA,
                atomicNumber: appState.acomSession.customZ
            )
        case .imported(let id):
            return appState.acomSession.importedCrystalModels.first { $0.id == id }
        }
    }

    @ViewBuilder
    private var customCrystalEditor: some View {
        @Bindable var session = appState.acomSession
        InspectorRow("Element") {
            Picker("Element", selection: $session.customZ) {
                ForEach(ScatteringFactors.supportedElements, id: \.self) { z in
                    Text("\(ScatteringFactors.symbols[z] ?? "?")  (Z=\(z))").tag(z)
                }
            }
            .labelsHidden()
        }
        InspectorRow("Structure") {
            Picker("Structure", selection: $session.customStructure) {
                ForEach(Crystal.CubicStructure.allCases) { structure in
                    Text(structure.rawValue).tag(structure)
                }
            }
            .labelsHidden()
        }
        InspectorRow("a") {
            NumericField(
                "Lattice parameter a",
                value: $session.customLatticeA,
                format: .number.precision(.fractionLength(0...4)),
                unit: "Å"
            )
        }
        InspectorNote("Custom models are single-element cubic cells; other phases need a validated model.")
    }

    @ViewBuilder
    private var scopeControls: some View {
        @Bindable var session = appState.acomSession
        // A menu, not three segments: the segmented row does not fit the
        // column (measured 2026-09-03).
        InspectorRow("Area") {
            Picker("Area", selection: $session.scope) {
                ForEach(ACOMRunScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("acom.scope")
        }

        if appState.acomSession.scope == .selectedRegion, let descriptor = appState.descriptor {
            InspectorRow("Center X") {
                Stepper(
                    value: Binding(
                        get: { appState.selectedScan.x },
                        set: { appState.selectScan(x: $0, y: appState.selectedScan.y) }
                    ),
                    in: 0...max(0, descriptor.rx - 1)
                ) {
                    Text("\(appState.selectedScan.x)")
                }
                .accessibilityLabel("Center X")
                .accessibilityValue("\(appState.selectedScan.x)")
            }
            InspectorRow("Center Y") {
                Stepper(
                    value: Binding(
                        get: { appState.selectedScan.y },
                        set: { appState.selectScan(x: appState.selectedScan.x, y: $0) }
                    ),
                    in: 0...max(0, descriptor.ry - 1)
                ) {
                    Text("\(appState.selectedScan.y)")
                }
                .accessibilityLabel("Center Y")
                .accessibilityValue("\(appState.selectedScan.y)")
            }
            InspectorRow("Half-size") {
                Stepper(
                    value: $session.regionRadius,
                    in: 4...max(4, min(descriptor.rx, descriptor.ry) / 2)
                ) {
                    Text("\(appState.acomSession.regionRadius) px")
                }
                .accessibilityLabel("Half-size")
                .accessibilityValue(RoomAccessibilityText.pixels(Double(appState.acomSession.regionRadius)))
            }
            InspectorNote("The orange square is matched at full spatial resolution.")
        } else if appState.acomSession.scope == .preview {
            InspectorNote("Samples at most 32 × 32 positions, then expands coarse blocks for a rapid whole-field check.")
        }
    }

    @ViewBuilder
    private var engineControls: some View {
        @Bindable var session = appState.acomSession
        InspectorRow("Engine") {
            Picker("Engine", selection: $session.backend) {
                ForEach(ACOMMatchingBackend.allCases) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            .labelsHidden()
        }
        InspectorValueRow("Will use", appState.acomSession.effectiveBackend.rawValue)
        if appState.acomSession.backend == .automatic {
            InspectorNote("Automatic currently uses the real-data-verified Accelerate CPU backend.")
        }
    }

    @ViewBuilder
    private var qScaleControls: some View {
        @Bindable var session = appState.acomSession
        let semantics = appState.acomScaleSemantics
        InspectorRow("Interpretation") {
            Text(appState.acomInterpretationLabel)
                .foregroundStyle(semantics.provenance.isPhysical ? Color.green : Color.orange)
        }
        InspectorValueRow(
            "Q scale",
            ACOMQScaleReadout.text(semantics.invAngstromPerPixel)
        )
        InspectorValueRow("Provenance", semantics.provenance.displayName)

        // **Prepare owns Q calibration.** What lives here is the read-out —
        // interpretation, Q scale, provenance — because ACOM's results are
        // labelled by it, plus a route to the owner. The link is
        // unconditional: when the scale is *not* physical is exactly when a
        // user most needs to be told where to fix it.
        InspectorActionRow {
            InspectorAdaptiveButton("Review Q Calibration in Prepare", systemImage: "checkmark.seal") {
                appState.selectWorkspace(.prepare)
            }
            .accessibilityIdentifier("acom.reviewQCalibration")
        }

        if !semantics.provenance.isPhysical {
            // An AdjustmentSlider row, not InspectorValueRow: this is a
            // scientifically live control, not a read-out.
            AdjustmentSlider(
                "Exploratory scale",
                value: $session.exploratoryScale,
                in: 0.001...0.05,
                format: .number.precision(.fractionLength(4)),
                unit: "Å⁻¹/px"
            )
            Text("This can help inspect correlation, but it is not physical calibration and every result remains Exploratory.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if appState.acomSession.hasOrientationPlan, let plan = appState.acomSession.orientationPlan {
            InspectorValueRow("Cached plan", "\(plan.count) templates")
        }
    }

    @ViewBuilder
    private var prerequisiteStatus: some View {
        if appState.diskDetectionSettingsAreStale {
            DetectionSettingsStaleWarning(reason: "before ACOM")
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
            InspectorRow("Display") {
                Picker("Display", selection: Binding(
                    get: { appState.acomSession.display },
                    set: { appState.selectACOMDisplay($0) }
                )) {
                    ForEach(ACOMDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                // "Display" alone collides with a section header of the same
                // name; the accessibility label disambiguates for VoiceOver and
                // label-based automation queries.
                .accessibilityLabel("ACOM display mode")
                .accessibilityIdentifier("acom.display")
            }
            // Owner card S2 (a), 2026-10-02: label now, settle the convention after v4.1.
            if appState.acomSession.display == .inPlane {
                InspectorNote(ACOMDisplayMode.inPlaneConventionNote)
            }
            // The IPF colour key is drawn over the image, keyed on the
            // *displayed* result actually being an IPF-Z map — a legend
            // belongs with the pixels it decodes, never here.
            if let text = appState.selectedEulerText {
                InspectorValueRow(
                    "\(appState.acomSession.orientationMap?.symmetry.displayName ?? "Symmetry") FZ Euler",
                    text
                )
                if let mirrored = appState.selectedMirroredText {
                    InspectorValueRow("Mirrored", mirrored)
                        .help("Yes: the pattern matched the mirror image of the template (the matcher's conjugated pass).")
                }
            }
        }
    }
}

// MARK: - Shared rows and bindings

/// The warning shown wherever `AppState.diskDetectionSettingsAreStale` gates
/// a section — Disks, Strain and ACOM each hand-copied this, and Disks' copy
/// put the "rerun Detect All Disks" instruction only in a `.help()` tooltip
/// rather than the always-visible text the other two carry (consolidation
/// review, finding W-5). One row, one wording, the reason parametrized per
/// caller.
private struct DetectionSettingsStaleWarning: View {
    let reason: String

    var body: some View {
        Text("Detection settings changed — rerun Detect All Disks \(reason).")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// Bridges a `Float` parameter binding to the `Double` `AdjustmentSlider`
/// expects; the clamping stays in the wrapped `Float` binding, unchanged.
private func doubleBinding(_ floatBinding: Binding<Float>) -> Binding<Double> {
    Binding(
        get: { Double(floatBinding.wrappedValue) },
        set: { floatBinding.wrappedValue = Float($0) }
    )
}

private func floatEditorRange(
    _ parameter: DiskDetectionParameterID
) -> ClosedRange<Float> {
    let range = parameter.editorRange ?? 0...1
    return Float(range.lowerBound)...Float(range.upperBound)
}

private func parameterBinding<Value>(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Value>
) -> Binding<Value> {
    Binding(
        get: { appState.diskDetection.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskDetection.diskParams
            params[keyPath: keyPath] = value
            appState.diskDetection.diskParams = params
        }
    )
}

private func floatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>,
    in range: ClosedRange<Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskDetection.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskDetection.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskDetection.diskParams = params
        }
    )
}

private func nonnegativeFloatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskDetection.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskDetection.diskParams
            params[keyPath: keyPath] = value.isFinite ? max(0, value) : 0
            appState.diskDetection.diskParams = params
        }
    )
}

private func intBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Int>,
    in range: ClosedRange<Int>
) -> Binding<Int> {
    Binding(
        get: { appState.diskDetection.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskDetection.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskDetection.diskParams = params
        }
    )
}

/// Clamped to the range around `LearnedDiskDetector.defaultThreshold` (0.7).
private func learnedThresholdBinding(_ appState: AppState) -> Binding<Float> {
    Binding(
        get: { appState.learnedDetection.threshold },
        set: { value in
            let finite = value.isFinite ? value : LearnedDiskDetector.defaultThreshold
            appState.learnedDetection.threshold = min(max(finite, 0.3), 0.99)
        }
    )
}

/// The "Model" row's one line: loading, loaded (its identity hash), failed
/// (why), or not yet attempted.
private func learnedModelStatus(_ learned: LearnedDetectionSession) -> String {
    if learned.preparing { return "Loading…" }
    if let sha = learned.assetSHA256 { return String(sha.prefix(8)) }
    if let reason = learned.unavailableReason { return reason }
    return "Loads on the first run"
}

private func maximumPeaksBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskDetection.diskParams.maxNumPeaks },
        set: { value in
            var params = appState.diskDetection.diskParams
            params.maxNumPeaks = min(max(value, 1), 500)
            params.relativeToPeak = min(params.relativeToPeak, params.maxNumPeaks - 1)
            appState.diskDetection.diskParams = params
        }
    )
}

/// py4DSTEM stores this value as a fraction. Percent is easier to reason
/// about in a compact UI while preserving the exact underlying parameter.
private func relativeIntensityPercentBinding(_ appState: AppState) -> Binding<Double> {
    Binding(
        get: { Double(appState.diskDetection.diskParams.minRelativeIntensity) * 100 },
        set: { value in
            var params = appState.diskDetection.diskParams
            let finite = value.isFinite ? value : 0
            params.minRelativeIntensity = Float(min(max(finite, 0), 100) / 100)
            appState.diskDetection.diskParams = params
        }
    )
}

private func relativePeakRankBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskDetection.diskParams.relativeToPeak + 1 },
        set: { rank in
            var params = appState.diskDetection.diskParams
            params.relativeToPeak = min(
                max(0, rank - 1), max(0, params.maxNumPeaks - 1)
            )
            appState.diskDetection.diskParams = params
        }
    )
}

/// The ACOM Q-scale read-out in the locale's own decimal mark. `String(format:)`
/// printed a period beside the comma fields of a German region (polish drive
/// 2026-10-04). Six significant digits, as the old `%.6g` gave, trailing zeros dropped.
nonisolated enum ACOMQScaleReadout {
    static func text(_ invAngstromPerPixel: Double, locale: Locale = .current) -> String {
        invAngstromPerPixel.formatted(.number.precision(.significantDigits(1...6)).locale(locale)) + " Å⁻¹/px"
    }
}
