//
//  FigureRendering.swift
//  Role: The pure drawing behind the exported figures (tier 2, 2026-10-14): a panel's data pixels, the outlines the
//        app draws over them (the virtual detector on a diffraction pattern, a region on an EDX map), its scale bar,
//        and several panels laid out in one labelled image at 1x, 2x or 3x pixels per point. No AppState: the
//        callers (`ResultExport.swift`, `MapsExport.swift`, `FigureExport.swift`) hand it finished panels.
//
//  One implementation per thing the screen also shows. The detector's position and its line styles are
//  `ApertureOutline` (the pane's `ApertureOverlay` takes them too); a region's path is `RegionOutline` (the room's
//  `MapTileView` strokes it too); the result and pattern bar is `drawLadderBar`, which is what `burnScaleBar` always
//  drew; a map's bar is `MapBitmap.drawScaleBar`, which the Maps PNGs draw too. Only the stroking differs, SwiftUI
//  there and Core Graphics here.
//
//  No AppKit: the strokes are Core Graphics, the text Core Text, the colours SwiftUI's (the one piece of text that is still drawn
//  by AppKit, the result and pattern scale bar, lives with `burnScaleBar` in ResultExport+Rendering.swift, which pins it byte for byte).
//
//  Units. A panel is laid out in POINTS: one data pixel is `magnification` points, and the export draws `deviceScale`
//  pixels per point. So a figure at 2x is exactly the 1x figure with twice the pixels, line weights and text included.
//

import CoreText
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// What is stroked over a panel's data pixels, in the panel's own data-pixel coordinates (the image's width and height are the
/// detector's, or the scan grid's).
enum FigureOverlay {
    /// The active virtual detector, outlined as the pane draws it (no drag handles: they are controls, not part of a figure), in the
    /// colours of the given appearance (`FigureColors.scheme`).
    case detector(Aperture, VirtualShapeMode, ColorScheme)
    /// A region on an EDX map's grid.
    case region(SpectrumRegionShape, RegionStroke)
}

/// How a region's outline is stroked: the live region is the dashed accent line, a pin a thinner solid line in its tint.
struct RegionStroke {
    var color: CGColor
    var width: CGFloat
    var dash: [CGFloat] = []
}

/// Which of the app's two scale bars a panel carries.
enum FigureScaleBar {
    /// The result and diffraction bar (`burnScaleBar`'s): a 1-2-5 length near a fifth of the width. nil sampling is a bar in data px.
    case ladder(unitsPerDataPixel: Double?, unit: String)
    /// A spectroscopy map's bar (`MapScaleBar`, drawn by `MapBitmap.drawScaleBar`): sized for the panel as it is laid out.
    case map(pixelSize: Double, unit: String)
}

/// One image of a figure, at data resolution.
struct FigurePanel {
    var label: String
    var image: CGImage
    var overlays: [FigureOverlay] = []
    var bar: FigureScaleBar?
}

// MARK: - Layout

