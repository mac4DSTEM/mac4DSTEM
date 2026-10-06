import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// The five steps' inspector content (ADR 054 §8): one flat stack per step, label left /
// control right (the app's `InspectorRow` kit), ≤ 7 rows each, no prominent button (the
// toolbar verb is Quantify and is not drawn here), colour only on symbols. A row whose
// value the session has not supplied is hidden — nothing is shown that was not measured.
// Numbers are typed through `OptionalNumericField` (locale-safe, commits on Return/blur).

/// A picker row whose options are plain strings (lane R maps them to its enums). An empty
/// value shows "—".
private struct ChoiceRow: View {
    let label: String
    @Binding var value: String
    let options: [String]
    var body: some View {
        InspectorRow(label) {
            Picker(label, selection: $value) {
                if value.isEmpty { Text("—").tag("") }
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().fixedSize()
        }
    }
}

/// 1 · Spectrum image — up to six rows; most are readouts.
struct SpectrumImageInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        let s = model.image
        InspectorGroup {
            if let source = s.source {
                InspectorValueRow("Source", source)
                if s.sourceWarning, let note = s.sourceNote { InspectorNote(note) }
            }
            if let v = s.framesReadout { InspectorValueRow("Frames", v) }
            if let frames = s.frames {
                InspectorRow("Frames") {   // "of N" is the help: the label plus two 72-pt fields did not fit 248 pt
                    HStack(spacing: 4) {
                        OptionalNumericField(title: "First frame", value: s.frameLo, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                            model.image.frameLo = min(max($0, 1), s.frameHi ?? frames)
                        }
                        Text("–")
                        OptionalNumericField(title: "Last frame", value: s.frameHi, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                            model.image.frameHi = min(max($0, s.frameLo ?? 1), frames)
                        }
                    }.help("First and last frame of \(frames)")
                }
            }
            // The one Energy axis readout of the room (the Expert lock refers to this). Refinement is WP3's: until
            // then the axis is the file's, and there is nothing to choose.
            if model.isLive {
                if let r = s.energyAxisReadout { InspectorValueRow("Energy axis", r) }
                if let r = s.energyAxisRefined { InspectorValueRow("Refined", r) }
            } else {
                InspectorRow("Energy axis") {
                    HStack(spacing: 6) {
                        if let r = s.energyAxisReadout { Text(r).foregroundStyle(.secondary).lineLimit(1) }
                        Picker("Energy axis", selection: $model.image.energyAxis) { Text("File").tag("File"); Text("Refined").tag("Refined") }
                            .labelsHidden().fixedSize()
                    }
                }
            }
            if let median = s.countsMedian {
                InspectorRow("Counts / px") {
                    HStack(spacing: 8) {
                        if !s.countsHistogram.isEmpty { CountsSparkline(values: s.countsHistogram).frame(width: 60, height: 16) }
                        Text(median).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if let v = s.liveDead { InspectorValueRow("Live / dead", v) }
            if let v = s.geometry { InspectorValueRow("Geometry", v) }
        }
    }
}

private struct CountsSparkline: View {
    let values: [Double]
    var body: some View {
        Canvas { ctx, size in
            let mx = values.max() ?? 1, w = size.width / CGFloat(max(values.count, 1))
            for (i, v) in values.enumerated() {
                let h = size.height * CGFloat(v / max(mx, 1e-12))
                ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: size.height - h, width: w - 1, height: h)), with: .color(.secondary.opacity(0.7)))
            }
        }
    }
}

/// 2 · Elements & maps — the periodic table plus two rows ("Map shows" lives in the map header).
struct ElementsInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var reviewing = false
    @State private var detailsOpen = false
    var body: some View {
        InspectorGroup {
            PeriodicTableView(model: model)
            InspectorRow("Suggestions") {
                HStack(spacing: 8) {
                    let s = model.elements.suggestions
                    Text(s.isEmpty ? "none" : "\(s.count) pending · \(s.map { PeriodicLayout.symbol($0.z) }.joined(separator: ", "))")
                        .foregroundStyle(.secondary).lineLimit(1)
                    Button("Review") { reviewing = true }.disabled(s.isEmpty)
                        .popover(isPresented: $reviewing, arrowEdge: .bottom) { SuggestionReview(model: model) }
                }
            }
            InspectorRow("Auto ID") {
                HStack(spacing: 6) {
                    if model.autoID.running {
                        ProgressView().controlSize(.small)
                        Text("Proposing…").foregroundStyle(.secondary).lineLimit(1)
                        Button("Cancel") { model.onCancelAutoID?() }
                    } else {
                        // The proposer is unvalidated on real data (the same word the at% carries).
                        if model.autoID.outcome != nil { UnvalidatedBadge() }
                        Button("Run") { model.onAutoID?() }.disabled(model.onAutoID == nil)
                            .help("Proposes elements from the selected region's spectrum, on the file's axis (Quantify refines the axis unless it is locked). Your picks are never changed; each suggestion waits for one click.")
                    }
                }
            }
            if let why = model.autoID.failure { InspectorNote(why) }
            if let o = model.autoID.outcome, o.hasDetails {
                InspectorSection("Auto ID notes · \(o.region)", expanded: $detailsOpen) {
                    ForEach(o.suspects, id: \.label) { InspectorNote("\($0.label) \($0.question)") }
                    if !o.notTested.isEmpty {
                        InspectorNote("Not tested: \(o.notTested.map(\.element).joined(separator: ", "))")
                            .help(o.notTested.map { "\($0.element): \($0.reason)" }.joined(separator: "\n"))
                    }
                    ForEach(o.notes, id: \.self) { InspectorNote($0) }
                }
            }
            if !model.isLive {
                ChoiceRow(label: "Smoothing", value: $model.smoothing, options: ["None", "3 × 3 · σ 1 px", "5 × 5 · σ 1.5 px"])
            }
        }
    }
}

