import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The UI2 inspector: the window's right column, in two tabs.
///
/// **Settings** is every control the selected workspace owns, preceded by the
/// one readiness surface in the app — what still has to happen before the
/// selected task may run, and, when it may, what its numbers will and will
/// not mean. **Info** is what the dataset and the displayed product actually
/// *are*: the descriptive halves of the old `DatasetInspector` and
/// `ProductInspector`, merged.
///
/// **Why they merged.** The old pair was chosen by which pane held the focus
/// ring (`WorkspaceNavigation.inspectorContent`), so the dataset's dimensions
/// and the product's units were never on screen together and the user had to
/// click a pane to change what the inspector described. UI2 has no pane focus
/// model: the dataset sections are always shown, and the product sections
/// join them whenever a product is displayed.
struct UI2Inspector: View {
    /// Persisted so the column comes back on the tab the user left it on.
    private enum InspectorTab: String {
        case settings, info
    }

    @AppStorage("ui2.inspectorTab") private var tab: InspectorTab = .settings

    var body: some View {
        TabView(selection: $tab) {
            UI2InspectorSettingsTab()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(InspectorTab.settings)
            UI2InspectorInfoTab()
                .tabItem { Label("Info", systemImage: "info.circle") }
                .tag(InspectorTab.info)
        }
    }
}

// MARK: - Settings tab

/// Readiness first, then the selected workspace's own controls.
private struct UI2InspectorSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.hasDataset {
            Form {
                UI2RequirementsSection()
                UI2GuidanceSection()
                workspaceSettings
            }
            .formStyle(.grouped)
            // The grouped Form draws no ground over the column's material.
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No dataset loaded",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Open a 4D-STEM dataset; the controls for each step appear here.")
            )
        }
    }

    /// Each of these produces bare `Section`s of its own.
    @ViewBuilder
    private var workspaceSettings: some View {
        switch appState.navigation.workspaceArea {
        case .prepare: UI2PrepareSettings()
        case .image: UI2ImagingSettings()
        case .map: UI2MapSettings()
        case .reconstruct: UI2PhaseSettings()
        case .results: UI2ResultsSettings()
        }
    }
}

/// **Ownership.** Readiness lives here and only here — the rows come from
/// `ProductWorkflow.prerequisiteItems(for:)` by way of
/// `AppState.ui2UnmetRequirements`, which is the same list that disables the
/// primary action, so the checklist can never disagree with the gate.
private struct UI2RequirementsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let unmet = appState.ui2UnmetRequirements
        if !unmet.isEmpty {
            Section("Requirements") {
                ForEach(unmet) { item in
                    LabeledContent {
                        action(for: item)
                    } label: {
                        Label(item.title, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        // A `taskPanel` resolution is a pointer, not a
                        // destination: it names the control in this task's own
                        // settings. As the second element of a Form's label it
                        // stacks under the title and wraps.
                        if case .taskPanel(let hint) = item.resolution {
                            Text(hint)
                                .accessibilityIdentifier("workspace.prerequisite.\(item.id).hint")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspace.prerequisite.\(item.id)")
                }
            }
            .accessibilityIdentifier("workspace.prerequisites")
        }
    }

    @ViewBuilder
    private func action(for item: TaskPrerequisite) -> some View {
        switch item.resolution {
        case .prepare:
            Button("Open Prepare") { appState.selectWorkspace(.prepare) }
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).action")
        case .task(let mode):
            Button("Open \(mode.productTitle)") { appState.changeMode(mode) }
                .accessibilityIdentifier("workspace.prerequisite.\(item.id).action")
        case .taskPanel:
            EmptyView()
        }
    }
}

/// Non-blocking scientific context: the task may run, and this is what its
/// numbers will and will not mean. Shown only once every requirement is met —
/// while something is missing, the missing thing is the message.
private struct UI2GuidanceSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let guidance = appState.ui2Guidance
        if appState.ui2UnmetRequirements.isEmpty, !guidance.isEmpty {
            Section("Interpretation") {
                Label("Ready · limited interpretation", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                ForEach(guidance, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Improve in Prepare") { appState.selectWorkspace(.prepare) }
                    .accessibilityIdentifier("workspace.guidance.improve")
            }
            .accessibilityIdentifier("workspace.guidance")
        }
    }
}

