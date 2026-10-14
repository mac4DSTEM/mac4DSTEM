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
            ],
            context: nil   // macOS 27 deprecates the context-less overload; nil is its old behaviour
        )
        return max(17, ceil(bounds.height))
    }

    /// `pixelScale` is the export's pixels per point (1x, 2x, 3x): `image` is already that many times larger than its layout
    /// size, and the margins, text, colorbar and caption are laid out in points exactly as at 1x and drawn at that many pixels per
    /// point, so a 2x figure is the 1x figure with twice the pixels.
    static func publicationFigure(
        image: CGImage, title: String, caption: String,
        valueRange: (low: Double, high: Double)?, valueUnits: String,
        colormap: ColormapKind, masksNoData: Bool = false, gamma: Float = 1,
        pixelScale: Int = 1
    ) -> CGImage {
        let pixels = CGFloat(max(pixelScale, 1))
        let imageWidth = CGFloat(image.width) / pixels, imageHeight = CGFloat(image.height) / pixels   // points
        let margin: CGFloat = 18
        let colorbarWidth: CGFloat = valueRange == nil ? 0 : 76
        let width = imageWidth + margin * 2 + colorbarWidth
        // The caption WRAPS; the figure grows to hold it (v2 S7). It used to
        // truncate at one 17 pt line with `.byTruncatingTail` — and the
        // burned-in caption is the provenance record of the exported pixels,
        // so a tail-truncated caption silently dropped exactly the
        // provenance keys it exists to carry.
        let captionText = captionTextHeight(caption, width: width - margin * 2)
        let captionHeight: CGFloat = 41 + captionText
        let size = NSSize(
            width: width,
            height: imageHeight + margin * 2 + captionHeight
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * pixels), pixelsHigh: Int(size.height * pixels),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return image
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        if pixels != 1 { graphics.cgContext.scaleBy(x: pixels, y: pixels) }   // lay out in points
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        let imageRect = NSRect(
            x: margin, y: margin + captionHeight,
            width: imageWidth, height: imageHeight
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
                let (red, green, blue) = colorbarRowRGB(lut, fraction: Double(index) / 255, gamma: gamma)
                NSColor(
                    red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                    blue: CGFloat(blue) / 255, alpha: 1
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

    /// The colour of a colorbar row at value `fraction` of the window: the same gamma and
    /// LUT lookup the image pixels get, so the bar labels the image at any gamma.
    nonisolated static func colorbarRowRGB(_ lut: [UInt8], fraction: Double,
                                           gamma: Float) -> (UInt8, UInt8, UInt8) {
        Colormaps.sampleRGB(lut, pow(fraction, 1 / Double(max(gamma, 0.05))))
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
            let (r, g, b) = Colormaps.sampleRGB(lut, Double(v))   // the shader's linear-filter lookup
            out[4 * i] = r; out[4 * i + 1] = g; out[4 * i + 2] = b
        }
        return out
    }

    /// Burn a 1-2-5 scale bar into the bottom-left corner of an export.
    /// Small maps are integer-upscaled (nearest neighbor, so data pixels stay
    /// exact) to ≥512 px wide first, keeping the bar and label legible.
    /// `unitsPerDataPixel` nil → uncalibrated, bar labelled in data px.
    /// `pixelScale` (1x, 2x, 3x) enlarges the result by that factor again, the bar and `overlays` (the virtual detector on a
    /// pattern) drawn at the larger size, not enlarged after: the same figure with more pixels.
    static func burnScaleBar(on base: CGImage,
                             unitsPerDataPixel: Double?,
                             unitLabel: String,
                             pixelScale: Int = 1,
                             overlays: [FigureOverlay] = []) -> CGImage {
        let magnification = max(1, Int((512.0 / Double(base.width)).rounded(.up)))
        return FigureRendering.rendered(
            FigurePanel(label: "", image: base, overlays: overlays,
                        bar: .ladder(unitsPerDataPixel: unitsPerDataPixel, unit: unitLabel)),
            magnification: magnification, deviceScale: pixelScale) ?? base
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
        properties: [CFString: Any]? = nil,
        producing: DisplayedProduct? = nil,
        message: String? = nil
    ) {
        saveFile(suggestedName: suggestedName, type: .png, format: "png", state: state, message: message, producing: producing) {
            writePNG(image, to: $0, properties: properties)
        }
    }

    /// The save panel for any exported file: `message` is the sentence under its title (what is being saved, at what size),
    /// `write` puts the bytes at the chosen URL. The status line, the export record and the error are the same for every format.
    ///
    /// AppKit (`NSSavePanel`), kept on purpose: the result and the diffraction exports start from File-menu commands, which have no view
    /// to present SwiftUI's `fileExporter` from, and the shell that hosts the views is frozen. The figure, started by a button in a view,
    /// goes through `fileExporter` (`FigureFile`).
    static func saveFile(
        suggestedName: String, type: UTType, format: String, state: AppState, message: String? = nil,
        producing: DisplayedProduct? = nil, write: (URL) -> Bool
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggestedName
        if let message { panel.message = message }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if write(url) {
            state.statusText = "Exported \(url.lastPathComponent)"
            state.recordExportRun(format: format, fileName: url.lastPathComponent,
                                  productKind: producing?.kind,
                                  productStep: producing?.provenance["lineage_step"])   // lineage sink (ADR 047)
        } else {
            state.present(SimpleError("Writing the \(format.uppercased()) failed."))
        }
    }

    /// What the save panel says about an export: the subject, then its pixel size and the image size it was drawn at, or (a vector
    /// file, which has no pixels) its size in points.
    nonisolated static func exportPanelMessage(subject: String, width: Int, height: Int, scale: Int?) -> String {
        if let scale {
            return "\(subject) \u{00B7} \(scale)\u{00D7} \u{00B7} \(width) \u{00D7} \(height) pixels"
        }
        return "\(subject) \u{00B7} vector \u{00B7} \(width) \u{00D7} \(height) points"
    }

    /// The panel-free write, separated so a test can pin that the metadata
    /// actually lands in the file — a property dict that ImageIO silently
    /// drops would otherwise look exactly like one it wrote. // v2 S7
    nonisolated static func writePNG(
        _ image: CGImage, to url: URL, properties: [CFString: Any]?
    ) -> Bool {
        writeImage(image, to: url, type: .png, properties: properties)
    }

    /// The same write for any image type ImageIO encodes (the figure's TIFF).
    nonisolated static func writeImage(
        _ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any]?
    ) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
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
        title: String, record: [String: Any], pixelScale: Int = 1
    ) -> [CFString: Any]? {
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(
                withJSONObject: record, options: [.sortedKeys]
              ),
              let json = String(data: data, encoding: .utf8) else { return nil }
        var properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGTitle: title,
                kCGImagePropertyPNGDescription: json,
                kCGImagePropertyPNGSoftware: "mac4DSTEM",
            ] as [CFString: Any],
        ]
        if let density = pngDensity(pixelScale: pixelScale) { properties.merge(density) { $1 } }
        return properties
    }

    /// A 2x or 3x export says so in the file: 144 or 216 pixels per inch, so Keynote, Preview and Pages place it at the size
    /// of the 1x figure and the extra pixels are sharpness, not size. 1x carries no density (the file is as it always was).
    nonisolated static func pngDensity(pixelScale: Int) -> [CFString: Any]? {
        guard pixelScale > 1 else { return nil }
        return [kCGImagePropertyDPIWidth: 72.0 * Double(pixelScale), kCGImagePropertyDPIHeight: 72.0 * Double(pixelScale)]
    }
}

