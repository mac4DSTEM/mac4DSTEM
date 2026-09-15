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
//  `docs/v3-vector-matching-plan.md` runs. The badge is not decoration — this
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
    @SceneStorage("ai.phaseMapping.advanced.isExpanded") private var showsAdvanced = false

    /// Same reasoning as ACOM's importer: nothing on a stock macOS declares
    /// `.cif`, so this resolves to the same dynamic type a `.cif` on disk gets.
    private var cifTypes: [UTType] { [UTType(filenameExtension: "cif") ?? .data] }

    var body: some View {
        @Bindable var product = appState.phaseMapping

        Section("Phases") {
            if product.phases.isEmpty {
                Text("Add the matrix phase and at least one precipitate phase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(product.phases.enumerated()), id: \.element.id) { index, slot in
                PhaseRow(index: index, slot: slot)
            }
            if product.phases.count > 1 {
                Picker("Matrix", selection: matrixSelection) {
                    ForEach(product.phases) { slot in
                        Text(slot.model.displayName).tag(slot.id)
                    }
                }
                .accessibilityIdentifier("phaseMapping.matrix")
                Text("The matrix is stated, not found: its reflections are removed "
                     + "from every pattern and it is the answer where too little is left.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Which AXIS it is viewed down is not stated — it is measured.
                // A matrix viewed down an axis it is not on presents no
                // reflections to remove, so nothing is removed and every
                // position comes back "not indexed", which looks exactly like
                // a method that does not work (the owner's run, 2026-09-12).
                Button {
                    Task { await appState.findMatrixZoneAxis() }
                } label: {
                    Label("Find Matrix Zone Axis", systemImage: "scope")
                }
                .disabled(appState.isBusy || appState.braggVectors == nil)
                .accessibilityIdentifier("phaseMapping.findZoneAxis")

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
                    LabeledContent {
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
                    } label: {
                        Text("[\(fit.zoneAxis.x) \(fit.zoneAxis.y) \(fit.zoneAxis.z)]")
                            .monospacedDigit()
                            .foregroundStyle(rank == 0 ? .primary : .secondary)
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
                } else if product.zoneAxisFits.count > 1 {
                    Text("Symmetry-equivalent axes should tie exactly. They are "
                         + "shown so a fit can be told from a coin toss.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            addPhaseMenu
        }

        Section("Reference library") {
            LabeledContent("Orientations") {
                Text("\(product.projectedEntryCount)")
                    .monospacedDigit()
                    .foregroundStyle(product.projectedEntryCount > product.reference.maximumEntries
                                     ? .orange : .primary)
            }
            parameterField("Max |q|", value: $product.reference.kMaxInvAngstrom,
                           units: "Å⁻¹", format: "%.2f")
            parameterField("In-plane step", value: $product.reference.inPlaneStepDeg,
                           units: "°", format: "%.1f")
            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                intField("Vectors per orientation",
                         value: $product.reference.maximumVectorsPerEntry)
                parameterField("Minimum intensity",
                               value: $product.reference.minimumIntensityFraction,
                               units: "of strongest", format: "%.3f")
                parameterField("Excitation slab",
                               value: $product.reference.excitationSlabInvAngstrom,
                               units: "Å⁻¹", format: "%.3f")
                Text("A library holding every allowed reflection matches anything. "
                     + "The cap is what keeps a match informative. Minimum intensity "
                     + "only bites when it removes more than the cap already does.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Matching") {
            parameterField("Pair radius", value: $product.matching.pairRadiusInvAngstrom,
                           units: "Å⁻¹", format: "%.3f")
            parameterField("Matrix removal", value: $product.matching.matrixToleranceInvAngstrom,
                           units: "Å⁻¹", format: "%.3f")
            parameterField("Not indexed above",
                           value: $product.matching.notIndexedAboveInvAngstrom,
                           units: "Å⁻¹", format: "%.3f")
            // The data's reach: a masked or cropped pattern ends before the
            // detector does, and its edge is a ring of maxima no phase
            // explains (Thronsen step 3, 2026-09-15). 0 = the detector.
            parameterField("Ignore peaks beyond",
                           value: $product.matching.maximumVectorInvAngstrom,
                           units: "Å⁻¹ (0 = detector)", format: "%.2f")

            // These are set in Å⁻¹ and met on a pixel grid, and until
            // 2026-09-12 nothing on screen joined the two. On the owner's own
            // cube the defaults are 0.44 of one detector pixel; matrix removal
            // removed nothing and the map came back empty.
            if let resolution = appState.phaseVectorResolution {
                LabeledContent("On this detector") {
                    Text(String(format: "%.2f · %.2f · %.2f px",
                                resolution.pairRadiusPixels,
                                resolution.matrixRemovalPixels,
                                resolution.notIndexedAbovePixels))
                        .monospacedDigit()
                        .foregroundStyle(resolution.advice == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }
                if let advice = resolution.advice {
                    Label(advice, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

        Section {
            if let refusal = product.runRefusal {
                Label(refusal, systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if appState.braggVectors == nil {
                Label("Detect Bragg disks first — this matches the peaks disk "
                      + "detection finds, it does not find its own.",
                      systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await appState.runPhaseMapping() }
            } label: {
                Label("Map Phases", systemImage: "square.grid.3x3.topleft.filled")
            }
            .disabled(appState.isBusy || product.runRefusal != nil
                      || appState.braggVectors == nil)
            .accessibilityIdentifier("phaseMapping.run")
        }

        if let map = product.map, let run = product.lastRun {
            resultSection(map: map, run: run, product: product)
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(map: PhaseMap, run: PhaseMappingProduct.RunRecord,
                               product: PhaseMappingProduct) -> some View {
        Section("Result") {
            Label("Unvalidated — this method has not been scored against an "
                  + "external ground truth in this app. Read the map; do not "
                  + "quote a phase fraction from it.",
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
                LabeledContent {
                    Text(String(format: "%.1f %%", 100 * row.fraction))
                        .monospacedDigit()
                } label: {
                    HStack(spacing: 6) {
                        swatch(row)
                        Text(row.label)
                    }
                }
            }

            if let diagnosis = appState.phaseMappingDiagnosis {
                // A map that found nothing is a result about the SETTINGS, and
                // on screen it looks exactly like a result about the specimen.
                Label(diagnosis, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let evidence = appState.phaseMappingEvidenceLine {
                LabeledContent("Evidence") {
                    Text(evidence)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
                Text("The scan position under the cursor, and why it is that colour.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.publishPhaseDistanceProduct()
            } label: {
                Label("Show Match Distance", systemImage: "ruler")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("phaseMapping.showDistance")

            LabeledContent("Chance match at max |q|",
                           value: String(format: "%.1f %%", run.worstChanceMatchPercent))
            LabeledContent("Orientations", value: "\(run.libraryEntryCount)")
            if run.matrixInPlaneDegrees.isFinite {
                LabeledContent("Matrix in-plane",
                               value: String(format: "%.0f° (mod symmetry)",
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

    private var addPhaseMenu: some View {
        Menu {
            ForEach(CrystalModelLibrary.models) { model in
                Button(model.displayName) { add(model) }
            }
            Divider()
            Button("From CIF file…") { showCIFImporter = true }
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
    }

    private func add(_ model: CrystalModel) {
        guard !appState.phaseMapping.phases.contains(where: { $0.model.id == model.id })
        else { return }
        let isFirst = appState.phaseMapping.phases.isEmpty
        appState.phaseMapping.phases.append(
            PhaseMappingSlot(model: model, isMatrix: isFirst, u: 0, v: 0, w: 1))
    }

    private struct PhaseRow: View {
        @Environment(AppState.self) private var appState
        let index: Int
        let slot: PhaseMappingSlot
        @State private var draft = ""

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
            }
            .onAppear { if draft.isEmpty { draft = "\(slot.u) \(slot.v) \(slot.w)" } }
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
            return LabeledContent("Zone axis") {
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
            }
        }
    }

    // MARK: Small controls

    /// `NumericField` is the one place a UI form control takes a width
    /// (`LayoutPolicy.swift`, presentation contract rule 4) — these wrap it so
    /// the panel spells no frame of its own.
    private func parameterField(_ title: String, value: Binding<Double>,
                                units: String, format: String) -> some View {
        LabeledContent(title) {
            NumericField(title, value: value,
                         format: .number.precision(.fractionLength(3)), unit: units)
        }
    }

    private func intField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            NumericField(title, value: value, format: .number)
        }
    }
}
