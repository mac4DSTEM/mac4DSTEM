import SwiftUI

/// Pure composite for the ColorMix map: each ticked element's map is tinted with its colour
/// and added; the sum is clamped to 1 per channel. Presentation arithmetic, not a result.
enum ColorMixComposite {
    typealias RGB = (r: Double, g: Double, b: Double)
    /// `colors` is resolved once per draw by the caller (one entry per ticked tile).
    static func rgb(at index: Int, tiles: [MapTile], mixed: Set<Int>, colors: [Int: RGB]) -> RGB {
        var r = 0.0, g = 0.0, b = 0.0
        for t in tiles where mixed.contains(t.z) && index < t.values.count {
            guard let c = colors[t.z] else { continue }
            let v = Double(t.values[index])
            r += c.r * v; g += c.g * v; b += c.b * v
        }
        return (min(r, 1), min(g, 1), min(b, 1))
    }
}

/// The map pane: header (title, draw tools, "Map shows"), the composite with scale bar,
/// and the element tile strip beneath.
struct ColorMixMapView: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 6) {
                composite
                ElementTileStrip(model: model)
            }.padding(8)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Map · \(model.mapUnits)").font(.callout.weight(.semibold)).lineLimit(1).help("Map · \(model.mapLabel)")
            // an at% map carries the same validation badge as the table (ADR 054 §3)
            if model.mapMode == .atomic && model.unvalidated { UnvalidatedBadge() }
            Spacer(minLength: 4)
            Picker("Draw tool", selection: $model.drawTool) {
                ForEach(DrawTool.allCases, id: \.self) { Image(systemName: $0.symbol).tag($0).help($0.rawValue.capitalized) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            Picker("Map shows", selection: $model.mapMode) {
                ForEach(MapMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize().help("Map shows")
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    private var composite: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.05, blue: 0.14)))
            guard let t = model.tiles.first else { return }
            let cw = size.width / CGFloat(t.width), ch = size.height / CGFloat(t.height)
            var colors: [Int: ColorMixComposite.RGB] = [:]       // palette resolved once per draw
            for tile in model.tiles where model.mixed.contains(tile.z) { colors[tile.z] = Self.rgb(ElementPalette.color(tile.z)) }
            for y in 0..<t.height { for x in 0..<t.width {
                let c = ColorMixComposite.rgb(at: y * t.width + x, tiles: model.tiles, mixed: model.mixed, colors: colors)
                if c.r + c.g + c.b < 0.02 { continue }
                ctx.fill(Path(CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw + 0.5, height: ch + 0.5)),
                         with: .color(Color(red: c.r, green: c.g, blue: c.b)))
            } }
            guard !model.scaleBar.isEmpty else { return }
            let bar = CGRect(x: 10, y: size.height - 14, width: size.width * 0.2, height: 3)
            ctx.fill(Path(bar), with: .color(.white))
            ctx.draw(Text(model.scaleBar).font(.caption).foregroundStyle(.white), at: CGPoint(x: bar.minX, y: bar.minY - 8), anchor: .leading)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: LayoutPolicy.thumbnailMaximumHeight * 1.2)
    }

    static func rgb(_ c: Color) -> (r: Double, g: Double, b: Double) {
        let r = c.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }
}

#Preview("ColorMix map") { ColorMixMapView(model: .fixture).frame(width: 340, height: 420) }