extension FigureRendering {
    /// A 1-2-5 scale bar in the bottom-left corner of a `width` x `height` pixel image, on a translucent plate. This is what
    /// `burnScaleBar` always drew, moved here unchanged (its output is pinned byte for byte, `NSString` text and all) so a figure's
    /// panels draw the same bar; it stays AppKit because Core Text would set the same words in a different rasterisation.
    /// `unitsPerOutPixel` is the sampling of the pixels being drawn into (the data's, divided by the enlargement), so the bar's label
    /// does not depend on the export scale.
    @discardableResult
    static func drawLadderBar(in ctx: CGContext, width outW: Int, height outH: Int, unitsPerOutPixel: Double, unit unitLabel: String) -> LadderBarPlan {
        let plan = ladderBarPlan(width: outW, unitsPerOutPixel: unitsPerOutPixel, unit: unitLabel)
        let barLength = CGFloat(plan.lengthPixels)
        let margin = CGFloat(max(10, outH / 30))
        let barHeight = CGFloat(max(3, outH / 150))
        let fontSize = CGFloat(max(11, outH / 28))

        let text = plan.label as NSString
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
        return plan
    }

    /// What a scale bar says and how long it is: a 1-2-5 value near a fifth of the width, in the unit ladder the on-screen bar reads.
    struct LadderBarPlan: Equatable {
        var label: String
        var lengthPixels: Double
    }

    /// The bar's words and length for a `outW`-pixel image sampled at `unitsPerOutPixel`. Pure, so the words and the pixels can be held
    /// together: at any export scale the label is the same and the length grows with the pixels.
    static func ladderBarPlan(width outW: Int, unitsPerOutPixel: Double, unit unitLabel: String) -> LadderBarPlan {
        // Bar sized to a nice 1-2-5 value near 1/5 of the image width.
        let nice = ScaleBar.nice125(unitsPerOutPixel * Double(outW) / 5)
        // The same unit ladder as the on-screen bar, so an export reads what the pane read.
        let shown = ScaleBar.ladder(nice, unit: unitLabel)
        return LadderBarPlan(label: "\(ScaleBar.format(shown.value, locale: Locale(identifier: "en_US_POSIX"))) \(shown.unit)",
                             lengthPixels: nice / unitsPerOutPixel)
    }
}