/// The Review popover: each pending suggestion with its reason and one click per role.
/// Nothing is accepted in bulk (ADR 054 §6).
struct SuggestionReview: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.elements.suggestions.isEmpty { Text("No suggestions pending").foregroundStyle(.secondary) }
            ForEach(model.elements.suggestions, id: \.z) { s in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(PeriodicLayout.symbol(s.z)).fontWeight(.semibold)
                        Text(s.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    ForEach(ElementRole.allCases, id: \.self) { r in
                        Button(r.title) { model.elements.accept(s.z, as: r) }.controlSize(.small)
                    }
                }
            }
        }
        .padding(12).frame(minWidth: 300)
    }
}

/// 3 · Regions — up to six rows; Line width appears (7th) only for a drawn line.
struct RegionsInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        let r = model.regionSettings
        InspectorGroup {
            if model.isLive {
                // Regions come from the map (drag a rectangle or ellipse) until the 4D scan's phases are registered (WP3).
                InspectorRow("Region") {
                    Picker("Region", selection: Binding(get: { model.selectedRegion ?? -1 }, set: { model.selectedRegion = $0 })) {
                        ForEach(model.regions) { Text($0.name).tag($0.id) }
                    }.labelsHidden().fixedSize()
                }
                InspectorValueRow("Source", r.source)
                if model.regions.first(where: { $0.id == model.selectedRegion })?.isDrawn == true {
                    InspectorActionRow {
                        Button("Remove region") { if let id = model.selectedRegion { model.onRemoveRegion?(id) } }
                    }
                }
            } else {
                ChoiceRow(label: "Source", value: $model.regionSettings.source, options: ["Drawn", "Phase", "Object"])
            }
            if let phase = r.phase {
                InspectorRow("Phase") {
                    HStack(spacing: 6) {
                        Text(phase).foregroundStyle(.secondary)
                        if model.unvalidated { UnvalidatedBadge() }
                    }
                }
            }
            if let v = r.pixels { InspectorValueRow("Pixels", v) }
            if let v = r.counts { InspectorValueRow("Counts", v) }
            if let v = r.liveTime { InspectorValueRow("Live time", v) }
            if r.isLine {
                InspectorRow("Line width") {
                    Stepper("\(r.lineWidth) px", value: $model.regionSettings.lineWidth, in: 1...25)
                }
            }
            if r.compare != nil {
                ChoiceRow(label: "Compare", value: Binding(get: { model.regionSettings.compare ?? "" }, set: { model.regionSettings.compare = $0 }),
                          options: ["Al Kα · live time", "Al Kα"])
                InspectorNote("Compare names its basis: live time when the file stores it, otherwise the Al Kα reference.")
            }
        }
    }
}

