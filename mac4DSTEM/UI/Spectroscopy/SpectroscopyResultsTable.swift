import SwiftUI

/// Number formatting for the table; separate so the pure part is testable.
enum ResultFormat {
    static func plusMinus(_ v: Double, _ s: Double, digits: Int) -> String {
        String(format: "%.\(digits)f ± %.\(digits)f", v, s)
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
                                Text("\(ResultFormat.counts(row.netCounts)) ± \(ResultFormat.counts(row.netSigma))")
                                Text(row.kFreeSigma.map { String(format: "%.4f ± %.4f", row.kFreeRatio, $0) } ?? "1")
                                Text(model.unit == .atomic ? ResultFormat.plusMinus(row.atPercent, row.atSigma, digits: 1)
                                                           : ResultFormat.plusMinus(row.wtPercent, row.wtSigma, digits: 1)).fontWeight(.semibold)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { model.toggleExpanded(row.z) } }
                            .monospacedDigit()
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
                    if let r = model.ratioLine {
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
            if model.unvalidated { UnvalidatedBadge() }
            Spacer(minLength: 4)
            Picker("Unit", selection: $model.unit) {
                ForEach(AbundanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
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
