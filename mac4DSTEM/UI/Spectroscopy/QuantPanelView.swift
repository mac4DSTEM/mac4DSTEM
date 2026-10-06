import SwiftUI
import UniformTypeIdentifiers
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
        "\(unit.rawValue) ± σ" + (noAbsorption ? " · no absorption" : "")
    }
    /// R6: the Net ± σ cell as parts, so it is one line at the panel's minimum width and never wraps ("88 515 / ± 413" in
    /// drive 2): grouped digits with a narrow no-break space (U+202F) around the sign. A long pair (more than `compactAbove`
    /// characters of digits and grouping) sets σ in a smaller secondary style rather than wrapping or truncating.
    static let compactAbove = 11
    static func netCell(_ net: Double, _ sigma: Double) -> (net: String, sigma: String, separator: String, compact: Bool) {
        let n = counts(net), s = counts(sigma)
        return (n, s, "\u{202F}\u{00B1}\u{202F}", n.count + s.count > compactAbove)
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    static func counts(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "\u{202F}"; f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US"); f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }
}

/// The quantification panel beside the spectrum (ADR 056): Element · Net ± σ · at% ± σ, "unvalidated" in the header with
/// Export…, the k-free ratio line, the unlisted-line check, a whole-map comparison line, and one method line that opens onto
/// the fit's own footer (the fit range and its sensitivity, the k source, the absorption). A row's warnings and its σ terms sit
/// behind a "!" and the row's hover, not under every row.
struct QuantPanelView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var methodOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ViewThatFits(in: .vertical) {
                content
                ScrollView(.vertical) { content }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("spectroscopy.quant")
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

    // MARK: header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Region").font(.callout.weight(.semibold)).lineLimit(1)
            if model.hasFit && model.unvalidated { UnvalidatedBadge() }
            Spacer(minLength: 4)
            ExportMenu(model: model)
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    // MARK: content

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.results.isEmpty {
                Text(model.isLive ? "Pick elements in the periodic table to see their window net counts here." : "No results yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else { table }
            if let r = model.ratioLine, model.hasFit {
                HStack(spacing: 4) {
                    Text(r.label)
                    Text(String(format: "%.3f \u{00B1} %.3f", r.value, r.sigma)).fontWeight(.semibold).monospacedDigit()
                    Text("\u{2014} k-free").foregroundStyle(.secondary)
                }
                .font(.callout).help(r.note)
            }
            if model.hasFit, let q = model.quantify.quality {
                // R7 (wp3e item 2): the misfit is a result, not the tail of a caption: always on its own line under the table.
                Text(q).font(.callout).fontWeight(.semibold).monospacedDigit()
                    .help("Reduced chi-square of this fit. Every \u{03C3} shown is counting statistics at 1; the farther this is above 1, the more the model misses the spectrum beyond counting noise.")
            }
            if let u = model.unlisted { unlisted(u) }
            if let why = model.fitFailure { quietLabel(why, "xmark.circle") }
            if let note = model.abundanceNote { quietLabel(note, "info.circle") }
            if !model.results.isEmpty && !model.hasFit && model.fitFailure == nil {
                Text("Quantify fits this region and adds at%.").font(.caption).foregroundStyle(.secondary)
            }
            if model.hasFit, !model.fitFooter.isEmpty || !model.resultsFooter.isEmpty || !model.fitWarnings.isEmpty { methodDisclosure }
            if let line = model.wholeMapLine { Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func quietLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Element"); Text("Net \u{00B1} \u{03C3}")
                Menu {
                    Picker("Unit", selection: $model.unit) { ForEach(AbundanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { Text(ResultFormat.abundanceHeader(unit: model.unit, noAbsorption: model.abundanceWithoutAbsorption)) }
                .menuStyle(.borderlessButton).fixedSize().help("at% or wt%")
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
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
                    Text(ResultFormat.fitCells(row, unit: model.unit, hasFit: model.hasFit).abundance).fontWeight(.semibold)
                }
                .monospacedDigit()
                .help("\(PeriodicLayout.symbol(row.z)) \u{03C3} terms: \(model.unit == .weight ? (row.sigmaTermsWeight ?? row.sigmaTerms) : row.sigmaTerms)")
            }
        }
    }

    /// One line, monospaced digits; a long pair sets σ smaller and secondary (`ResultFormat.netCell`).
    private func netCell(_ row: ResultRow) -> some View {
        let c = ResultFormat.netCell(row.netCounts, row.netSigma)
        let t: Text = row.failure != nil ? Text("\u{2014}")
            : Text(c.net) + Text(c.separator).foregroundStyle(.secondary)
              + (c.compact ? Text(c.sigma).font(.caption).foregroundStyle(.secondary) : Text(c.sigma))
        return t.lineLimit(1).minimumScaleFactor(0.7)
    }

    private func unlisted(_ u: UnlistedLineNote) -> some View {
        HStack(spacing: 6) {
            Label(u.text, systemImage: u.checking ? "hourglass" : (u.candidates.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(u.detail ?? u.text)
            if !u.candidates.isEmpty {
                Button("Add as Fit only") { model.onAddUnlistedAsFitOnly?() }
                    .help("List the named elements as Fit only: their lines are modelled, they get no at%.")
                Button("Dismiss") { model.onDismissUnlisted?() }
                    .help("Switch the named elements Off: they are not named again for this spectrum image.")
            }
        }
        .controlSize(.small)
    }

    /// One method line (estimator, continuum, fit quality) that opens onto the fit's own footer lines and warnings.
    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodOpen) {
            VStack(alignment: .leading, spacing: 3) {
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
                Text(model.fitFooter.isEmpty ? "Method" : model.fitFooter).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                if !model.fitWarnings.isEmpty {
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                        .help("\(model.fitWarnings.count) warning\(model.fitWarnings.count == 1 ? "" : "s"): open the method line")
                }
            }
        }
        .font(.caption)
    }
}

/// The panel header's Export…: the results table as CSV and the method as JSON, written from the last fit
/// (`SpectroscopyExport`, Core). Before a fit there is nothing to write and the menu is off.
struct ExportMenu: View {
    @Bindable var model: SpectroscopyRoomModel
    static let csvTitle = "Results CSV\u{2026}", jsonTitle = "Method JSON\u{2026}"

    var body: some View {
        let e = model.export
        Menu("Export\u{2026}") {
            Button(Self.csvTitle) { if let t = e.csv { model.pendingExport = PendingExport(text: t, isJSON: false, name: e.fileStem) } }
                .help("The results table: element, line, net counts, k-free ratio, at%, each with its \u{03C3}, the flags and the estimator")
            Button(Self.jsonTitle) { if let t = e.methodJSON { model.pendingExport = PendingExport(text: t, isJSON: true, name: e.fileStem + "-method") } }
                .help("The quantification method in its own sorted-keys encoding, with its SHA-256")
        }
        .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
        .disabled(e.csv == nil || e.methodJSON == nil)
        .help(e.csv == nil ? "Once Quantify has run, this writes the results table as CSV and the method as JSON." : "Write the results table or the method")
        .accessibilityIdentifier("spectroscopy.export")
    }
}

#Preview("Quant panel") {
    let m = SpectroscopyRoomModel.fixture
    return QuantPanelView(model: m).frame(width: 360, height: 300)
}
