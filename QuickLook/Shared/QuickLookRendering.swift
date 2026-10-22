//
//  QuickLookRendering.swift
//  Role: the pixels of a Quick Look thumbnail and the card's image, from FormatoKit's `Peek.Frame`: the stretch (1 to 99 percent for
//        images, log for a diffraction pattern, a plain trace for a spectrum), an 8-bit grey bitmap and the aspect fit. CoreGraphics
//        only: no AppKit, no SwiftUI, no app types, so the thumbnail extension (a sandboxed process with seconds and tens of MB) links it
//        without the app. Grey, not a colour map: a thumbnail reads best as the instrument's own contrast (taste check for Paul).
//  Provenance: shared by the QuickLookThumbnail and QuickLookPreview extensions and the app's unit tests (package target DSTEMQuickLook);
//        macTEM copies it with a header (copies.manifest) until MacEMShell exists.
//

import CoreGraphics
import Foundation
import FormatoPeek

public nonisolated enum QuickLookRendering {
    /// The grey levels a frame is drawn between, after `log` (when set) is applied to `value - floor`.
    public struct Stretch: Sendable, Equatable {
        public var floor: Float
        public var low: Float
        public var high: Float
        public var logScale: Bool
    }

    /// 1 to 99 percent for images, so a few hot pixels do not flatten the picture; log scale (from the frame's minimum, 0 to 99.9 percent)
    /// for a diffraction pattern, whose bright centre spans decades; the plain range for a spectrum.
    public static func stretch(for frame: Peek.Frame) -> Stretch {
        let finite = frame.pixels.filter { $0.isFinite }
        guard let minimum = finite.min(), let maximum = finite.max(), maximum > minimum else {
            return Stretch(floor: 0, low: 0, high: 1, logScale: false)
        }
        switch frame.kind {
        case .spectrum:
            return Stretch(floor: minimum, low: 0, high: maximum - minimum, logScale: false)
        case .diffractionPattern:
            let values = finite.map { Float(Foundation.log10(Double(1 + $0 - minimum))) }.sorted()
            return Stretch(floor: minimum, low: 0, high: max(percentile(values, 0.999), 1e-6), logScale: true)
        case .image, .virtualImage:
            let sorted = finite.sorted()
            let low = percentile(sorted, 0.01), high = percentile(sorted, 0.99)
            return high > low ? Stretch(floor: 0, low: low, high: high, logScale: false)
                              : Stretch(floor: 0, low: minimum, high: maximum, logScale: false)
        }
    }

    private static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))]
    }

    /// The frame as 8-bit grey, row-major, `width * height` bytes (not for a spectrum, which is a trace).
    public static func grayscale(_ frame: Peek.Frame) -> [UInt8] {
        let s = stretch(for: frame)
        var out = [UInt8](repeating: 0, count: frame.pixels.count)
        let span = s.high - s.low
        for (i, raw) in frame.pixels.enumerated() {
            guard raw.isFinite else { continue }
            let v = s.logScale ? Float(Foundation.log10(Double(1 + raw - s.floor))) : raw
            out[i] = UInt8(max(0, min(255, ((v - s.low) / span * 255).rounded())))
        }
        return out
    }

    /// The largest size with the frame's aspect that fits in `maximum` (a spectrum is drawn 2:1).
    public static func fittedSize(for frame: Peek.Frame, within maximum: CGSize) -> CGSize {
        let aspect = frame.kind == .spectrum ? 2.0 : Double(frame.width) / Double(max(frame.height, 1))
        guard maximum.width > 0, maximum.height > 0, aspect > 0 else { return .zero }
        let width = min(maximum.width, maximum.height * aspect)
        return CGSize(width: width.rounded(.down), height: (width / aspect).rounded(.down))
    }

    /// Draws the frame filling `size` (origin at the lower left, as CoreGraphics): an image, or a spectrum as a trace.
    public static func draw(_ frame: Peek.Frame, in context: CGContext, size: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        if frame.kind == .spectrum { drawTrace(frame, in: context, size: size); return }
        let bytes = grayscale(frame)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: frame.width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: .zero, size: size))
    }

    private static func drawTrace(_ frame: Peek.Frame, in context: CGContext, size: CGSize) {
        let s = stretch(for: frame)
        guard frame.width > 1 else { return }
        context.setStrokeColor(CGColor(gray: 0.92, alpha: 1))
        context.setLineWidth(max(1, size.height / 200))
        let inset = size.height * 0.06
        for (i, raw) in frame.pixels.enumerated() where raw.isFinite {
            let x = CGFloat(i) / CGFloat(frame.width - 1) * size.width
            let y = inset + CGFloat((raw - s.floor) / s.high) * (size.height - 2 * inset)
            if i == 0 { context.move(to: CGPoint(x: x, y: y)) } else { context.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.strokePath()
    }

    /// The frame as a bitmap image fitted into `maximum`, for the preview card.
    public static func image(for frame: Peek.Frame, within maximum: CGSize) -> CGImage? {
        let size = fittedSize(for: frame, within: maximum)
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        draw(frame, in: context, size: size)
        return context.makeImage()
    }
}
