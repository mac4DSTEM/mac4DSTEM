//
//  PrecipitateThicknessRows.swift
//  Role: the thickness behind the counts and what it gives (rooms design 2026-10-21 §3, task 41): a typed t ± σ in nm with its source
//        in words, and under it N_V per phase, ImagoKit's `numberDensity` of each phase's areal density (the report's summaries; the
//        view computes nothing). Typing a usable value records a new objects run through `AppState.setPrecipitateThickness`; an
//        unusable one marks itself and leaves the run alone. Read the EELS method JSON fills the source words, never the number.
//

import ShellInspector
import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct PrecipitateThicknessRows: View {
    @Environment(AppState.self) private var appState
    let report: PrecipitateObjectReport

    @State private var thickness: Double?
    @State private var sigma: Double?
    @State private var source = ""
    @State private var origin = ThicknessEntry.Origin.typed
    @State private var importing = false
    @State private var importFailure: String?

    var body: some View {
        InspectorRow("Thickness") {
            OptionalNumericField(title: "Thickness", value: thickness, format: .number, unit: "nm", prompt: "—") { thickness = $0; commit() }
                .accessibilityIdentifier("precipitates.nv.thickness")
        }
        .help("The specimen thickness behind N_V, in nm, typed by you.")
        InspectorRow("Thickness ±") {
            OptionalNumericField(title: "Thickness sigma", value: sigma, format: .number, unit: "nm", prompt: "0") { sigma = $0; commit() }
                .accessibilityIdentifier("precipitates.nv.sigma")
        }
        .help("The thickness's uncertainty (σ), in nm; it is the σ of N_V.")
        InspectorRow("Source") {
            TextField("Source", text: $source, prompt: Text("CBED fringes, EELS t/λ …"))
                .labelsHidden().textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
                .accessibilityIdentifier("precipitates.nv.sourceNote")
        }
        .help("Where the thickness comes from, in words; it is written into the CSV and the session.")
        InspectorActionRow {
            InspectorAdaptiveButton("Read EELS method JSON…", systemImage: "doc.text.magnifyingglass",
                                    help: "macTEM's EELS thickness method file: fills the source words; the thickness stays your number.") {
                importing = true
            }
            .accessibilityIdentifier("precipitates.nv.readJSON")
        }
        if let why = importFailure { InspectorNote(why) }
        if let invalid = invalidReason { InspectorNote(invalid).accessibilityIdentifier("precipitates.nv.invalid") }
        nVolumeRows
        .onAppear { load(appState.precipitateThickness) }
        .onChange(of: appState.precipitateThickness) { _, new in load(new) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let parsed = try ThicknessEntry.source(fromEELSMethodJSON: String(contentsOf: url, encoding: .utf8))
                    source = parsed.text; origin = parsed.origin; importFailure = nil
                    commit()
                } catch { importFailure = error.localizedDescription }
            case .failure(let error): importFailure = error.localizedDescription
            }
        }
    }

    /// N_V per phase from the report, or the one sentence that says what is missing.
    @ViewBuilder private var nVolumeRows: some View {
        let rows = report.summaries.filter { $0.nVolumePerUm3 != nil }
        if rows.isEmpty {
            if appState.precipitateThickness == nil {
                InspectorNote("Type a thickness to get N_V.").accessibilityIdentifier("precipitates.nv.empty")
            } else if !report.hasPhysicalScale {
                InspectorNote("No scan scale: N_V needs the real-space pixel size.").accessibilityIdentifier("precipitates.nv.empty")
            }
        } else {
            ForEach(rows) { s in
                InspectorDataRow("N_V " + s.phaseName) {
                    HStack(spacing: 6) {
                        PhaseSwatch(rgb: report.color(of: s.label))
                        Text(Self.nVolumeText(s)).monospacedDigit()
                    }
                    .labelsHidden()
                }
                .help("Areal density over the thickness: N_A / t. Assumes the objects span the foil; σ is the thickness's alone.")
                .accessibilityIdentifier("precipitates.nv.row.\(s.label)")
            }
            Text("Assumes objects span the foil.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("precipitates.nv.assumption")
        }
    }

    /// "3 400 ± 430 /µm³", the σ only when the thickness has one.
    static func nVolumeText(_ s: PrecipitateObjectReport.ClassSummary) -> String {
        guard let value = s.nVolumePerUm3 else { return "—" }
        var text = PrecipitateFormat.number(value)
        if let sigma = s.nVolumeSigmaPerUm3, sigma > 0 { text += " ± " + PrecipitateFormat.number(sigma) }
        return text + " /µm³"
    }

    /// The entry the fields describe, or nil when they are not usable yet (no thickness, or a value the kit refuses).
    private var draft: ThicknessEntry? {
        guard let thickness else { return nil }
        let words = source.trimmingCharacters(in: .whitespaces)
        return ThicknessEntry(nanometres: thickness, sigmaNanometres: sigma ?? 0, source: words.isEmpty ? "typed value" : words, origin: origin)
    }

    private var invalidReason: String? {
        guard let thickness else { return nil }
        if !(thickness > 0 && thickness.isFinite) { return "Thickness must be a positive number of nm." }
        if let sigma, !(sigma >= 0 && sigma.isFinite) { return "σ must be zero or more." }
        return nil
    }

    /// A usable draft records the run; an unusable one, or a cleared thickness, is the person's to fix (a cleared one clears the entry).
    private func commit() {
        if thickness == nil { appState.setPrecipitateThickness(nil); return }
        guard invalidReason == nil, let entry = draft, entry.isUsable else { return }
        appState.setPrecipitateThickness(entry)
    }

    private func load(_ entry: ThicknessEntry?) {
        guard let entry else { return }
        if thickness != entry.nanometres { thickness = entry.nanometres }
        if sigma != entry.sigmaNanometres { sigma = entry.sigmaNanometres }
        if source != entry.source { source = entry.source }
        origin = entry.origin
    }
}
