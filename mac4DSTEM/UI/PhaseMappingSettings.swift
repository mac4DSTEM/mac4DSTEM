//
//  PhaseMappingSettings.swift
//  Role: the AI Analysis room's second task — vector-matched phase mapping.
//        The phase list, the two settings groups, the run, and the evidence
//        for the position under the cursor.
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
//    for the colour under the cursor, in physical units.
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
    @State private var showMaterialsProjectSheet = false
    @SceneStorage("ai.phaseMapping.advanced.isExpanded") private var showsAdvanced = false

    /// Same reasoning as ACOM's importer: nothing on a stock macOS declares
    /// `.cif`, so this resolves to the same dynamic type a `.cif` on disk gets.
    private var cifTypes: [UTType] { [UTType(filenameExtension: "cif") ?? .data] }

    var body: some View {
        @Bindable var product = appState.phaseMapping

        // The Xcode-inspector trial (owner, 2026-09-21) — a nested `Form`
        // styled `.columns`, bold `Text` headers, hand `Divider()`s — is
        // retired ("school project"). This room now speaks the inspector's
        // shared vocabulary (`InspectorRows.swift`): collapsible
        // `InspectorSection`s with a hairline divider and a consistent label
        // column. The outer inspector (`WorkspaceInspector.swift`) supplies
        // the scroll container.
        InspectorSection("Phases") {
            if product.phases.isEmpty {
                InspectorNote("Add the matrix phase and at least one precipitate phase.")
            }
            ForEach(Array(product.phases.enumerated()), id: \.element.id) { index, slot in
                PhaseRow(index: index, slot: slot)
            }
            if product.phases.count > 1 {
                InspectorRow("Matrix") {
                    Picker("Matrix", selection: matrixSelection) {
                        ForEach(product.phases) { slot in
                            Text(slot.model.displayName).tag(slot.id)
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
                // a method that does not work (the owner's run, 2026-09-12).
                InspectorActionRow {
                    Button {
                        Task { await appState.findMatrixZoneAxis() }
                    } label: {
                        Label("Find Matrix Zone Axis", systemImage: "scope")
                    }
                    .disabled(appState.isBusy || appState.resultPresentation.braggVectors == nil)
                    .accessibilityIdentifier("phaseMapping.findZoneAxis")
                    .help("Symmetry-equivalent axes should tie exactly. They are shown "
                          + "so a fit can be told from a coin toss.")
                }

                // A percentage alone cannot be read: at a tight tolerance an
                // axis explains a few percent of ANY vectors, and the panel
                // showed that the same way it shows a real fit (the owner's
                // ⟨112⟩ at 8 %, 2026-09-14). Each row says whether it beats
                // chance by the matcher's own multiple AND whether it explains
                // more than a wrong axis does on this data (the sweep's
                // median, Gate D 2026-09-15 night) — the second is what marks
                // the ⟨112⟩, which shares reflections with the true axis.
                ForEach(Array(product.zoneAxisFits.enumerated()), id: \.offset) { rank, fit in
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
                if let top = product.zoneAxisFits.first,
                   !top.isAboveChance(
                       multiple: appState.phaseMapping.matching.chanceMatchMultiple) {
                    Text(String(format: "No axis beats chance here. A reference set "
                                + "this dense could match up to about %.1f %% of vectors "
                                + "pointing nowhere in particular, and the best axis "
                                + "explains %.1f %%. Treat the ranking as undecided.",
                                100 * top.chanceFraction, 100 * top.explainedFraction))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let top = product.zoneAxisFits.first, !top.isAboveSweep {
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
                parameterField("Minimum intensity",
                               value: $product.reference.minimumIntensityFraction,
                               units: "of strongest", format: "%.3f",
                               help: "Only bites when it removes more than the cap "
                                   + "(vectors per orientation) already does.")
                parameterField("Excitation slab",
                               value: $product.reference.excitationSlabInvAngstrom,
                               units: "Å⁻¹", format: "%.3f")
            }
        }

        InspectorSection("Matching") {
            // Switching the rule resets the library's "Minimum intensity" to
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
                intField("Direct matrix up to (vectors)",
                         value: $product.matching.directMatrixMaximumVectors)
            } else {
                parameterField("Not indexed above",
                               value: $product.matching.notIndexedAboveInvAngstrom,
                               units: "Å⁻¹", format: "%.3f")
            }

            // The data's reach: a masked or cropped pattern ends before the
            // detector does, and its edge is a ring of maxima no phase
            // explains (Thronsen step 3, 2026-09-15). 0 = the detector.
            parameterField("Ignore peaks beyond",
                           value: $product.matching.maximumVectorInvAngstrom,
                           units: "Å⁻¹ (0 = detector)", format: "%.2f")

            // These are set in Å⁻¹ and met on a pixel grid, and until
            // 2026-09-12 nothing on screen joined the two. On the owner's own
            // cube the defaults are 0.44 of one detector pixel; matrix removal
            // removed nothing and the map came back empty. Only meaningful
            // for `.search`'s own floors and cliff — see the footnote above.
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
                    Label(advice, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    InspectorActionRow {
                        Button {
                            appState.scalePhaseMatchingToDetector()
                        } label: {
                            Label("Scale to This Detector", systemImage: "arrow.left.and.right")
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
            if let refusal = product.runRefusal {
                Label(refusal, systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if appState.resultPresentation.braggVectors == nil {
                Label("Detect Bragg disks first — this matches the peaks disk "
                      + "detection finds, it does not find its own.",
                      systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            InspectorActionRow {
                Button {
                    Task { await appState.runPhaseMapping() }
                } label: {
                    Label("Map Phases", systemImage: "square.grid.3x3.topleft.filled")
                }
                .disabled(appState.isBusy || product.runRefusal != nil
                          || appState.resultPresentation.braggVectors == nil)
                .accessibilityIdentifier("phaseMapping.run")
            }
        }

        if let map = product.map, let run = product.lastRun {
            resultSection(map: map, run: run, product: product)
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(map: PhaseMap, run: PhaseMappingProduct.RunRecord,
                               product: PhaseMappingProduct) -> some View {
        InspectorSection("Result") {
            Label("Unvalidated — this method has not been scored against an "
                  + "external ground truth in this app. Read the map; do not "
                  + "quote a phase fraction from it. Object counts and "
                  + "densities come from this unvalidated map.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            if product.isStale {
                Label("From an earlier run — the phases or the settings have "
                      + "changed since. Map Phases again to update it.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(Array(PhaseMapPresentation.legend(map).enumerated()), id: \.offset) { _, row in
                InspectorRow(row.label) {
                    HStack(spacing: 6) {
                        swatch(row)
                        Text(String(format: "%.1f %%", 100 * row.fraction))
                            .monospacedDigit()
                    }
                    .labelsHidden()
                }
            }

            // One compact row per precipitate phase — objects, median length,
            // areal density — from the SAME map, via
            // `AppState.publishPrecipitateClassificationFromPhaseMap()`. No
            // new room, no table: this is the class map's per-phase fraction
            // row above, extended by one line.
            if let objects = appState.precipitateClassification.result {
                ForEach(objects.classes, id: \.label) { classObjects in
                    InspectorRow(precipitatePhaseName(classObjects.label, map: map)) {
                        Text(precipitateObjectsLine(classObjects))
                            .font(.caption)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                    }
                    .help(objects.analysedAreaRule)
                }
            }

            // How much of the matrix fraction above rests on a full
            // explanation. A matrix verdict is reached both when almost
            // nothing survived removal and when the matrix out-fitted every
            // candidate, and the fraction above says neither. Reported, NOT
            // thresholded: a 0.90 bar measured on one dataset marked 46 % of
            // another whose every acceptance clause passes (2026-09-16,
            // `open-items.md`), so the number is given and the reader judges.
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
                Label(diagnosis, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let evidence = appState.phaseMappingEvidenceLine {
                InspectorRow("Evidence") {
                    Text(evidence)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                }
                .help("The scan position under the cursor, and why it is that colour.")
            }

            InspectorActionRow {
                Button {
                    appState.publishPhaseDistanceProduct()
                } label: {
                    Label("Show Match Distance", systemImage: "ruler")
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
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: Double(row.color.r) / 255,
                        green: Double(row.color.g) / 255,
                        blue: Double(row.color.b) / 255))
            .frame(width: LayoutPolicy.legendSwatch, height: LayoutPolicy.legendSwatch)
            .overlay {
                // The hatch that marks "not indexed" on the map is repeated
                // here, so the legend cannot read as one more phase colour.
                if row.hatched {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
                }
            }
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

    /// Session S5 (owner's product decision): Materials Project is the
    /// default phase source; the built-in library is no longer offered here
    /// — see the doc comment on `CrystalModelLibrary.models`. The menu now
    /// offers exactly the two sources plus this session's already-imported
    /// models (CIF or Materials Project).
    private var addPhaseMenu: some View {
        Menu {
            Button("Materials Project…") { showMaterialsProjectSheet = true }
            Button("From CIF file…") { showCIFImporter = true }
            if !appState.acomSession.importedCrystalModels.isEmpty {
                Divider()
                ForEach(appState.acomSession.importedCrystalModels) { model in
                    Button(importedCrystalModelLabel(model)) { add(model) }
                }
            }
        } label: {
            Label("Add Phase", systemImage: "plus")
        }
        .accessibilityIdentifier("phaseMapping.addPhase")
        .fileImporter(isPresented: $showCIFImporter,
                      allowedContentTypes: cifTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                appState.importCrystalModel(from: url)
                // `importCrystalModel` appends to the shared imported-model
                // list, which ACOM owns; take the one it just selected so a
                // single import serves both rooms.
                if let model = appState.acomSession.importedCrystalModels.last {
                    add(model)
                }
            case .failure(let error):
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

        var body: some View {
            @Bindable var product = appState.phaseMapping
            VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: LayoutPolicy.legendSwatch, height: LayoutPolicy.legendSwatch)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.model.displayName)
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
            }
            zoneAxisField
            if !draft.isEmpty, PhaseMappingSlot.parseZoneAxis(draft) == nil {
                Text("A zone axis is three integers, like 0 1 0.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if !slot.isMatrix {
                orientationRelationshipField
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
            // the fitted [u v w] into the slot — and a draft filled once on
            // appear kept showing "0 0 1" beside a row that said "zone [0 -1 1]"
            // (owner's drive, 2026-09-14). Refresh only when the field's own
            // text no longer means the slot's axis, so "0-12" stays as typed.
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
                        guard index < product.phases.count,
                              let parsed = PhaseMappingSlot.parseZoneAxis(text) else { return }
                        product.phases[index].u = parsed.x
                        product.phases[index].v = parsed.y
                        product.phases[index].w = parsed.z
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            }
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
                TextField("(002) ∥ (200), (002) ∥ (020)", text: Binding(
                    get: { orientationDraft },
                    set: { text in
                        orientationDraft = text
                        guard index < product.phases.count else { return }
                        product.phases[index].orientationRelationshipText = text
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            }
            .help("This phase's plane (hkl) or direction [uvw] that lies parallel "
                  + "to the matrix's, as an orientation relationship is written; "
                  + "list each variant. Empty = any in-plane rotation. Applied "
                  + "once the matrix orientation is fitted.")
        }
    }

    // MARK: Small controls

    /// `NumericField` is the one place a UI form control takes a width
    /// (`LayoutPolicy.swift`, presentation contract rule 4) — these wrap it so
    /// the panel spells no frame of its own.
    ///
    /// `help`, when given, is the row's own explanatory paragraph — moved off
    /// the panel and onto the row it explains as an Xcode-style tooltip
    /// rather than inline prose (owner, 2026-09-21).
    @ViewBuilder
    private func parameterField(_ title: String, value: Binding<Double>,
                                units: String, format: String, help: String? = nil) -> some View {
        if let help {
            InspectorRow(title) {
                NumericField(title, value: value,
                             format: .number.precision(.fractionLength(3)), unit: units)
                    .labelsHidden()
            }
            .help(help)
        } else {
            InspectorRow(title) {
                NumericField(title, value: value,
                             format: .number.precision(.fractionLength(3)), unit: units)
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

    /// The phase name a class label prints as, or a fallback that still
    /// names the number — `map.phaseNames` and `classObjects.label` are
    /// index-aligned by construction (`PhaseMapObjectsBridge.labeledMap`).
    private func precipitatePhaseName(_ label: Int32, map: PhaseMap) -> String {
        let index = Int(label)
        guard map.phaseNames.indices.contains(index) else { return "Phase \(label)" }
        return map.phaseNames[index]
    }

    /// "N objects · median length L nm · D per µm²", or "N objects · no scan
    /// scale" without a real-space pixel size — the refusal rule stays
    /// visible rather than a blank field (`PrecipitateStatistics.density`).
    /// `medianLength`/`meanWidth` are scan PIXELS (`PrecipitateStatistics
    /// .density`'s own contract); this is the one place that turns them
    /// physical, using the same calibration the density itself was computed
    /// from, never a different one.
    private func precipitateObjectsLine(_ classObjects: PrecipitateSegmentation.ClassObjects) -> String {
        let density = classObjects.density
        let n = density.acceptedCount
        let countText = "\(n) object\(n == 1 ? "" : "s")"
        guard let pixelSize = density.pixelSize, let unit = density.pixelUnit,
              let areal = density.arealDensity else {
            return "\(countText) · no scan scale"
        }
        var parts = [countText]
        if let medianPx = density.medianLength {
            parts.append(String(format: "median length %.3g %@", medianPx * pixelSize, unit as NSString))
        }
        // µm² reads better than nm² for a precipitate density; converted
        // only for the unit this app actually normalizes to on load
        // (`AppState+Open.swift`'s µm → nm pixel-calibration step). Any
        // other unit is printed in its own units rather than guessing a
        // conversion for it.
        if unit.lowercased() == "nm" {
            parts.append(String(format: "%.3g per µm²", areal * 1e6))
        } else {
            parts.append(String(format: "%.3g per %@²", areal, unit as NSString))
        }
        return parts.joined(separator: " · ")
    }
}
