import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// Number formatting for the table; separate so the pure part is testable.
enum ResultFormat {
    static func plusMinus(_ v: Double, _ s: Double, digits: Int) -> String {
        String(format: "%.\(digits)f ± %.\(digits)f", v, s)
    }
    /// The k-free ratio and abundance cells of a row. Until WP3 fits a spectrum there is neither: "—", never a number.
    static func fitCells(_ row: ResultRow, unit: AbundanceUnit, hasFit: Bool) -> (kFree: String, abundance: String) {
        guard hasFit else { return ("—", "—") }
        let abundance = row.hasAbundance
            ? (unit == .atomic ? plusMinus(row.atPercent, row.atSigma, digits: 1) : plusMinus(row.wtPercent, row.wtSigma, digits: 1)) : "—"
        guard row.hasKFree else { return ("—", abundance) }
        return (row.kFreeSigma.map { String(format: "%.4f ± %.4f", row.kFreeRatio, $0) } ?? "1",
                abundance)
    }
    /// The abundance column's header; at% computed without the absorption correction says so in the column itself.
    static func abundanceHeader(unit: AbundanceUnit, noAbsorption: Bool) -> String {
        "\(unit.rawValue) ± σ" + (noAbsorption ? " " + noAbsorptionLabel : "")
    }
    /// The honesty label of an at% computed without the absorption correction.
    static let noAbsorptionLabel = "· no absorption"
    /// R6: the Net ± σ cell as parts, so it is one line at the panel's minimum width and never wraps ("88 515 / ± 413" in
    /// drive 2): grouped digits with a narrow no-break space (U+202F) around the sign. A long pair (more than `compactAbove`
    /// characters of digits and grouping) sets σ in a smaller secondary style rather than wrapping or truncating.
    static let compactAbove = 11
    static func netCell(_ net: Double, _ sigma: Double) -> (net: String, sigma: String, separator: String, compact: Bool) {
        let n = counts(net), s = counts(sigma)
        return (n, s, "\u{202F}\u{00B1}\u{202F}", n.count + s.count > compactAbove)
    }
    /// Narrow-space grouping (`SpectrumReadout.grouped`, kept beside the spectrum logic so tools/ harnesses compile without views).
    nonisolated static func grouped(_ v: Double, fraction: ClosedRange<Int> = 0...0, locale: Locale) -> String {
        SpectrumReadout.grouped(v, fraction: fraction, locale: locale)
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    nonisolated static func counts(_ v: Double) -> String { SpectrumReadout.counts(v) }
}

/// The inspector's Results section (spec 2 D-4; it was the panel beside the spectrum): the unvalidated badge in the first row,
/// Element · Net ± σ · at% ± σ with "· no absorption" in the column header, the k-free ratio line, the fit quality, the
/// unlisted-line / at% caveat, a whole-map comparison line, and one Method line that opens onto the fit's own footer (the fit
/// range and its sensitivity, the k source, the absorption). A row's warnings and its σ terms sit behind a "!" and the row's hover.
/// Rows only: the section's own stack spaces them (`InspectorSection`).
struct ResultsSection: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var methodOpen = false

    /// The badge row: a fitted result is unvalidated until a dataset with truth says otherwise (CLAUDE.md, "unvalidated stays labelled").
    static func showsBadge(_ model: SpectroscopyRoomModel) -> Bool { model.hasFit && model.unvalidated }

