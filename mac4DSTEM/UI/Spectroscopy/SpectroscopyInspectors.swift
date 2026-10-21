import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
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
        case elements, region, spectrum, results, quantification, fitting, export
        var title: String {
            switch self {
            case .elements: "Elements"
            case .region: "Region"
            case .spectrum: "Spectrum"
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
        case .spectrum: InspectorSection(part.title) { SpectrumLayersSection(model: model) }
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
    @State private var detailsOpen = false
    var body: some View {
        PeriodicTableView(model: model)
        SelectedElementRows(model: model)
        InspectorRow("Maps") {
            GlassChipGroup(chips: Self.mapChips(quantified: model.hasFit), mode: .single, selection: Self.mapSelection(model), identifier: "spectroscopy.mapMode")
        }
        // Row 1a: a display kernel on the maps (the fixture has no maps behind it, so no row there).
        if model.isLive {
            InspectorRow("Smooth") {
                Picker("Smooth", selection: $model.smoothing) {
                    ForEach(MapSmoothing.allCases, id: \.self) { Text(Self.smoothingTitle($0)).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                .help(Self.smoothingHelp)
                .accessibilityIdentifier("spectroscopy.smoothing")
            }
        }
        // The proposer is unvalidated, so its badge stands in this row whatever the run's state (CLAUDE.md, "unvalidated stays
        // labelled"); the button (or, while it runs, the progress and Cancel) is the row under it.
        InspectorRow("Auto ID") { UnvalidatedBadge() }
            .help("Proposes elements from the spectrum when an image opens and picks them (the proposer is unvalidated). Remove a wrong pick in the table.")
        InspectorActionRow {
            if model.autoID.running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    InspectorAdaptiveButton("Cancel", systemImage: "xmark.circle", help: "Stop proposing elements") { model.onCancelAutoID?() }
                        .accessibilityIdentifier("spectroscopy.autoID.cancel")
                }
            } else {
                InspectorAdaptiveButton("Auto ID", systemImage: "sparkles",
                                        help: "Propose elements from this spectrum and pick them; the unvalidated proposer's reasons are on the Found row.") { model.onAutoID?() }
                    .disabled(model.onAutoID == nil)
                    .accessibilityIdentifier("spectroscopy.autoID")
            }
        }
        if let o = model.autoID.outcome {
            InspectorValueRow(Self.foundTitle, Self.foundText(o))
                .help(Self.foundHover(o))
            // The proposer's reasons are read on the row, not behind a hover (UI audit 2026-10-14, Offering help).
            if Self.showsDetails(o) {
                DisclosureGroup("Details", isExpanded: $detailsOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(Self.noteLines(o, o.suggestions).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .textSelection(.enabled).padding(.top, 3)
                }
                .accessibilityIdentifier("spectroscopy.autoID.details")
            }
            // R7 (wp3e F3.1): an excess beside a listed line is a misfit, named so, with no tile.
            let excesses = model.autoIDExcesses
            if !excesses.isEmpty {
                InspectorNote(excesses.map(\.title).joined(separator: "; ")).help(excesses.map(\.detail).joined(separator: "\n"))
            }
        }
        if let why = model.autoID.failure { InspectorNote(why) }
    }

    /// The maps' choice as chips: int and net always, wt% and at% once Quantify has run.
    static let mapHelp = "int: the line's window sum. net: less its background windows. wt% and at% (after Quantify, typed k) are per-pixel with no σ; the number with a σ is a pooled region's, in the Results section."
    static func mapChips(quantified: Bool) -> [GlassChip<MapMode>] {
        MapMode.allCases.filter { $0.isOffered(quantified: quantified) }.map {
            GlassChip(id: $0, title: $0.rawValue, help: mapHelp, accessibilityID: "spectroscopy.mapMode." + $0.rawValue)
        }
    }
    static func mapSelection(_ model: SpectroscopyRoomModel) -> Binding<Set<MapMode>> {
        GlassChipSelection.single(Binding(get: { model.mapMode }, set: { model.mapMode = $0 }))
    }

    /// The Smooth menu's entries: the kernel as a tile names it, "None" for the raw map.
    static func smoothingTitle(_ s: MapSmoothing) -> String { s == .none ? "None" : s.label }
    static let smoothingHelp = "A count-conserving kernel on the displayed maps only (Velox's pre-filter). The raw map, the spectra, the fit and the export are untouched; every tile names the kernel."

    /// "Cu 41, Al 380, O 12, Eu 1,1": what the last run picked, in its order (strongest first), each with its net / L_D (one
    /// decimal below 10, none above; the symbol alone when the proposer gave none). A pick applied as Fit only (a line without a
    /// computed k) says so, since it gets no at%. "none" when it found nothing.
    static func foundText(_ o: AutoIDOutcome, locale: Locale = .current) -> String {
        guard !o.suggestions.isEmpty else { return "none" }
        return o.suggestions.map { s in
            var t = PeriodicLayout.symbol(s.z)
            if s.significance > 0 { t += " " + significanceText(s.significance, locale: locale) }
            if s.proposedRole == .fitOnly { t += " (fit only)" }
            return t
        }.joined(separator: ", ")
    }

    /// Rounded first, so 9.96 reads "10" and not "10.0".
    static func significanceText(_ v: Double, locale: Locale) -> String {
        let digits = (v * 10).rounded() / 10 < 10 ? 1 : 0
        return v.formatted(.number.locale(locale).precision(.fractionLength(digits)).grouping(.never))
    }

    /// The number's definition, the hover's first line.
    static func significanceLine(locale: Locale = .current) -> String {
        "net / L_D: 1 = just detectable (Currie, \u{03B1} = \u{03B2} = \(0.05.formatted(.number.locale(locale))))"
    }

    /// The Found row's hover: the number's definition and the row's help. The proposer's reasons are the Details disclosure's.
    static func foundHover(_ o: AutoIDOutcome, locale: Locale = .current) -> String {
        significanceLine(locale: locale) + "\n" + foundHelp
    }

    /// The Details disclosure is drawn when the proposer said anything about its picks, the sum-peak questions or what it did not test.
    static func showsDetails(_ o: AutoIDOutcome) -> Bool { !noteLines(o, o.suggestions).isEmpty }

    /// The proposer's own words, as the row's hover: each pick's reason, the sum-peak questions, what it did not test.
    /// The Found row's help (the row lists Auto ID's outcome, not the current picks: the person may have removed one since).
    static let foundTitle = "Found"
    static let foundHelp = "What Auto ID found and picked; remove a wrong one in the table"

    static func notes(_ o: AutoIDOutcome, _ s: [ElementSuggestion]) -> String { noteLines(o, s).joined(separator: "\n") }

    static func noteLines(_ o: AutoIDOutcome, _ s: [ElementSuggestion]) -> [String] {
        var lines = s.map { "\(PeriodicLayout.symbol($0.z)): \($0.reason)" }
        lines += o.excesses.map(\.detail)
        lines += o.suspects.map { "\($0.label) \($0.question) \($0.stats)" }
        if !o.notTested.isEmpty { lines.append("Not tested: " + o.notTested.map { "\($0.element) (\($0.reason))" }.joined(separator: ", ")) }
        lines += o.notes
        return lines
    }
}

/// Region: the drawing tool, where the spectrum comes from, what to compare it with, and Pin.
struct RegionSection: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        let r = model.regionSettings
        InspectorRow("Tool") {
            GlassChipGroup(chips: Self.toolChips, mode: .single, selection: Self.toolSelection(model), identifier: "spectroscopy.regionTool")
        }
        if model.regions.count > 1 || !model.poolNotes.isEmpty {
            InspectorRow("Source") {
                Picker("Source", selection: Binding(get: { model.selectedRegion ?? 0 }, set: { model.selectedRegion = $0 })) {
                    if Self.isSectioned(model) {   // Drawn · Whole map · Phases · Groups (E1, card E3 a)
                        let drawn = model.regions.filter(\.isDrawn)
                        if !drawn.isEmpty { Section("Drawn") { ForEach(drawn) { Text(Self.sourceTitle($0)).tag($0.id) } } }
                        Section("Whole map") { ForEach(model.regions.filter { !$0.isDrawn && $0.pool == nil }) { Text(Self.sourceTitle($0)).tag($0.id) } }
                        poolSection("Phases", .phases)
                        poolSection("Groups", .groups)
                    } else {
                        ForEach(model.regions) { Text(Self.sourceTitle($0)).tag($0.id) }
                    }
                }.labelsHidden()   // compressible: a phase pool carries a CIF's name, which has no bound
            }
        } else {
            InspectorValueRow("Source", "Whole map")
        }
        if let note = r.registrationNote { InspectorNote(note) }   // card E5 a: a pool says how it reached the spectrum grid
        if let phase = r.phase {
            InspectorRow("Phase") {
                HStack(spacing: 6) { Text(phase).foregroundStyle(.secondary); if r.phaseUnvalidated { UnvalidatedBadge() } }
            }
        }
        if let shape = model.regionOutline { extentRows(shape) }
        InspectorRow("Compare with") {
            Picker("Compare with", selection: $model.compare) {
                ForEach(CompareBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().fixedSize()
            .disabled(model.selectedRegion == 0 || model.selectedRegion == nil)
            .help(model.selectedRegion == 0 ? "The whole map has nothing to compare with." : "The grey curve under the spectrum, scaled to this region's counts")
        }
        InspectorRow("Keep this region") {
            Button("Pin") { SpectroscopyMenuRule.pin(model) }
                .disabled(!SpectroscopyMenuRule.canPin(model))
                .help(model.pins.count >= SpectroscopyRoomModel.maximumPins
                      ? "Three regions are pinned: unpin one under the spectrum first."
                      : "Freeze a copy of this region's spectrum as a coloured overlay (up to three); the live region moves on.")
        }
        if model.image.sourceWarning, let note = model.image.sourceNote { InspectorNote(note) }
    }

    /// The live region's extent as numbers (the pointer's alternative, HIG Pointing devices / Accessibility): a rectangle or an
    /// ellipse is typed, a polygon is read. Typed values obey the drag's rules (`RegionExtent`).
    @ViewBuilder private func extentRows(_ shape: SpectrumRegionShape) -> some View {
        if RegionExtent.isEditable(shape) {
            InspectorRow("Origin (px)") {
                HStack(spacing: 6) { extentField(.x, shape); extentField(.y, shape) }
            }
            InspectorRow("Size (px)") {
                HStack(spacing: 6) { extentField(.width, shape); extentField(.height, shape) }
            }
        } else {
            InspectorValueRow("Extent", Self.extentText(shape))
        }
    }

    private func extentField(_ field: RegionExtent.Field, _ shape: SpectrumRegionShape) -> some View {
        OptionalNumericField(title: Self.extentTitle(field), value: RegionExtent.value(shape, field),
                             format: IntegerFormatStyle<Int>.number.grouping(.never)) { Self.commit(model, field, $0) }
            .accessibilityIdentifier("spectroscopy.region." + Self.extentTitle(field).lowercased())
    }

    static func extentTitle(_ f: RegionExtent.Field) -> String {
        switch f { case .x: "x"; case .y: "y"; case .width: "Width"; case .height: "Height" }
    }

    /// A polygon's bounding rectangle, "x 12 · y 8 · 40 × 30 px".
    static func extentText(_ shape: SpectrumRegionShape) -> String {
        let v = RegionExtent.values(shape)
        return "x \(v.x) \u{00B7} y \(v.y) \u{00B7} \(v.width) \u{00D7} \(v.height) px"
    }

    /// A typed extent value becomes the region edit a drag's end would make (final: the numbers follow).
    static func commit(_ model: SpectroscopyRoomModel, _ field: RegionExtent.Field, _ value: Int) {
        guard let shape = model.regionOutline,
              let edited = RegionExtent.edited(shape, field, to: value, grid: model.gridSize) else { return }
        model.onRegionEdit?(edited, true)
    }

    /// The picker is sectioned only when the 4D scan offers pools or says why not; otherwise it is the flat list it always was.
    static func isSectioned(_ model: SpectroscopyRoomModel) -> Bool {
        !model.poolNotes.isEmpty || model.regions.contains { $0.pool != nil }
    }

    /// One pool section: its pools, then its sentences as disabled lines (no phase map yet, a refusal, an empty class).
    @ViewBuilder private func poolSection(_ title: String, _ section: PoolSection) -> some View {
        let pools = model.regions.filter { $0.pool == section }
        let notes = model.poolNotes.filter { $0.section == section }
        if !pools.isEmpty || !notes.isEmpty {
            Section(title) {
                ForEach(pools) { Text(Self.sourceTitle($0)).tag($0.id) }
                ForEach(Array(notes.enumerated()), id: \.offset) { i, note in
                    Text(note.text).tag(Int.min + (section == .phases ? 0 : 1000) + i).disabled(true)
                }
            }
        }
    }

    /// The three tools as symbol chips; the tool's name is the accessibility label.
    static var toolChips: [GlassChip<DrawTool>] {
        DrawTool.allCases.map {
            GlassChip(id: $0, title: $0.rawValue.capitalized, showsTitle: false, symbol: $0.symbol, help: toolHelp($0),
                      accessibilityID: "spectroscopy.regionTool." + $0.rawValue)
        }
    }
    static func toolSelection(_ model: SpectroscopyRoomModel) -> Binding<Set<DrawTool>> {
        GlassChipSelection.single(Binding(get: { model.drawTool }, set: { model.drawTool = $0 }))
    }

    /// What each drawing tool does, as the chip's hover.
    static func toolHelp(_ t: DrawTool) -> String {
        t == .rectangle ? "Rectangle: drag on the ColorMix"
            : t == .polygon ? "Polygon: click the corners, then the first corner again"
            : "\(t.rawValue.capitalized): drag on the ColorMix"
    }

    /// "Drawn rectangle" for the live region, the pool's own name otherwise.
    static func sourceTitle(_ r: RegionSummary) -> String { r.isDrawn ? "Drawn region" : r.name }
}

/// The five curves the spectrum can draw, each with the colour it is drawn in (the legend the Show menu had) and the layer it
/// switches.
enum CurveLayer: CaseIterable {
    case spectrum, background, model, residual, pins
    var title: String {
        switch self {
        case .spectrum: "Spectrum"
        case .background: "Background"
        case .model: "Model"
        case .residual: "Residual"
        case .pins: "Pins"
        }
    }
    var color: Color { color(role: .wholeMap) }
    /// The chip's colour is the curve's: the Spectrum curve is the live region's colour while a region is shown (ADR 059 §3),
    /// the label colour for the whole map (`SpectrumInteraction.curveColor`); the others are fixed hues, none the accent.
    func color(role: SpectrumInteraction.CurveRole) -> Color {
        switch self {
        case .spectrum: role == .region ? SpectroscopyRoomModel.liveRegionColor : .primary
        case .background: Self.backgroundHue
        case .model: Self.modelHue
        case .residual: .secondary
        case .pins: .pink
        }
    }
    /// The model and background curves' hues, the strip's own (one place for the curve and its chip).
    static let modelHue = Color.blue, backgroundHue = Color.orange
    var keyPath: WritableKeyPath<SpectrumLayers, Bool> {
        switch self {
        case .spectrum: \.spectrum
        case .background: \.background
        case .model: \.model
        case .residual: \.residual
        case .pins: \.pins
        }
    }
    var help: String {
        switch self {
        case .spectrum: "The pooled spectrum of the live region"
        case .background: "The fit's background: the Empirical continuum or the polynomial"
        case .model: "The fitted model, the sum of every fitted line on that background"
        case .residual: "Spectrum less model"
        case .pins: "The pinned regions' spectra and their outlines on the ColorMix"
        }
    }
}

/// The spectrum's vertical scale, as the Linear / Log chips show it: the model keeps one Bool.
nonisolated enum LayerScale: CaseIterable, Sendable {
    case linear, log
    init(log: Bool) { self = log ? .log : .linear }
    var isLog: Bool { self == .log }
    var title: String { self == .log ? "Log" : "Linear" }
}

/// Spectrum: what the plot draws (the Show menu's content, as glass chips): the five curves, the vertical scale, counts per pixel
/// and the net maps' windows.
struct SpectrumLayersSection: View {
    @Bindable var model: SpectroscopyRoomModel

    /// Counts per pooled pixel needs the region's pixel count.
    static func perPixelEnabled(_ model: SpectroscopyRoomModel) -> Bool { model.spectrumPixels > 0 }
    /// The windows need a map to take them from.
    static func windowsEnabled(_ model: SpectroscopyRoomModel) -> Bool { !model.windowBands.isEmpty }
    static let perPixelHelp = "Counts per pooled pixel: a region's size falls out of a comparison."
    static let windowsHelp = "The line and background windows the net maps use. The fit's background (orange) is the Empirical continuum \u{2014} a different model."

    /// The five curves as multi chips, each lit in its own colour (the legend the Show menu had).
    static var curveChips: [GlassChip<CurveLayer>] { curveChips(role: .wholeMap) }
    static func curveChips(role: SpectrumInteraction.CurveRole) -> [GlassChip<CurveLayer>] {
        CurveLayer.allCases.map {
            GlassChip(id: $0, title: $0.title, symbol: "circle.fill", symbolColor: $0.color(role: role), tint: $0.color(role: role), help: $0.help,
                      accessibilityID: "spectroscopy.layers.\($0.title.lowercased())")
        }
    }
    static func curveSelection(_ model: SpectroscopyRoomModel) -> Binding<Set<CurveLayer>> {
        Binding(get: { Set(CurveLayer.allCases.filter { model.layers[keyPath: $0.keyPath] }) },
                set: { on in for layer in CurveLayer.allCases { model.layers[keyPath: layer.keyPath] = on.contains(layer) } })
    }

    static var scaleChips: [GlassChip<LayerScale>] {
        LayerScale.allCases.map { GlassChip(id: $0, title: $0.title, accessibilityID: "spectroscopy.layers.scale." + $0.title.lowercased()) }
    }
    static func scaleSelection(_ model: SpectroscopyRoomModel) -> Binding<Set<LayerScale>> {
        GlassChipSelection.single(Binding(get: { LayerScale(log: model.layers.log) }, set: { model.layers.log = $0.isLog }))
    }

    /// The two overlays that need something to show: one group, each chip on or off, disabled until it has its data.
    enum Overlay: CaseIterable { case perPixel, windows }
    static func overlayChips(_ model: SpectroscopyRoomModel) -> [GlassChip<Overlay>] {
        [GlassChip(id: .perPixel, title: "Per pixel", help: perPixelHelp, enabled: perPixelEnabled(model), accessibilityID: "spectroscopy.layers.perpixel"),
         GlassChip(id: .windows, title: "Windows", help: windowsHelp, enabled: windowsEnabled(model), accessibilityID: "spectroscopy.layers.windows")]
    }
    static func overlaySelection(_ model: SpectroscopyRoomModel) -> Binding<Set<Overlay>> {
        Binding(get: { Set(Overlay.allCases.filter { $0 == .perPixel ? model.layers.perPixel : model.layers.windows }) },
                set: { on in model.layers.perPixel = on.contains(.perPixel); model.layers.windows = on.contains(.windows) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            Text("Curves")
            GlassChipGroup(chips: Self.curveChips(role: SpectrumInteraction.curveRole(isLive: model.isLive, selectedRegion: model.selectedRegion)),
                           mode: .multi, selection: Self.curveSelection(model))
        }
        InspectorRow("Scale") {
            GlassChipGroup(chips: Self.scaleChips, mode: .single, selection: Self.scaleSelection(model), identifier: "spectroscopy.layers.scale")
        }
        InspectorRow("Display") {
            GlassChipGroup(chips: Self.overlayChips(model), mode: .multi, selection: Self.overlaySelection(model))
        }
    }
}

/// Quantification: the settings every pooled fit follows (live after Quantify, ADR 054 item 8: no Apply).
struct QuantificationSection: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var editingTyped = false

    /// The absorption correction needs a thickness; until one is typed the box is disabled.
    static func absorptionEnabled(_ q: QuantifySettings) -> Bool { q.thickness != nil }
    /// What the box shows: the stored choice once a thickness is typed, unticked before (the fit does not correct then).
    static func absorptionShown(_ q: QuantifySettings) -> Bool { q.absorption && q.thickness != nil }
    static let absorptionHelp = "Needs a thickness; the box follows it."
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
        // Row 8a: without a thickness the correction cannot run, so the box is off and cannot be ticked; the stored choice
        // (`quantify.absorption`, a provenance key) is not written by this and is shown again once a thickness is typed.
        InspectorRow("Absorption") {
            Toggle("Absorption", isOn: Binding(get: { Self.absorptionShown(q) }, set: { model.quantify.absorption = $0 }))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(!Self.absorptionEnabled(q))
                .help(Self.absorptionHelp)
                .accessibilityIdentifier("spectroscopy.absorption")
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
        InspectorRow("Maps min. counts") {
            OptionalNumericField(title: "Maps minimum counts", value: model.mapsMinimumCounts, format: FloatingPointFormatStyle<Double>.number, unit: "net", prompt: "off") {
                model.mapsMinimumCounts = $0 > 0 ? $0 : nil
                model.onMapsMask?()
            }
        }
        .help("wt% / at% maps leave out pixels whose summed net counts of the quantified elements are below this (composition 0). Off: every pixel.")
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
    @Environment(AppPreferences.self) private var preferences
    static let csvTitle = "Results CSV\u{2026}", jsonTitle = "Method JSON\u{2026}", spectrumTitle = "Spectrum CSV\u{2026}", mapsTitle = "Maps\u{2026}"
    /// The Maps button is on whenever there is an element map to write (no fit needed).
    static func canExportMaps(_ model: SpectroscopyRoomModel) -> Bool { !model.tiles.isEmpty }

    /// What each button hands the save panel; nil until its text exists (the button is then off).
    static func resultsExport(_ e: ExportSettings) -> PendingExport? { e.csv.map { PendingExport(text: $0, isJSON: false, name: e.fileStem) } }
    static func methodExport(_ e: ExportSettings) -> PendingExport? { e.methodJSON.map { PendingExport(text: $0, isJSON: true, name: e.fileStem + "-method") } }
    /// The scale bar needs a pixel size from the file; without one the box is off and unticked (as Absorption without a thickness).
    static func scaleBarEnabled(_ model: SpectroscopyRoomModel) -> Bool { model.scanPixel != nil }
    static func scaleBarShown(_ model: SpectroscopyRoomModel) -> Bool { model.export.scaleBar && scaleBarEnabled(model) }
    static func scaleBarHelp(_ model: SpectroscopyRoomModel) -> String {
        scaleBarEnabled(model) ? "Draws the scale bar into the map PNGs and adds -scalebar to their names; the CSV never has one."
            : "This file states no pixel size, so there is no scale to draw."
    }
    static let regionsHelp = "Outlines the drawn region and the pins on the map PNGs, as the ColorMix shows them, and adds -region to their names; the CSV never has them."
    /// The Spectrum CSV button is on once a spectrum is shown (no fit needed); its text is built here, when it is pressed.
    static func canExportSpectrum(_ e: ExportSettings) -> Bool { e.spectrumOf != nil }
    static func spectrumExport(_ model: SpectroscopyRoomModel) -> PendingExport? {
        guard let label = model.export.spectrumOf else { return nil }
        return PendingExport(text: SpectrumCSV.text(model.series, imageName: label.imageName, regionName: label.regionName),
                             isJSON: false, name: model.export.fileStem + "-spectrum")
    }

    /// The shown spectrum as an EMSA/MAS `.msa` file (FormatoKit's `MSAWriter`; keV axis, counts as Y). nil when it cannot be written.
    static func spectrumMSAExport(_ model: SpectroscopyRoomModel) -> PendingExport? {
        guard let label = model.export.spectrumOf, !model.series.data.isEmpty,
              let data = try? FileRouting.msaData(counts: model.series.data, offsetKeV: model.series.energyStart,
                                                  scaleKeV: model.series.energyStep, title: label.imageName, beamEnergyKeV: nil)
        else { return nil }
        return PendingExport(text: String(decoding: data, as: UTF8.self), isJSON: false, name: model.export.fileStem + "-spectrum", isMSA: true)
    }

    var body: some View {
        @Bindable var preferences = preferences
        let e = model.export
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            if let elements = e.elements { InspectorValueRow("Elements", elements) }
            InspectorActionRow {
                InspectorAdaptiveButton(Self.csvTitle, systemImage: "tablecells",
                                        help: "The results table: element, line, net counts, k-free ratio, at%, each with its \u{03C3}, the flags and the estimator; the fit's provenance and the unvalidated badge in the header lines") {
                    SpectroscopyMenuRule.exportResults(model)
                }
                .disabled(!SpectroscopyMenuRule.canExportResults(model))
                .accessibilityIdentifier("spectroscopy.export.results")
                InspectorAdaptiveButton(Self.jsonTitle, systemImage: "curlybraces",
                                        help: "The quantification method in its own sorted-keys encoding, with its SHA-256") {
                    SpectroscopyMenuRule.exportMethod(model)
                }
                .disabled(!SpectroscopyMenuRule.canExportMethod(model))
                .accessibilityIdentifier("spectroscopy.export.method")
            }
            InspectorRow("Scale bar") {
                Toggle("Scale bar", isOn: Binding(get: { Self.scaleBarShown(model) }, set: { model.export.scaleBar = $0 }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .disabled(!Self.scaleBarEnabled(model))
                    .help(Self.scaleBarHelp(model))
                    .accessibilityIdentifier("spectroscopy.export.scalebar")
            }
            InspectorRow("Regions") {
                Toggle("Regions", isOn: $model.export.regions)
                    .labelsHidden().toggleStyle(.checkbox)
                    .help(Self.regionsHelp)
                    .accessibilityIdentifier("spectroscopy.export.regions")
            }
            InspectorRow("Image size") {
                Picker("Image size", selection: $preferences.exportScale) {
                    ForEach(ExportImageScale.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
                .help(FigureExportSection.sizeHelp)
                .accessibilityIdentifier("spectroscopy.export.size")
            }
            InspectorActionRow {
                InspectorAdaptiveButton(Self.spectrumTitle, systemImage: "waveform",
                                        help: "The shown spectrum: energy, counts, and the model and background where fitted") {
                    SpectroscopyMenuRule.exportSpectrum(model)
                }
                .disabled(!SpectroscopyMenuRule.canExportSpectrum(model))
                .accessibilityIdentifier("spectroscopy.export.spectrum")
                InspectorAdaptiveButton("Spectrum MSA\u{2026}", systemImage: "waveform.path",
                                        help: "The shown spectrum as an EMSA/MAS .msa file (keV axis, counts), readable by other EDX software and by this room") {
                    SpectroscopyMenuRule.exportSpectrumMSA(model)
                }
                .disabled(!SpectroscopyMenuRule.canExportSpectrum(model))
                .accessibilityIdentifier("spectroscopy.export.spectrumMSA")
                InspectorAdaptiveButton(Self.mapsTitle, systemImage: "square.grid.2x2",
                                        help: "Every element map, the ColorMix and the HAADF as PNG files as shown (colour, contrast, gamma), one pixel per scan pixel (times the image size), with the scale bar and the regions when they are on, and the net-count maps as one CSV, into a new folder inside the one you pick (an earlier export is never overwritten)") {
                    SpectroscopyMenuRule.exportMaps(model)
                }
                .disabled(!SpectroscopyMenuRule.canExportMaps(model))
                .accessibilityIdentifier("spectroscopy.export.maps")
            }
            InspectorActionRow {
                InspectorAdaptiveButton("Composition by Class\u{2026}", systemImage: "square.stack.3d.up",
                                        help: "Pool by Class: one pooled fit per phase (the class's spectrum pixels, summed once, moved onto this grid from the phase map), with the current method; class, pixels pooled, element, wt%, at%, \u{03C3}, method hash. validation: none") {
                    model.onCompositionByClass?()
                }
                .disabled(model.classPoolCount == 0 || model.compositionByClassRunning)
                .accessibilityIdentifier("spectroscopy.export.compositionByClass")
            }
            if model.classPoolCount == 0 { InspectorNote("Composition by class needs a phase map on a scan registered to this image.") }
            if Self.resultsExport(e) == nil { InspectorNote("Once Quantify has run, the results table and the method can be written.") }
            if let saved = model.exportNote { InspectorNote(saved) }
            if let folder = model.exportedFolder {
                InspectorActionRow {
                    InspectorAdaptiveButton("Reveal in Finder", systemImage: "folder", help: "Show the folder the maps were written to") {
                        DatasetLocationActions.reveal(path: folder.path)
                    }
                    .accessibilityIdentifier("spectroscopy.export.reveal")
                }
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
        .environment(AppPreferences())
}