/// Where each panel of a figure goes, in points, top-left origin. Pure: the renderer and the tests read the same plan.
nonisolated enum FigureLayout {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 16
    static let labelHeight: CGFloat = 22
    /// A panel is enlarged by the whole factor that brings it nearest to this box, at least 1 (no data is resampled).
    static let targetWidth = 480.0, targetHeight = 400.0
    /// Past this a figure is refused rather than allocated: a few panels of a large scan at 3x would otherwise ask for gigabytes.
    static let maximumPixels = 16_384

    struct Cell: Equatable {
        var index: Int
        var label: String
        /// Points per data pixel.
        var magnification: Int
        var labelRect: CGRect
        var imageRect: CGRect
    }

    struct Plan: Equatable {
        var columns: Int
        /// Points.
        var size: CGSize
        var cells: [Cell]
    }

    /// One row up to three panels, two by two for four, three across beyond.
    static func columns(for count: Int) -> Int {
        count <= 3 ? max(count, 0) : (count == 4 ? 2 : 3)
    }

    static func magnification(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 1 }
        return max(1, Int(min(targetWidth / Double(width), targetHeight / Double(height)).rounded()))
    }

    static func plan(_ panels: [(label: String, width: Int, height: Int)]) -> Plan {
        let n = panels.count
        guard n > 0 else { return Plan(columns: 0, size: .zero, cells: []) }
        let columns = columns(for: n)
        let rows = (n + columns - 1) / columns
        let mags = panels.map { magnification(width: $0.width, height: $0.height) }
        let widths = zip(panels, mags).map { CGFloat($0.width * $1) }
        let heights = zip(panels, mags).map { CGFloat($0.height * $1) }
        var columnWidth = [CGFloat](repeating: 0, count: columns), rowHeight = [CGFloat](repeating: 0, count: rows)
        for i in 0..<n {
            columnWidth[i % columns] = max(columnWidth[i % columns], widths[i])
            rowHeight[i / columns] = max(rowHeight[i / columns], heights[i])
        }
        var cells: [Cell] = []
        for i in 0..<n {
            let column = i % columns, row = i / columns
            let x = margin + columnWidth[0..<column].reduce(0) { $0 + $1 + gap }
            let y = margin + rowHeight[0..<row].reduce(0) { $0 + labelHeight + $1 + gap }
            cells.append(Cell(index: i, label: panels[i].label, magnification: mags[i],
                              labelRect: CGRect(x: x, y: y, width: widths[i], height: labelHeight),
                              imageRect: CGRect(x: x, y: y + labelHeight, width: widths[i], height: heights[i])))
        }
        let width = 2 * margin + columnWidth.reduce(0, +) + gap * CGFloat(columns - 1)
        let height = 2 * margin + rowHeight.reduce(0) { $0 + labelHeight + $1 } + gap * CGFloat(rows - 1)
        return Plan(columns: columns, size: CGSize(width: width, height: height), cells: cells)
    }

    /// The figure's pixel size at `scale` pixels per point.
    static func pixelSize(_ plan: Plan, scale: Int) -> (width: Int, height: Int) {
        (Int(plan.size.width) * max(scale, 1), Int(plan.size.height) * max(scale, 1))
    }
}

// MARK: - Drawing

enum FigureRendering {

