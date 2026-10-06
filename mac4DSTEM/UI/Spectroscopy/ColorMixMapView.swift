import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

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

/// The mixed map as one bitmap (a pixel per scan pixel), built once per change of tiles or ticks and drawn scaled with
/// nearest-neighbour sampling: a 256 x 256 map is one image draw, not 65 536 paths. When no element is ticked the
/// scan image (HAADF, grey) stands in, so regions can be drawn before any element is chosen.
enum ColorMixRaster {
    static func image(tiles: [MapTile], mixed: Set<Int>, colors: [Int: ColorMixComposite.RGB],
                      backdrop: [Float], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let ticked = tiles.contains { mixed.contains($0.z) }
        guard ticked || backdrop.count == width * height else { return nil }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        for i in 0..<(width * height) {
            let c: ColorMixComposite.RGB
            if ticked { c = ColorMixComposite.rgb(at: i, tiles: tiles, mixed: mixed, colors: colors) }
            else { let g = Double(backdrop[i]); c = (g, g, g) }
            bytes[i * 4] = q(c.r); bytes[i * 4 + 1] = q(c.g); bytes[i * 4 + 2] = q(c.b)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The bitmap, kept until the tiles (by revision), the ticks, the grid or the backdrop change. A reference type held in
/// `@State`: the view's body asks it for the image and a draw of the same state costs nothing.
final class ColorMixRasterCache {
    struct Key: Equatable { var revision: Int, mixed: Set<Int>, width: Int, height: Int, backdropCount: Int }
    private var key: Key?
    private var image: CGImage?
    private(set) var builds = 0
    func image(for k: Key, build: () -> CGImage?) -> CGImage? {
        if key != k { image = build(); key = k; builds += 1 }
        return image
    }
}

/// The map pane: header (title, draw tools, "Map shows"), the composite with scale bar,
/// and the element tile strip beneath. A drag on the composite draws a region (rectangle or ellipse).
struct ColorMixMapView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var drag: (from: CGPoint, to: CGPoint)?
    @State private var rasterCache = ColorMixRasterCache()

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
            Text("Map · \(model.mapUnits)").font(.callout.weight(.semibold)).lineLimit(1)
                .help(model.isLive ? "Window net counts. at% is computed on pooled regions only (the table), never per pixel." : "Map · \(model.mapLabel)")
            // an at% map carries the same validation badge as the table (ADR 054 §3)
            if model.mapMode == .atomic && model.unvalidated { UnvalidatedBadge() }
            Spacer(minLength: 4)
            Picker("Draw tool", selection: $model.drawTool) {
                ForEach(DrawTool.drawable, id: \.self) { Image(systemName: $0.symbol).tag($0).help($0.rawValue.capitalized) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            // At% maps are never computed for a real spectrum image (ADR 054 item 3: at% on pooled regions only), so the
            // choice is not offered there; the map is the window net counts and the header says what at% is computed on.
            if model.hasFit && !model.isLive {
                Picker("Map shows", selection: $model.mapMode) {
                    ForEach(MapMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize().help("Map shows")
            }
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    /// Grid size the map draws on: the tiles', else the room's own grid (the HAADF backdrop's).
    private var grid: (w: Int, h: Int) {
        if let t = model.tiles.first { return (t.width, t.height) }
        return (model.gridWidth, model.gridHeight)
    }

    private var composite: some View {
        let g = grid
        var colors: [Int: ColorMixComposite.RGB] = [:]       // palette resolved once per body
        for tile in model.tiles where model.mixed.contains(tile.z) { colors[tile.z] = Self.rgb(ElementPalette.color(tile.z)) }
        let key = ColorMixRasterCache.Key(revision: model.tileRevision, mixed: model.mixed, width: g.w, height: g.h,
                                          backdropCount: model.backdrop.count)
        let raster = rasterCache.image(for: key) {
            ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors,
                                 backdrop: model.backdrop, width: g.w, height: g.h)
        }
        return Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.05, blue: 0.14)))
            guard g.w > 0, g.h > 0 else { return }
            if let raster {
                ctx.draw(ctx.resolve(Image(decorative: raster, scale: 1).interpolation(.none)), in: CGRect(origin: .zero, size: size))
            }
            let cw = size.width / CGFloat(g.w), ch = size.height / CGFloat(g.h)
            func rect(_ r: PixelRect) -> CGRect {
                CGRect(x: CGFloat(r.x0) * cw, y: CGFloat(r.y0) * ch, width: CGFloat(r.width) * cw, height: CGFloat(r.height) * ch)
            }
            func outline(_ shape: SpectrumRegionShape) {
                let p: Path
                switch shape { case .rectangle(let r): p = Path(rect(r)); case .ellipse(let r): p = Path(ellipseIn: rect(r)) }
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            if let o = model.regionOutline { outline(o) }
            if let d = drag, let r = Self.pixelRect(d.from, d.to, size: size, grid: g) {
                outline(model.drawTool == .ellipse ? .ellipse(r) : .rectangle(r))
            }
            guard !model.scaleBar.isEmpty else { return }
            let bar = CGRect(x: 10, y: size.height - 14, width: size.width * 0.2, height: 3)
            ctx.fill(Path(bar), with: .color(.white))
            ctx.draw(Text(model.scaleBar).font(.caption).foregroundStyle(.white), at: CGPoint(x: bar.minX, y: bar.minY - 8), anchor: .leading)
        }
        .aspectRatio(g.w > 0 && g.h > 0 ? CGFloat(g.w) / CGFloat(g.h) : 1, contentMode: .fit)
        .frame(maxWidth: LayoutPolicy.thumbnailMaximumHeight * 1.2)
        .overlay {
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { v in drag = (v.startLocation, v.location) }
                        .onEnded { v in
                            drag = nil
                            guard model.isLive, let r = Self.pixelRect(v.startLocation, v.location, size: geo.size, grid: g) else { return }
                            model.onDrawRegion?(model.drawTool == .ellipse ? .ellipse(r) : .rectangle(r))
                        })
            }
        }
    }

    /// The pixel rectangle two points of the drawn map span (both end pixels included); nil off the grid.
    static func pixelRect(_ a: CGPoint, _ b: CGPoint, size: CGSize, grid: (w: Int, h: Int)) -> PixelRect? {
        guard grid.w > 0, grid.h > 0, size.width > 0, size.height > 0 else { return nil }
        func px(_ p: CGPoint) -> (x: Int, y: Int) {
            (min(max(Int(p.x / size.width * CGFloat(grid.w)), 0), grid.w - 1),
             min(max(Int(p.y / size.height * CGFloat(grid.h)), 0), grid.h - 1))
        }
        return PixelRect.spanning(px(a), px(b), nx: grid.w, ny: grid.h)
    }

    static func rgb(_ c: Color) -> (r: Double, g: Double, b: Double) {
        let r = c.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }
}

#Preview("ColorMix map") { ColorMixMapView(model: .fixture).frame(width: 340, height: 420) }