    var body: some View {
        let block = QuantifyPresentation.unlistedBlock(model.unlisted, abundanceNote: model.abundanceNote)
        let candidates = block.line?.candidates ?? []
        if Self.showsBadge(model) { InspectorRow("Result") { UnvalidatedBadge() } }
        if model.results.isEmpty {
            Text(QuantifyPresentation.emptyText(isLive: model.isLive))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else { table }
        if let r = model.ratioLine, model.hasFit {
            HStack(spacing: 4) {
                Text(r.label)
                Text(String(format: "%.3f \u{00B1} %.3f", r.value, r.sigma)).monospacedDigit()
                Text("\u{2014} k-free").foregroundStyle(.secondary)
            }
            .font(.callout).help(r.note)
        }
        if model.hasFit, let q = model.quantify.quality {
            // UX lane DE (#6): the misfit is a result row like the ratio, regular weight, not a bold caption.
            HStack(spacing: 6) {
                Text("Fit quality")
                Text(QuantifyPresentation.fitQualityValue(q)).monospacedDigit()
            }
            .font(.callout)
            .help("Reduced chi-square of this fit. Every \u{03C3} shown is counting statistics at 1; the farther this is above 1, the more the model misses the spectrum beyond counting noise.")
        }
        // One caveat line; its two buttons live in the Method disclosure below.
        if let u = block.line { caveat(u) }
        if let why = model.fitFailure { quietLabel(why, "xmark.circle") }
        if let note = block.note { quietLabel(note, "info.circle") }
        if !model.results.isEmpty && !model.hasFit && model.fitFailure == nil {
            Text("Quantify fits this region and adds at%.").font(.caption).foregroundStyle(.secondary)
        }
        if (model.hasFit && (!model.fitFooter.isEmpty || !model.resultsFooter.isEmpty || !model.fitWarnings.isEmpty)) || !candidates.isEmpty {
            methodDisclosure(candidates: candidates)
        }
        if let line = model.wholeMapLine { Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }

    private func quietLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Element"); Text("Net \u{00B1} \u{03C3}")
                // The unit menu and, under it, "· no absorption" when the at% was computed without the correction: two lines so the
                // column stays inside the inspector's narrowest width, the label always visible (never a hover).
                VStack(alignment: .leading, spacing: 0) {
                    Menu {
                        Picker("Unit", selection: $model.unit) { ForEach(AbundanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    } label: { Text(ResultFormat.abundanceHeader(unit: model.unit, noAbsorption: false)) }
                    .menuStyle(.borderlessButton).fixedSize().help("at% or wt%")
                    if model.abundanceWithoutAbsorption { Text(ResultFormat.noAbsorptionLabel).accessibilityLabel(ResultFormat.noAbsorptionLabel) }
                }
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            let unit = model.unit, hasFit = model.hasFit   // read once, not in every row's closure
            ForEach(model.results) { row in
                GridRow {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(model.color(row.z))
                        Text(PeriodicLayout.symbol(row.z)).fontWeight(.semibold)
                        if let note = row.failure ?? row.conflictNote {
                            Image(systemName: row.failure != nil ? "xmark.circle" : "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.secondary).help(note)
                                .accessibilityLabel(note)
                        }
                    }
                    netCell(row)
                    Text(ResultFormat.fitCells(row, unit: unit, hasFit: hasFit).abundance).fontWeight(.semibold)
                }
                .monospacedDigit()
                .help("\(PeriodicLayout.symbol(row.z)) \u{03C3} terms: \(unit == .weight ? (row.sigmaTermsWeight ?? row.sigmaTerms) : row.sigmaTerms)")
            }
        }
    }

    /// One line, monospaced digits; a long pair sets σ smaller and secondary (`ResultFormat.netCell`).
    private func netCell(_ row: ResultRow) -> some View {
        let c = ResultFormat.netCell(row.netCounts, row.netSigma)
        let sigma: Text = c.compact ? Text(c.sigma).font(.caption).foregroundStyle(.secondary) : Text(c.sigma)
        let separator = Text(c.separator).foregroundStyle(.secondary)
        let t: Text = row.failure != nil ? Text("\u{2014}")
            : Text("\(Text(c.net))\(separator)\(sigma)")
        return t.lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The unlisted-line / at% caveat as one quiet line (never truncated; the full detail is the hover).
    private func caveat(_ u: UnlistedLineNote) -> some View {
        Label(u.text, systemImage: u.checking ? "hourglass" : (u.candidates.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(u.detail ?? u.text)
    }

    /// "Method": the caveat's two buttons (own row, trailing), then the fit's footer lines and warnings. The fit's one-line
    /// label (estimator, continuum) is the first line inside, so nothing is cut off in a closed label.
    private func methodDisclosure(candidates: [Int]) -> some View {
        DisclosureGroup(isExpanded: $methodOpen) {
            VStack(alignment: .leading, spacing: 4) {
                if !candidates.isEmpty {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button("Add as Fit only") { model.onAddUnlistedAsFitOnly?() }
                            .help("List the named elements as Fit only: their lines are modelled, they get no at%.")
                        Button("Dismiss") { model.onDismissUnlisted?() }
                            .help("Switch the named elements Off: they are not named again for this spectrum image.")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if model.hasFit, !model.fitFooter.isEmpty {
                    Text(model.fitFooter).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(model.resultsFooter.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    Text(String(line)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(model.fitWarnings.enumerated()), id: \.offset) { _, w in
                    Label(w.text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).help(w.detail ?? w.text)
                }
            }
            .textSelection(.enabled).padding(.top, 3)
        } label: {
            HStack(spacing: 6) {
                Text("Method").font(.caption).foregroundStyle(.secondary)
                if !model.fitWarnings.isEmpty || !candidates.isEmpty {
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                        .help(candidates.isEmpty ? "\(model.fitWarnings.count) warning\(model.fitWarnings.count == 1 ? "" : "s"): open Method" : "Unlisted lines: open Method for the choices")
                }
            }
        }
        .font(.caption)
    }
}

#Preview("Results") {
    ScrollView { InspectorGroup { ResultsSection(model: .fixture) }.padding() }.frame(width: 320, height: 500)
}