// MARK: - Info tab

/// What the dataset and the displayed product actually are.
private struct UI2InspectorInfoTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let descriptor = appState.descriptor {
            Form {
                UI2DatasetInfoSections(descriptor: descriptor)
                UI2ProductInfoSections()
                UI2SessionProductsSections()
                UI2InspectorDiagnosticsSections()
            }
            .formStyle(.grouped)
            // The grouped Form draws no ground over the column's material.
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No dataset loaded",
                systemImage: "square.stack.3d.up.slash"
            )
        }
    }
}

// MARK: Info — the dataset

private struct UI2DatasetInfoSections: View {
    @Environment(AppState.self) private var appState
    let descriptor: DatasetDescriptor

    var body: some View {
        datasetSection
        dimensionsSection
        previewSection
        loadedViewSection
        currentScanPositionSection
        apertureSection
        realSpaceHistogramSection
        diffractionHistogramSection
    }

    @ViewBuilder
    private var datasetSection: some View {
        Section("Dataset") {
            ui2InspectorRow("File", descriptor.fileName)
            ui2InspectorRow("Path", descriptor.datasetPath, mono: true)
            ui2InspectorRow("Shape", descriptor.shapeString, mono: true)
            ui2InspectorRow("dtype", descriptor.dtypeDescription, mono: true)
            ui2InspectorRow(
                "Chunks",
                descriptor.chunkShape.map { $0.map(String.init).joined(separator: " x ") } ?? "contiguous",
                mono: true
            )
            ui2InspectorRow("Size (f32)", ui2ByteString(descriptor.byteCountAsFloat32))
        }
    }

