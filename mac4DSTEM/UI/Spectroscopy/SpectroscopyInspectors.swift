import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// The room's inspector (ADR 056): one flat stack of sections, label left / control right (the app's `InspectorRow` kit), at
// most seven rows each, no prominent button (the toolbar verb is Quantify and is not drawn here), colour only on symbols.
// Elements, Region and Fit are open; Map display, Export and Expert start closed. A row whose value the session has not
// supplied is hidden: nothing is shown that was not measured. Numbers are typed through `OptionalNumericField` (locale-safe,
// commits on Return/blur).

/// The Settings tab's content in the Spectroscopy room. Separate from the host so a test can lay it out without an `AppState`.
struct SpectroscopyInspectorSections: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var mapDisplayOpen: Bool
    @State private var exportOpen: Bool

    init(model: SpectroscopyRoomModel, startOpen: Bool = false) {
        self.model = model
        _mapDisplayOpen = State(initialValue: startOpen)
        _exportOpen = State(initialValue: startOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
            InspectorSection("Elements") { ElementsSection(model: model) }
            InspectorSection("Region") { RegionSection(model: model) }
            InspectorSection("Fit") { FitSection(model: model) }
            InspectorSection("Map display", expanded: $mapDisplayOpen) { MapDisplaySection(model: model) }
            InspectorSection("Export", expanded: $exportOpen) { ExportSection(model: model) }
            InspectorSection("Expert", expanded: $model.quantify.expertOpen) { ExpertSection(model: model) }
        }
    }
}

