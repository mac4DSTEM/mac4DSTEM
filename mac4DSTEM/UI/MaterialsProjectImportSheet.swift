//
//  MaterialsProjectImportSheet.swift
//  Role: the fetch UI — an owner decision made this the DEFAULT and only
//        phase source besides the user's own CIFs: no dropdown of stored
//        presets, just an mp-id the user already knows and an optional
//        expectation to check it against. Opened from either the ACOM phase
//        picker (`UI/MapSettings.swift`) or the Phase Mapping "Add Phase"
//        menu (`UI/PhaseMappingSettings.swift`); `addsToPhaseMapping` is the
//        only difference between those two call sites.
//
//  Import is disabled on a mismatch or a failure, and the disabled state says
//  why — the same reason line the result card already shows, since a second,
//  differently-worded copy of that reason is exactly the drift
//  `docs/architecture.md`'s "one legend" rule warns about elsewhere. The pure
//  decision itself lives in `App/AppState+MaterialsProject.swift`'s
//  `canImport(outcome:)`, so it is tested without driving this view.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct MaterialsProjectImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Opened from the Phase workspace: a successful import also becomes a
    /// phase slot, not just the selected ACOM model.
    let addsToPhaseMapping: Bool

    @State private var materialID: String
    @State private var expectedFormula: String
    @State private var expectedSpaceGroupText: String
    @State private var isFetching = false
    @State private var outcome: MaterialsProjectFetchOutcome?

    /// `replacing` prefills the expectation from a model already on the
    /// slot/selection being replaced — its space-group number always, and a
    /// formula only if a cheap way to derive one from `CrystalModel` exists
    /// (none does today; `MaterialsProjectImport`'s own formula parsing runs
    /// the other direction, string to counts). Nothing calls this sheet with
    /// `replacing:` yet — the parameter exists so a future "replace this
    /// phase" action does not need a second initializer.
    init(addsToPhaseMapping: Bool, replacing: CrystalModel? = nil) {
        self.addsToPhaseMapping = addsToPhaseMapping
        _materialID = State(initialValue: "")
        _expectedFormula = State(initialValue: "")
        _expectedSpaceGroupText = State(
            initialValue: replacing?.spaceGroupNumber.map(String.init) ?? "")
    }

    private var trimmedID: String {
        materialID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var expectation: PhaseExpectation {
        let formula = expectedFormula.trimmingCharacters(in: .whitespacesAndNewlines)
        let spaceGroup = Int(expectedSpaceGroupText.trimmingCharacters(in: .whitespacesAndNewlines))
        return PhaseExpectation(
            formula: formula.isEmpty ? nil : formula,
            spaceGroupNumber: spaceGroup
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Divider()
            Form {
                Section("Material") {
                    TextField("mp-id", text: $materialID)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("materialsProject.sheet.id")
                    TextField("Expected formula (optional)", text: $expectedFormula)
                        .accessibilityIdentifier("materialsProject.sheet.formula")
                    TextField("Expected space group number (optional)", text: $expectedSpaceGroupText)
                        .accessibilityIdentifier("materialsProject.sheet.spaceGroup")
                }

                if !appState.materialsProject.hasKey {
                    Section {
                        noKeyNotice
                    }
                }

                if let outcome {
                    Section("Result") {
                        resultCard(for: outcome)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        .frame(
            minWidth: LayoutPolicy.materialsProjectSheet.min.width,
            idealWidth: LayoutPolicy.materialsProjectSheet.ideal.width,
            minHeight: LayoutPolicy.materialsProjectSheet.min.height,
            idealHeight: LayoutPolicy.materialsProjectSheet.ideal.height
        )
        // Picks up a key saved in Settings after this sheet was already
        // constructed — `MaterialsProjectSettings` caches `hasKey` until
        // `load()` runs again (Session/MaterialsProjectSettings.swift).
        .task { appState.materialsProject.load() }
    }

    private var title: some View {
        Text("Materials Project")
            .font(.title3.weight(.semibold))
            .padding()
    }

    private var noKeyNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Materials Project API key — set one in Settings (⌘,).")
                .font(.callout)
            SettingsLink {
                Text("Open Settings…")
            }
            .accessibilityIdentifier("materialsProject.sheet.openSettings")
        }
    }

    @ViewBuilder
    private func resultCard(for outcome: MaterialsProjectFetchOutcome) -> some View {
        switch outcome {
        case .noAPIKey:
            // The "no key" section above already covers this; nothing further
            // to say once a fetch has actually run and confirmed it.
            EmptyView()
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
                .accessibilityIdentifier("materialsProject.sheet.failure")
        case .fetched(let document, let model, let verdict, let fetchedAt):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Formula", value: "\(document.formulaPretty ?? "—") (\(document.materialID))")
                LabeledContent("Space group", value: spaceGroupText(document))
                LabeledContent("Cell", value: cellText(model))
                LabeledContent("Sites", value: "\(model.crystal.sites.count)")
                Text(provenanceText(document, fetchedAt: fetchedAt, model: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                verdictView(verdict)
            }
            .accessibilityIdentifier("materialsProject.sheet.result")
        }
    }

    private func spaceGroupText(_ document: MaterialsProjectDocument) -> String {
        guard let number = document.symmetry?.number else { return "not recorded" }
        if let symbol = document.symmetry?.symbol {
            return "\(symbol) (\(number))"
        }
        return "space group \(number)"
    }

    private func cellText(_ model: CrystalModel) -> String {
        let crystal = model.crystal
        func length(_ value: Double) -> String { String(format: "%.4g", value) }
        func angle(_ value: Double) -> String { String(format: "%.2f", value) }
        return "a=\(length(crystal.a)) b=\(length(crystal.b)) c=\(length(crystal.c)) Å · "
            + "α=\(angle(crystal.alphaDeg)) β=\(angle(crystal.betaDeg)) γ=\(angle(crystal.gammaDeg))°"
    }

    private func provenanceText(
        _ document: MaterialsProjectDocument, fetchedAt: Date, model: CrystalModel
    ) -> String {
        var line = "Materials Project \(document.materialID), fetched \(Self.displayDateFormatter.string(from: fetchedAt))"
            + " — DFT-relaxed cell, typically ~1% off measured."
        if let cellNote = model.provenance["materials_project_cell"] {
            line += " \(cellNote)"
        }
        return line
    }

    @ViewBuilder
    private func verdictView(_ verdict: PhaseExpectationVerdict) -> some View {
        switch verdict {
        case .matches:
            Label("Matches the expected phase", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("materialsProject.sheet.verdict")
        case .unchecked:
            Text("Not checked — no expectation stated")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("materialsProject.sheet.verdict")
        case .mismatch(let reason):
            Text("⚠ \(reason)")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("materialsProject.sheet.verdict")
        }
    }

    private var footer: some View {
        HStack {
            if isFetching {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Fetch") { Task { await fetch() } }
                .keyboardShortcut(.defaultAction)
                .disabled(isFetching || trimmedID.isEmpty)
                .accessibilityIdentifier("materialsProject.sheet.fetch")
            Button("Import") { performImport() }
                .disabled(!canImport(outcome: outcome))
                .help(importDisabledReason ?? "Add this phase model.")
                .accessibilityIdentifier("materialsProject.sheet.import")
        }
        .padding()
    }

    /// Why Import is disabled right now, or nil when it isn't — read by the
    /// button's own tooltip so the reason is stated once, not duplicated.
    private var importDisabledReason: String? {
        guard !canImport(outcome: outcome) else { return nil }
        switch outcome {
        case nil:
            return "Fetch a material first."
        case .noAPIKey:
            return "No Materials Project API key is set."
        case .failure(let message):
            return message
        case .fetched(_, _, .mismatch(let reason), _):
            return reason
        case .fetched:
            return nil
        }
    }

    private func fetch() async {
        isFetching = true
        defer { isFetching = false }
        outcome = await appState.fetchMaterialsProject(materialID: trimmedID, expectation: expectation)
    }

    private func performImport() {
        guard case .fetched(_, let model, _, _) = outcome else { return }
        appState.importFetchedCrystalModel(model, addAsPhaseSlot: addsToPhaseMapping)
        dismiss()
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
