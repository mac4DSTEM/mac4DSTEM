import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Pure composite for the ColorMix map: each ticked element's map is tinted with its colour
/// and added; the sum is clamped to 1 per channel. Presentation arithmetic, not a result.
/// `displays` is each ticked map's own contrast window and gamma (the active map's popover): changing one map's changes
/// only that map's contribution.
enum ColorMixComposite {
    typealias RGB = (r: Double, g: Double, b: Double)
    /// `colors` is resolved once per draw by the caller (one entry per ticked tile).
    static func rgb(at index: Int, tiles: [MapTile], mixed: Set<Int>, colors: [Int: RGB], displays: [Int: MapDisplay] = [:]) -> RGB {
        var r = 0.0, g = 0.0, b = 0.0
        for t in tiles where mixed.contains(t.z) && !t.proposed && index < t.values.count {
            guard let c = colors[t.z] else { continue }
            let raw = t.values[index]
            let v = Double(displays[t.z].map { $0.apply(raw) } ?? raw)
            r += c.r * v; g += c.g * v; b += c.b * v
        }
        return (min(r, 1), min(g, 1), min(b, 1))
    }
}

/// A bitmap of `width x height` pixels from a per-pixel colour, drawn scaled with nearest-neighbour sampling: a map is one
/// image draw, not a path per scan pixel.
enum MapBitmap {
    static func image(width: Int, height: Int, pixel: (Int) -> (UInt8, UInt8, UInt8)) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let c = pixel(i)
            bytes[i * 4] = c.0; bytes[i * 4 + 1] = c.1; bytes[i * 4 + 2] = c.2
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    static func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
}

/// The mixed map as one bitmap (a pixel per scan pixel). When no element is ticked the scan image (HAADF, grey) stands in,
/// so regions can be drawn before any element is chosen.
enum ColorMixRaster {
    static func image(tiles: [MapTile], mixed: Set<Int>, colors: [Int: ColorMixComposite.RGB],
                      backdrop: [Float], width: Int, height: Int, displays: [Int: MapDisplay] = [:]) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let ticked = tiles.contains { mixed.contains($0.z) && !$0.proposed }
        guard ticked || backdrop.count == width * height else { return nil }
        return MapBitmap.image(width: width, height: height) { i in
            let c: ColorMixComposite.RGB
            if ticked { c = ColorMixComposite.rgb(at: i, tiles: tiles, mixed: mixed, colors: colors, displays: displays) }
            else { let g = Double(backdrop[i]); c = (g, g, g) }
            return (MapBitmap.q(c.r), MapBitmap.q(c.g), MapBitmap.q(c.b))
        }
    }
}

/// One element's tile: black to the element's colour by the map's value, after its contrast window and gamma.
enum ElementTileRaster {
    static func image(tile: MapTile, color: ColorMixComposite.RGB, display: MapDisplay) -> CGImage? {
        guard tile.width > 0, tile.height > 0, tile.values.count == tile.width * tile.height else { return nil }
        return MapBitmap.image(width: tile.width, height: tile.height) { i in
            let v = Double(display.apply(tile.values[i]))
            return (MapBitmap.q(color.r * v), MapBitmap.q(color.g * v), MapBitmap.q(color.b * v))
        }
    }

    /// The HAADF tile: the scan image through the chosen colormap (`Colormaps.lutRGBA`), after its contrast window and gamma.
    static func haadf(values: [Float], width: Int, height: Int, colormap: ColormapKind, display: MapDisplay) -> CGImage? {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        let lut = Colormaps.lutRGBA(colormap)
        return MapBitmap.image(width: width, height: height) { i in
            let k = min(255, max(0, Int((display.apply(values[i]) * 255).rounded())))
            return (lut[k * 4], lut[k * 4 + 1], lut[k * 4 + 2])
        }
    }
}

/// The ColorMix bitmap, kept until the tiles (by revision), the ticks, the colours, the contrast, the grid or the backdrop
/// change. A reference type held in `@State`: the view's body asks it for the image and a draw of the same state costs nothing.
final class ColorMixRasterCache {
    struct Key: Equatable {
        var revision: Int, mixed: Set<Int>, width: Int, height: Int, backdropCount: Int
        /// The colours and contrast windows of the ticked maps (`MapStyle.stamp`); 0 when the caller sets none.
        var style: Int = 0
    }
    private var key: Key?
    private var image: CGImage?
    private(set) var builds = 0
    func image(for k: Key, build: () -> CGImage?) -> CGImage? {
        if key != k { image = build(); key = k; builds += 1 }
        return image
    }
}

/// The per-tile bitmaps (HAADF and each element), each rebuilt only when its own map, colour or display changed.
final class MapTileRasterCache {
    struct Key: Equatable { var revision: Int, style: Int, count: Int }
    private var entries: [ActiveMap: (Key, CGImage?)] = [:]
    private(set) var builds = 0
    func image(_ map: ActiveMap, key: Key, build: () -> CGImage?) -> CGImage? {
        if let e = entries[map], e.0 == key { return e.1 }
        let img = build()
        entries[map] = (key, img)
        builds += 1
        return img
    }
}

/// What a map's look depends on, folded to one Int for the caches' keys.
enum MapStyle {
    static func stamp(color: ColorMixComposite.RGB?, display: MapDisplay, colormap: ColormapKind? = nil) -> Int {
        var h = Hasher()
        if let c = color { h.combine(c.r); h.combine(c.g); h.combine(c.b) }
        h.combine(display.lo); h.combine(display.hi); h.combine(display.gamma)
        h.combine(colormap?.rawValue ?? "")
        return h.finalize()
    }
}
