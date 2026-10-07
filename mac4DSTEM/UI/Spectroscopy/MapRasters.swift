import SwiftUI
import ImageIO
import CoreText
import UniformTypeIdentifiers
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
        for t in tiles where mixed.contains(t.z) && index < t.values.count {
            guard let c = colors[t.z] else { continue }
            let raw = t.values[index]
            let v = Double(displays[t.z].map { $0.apply(raw) } ?? raw)
            r += c.r * v; g += c.g * v; b += c.b * v
        }
        return (min(r, 1), min(g, 1), min(b, 1))
    }
}

/// The default display window of a map (R8, Velox-like): a robust percentile stretch, not min to max, so one hot pixel or a
/// handful of bright ones cannot push every other pixel to black. Presentation only; the values are untouched.
enum MapContrast {
    /// The 0.5 to 99.5 percent window of the finite values (NaN and infinities ignored), as a `MapDisplay` of gamma 1. Sorted
    /// from at most 65 536 evenly strided samples (exact for any map up to that size). When the stretch collapses (a sparse map
    /// whose 99.5 % is its floor) the window runs to the maximum; a flat or empty map is the identity.
    static func defaultWindow(of values: [Float], low: Double = 0.005, high: Double = 0.995) -> MapDisplay {
        let stride = max(1, values.count / 65_536)
        var s: [Float] = []
        s.reserveCapacity(values.count / stride + 1)
        var i = 0
        while i < values.count { if values[i].isFinite { s.append(values[i]) }; i += stride }
        guard s.count > 1 else { return MapDisplay() }
        s.sort()
        func q(_ p: Double) -> Float { s[min(s.count - 1, max(0, Int((p * Double(s.count - 1)).rounded())))] }
        let lo = q(low)
        var hi = q(high)
        if hi <= lo { hi = s[s.count - 1] }
        guard hi > lo else { return MapDisplay() }
        return MapDisplay(lo: lo, hi: hi, gamma: 1)
    }
}

/// The scale bar of a map (R8, Velox-style): a round length (1, 2 or 5 times a power of ten) near a target on-screen size, in the
/// unit the reader gave (nm, \u{00B5}m, \u{00C5}...). Pure: the pixel size comes from the file (Velox metres, GMS axis calibration);
/// a file that states none gets no bar, none is invented.
enum MapScaleBar {
    struct Plan: Equatable { var label: String; var lengthPoints: Double }

    /// Nanometres per unit for the length units a reader reports; nil for anything else.
    static func nanometres(per unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "nm": 1
        case "\u{00B5}m", "\u{03BC}m", "um", "micron", "microns": 1000
        case "m": 1e9
        case "mm": 1e6
        case "\u{00C5}", "A", "Angstrom": 0.1
        case "pm": 0.001
        default: nil
        }
    }

    /// `pixelSize` per scan pixel in `unit`; `pointsPerPixel` the map's drawn size; the bar aims at `targetPoints`.
    static func plan(pixelSize: Double, unit: String, pointsPerPixel: Double, targetPoints: Double = 64) -> Plan? {
        guard pixelSize > 0, pixelSize.isFinite, pointsPerPixel > 0, pointsPerPixel.isFinite, targetPoints > 0 else { return nil }
        guard let nm = nanometres(per: unit) else {
            let nice = ScaleBar.nice125(targetPoints * pixelSize / pointsPerPixel)
            return Plan(label: "\(ScaleBar.format(nice)) \(unit)", lengthPoints: nice / (pixelSize / pointsPerPixel))
        }
        let nmPerPoint = pixelSize * nm / pointsPerPixel
        let nice = ScaleBar.nice125(targetPoints * nmPerPoint)
        let label = nice >= 1000 ? "\(ScaleBar.format(nice / 1000)) \u{00B5}m" : "\(ScaleBar.format(nice)) nm"
        return Plan(label: label, lengthPoints: nice / nmPerPoint)
    }
}

extension MapScaleBar {
    /// The shortest bar a map carries, in points (screen) or pixels (export).
    static let minimumLengthPoints: Double = 32

