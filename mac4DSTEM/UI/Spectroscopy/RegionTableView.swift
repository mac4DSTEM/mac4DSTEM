import ShellSpectroscopy
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// The Table tab: the mean of each mixed element map under the whole map and under every drawn region, with the spread of its pixels, in the
/// maps' own unit. The numbers are ImagoCore's labelled statistics (`RegionMapTable`). They are the maps' means, not the pooled fit's
/// composition with a sigma (the Results table is that), and they inherit the maps' badges.
struct RegionTableView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var rows: [RegionMapTable.Row] = []

    /// What the table depends on, as one value: a change recomputes it.
    private var key: String {
        "\(model.tileRevision)|\(model.mapMode.rawValue)|\(model.mixed.sorted())|\(model.tiles.map(\.z))|" +
            model.regions.filter(\.isDrawn).map { "\($0.id):\(String(describing: model.drawnShapes[$0.id]))" }.joined(separator: ";")
    }

    var body: some View {
        let maps = model.tabMaps
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 14) {
                if !model.regionFits.isEmpty || !model.regionFitNotes.isEmpty { fittedComposition }
                mapMeans(maps)
            }
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Region table")
        .task(id: key) { await compute() }
    }

    // MARK: fitted composition (SpectroKit's per-region result)

    /// The pooled fit of the whole map and of each drawn region, one row each, an element per column, in the Results table's unit. The fit is
    /// the Quantify verb's method on each region's own spectrum; the numbers carry the fit's `validation` word.
    private var fittedComposition: some View {
        let rows = model.regions.filter { ($0.isDrawn || $0.id == 0) && (model.regionFits[$0.id] != nil || model.regionFitNotes[$0.id] != nil) }
        let elements = model.regionFits.values.first?.elements ?? []
        let unit = model.unit
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Fitted composition").font(.callout.weight(.semibold))
                Text(unit == .atomic ? "at%" : "wt%").font(.caption).foregroundStyle(.secondary)
                if model.regionFits.values.contains(where: { $0.validation == "none" }) { UnvalidatedBadge() }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Region").font(.caption.weight(.semibold))
                    Text("px").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                    ForEach(elements, id: \.self) { Text($0).font(.caption.weight(.semibold)) }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows) { row in
                    GridRow {
                        Text(model.regionName(row.id)).font(.callout)
                        Text(ResultFormat.counts(Double(row.pixels))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        if let fit = model.regionFits[row.id] {
                            ForEach(elements, id: \.self) { symbol in
                                let line = fit.lines.first { $0.element == symbol }
                                Text(Self.fitText(line, unit: unit)).font(.callout.monospacedDigit())
                                    .help((line?.flags ?? []).joined(separator: "; "))
                            }
                        } else {
                            Text(model.regionFitNotes[row.id] ?? "no fit").font(.caption).foregroundStyle(.secondary)
                                .gridCellColumns(max(elements.count, 1))
                        }
                    }
                }
            }
            if let note = model.regionFits.values.compactMap(\.abundanceRefusal).first ?? model.regionFits.values.compactMap(\.abundanceCaveat).first {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fitted composition")
    }

    /// "36.2 ± 1.1": the row's at% or wt% with its sigma (three significant digits); "n.d." for a line held at zero, a dash for no number.
    static func fitText(_ line: RegionQuantResult.Line?, unit: AbundanceUnit) -> String {
        guard let line else { return "\u{2013}" }
        let value = unit == .atomic ? line.atomicPercent : line.weightPercent
        let sigma = unit == .atomic ? line.atomicSigma : line.weightSigma
        let style = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...3)).locale(Locale(identifier: "en_US"))
        // No at% or wt% (a single element, no k): the net counts, named, rather than a dash that says nothing.
        guard let value, value.isFinite else {
            guard let net = line.netCounts, net.isFinite else { return "\u{2013}" }
            return net.formatted(style) + (line.netSigma.flatMap { $0.isFinite ? " \u{00B1} " + $0.formatted(style) : nil } ?? "") + " net"
        }
        if line.atBound { return "n.d." }
        guard let sigma, sigma.isFinite else { return value.formatted(style) }
        return "\(value.formatted(style)) \u{00B1} \(sigma.formatted(style))"
    }

    // MARK: map means

    @ViewBuilder private func mapMeans(_ maps: [(tile: MapTile, values: [Float])]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Map means").font(.callout.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Region").font(.caption.weight(.semibold))
                    Text("px").font(.caption.weight(.semibold)).gridColumnAlignment(.trailing)
                    ForEach(maps, id: \.tile.z) { t, _ in
                        HStack(spacing: 4) {
                            Circle().fill(model.color(t.z)).frame(width: 7, height: 7)
                            Text(PeriodicLayout.symbol(t.z)).font(.caption.weight(.semibold))
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.name).font(.callout)
                        Text(ResultFormat.counts(Double(row.pixels))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            Text(Self.text(cell)).font(.callout.monospacedDigit())
                        }
                    }
                }
                if rows.isEmpty { Text("Draw a region on the ColorMix to compare it with the whole map.").font(.callout).foregroundStyle(.secondary) }
                Text("Mean ± spread of each map's pixels, in \(model.mapMode.units). The maps are per-pixel and carry their badges.")
                    .font(.caption).foregroundStyle(.secondary).gridCellColumns(max(2 + maps.count, 2)).padding(.top, 6)
                    .frame(maxWidth: 420, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compute() async {
        let tab = model.tabMaps
        guard let first = tab.first?.tile else { rows = []; return }
        let w = first.width, h = first.height
        let maps = tab.map(\.values)
        var regions: [(name: String, mask: [Bool]?)] = [("Whole map", nil)]
        for r in model.regions where r.isDrawn { if let shape = model.drawnShapes[r.id] { regions.append((model.regionName(r.id), shape.mask(nx: w, ny: h))) } }
        let result = await Task.detached(priority: .userInitiated) { RegionMapTable.rows(maps: maps, width: w, height: h, regions: regions) }.value
        if !Task.isCancelled { rows = result }
    }

    /// "36.2 ± 4.1": three significant digits each; a dash where the region holds nothing.
    static func text(_ cell: RegionMapTable.Cell?) -> String {
        guard let cell, cell.mean.isFinite else { return "\u{2013}" }
        let style = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...3)).locale(Locale(identifier: "en_US"))
        return "\(cell.mean.formatted(style)) \u{00B1} \(cell.spread.formatted(style))"
    }
}