/// Elements: the periodic table, Auto ID, and what it proposed.
struct ElementsSection: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        PeriodicTableView(model: model)
        InspectorRow("Auto ID") {
            HStack(spacing: 6) {
                if model.autoID.running {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.onCancelAutoID?() }
                } else if model.autoID.outcome != nil { UnvalidatedBadge() }
                Toggle("Auto ID", isOn: Binding(get: { model.autoIDEnabled }, set: { on in
                    model.autoIDEnabled = on
                    if on, !model.autoID.running { model.onAutoID?() }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
        .help("Proposes elements from the spectrum when an image opens: the proposals are mapped, marked proposed and left unquantified until you accept them. Your picks are never changed.")
        if let o = model.autoID.outcome {
            let s = model.elements.suggestions
            InspectorRow("Proposed") {
                HStack(spacing: 8) {
                    Text(s.isEmpty ? "none" : s.map { PeriodicLayout.symbol($0.z) }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                    if !s.isEmpty { Button("Accept") { model.acceptProposed() }.buttonStyle(.link) }
                }
            }
            .help(Self.notes(o, s))
            // R7 (wp3e F3.1): a proposal beside a listed line is a misfit, named so, with no tile and no Accept.
            let excesses = model.autoIDExcesses
            if !excesses.isEmpty {
                InspectorNote(excesses.map(\.title).joined(separator: "; ")).help(excesses.map(\.detail).joined(separator: "\n"))
            }
        }
        if let why = model.autoID.failure { InspectorNote(why) }
    }

    /// The proposer's own words, as the row's hover: each proposal's reason, the sum-peak questions, what it did not test.
    static func notes(_ o: AutoIDOutcome, _ s: [ElementSuggestion]) -> String {
        var lines = s.map { "\(PeriodicLayout.symbol($0.z)): \($0.reason)" }
        lines += o.excesses.map(\.detail)
        lines += o.suspects.map { "\($0.label) \($0.question) \($0.stats)" }
        if !o.notTested.isEmpty { lines.append("Not tested: " + o.notTested.map { "\($0.element) (\($0.reason))" }.joined(separator: ", ")) }
        lines += o.notes
        return lines.joined(separator: "\n")
    }
}

/// Region: where the spectrum comes from, what it holds, what to compare it with, and Pin.
struct RegionSection: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        let r = model.regionSettings
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
        if let p = r.pixels { InspectorValueRow("Pixels", p + (r.counts.map { " \u{00B7} \($0) counts" } ?? "")) }
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

    /// "Drawn rectangle" for the live region, the pool's own name otherwise.
    static func sourceTitle(_ r: RegionSummary) -> String { r.isDrawn ? "Drawn region" : r.name }
}

/// Fit: the settings every pooled fit follows (live after Quantify, ADR 054 item 8: no Apply).
struct FitSection: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var editingTyped = false
    var body: some View {
        let q = model.quantify
        InspectorRow("Background") {
            Picker("Background", selection: $model.quantify.background) {
                Text("Empirical").tag(QuantificationMethod.Background.empiricalWithAlEdge)
                Text("Polynomial").tag(QuantificationMethod.Background.wholeRangePolynomial6)
            }.labelsHidden().fixedSize()
            .help("Empirical: a fitted whole-spectrum continuum with the Al K edge step. Polynomial: eXSpy's whole-range polynomial (Expert order).")
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
        if let note = q.absorptionNote { InspectorNote(note) }
        InspectorRow("Thickness") {
            OptionalNumericField(title: "Thickness", value: q.thickness, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "\u{2014}") {
                model.quantify.thickness = max($0, 0)
            }
        }
        if q.thickness != nil {
            InspectorRow("\u{00B1} \u{03C3}") {
                OptionalNumericField(title: "Thickness \u{03C3}", value: q.thicknessSigma, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "\u{2014}") {
                    model.quantify.thicknessSigma = max($0, 0)
                }
            }
        }
        InspectorRow("Beam energy") {
            HStack(spacing: 6) {
                if let p = q.beamPhrase { Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                OptionalNumericField(title: "Beam energy", value: q.shownBeam, format: FloatingPointFormatStyle<Double>.number, unit: "keV", prompt: "\u{2014}") {
                    model.quantify.beamEnergy = max($0, 0)
                }
            }
        }
    }
}

/// Map display: the active map's colour, contrast window and gamma (the same controls as the popover on its tile's chip), and
/// one reset for every map. The ColorMix has none of its own: it follows its elements. (Smoothing and binning are not applied
/// to the maps yet, so they are not drawn.)
struct MapDisplaySection: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        let map = model.active, pixels = model.pixels(of: map)
        if map == .colorMix {
            InspectorNote("Click a map to set its colour, contrast and gamma. The ColorMix follows its elements.")
        } else {
            InspectorValueRow("Map", model.mapTitle(map))
            switch map {
            case .element(let z):
                InspectorRow("Colour") { ColorPicker("Colour", selection: model.colorBinding(z), supportsOpacity: false).labelsHidden() }
            case .haadf:
                InspectorRow("Colormap") { Picker("Colormap", selection: $model.haadfColormap) { ColormapChoices() }.labelsHidden().pickerStyle(.menu) }
            case .colorMix: EmptyView()
            }
            if !pixels.isEmpty {
                let display = model.displayBinding(map)
                HistogramView(pixels: pixels, version: model.tileRevision, rangeLo: display.lo, rangeHi: display.hi)
                    .help("Drag the handles to set this map's contrast window.")
                AdjustmentSlider("Gamma", value: display.gamma.mapGammaDouble, in: 0.2...3, defaultValue: 1.0)
            }
        }
        InspectorRow("All maps") {
            Button("Reset") { model.elementColors = [:]; model.mapDisplays = [:]; model.haadfColormap = .gray }
                .disabled(model.elementColors.isEmpty && model.mapDisplays.isEmpty && model.haadfColormap == .gray)
                .help("Back to the default colours, each map\u{2019}s default contrast window and gamma 1")
        }
    }
}

/// Export: the results table as CSV and the method as JSON (the same menu as the panel's header).
struct ExportSection: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        if let elements = model.export.elements, let hash = model.export.methodHash {
            InspectorValueRow("Elements", elements)
            InspectorValueRow("Method", hash, mono: true)
            InspectorActionRow {
                Button(ExportMenu.csvTitle) { if let t = model.export.csv { model.pendingExport = PendingExport(text: t, isJSON: false, name: model.export.fileStem) } }
                    .help("The results table: element, line, net counts, k-free ratio, at%, each with its \u{03C3}, the flags and the estimator; the fit's provenance and the unvalidated badge in the header lines")
                Button(ExportMenu.jsonTitle) { if let t = model.export.methodJSON { model.pendingExport = PendingExport(text: t, isJSON: true, name: model.export.fileStem + "-method") } }
                    .help("The quantification method in its own sorted-keys encoding, with its SHA-256")
            }
            if let saved = model.exportNote { InspectorNote(saved) }
        } else {
            InspectorNote("Once Quantify has run, this writes the results table as CSV and the method as JSON.")
        }
    }
}

/// Expert: the fit's own knobs. "Fit to" is lane C's (WP3c): emptying it returns to the default range.
struct ExpertSection: View {
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
