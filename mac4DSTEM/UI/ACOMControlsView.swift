import SwiftUI
import DSTEMCore
import DSTEMSession
import UniformTypeIdentifiers

/// ACOM's complete user-facing contract. Keeping material, scale semantics,
/// work scope, and result diagnostics together prevents a physically labelled
/// output from being assembled out of unrelated controls elsewhere.
struct ACOMControlsView: View {
    @Environment(AppState.self) private var appState
    @State private var showCIFImporter = false

    /// Nothing on a stock macOS declares `.cif`, so this resolves to the
    /// dynamic type `dyn.ah62d4rv4ge80g4pg` — which is also what a `.cif` file
    /// on disk resolves to, so the picker matches it. The fallback must be
    /// `.data`, not `.plainText`: a `.cif` file does *not* conform to
    /// `public.plain-text` (verified — its dynamic type conforms to
    /// `public.data` only), so a `.plainText` fallback would grey out every
    /// CIF in the picker.
    private var cifTypes: [UTType] {
        [UTType(filenameExtension: "cif") ?? .data]
    }

    var body: some View {
        @Bindable var appState = appState
        Section("ACOM (orientation)") {
            Picker("Phase model", selection: $appState.acomModelSelection) {
                Text("Choose phase…").tag(CrystalModelSelection.none)
                ForEach(CrystalModelLibrary.models) { model in
                    Text(model.displayName).tag(CrystalModelSelection.library(model.id))
                }
                Text("Custom cubic…").tag(CrystalModelSelection.customCubic)
                if !appState.importedCrystalModels.isEmpty {
                    Divider()
                    ForEach(appState.importedCrystalModels) { model in
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
            .font(.caption)
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
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let model = appState.resolvedACOMModel {
                LabeledContent("Symmetry", value: model.symmetry.displayName)
                    .font(.caption)
                if model.source == .imported {
                    LabeledContent("Source", value: "Imported CIF")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Text("The phase model is selected explicitly; mac4DSTEM never infers it from the dataset name.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.acomModelSelection == .customCubic {
                customCrystalEditor(appState: appState)
            }

            Picker("Quality", selection: $appState.acomQuality) {
                ForEach(ACOMQualityPreset.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            Text(appState.acomQuality.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                // S22d: wrap, never truncate (see SidebarTextWidth.swift).
                .sidebarWrapped()

            scopeControls(appState: appState)

            LabeledContent("Work", value: appState.acomWorkSummary)
                .font(.caption)
                .accessibilityIdentifier("acom.work")
            LabeledContent("Expected", value: appState.acomEstimatedDurationText)
                .font(.caption)
                .accessibilityIdentifier("acom.expected")
            if let suggestion = appState.acomFullScanSuggestion {
                Button(suggestion) {
                    appState.acomScope = .fullScan
                }
                .font(.caption)
                .disabled(appState.isBusy)
                .accessibilityIdentifier("acom.suggestFullScan")
            }

            DisclosureGroup("Engine & Q scale") {
                engineControls(appState: appState)
                qScaleControls(appState: appState)
            }

            prerequisiteStatus
            resultControls(appState: appState)
        }
    }

    @ViewBuilder
    private func customCrystalEditor(appState: AppState) -> some View {
        @Bindable var appState = appState
        Picker("Element", selection: $appState.customZ) {
            ForEach(ScatteringFactors.supportedElements, id: \.self) { z in
                Text("\(ScatteringFactors.symbols[z] ?? "?")  (Z=\(z))").tag(z)
            }
        }
        Picker("Structure", selection: $appState.customStructure) {
            ForEach(Crystal.CubicStructure.allCases) { structure in
                Text(structure.rawValue).tag(structure)
            }
        }
        HStack {
            Text("a (Å)").font(.caption)
            TextField(
                "a", value: $appState.customLatticeA,
                format: .number.precision(.fractionLength(0...4))
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }
        Text("Custom models are single-element cubic cells. Compound or other point-group models require a complete validated phase definition.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func scopeControls(appState: AppState) -> some View {
        @Bindable var appState = appState
        Picker("Area", selection: $appState.acomScope) {
            ForEach(ACOMRunScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("acom.scope")

        if appState.acomScope == .selectedRegion, let descriptor = appState.descriptor {
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
                "Half-size  \(appState.acomRegionRadius) px",
                value: $appState.acomRegionRadius,
                in: 4...max(4, min(descriptor.rx, descriptor.ry) / 2)
            )
            Text("The orange square is matched at full spatial resolution.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if appState.acomScope == .preview {
            Text("Samples at most 32 × 32 positions, then expands coarse blocks for a rapid whole-field check.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func engineControls(appState: AppState) -> some View {
        @Bindable var appState = appState
        Picker("Engine", selection: $appState.acomBackend) {
            ForEach(ACOMMatchingBackend.allCases) { backend in
                Text(backend.rawValue).tag(backend)
            }
        }
        LabeledContent("Will use", value: appState.effectiveACOMBackend.rawValue)
            .font(.caption)
        if appState.acomBackend == .automatic {
            Text("Automatic currently uses the real-data-verified Accelerate CPU backend.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func qScaleControls(appState: AppState) -> some View {
        @Bindable var appState = appState
        let semantics = appState.acomScaleSemantics
        LabeledContent("Interpretation", value: appState.acomInterpretationLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(semantics.provenance.isPhysical ? Color.green : Color.orange)
        LabeledContent(
            "Q scale",
            value: String(format: "%.6g Å⁻¹/px", semantics.invAngstromPerPixel)
        )
        .font(.caption.monospacedDigit())
        LabeledContent("Provenance", value: semantics.provenance.displayName)
            .font(.caption)

        // Backlog #40. **Prepare owns Q calibration.** This panel used to render
        // its own "Calibrate Q from Selected Material" button beside the same
        // provenance rows the Prepare checklist shows, both calling
        // `calibrateQFromCrystal()`. Two owners for one decision invites the two
        // surfaces to disagree — and #2 deliberately shaped how that choice is
        // presented in Prepare (prominent button, an explicit manual
        // alternative, a reason when the crystal route is unavailable), none of
        // which applied to the copy here.
        //
        // What stays is the read-out — interpretation, Q scale, provenance —
        // because ACOM's results are labelled by it, plus a route to the owner.
        // The link is now unconditional: when the scale is *not* physical is
        // exactly when a user most needs to be told where to fix it.
        Button("Review Q Calibration in Prepare") {
            appState.selectWorkspace(.prepare)
        }
        .font(.caption)
        .accessibilityIdentifier("acom.reviewQCalibration")

        if !semantics.provenance.isPhysical {
            VStack(alignment: .leading, spacing: 3) {
                Text("Exploratory scale  \(appState.acomExploratoryScale, specifier: "%.4f") Å⁻¹/px")
                    .font(.caption)
                Slider(value: $appState.acomExploratoryScale, in: 0.001...0.05)
                Text("This can help inspect correlation, but it is not physical calibration and every result remains Exploratory.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        if appState.hasOrientationPlan, let plan = appState.orientationPlan {
            LabeledContent("Cached plan", value: "\(plan.count) templates")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var prerequisiteStatus: some View {
        if appState.diskDetectionSettingsAreStale {
            Text("Detection settings changed — rerun Detect All Disks before ACOM.")
                .font(.caption2).foregroundStyle(.orange)
        } else if appState.braggVectors == nil {
            Text("Detect Bragg disks first (Map → Bragg disks).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultControls(appState: AppState) -> some View {
        @Bindable var appState = appState
        if appState.hasOrientationMap {
            if let semantics = appState.acomLastRunSemantics {
                Label(
                    semantics.scale.provenance.isPhysical
                        ? "Physical ACOM result" : "Exploratory ACOM result",
                    systemImage: semantics.scale.provenance.isPhysical
                        ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    semantics.scale.provenance.isPhysical ? Color.green : Color.orange
                )
            }
            // Routed through `selectACOMDisplay` rather than bound directly, so
            // an explicit choice here is recorded and a later completed map
            // never silently promotes IPF·Z over it.
            Picker("Display", selection: Binding(
                get: { appState.acomDisplay },
                set: { appState.selectACOMDisplay($0) }
            )) {
                ForEach(ACOMDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            // "Display" alone collides with the sidebar section header of the
            // same name; the accessibility label disambiguates for VoiceOver
            // and label-based automation queries.
            .accessibilityLabel("ACOM display mode")
            .accessibilityIdentifier("acom.display")
            // Backlog #40. The IPF colour key is drawn over the image by
            // `StemImageView`, keyed on the *displayed* result actually being an
            // IPF-Z map. It used to be drawn here as well, keyed only on this
            // picker — so the two could be on screen together, and the sidebar
            // copy could describe a colouring no visible pixel was using. A
            // legend belongs with the pixels it decodes.
            if let text = appState.selectedEulerText {
                LabeledContent(
                    "\(appState.orientationMap?.symmetry.displayName ?? "Symmetry") FZ Euler",
                    value: text
                )
                .font(.caption.monospacedDigit())
            }
        }
    }
}