    /// Draws `panel` into `rect` (pixels, y up) of `ctx`: the data pixels enlarged without smoothing, then the outlines, then the bar.
    /// `rect` is `image size x magnification x deviceScale` on a side, and nothing is drawn outside it.
    /// `embedFactor` > 1 enlarges the data pixels (nearest neighbour) before they are drawn: a PDF stores the image it is given and
    /// leaves the smoothing to the viewer, so a vector figure is handed the map already at the size it is laid out.
    /// Returns what the result/pattern scale bar said (its label and its length in pixels) when the panel has one, so a test can hold
    /// the words and the pixels together.
    @discardableResult
    static func draw(_ panel: FigurePanel, in ctx: CGContext, rect: CGRect, magnification: Int, deviceScale: Int, embedFactor: Int = 1) -> LadderBarPlan? {
        var ladder: LadderBarPlan?
        let device = CGFloat(max(deviceScale, 1))
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.interpolationQuality = .none   // nearest neighbour: data pixels stay exact
        ctx.draw(embedFactor > 1 ? MapBitmap.enlarged(panel.image, by: embedFactor) ?? panel.image : panel.image, in: rect)
        if !panel.overlays.isEmpty {
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.maxY)   // the panel's top-left corner ...
            ctx.scaleBy(x: device, y: -device)            // ... in points, y down, like the SwiftUI overlays
            let box = CGSize(width: CGFloat(panel.image.width * magnification), height: CGFloat(panel.image.height * magnification))
            for overlay in panel.overlays {
                switch overlay {
                case .detector(let aperture, let shape, let scheme):
                    drawDetector(aperture, shape, scheme: scheme, patternWidth: panel.image.width, patternHeight: panel.image.height, box: box, in: ctx)
                case .region(let shape, let stroke):
                    drawRegion(shape, stroke, gridWidth: panel.image.width, gridHeight: panel.image.height, box: box, in: ctx)
                }
            }
            ctx.restoreGState()
        }
        if let bar = panel.bar {
            ctx.translateBy(x: rect.minX, y: rect.minY)   // the panel's bottom-left corner, y up
            switch bar {
            case .ladder(let unitsPerDataPixel, let unit):
                ladder = drawLadderBar(in: ctx, width: Int(rect.width), height: Int(rect.height),
                                       unitsPerOutPixel: (unitsPerDataPixel ?? 1) / Double(magnification * max(deviceScale, 1)), unit: unit,
                                       deviceScale: deviceScale)
            case .map(let pixelSize, let unit):
                if let plan = MapScaleBar.tilePlan(pixelSize: pixelSize, unit: unit, pointsPerPixel: Double(magnification),
                                                   width: Double(panel.image.width * magnification),
                                                   locale: Locale(identifier: "en_US_POSIX")) {
                    MapBitmap.drawScaleBar(in: ctx, plan: plan, scale: device)
                }
            }
        }
        ctx.restoreGState()
        return ladder
    }

    /// The panel as an image of its own: its data pixels enlarged `magnification` x `deviceScale` times without smoothing, then its
    /// outlines and its bar. nil when the image is empty or the context cannot be made.
    static func rendered(_ panel: FigurePanel, magnification: Int, deviceScale: Int) -> CGImage? {
        let factor = max(magnification, 1) * max(deviceScale, 1)
        let width = panel.image.width * factor, height = panel.image.height * factor
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        draw(panel, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height),
             magnification: max(magnification, 1), deviceScale: max(deviceScale, 1))
        return ctx.makeImage()
    }

    // MARK: Detector

    /// The virtual detector the pane draws, stroked in `box` (view points, y down): the dark halo under every edge, the yellow
    /// outer edge (a square's, a point's crosshair), the dashed cyan inner edge of an annulus. `ApertureOutline` has the
    /// position and every width, opacity and dash.
    static func drawDetector(_ aperture: Aperture, _ shape: VirtualShapeMode, scheme: ColorScheme, patternWidth: Int, patternHeight: Int,
                             box: CGSize, in ctx: CGContext) {
        let m = ApertureOutline.metrics(aperture: aperture, patternWidth: patternWidth, patternHeight: patternHeight, box: box)
        let halo = CGColor(gray: 0, alpha: ApertureOutline.haloOpacity)
        let yellow = ApertureOutline.outerColor.cgColor(opacity: ApertureOutline.lineOpacity, scheme: scheme)
        let cyan = ApertureOutline.innerColor.cgColor(opacity: ApertureOutline.lineOpacity, scheme: scheme)
        func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, dash: [CGFloat] = []) {
            ctx.saveGState()
            ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineDash(phase: 0, lengths: dash)
            ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
        func disc(_ radius: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: m.center.x - radius, y: m.center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        }
        switch shape {
        case .circle, .annulus:
            stroke(disc(m.outer), halo, width: ApertureOutline.haloWidth)
            stroke(disc(m.outer), yellow, width: ApertureOutline.lineWidth)
            // At inner radius 0 the pane draws a faint dot under the centre handle; a figure has no handle, so nothing.
            if shape == .annulus, aperture.inner > 0 {
                stroke(disc(m.inner), halo, width: ApertureOutline.haloWidth)
                stroke(disc(m.inner), cyan, width: ApertureOutline.lineWidth, dash: ApertureOutline.innerDash)
            }
        case .rectangle:
            // `outer` is the half-extent of the square the mask kernel integrates.
            let square = CGPath(rect: CGRect(x: m.center.x - m.outer, y: m.center.y - m.outer, width: 2 * m.outer, height: 2 * m.outer), transform: nil)
            stroke(square, halo, width: ApertureOutline.haloWidth)
            stroke(square, yellow, width: ApertureOutline.lineWidth)
        case .point:
            let arm = ApertureOutline.crossArm
            let cross = CGMutablePath()
            cross.move(to: CGPoint(x: m.center.x - arm, y: m.center.y)); cross.addLine(to: CGPoint(x: m.center.x + arm, y: m.center.y))
            cross.move(to: CGPoint(x: m.center.x, y: m.center.y - arm)); cross.addLine(to: CGPoint(x: m.center.x, y: m.center.y + arm))
            stroke(cross, halo, width: ApertureOutline.haloWidth)
            stroke(cross, yellow, width: ApertureOutline.lineWidth)
        }
    }

    // MARK: Region

    /// A region's outline over a map's grid, stroked in `box` (view points, y down) along `RegionOutline`'s path.
    static func drawRegion(_ shape: SpectrumRegionShape, _ stroke: RegionStroke, gridWidth: Int, gridHeight: Int,
                           box: CGSize, in ctx: CGContext) {
        guard gridWidth > 0, gridHeight > 0 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(stroke.color); ctx.setLineWidth(stroke.width); ctx.setLineDash(phase: 0, lengths: stroke.dash)
        ctx.addPath(RegionOutline.path(shape, cellWidth: box.width / CGFloat(gridWidth), cellHeight: box.height / CGFloat(gridHeight)))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Figure

    /// The panels in one labelled image on black, laid out by `FigureLayout`, `scale` pixels per point. nil when there is nothing to
    /// draw, the figure would pass `FigureLayout.maximumPixels` on a side, or the context cannot be made.
    static func render(_ panels: [FigurePanel], scale: Int) -> CGImage? {
        let s = max(scale, 1)
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        let size = FigureLayout.pixelSize(plan, scale: s)
        guard !panels.isEmpty, size.width > 0, size.height > 0,
              size.width <= FigureLayout.maximumPixels, size.height <= FigureLayout.maximumPixels,
              let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        compose(panels, plan: plan, scale: s, vector: false, in: ctx)
        return ctx.makeImage()
    }

    /// The same figure as a one-page PDF, its page the figure's size in points: the labels, outlines and scale bars are text and
    /// paths that stay sharp at any zoom; each map is an image enlarged to its laid-out size. nil with nothing to draw.
    static func renderPDF(_ panels: [FigurePanel]) -> Data? {
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        guard !panels.isEmpty, plan.size.width > 0, plan.size.height > 0,
              plan.size.width <= CGFloat(FigureLayout.maximumPixels), plan.size.height <= CGFloat(FigureLayout.maximumPixels) else { return nil }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: plan.size)
        let info = [kCGPDFContextCreator: "mac4DSTEM", kCGPDFContextTitle: "Figure"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, info) else { return nil }
        ctx.beginPDFPage(nil)
        compose(panels, plan: plan, scale: 1, vector: true, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    /// Black ground, then each panel and its label in its cell. `vector` hands the maps to the context already enlarged.
    private static func compose(_ panels: [FigurePanel], plan: FigureLayout.Plan, scale s: Int, vector: Bool, in ctx: CGContext) {
        let size = FigureLayout.pixelSize(plan, scale: s)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let height = CGFloat(size.height), device = CGFloat(s)
        for (panel, cell) in zip(panels, plan.cells) {
            draw(panel, in: ctx,
                 rect: CGRect(x: cell.imageRect.minX * device, y: height - cell.imageRect.maxY * device,
                              width: cell.imageRect.width * device, height: cell.imageRect.height * device),
                 magnification: cell.magnification, deviceScale: s, embedFactor: vector ? cell.magnification : 1)
            drawLabel(cell.label, in: CGRect(x: cell.labelRect.minX * device, y: height - cell.labelRect.maxY * device,
                                             width: cell.labelRect.width * device, height: cell.labelRect.height * device),
                      scale: device, in: ctx)
        }
    }

    /// A panel's label, white and semibold (Core Text, so it is a font in a PDF and a bitmap in a PNG), on the baseline of its band
    /// (`rect`, pixels, y up); a label wider than the band is cut with an ellipsis.
    static func drawLabel(_ label: String, in rect: CGRect, scale: CGFloat, in ctx: CGContext) {
        guard !label.isEmpty else { return }
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 13 * scale, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 13 * scale, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any]
        guard let text = CFAttributedStringCreate(nil, label as CFString, attributes as CFDictionary),
              let ellipsis = CFAttributedStringCreate(nil, "\u{2026}" as CFString, attributes as CFDictionary) else { return }
        var line = CTLineCreateWithAttributedString(text)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(rect.width),
           let cut = CTLineCreateTruncatedLine(line, Double(rect.width), .end, CTLineCreateWithAttributedString(ellipsis)) {
            line = cut
        }
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + 5 * scale)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

extension Color {
    /// The colour as the Core Graphics colour the drawing contexts take, at `opacity`, resolved in `scheme`. SwiftUI's system colours
    /// have a light and a dark variant (cyan most: (0, 0.75, 0.91) light, (0.24, 0.83, 1.0) dark) and the pane draws the variant of
    /// the app's appearance, so an export is resolved in the same appearance (`FigureColors.scheme`: the Settings preference, else the
    /// system's) and carries the colour the pane showed when it was made. The default is dark, the appearance a figure on black reads in.
    func cgColor(opacity: Double = 1, scheme: ColorScheme = .dark) -> CGColor {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = resolve(in: environment).cgColor
        return opacity == 1 ? resolved : (resolved.copy(alpha: CGFloat(opacity)) ?? resolved)
    }
}