/// 4 · Quantify — at most seven visible rows (Background, k-factors, Typed k, Absorption, Thickness, σ thickness, Beam
/// energy; the last two only when they apply); ▸ Expert adds five (Fit to, WP3c). The fit is live: every row re-fits the pooled
/// spectrum once the Quantify verb has run (ADR 054 item 8), so there is no Apply here.
struct QuantifyInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var editingTyped = false
    var body: some View {
        let q = model.quantify
        InspectorGroup {
            InspectorRow("Background") {
                Picker("Background", selection: $model.quantify.background) {
                    Text("Empirical").tag(QuantificationMethod.Background.empiricalWithAlEdge)
                    Text("Polynomial").tag(QuantificationMethod.Background.wholeRangePolynomial6)
                }.labelsHidden().fixedSize()
                .help("Empirical: a fitted whole-spectrum continuum with the Al K edge step. Polynomial: eXSpy's whole-range polynomial (Expert order).")
            }
            InspectorRow("k-factors") {
                Picker("k-factors", selection: $model.quantify.kSource) {
                    Text("Computed").tag(QuantificationMethod.KFactorSource.computed)
                    Text("Typed").tag(QuantificationMethod.KFactorSource.typed)
                }.labelsHidden().fixedSize()
                .help("Computed: Bote-Salvat cross-section, Krause yield, EPQ detector model (unvalidated). Typed: your k with its source and date.")
            }
            if q.kSource == .typed {
                InspectorActionRow { Button("Typed k…") { editingTyped = true } }
            }
            InspectorRow("Absorption") {
                Toggle("Absorption", isOn: $model.quantify.absorption).labelsHidden().toggleStyle(.checkbox)
            }
            if let note = q.absorptionNote { InspectorNote(note) }
            InspectorRow("Thickness") {
                OptionalNumericField(title: "Thickness", value: q.thickness, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "—") {
                    model.quantify.thickness = max($0, 0)
                }
            }
            InspectorRow("± σ") {
                OptionalNumericField(title: "Thickness σ", value: q.thicknessSigma, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "—") {
                    model.quantify.thicknessSigma = max($0, 0)
                }
            }
            InspectorRow("Beam energy") {
                HStack(spacing: 6) {
                    if let p = q.beamPhrase { Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    OptionalNumericField(title: "Beam energy", value: q.shownBeam, format: FloatingPointFormatStyle<Double>.number, unit: "keV", prompt: "—") {
                        model.quantify.beamEnergy = max($0, 0)
                    }
                }
            }
            InspectorSection("Expert", expanded: $model.quantify.expertOpen) {
                InspectorRow("Estimator") {
                    Picker("Estimator", selection: $model.quantify.estimator) {
                        Text("Least squares").tag(QuantificationMethod.Estimator.leastSquares)
                        Text("Poisson ML").tag(QuantificationMethod.Estimator.poissonMaximumLikelihood)
                    }.labelsHidden().fixedSize()
                }
                InspectorRow("σ_k") {
                    OptionalNumericField(title: "σ_k", value: q.sigmaK, format: FloatingPointFormatStyle<Double>.number, unit: "%") {
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
                    .help("Upper end of the fitted range. Empty: the default, the axis end or the beam energy but at most 20 keV, the range the continuum's orders were measured on. The results footer names the range used; past 20 keV the continuum is unmeasured.")
                }
            }
        }
        .sheet(isPresented: $editingTyped) { TypedKSheet(model: model) { editingTyped = false } }
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

/// 5 · Export — the results table as CSV and the method as JSON, written from the last fit (`SpectroscopyExport`, Core). A
/// plain (non-prominent) pair of buttons; the toolbar verb stays Quantify. Before a fit there is nothing to write, and the
/// step says what it will write.
struct ExportInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    static let csvTitle = "Results CSV\u{2026}", jsonTitle = "Method JSON\u{2026}"
    private struct Pending { var text: String; var type: UTType; var name: String }
    @State private var pending: Pending?
    @State private var saved: String?
    var body: some View {
        InspectorGroup {
            if let elements = model.export.elements, let hash = model.export.methodHash, let csv = model.export.csv, let json = model.export.methodJSON {
                InspectorValueRow("Elements", elements)
                InspectorValueRow("Method", hash, mono: true)
                InspectorActionRow {
                    Button(Self.csvTitle) { pending = Pending(text: csv, type: .commaSeparatedText, name: model.export.fileStem) }
                        .help("The results table: element, line, net counts, k-free ratio, at%, each with its σ, the flags and the estimator; the fit's provenance and the unvalidated badge in the header lines")
                    Button(Self.jsonTitle) { pending = Pending(text: json, type: .json, name: model.export.fileStem + "-method") }
                        .help("The quantification method in its own sorted-keys encoding, with its SHA-256")
                }
                if let saved { InspectorNote(saved) }
            } else {
                InspectorNote("Once Quantify has run, this step writes the results table as CSV and the method as JSON.")
            }
        }
        .fileExporter(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                      document: SpectroscopyTextDocument(text: pending?.text ?? ""), contentType: pending?.type ?? .json,
                      defaultFilename: pending?.name ?? "spectroscopy") { result in
            switch result {
            case .success(let url): saved = "Saved \(url.lastPathComponent)"
            case .failure(let error): saved = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}

#Preview("Inspectors") {
    let m = SpectroscopyRoomModel.fixture
    return ScrollView { VStack(alignment: .leading, spacing: 16) {
        SpectrumImageInspector(model: m); ElementsInspector(model: m); RegionsInspector(model: m)
        QuantifyInspector(model: m); ExportInspector(model: m)
    }.padding() }.frame(width: 320, height: 900)
}
