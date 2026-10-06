import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// The room's inspector (ADR 056, spec 2 D-5): one flat stack of sections, label left / control right (the app's `InspectorRow`
// kit), no prominent button (the toolbar verb is Quantify and is not drawn here), colour only on symbols. Elements, Region,
// Results and Quantification are open; Fitting and Export start closed. A row whose value the session has not supplied is
// hidden: nothing is shown that was not measured. Numbers are typed through `OptionalNumericField` (locale-safe, commits on
// Return/blur).

/// The Settings tab's content in the Spectroscopy room. Separate from the host so a test can lay it out without an `AppState`.
struct SpectroscopyInspectorSections: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var exportOpen: Bool

    /// The sections, in the order they are drawn (spec 2 D-5): the single source of both.
    enum Part: CaseIterable {
        case elements, region, results, quantification, fitting, export
        var title: String {
            switch self {
            case .elements: "Elements"
            case .region: "Region"
            case .results: "Results"
            case .quantification: "Quantification"
            case .fitting: "Fitting"
            case .export: "Export"
            }
        }
    }

    init(model: SpectroscopyRoomModel, startOpen: Bool = false) {
        self.model = model
        _exportOpen = State(initialValue: startOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
            ForEach(Part.allCases, id: \.self) { part in section(part) }
        }
    }

    @ViewBuilder private func section(_ part: Part) -> some View {
        switch part {
        case .elements: InspectorSection(part.title) { ElementsSection(model: model) }
        case .region: InspectorSection(part.title) { RegionSection(model: model) }
        case .results: InspectorSection(part.title) { ResultsSection(model: model) }
        case .quantification: InspectorSection(part.title) { QuantificationSection(model: model) }
        case .fitting: InspectorSection(part.title, expanded: $model.quantify.expertOpen) { FittingSection(model: model) }
        case .export: InspectorSection(part.title, expanded: $exportOpen) { ExportSection(model: model) }
        }
    }
}

/// Elements: the periodic table, the maps' int / net switch, and Auto ID with what it picked.
struct ElementsSection: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        PeriodicTableView(model: model)
        InspectorRow("Maps") {
            Picker("Map shows", selection: $model.mapMode) {
                ForEach(MapMode.allCases.filter(\.isAvailable), id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("int: the line's window sum. net: less its background windows. wt% and at% are computed on regions (the Results section), not per pixel.")
            .accessibilityIdentifier("spectroscopy.mapMode")
        }
        // The proposer is unvalidated, so its badge stands in this row whatever the run's state (CLAUDE.md, "unvalidated stays
        // labelled"); the button (or, while it runs, the progress and Cancel) is the row under it.
        InspectorRow("Auto ID") { UnvalidatedBadge() }
            .help("Proposes elements from the spectrum when an image opens and picks them (the proposer is unvalidated). Remove a wrong pick in the table.")
        InspectorActionRow {
            if model.autoID.running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.onCancelAutoID?() }
                }
            } else {
                InspectorAdaptiveButton("Auto ID", systemImage: "sparkles",
                                        help: "Propose elements from this spectrum and pick them; the unvalidated proposer's reasons are on the Found row.") { model.onAutoID?() }
                    .disabled(model.onAutoID == nil)
                    .accessibilityIdentifier("spectroscopy.autoID")
            }
        }
        if let o = model.autoID.outcome {
            InspectorValueRow(Self.foundTitle, Self.pickedList(o))
                .help(Self.foundHelp + "\n" + Self.notes(o, o.suggestions))
            // R7 (wp3e F3.1): an excess beside a listed line is a misfit, named so, with no tile.
            let excesses = model.autoIDExcesses
            if !excesses.isEmpty {
                InspectorNote(excesses.map(\.title).joined(separator: "; ")).help(excesses.map(\.detail).joined(separator: "\n"))
            }
        }
        if let why = model.autoID.failure { InspectorNote(why) }
    }

    /// "Al, Si, Mg": what the last run picked, in its order (strongest first); "none" when it found nothing.
    static func pickedList(_ o: AutoIDOutcome) -> String {
        o.suggestions.isEmpty ? "none" : o.suggestions.map { PeriodicLayout.symbol($0.z) }.joined(separator: ", ")
    }

    /// The proposer's own words, as the row's hover: each pick's reason, the sum-peak questions, what it did not test.
    /// The Found row's help (the row lists Auto ID's outcome, not the current picks: the person may have removed one since).
    static let foundTitle = "Found"
    static let foundHelp = "What Auto ID found and picked; remove a wrong one in the table"

    static func notes(_ o: AutoIDOutcome, _ s: [ElementSuggestion]) -> String {
        var lines = s.map { "\(PeriodicLayout.symbol($0.z)): \($0.reason)" }
        lines += o.excesses.map(\.detail)
        lines += o.suspects.map { "\($0.label) \($0.question) \($0.stats)" }
        if !o.notTested.isEmpty { lines.append("Not tested: " + o.notTested.map { "\($0.element) (\($0.reason))" }.joined(separator: ", ")) }
        lines += o.notes
        return lines.joined(separator: "\n")
    }
}

