//
//  PhaseMappingSettings.swift
//  Role: Crystal Maps' third task (ADR 046) — vector-matched phase mapping.
//        The phase list, the two settings groups, the run, and the evidence
//        for the selected position.
//
//  Two things here are deliberate and are the difference between a phase map
//  a user can defend and a picture:
//
//  • THE PHASE LIST IS THE LEGEND. One row per phase, carrying the swatch the
//    map is drawn with and the fraction of the scan it claimed. There is no
//    second legend to fall out of step with the first, and the row a user
//    edits is the row they read the answer off.
//  • EVERY POSITION CAN BE TAKEN APART. `Evidence` names the phase, how many
//    of the surviving vectors it explained, the mean distance in Å⁻¹, how many
//    the matrix took, and what came second. That line is the whole argument
//    for the colour at the selected position, in physical units.
//
//  And one refusal: the result is badged UNVALIDATED until step 3 of
//  `docs/v3-features.md#vector-matching` runs. The badge is not decoration — this
//  method has never been scored against an external truth in this app.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif
import simd

struct PhaseMappingSections: View {
    @Environment(AppState.self) private var appState
    @State private var showCIFImporter = false
    /// What the CIF importer is for: one phase, or the Al–Mg–Si preset's β″.
    @State private var importsAlMgSiPreset = false
    @State private var showMaterialsProjectSheet = false
    @SceneStorage private var showsAdvanced: Bool

    /// `advancedExpanded` is only the first-launch value of the remembered
    /// disclosure; a test hosts the view with it open to measure its rows.
    init(advancedExpanded: Bool = false) {
        _showsAdvanced = SceneStorage(wrappedValue: advancedExpanded,
                                      "aiAnalysis.phaseMapping.advanced.isExpanded")
    }

    /// Same reasoning as ACOM's importer: nothing on a stock macOS declares
    /// `.cif`, so this resolves to the same dynamic type a `.cif` on disk gets.
    private var cifTypes: [UTType] { [UTType(filenameExtension: "cif") ?? .data] }

