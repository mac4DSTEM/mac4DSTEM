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
                Text("Mean ± spread of each map's pixels, in \(model.mapMode.units). The maps are per-pixel and carry their badges; the Results table has the fitted composition.")
                    .font(.caption).foregroundStyle(.secondary).gridCellColumns(max(2 + maps.count, 2)).padding(.top, 6)
            }
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Region table")
        .task(id: key) { await compute() }
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
