//
//  ResultExport.swift
//  Role: Minimal result export — PNG of the current real-space result or
//        diffraction pattern (rendered exactly as displayed: colormap, log
//        scale, contrast window), and CSV of detected Bragg peaks.
//        First slice of the persistence milestone; the sidecar-.h5 store
//        comes later and replaces none of this.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

extension AppState {

    /// Export the current real-space result (virtual image / DPC / strain /
    /// ACOM map) as a PNG, rendered as displayed, with the scale bar burned in.
    func exportResultImage() {
        let cg: CGImage?
        if let rgba = resultRGBA {
            cg = Self.cgImage(rgba: rgba.rgba, width: rgba.width, height: rgba.height)
        } else if let image = resultImage {
            let norm = image.normalized(symmetric: colormap.isDiverging)
            let bytes = Self.applyColormap(norm, colormap: colormap,
                                           lo: displayRangeLo, hi: displayRangeHi)
            cg = Self.cgImage(rgba: bytes, width: image.width, height: image.height)
        } else {
            present(SimpleError("No result image to export yet."))
            return
        }
        guard let cg else {
            present(SimpleError("Could not render the result image for export."))
            return
        }
        let rSize = calibration.rPixelSize
        let final = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: rSize,
                                      unitLabel: rSize != nil ? (calibration.rPixelUnits ?? "nm") : "px")
        Self.savePNG(final, suggestedName: exportBaseName + "_result.png", state: self)
    }

    /// Export the currently displayed diffraction pattern as a PNG, with the
    /// q-space scale bar burned in.
    func exportDiffractionImage() {
        guard let pattern = displayedPattern else {
            present(SimpleError("No diffraction pattern to export yet."))
            return
        }
        let norm = pattern.normalized(useLog: logScale)
        let bytes = Self.applyColormap(norm, colormap: colormap, lo: 0, hi: 1)
        guard let cg = Self.cgImage(rgba: bytes, width: pattern.qx, height: pattern.qy) else {
            present(SimpleError("Could not render the diffraction pattern for export."))
            return
        }
        let qSize = calibration.qPixelSize
        let final = Self.burnScaleBar(on: cg,
                                      unitsPerDataPixel: qSize,
                                      unitLabel: qSize != nil ? (calibration.qPixelUnits ?? "1/nm") : "px")
        Self.savePNG(final, suggestedName: exportBaseName + "_cbed.png", state: self)
    }

    /// Export all detected Bragg peaks as CSV: scan position, detector
    /// position (subpixel), intensity.
    func exportBraggPeaksCSV() {
        guard let vectors = braggVectors else {
            present(SimpleError("No Bragg peaks to export — run Detect All Disks first."))
            return
        }
        var csv = "rx,ry,qx,qy,intensity\n"
        csv.reserveCapacity(vectors.totalPeakCount * 32)
        for ry in 0..<vectors.scanHeight {
            for rx in 0..<vectors.scanWidth {
                for p in vectors.peaks[ry * vectors.scanWidth + rx] {
                    csv += "\(rx),\(ry),\(p.x),\(p.y),\(p.intensity)\n"
                }
            }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = exportBaseName + "_bragg_peaks.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            statusText = "Exported \(vectors.totalPeakCount) peaks → \(url.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    private var exportBaseName: String {
        let file = descriptor.map { ($0.fileName as NSString).deletingPathExtension } ?? "mac4DSTEM"
        return file
    }

    // MARK: - Rendering helpers

    /// Normalized [0,1] scalar pixels → packed RGBA via the colormap LUT,
    /// with the same contrast window the shader applies on screen.
    private static func applyColormap(_ pixels: [Float], colormap: ColormapKind,
                                      lo: Float, hi: Float) -> [UInt8] {
        let lut = Colormaps.lutRGBA(colormap, count: 256)
        var out = [UInt8](repeating: 255, count: pixels.count * 4)
        let span = max(hi - lo, 1e-6)
        for (i, raw) in pixels.enumerated() {
            let v = min(max((raw - lo) / span, 0), 1)
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
    private static func burnScaleBar(on base: CGImage,
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
        let nice = ScaleBarView.nice125(unitsPerOutPixel * Double(outW) / 5)
        let barLength = CGFloat(nice / unitsPerOutPixel)
        let margin = CGFloat(max(10, outH / 30))
        let barHeight = CGFloat(max(3, outH / 150))
        let fontSize = CGFloat(max(11, outH / 28))

        let text = "\(ScaleBarView.format(nice)) \(unitLabel)" as NSString
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

    private static func cgImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
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

    private static func savePNG(_ image: CGImage, suggestedName: String, state: AppState) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else {
            state.present(SimpleError("Could not create the PNG file."))
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            state.statusText = "Exported \(url.lastPathComponent)"
        } else {
            state.present(SimpleError("Writing the PNG failed."))
        }
    }
}