    /// The bar for one map of `width` points (or export pixels) drawn at `pointsPerPixel`: the round length nearest 0.3 of the width
    /// (at most 64, at least the minimum), so a smaller tile gets a shorter bar. A map narrower than twice the minimum length has
    /// no room for a bar and its label: none is drawn. No pixel size, no bar.
    static func tilePlan(pixelSize: Double, unit: String, pointsPerPixel: Double, width: Double) -> Plan? {
        guard width >= 2 * minimumLengthPoints else { return nil }
        return plan(pixelSize: pixelSize, unit: unit, pointsPerPixel: pointsPerPixel,
                    targetPoints: min(64, max(minimumLengthPoints, width * 0.3)))
    }
}

/// The bar, bottom-left on the map, on glass so it reads on any map.
struct MapScaleBarView: View {
    let plan: MapScaleBar.Plan
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.label).font(.caption.weight(.semibold))
            Rectangle().frame(width: CGFloat(plan.lengthPoints), height: 3)
        }
        .foregroundStyle(.primary)   // vibrant on the thin material
        .padding(.horizontal, 8).padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 6))   // spec 2 D-8: glass only over a map
        .environment(\.colorScheme, .dark)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale bar \(plan.label)")
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
    /// The bitmap as PNG bytes at its own pixel grid (no resampling, no chrome); nil if the encoder refuses. The Maps export's one encoder.
    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
    static func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

    /// The bitmap with a scale bar drawn into its bottom-left corner, at the bitmap's own pixel size (the export has no points):
    /// a white bar with a dark outline, 8 px in from the left and bottom edges, its label above it in 12 px white text with a
    /// 1 px dark shadow. Every other pixel is the image's own. `plan.lengthPoints` is read as pixels. nil if the context fails.
    static func addingScaleBar(to image: CGImage, plan: MapScaleBar.Plan) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let inset: CGFloat = 8, barHeight: CGFloat = 3
        let length = CGFloat(max(1, plan.lengthPoints.rounded()))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        ctx.fill(CGRect(x: inset - 1, y: inset - 1, width: length + 2, height: barHeight + 2))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: inset, y: inset, width: length, height: barHeight))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 12, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any]
        guard let text = CFAttributedStringCreate(nil, plan.label as CFString, attributes as CFDictionary) else { return nil }
        let line = CTLineCreateWithAttributedString(text)
        let base = CGPoint(x: inset, y: inset + barHeight + 4)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        ctx.textPosition = CGPoint(x: base.x + 1, y: base.y - 1)
        CTLineDraw(line, ctx)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.textPosition = base
        CTLineDraw(line, ctx)
        return ctx.makeImage()
    }
}

/// The mixed map as one bitmap (a pixel per scan pixel). `backdrop` is the HAADF under the mix (spec 2 D-2): empty means none, the
/// mix then sits on black (a pixel with no element is black). With one, it shows grey where the elements leave room, so a
/// full-strength element hides it. With no element ticked the backdrop alone stands in, so regions can be drawn before any element
/// is chosen; with neither there is no image.
enum ColorMixRaster {
    static func image(tiles: [MapTile], mixed: Set<Int>, colors: [Int: ColorMixComposite.RGB],
                      backdrop: [Float], width: Int, height: Int, displays: [Int: MapDisplay] = [:]) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let ticked = tiles.contains { mixed.contains($0.z) }
        let hasBackdrop = backdrop.count == width * height
        guard ticked || hasBackdrop else { return nil }
        return MapBitmap.image(width: width, height: height) { i in
            var c: ColorMixComposite.RGB = (0, 0, 0)
            if ticked { c = ColorMixComposite.rgb(at: i, tiles: tiles, mixed: mixed, colors: colors, displays: displays) }
            if hasBackdrop {
                let g = Double(backdrop[i]), room = 1 - max(c.r, c.g, c.b)
                c = (c.r + g * room, c.g + g * room, c.b + g * room)
            }
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
        /// The HAADF tile's outline: the backdrop under the mix is on or off.
        var mixHAADF: Bool = true
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