    var body: some View {
        @Bindable var product = appState.phaseMapping

        // This room speaks the inspector's shared vocabulary
        // (`InspectorRows.swift`): collapsible `InspectorSection`s with a
        // hairline divider and a consistent label column, not a nested
        // `Form` with its own headers and dividers. The outer inspector
        // (`WorkspaceInspector.swift`) supplies the scroll container.
        InspectorSection("Phases") {
            // An empty list is named once, by the Requirements section (the
            // phases are a prerequisite since 2026-09-30), not again here.
            ForEach(Array(product.phases.enumerated()), id: \.element.id) { index, slot in
                PhaseRow(index: index, slot: slot)
            }
            if product.phases.count > 1 {
                InspectorRow("Matrix") {
                    Picker("Matrix", selection: matrixSelection) {
                        // Two slots of one structure (the preset's two β″)
                        // read identically by name; the zone axis tells them apart.
                        let labels = PhaseMappingSlot.pickerLabels(product.phases)
                        ForEach(Array(product.phases.enumerated()), id: \.element.id) { index, slot in
                            Text(labels[index]).tag(slot.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("phaseMapping.matrix")
                }
                .help("The matrix is stated, not found: its reflections are removed "
                      + "from every pattern and it is the answer where too little is left.")

                // Which AXIS it is viewed down is not stated — it is measured.
                // A matrix viewed down an axis it is not on presents no
                // reflections to remove, so nothing is removed and every
                // position comes back "not indexed", which looks exactly like
                // a method that does not work.
                InspectorActionRow {
                    InspectorAdaptiveButton("Find Matrix Zone Axis", systemImage: "scope",
                                             help: "Symmetry-equivalent axes should tie exactly. They are shown "
                                                 + "so a fit can be told from a coin toss.") {
                        PendingEdits.run { await appState.findMatrixZoneAxis() }
                    }
                    // No physical Q scale, no fit: every axis would read "at
                    // chance" (drive 2026-09-24); the run section says why.
                    .disabled(appState.isBusy || appState.resultPresentation.braggVectors == nil
                              || appState.phaseMappingQScaleRefusal != nil)
                    .accessibilityIdentifier("phaseMapping.findZoneAxis")
                }

                // A percentage alone cannot be read: at a tight tolerance an
                // axis explains a few percent of ANY vectors, indistinguishable
                // on screen from a real fit (⟨112⟩ at 8 %, measured 2026-09-14).
                // Each row says whether it beats chance by the matcher's own
                // multiple AND whether it explains more than a wrong axis does
                // on this data (the sweep's median, Gate D 2026-09-15) — the
                // second is what marks the ⟨112⟩, which shares reflections
                // with the true axis.
                // A ranking from another Q scale, origin or ellipse is not
                // offered: only a new fit answers for the live calibration.
                let staleRanking = appState.zoneAxisStaleness
                if let staleRanking {
                    InspectorWarning(staleRanking, systemImage: "clock.arrow.circlepath")
                        .accessibilityIdentifier("phaseMapping.zoneAxisStale")
                }
                ForEach(staleRanking == nil ? Array(product.zoneAxisFits.enumerated()) : [],
                        id: \.offset) { rank, fit in
                    let aboveChance = fit.isAboveChance(
                        multiple: appState.phaseMapping.matching.chanceMatchMultiple)
                    InspectorRow("[\(fit.zoneAxis.x) \(fit.zoneAxis.y) \(fit.zoneAxis.z)]", emphasized: rank == 0) {
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f %% · %.4f Å⁻¹",
                                        100 * fit.explainedFraction, fit.meanDistance))
                                .monospacedDigit()
                                .foregroundStyle(rank == 0 ? .primary : .secondary)
                            if !aboveChance {
                                Text("at chance").foregroundStyle(.orange)
                            } else if !fit.isAboveSweep {
                                Text("no better than a wrong axis").foregroundStyle(.orange)
                            }
                        }
                        .labelsHidden()
                    }
                }
                if staleRanking == nil, let top = product.zoneAxisFits.first,
                   !top.isAboveChance(
                       multiple: appState.phaseMapping.matching.chanceMatchMultiple) {
                    Text(String(format: "No axis beats chance here. A reference set "
                                + "this dense could match up to about %.1f %% of vectors "
                                + "pointing nowhere in particular, and the best axis "
                                + "explains %.1f %%. Treat the ranking as undecided.",
                                100 * top.chanceFraction, 100 * top.explainedFraction))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if staleRanking == nil, let top = product.zoneAxisFits.first, !top.isAboveSweep {
                    Text(String(format: "No axis stands out here. The best explains "
                                + "%.0f %% and the median axis %.0f %%; on a real crystal "
                                + "a wrong axis explains that much through shared "
                                + "reflections. Treat the ranking as undecided.",
                                100 * top.explainedFraction, 100 * top.sweepMedianFraction))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            InspectorActionRow {
                addPhaseMenu
            }
        }

        InspectorSection("Reference library") {
            InspectorRow("Orientations") {
                Text("\(product.projectedEntryCount)")
                    .monospacedDigit()
                    .foregroundStyle(product.projectedEntryCount > product.reference.maximumEntries
                                     ? .orange : .primary)
                    .labelsHidden()
            }
            parameterField("Max |q|", value: $product.reference.kMaxInvAngstrom,
                           units: "Å⁻¹", format: "%.2f")
            parameterField("In-plane step", value: $product.reference.inPlaneStepDeg,
                           units: "°", format: "%.1f")
            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                intField("Vectors per orientation",
                         value: $product.reference.maximumVectorsPerEntry,
                         help: "A library holding every allowed reflection matches "
                             + "anything. The cap is what keeps a match informative.")
                parameterField("Min. intensity",
                               value: $product.reference.minimumIntensityFraction,
                               units: "of max", format: "%.3f",
                               help: "Reflections weaker than this fraction of an orientation's "
                                   + "strongest are dropped. Only bites when it removes more than "
                                   + "the cap (vectors per orientation) already does.")
                parameterField("Excitation slab",
                               value: $product.reference.excitationSlabInvAngstrom,
                               units: "Å⁻¹", format: "%.3f")
            }
        }

        InspectorSection("Matching") {
            // Switching the rule resets the library's "Min. intensity" to
            // the rule's own default (`PhaseMappingRuleDefaults`) — the user
            // can still edit it afterwards. A pure function, not a listener
            // on the settings struct, so the reset happens exactly once, at
            // the moment of the switch, and not on every unrelated edit.
            InspectorRow("Classifier") {
                Picker("Classifier", selection: $product.matching.classificationRule) {
                    ForEach(PhaseVectorSettings.ClassificationRule.allCases, id: \.self) { rule in
                        Text(classifierLabel(rule)).tag(rule)
                    }
                }
                .labelsHidden()
                .onChange(of: product.matching.classificationRule) { _, newRule in
                    product.reference.minimumIntensityFraction =
                        PhaseMappingRuleDefaults.minimumIntensityFraction(for: newRule)
                }
                .accessibilityIdentifier("phaseMapping.classifierPicker")
            }

            parameterField("Pair radius", value: $product.matching.pairRadiusInvAngstrom,
                           units: "Å⁻¹", format: "%.3f")
            parameterField("Matrix removal", value: $product.matching.matrixToleranceInvAngstrom,
                           units: "Å⁻¹", format: "%.3f")

            // `.knownVariants` (Thronsen et al.'s own rule) has no floors and
            // no "not indexed above" cliff — every survivor is scored and the
            // residual cutoff alone decides — so that row is replaced, not
            // merely supplemented, and the resolution-in-pixels block below
            // (which exists only to explain THOSE floors) does not apply
            // either.
            if product.matching.classificationRule == .knownVariants {
                parameterField("Residual cutoff",
                               value: $product.matching.residualCutoffInvAngstrom,
                               units: "Å⁻¹", format: "%.3f",
                               help: "Known variants: every surviving vector is "
                                   + "scored; no floors (Thronsen et al. 2024).")
                intField("Direct matrix, max",
                         value: $product.matching.directMatrixMaximumVectors,
                         help: "Direct matrix up to this many vectors: a position whose "
                             + "surviving vectors number at or below it is the matrix, by "
                             + "exclusion (Thronsen et al.'s direct_Al = 1).")
                intField("Specific reflections, min",
                         value: $product.matching.knownVariantsMinimumSpecificReflections,
                         help: "A winner that matches fewer reflections the matrix does not also "
                             + "have falls back to the matrix. 1 is shipped (measured on Thronsen "
                             + "et al.'s dataset A: fewer Al → precipitate false calls at the 0.1–0.2 % "
                             + "detection floors, a 5-position cost at 0.5 %); 0 turns it off.")
            } else {
                parameterField("Not indexed above",
                               value: $product.matching.notIndexedAboveInvAngstrom,
                               units: "Å⁻¹", format: "%.3f")
            }

            // The data's reach: a masked or cropped pattern ends before the
            // detector does, and its edge is a ring of maxima no phase
            // explains (Thronsen step 3). 0 = the detector.
            parameterField("Ignore peaks beyond",
                           value: $product.matching.maximumVectorInvAngstrom,
                           units: "Å⁻¹", format: "%.2f",
                           help: "0 = the detector's edge. A masked or cropped pattern ends "
                               + "before the detector does, and its edge is a ring of maxima "
                               + "no phase explains (Thronsen step 3).")

            // These are set in Å⁻¹ but met on a pixel grid, and the two can
            // silently disagree: at 0.44 of one detector pixel (measured),
            // matrix removal removes nothing and the map comes back empty.
            // Only meaningful for `.search`'s own floors and cliff — see the
            // footnote above.
            if product.matching.classificationRule == .search,
               let resolution = appState.phaseVectorResolution {
                InspectorRow("On this detector") {
                    Text(String(format: "%.2f · %.2f · %.2f px",
                                resolution.pairRadiusPixels,
                                resolution.matrixRemovalPixels,
                                resolution.notIndexedAbovePixels))
                        .monospacedDigit()
                        .foregroundStyle(resolution.advice == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .labelsHidden()
                }
                if let advice = resolution.advice {
                    InspectorWarning(advice, systemImage: "exclamationmark.triangle")
                    InspectorActionRow {
                        InspectorAdaptiveButton("Scale to This Detector", systemImage: "arrow.left.and.right") {
                            appState.scalePhaseMatchingToDetector()
                        }
                        .disabled(appState.isBusy)
                        .accessibilityIdentifier("phaseMapping.scaleToDetector")
                    }
                }
            }
        }

        // Untitled at HEAD, and left that way: a title here would invent a
        // name this run button never had, and "Run" now also collides with
        // the bottom pane's own Run tab (F6, `InspectorGroup` — no header,
        // not collapsible).
        InspectorGroup {
            // What blocks the run is named once, by the Requirements section
            // at the top of the inspector (Bragg vectors, Q scale, the phase
            // list — `ProductWorkflow.prerequisiteItems`), which also carries
            // the buttons that resolve it; repeating it here said it twice
            // (polish drive 2026-10-01). The button below is disabled by the
            // same conditions.
            InspectorActionRow {
                InspectorAdaptiveButton("Map Phases", systemImage: "square.grid.3x3.topleft.filled") {
                    PendingEdits.run { await appState.runPhaseMapping() }
                }
                // C4(a): the toolbar's own readiness (Bragg vectors current,
                // a physical Q scale), plus the phase list's own refusal.
                .disabled(product.runRefusal != nil || !ProductWorkflow.mayRun(
                    .phaseMapping, readiness: appState.productWorkflowReadiness,
                    isBusy: appState.isBusy))
                .accessibilityIdentifier("phaseMapping.run")
            }
        }

        if let map = product.map, let run = product.lastRun {
            resultSection(map: map, run: run, product: product)
            PrecipitateObjectsSection()
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(map: PhaseMap, run: PhaseMappingProduct.RunRecord,
                               product: PhaseMappingProduct) -> some View {
        InspectorSection("Result") {
            InspectorWarning("Unvalidated — this method has not been scored against an "
                  + "external ground truth in this app. Read the map; do not "
                  + "quote a phase fraction from it. Object counts and "
                  + "densities come from this unvalidated map.", systemImage: "exclamationmark.triangle")

            if product.isStale {
                InspectorWarning("From an earlier run — the phases or the settings have "
                      + "changed since. Map Phases again to update it.", systemImage: "clock.arrow.circlepath")
            }

            ForEach(Array(PhaseMapPresentation.legend(map).enumerated()), id: \.offset) { _, row in
                // The label is a phase's own name, so it truncates rather than
                // pushing the inspector's minimum width up (`InspectorDataRow`).
                InspectorDataRow(row.label) {
                    HStack(spacing: 6) {
                        swatch(row)
                        Text(String(format: "%.1f %%", 100 * row.fraction))
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
            }

            // How much of the matrix fraction above rests on a full
            // explanation. A matrix verdict is reached both when almost
            // nothing survived removal and when the matrix out-fitted every
            // candidate, and the fraction above says neither. Reported, NOT
            // thresholded: a 0.90 bar measured on one dataset marked 46 % of
            // another whose every acceptance clause passes (measured
            // 2026-09-16, see `open-items.md`), so the number is given and
            // the reader judges.
            if let explained = PhaseMapPresentation.medianMatrixExplainedFraction(map) {
                InspectorRow("Matrix evidence") {
                    Text(String(format: "%.0f %% of vectors, median", 100 * explained))
                        .monospacedDigit()
                        .labelsHidden()
                }
                .help("How much of each matrix position's detected signal the matrix "
                      + "itself accounts for. Near 100 % the matrix explains the pattern; "
                      + "well below it, the position is matrix because nothing else fitted, "
                      + "not because the matrix did. There is no threshold here — the "
                      + "number falls as detection admits more noise, so read it against "
                      + "this dataset's own settings.")
            }

            if let diagnosis = appState.phaseMappingDiagnosis {
                // A map that found nothing is a result about the SETTINGS, and
                // on screen it looks exactly like a result about the specimen.
                InspectorWarning(diagnosis, systemImage: "questionmark.circle")
            }

            if let evidence = appState.phaseMappingEvidenceLine {
                InspectorRow("Evidence") {
                    Text(evidence)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                }
                .help(PhaseMapPresentation.evidenceHelp)
            }

            InspectorActionRow {
                // Reads "Show Phase Map" while the distance is on screen — the
                // way back, without a second row.
                let control = PhaseResultPicture.control(
                    owning: .distance, displayedKind: appState.displayedProduct?.kind)
                InspectorAdaptiveButton(control.title, systemImage: control.systemImage) {
                    appState.showPhaseResult(control.target)
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("phaseMapping.showDistance")
            }

            InspectorValueRow("Chance match at max |q|",
                               String(format: "%.1f %%", run.worstChanceMatchPercent))
            InspectorValueRow("Orientations", "\(run.libraryEntryCount)")
            if run.matrixInPlaneDegrees.isFinite {
                InspectorValueRow("Matrix in-plane",
                                   String(format: "%.0f° (mod symmetry)",
                                          run.matrixInPlaneDegrees))
            }
            if !run.qScaleIsPhysical {
                Label("The Å⁻¹ scale is exploratory, not calibrated — every "
                      + "distance above is only as good as it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func swatch(_ row: PhaseMapPresentation.LegendRow) -> some View {
        LegendSwatch(color: row.color, stripe: row.stripe)
    }

    // MARK: Phase list

    private var matrixSelection: Binding<String> {
        Binding(
            get: { appState.phaseMapping.phases.first(where: \.isMatrix)?.id ?? "" },
            set: { newID in
                for index in appState.phaseMapping.phases.indices {
                    appState.phaseMapping.phases[index].isMatrix =
                        appState.phaseMapping.phases[index].id == newID
                }
            }
        )
    }

    /// Materials Project is the default phase source (owner decision); the
    /// built-in library is not offered here — see the doc comment on
    /// `CrystalModelLibrary.models`. The menu offers exactly the two sources
    /// plus this session's already-imported models (CIF or Materials Project).
    private static let alMgSiPresetHelp = """
        Replaces the phase list with Al (matrix, zone [0 0 1]) and your β″ (Mg5Si6) CIF twice, at zones \
        [0 1 0] (needles end-on) and [0 0 1] (in-plane), and selects the Known variants classifier. \
        "Parallel to matrix" stays empty and the tolerances stay as they are. Calibration (ellipse, Q, R) \
        is per dataset and is not set — calibrate from this scan's own lattice.
        """

    private var addPhaseMenu: some View {
        InspectorAdaptiveMenu("Add Phase", systemImage: "plus") {
            Button("Materials Project…") { showMaterialsProjectSheet = true }
            Button("From CIF file…") { importsAlMgSiPreset = false; showCIFImporter = true }
            Divider()
            Section("Presets") {
                Button("Al–Mg–Si (β″ needles)…") { importsAlMgSiPreset = true; showCIFImporter = true }
                    .help(Self.alMgSiPresetHelp)
            }
            if !appState.acomSession.importedCrystalModels.isEmpty {
                Divider()
                ForEach(appState.acomSession.importedCrystalModels) { model in
                    Button(importedCrystalModelLabel(model)) { add(model) }
                }
            }
        }
        .accessibilityIdentifier("phaseMapping.addPhase")
        .fileImporter(isPresented: $showCIFImporter,
                      allowedContentTypes: cifTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if importsAlMgSiPreset {
                    importsAlMgSiPreset = false
                    appState.applyAlMgSiPreset(precipitateCIF: url)
                    return
                }
                appState.importCrystalModel(from: url)
                // `importCrystalModel` appends to the shared imported-model
                // list, which ACOM owns; take the one it just selected so a
                // single import serves both rooms.
                if let model = appState.acomSession.importedCrystalModels.last {
                    add(model)
                }
            case .failure(let error):
                importsAlMgSiPreset = false
                appState.present(error)
            }
        }
        .sheet(isPresented: $showMaterialsProjectSheet) {
            // `addsToPhaseMapping: true` routes the sheet's Import button
            // through `AppState.addPhaseMappingSlot(_:)` — the same function
            // `add(_:)` below delegates to — so both paths share one rule.
            MaterialsProjectImportSheet(addsToPhaseMapping: true)
                .environment(appState)
        }
    }

    /// `AppState.addPhaseMappingSlot(_:)` (`App/AppState+MaterialsProject.swift`)
    /// is the same duplicate/matrix rule; this delegates rather than keeping
    /// a second copy, now that the Materials Project sheet needs the same
    /// logic from a view that doesn't have this one's local state.
    private func add(_ model: CrystalModel) {
        appState.addPhaseMappingSlot(model)
    }

    private struct PhaseRow: View {
        @Environment(AppState.self) private var appState
        let index: Int
        let slot: PhaseMappingSlot
        @State private var draft = ""
        @State private var orientationDraft = ""

        /// The matrix picker's own label (`pickerLabels`): a name another slot
        /// shares carries its zone axis, so no two rows read the same.
        private var rowName: String {
            let labels = PhaseMappingSlot.pickerLabels(appState.phaseMapping.phases)
            return labels.indices.contains(index) ? labels[index] : slot.model.displayName
        }

        var body: some View {
            @Bindable var product = appState.phaseMapping
            VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: LayoutPolicy.legendSwatch, height: LayoutPolicy.legendSwatch)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rowName)
                    Text(slot.isMatrix ? "matrix · zone \(slot.zoneAxisText)"
                                       : "zone \(slot.zoneAxisText)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    product.phases.removeAll { $0.id == slot.id }
                    // Removing the matrix must not leave the list without one.
                    if !product.phases.contains(where: \.isMatrix),
                       !product.phases.isEmpty {
                        product.phases[0].isMatrix = true
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove \(slot.model.displayName)")
                .accessibilityLabel("Remove \(slot.model.displayName)")
            }
            zoneAxisField
            if !draft.isEmpty, PhaseMappingSlot.parseZoneAxis(draft) == nil {
                Text("A zone axis is three integers, like 0 1 0.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if !slot.isMatrix {
                orientationRelationshipField
                excitationSlabField
                if !orientationDraft.isEmpty,
                   PhaseMappingSlot.parseOrientationRelationships(orientationDraft) == nil {
                    Text("A relationship is pairs like (002) ∥ (200); planes in "
                         + "parentheses, directions in square brackets.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            }
            .onAppear {
                if draft.isEmpty { draft = "\(slot.u) \(slot.v) \(slot.w)" }
                if orientationDraft.isEmpty {
                    orientationDraft = slot.orientationRelationshipText
                }
            }
            // The axis can change UNDER the field — Find Matrix Zone Axis writes
            // the fitted [u v w] into the slot — so a draft filled once on
            // appear can go stale and disagree with the row's own label.
            // Refresh only when the field's own text no longer means the
            // slot's axis, so "0-12" stays as typed.
            .onChange(of: slot.zoneAxis) { _, axis in
                if PhaseMappingSlot.parseZoneAxis(draft) != axis {
                    draft = "\(axis.x) \(axis.y) \(axis.z)"
                }
            }
            // Same reasoning as the zone axis: refresh only when the slot's
            // text no longer matches what the draft holds, so a keystroke
            // mid-typo is never clobbered by this view's own last write.
            .onChange(of: slot.orientationRelationshipText) { _, text in
                if orientationDraft != text { orientationDraft = text }
            }
        }

        private var color: Color {
            let matrixIndex = appState.phaseMapping.phases.firstIndex(where: \.isMatrix) ?? 0
            let rgb = PhaseMapPresentation.color(phaseIndex: index, matrixPhaseIndex: matrixIndex)
            return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255,
                         blue: Double(rgb.b) / 255)
        }

        /// One field for the whole zone axis rather than three integer boxes.
        /// Three boxes cannot fit an inspector column without a fixed width,
        /// and "0 1 0" is how a crystallographer writes it anyway. A string
        /// that does not parse leaves the last valid axis in place and says so
        /// on the row, rather than silently becoming [0 0 0].
        private var zoneAxisField: some View {
            @Bindable var product = appState.phaseMapping
            return InspectorRow("Zone axis") {
                TextField("u v w", text: Binding(
                    get: { draft },
                    set: { text in
                        draft = text
                        guard let parsed = PhaseMappingSlot.parseZoneAxis(text) else { return }
                        product.updatePhase(id: slot.id) {
                            $0.u = parsed.x; $0.v = parsed.y; $0.w = parsed.z
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            }
        }

        /// This phase's own excitation slab, or empty for the library's global
        /// value (Reference library › Advanced), which the empty field shows
        /// greyed. A thin plate's reflections stay excited much further from
        /// the Bragg condition than the matrix's — θ′ edge-on at 0.3 Å⁻¹ in the
        /// Thronsen recipe — so one global value cannot serve every phase.
        private var excitationSlabField: some View {
            @Bindable var product = appState.phaseMapping
            let global = product.reference.excitationSlabInvAngstrom
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3))
            return InspectorRow("Excitation slab") {
                HStack(spacing: 6) {
                    // By the slot's id, not `index`: `PendingEdits` keeps this closure
                    // as it was at the last keystroke, and by the time a toolbar
                    // verb flushes it an earlier phase may have been removed —
                    // the index would then name a different phase.
                    let slotID = slot.id
                    NumberEntryField(title: "Excitation slab", value: slot.excitationSlabInvAngstrom,
                                     format: format, prompt: DecimalEntryFormat(format).format(global),
                                     emptyClears: true) { value in
                        product.updatePhase(id: slotID) { $0.excitationSlabInvAngstrom = value }
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: LayoutPolicy.numericFieldWidth)
                    Text("Å⁻¹")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .accessibilityLabel("Excitation slab")
            }
            .help("How far from the Bragg condition this phase's reflections still "
                  + "count as excited. Empty = the library's global value, shown "
                  + "grey. Changing it marks the map as needing a re-run.")
        }

        /// The orientation relationship to the matrix, in the form a paper
        /// states it — pairs of parallel lattice vectors. Kept as free text
        /// like the zone axis field, and for the same reason: a malformed
        /// entry stays visible with its own caption rather than silently
        /// reverting, and the last valid parse (here, the empty list) is what
        /// the run actually uses.
        private var orientationRelationshipField: some View {
            @Bindable var product = appState.phaseMapping
            return InspectorRow("Parallel to matrix") {
                TextField("Any rotation", text: Binding(
                    get: { orientationDraft },
                    set: { text in
                        orientationDraft = text
                        product.updatePhase(id: slot.id) { $0.orientationRelationshipText = text }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            }
            .help("This phase's plane (hkl) or direction [uvw] that lies parallel "
                  + "to the matrix's, as an orientation relationship is written; "
                  + "list each variant, e.g. (002) ∥ (200), (002) ∥ (020). Empty = "
                  + "any in-plane rotation. Applied once the matrix orientation "
                  + "is fitted.")
        }
    }

    // MARK: Small controls

    /// `NumericField` is the one place a UI form control takes a width
    /// (`LayoutPolicy.swift`, presentation contract rule 4) — these wrap it so
    /// the panel spells no frame of its own.
    ///
    /// `help`, when given, is the row's own explanatory paragraph — an
    /// Xcode-style tooltip on the row it explains, rather than inline prose.
    /// The caller's printf precision (`"%.2f"` → 2 decimals) as the field's
    /// display format. It is the MINIMUM number of decimals, up to six: the
    /// field commits what it shows on focus loss, so a format that rounded
    /// below the stored value's own digits would silently round the stored
    /// parameter. (`1,600` in a German locale read as sixteen hundred; `1,60`
    /// and `2,0` do not.) Pure and `static` so the output is unit-tested.
    static func displayFormat(_ printf: String) -> FloatingPointFormatStyle<Double> {
        let digits = printf.split(separator: ".").last
            .flatMap { Int($0.prefix { $0.isNumber }) } ?? 3
        let minimum = min(max(digits, 0), 6)
        return .number.precision(.fractionLength(minimum...6))
    }

    @ViewBuilder
    private func parameterField(_ title: String, value: Binding<Double>,
                                units: String, format: String, help: String? = nil) -> some View {
        if let help {
            InspectorRow(title) {
                NumericField(title, value: value,
                             format: Self.displayFormat(format), unit: units)
                    .labelsHidden()
            }
            .help(help)
        } else {
            InspectorRow(title) {
                NumericField(title, value: value,
                             format: Self.displayFormat(format), unit: units)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func intField(_ title: String, value: Binding<Int>, help: String? = nil) -> some View {
        if let help {
            InspectorRow(title) {
                NumericField(title, value: value, format: .number)
                    .labelsHidden()
            }
            .help(help)
        } else {
            InspectorRow(title) {
                NumericField(title, value: value, format: .number)
                    .labelsHidden()
            }
        }
    }

    /// `PhaseVectorSettings.ClassificationRule`'s raw values are the Core
    /// enum's Swift case names (`search`, `knownVariants`); this is a
    /// presentation label only, kept here rather than on the Core type
    /// itself so a picker word choice never touches `Core/`.
    private func classifierLabel(_ rule: PhaseVectorSettings.ClassificationRule) -> String {
        switch rule {
        case .search: "Search"
        case .knownVariants: "Known variants"
        }
    }
}

/// One colour key square of a phase-map legend row, solid or striped exactly as
/// the map paints it. Shared by the inspector's result list and the map pane's
/// footer legend, so the two cannot drift apart.
struct LegendSwatch: View {
    let color: PhaseMapPresentation.RGB
    /// The second stripe tone; nil = solid.
    let stripe: PhaseMapPresentation.RGB?

    var body: some View {
        func tone(_ c: PhaseMapPresentation.RGB) -> Color {
            Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
        }
        let side = LayoutPolicy.legendSwatch
        let shape = RoundedRectangle(cornerRadius: 2)
        return Canvas { context, _ in
            guard let second = stripe else {
                context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)),
                             with: .color(tone(color)))
                return
            }
            // The map's stripe (`isFirstStripeTone`: first tone where
            // (x + y) % period < period / 2) at 1 pt per map pixel, so the
            // swatch shows exactly the two tones and the orientation the map
            // draws; a 12-pt swatch carries four periods.
            let period = CGFloat(PhaseMapPresentation.stripePeriod)
            context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)),
                         with: .color(tone(second)))
            var band = Path()
            var k: CGFloat = 0
            while k < 2 * side {
                band.move(to: CGPoint(x: k, y: 0))
                band.addLine(to: CGPoint(x: k + period / 2, y: 0))
                band.addLine(to: CGPoint(x: 0, y: k + period / 2))
                band.addLine(to: CGPoint(x: 0, y: k))
                band.closeSubpath()
                k += period
            }
            context.fill(band, with: .color(tone(color)))
        }
        .frame(width: side, height: side)
        .clipShape(shape)
    }
}
