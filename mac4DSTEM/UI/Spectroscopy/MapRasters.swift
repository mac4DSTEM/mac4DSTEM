import ShellControls
import ImagoCore
import SwiftUI
import ImageIO
import CoreText
import UniformTypeIdentifiers
import ShellMetal
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

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
    static func plan(pixelSize: Double, unit: String, pointsPerPixel: Double, targetPoints: Double = 64,
                     locale: Locale = .autoupdatingCurrent) -> Plan? {
        guard pixelSize > 0, pixelSize.isFinite, pointsPerPixel > 0, pointsPerPixel.isFinite, targetPoints > 0 else { return nil }
        guard let nm = nanometres(per: unit) else {
            let nice = ScaleBarMath.nice125(targetPoints * pixelSize / pointsPerPixel)
            return Plan(label: "\(ScaleBar.format(nice, locale: locale)) \(unit)", lengthPoints: nice / (pixelSize / pointsPerPixel))
        }
        let nmPerPoint = pixelSize * nm / pointsPerPixel
        let nice = ScaleBarMath.nice125(targetPoints * nmPerPoint)
        let label = nice >= 1000 ? "\(ScaleBar.format(nice / 1000, locale: locale)) \u{00B5}m" : "\(ScaleBar.format(nice, locale: locale)) nm"
        return Plan(label: label, lengthPoints: nice / nmPerPoint)
    }
}

extension MapScaleBar {
    /// The shortest bar a map carries, in points (screen) or pixels (export).
    static let minimumLengthPoints: Double = 32

    /// The bar for one map of `width` points (or export pixels) drawn at `pointsPerPixel`: the round length nearest 0.3 of the width
    /// (at most 64, at least the minimum), so a smaller tile gets a shorter bar. A map narrower than twice the minimum length has
    /// no room for a bar and its label: none is drawn. No pixel size, no bar. A burned-in export passes `en_US_POSIX`.
    static func tilePlan(pixelSize: Double, unit: String, pointsPerPixel: Double, width: Double,
                         locale: Locale = .autoupdatingCurrent) -> Plan? {
        guard width >= 2 * minimumLengthPoints else { return nil }
        return plan(pixelSize: pixelSize, unit: unit, pointsPerPixel: pointsPerPixel,
                    targetPoints: min(64, max(minimumLengthPoints, width * 0.3)), locale: locale)
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
    /// `pixelScale` 2 or 3 tags the file 144 or 216 pixels per inch (`AppState.pngDensity`), so it is placed at the 1x size.
    static func pngData(_ image: CGImage, pixelScale: Int = 1) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, AppState.pngDensity(pixelScale: pixelScale) as CFDictionary?)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
    static func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

    /// The bitmap with a scale bar drawn into its bottom-left corner, at the bitmap's own pixel size (the export has no points):
    /// a white bar with a dark outline, 8 px in from the left and bottom edges, its label above it in 12 px white text with a
    /// 1 px dark shadow. Every other pixel is the image's own. `plan.lengthPoints` is read as pixels. nil if the context fails.
    /// `scale` is the export's pixels per point (an image already enlarged by it): every length above grows with it, so a 2x
    /// export carries the same bar, twice the pixels.
    static func addingScaleBar(to image: CGImage, plan: MapScaleBar.Plan, scale: Int = 1) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard drawScaleBar(in: ctx, plan: plan, scale: CGFloat(max(scale, 1))) else { return nil }
        return ctx.makeImage()
    }

    /// The bar and its label in the bottom-left corner of whatever `ctx` is drawing into (y up, origin at that corner), the
    /// one drawing the Maps PNGs and the exported figures share. False if the label cannot be made.
    @discardableResult
    static func drawScaleBar(in ctx: CGContext, plan: MapScaleBar.Plan, scale: CGFloat = 1) -> Bool {
        let inset: CGFloat = 8 * scale, barHeight: CGFloat = 3 * scale, outline: CGFloat = scale
        let length = CGFloat(max(1, (plan.lengthPoints * scale).rounded()))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        ctx.fill(CGRect(x: inset - outline, y: inset - outline, width: length + 2 * outline, height: barHeight + 2 * outline))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: inset, y: inset, width: length, height: barHeight))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 12 * scale, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 12 * scale, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any]
        guard let text = CFAttributedStringCreate(nil, plan.label as CFString, attributes as CFDictionary) else { return false }
        let line = CTLineCreateWithAttributedString(text)
        let base = CGPoint(x: inset, y: inset + barHeight + 4 * scale)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        ctx.textPosition = CGPoint(x: base.x + scale, y: base.y - scale)
        CTLineDraw(line, ctx)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.textPosition = base
        CTLineDraw(line, ctx)
        return true
    }

    /// The bitmap enlarged by a whole factor, each pixel a `factor` x `factor` block (nearest neighbour: no value is invented).
    static func enlarged(_ image: CGImage, by factor: Int) -> CGImage? {
        guard factor > 1 else { return image }
        let w = image.width * factor, h = image.height * factor
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

