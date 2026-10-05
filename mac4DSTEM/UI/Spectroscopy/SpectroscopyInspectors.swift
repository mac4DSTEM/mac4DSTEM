import SwiftUI

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
                InspectorRow("Source") {
                    HStack(spacing: 4) {
                        Text(source).foregroundStyle(.secondary)
                        if s.sourceWarning {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Scan shapes differ — the shapes are in Info").accessibilityLabel("Scan shapes differ")
                        }
                    }
                }
            }
            if let frames = s.frames {
                InspectorRow("Frames of \(frames)") {
                    HStack(spacing: 4) {
                        OptionalNumericField(title: "First frame", value: s.frameLo, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                            model.image.frameLo = min(max($0, 1), s.frameHi ?? frames)
                        }
                        Text("–")
                        OptionalNumericField(title: "Last frame", value: s.frameHi, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                            model.image.frameHi = min(max($0, s.frameLo ?? 1), frames)
                        }
                    }
                }
            }
            // The one Energy axis readout of the room (the Expert lock refers to this).
            InspectorRow("Energy axis") {
                HStack(spacing: 6) {
                    if let r = s.energyAxisReadout { Text(r).foregroundStyle(.secondary).lineLimit(1) }
                    Picker("Energy axis", selection: $model.image.energyAxis) { Text("File").tag("File"); Text("Refined").tag("Refined") }
                        .labelsHidden().fixedSize()
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
            ChoiceRow(label: "Smoothing", value: $model.smoothing, options: ["None", "3 × 3 · σ 1 px", "5 × 5 · σ 1.5 px"])
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
            ChoiceRow(label: "Source", value: $model.regionSettings.source, options: ["Drawn", "Phase", "Object"])
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

/// 4 · Quantify — up to six visible rows; ▸ Expert adds four.
struct QuantifyInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    var body: some View {
        let q = model.quantify
        InspectorGroup {
            ChoiceRow(label: "Method", value: $model.quantify.method, options: ["Mg/Si in Al · LS · BP k", "Custom"])
            ChoiceRow(label: "Background", value: $model.quantify.background, options: ["Empirical + Al edge", "Polynomial windows"])
            ChoiceRow(label: "k-factors", value: $model.quantify.kFactors, options: ["Brown-Powell (computed)", "Typed (with source)"])
            InspectorRow("Absorption") {
                Toggle(q.absorptionNote ?? "", isOn: $model.quantify.absorption).toggleStyle(.checkbox)
            }
            InspectorRow("Thickness") {
                HStack(spacing: 4) {
                    OptionalNumericField(title: "Thickness", value: q.thickness, format: FloatingPointFormatStyle<Double>.number, prompt: "—") {
                        model.quantify.thickness = max($0, 0)
                    }
                    Text("±")
                    OptionalNumericField(title: "Thickness σ", value: q.thicknessSigma, format: FloatingPointFormatStyle<Double>.number, unit: "nm", prompt: "—") {
                        model.quantify.thicknessSigma = max($0, 0)
                    }
                }
            }
            if let chi = q.chiSquared {
                InspectorRow("Fit quality") { Text("χ²ᵣ \(String(format: "%.2f", chi))").monospacedDigit() }
            }
            InspectorSection("Expert", expanded: $model.quantify.expertOpen) {
                ChoiceRow(label: "Estimator", value: $model.quantify.estimator, options: ["Least squares", "Poisson ML"])
                InspectorRow("σ_k") {
                    OptionalNumericField(title: "σ_k", value: q.sigmaK, format: FloatingPointFormatStyle<Double>.number, unit: "%") {
                        model.quantify.sigmaK = min(max($0, 0), 100)
                    }
                }
                InspectorRow("Poly order") { Stepper("\(q.polyOrder)", value: $model.quantify.polyOrder, in: 0...8) }
                InspectorRow("Lock energy axis") { Toggle("Lock energy axis", isOn: $model.quantify.energyLock).labelsHidden().toggleStyle(.checkbox) }
            }
        }
    }
}

/// 5 · Export — a plain (non-prominent) button; the toolbar verb stays Quantify.
struct ExportInspector: View {
    @Bindable var model: SpectroscopyRoomModel
    var onExport: () -> Void = {}
    var body: some View {
        InspectorGroup {
            ChoiceRow(label: "Format", value: $model.export.format, options: ["CSV", "JSON", "PNG (spectrum)"])
            InspectorRow("Include") { Toggle("method and σ terms", isOn: $model.export.includeMethod).toggleStyle(.checkbox) }
            InspectorActionRow { Button("Export…", action: onExport) }
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