/// Region: the drawing tool, where the spectrum comes from, what to compare it with, and Pin.
struct RegionSection: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        let r = model.regionSettings
        InspectorRow("Tool") {
            Picker("Region tool", selection: $model.drawTool) {
                ForEach(DrawTool.allCases, id: \.self) { Image(systemName: $0.symbol).imageScale(.medium).tag($0).help(Self.toolHelp($0)) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .accessibilityIdentifier("spectroscopy.regionTool")
        }
        if model.regions.count > 1 {
            InspectorRow("Source") {
                Picker("Source", selection: Binding(get: { model.selectedRegion ?? 0 }, set: { model.selectedRegion = $0 })) {
                    ForEach(model.regions) { Text(Self.sourceTitle($0)).tag($0.id) }
                }.labelsHidden()   // compressible: a phase pool carries a CIF's name, which has no bound
            }
        } else {
            InspectorValueRow("Source", "Whole map")
        }
        if let phase = r.phase {
            InspectorRow("Phase") {
                HStack(spacing: 6) { Text(phase).foregroundStyle(.secondary); if model.unvalidated { UnvalidatedBadge() } }
            }
        }
        InspectorRow("Compare with") {
            Picker("Compare with", selection: $model.compare) {
                ForEach(CompareBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().fixedSize()
            .disabled(model.selectedRegion == 0 || model.selectedRegion == nil)
            .help(model.selectedRegion == 0 ? "The whole map has nothing to compare with." : "The grey curve under the spectrum, scaled to this region's counts")
        }
        InspectorRow("Keep this region") {
            Button("Pin") { model.onPin?() }
                .disabled(model.onPin == nil || model.pins.count >= SpectroscopyRoomModel.maximumPins)
                .help(model.pins.count >= SpectroscopyRoomModel.maximumPins
                      ? "Three regions are pinned: unpin one under the spectrum first."
                      : "Freeze a copy of this region's spectrum as a coloured overlay (up to three); the live region moves on.")
        }
        if model.image.sourceWarning, let note = model.image.sourceNote { InspectorNote(note) }
    }

    /// What each drawing tool does, as the segment's hover.
    static func toolHelp(_ t: DrawTool) -> String {
        t == .rectangle ? "Rectangle: drag on the ColorMix"
            : t == .polygon ? "Polygon: click the corners, then the first corner again"
            : "\(t.rawValue.capitalized): drag on the ColorMix"
    }

    /// "Drawn rectangle" for the live region, the pool's own name otherwise.
    static func sourceTitle(_ r: RegionSummary) -> String { r.isDrawn ? "Drawn region" : r.name }
}

/// Quantification: the settings every pooled fit follows (live after Quantify, ADR 054 item 8: no Apply).
struct QuantificationSection: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var editingTyped = false
    var body: some View {
        let q = model.quantify
        InspectorRow("Background") {
            Picker("Background", selection: $model.quantify.background) {
                Text("Empirical").tag(QuantificationMethod.Background.empiricalWithAlEdge)
                Text("Polynomial").tag(QuantificationMethod.Background.wholeRangePolynomial6)
            }.labelsHidden().fixedSize()
            .help("Empirical: a fitted whole-spectrum continuum with the Al K edge step. Polynomial: eXSpy's whole-range polynomial (order under Fitting).")
        }
        InspectorRow("k-factors") {
            HStack(spacing: 6) {
                if q.kSource == .typed { Button("Edit\u{2026}") { editingTyped = true }.help("The typed k table: source, date and a \u{03C3} per factor") }
                Picker("k-factors", selection: $model.quantify.kSource) {
                    Text("Computed").tag(QuantificationMethod.KFactorSource.computed)
                    Text("Typed").tag(QuantificationMethod.KFactorSource.typed)
                }.labelsHidden().fixedSize()
                .help("Computed: Bote-Salvat cross-section, Krause yield, EPQ detector model (unvalidated). Typed: your k with its source and date.")
            }
        }        .sheet(isPresented: $editingTyped) { TypedKSheet(model: model) { editingTyped = false } }
        InspectorRow("Absorption") {
            Toggle("Absorption", isOn: $model.quantify.absorption).labelsHidden().toggleStyle(.checkbox)
        }
        if let note = QuantifyPresentation.absorptionNoteText(q.absorptionNote) { InspectorNote(note) }
        InspectorRow("Thickness") {
            OptionalNumericField(title: "Thickness", value: q.thickness, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "\u{2014}") {
                model.quantify.thickness = max($0, 0)
            }
        }
        if q.thickness != nil {
            InspectorRow("\u{03C3}") {
                OptionalNumericField(title: "Thickness \u{03C3}", value: q.thicknessSigma, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "\u{2014}") {
                    model.quantify.thicknessSigma = max($0, 0)
                }
            }
        }
        InspectorRow("Beam energy") {
            OptionalNumericField(title: "Beam energy", value: q.shownBeam, format: FloatingPointFormatStyle<Double>.number, unit: "keV", prompt: "\u{2014}") {
                model.quantify.beamEnergy = max($0, 0)
            }
            .help(QuantifyPresentation.beamEnergyHelp(q.beamPhrase))
        }
    }
}

/// Export: the results table as CSV, the method as JSON, the shown spectrum as CSV, and the maps as PNG files and one CSV
/// (the only place that writes them).
struct ExportSection: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var pickingFolder = false
    static let csvTitle = "Results CSV\u{2026}", jsonTitle = "Method JSON\u{2026}", spectrumTitle = "Spectrum CSV\u{2026}", mapsTitle = "Maps\u{2026}"
    /// The Maps button is on whenever there is an element map to write (no fit needed).
    static func canExportMaps(_ model: SpectroscopyRoomModel) -> Bool { !model.tiles.isEmpty }

    /// What each button hands the save panel; nil until its text exists (the button is then off).
    static func resultsExport(_ e: ExportSettings) -> PendingExport? { e.csv.map { PendingExport(text: $0, isJSON: false, name: e.fileStem) } }
    static func methodExport(_ e: ExportSettings) -> PendingExport? { e.methodJSON.map { PendingExport(text: $0, isJSON: true, name: e.fileStem + "-method") } }
    static func spectrumExport(_ e: ExportSettings) -> PendingExport? { e.spectrumCSV.map { PendingExport(text: $0, isJSON: false, name: e.fileStem + "-spectrum") } }

    var body: some View {
        let e = model.export
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            if let elements = e.elements { InspectorValueRow("Elements", elements) }
            InspectorActionRow {
                Button(Self.csvTitle) { model.pendingExport = Self.resultsExport(e) }
                    .disabled(Self.resultsExport(e) == nil)
                    .help("The results table: element, line, net counts, k-free ratio, at%, each with its \u{03C3}, the flags and the estimator; the fit's provenance and the unvalidated badge in the header lines")
                    .accessibilityIdentifier("spectroscopy.export.results")
                Button(Self.jsonTitle) { model.pendingExport = Self.methodExport(e) }
                    .disabled(Self.methodExport(e) == nil)
                    .help("The quantification method in its own sorted-keys encoding, with its SHA-256")
                    .accessibilityIdentifier("spectroscopy.export.method")
            }
            InspectorActionRow {
                Button(Self.spectrumTitle) { model.pendingExport = Self.spectrumExport(e) }
                    .disabled(Self.spectrumExport(e) == nil)
                    .help("The shown spectrum: energy, counts, and the model and background where fitted")
                    .accessibilityIdentifier("spectroscopy.export.spectrum")
                Button(Self.mapsTitle) { pickingFolder = true }
                    .disabled(!Self.canExportMaps(model))
                    .help("Every element map, the ColorMix and the HAADF as PNG files as shown (colour, contrast, gamma), one pixel per scan pixel, and the net-count maps as one CSV, into a folder you pick")
                    .accessibilityIdentifier("spectroscopy.export.maps")
                    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                        switch result {
                        case .success(let folder):
                            do {
                                let names = try MapsExport.write(try MapsExport.files(model), to: folder)
                                model.exportNote = MapsExport.note(written: names, folder: folder)
                            } catch { model.exportNote = "Could not write the maps: \(error.localizedDescription)" }
                        case .failure(let error): model.exportNote = "Could not write the maps: \(error.localizedDescription)"
                        }
                    }
            }
            if Self.resultsExport(e) == nil { InspectorNote("Once Quantify has run, the results table and the method can be written.") }
            if let saved = model.exportNote { InspectorNote(saved) }
        }
        .fileExporter(isPresented: Binding(get: { model.pendingExport != nil }, set: { if !$0 { model.pendingExport = nil } }),
                      document: SpectroscopyTextDocument(text: model.pendingExport?.text ?? ""),
                      contentType: model.pendingExport?.isJSON == false ? .commaSeparatedText : .json,
                      defaultFilename: model.pendingExport?.name ?? "spectroscopy") { result in
            switch result {
            case .success(let url): model.exportNote = "Saved \(url.lastPathComponent)"
            case .failure(let error): model.exportNote = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}

/// Fitting: the fit's own knobs. "Fit to" is lane C's (WP3c): emptying it returns to the default range.
struct FittingSection: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        let q = model.quantify
        InspectorRow("Estimator") {
            Picker("Estimator", selection: $model.quantify.estimator) {
                Text("Least squares").tag(QuantificationMethod.Estimator.leastSquares)
                Text("Poisson ML").tag(QuantificationMethod.Estimator.poissonMaximumLikelihood)
            }.labelsHidden().fixedSize()
        }
        InspectorRow("\u{03C3}_k") {
            OptionalNumericField(title: "\u{03C3}_k", value: q.sigmaK, format: FloatingPointFormatStyle<Double>.number, unit: "%") {
                model.quantify.sigmaK = min(max($0, 0), 100)
            }
        }
        if q.background == .wholeRangePolynomial6 {
            InspectorRow("Poly order") { Stepper("\(q.polyOrder)", value: $model.quantify.polyOrder, in: 0...8) }
        }
        InspectorRow("Lock energy axis") { Toggle("Lock energy axis", isOn: $model.quantify.lockEnergyAxis).labelsHidden().toggleStyle(.checkbox) }
        InspectorRow("Fit to") {
            // Emptying the field returns to the default (the Excitation slab pattern, PhaseMappingSettings).
            HStack(spacing: 6) {
                NumberEntryField(title: "Fit to", value: q.fitTo, format: FloatingPointFormatStyle<Double>.number, prompt: "default",
                                 emptyClears: true) { v in model.quantify.fitTo = v.flatMap { $0 > 0.2 ? $0 : nil } }
                    .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: LayoutPolicy.numericFieldWidth)
                Text("keV").foregroundStyle(.secondary).fixedSize()
            }
            .accessibilityLabel("Fit to")
            .help("Upper end of the fitted range. Empty: the default, the axis end or the beam energy but at most 20 keV, the range the continuum's orders were measured on. The method line under the results names the range used; past 20 keV the continuum is unmeasured.")
        }
        if let refined = model.image.energyAxisRefined { InspectorNote("Energy axis: " + refined) }
    }
}