    @ViewBuilder
    private var dimensionsSection: some View {
        Section("Dimensions") {
            ui2InspectorRow("Scan (Ry x Rx)", "\(descriptor.ry) x \(descriptor.rx)")
            ui2InspectorRow("Detector (Qy x Qx)", "\(descriptor.qy) x \(descriptor.qx)")
            if let acceleratingVoltage = appState.calibrationSession.acceleratingVoltage {
                ui2InspectorRow("Accel. voltage", String(format: "%.0f kV", acceleratingVoltage))
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = appState.datasetPreview {
            Section("Preview") {
                // INVARIANT I4: a sampled preview is not a result. The
                // summary states the stride and is drawn FIRST, above the
                // images, so nothing here can be read as a virtual image.
                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("preview.summary")
                previewImage(
                    "Real space", pixels: preview.realSpace.normalized(),
                    width: preview.realSpace.width,
                    height: preview.realSpace.height, colormap: .gray
                )
                previewImage(
                    "Mean pattern", pixels: preview.meanDP.normalized(useLog: true),
                    width: preview.meanDP.qx, height: preview.meanDP.qy,
                    colormap: .viridis
                )
                previewImage(
                    "Max pattern", pixels: preview.maxDP.normalized(useLog: true),
                    width: preview.maxDP.qx, height: preview.maxDP.qy,
                    colormap: .viridis
                )
                if preview.isSampled {
                    Text("Not a result — cannot be exported or saved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// WHAT IS ACTUALLY LOADED, and what that cost the calibration: a cropped
    /// or binned cube is a DIFFERENT MEASUREMENT. Absent at full extent,
    /// deliberately — the section's presence is itself the signal that
    /// something was reduced.
    @ViewBuilder
    private var loadedViewSection: some View {
        if !appState.loadedView.isFullExtent {
            Section("Loaded view") {
                if let summary = appState.loadedView.summary {
                    Text(summary)
                        .accessibilityIdentifier("inspector.loadedViewSummary")
                }
                if let notice = appState.loadedView.binningNotice {
                    // The intensity consequence, said plainly: binning SUMS,
                    // so every absolute-intensity threshold moves with the
                    // factor.
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.binningNotice")
                }
                ui2InspectorRow("Source shape", appState.loadedView.sourceShapeString, mono: true)
                ui2InspectorRow("Loaded shape", descriptor.shapeString, mono: true)
                ui2InspectorRow("Size (f32)", ui2ByteString(descriptor.byteCountAsFloat32))

                // THE PROMOTE CONTROL. It lives in this section because the
                // section exists exactly when promotion is meaningful: a
                // reduced view is loaded. Promotion reopens the SOURCE at full
                // extent — never re-derives from reduced data — so the cost
                // stated is the whole cube's.
                Button("Reopen at Full Extent") {
                    Task { await appState.promoteAndReplayRecipe() }
                }
                .disabled(appState.isLoadingDataset
                          || appState.replayRun.isRunning)
                .accessibilityIdentifier("inspector.promoteToFullExtent")
                if let source = appState.loadView?.source {
                    // SystemMonitor.byteString, deliberately: the configurator
                    // prices this same quantity through it, and the two
                    // surfaces a user compares when deciding to promote must
                    // not render the same cube with different precision.
                    Text("Reloads the whole cube — "
                         + SystemMonitor.byteString(source.byteCountAsFloat32)
                         + " as float32. Analyses re-run against the full dataset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UI2PromoteRunCaption(
                    record: appState.replay.record,
                    frame: appState.replay.parameterFrame
                )
            }
        }
    }

    @ViewBuilder
    private var currentScanPositionSection: some View {
        Section("Current scan position") {
            ui2InspectorRow("x (Rx)", "\(appState.selectedScan.x)")
            ui2InspectorRow("y (Ry)", "\(appState.selectedScan.y)")
            if let (lowerBound, upperBound) = appState.patternMinMax {
                ui2InspectorRow("Pattern min", String(format: "%.3g", lowerBound))
                ui2InspectorRow("Pattern max", String(format: "%.3g", upperBound))
            }
        }
    }

    @ViewBuilder
    private var apertureSection: some View {
        Section("Aperture (detector px)") {
            ui2InspectorRow("Center x", String(format: "%.1f", appState.aperture.centerX))
            ui2InspectorRow("Center y", String(format: "%.1f", appState.aperture.centerY))
            ui2InspectorRow("Inner r", String(format: "%.1f", appState.aperture.inner))
            ui2InspectorRow("Outer r", String(format: "%.1f", appState.aperture.outer))
        }
    }

    @ViewBuilder
    private var realSpaceHistogramSection: some View {
        if let image = appState.resultImage {
            Section("Histogram (real space)") {
                UI2Histogram(pixels: image.pixels, version: appState.resultVersion,
                             rangeLo: Bindable(appState).displayRangeLo,
                             rangeHi: Bindable(appState).displayRangeHi)
                Text("Drag the handles to clip which intensities map into the image.")
                    .font(.caption2).foregroundStyle(.tertiary)
                gammaControl("Gamma", value: Bindable(appState).resultGamma)
            }
        }
    }

    @ViewBuilder
    private var diffractionHistogramSection: some View {
        if let pattern = appState.displayedPattern {
            Section("Histogram (diffraction)") {
                UI2Histogram(
                    pixels: pattern.contrastPixels(useLog: appState.logScale),
                    version: appState.patternVersion,
                    rangeLo: Bindable(appState).patternDisplayRangeLo,
                    rangeHi: Bindable(appState).patternDisplayRangeHi
                )
                Text(appState.logScale
                     ? "Contrast is selected on the log10(1 + intensity) axis."
                     : "Drag the handles to set the CBED intensity window.")
                    .font(.caption2).foregroundStyle(.tertiary)
                gammaControl("Gamma", value: Bindable(appState).patternGamma)
            }
        }
    }

    /// A labelled `Slider` row: as a `LabeledContent` value a slider collapses
    /// to its knob at the column's minimum (measured 2026-09-03).
    private func gammaControl(_ label: String, value: Binding<Float>) -> some View {
        Slider(value: value, in: 0.2...3) {
            Text("\(label), \(String(format: "%.2f", value.wrappedValue))")
        }
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.2f", value.wrappedValue))
    }

    /// One preview thumbnail. LETTERBOXED: `UI2MetalImage` maps the image to
    /// normalized view UVs, so a height-only frame stretches it to the
    /// column's full width — a 128x128 mean pattern drawn 2.5x wider than
    /// tall renders every Bragg disk as a horizontal ellipse, in the app that
    /// has an ellipse-calibration feature for measuring exactly that.
    @ViewBuilder
    private func previewImage(
        _ label: String, pixels: [Float], width: Int, height: Int,
        colormap: ColormapKind
    ) -> some View {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        UI2MetalImage(
            pixels: pixels, width: width, height: height,
            // `datasetPreview` is written exactly once per open, so the
            // dataset epoch IS this image's version — it changes precisely
            // when the preview does, including a same-shape swap, and it is
            // O(1) in a body that re-evaluates on every AppState change.
            contentVersion: appState.datasetEpoch,
            colormap: colormap
        )
        .aspectRatio(
            CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit
        )
        .ui2Thumbnail()
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityIdentifier("preview.\(label.replacingOccurrences(of: " ", with: ""))")
    }
}

// MARK: Info — the displayed product

/// What the displayed product IS — units, frame, sampling, validity, quality
/// fields, overlays, provenance. Present whenever a product is displayed;
/// there is no focus pane to choose it.
private struct UI2ProductInfoSections: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let product = appState.displayedProduct {
            Section("Product") {
                ui2InspectorRow("Name", product.displayName)
                ui2InspectorRow("Kind", product.kind.replacingOccurrences(of: "_", with: " "))
                ui2InspectorRow("Origin", product.origin == .computed
                                ? "Computed this session" : "Restored from the session sidecar")
                ui2InspectorRow("Size", "\(product.width) × \(product.height) px", mono: true)
                ui2InspectorRow("Frame", Self.frameLabel(product.domain))
                ui2InspectorRow("Values", product.valueUnits)
                ui2InspectorRow("Status", Self.statusLabel(product.quantitativeStatus))
                // One wording authority for sampling, shared with the
                // saved-result rows: a product's pixel size reads the same
                // everywhere it appears.
                ui2InspectorRow(
                    "Sampling",
                    SessionResultPresentation.sampling(
                        row: product.sampling.row, column: product.sampling.column,
                        units: product.sampling.units
                    ) ?? "not calibrated",
                    mono: true
                )
                ui2InspectorRow("Valid", Self.validityLabel(product))
            }
            .accessibilityIdentifier("inspector.product")

            if !product.qualityFields.isEmpty {
                Section("Quality fields") {
                    ForEach(product.qualityFields, id: \.name) { field in
                        ui2InspectorRow(field.name, field.units, mono: true)
                    }
                }
            }

            if !product.overlays.isEmpty {
                Section("Overlays") {
                    ForEach(product.overlays, id: \.kind) { overlay in
                        ui2InspectorRow(
                            overlay.kind.replacingOccurrences(of: "_", with: " "),
                            overlay.provenance
                        )
                    }
                }
            }

            Section("Provenance") {
                ForEach(product.provenance.keys.sorted(), id: \.self) { key in
                    ui2InspectorRow(key, product.provenance[key] ?? "", mono: true)
                }
            }
        }
    }

    static func frameLabel(_ domain: ProductDomain) -> String {
        switch domain {
        case .scan: "Scan (real space)"
        case .detector: "Detector (diffraction)"
        case .reconstruction: "Reconstruction"
        }
    }

    static func statusLabel(_ status: ProductQuantitativeStatus) -> String {
        switch status {
        case .quantitative: "Quantitative"
        case .relative: "Relative units"
        case .exploratory: "Exploratory"
        case .categorical: "Categorical"
        }
    }

    /// "N of M positions" — the validity mask is the product's own statement
    /// of where it has a value; an all-valid product says so in one word.
    static func validityLabel(_ product: DisplayedProduct) -> String {
        let total = product.validityMask.count
        let valid = product.validityMask.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard total > 0 else { return "no positions" }
        if valid == total { return "all \(total) positions" }
        return String(format: "%d of %d positions (%.0f%%)", valid, total,
                      Double(valid) / Double(total) * 100)
    }
}

// MARK: Info — products computed and saved

/// The in-memory products and the objects discovered in the stable companion
/// sidecar.
private struct UI2SessionProductsSections: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Computed this session") {
            product("Origin calibration", done: appState.calibrationSession.calibration.hasFittedOrigin)
            product("R–Q rotation", done: appState.calibrationSession.calibration.hasRotation)
            product(
                "Bragg disks",
                done: appState.hasCurrentBraggVectors,
                detail: appState.diskDetectionSettingsAreStale
                    ? "settings changed · rerun"
                    : appState.braggPeakCount.map { "\($0) peaks" }
            )
            // Clickable when retained: these are held in memory
            // simultaneously, so bringing one back needs no recompute.
            showableProduct(.strain, done: appState.strain.map != nil)
            showableProduct(.orientation, done: appState.acomSession.hasOrientationMap)
        }

        Section("Saved session sidecar") {
            if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
                // Through the seam: this site once derived the path itself, so
                // a bookmark resolving to a sidecar the user had RENAMED made
                // the inspector name a file the app was not reading.
                let sidecar = appState.sessionSidecar.location(for: descriptor)
                Label(sidecar.lastPathComponent, systemImage: "externaldrive")
                // Rename/relocate, offered where the user is already looking
                // at the filename — once a grant exists the save panel never
                // reappears on its own.
                Button("Ignore…") { appState.reopenIgnoringSessionSidecar() }
                    .help("Reopen this dataset without restoring the saved session; the sidecar file stays on disk")
                    .accessibilityIdentifier("products.reopenWithoutSession")
                Button("Change…") { appState.saveSessionSidecarAs() }
                    .disabled(appState.isBusy)
                    .help("Choose a new name or location for the session sidecar. Existing saved results are copied across.")
                    .accessibilityIdentifier("inspector.changeSidecar")
                if appState.sessionInventory.hasCalibration {
                    Label("Calibration", systemImage: "scope")
                }
                if appState.sessionInventory.hasBraggVectors {
                    Label("BraggVectors", systemImage: "circle.grid.cross")
                }
                ForEach(appState.sessionInventory.results) { result in
                    savedResultButton(
                        result, isCurrent: result.id == appState.sessionInventory.currentResultID
                    )
                    Button(role: .destructive) {
                        Task { await appState.removeSavedSessionResult(result) }
                    } label: {
                        Label("Remove \(result.displayName)", systemImage: "trash")
                    }
                    .disabled(appState.isBusy)
                    .help("Remove this saved result from the session sidecar")
                }
                if let controls = appState.selectedSavedControlRehydration {
                    Button {
                        appState.applySelectedSavedControls()
                    } label: {
                        Label("Apply Saved Controls", systemImage: "slider.horizontal.3")
                    }
                    .disabled(appState.isBusy)
                    .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
                }
            } else {
                Text("No companion results saved yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A computed product that can be put back in the viewer on click.
    @ViewBuilder
    private func showableProduct(
        _ kind: AppState.ComputedProduct, done: Bool
    ) -> some View {
        if done {
            Button {
                appState.showComputedProduct(kind)
            } label: {
                product(kind.displayName, done: true, detail: "show")
            }
            .buttonStyle(.plain)
            .help("Display this result again — it is still in memory, nothing is recomputed")
            .accessibilityIdentifier("computed.\(kind.rawValue)")
        } else {
            product(kind.displayName, done: false)
        }
    }

    private func product(_ name: String, done: Bool, detail: String? = nil) -> some View {
        LabeledContent {
            if let detail {
                Text(detail).fontDesign(.monospaced).foregroundStyle(.secondary)
            }
        } label: {
            Label(name, systemImage: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
    }

    /// A saved result as a row-as-button: the current one highlighted, its
    /// sampling as the row's trailing value.
    private func savedResultButton(_ result: SessionResultDescriptor, isCurrent: Bool) -> some View {
        Button {
            Task { await appState.selectSavedSessionResult(result) }
        } label: {
            LabeledContent {
                if let sampling = SessionResultPresentation.sampling(
                    row: result.pixelSizeRow, column: result.pixelSizeColumn,
                    units: result.pixelUnits
                ) {
                    Text(sampling).monospacedDigit().foregroundStyle(.secondary)
                }
            } label: {
                Label(result.displayName,
                      systemImage: isCurrent ? "eye.fill" : (result.storage == .rgba8 ? "paintpalette" : "map"))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text("\(result.width)×\(result.height) · \(result.storage == .rgba8 ? "RGBA8" : "float32") · \(result.valueUnits)")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                if let provenance = SessionResultPresentation.provenance(result.provenance) {
                    Text(provenance)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(result.kind) · \(result.id)")
    }
}

// MARK: Info — diagnostics

/// Promote run, calibration not carried into the view, the rotation curve,
/// performance, and the session-vs-view warnings.
private struct UI2InspectorDiagnosticsSections: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        promoteRunSection
        invalidatedCalibrationSection
        rotationDiagnosticsSection
        Section("Performance") {
            UI2PerformanceRows()
        }
        sessionProvenanceSection
        sidecarUnreadableSection
        sidecarDoesNotFitSection
    }

    /// Live progress while the recipe replays, and the morning summary
    /// afterwards. Outside the reduced-view condition on purpose: a finished
    /// promote IS full extent, and the summary is exactly what the user reads
    /// then.
    @ViewBuilder
    private var promoteRunSection: some View {
        if appState.replayRun.phase != .idle {
            Section("Promote run") {
                if let headline = appState.replayRun.summaryHeadline {
                    Text(headline)
                        .font(.callout.weight(.medium))
                        .accessibilityIdentifier("inspector.promoteRunHeadline")
                }
                if let halt = appState.replayRun.haltReason {
                    Text("Halted — \(halt)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("inspector.promoteRunHalt")
                }
                if let note = appState.replayRun.frameNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.promoteRunFrameNote")
                }
                ForEach(appState.replayRun.steps) { step in
                    LabeledContent("\(step.index + 1). \(step.title)") {
                        Text(Self.symbol(for: step.outcome))
                    }
                    if let detail = Self.detail(for: step.outcome) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Calibration values that could NOT be carried into this view. Shown
    /// separately from the loaded-view summary because these are refusals,
    /// not descriptions: something the file provided is now absent, and the
    /// reason is the actionable part.
    @ViewBuilder
    private var invalidatedCalibrationSection: some View {
        if !appState.loadedView.invalidatedCalibration.isEmpty {
            Section("Not carried into this view") {
                ForEach(appState.loadedView.invalidatedCalibration) { item in
                    Text(item.field.rawValue)
                        .font(.callout.weight(.medium))
                    Text(item.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("inspector.invalidatedCalibration")
        }
    }

    @ViewBuilder
    private var rotationDiagnosticsSection: some View {
        if let rotation = appState.lastRotationResult {
            Section("Rotation diagnostics") {
                UI2RotationCurve(result: rotation)
                Text("Mean |curl| vs angle — solid: as-is, dashed: transposed. The marker is the chosen minimum.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// PROVENANCE. A result restored from a session was computed under some
    /// view; if the app is now showing a different one, the numbers on screen
    /// and the numbers in the sidecar are about different data.
    @ViewBuilder
    private var sessionProvenanceSection: some View {
        if let recorded = appState.sessionLoadSpecification,
           recorded != appState.loadedView.specification {
            Section("Session provenance") {
                Text("The saved session was computed on a different view of this file.")
                    .font(.callout)
                ui2InspectorRow("Session view", recorded.provenanceSummary ?? "whole file")
                ui2InspectorRow("Loaded view",
                                appState.loadedView.specification.provenanceSummary ?? "whole file")
                Text("Restored results describe the session's view, not the one loaded now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The way OUT — a clean reopen with the session skipped. The
                // sidecar file is untouched.
                Button("Reopen Without This Session") {
                    appState.reopenIgnoringSessionSidecar()
                }
                .help("Reopens this dataset without restoring the saved session. "
                      + "The sidecar file stays on disk; results you save afterwards "
                      + "still go to the same sidecar.")
                .accessibilityIdentifier("inspector.reopenWithoutSession")
            }
            .accessibilityIdentifier("inspector.sessionProvenanceMismatch")
        }
    }

    /// A SIDECAR THAT IS THERE AND UNREADABLE. Distinct from the mismatch
    /// above, and it has to be: that one compares two KNOWN views, while this
    /// is the case where the recorded view is unknown because the file could
    /// not be opened. The dataset then loaded at full extent, which looks
    /// exactly like a dataset that never had a session.
    @ViewBuilder
    private var sidecarUnreadableSection: some View {
        if let reason = appState.sessionSidecar.unreadableReason {
            Section("Session sidecar") {
                Text("A saved session sits beside this dataset and could not be read.")
                    .font(.callout)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The whole file is loaded. If that session recorded a crop, what is on screen is a different extent from what it saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("inspector.sessionSidecarUnreadable")
        }
    }

    /// A RECORDED VIEW THIS FILE DOES NOT HAVE. The sibling failure — the
    /// sidecar was READ, and the region it records does not fit the file.
    /// While either failure stands, sidecar rewrites are refused.
    @ViewBuilder
    private var sidecarDoesNotFitSection: some View {
        if appState.sessionSidecar.unreadableReason == nil,
           let failure = appState.gates.sidecarRestoreFailure,
           failure.kind == .doesNotFit {
            Section("Session sidecar") {
                Text("The saved session beside this dataset describes a region this file does not have.")
                    .font(.callout)
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The whole file is loaded, and session saves are disabled so the sidecar's recorded view and results are not relabelled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("inspector.sessionSidecarDoesNotFit")
        }
    }

    // MARK: Promote run rendering

    private static func symbol(for outcome: ReplayRun.Outcome) -> String {
        switch outcome {
        case .notReached: "· not reached"
        case .running: "… running"
        case .succeeded: "✓"
        case .failed: "✕ failed"
        case .cancelled: "⊘ cancelled"
        case .refused: "— refused"
        }
    }

    private static func detail(for outcome: ReplayRun.Outcome) -> String? {
        switch outcome {
        case .notReached, .running, .cancelled:
            nil
        case .succeeded(let detail, let seconds):
            seconds >= 1
                ? "\(detail)  (\(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))))"
                : detail
        case .failed(let reason), .refused(let reason):
            reason
        }
    }
}

/// Live performance readout. The status strip is the single progress and
/// cancellation surface; the inspector only provides supporting metrics.
private struct UI2PerformanceRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        labeled("Status", appState.isBusy
                ? (appState.activeOperation ?? "Working…") : "Idle")

        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let metrics = appState.activeOperationMetrics(at: context.date) {
                labeled("Elapsed", duration(metrics.elapsed))
                if let rate = metrics.unitsPerSecond {
                    labeled("Throughput", String(format: "%.1f %@", rate, throughputUnit))
                }
                if let eta = metrics.eta {
                    labeled("ETA", duration(eta))
                }
            }
            labeled("App memory", String(format: "%.0f MB", SystemMonitor.residentMemoryMB()))
        }
        if let descriptor = appState.descriptor {
            labeled("Full cube (f32)", SystemMonitor.byteString(descriptor.byteCountAsFloat32))
            // Which path the analyses are actually taking. Resident and
            // streaming produce identical numbers, so nothing else on screen
            // would tell the user which one they are on.
            labeled("Cube memory", appState.residency.summary)
            if appState.residency.isResident {
                Button("Release cube") {
                    Task { await appState.releaseResidentCube() }
                }
                .accessibilityIdentifier("performance.releaseCube")
            }
        }
        labeled("GPU", SystemMonitor.gpuName)
        // The configurator's row carries this name too; the two surfaces a
        // user compares must use one name.
        labeled("GPU working-set limit", String(format: "%.0f MB", SystemMonitor.gpuWorkingSetMB))
    }

    private var throughputUnit: String {
        appState.activeOperation == "Virtual detector" ? "patterns/s" : "positions/s"
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            // Monospaced digits: these values refresh continuously, and
            // proportional digits make the whole column jitter.
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }
}

// MARK: - Supporting views

/// The promote button's replay price tag. Its own view so the plan is
/// re-derived only when the recipe or its frame changes, and so the caption
/// and the executor read the SAME pure plan: a promise the run is already
/// known to break is stated as the halt it will be, before the click.
private struct UI2PromoteRunCaption: View {
    let record: SessionReplayRecord
    let frame: ReplayParameterFrame?

    var body: some View {
        if !record.steps.isEmpty {
            let planned = ReplayPlanner.plan(record, frame: frame ?? .unknown)
            let titles = planned.map(\.title).joined(separator: ", ")
            let count = planned.count
            // The keep-awake honesty limit is stated where the decision is
            // made: an idle-sleep assertion does not survive a closed lid.
            Text("Then replays this session's \(count) recorded "
                 + (count == 1 ? "analysis" : "analyses")
                 + " in order (\(titles)), keeping this Mac awake while it "
                 + "runs (lid open). A step that fails halts the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector.promoteReplayCaption")
            // A re-referenced replay is never a silent substitution: the
            // numbers the entry points will receive are exact re-expressions
            // of the rehearsal's, and the caption says so BEFORE the click —
            // shown only when a step actually carries detector numbers, so a
            // DPC-only recipe does not claim a mapping it never uses.
            if let note = frame?.reReferenceDescription,
               planned.contains(where: {
                   if case .success(let plan) = $0.result {
                       plan.usesDetectorFrameParameters
                   } else { false }
               }) {
                Text("Recipe \(note) — the exact inverse of the load-time re-reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("inspector.promoteReplayReReference")
            }
            if let firstRefused = planned.firstIndex(where: {
                if case .failure = $0.result { true } else { false }
            }), case .failure(let refusal) = planned[firstRefused].result {
                Text(firstRefused == 0
                     ? "This recipe cannot replay here — \(planned[0].title): \(refusal.reason). The button reopens at full extent and re-runs the current analysis instead."
                     : "The run will halt at step \(firstRefused + 1) (\(planned[firstRefused].title)): \(refusal.reason)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("inspector.promoteReplayRefusal")
            }
        }
    }
}

/// Line plot of the rotation-calibration objective curves — a flat or
/// multi-minimum curve is an untrustworthy calibration, and this is where it
/// becomes visible. Scientific drawing, so it sets its own height.
private struct UI2RotationCurve: View {
    let result: RotationCalibration.Result

    var body: some View {
        Canvas { context, size in
            let all = result.objectiveCurve + result.objectiveCurveTransposed
            guard let lo = all.min(), let hi = all.max(), hi > lo,
                  result.anglesDeg.count > 1 else { return }
            let n = result.anglesDeg.count

            func path(_ curve: [Float]) -> Path {
                Path { p in
                    for i in 0..<n {
                        let x = CGFloat(i) / CGFloat(n - 1) * size.width
                        let y = size.height * (1 - CGFloat((curve[i] - lo) / (hi - lo)))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y))
                               : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            context.stroke(path(result.objectiveCurve),
                           with: .color(.accentColor), lineWidth: 1.2)
            context.stroke(path(result.objectiveCurveTransposed),
                           with: .color(.secondary),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            // Marker at the chosen angle.
            let chosenDeg = result.rotationRad * 180 / .pi
            if let first = result.anglesDeg.first, let last = result.anglesDeg.last, last > first {
                let fx = CGFloat((chosenDeg - first) / (last - first)) * size.width
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: fx, y: 0))
                        p.addLine(to: CGPoint(x: fx, y: size.height))
                    },
                    with: .color(.red), lineWidth: 1)
            }
        }
        .frame(height: UI2Metrics.diagnosticPlotHeight)   // science: the rotation curve
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotation calibration objective")
        .accessibilityValue(String(
            format: "chosen angle %.2f degrees, %@ detector axes",
            result.rotationRad * 180 / .pi,
            result.transpose ? "transposed" : "untransposed"
        ))
    }
}

// MARK: - Shared rows

/// One label/value row. Every descriptive line in the Info tab is one of
/// these, so a value the user needs to paste into a lab notebook is always
/// selectable and a path or a shape is always monospaced.
private func ui2InspectorRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
    LabeledContent(label) {
        Text(value)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fontDesign(mono ? .monospaced : .default)
            .textSelection(.enabled)
    }
}

/// The dataset inspector's own byte formatter — MB below a gigabyte, GB above.
/// Deliberately NOT `SystemMonitor.byteString`: the rows that price the whole
/// cube for a promote decision use that one, and the two must not be swapped.
private func ui2ByteString(_ bytes: Int) -> String {
    let megabytes = Double(bytes) / 1_048_576
    if megabytes >= 1024 {
        return String(format: "%.2f GB", megabytes / 1024)
    }
    return String(format: "%.1f MB", megabytes)
}
