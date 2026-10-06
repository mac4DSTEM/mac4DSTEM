import SwiftUI

/// Number formatting for the table; separate so the pure part is testable.
enum ResultFormat {
    static func plusMinus(_ v: Double, _ s: Double, digits: Int) -> String {
        String(format: "%.\(digits)f ± %.\(digits)f", v, s)
    }
    /// The k-free ratio and abundance cells of a row. Until WP3 fits a spectrum there is neither: "—", never a number.
    static func fitCells(_ row: ResultRow, unit: AbundanceUnit, hasFit: Bool) -> (kFree: String, abundance: String) {
        guard hasFit else { return ("—", "—") }
        return (row.kFreeSigma.map { String(format: "%.4f ± %.4f", row.kFreeRatio, $0) } ?? "1",
                unit == .atomic ? plusMinus(row.atPercent, row.atSigma, digits: 1) : plusMinus(row.wtPercent, row.wtSigma, digits: 1))
    }
    /// 412380 -> "412 380" (thin grouping, as the mock prints counts).
    static func counts(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "\u{202F}"; f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US"); f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }
}

/// The results table: header (title, "unvalidated" badge, at%/wt% control), one row per
/// quantified element, expandable σ terms, the Mg/Si k-free ratio line (ADR 054 §3: the k-free ratio column
/// precedes at%, which is badged).
struct SpectroscopyResultsTable: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ViewThatFits(in: .vertical) {
                tableBody
                ScrollView(.vertical) { tableBody }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tableBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                Group {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text("Element"); Text("Net counts ± σ"); Text("k-free ratio"); Text("\(model.unit.rawValue) ± σ")
                        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(model.results) { row in
                            GridRow {
                                HStack(spacing: 4) {
                                    Image(systemName: model.expandedRows.contains(row.z) ? "chevron.down" : "chevron.right")
                                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                                    Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(ElementPalette.color(row.z))
                                    Text(PeriodicLayout.symbol(row.z)).fontWeight(.semibold)
                                }
                                Text(row.failure != nil ? "—" : "\(ResultFormat.counts(row.netCounts)) ± \(ResultFormat.counts(row.netSigma))")
                                // No fit yet (WP3): no k-free ratio and no at%, never a placeholder number.
                                let cells = ResultFormat.fitCells(row, unit: model.unit, hasFit: model.hasFit)
                                Text(cells.kFree)
                                Text(cells.abundance).fontWeight(.semibold)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { model.toggleExpanded(row.z) } }
                            .monospacedDigit()
                            if let note = row.failure ?? row.conflictNote {
                                GridRow {
                                    Label(note, systemImage: row.failure != nil ? "xmark.circle" : "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                                        .padding(.leading, 8)
                                        .gridCellColumns(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if model.expandedRows.contains(row.z) {
                                GridRow {
                                    Text("\(PeriodicLayout.symbol(row.z)) σ terms: \(row.sigmaTerms)")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .padding(.leading, 8)
                                        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.5)).frame(width: 2) }
                                        .gridCellColumns(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if model.isLive && model.results.isEmpty {
                        Text("Pick elements in the periodic table (Elements & maps) to see their window net counts here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !model.resultsFooter.isEmpty {
                        Text(model.resultsFooter).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.hasFit, let r = model.ratioLine {
                        Divider()
                        (Text("\(r.label) ") + Text(String(format: "%.3f ± %.3f", r.value, r.sigma)).fontWeight(.bold).monospacedDigit()
                         + Text(" · \(r.note)").font(.caption).foregroundStyle(.secondary))
                            .font(.callout)
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.resultsTitle).font(.callout.weight(.semibold)).lineLimit(1)
            if model.hasFit && model.unvalidated { UnvalidatedBadge() }
            Spacer(minLength: 4)
            if model.hasFit {
                Picker("Unit", selection: $model.unit) {
                    ForEach(AbundanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }
}

#Preview("Results") {
    let m = SpectroscopyRoomModel.fixture
    m.expandedRows = [12]
    return SpectroscopyResultsTable(model: m).frame(width: 440, height: 300)
}