/// The typed k table (ADR 054 item 3): one k per quantified element relative to the reference (C ∝ k·I, eXSpy's
/// convention), with the source, the date and a relative σ per factor. Without a source and a date it is not a k.
struct TypedKSheet: View {
    @Bindable var model: SpectroscopyRoomModel
    var onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typed k-factors").font(.headline)
            Text("k relative to the reference element, C ∝ k·I (as in eXSpy and Cliff-Lorimer). A k without its source and date is not accepted.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text("Element"); Text("k"); Text("σ_k %") }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach($model.quantify.typed) { $e in
                    GridRow {
                        Text(e.element).fontWeight(.semibold)
                        OptionalNumericField(title: "k \(e.element)", value: e.k, format: FloatingPointFormatStyle<Double>.number, prompt: "—") { e.k = max($0, 0) }
                        OptionalNumericField(title: "σ_k \(e.element)", value: e.sigmaPercent, format: FloatingPointFormatStyle<Double>.number, prompt: "flat") {
                            e.sigmaPercent = min(max($0, 0), 100)
                        }
                    }
                }
            }
            LabeledContent("Reference") {
                Picker("Reference", selection: Binding(get: { model.quantify.typedReference ?? "" }, set: { model.quantify.typedReference = $0.isEmpty ? nil : $0 })) {
                    Text("none").tag("")
                    ForEach(model.quantify.typed) { Text($0.element).tag($0.element) }
                }.labelsHidden().fixedSize()
            }
            LabeledContent("Source") { TextField("Source", text: $model.quantify.typedSource, prompt: Text("citation or file")).labelsHidden().frame(width: 260) }
            LabeledContent("Date") { TextField("Date", text: $model.quantify.typedDate, prompt: Text("YYYY-MM-DD")).labelsHidden().frame(width: 120) }
            HStack { Spacer(); Button("Done", action: onDone).keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(minWidth: 420)
    }
}

/// A text file the save panel writes (the results CSV, the method JSON).
struct SpectroscopyTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

#Preview("Inspector") {
    ScrollView { SpectroscopyInspectorSections(model: .fixture, startOpen: true).padding() }.frame(width: 320, height: 900)
}
