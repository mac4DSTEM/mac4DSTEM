import SwiftUI

/// The strip of per-element map thumbnails under the map: a gradient thumbnail in the
/// element's colour, the mix checkbox, and the role as a symbol only (ADR 054 addendum:
/// roles are set in the periodic table, not on the tiles).
struct ElementTileStrip: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tiles) { tile in
                let color = ElementPalette.color(tile.z)
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ElementThumbnail(tile: tile, color: color).frame(height: 30)
                        Toggle("Mix \(PeriodicLayout.symbol(tile.z))", isOn: Binding(
                            get: { model.mixed.contains(tile.z) }, set: { _ in model.toggleMix(tile.z) }))
                            .labelsHidden().toggleStyle(.checkbox).controlSize(.mini).padding(2)
                            .help(tile.notMeasuredWhy.map { "Not in the ColorMix by default (tick it to add): \($0)" } ?? "Show \(PeriodicLayout.symbol(tile.z)) in the ColorMix")
                    }
                    HStack(spacing: 0) {
                        Text(PeriodicLayout.symbol(tile.z)).font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        let role = model.elements.role(tile.z)
                        Image(systemName: role.symbolName).font(.system(size: 8)).foregroundStyle(color)
                            .help(role.title).accessibilityLabel(role.title)
                    }.padding(.horizontal, 4).frame(height: 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            }
        }
    }
}

private struct ElementThumbnail: View {
    let tile: MapTile
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let cw = size.width / CGFloat(tile.width), ch = size.height / CGFloat(tile.height)
            let step = max(1, tile.width / 14)   // thumbnails sub-sample: cost bound
            for y in stride(from: 0, to: tile.height, by: step) {
                for x in stride(from: 0, to: tile.width, by: step) {
                    let v = Double(tile.values[y * tile.width + x])
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw * CGFloat(step) + 0.5, height: ch * CGFloat(step) + 0.5)),
                             with: .color(color.opacity(0.15 + 0.85 * v)))
                }
            }
        }.background(Color.black)
    }
}

#Preview("Tile strip") { ElementTileStrip(model: .fixture).padding().frame(width: 320) }
