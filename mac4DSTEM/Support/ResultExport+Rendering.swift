//
//  ResultExport+Rendering.swift
//  Role: The export pipeline's pure rendering helpers — burning a caption,
//        title and colorbar into a publication figure, the 1-2-5 scale bar,
//        colormap application, and the PNG write itself (properties, the
//        provenance JSON `Description` chunk). No AppState instance state:
//        every function here is `static`/`nonisolated static`, and the one
//        that needs a live AppState (`savePNG`, for its status/error
//        surfaces) takes it as an explicit parameter rather than using
//        `self`.
//
//  Split out of Support/ResultExport.swift (audit 3.2 row 6, "the export
//  parity harnesses verify the wire format is unchanged" — a pure code
//  relocation between files in the same extension changes no behavior;
//  bragg-export-test, preprocessing-export-test, reduced-export-test and
//  scientific-bundle-test are the check that transcription introduced none).
//

import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import ImageIO
import UniformTypeIdentifiers

extension AppState {

    // MARK: - Rendering helpers

    /// The height the caption needs at `width`, wrapped, never truncated.
    /// Split out so the tests can pin "a longer caption gets a taller
    /// figure" without rendering pixels. // v2 S7
    static func captionTextHeight(_ caption: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // `.usesFontLeading` matters: `draw(in:)` lays out WITH per-line
        // leading and clips to the rect, so measuring without it comes up
        // short by ~(lines−1)×leading on long captions — the truncation
        // defect reintroduced at a new height (Gate B, 2026-08-25).
        let bounds = (caption as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .paragraphStyle: paragraph,
            ]
        )
        return max(17, ceil(bounds.height))
    }

    static func publicationFigure(
        image: CGImage, title: String, caption: String,
        valueRange: (low: Double, high: Double)?, valueUnits: String,
        colormap: ColormapKind, masksNoData: Bool = false
    ) -> CGImage {
        let margin: CGFloat = 18
        let colorbarWidth: CGFloat = valueRange == nil ? 0 : 76
        let width = CGFloat(image.width) + margin * 2 + colorbarWidth
        // The caption WRAPS; the figure grows to hold it (v2 S7). It used to
        // truncate at one 17 pt line with `.byTruncatingTail` — and the
        // burned-in caption is the provenance record of the exported pixels,
        // so a tail-truncated caption silently dropped exactly the
        // provenance keys it exists to carry.
        let captionText = captionTextHeight(caption, width: width - margin * 2)
        let captionHeight: CGFloat = 41 + captionText
        let size = NSSize(
            width: width,
            height: CGFloat(image.height) + margin * 2 + captionHeight
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return image
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        let imageRect = NSRect(
            x: margin, y: margin + captionHeight,
            width: CGFloat(image.width), height: CGFloat(image.height)
        )
        NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(
            in: NSRect(x: margin, y: 8 + captionText,
                       width: size.width - margin * 2, height: 24),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white, .paragraphStyle: titleParagraph,
            ]
        )
        let captionParagraph = NSMutableParagraphStyle()
        captionParagraph.lineBreakMode = .byWordWrapping
        (caption as NSString).draw(
            in: NSRect(x: margin, y: 7, width: size.width - margin * 2,
                       height: captionText),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
                .paragraphStyle: captionParagraph,
            ]
        )
        if let range = valueRange {
            let lut = Colormaps.lutRGBA(colormap, count: 256)
            let barX = imageRect.maxX + 14
            let barY = imageRect.minY
            let barHeight = imageRect.height
            for index in 0..<256 {
                let offset = index * 4
                NSColor(
                    red: CGFloat(lut[offset]) / 255,
                    green: CGFloat(lut[offset + 1]) / 255,
                    blue: CGFloat(lut[offset + 2]) / 255, alpha: 1
                ).setFill()
                NSRect(x: barX, y: barY + CGFloat(index) / 256 * barHeight,
                       width: 14, height: max(1, barHeight / 256 + 0.5)).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.white,
            ]
            (String(format: "%.4g", range.high) as NSString).draw(
                at: NSPoint(x: barX + 19, y: barY + barHeight - 12),
                withAttributes: attributes
            )
            (String(format: "%.4g", range.low) as NSString).draw(
                at: NSPoint(x: barX + 19, y: barY), withAttributes: attributes
            )
            (valueUnits as NSString).draw(
                in: NSRect(x: barX, y: barY - 17, width: 65, height: 14),
                withAttributes: attributes
            )
            // support-export-07 (S22e): the on-screen views explain the gray
            // no-data pixels; the burned figure travels without the app, so
            // it must carry the same legend — the swatch is the exact masked
            // gray `applyColormap` renders (82,82,87).
            if masksNoData {
                NSColor(calibratedRed: 82 / 255, green: 82 / 255,
                        blue: 87 / 255, alpha: 1).setFill()
                NSRect(x: barX, y: barY + barHeight + 5, width: 10, height: 10).fill()
                ("no data" as NSString).draw(
                    at: NSPoint(x: barX + 14, y: barY + barHeight + 3),
                    withAttributes: attributes
                )
            }
        }
        return bitmap.cgImage ?? image
    }

    /// Normalized [0,1] scalar pixels → packed RGBA via the colormap LUT,
    /// with the same contrast window the shader applies on screen. Negative
    /// sentinel pixels (FloatImage.invalidDisplayValue) render as the same
    /// masked gray the Metal shader uses.
    static func applyColormap(_ pixels: [Float], colormap: ColormapKind,
                                      lo: Float, hi: Float, gamma: Float) -> [UInt8] {
        let lut = Colormaps.lutRGBA(colormap, count: 256)
        var out = [UInt8](repeating: 255, count: pixels.count * 4)
        let span = max(hi - lo, 1e-6)
        for (i, raw) in pixels.enumerated() {
            if raw < 0 {
                out[4 * i] = 82; out[4 * i + 1] = 82; out[4 * i + 2] = 87
                continue
            }
            let clipped = min(max((raw - lo) / span, 0), 1)
            let v = pow(clipped, 1 / max(gamma, 0.05))
            let li = Int((v * 255).rounded()) * 4
            out[4 * i]     = lut[li]
            out[4 * i + 1] = lut[li + 1]
            out[4 * i + 2] = lut[li + 2]
        }
        return out
    }

    /// Burn a 1-2-5 scale bar into the bottom-left corner of an export.
    /// Small maps are integer-upscaled (nearest neighbor, so data pixels stay
    /// exact) to ≥512 px wide first, keeping the bar and label legible.
    /// `unitsPerDataPixel` nil → uncalibrated, bar labelled in data px.
    static func burnScaleBar(on base: CGImage,
                             unitsPerDataPixel: Double?,
                             unitLabel: String) -> CGImage {
        let scale = max(1, Int((512.0 / Double(base.width)).rounded(.up)))
        let outW = base.width * scale
        let outH = base.height * scale
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return base }
        ctx.interpolationQuality = .none   // nearest-neighbor upscale
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: outW, height: outH))

        // Bar sized to a nice 1-2-5 value near 1/5 of the image width.
        let unitsPerOutPixel = (unitsPerDataPixel ?? 1) / Double(scale)
        let nice = ScaleBar.nice125(unitsPerOutPixel * Double(outW) / 5)
        let barLength = CGFloat(nice / unitsPerOutPixel)
        let margin = CGFloat(max(10, outH / 30))
        let barHeight = CGFloat(max(3, outH / 150))
        let fontSize = CGFloat(max(11, outH / 28))

        let text = "\(ScaleBar.format(nice)) \(unitLabel)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)

        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        // Legibility backing behind bar + label (CG origin is bottom-left).
        let pad: CGFloat = 6
        let backing = CGRect(x: margin - pad, y: margin - pad,
                             width: max(barLength, textSize.width) + 2 * pad,
                             height: barHeight + 4 + textSize.height + 2 * pad)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(backing)

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: margin, y: margin, width: barLength, height: barHeight))
        text.draw(at: NSPoint(x: margin, y: margin + barHeight + 4),
                  withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? base
    }

    static func cgImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    static func savePNG(
        _ image: CGImage, suggestedName: String, state: AppState,
        properties: [CFString: Any]? = nil
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if writePNG(image, to: url, properties: properties) {
            state.statusText = "Exported \(url.lastPathComponent)"
        } else {
            state.present(SimpleError("Writing the PNG failed."))
        }
    }

    /// The panel-free write, separated so a test can pin that the metadata
    /// actually lands in the file — a property dict that ImageIO silently
    /// drops would otherwise look exactly like one it wrote. // v2 S7
    nonisolated static func writePNG(
        _ image: CGImage, to url: URL, properties: [CFString: Any]?
    ) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary?)
        return CGImageDestinationFinalize(dest)
    }

    /// PNG properties carrying the FULL provenance record beside the burned
    /// caption (v2 S7): the caption is drawn into the pixels — now unabridged
    /// — but pixels cannot be parsed back, so the same record travels as
    /// machine-readable metadata (a JSON `Description` text chunk). The JSON
    /// is serialized with sorted keys so the record is byte-stable for a
    /// given result.
    nonisolated static func pngProperties(
        title: String, record: [String: Any]
    ) -> [CFString: Any]? {
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(
                withJSONObject: record, options: [.sortedKeys]
              ),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGTitle: title,
                kCGImagePropertyPNGDescription: json,
                kCGImagePropertyPNGSoftware: "mac4DSTEM",
            ] as [CFString: Any],
        ]
    }
}
