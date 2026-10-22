import ShellLayout
import AppKit
import ImageIO
import PDFKit
import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
@testable import mac4DSTEM

/// Talk-quality figure export (tier 2, 2026-10-14): the detector outlined on the diffraction pattern, the regions on the EDX maps,
/// several images in one labelled figure, and 1x/2x/3x pixels. Every test renders into pixels and reads them; each names the
/// mutation that turns it red.
@MainActor
final class FigureExportTests: XCTestCase {

    // MARK: pixels

    private struct Raster {
        let w: Int, h: Int, bytes: [UInt8]
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * w + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
    }

    /// Row 0 is the top of the image.
    private func raster(_ image: CGImage) -> Raster {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Raster(w: image.width, h: image.height, bytes: Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4)))
    }

    /// The first page of a PDF drawn at `scale` pixels per point on white.
    private func raster(pdf data: Data, scale: CGFloat) throws -> Raster {
        let page = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: data as CFData)))?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let w = Int(box.width * scale), h = Int(box.height * scale)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        return Raster(w: w, h: h, bytes: Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4)))
    }

    private func solid(_ w: Int, _ h: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { bytes[i * 4] = r; bytes[i * 4 + 1] = g; bytes[i * 4 + 2] = b }
        return AppState.cgImage(rgba: bytes, width: w, height: h)!
    }

    /// The pixels `score` marks, weighted: their centroid, mean distance from it and extent.
    private struct Blob { var cx = 0.0, cy = 0.0, meanRadius = 0.0, minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min, count = 0 }
    private func blob(_ r: Raster, score: (Int, Int, Int) -> Int, minimum: Int = 60) -> Blob {
        var sum = 0.0, sx = 0.0, sy = 0.0
        var found: [(x: Int, y: Int, w: Double)] = []
        for y in 0..<r.h { for x in 0..<r.w {
            let c = r.rgb(x, y), s = score(c.r, c.g, c.b)
            guard s >= minimum else { continue }
            found.append((x, y, Double(s))); sum += Double(s); sx += Double(s) * (Double(x) + 0.5); sy += Double(s) * (Double(y) + 0.5)
        } }
        guard sum > 0 else { return Blob() }
        var b = Blob(cx: sx / sum, cy: sy / sum, count: found.count)
        var rad = 0.0
        for p in found {
            rad += p.w * hypot(Double(p.x) + 0.5 - b.cx, Double(p.y) + 0.5 - b.cy)
            b.minX = min(b.minX, p.x); b.maxX = max(b.maxX, p.x); b.minY = min(b.minY, p.y); b.maxY = max(b.maxY, p.y)
        }
        b.meanRadius = rad / sum
        return b
    }
    private func yellow(_ r: Int, _ g: Int, _ b: Int) -> Int { max(0, (r + g) / 2 - b) }
    private func red(_ r: Int, _ g: Int, _ b: Int) -> Int { max(0, r - (g + b) / 2) }

    // MARK: the layout

    /// Mutation: `columns(for: 4)` returns 4 (one row of four), or a fifth panel starts a fourth column - red.
    func testColumnsFollowThePanelCount() {
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 9].map(FigureLayout.columns(for:)), [0, 1, 2, 3, 2, 3, 3, 3])
    }

    /// A panel is enlarged by the whole factor nearest the target box, never below 1. Mutation: `.rounded()` becomes `.up` or
    /// the width is left out of the `min` - red.
    func testMagnificationIsTheWholeFactorNearestTheTargetBox() {
        XCTAssertEqual(FigureLayout.magnification(width: 64, height: 48), 8, "a Velox-sized EDX map: 7.5 rounds up")
        XCTAssertEqual(FigureLayout.magnification(width: 256, height: 256), 2, "a detector: 1.56 rounds to 2")
        XCTAssertEqual(FigureLayout.magnification(width: 100, height: 100), 4)
        XCTAssertEqual(FigureLayout.magnification(width: 215, height: 926), 1, "never below 1: a tall strip is not resampled")
        XCTAssertEqual(FigureLayout.magnification(width: 4000, height: 4000), 1)
        XCTAssertEqual(FigureLayout.magnification(width: 1000, height: 40), 1, "the width limits a wide strip as well as the height")
    }

    /// Three panels: one row, labels in order, every rectangle inside the canvas, none on another, each label directly over its image.
    /// Mutation: the column offset adds no gap, a cell takes the previous cell's x, or the label band is left out of the height - red.
    func testThreePanelsStandInOneRowWithoutOverlap() {
        let plan = FigureLayout.plan([("a", 64, 48), ("b", 256, 256), ("c", 215, 926)])
        XCTAssertEqual(plan.columns, 3)
        XCTAssertEqual(plan.cells.map(\.label), ["a", "b", "c"])
        XCTAssertEqual(plan.cells.map(\.magnification), [8, 2, 1])
        XCTAssertEqual(plan.cells.map(\.imageRect.size), [CGSize(width: 512, height: 384), CGSize(width: 512, height: 512), CGSize(width: 215, height: 926)])
        XCTAssertEqual(plan.size, CGSize(width: 32 + 512 + 512 + 215 + 32, height: 32 + 22 + 926), "margins, the three columns and gaps; the tallest image and its label band")
        let canvas = CGRect(origin: .zero, size: plan.size)
        for (i, cell) in plan.cells.enumerated() {
            XCTAssertTrue(canvas.contains(cell.imageRect) && canvas.contains(cell.labelRect), "cell \(i) inside the canvas")
            XCTAssertEqual(cell.labelRect.maxY, cell.imageRect.minY, "the label band sits on its image")
            XCTAssertEqual(cell.labelRect.minX, cell.imageRect.minX)
            for other in plan.cells.dropFirst(i + 1) {
                XCTAssertFalse(cell.imageRect.intersects(other.imageRect), "images \(i) and \(other.index) overlap")
                XCTAssertFalse(cell.labelRect.intersects(other.labelRect))
                XCTAssertFalse(cell.imageRect.intersects(other.labelRect))
            }
        }
    }

    /// Four panels stand two by two: the second row starts under the first row's tallest image, label band and gap included.
    /// Mutation: the row offset forgets the label band or the gap - red.
    func testFourPanelsStandTwoByTwo() {
        let plan = FigureLayout.plan([("a", 100, 100), ("b", 100, 100), ("c", 100, 100), ("d", 100, 100)])
        XCTAssertEqual(plan.columns, 2)
        XCTAssertEqual(plan.size, CGSize(width: 32 + 800 + 16, height: 32 + 2 * (22 + 400) + 16))
        XCTAssertEqual(plan.cells[2].labelRect.origin, CGPoint(x: 16, y: 16 + 22 + 400 + 16))
        XCTAssertEqual(plan.cells[3].imageRect.origin, CGPoint(x: 16 + 400 + 16, y: 16 + 22 + 400 + 16 + 22))
    }

    /// The pixel size is the point size times the scale, exactly. Mutation: the scale multiplies only one side - red.
    func testPixelSizeIsPointsTimesScale() {
        let plan = FigureLayout.plan([("a", 64, 48), ("b", 100, 100)])
        for s in 1...3 {
            let px = FigureLayout.pixelSize(plan, scale: s)
            XCTAssertEqual(CGFloat(px.width), plan.size.width * CGFloat(s))
            XCTAssertEqual(CGFloat(px.height), plan.size.height * CGFloat(s))
        }
    }

    // MARK: the figure

    /// A 2x figure is the 1x figure with twice the pixels each way, a 3x one three times. Mutation: `render` ignores `scale` - red.
    func testTheFigureIsExactlyScaleTimesTheOneXFigure() throws {
        let panels = [FigurePanel(label: "Red", image: solid(32, 24, 200, 20, 20)), FigurePanel(label: "Green", image: solid(40, 40, 20, 200, 20))]
        let one = try XCTUnwrap(FigureRendering.render(panels, scale: 1))
        for s in 2...3 {
            let img = try XCTUnwrap(FigureRendering.render(panels, scale: s))
            XCTAssertEqual(img.width, one.width * s); XCTAssertEqual(img.height, one.height * s)
        }
    }

    /// Each image is in its own cell, the gap between is the black background, and each label has ink on its band.
    /// Mutation: the panels are drawn in reversed order, a label is not drawn, or the label band is drawn at the image's row - red.
    func testEachPanelLandsInItsCellAndEachLabelIsDrawn() throws {
        let panels = [FigurePanel(label: "Red panel", image: solid(32, 24, 200, 20, 20)), FigurePanel(label: "", image: solid(40, 40, 20, 200, 20))]
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        for s in [1, 2] {
            let r = raster(try XCTUnwrap(FigureRendering.render(panels, scale: s)))
            func at(_ p: CGPoint) -> (r: Int, g: Int, b: Int) { r.rgb(Int(p.x) * s, Int(p.y) * s) }
            let first = plan.cells[0].imageRect, second = plan.cells[1].imageRect
            let a = at(CGPoint(x: first.midX, y: first.midY)), b = at(CGPoint(x: second.midX, y: second.midY))
            XCTAssertTrue(a.r > 150 && a.g < 60, "panel 0 is red in its cell (\(a)) at \(s)x")
            XCTAssertTrue(b.g > 150 && b.r < 60, "panel 1 is green in its cell (\(b)) at \(s)x")
            let gap = at(CGPoint(x: first.maxX + 8, y: first.midY))
            XCTAssertTrue(gap.r < 10 && gap.g < 10 && gap.b < 10, "between the panels the figure is black")
            func ink(_ band: CGRect) -> Int {
                var n = 0
                for y in Int(band.minY) * s..<Int(band.maxY) * s { for x in Int(band.minX) * s..<Int(band.maxX) * s {
                    let c = r.rgb(x, y); if c.r > 128 && c.g > 128 && c.b > 128 { n += 1 }
                } }
                return n
            }
            XCTAssertGreaterThan(ink(plan.cells[0].labelRect), 40 * s, "the first label is drawn in its band at \(s)x")
            XCTAssertEqual(ink(plan.cells[1].labelRect), 0, "an empty label draws nothing")
        }
    }

    /// An empty figure and one wider than the limit are refused, not allocated. Mutation: the limit check is dropped - red (the
    /// 5500 px strip at 3x would be 16 596 px wide).
    func testAnEmptyOrOversizeFigureIsRefused() {
        XCTAssertNil(FigureRendering.render([], scale: 1))
        let strip = [FigurePanel(label: "wide", image: solid(5500, 4, 1, 2, 3))]
        XCTAssertNotNil(FigureRendering.render(strip, scale: 1))
        XCTAssertNil(FigureRendering.render(strip, scale: 3))
    }

    // MARK: the detector outline

    private func pattern64() -> CGImage { solid(64, 64, 100, 100, 100) }

    private func detectorPanel(_ aperture: Aperture, _ shape: VirtualShapeMode) -> FigurePanel {
        FigurePanel(label: "", image: pattern64(), overlays: [.detector(aperture, shape, .dark)])
    }

    /// The pane's geometry, in view points: pixel-centre half offset, the mean axis scale, the radii. Mutation: `center` loses the
    /// half pixel, `radiusScale` uses one axis, or `inner` is taken from `outer` - red.
    func testTheApertureMetricsAreThePanesGeometry() {
        let m = ApertureOutline.metrics(aperture: Aperture(centerX: 32, centerY: 30, inner: 8, outer: 20),
                                        patternWidth: 64, patternHeight: 64, box: CGSize(width: 320, height: 256))
        XCTAssertEqual(m.scaleX, 5); XCTAssertEqual(m.scaleY, 4)
        XCTAssertEqual(m.radiusScale, 4.5)
        XCTAssertEqual(m.center.x, 32.5 * 5, accuracy: 1e-9); XCTAssertEqual(m.center.y, 30.5 * 4, accuracy: 1e-9)
        XCTAssertEqual(m.outer, 90, accuracy: 1e-9); XCTAssertEqual(m.inner, 36, accuracy: 1e-9)
    }

    /// An annulus: the outer edge is a yellow circle of the aperture's radius round the pixel centre; the inner edge a dashed cyan
    /// one; nothing between, inside or outside, and no handle at the centre. Mutations: the half pixel dropped from the centre (a 2 px
    /// shift at 4x), the radius halved, the inner dash removed (a solid ring), a handle drawn - red.
    func testAnAnnulusIsOutlinedWhereThePaneDrawsIt() throws {
        let img = try XCTUnwrap(FigureRendering.rendered(detectorPanel(Aperture(centerX: 32, centerY: 30, inner: 8, outer: 20), .annulus),
                                                         magnification: 4, deviceScale: 1))
        XCTAssertEqual(img.width, 256)
        let r = raster(img)
        let ring = blob(r, score: yellow)
        XCTAssertEqual(ring.cx, 130, accuracy: 0.3); XCTAssertEqual(ring.cy, 122, accuracy: 0.3)
        XCTAssertEqual(ring.meanRadius, 80, accuracy: 0.7)
        func sample(radius: Double, angle: Double) -> (r: Int, g: Int, b: Int) {
            r.rgb(Int(130 + radius * cos(angle)), Int(122 + radius * sin(angle)))
        }
        let angles = (0..<120).map { Double($0) * 2 * .pi / 120 }
        let cyan = angles.filter { let c = sample(radius: 32, angle: $0); return c.b - c.r > 80 }.count
        XCTAssertGreaterThan(Double(cyan) / 120, 0.35, "the inner edge is cyan along part of its length")
        XCTAssertLessThan(Double(cyan) / 120, 0.8, "and dashed: it is not a solid ring")
        for radius in [0.0, 60, 110] {
            for angle in angles.prefix(40) {
                let c = sample(radius: radius, angle: angle)
                XCTAssertTrue(abs(c.r - 100) < 3 && abs(c.g - 100) < 3 && abs(c.b - 100) < 3, "r=\(radius): the pattern is untouched (\(c))")
            }
        }
    }

    /// A circle has no inner edge: only the yellow outer one. Mutation: the circle case draws the inner edge, or `.annulus` is the
    /// only shape that gets an outer edge - red.
    func testACircleHasOnlyItsOuterEdge() throws {
        let r = raster(try XCTUnwrap(FigureRendering.rendered(detectorPanel(Aperture(centerX: 32, centerY: 30, inner: 8, outer: 20), .circle),
                                                              magnification: 4, deviceScale: 1)))
        XCTAssertEqual(blob(r, score: yellow).meanRadius, 80, accuracy: 0.7)
        let atInner = r.rgb(130 + 32, 122)
        XCTAssertTrue(abs(atInner.r - 100) < 3 && abs(atInner.b - 100) < 3, "no cyan inner edge on a circle")
    }

    /// A square detector: `outer` is the half-extent, so the outline spans centre +- outer on both axes. Mutation: the extent is
    /// the diameter or the radius of a circle - red.
    func testARectangleSpansItsHalfExtentEachWay() throws {
        let r = raster(try XCTUnwrap(FigureRendering.rendered(detectorPanel(Aperture(centerX: 32, centerY: 30, inner: 0, outer: 20), .rectangle),
                                                              magnification: 4, deviceScale: 1)))
        let b = blob(r, score: yellow)
        XCTAssertEqual(Double(b.minX), 49, accuracy: 1.5); XCTAssertEqual(Double(b.maxX), 210, accuracy: 1.5)
        XCTAssertEqual(Double(b.minY), 41, accuracy: 1.5); XCTAssertEqual(Double(b.maxY), 201, accuracy: 1.5)
        XCTAssertEqual(b.cx, 130, accuracy: 0.3); XCTAssertEqual(b.cy, 122, accuracy: 0.3)
    }

    /// A point detector is a crosshair of fixed arms (8 view points), not scaled with the radius. Mutation: arms scaled by the
    /// magnification or drawn as a circle - red.
    func testAPointIsACrosshair() throws {
        let r = raster(try XCTUnwrap(FigureRendering.rendered(detectorPanel(Aperture(centerX: 32, centerY: 30, inner: 0, outer: 20), .point),
                                                              magnification: 4, deviceScale: 1)))
        let b = blob(r, score: yellow)
        XCTAssertEqual(Double(b.minX), 122, accuracy: 1.5); XCTAssertEqual(Double(b.maxX), 138, accuracy: 1.5)
        XCTAssertEqual(Double(b.minY), 114, accuracy: 1.5); XCTAssertEqual(Double(b.maxY), 130, accuracy: 1.5)
        XCTAssertLessThan(b.count, 120, "two thin lines, not a disc")
    }

    /// At 2x the same outline is drawn at twice the pixels, not enlarged afterwards: the ring's radius doubles and its width does too.
    /// Mutation: `deviceScale` is not applied to the line widths, or the overlay is drawn before the enlargement - red.
    func testTheOutlineIsDrawnAtTheExportScale() throws {
        let panel = detectorPanel(Aperture(centerX: 32, centerY: 30, inner: 0, outer: 20), .circle)
        let one = blob(raster(try XCTUnwrap(FigureRendering.rendered(panel, magnification: 4, deviceScale: 1))), score: yellow)
        let two = blob(raster(try XCTUnwrap(FigureRendering.rendered(panel, magnification: 4, deviceScale: 2))), score: yellow)
        XCTAssertEqual(two.meanRadius, 2 * one.meanRadius, accuracy: 1.2)
        XCTAssertEqual(two.cx, 2 * one.cx, accuracy: 0.5)
        XCTAssertGreaterThan(Double(two.count), 2.5 * Double(one.count), "a line twice as wide on a ring twice as long")
    }

    // MARK: the region outline

    private func mapPanel(_ shape: SpectrumRegionShape, dash: [CGFloat] = [], magnification: Int = 10) -> CGImage {
        let red = RegionStroke(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1), width: 2, dash: dash)
        return FigureRendering.rendered(FigurePanel(label: "", image: solid(20, 10, 100, 100, 100), overlays: [.region(shape, red)]),
                                        magnification: magnification, deviceScale: 1)!
    }
    private func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 200 && c.g < 60 && c.b < 60 }
    private func isGray(_ c: (r: Int, g: Int, b: Int)) -> Bool { abs(c.r - 100) < 3 && abs(c.g - 100) < 3 && abs(c.b - 100) < 3 }

    /// A rectangle: its four edges at the region's pixel borders (x 4..12, y 2..7 on a 10x grid), nothing inside or outside.
    /// Mutation: x and y swap, the border moves by a pixel, or the box is filled - red.
    func testARectangleRegionIsOutlinedAtItsPixelBorders() {
        let r = raster(mapPanel(.rectangle(PixelRect(x0: 4, y0: 2, x1: 12, y1: 7))))
        XCTAssertEqual(r.w, 200); XCTAssertEqual(r.h, 100)
        XCTAssertTrue(isRed(r.rgb(40, 45)) || isRed(r.rgb(39, 45)), "left edge")
        XCTAssertTrue(isRed(r.rgb(120, 45)) || isRed(r.rgb(119, 45)), "right edge")
        XCTAssertTrue(isRed(r.rgb(80, 20)) || isRed(r.rgb(80, 19)), "top edge")
        XCTAssertTrue(isRed(r.rgb(80, 70)) || isRed(r.rgb(80, 69)), "bottom edge")
        XCTAssertTrue(isRed(r.rgb(40, 20)) || isRed(r.rgb(39, 19)), "the corner is on the outline")
        XCTAssertTrue(isGray(r.rgb(80, 45)), "inside is the map")
        XCTAssertTrue(isGray(r.rgb(20, 45)) && isGray(r.rgb(160, 45)) && isGray(r.rgb(80, 90)), "outside is the map")
    }

    /// An ellipse is inscribed in its rectangle: it touches the four edge midpoints and not the corners. Mutation: `RegionOutline`
    /// strokes the bounding rectangle for an ellipse - red.
    func testAnEllipseRegionTouchesTheEdgeMidpointsAndNotTheCorners() {
        let r = raster(mapPanel(.ellipse(PixelRect(x0: 4, y0: 2, x1: 12, y1: 7))))
        XCTAssertTrue(isRed(r.rgb(40, 45)) || isRed(r.rgb(39, 45)), "left midpoint")
        XCTAssertTrue(isRed(r.rgb(80, 20)) || isRed(r.rgb(80, 19)), "top midpoint")
        XCTAssertTrue(isGray(r.rgb(40, 20)) && isGray(r.rgb(119, 69)), "the rectangle's corners are outside the ellipse")
        XCTAssertTrue(isGray(r.rgb(80, 45)))
    }

    /// A polygon follows its vertices (grid pixel units). Mutation: the vertices are not scaled to the map, or the polygon is not closed
    /// back to its first vertex - red.
    func testAPolygonRegionFollowsItsVertices() {
        let r = raster(mapPanel(.polygon([PixelPoint(x: 2, y: 1), PixelPoint(x: 18, y: 1), PixelPoint(x: 10, y: 9)])))
        XCTAssertTrue(isRed(r.rgb(100, 10)) || isRed(r.rgb(100, 9)), "the top edge's midpoint")
        XCTAssertTrue(isRed(r.rgb(60, 50)) || isRed(r.rgb(59, 50)) || isRed(r.rgb(61, 50)), "the closing edge from the last vertex back to the first (x = 60 at y = 50)")
        XCTAssertTrue(isGray(r.rgb(100, 40)), "inside is the map")
        XCTAssertTrue(isGray(r.rgb(10, 80)), "outside is the map")
    }

    /// The path both the screen and the export stroke. Mutation: the ellipse case returns the rectangle path, or `cellWidth` and
    /// `cellHeight` are swapped - red.
    func testTheRegionPathIsInTheMapsCells() {
        let rect = RegionOutline.path(.rectangle(PixelRect(x0: 4, y0: 2, x1: 12, y1: 7)), cellWidth: 10, cellHeight: 5)
        XCTAssertEqual(rect.boundingBox, CGRect(x: 40, y: 10, width: 80, height: 25))
        let ellipse = RegionOutline.path(.ellipse(PixelRect(x0: 4, y0: 2, x1: 12, y1: 7)), cellWidth: 10, cellHeight: 5)
        XCTAssertEqual(ellipse.boundingBox, CGRect(x: 40, y: 10, width: 80, height: 25))
        XCTAssertTrue(ellipse.contains(CGPoint(x: 80, y: 22)))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 41, y: 11)), "a corner of the box is outside the ellipse")
        let polygon = RegionOutline.path(.polygon([PixelPoint(x: 1, y: 1), PixelPoint(x: 5, y: 1), PixelPoint(x: 3, y: 4)]), cellWidth: 10, cellHeight: 5)
        XCTAssertEqual(polygon.boundingBox, CGRect(x: 10, y: 5, width: 40, height: 15))
    }

    // MARK: the room's regions

    private func tile(_ z: Int, _ w: Int, _ h: Int) -> MapTile {
        var t = MapTile(z: z, width: w, height: h, values: (0..<(w * h)).map { Float($0 % 17) / 17 })
        t.scale = 100
        return t
    }
    /// A 64 x 64 scan with one element, a HAADF and a stated pixel size (0.5 nm), the scale bar off, a region drawn.
    private func regionModel(regions: Bool = true, scaleBar: Bool = false) -> SpectroscopyRoomModel {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = [tile(13, 64, 64)]
        m.mixed = [13]; m.gridWidth = 64; m.gridHeight = 64
        m.backdrop = (0..<4096).map { Float($0 % 31) / 31 }
        m.export.mapsStem = "scan"
        m.export.scaleBar = scaleBar
        m.export.regions = regions
        m.scanPixel = (size: 0.5, unit: "nm")
        m.regionOutline = .rectangle(PixelRect(x0: 10, y0: 12, x1: 40, y1: 50))
        return m
    }
    private func decode(_ data: Data) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)! }
    private func strokes(_ overlays: [FigureOverlay]) -> [RegionStroke] {
        overlays.compactMap { if case .region(_, let s) = $0 { s } else { nil } }
    }

    /// The regions the screen draws on the ColorMix: the live region dashed 4-3 at 2 pt in the accent colour, each pin solid at 1.6 pt in
    /// its tint at 0.6; none without a region, none for a pin hidden by the Show layer, none for a pin without a shape.
    /// Mutation: the pins are drawn when their layer is off, the live stroke loses its dash, or a pin takes the live width - red.
    func testTheRegionOverlaysAreWhatTheColorMixDraws() {
        let m = regionModel()
        let live = strokes(MapsExport.regionOverlays(m))
        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(live[0].width, RegionStrokeWidth.live); XCTAssertEqual(live[0].dash, [4, 3])
        m.pins = [PinnedRegion(id: 0, label: "p", tint: .pink, shape: .ellipse(PixelRect(x0: 1, y0: 1, x1: 9, y1: 9)), pixels: 64, spectrum: [], sourceRegion: nil),
                  PinnedRegion(id: 1, label: "q", tint: .teal, shape: nil, pixels: 0, spectrum: [], sourceRegion: nil)]
        let both = strokes(MapsExport.regionOverlays(m))
        XCTAssertEqual(both.count, 2, "the live region and the one pin that has a shape")
        XCTAssertEqual(both[1].width, RegionStrokeWidth.pin); XCTAssertEqual(both[1].dash, [])
        XCTAssertEqual(both[1].color.alpha, CGFloat(SpectrumLayers.pinOpacity), accuracy: 1e-6)
        m.layers.pins = false
        XCTAssertEqual(strokes(MapsExport.regionOverlays(m)).count, 1, "a hidden pin is not exported")
        m.regionOutline = nil
        XCTAssertEqual(MapsExport.regionOverlays(m).count, 0, "no region, no outline")
    }

    /// The live region's dash survives the export: along an edge about 4 pixels of 7 are inked.
    /// Mutation: `drawRegion` ignores `stroke.dash` (a solid line) - red.
    func testTheLiveRegionIsDashedInTheExport() throws {
        let m = regionModel(); m.regionOutline = .rectangle(PixelRect(x0: 4, y0: 4, x1: 36, y1: 16))
        let r = raster(try XCTUnwrap(FigureRendering.rendered(
            FigurePanel(label: "", image: solid(40, 20, 20, 20, 20), overlays: MapsExport.regionOverlays(m)), magnification: 10, deviceScale: 1)))
        // the top edge is y = 40 (a 2 px stroke: rows 39 and 40); count the inked columns between x = 60 and x = 340
        let inked = (60..<340).filter { x in [39, 40].contains { y in let c = r.rgb(x, y); return max(c.r, c.g, c.b) > 80 } }.count
        let fraction = Double(inked) / 280
        XCTAssertGreaterThan(fraction, 0.35); XCTAssertLessThan(fraction, 0.8)
    }

    // MARK: the Maps export

    /// With a region drawn and the option on, every map PNG carries the outline and its name says so; the CSV does not. With the option
    /// off the files are what they were. Mutations: `files` ignores `export.regions`, draws the outline on the ColorMix only, or tags
    /// the CSV - red.
    func testTheMapsExportOutlinesTheRegionOnEveryMapWhenAsked() throws {
        let on = try MapsExport.files(regionModel(regions: true)), off = try MapsExport.files(regionModel(regions: false))
        let symbol = PeriodicLayout.symbol(13)
        XCTAssertEqual(on.map(\.name), ["scan-HAADF-region.png", "scan-\(symbol)-region.png", "scan-ColorMix-region.png", "scan-maps.csv"])
        XCTAssertEqual(off.map(\.name), ["scan-HAADF.png", "scan-\(symbol).png", "scan-ColorMix.png", "scan-maps.csv"])
        XCTAssertEqual(on.last?.data, off.last?.data, "the CSV never changes")
        for (a, b) in zip(on.dropLast(), off.dropLast()) {
            let ra = raster(decode(a.data)), rb = raster(decode(b.data))
            XCTAssertEqual(ra.w, 64)
            func px(_ r: Raster, _ x: Int, _ y: Int) -> [Int] { let c = r.rgb(x, y); return [c.r, c.g, c.b] }
            // the region (10,12)-(40,50) of a 64 grid at 1 px per scan pixel: its left edge is x = 9 and 10; the dash leaves gaps, so
            // look along the whole edge
            let changed = (14..<48).filter { y in [9, 10].contains { px(ra, $0, y) != px(rb, $0, y) } }.count
            XCTAssertGreaterThan(changed, 10, "\(a.name): the left edge is outlined")
            XCTAssertEqual(px(ra, 25, 30), px(rb, 25, 30), "\(a.name): the inside is the map")
            XCTAssertTrue(px(ra, 3, 3) == px(rb, 3, 3) && px(ra, 60, 60) == px(rb, 60, 60), "\(a.name): the outside is the map")
        }
        XCTAssertTrue(ExportSettings().regions, "on to begin with, like the scale bar")
    }

    /// No region, no outline and no tag, whatever the option says. Mutation: the tag is added whenever the option is on - red.
    func testNoRegionMeansNoOutlineAndNoTag() throws {
        let m = regionModel(regions: true); m.regionOutline = nil
        let names = try MapsExport.files(m).map(\.name)
        XCTAssertEqual(names.filter { $0.contains("region") }, [])
    }

    /// 2x and 3x write every PNG at that many pixels per scan pixel, name it so, tag it 144 / 216 ppi and draw the bar and the outline
    /// at the larger size. Mutations: the scale reaches only the name, the density is not written, or the bar keeps its 1x length - red.
    func testTheMapsExportAtTwoAndThreeTimes() throws {
        let one = try MapsExport.files(regionModel(scaleBar: true), pixelScale: 1)
        let plan = try XCTUnwrap(MapScaleBar.tilePlan(pixelSize: 0.5, unit: "nm", pointsPerPixel: 1, width: 64))
        for s in [2, 3] {
            let files = try MapsExport.files(regionModel(scaleBar: true), pixelScale: s)
            XCTAssertEqual(files.map(\.name), one.map(\.name).map { $0.hasSuffix(".png") ? $0.replacingOccurrences(of: ".png", with: "-\(s)x.png") : $0 })
            XCTAssertEqual(files.last?.data, one.last?.data, "the CSV is the raw numbers at any size")
            for f in files.dropLast() {
                let src = try XCTUnwrap(CGImageSourceCreateWithData(f.data as CFData, nil))
                let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
                XCTAssertEqual(img.width, 64 * s); XCTAssertEqual(img.height, 64 * s)
                let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
                XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Double ?? 0, 72.0 * Double(s), accuracy: 0.5, f.name)
                // the bar (drawn in the element's file, whose pixels are never white): white along the row just above its bottom edge,
                // from x = 8 * s, plan * s long
                guard f.name.contains(PeriodicLayout.symbol(13)) else { continue }
                let r = raster(img)
                let row = r.h - 1 - (8 * s + 1)
                let white = (0..<r.w).filter { let c = r.rgb($0, row); return c.r == 255 && c.g == 255 && c.b == 255 }
                XCTAssertEqual(white.count, Int((plan.lengthPoints * Double(s)).rounded()), f.name)
                XCTAssertEqual(white.first, 8 * s, f.name)
            }
        }
    }

    // MARK: the scale on the single exports

    /// The result figure at 2x / 3x is the 1x figure with that many times the pixels. Mutation: the scale reaches `burnScaleBar` but not
    /// `publicationFigure` (or the reverse) - red.
    func testTheResultFigureIsExactlyScaleTimesTheOneXFigure() throws {
        let state = AppState()
        state.publishProduct(kind: "virtual_annulus", displayName: "Virtual image", valueUnits: "intensity",
                             payload: .scalar(FloatImage(width: 8, height: 6, pixels: (0..<48).map(Float.init))))
        let one = try state.resultExportImage(scale: 1).image
        for s in 2...3 {
            let img = try state.resultExportImage(scale: s).image
            XCTAssertEqual(img.width, one.width * s); XCTAssertEqual(img.height, one.height * s)
        }
    }

    func testBurnScaleBarAndTheCaptionFigureScaleTogether() throws {
        let base = solid(16, 12, 200, 30, 30)
        let one = AppState.burnScaleBar(on: base, unitsPerDataPixel: 0.5, unitLabel: "nm")
        XCTAssertEqual(one.width, 512); XCTAssertEqual(one.height, 384)
        for s in 2...3 {
            let img = AppState.burnScaleBar(on: base, unitsPerDataPixel: 0.5, unitLabel: "nm", pixelScale: s)
            XCTAssertEqual(img.width, 512 * s); XCTAssertEqual(img.height, 384 * s)
            let fig = AppState.publicationFigure(image: img, title: "T", caption: "c", valueRange: (low: 0, high: 1), valueUnits: "u", colormap: .viridis, pixelScale: s)
            let fig1 = AppState.publicationFigure(image: one, title: "T", caption: "c", valueRange: (low: 0, high: 1), valueUnits: "u", colormap: .viridis)
            XCTAssertEqual(fig.width, fig1.width * s); XCTAssertEqual(fig.height, fig1.height * s)
        }
    }

    /// A 2x / 3x PNG carries 144 / 216 ppi, a 1x one nothing extra. Mutation: `pngDensity` returns 72 x scale for 1x, or the figure's
    /// properties drop it - red.
    func testThePNGSaysItsDensity() throws {
        XCTAssertNil(AppState.pngDensity(pixelScale: 1))
        for s in [2, 3] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fig-density-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }
            let props = try XCTUnwrap(AppState.pngProperties(title: "t", record: ["a": 1], pixelScale: s))
            XCTAssertNotNil(props[kCGImagePropertyPNGDictionary], "the provenance chunk is still written")
            XCTAssertTrue(AppState.writePNG(solid(8, 8, 1, 2, 3), to: url, properties: props))
            let read = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil) as? [CFString: Any])
            XCTAssertEqual(read[kCGImagePropertyDPIWidth] as? Double ?? 0, 72.0 * Double(s), accuracy: 0.5)
            XCTAssertEqual(read[kCGImagePropertyDPIHeight] as? Double ?? 0, 72.0 * Double(s), accuracy: 0.5)
        }
    }

    // MARK: the window's panels

    private func windowWithPatternAndResult() -> AppState {
        let state = AppState()
        state.publishProduct(kind: "virtual_annulus", displayName: "Virtual image", valueUnits: "intensity",
                             payload: .scalar(FloatImage(width: 12, height: 10, pixels: (0..<120).map(Float.init))))
        state.currentPattern = DiffractionPattern(qy: 32, qx: 32, pixels: [Float](repeating: 5, count: 1024))   // flat: no yellow of its own under the viridis colormap
        state.aperture = Aperture(centerX: 16, centerY: 16, inner: 0, outer: 6)
        state.navigation.analysisMode = .virtualDetector
        return state
    }

    /// The detector is outlined in the Virtual Detector task, where the pane draws it, and nowhere else. Mutation: the mode guard is
    /// dropped, or the overlay carries the default aperture - red.
    func testTheDetectorIsOutlinedOnlyWhereThePaneDrawsIt() {
        let state = windowWithPatternAndResult()
        guard case .detector(let aperture, let shape, _)? = state.patternExportOverlays.first else { return XCTFail("no detector overlay") }
        XCTAssertEqual(aperture, Aperture(centerX: 16, centerY: 16, inner: 0, outer: 6))
        XCTAssertEqual(shape, state.resultPresentation.virtualShape)
        XCTAssertEqual(state.patternExportOverlays.count, 1)
        state.navigation.analysisMode = .disks
        XCTAssertEqual(state.patternExportOverlays.count, 0, "in another task the pane draws no detector")
        let bare = AppState(); bare.navigation.analysisMode = .virtualDetector
        XCTAssertEqual(bare.patternExportOverlays.count, 0, "no pattern, nothing to outline")
    }

    /// The diffraction export draws the outline where the geometry says and scales: the circle's pixels are yellow round the pixel centre
    /// at the burnt-in enlargement. Mutation: the export passes no overlays - red.
    func testTheDiffractionExportCarriesTheDetector() throws {
        let state = windowWithPatternAndResult()
        state.aperture = Aperture(centerX: 16, centerY: 16, inner: 0, outer: 6)
        state.resultPresentation.virtualShape = .circle
        for s in [1, 2] {
            let r = raster(try state.diffractionExportImage(scale: s))
            XCTAssertEqual(r.w, 512 * s, "a 32 px pattern is enlarged 16x to 512 px, times the scale")
            let ring = blob(r, score: yellow)
            XCTAssertEqual(ring.cx, 16.5 * 16 * Double(s), accuracy: 0.6 * Double(s))
            XCTAssertEqual(ring.cy, 16.5 * 16 * Double(s), accuracy: 0.6 * Double(s))
            XCTAssertEqual(ring.meanRadius, 6 * 16 * Double(s), accuracy: 1.0 * Double(s))
        }
        state.navigation.analysisMode = .disks
        XCTAssertEqual(blob(raster(try state.diffractionExportImage(scale: 1)), score: yellow).count, 0, "outside the Virtual Detector task: no outline")
    }

    /// The choices the window offers, in layout order, with the defaults ticked. Mutation: the pattern is offered without a pattern, the
    /// order changes, or an element is ticked to begin with - red.
    func testTheChoicesFollowTheWindow() {
        XCTAssertEqual(AppState().figureChoices, [])
        let state = windowWithPatternAndResult()
        XCTAssertEqual(state.figureChoices.map(\.id), [FigureChoice.resultID, FigureChoice.patternID])
        XCTAssertEqual(state.figureChoices.map(\.label), ["Virtual image", "Diffraction pattern"])
        XCTAssertEqual(state.figureChoices.map(\.isDefault), [true, true])
        state.patternDisplayMode = .mean
        state.meanPattern = DiffractionPattern(qy: 32, qx: 32, pixels: [Float](repeating: 1, count: 1024))
        XCTAssertEqual(state.figureChoices.last?.label, "Mean diffraction pattern")
        let m = regionModel()
        m.tiles = [tile(13, 64, 64), tile(14, 64, 64)]
        XCTAssertEqual(MapsExport.choices(m).map(\.id), ["map.haadf", "map.colormix", "map.el.13", "map.el.14"])
        XCTAssertEqual(MapsExport.choices(m).map(\.isDefault), [true, true, false, false], "the HAADF and the ColorMix; an element is asked for")
        XCTAssertEqual(MapsExport.choices(m).first { $0.id == "map.colormix" }?.label, MapsExport.colorMixLabel(m))
        m.backdrop = []; m.mixed = []
        XCTAssertEqual(MapsExport.choices(m).map(\.id), ["map.el.13", "map.el.14"], "no HAADF and nothing ticked: no ColorMix")
    }

    /// The listing and the drawing agree, and the maps come in the figure's order.
    func testTheMapsComeInTheFiguresOrder() {
        let m = regionModel()
        m.tiles = [tile(13, 64, 64), tile(14, 64, 64)]
        XCTAssertEqual(MapsExport.figureOrder(MapsExport.maps(m)).map { FigureChoice.mapID($0.map) }, MapsExport.choices(m).map(\.id))
        XCTAssertEqual(MapsExport.maps(m).map { FigureChoice.mapID($0.map) }.last, "map.colormix", "the files list the ColorMix last")
    }

    /// The panels for the ticked ids, labelled, with their bars and the detector on the pattern only; an id the window lacks is skipped.
    /// Mutation: `figurePanels` ignores the ids, labels the pattern like the result, or puts the detector on the result - red.
    func testThePanelsAreTheTickedImagesWithTheirOutlinesAndBars() throws {
        let state = windowWithPatternAndResult()
        let both = state.figurePanels(chosen: [FigureChoice.resultID, FigureChoice.patternID, "map.haadf"])
        XCTAssertEqual(both.map(\.label), ["Virtual image", "Diffraction pattern"], "no spectrum image: the map id is skipped")
        XCTAssertEqual(both[0].overlays.count, 0)
        XCTAssertEqual(both[1].overlays.count, 1)
        XCTAssertEqual(state.figurePanels(chosen: [FigureChoice.patternID]).map(\.label), ["Diffraction pattern"])
        XCTAssertEqual(state.figurePanels(chosen: []).count, 0)
    }

    /// The figure of a window: panels at data resolution, one image, the size the layout says at the chosen scale; refusals say why.
    /// Mutation: `figureImage` ignores `scale`, or the size guard is dropped - red.
    func testTheFigureOfAWindow() throws {
        let state = windowWithPatternAndResult()
        let ids: Set<String> = [FigureChoice.resultID, FigureChoice.patternID]
        let plan = FigureLayout.plan(state.figurePanels(chosen: ids).map { ($0.label, $0.image.width, $0.image.height) })
        for s in [1, 2, 3] {
            let made = try state.figureImage(chosen: ids, scale: s)
            XCTAssertEqual(made.panels.count, 2)
            XCTAssertEqual(made.image.width, Int(plan.size.width) * s); XCTAssertEqual(made.image.height, Int(plan.size.height) * s)
        }
        XCTAssertThrowsError(try state.figureImage(chosen: [], scale: 1)) { XCTAssertEqual($0.localizedDescription, "Pick at least one image for the figure.") }
    }

    /// The figure's provenance names its panels and its scale. Mutation: the record drops the scale or the panel labels - red.
    func testTheFigureRecordsItsPanelsAndScale() throws {
        let state = windowWithPatternAndResult()
        let made = try state.figureImage(chosen: [FigureChoice.resultID, FigureChoice.patternID], scale: 2)
        let record = state.figureProvenanceRecord(made.panels, scale: 2)
        XCTAssertEqual(record["panels"] as? [String], ["Virtual image", "Diffraction pattern"])
        XCTAssertEqual(record["export_scale"] as? Int, 2)
        XCTAssertNotNil(AppState.pngProperties(title: "Figure", record: record, pixelScale: 2), "the record is valid JSON")
    }

    // MARK: the Maps export folder

    /// Folder names count up the way Finder numbers copies. Mutation: `freeFolderName` ignores what exists, or starts counting at 1 - red.
    func testAFreeFolderNameCountsUp() {
        let parent = URL(fileURLWithPath: "/tmp/x")
        func taken(_ names: [String]) -> (URL) -> Bool { { names.contains($0.lastPathComponent) } }
        XCTAssertEqual(MapsExport.freeFolderName("scan-maps", in: parent, exists: taken([])), "scan-maps")
        XCTAssertEqual(MapsExport.freeFolderName("scan-maps", in: parent, exists: taken(["scan-maps"])), "scan-maps 2")
        XCTAssertEqual(MapsExport.freeFolderName("scan-maps", in: parent, exists: taken(["scan-maps", "scan-maps 2"])), "scan-maps 3")
        XCTAssertEqual(MapsExport.folderName(stem: "scan"), "scan-maps")
    }

    /// A second export lands in a second folder and the first is untouched: no file is ever replaced. Mutation: `writeInNewFolder` writes
    /// into the parent (or reuses the first folder) - red.
    func testASecondMapsExportNeverReplacesTheFirst() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("maps-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let first = try MapsExport.writeInNewFolder([MapsExport.File(name: "a.png", data: Data("one".utf8))], in: parent, named: "scan-maps")
        let second = try MapsExport.writeInNewFolder([MapsExport.File(name: "a.png", data: Data("two".utf8))], in: parent, named: "scan-maps")
        XCTAssertEqual(first.folder.lastPathComponent, "scan-maps"); XCTAssertEqual(second.folder.lastPathComponent, "scan-maps 2")
        XCTAssertEqual(first.names, ["a.png"])
        XCTAssertEqual(try Data(contentsOf: first.folder.appendingPathComponent("a.png")), Data("one".utf8), "the first export is as it was")
        XCTAssertEqual(try Data(contentsOf: second.folder.appendingPathComponent("a.png")), Data("two".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("a.png").path), "nothing is written loose in the picked folder")
        XCTAssertThrowsError(try MapsExport.writeInNewFolder([], in: parent.appendingPathComponent("missing"), named: "x"), "a parent that is not there is an error")
        XCTAssertNil(regionModel().exportedFolder, "nothing to reveal before an export")
    }

    // MARK: the figure as a file

    /// A vector figure: a one-page PDF whose page is the figure's size in points, whose labels are text, whose panels and outlines land in
    /// their cells. Mutations: the PDF takes the pixel size at 2x for its page, draws the labels as pixels, or leaves the outline out - red.
    func testTheFigureAsAVectorPDF() throws {
        let aperture = Aperture(centerX: 32, centerY: 30, inner: 0, outer: 20)
        let panels = [FigurePanel(label: "Blue panel", image: solid(32, 24, 20, 20, 200)),
                      FigurePanel(label: "Pattern here", image: pattern64(), overlays: [.detector(aperture, .circle, .dark)])]
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        let data = try XCTUnwrap(FigureRendering.renderPDF(panels))
        XCTAssertEqual(Array(data.prefix(5)), Array("%PDF-".utf8))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        let page = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .mediaBox).size)
        XCTAssertEqual(page.width, plan.size.width, accuracy: 0.01); XCTAssertEqual(page.height, plan.size.height, accuracy: 0.01)
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("Blue panel") && text.contains("Pattern here"), "the labels are text, not pixels: \(text)")
        let r = try raster(pdf: data, scale: 1)
        let blue = plan.cells[0].imageRect, pat = plan.cells[1].imageRect
        let a = r.rgb(Int(blue.midX), Int(blue.midY))
        XCTAssertTrue(a.b > 150 && a.r < 60, "the first panel is blue in its cell (\(a))")
        let ring = blob(r, score: yellow)
        let k = Double(plan.cells[1].magnification)
        XCTAssertGreaterThan(ring.count, 100, "the detector outline is in the PDF")
        XCTAssertEqual(ring.cx, Double(pat.minX) + 32.5 * k, accuracy: 0.8)
        XCTAssertEqual(ring.cy, Double(pat.minY) + 30.5 * k, accuracy: 0.8)
        XCTAssertEqual(ring.meanRadius, 20 * k, accuracy: 1.0)
    }

    /// An empty figure is refused. Mutation: `renderPDF` returns an empty document - red.
    func testNoPanelsNoPDF() {
        XCTAssertNil(FigureRendering.renderPDF([]))
    }

    /// A TIFF carries the record as its description, its LZW compression and, at 2x / 3x, the density that places it at the 1x size;
    /// a PNG keeps its text chunk; a PDF has no properties. Mutation: the TIFF properties are dropped, or the density is left out - red.
    func testTheTIFFCarriesItsRecordAndDensity() throws {
        let record: [String: Any] = ["title": "Figure", "panels": ["A", "B"]]
        XCTAssertNil(AppState.figureProperties(format: .pdf, title: "Figure", record: record, pixelScale: 1))
        XCTAssertNotNil(AppState.figureProperties(format: .png, title: "Figure", record: record, pixelScale: 1)?[kCGImagePropertyPNGDictionary])
        for s in [1, 2] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fig-\(UUID().uuidString).tiff")
            defer { try? FileManager.default.removeItem(at: url) }
            let props = AppState.figureProperties(format: .tiff, title: "Figure", record: record, pixelScale: s)
            XCTAssertTrue(AppState.writeImage(solid(40, 30, 1, 2, 3), to: url, type: .tiff, properties: props))
            let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(src) as String?, "public.tiff")
            let read = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
            XCTAssertEqual(read[kCGImagePropertyPixelWidth] as? Int, 40)
            let tiff = try XCTUnwrap(read[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
            XCTAssertEqual(tiff[kCGImagePropertyTIFFCompression] as? Int, 5, "LZW")
            let json = try XCTUnwrap(tiff[kCGImagePropertyTIFFImageDescription] as? String)
            XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["panels"] as? [String], ["A", "B"])
            if s == 2 { XCTAssertEqual(read[kCGImagePropertyDPIWidth] as? Double ?? 0, 144, accuracy: 0.5) }
        }
    }

    /// What the save panel says: the subject and the size in the units of the file. Mutation: the scale or the unit is left out - red.
    func testTheSavePanelStatesScaleAndSize() {
        XCTAssertEqual(AppState.exportPanelMessage(subject: "Figure: A, B", width: 3264, height: 1044, scale: 2), "Figure: A, B \u{00B7} 2\u{00D7} \u{00B7} 3264 \u{00D7} 1044 pixels")
        XCTAssertEqual(AppState.exportPanelMessage(subject: "Figure: A", width: 1632, height: 522, scale: nil), "Figure: A \u{00B7} vector \u{00B7} 1632 \u{00D7} 522 points")
        let panel = { (label: String) in FigurePanel(label: label, image: self.solid(4, 4, 1, 2, 3)) }
        XCTAssertEqual(AppState.figureSubject([panel("A"), panel("B")]), "Figure: A, B")
        XCTAssertEqual(AppState.figureSubject((0..<5).map { panel("Label number \($0) of the longest kind") }), "Figure of 5 images", "a long list is counted, not printed")
    }

    /// The figure of a window as a PDF, and its record. Mutation: the PDF record keeps an export scale, or the page is the 2x size - red.
    func testTheWindowsFigureAsPDF() throws {
        let state = windowWithPatternAndResult()
        let ids: Set<String> = [FigureChoice.resultID, FigureChoice.patternID]
        let plan = FigureLayout.plan(state.figurePanels(chosen: ids).map { ($0.label, $0.image.width, $0.image.height) })
        let made = try state.figurePDF(chosen: ids)
        XCTAssertEqual(made.width, Int(plan.size.width)); XCTAssertEqual(made.height, Int(plan.size.height))
        XCTAssertEqual(Array(made.data.prefix(5)), Array("%PDF-".utf8))
        XCTAssertThrowsError(try state.figurePDF(chosen: []))
        let record = state.figureProvenanceRecord(made.panels, scale: 3, format: .pdf)
        XCTAssertNil(record["export_scale"], "a vector file has no pixels to scale")
        XCTAssertEqual(record["format"] as? String, "pdf")
    }

    /// The file the export panel writes, in each format the preferences name: the bytes of that type, its content type and name, and
    /// the sentence the panel shows with the scale and pixel size (a PDF: points, no scale). Mutations: the format preference is
    /// ignored, the scale is not passed to the PNG, or the message omits the size - red.
    func testTheFigureFileIsWhatThePreferencesName() async throws {
        let state = windowWithPatternAndResult()
        let ids: Set<String> = [FigureChoice.resultID, FigureChoice.patternID]
        let panels = state.figurePanels(chosen: ids)
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })

        state.preferences.figureFormat = .png; state.preferences.exportScale = .two
        let png = try state.figureFile(chosen: ids)
        XCTAssertEqual(png.contentType, .png); XCTAssertEqual(png.suggestedName, "mac4DSTEM_figure")
        XCTAssertEqual(Array(png.data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png.data as CFData, nil)!, 0, nil))
        XCTAssertEqual(image.width, Int(plan.size.width) * 2)
        XCTAssertEqual(png.message, "Figure: Virtual image, Diffraction pattern \u{00B7} 2\u{00D7} \u{00B7} \(image.width) \u{00D7} \(image.height) pixels")
        let snapshot = try await png.snapshot(contentType: .png)
        XCTAssertEqual(snapshot, png.data)

        state.preferences.figureFormat = .tiff; state.preferences.exportScale = .three
        let tiff = try state.figureFile(chosen: ids)
        XCTAssertEqual(tiff.contentType, .tiff)
        XCTAssertTrue(Array(tiff.data.prefix(4)) == [0x49, 0x49, 0x2A, 0x00] || Array(tiff.data.prefix(4)) == [0x4D, 0x4D, 0x00, 0x2A], "a TIFF header")
        let timage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(tiff.data as CFData, nil)!, 0, nil))
        XCTAssertEqual(timage.width, Int(plan.size.width) * 3)

        state.preferences.figureFormat = .pdf
        let pdf = try state.figureFile(chosen: ids)
        XCTAssertEqual(pdf.contentType, .pdf)
        XCTAssertEqual(Array(pdf.data.prefix(5)), Array("%PDF-".utf8))
        XCTAssertEqual(pdf.message, "Figure: Virtual image, Diffraction pattern \u{00B7} vector \u{00B7} \(Int(plan.size.width)) \u{00D7} \(Int(plan.size.height)) points",
                       "a PDF states its size in points, whatever the image size")

        XCTAssertThrowsError(try state.figureFile(chosen: []))
        XCTAssertEqual(Set(FigureFile.writableContentTypes), [.png, .pdf, .tiff])
    }

    /// After the export panel: success says so and records the export, failure shows the error. Mutation: the failure is swallowed - red.
    func testTheStatusFollowsTheExportPanel() {
        let state = AppState()
        let file = FigureFile(data: Data(), format: .png, suggestedName: "x", message: "m")
        state.figureExported(.success(URL(fileURLWithPath: "/tmp/fig.png")), file: file)
        XCTAssertEqual(state.statusText, "Exported fig.png")
        XCTAssertNil(state.errorMessage)
        state.figureExported(.failure(SimpleError("disk full")), file: file)
        XCTAssertEqual(state.errorMessage, "disk full")
    }

    // MARK: the scale bar means what it says

    /// The longest run of pure white pixels in any row: the scale bar's fill (a label's glyphs are far shorter).
    private func longestWhiteRun(_ r: Raster) -> Int {
        var best = 0
        for y in 0..<r.h {
            var run = 0
            for x in 0..<r.w {
                let c = r.rgb(x, y)
                run = (c.r == 255 && c.g == 255 && c.b == 255) ? run + 1 : 0
                best = max(best, run)
            }
        }
        return best
    }

    private func ladderPanel() -> FigurePanel {
        FigurePanel(label: "R", image: solid(64, 48, 100, 100, 100), bar: .ladder(unitsPerDataPixel: 0.5, unit: "nm"))
    }

    /// The result and pattern bar at 1x, 2x and 3x: it SAYS the same thing ("5 nm" for 10 data pixels of 0.5 nm) and is that long in pixels
    /// (10 data pixels x 8 x scale), drawn directly, burnt into an export and in a rendered figure; words and pixels are held together
    /// because a bar of the right length can carry the wrong number (at 2x the broken code drew 160 px under "10 nm").
    /// Mutation: the device scale is dropped from the bar's `unitsPerOutPixel` in `FigureRendering.draw` - red (label at 2x, length at 3x).
    func testTheLadderBarSaysAndMeansTheSameAtEveryScale() throws {
        for s in 1...3 {
            let w = 64 * 8 * s, h = 48 * 8 * s
            let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let plan = try XCTUnwrap(FigureRendering.draw(ladderPanel(), in: ctx, rect: CGRect(x: 0, y: 0, width: w, height: h), magnification: 8, deviceScale: s))
            XCTAssertEqual(plan.label, "5 nm", "the words do not change with the export scale (\(s)x)")
            XCTAssertEqual(plan.lengthPixels, 80 * Double(s), accuracy: 1e-9, "5 nm is 10 data pixels, 8 x \(s) pixels each")
            XCTAssertEqual(Double(longestWhiteRun(raster(try XCTUnwrap(ctx.makeImage())))), plan.lengthPixels, accuracy: 1, "the pixels are as long as the plan says (\(s)x)")

            let burnt = AppState.burnScaleBar(on: solid(64, 48, 100, 100, 100), unitsPerDataPixel: 0.5, unitLabel: "nm", pixelScale: s)
            XCTAssertEqual(Double(longestWhiteRun(raster(burnt))), 80 * Double(s), accuracy: 1, "burnScaleBar at \(s)x")
            let figure = try XCTUnwrap(FigureRendering.render([ladderPanel()], scale: s))
            XCTAssertEqual(Double(longestWhiteRun(raster(figure))), 80 * Double(s), accuracy: 1, "a figure panel at \(s)x")
        }
        let pdf = try raster(pdf: try XCTUnwrap(FigureRendering.renderPDF([ladderPanel()])), scale: 1)
        XCTAssertEqual(Double(longestWhiteRun(pdf)), 80, accuracy: 1, "the PDF page")
        // the pure plan, the words and the length from the sampling alone
        let plan = FigureRendering.ladderBarPlan(width: 1024, unitsPerOutPixel: 0.5 / 16, unit: "nm")
        XCTAssertEqual(plan, FigureRendering.LadderBarPlan(label: "5 nm", lengthPixels: 160))
        XCTAssertEqual(FigureRendering.ladderBarPlan(width: 512, unitsPerOutPixel: 2, unit: "nm").label, "200 nm")
    }

    // MARK: the EDX panels of a window

    private func windowWithMaps() -> AppState {
        let state = AppState()
        state.preferences.appearance = .dark
        state.openSpectrumImage(DemoSpectrumImageSource.make())
        let m = state.spectroscopyRoom.model
        m.tiles = [tile(13, 64, 64), tile(14, 64, 64)]
        m.mixed = [13]; m.gridWidth = 64; m.gridHeight = 64
        m.backdrop = (0..<4096).map { Float($0 % 31) / 31 }
        m.scanPixel = (size: 0.5, unit: "nm")
        m.regionOutline = .rectangle(PixelRect(x0: 10, y0: 12, x1: 40, y1: 50))
        m.export.regions = true
        return state
    }

    /// The EDX branch of the figure: the maps in the figure's order (HAADF, ColorMix, then each element), each with the room's region
    /// outline when `Regions` is on and none when off, each with the map bar from the file's pixel size and none without one.
    /// Mutations: `figurePanels` hands the maps no overlays, ignores `scanPixel`, or lists them in the files' order - red.
    func testTheEDXPanelsCarryTheirOutlinesAndBars() throws {
        let state = windowWithMaps()
        let m = state.spectroscopyRoom.model
        let ids: Set<String> = ["map.haadf", "map.colormix", "map.el.13", "map.el.14", FigureChoice.resultID]
        XCTAssertEqual(state.figureChoices.map(\.id), ["map.haadf", "map.colormix", "map.el.13", "map.el.14"])
        let panels = state.figurePanels(chosen: ids)
        XCTAssertEqual(panels.map(\.label), ["HAADF", MapsExport.colorMixLabel(m), PeriodicLayout.symbol(13), PeriodicLayout.symbol(14)], "the figure's order, not the files'")
        for panel in panels {
            XCTAssertEqual(panel.image.width, 64)
            let stroke = try XCTUnwrap(strokes(panel.overlays).first, "\(panel.label): the region is outlined")
            XCTAssertEqual(strokes(panel.overlays).count, 1)
            XCTAssertEqual(stroke.width, RegionStrokeWidth.live); XCTAssertEqual(stroke.dash, [4, 3])
            guard case .map(let size, let unit)? = panel.bar else { return XCTFail("\(panel.label): the map bar from the file's pixel size") }
            XCTAssertEqual(size, 0.5); XCTAssertEqual(unit, "nm")
        }
        // the outline is the live region on the map's own grid
        guard case .region(let shape, _)? = panels[0].overlays.first else { return XCTFail("no region overlay") }
        XCTAssertEqual(shape, .rectangle(PixelRect(x0: 10, y0: 12, x1: 40, y1: 50)))

        m.export.regions = false
        XCTAssertTrue(state.figurePanels(chosen: ids).allSatisfy { $0.overlays.isEmpty }, "Regions off: no outline")
        m.export.regions = true; m.scanPixel = nil
        XCTAssertTrue(state.figurePanels(chosen: ids).allSatisfy { $0.bar == nil }, "no pixel size, no bar")
        m.scanPixel = (size: 0.5, unit: "nm")
        XCTAssertEqual(state.figurePanels(chosen: ["map.el.14", "map.haadf"]).map(\.label), ["HAADF", PeriodicLayout.symbol(14)], "only the ticked maps")
        // and the whole figure draws, at the layout's size
        let made = try state.figureImage(chosen: ids, scale: 1)
        XCTAssertEqual(made.panels.count, 4)
    }

    // MARK: colours

    /// The export resolves SwiftUI's colours in the app's appearance, not in a light one: cyan differs between the two, the Settings
    /// preference decides, and "System" follows the system. Mutations: `cgColor` ignores the scheme, or `scheme(appearance:)` ignores the
    /// preference - red.
    func testTheExportColoursAreTheAppsAppearance() throws {
        let light = Color.cyan.cgColor(scheme: .light), dark = Color.cyan.cgColor(scheme: .dark)
        func rgb(_ c: CGColor) -> [Double] { (c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? []).map { Double($0) } }
        XCTAssertGreaterThan(rgb(dark)[0], rgb(light)[0] + 0.2, "dark cyan has red in it (0.24), light cyan none")
        var env = EnvironmentValues(); env.colorScheme = .dark
        XCTAssertEqual(Float(rgb(dark)[1]), Color.cyan.resolve(in: env).green, accuracy: 0.01, "it is the colour SwiftUI draws in that appearance")
        XCTAssertEqual(Color.cyan.cgColor(opacity: 0.5, scheme: .dark).alpha, 0.5, accuracy: 1e-6)
        XCTAssertEqual(FigureColors.scheme(appearance: .light, systemIsDark: true), .light)
        XCTAssertEqual(FigureColors.scheme(appearance: .dark, systemIsDark: false), .dark)
        XCTAssertEqual(FigureColors.scheme(appearance: .system, systemIsDark: true), .dark)
        XCTAssertEqual(FigureColors.scheme(appearance: .system, systemIsDark: false), .light)
        // the detector overlay carries the scheme the state names, and the drawing uses it
        let state = windowWithPatternAndResult()
        state.preferences.appearance = .light
        guard case .detector(_, _, let scheme)? = state.patternExportOverlays.first else { return XCTFail("no detector overlay") }
        XCTAssertEqual(scheme, .light)
        let aperture = Aperture(centerX: 32, centerY: 30, inner: 8, outer: 20)
        /// The red of the most cyan pixel on the inner ring (a pixel of a dash that is on).
        func innerRed(_ scheme: ColorScheme) throws -> Int {
            let panel = FigurePanel(label: "", image: pattern64(), overlays: [.detector(aperture, .annulus, scheme)])
            let r = raster(try XCTUnwrap(FigureRendering.rendered(panel, magnification: 4, deviceScale: 1)))
            let ring = (0..<120).map { a -> (r: Int, g: Int, b: Int) in
                let t = Double(a) * 2 * .pi / 120
                return r.rgb(Int(130 + 32 * cos(t)), Int(122 + 32 * sin(t)))
            }
            return ring.max { $0.b - $0.r < $1.b - $1.r }?.r ?? 0
        }
        XCTAssertGreaterThan(try innerRed(.dark), try innerRed(.light) + 20, "the dashed cyan ring is the appearance's variant")
        let m = regionModel(); m.pins = []
        XCTAssertNotEqual(strokes(MapsExport.regionOverlays(m, scheme: .dark)).first?.color, strokes(MapsExport.regionOverlays(m, scheme: .light)).first?.color,
                          "the accent differs between the appearances too")
    }

    // MARK: the detector tick and the TIFF profile

    /// "Detector outline" decides the pattern's outline; nil follows the pane. Mutation: the tick is ignored (the last room decides) - red.
    func testTheDetectorTickDecidesTheOutline() {
        let state = windowWithPatternAndResult()
        let pattern: Set<String> = [FigureChoice.patternID]
        func outlines(_ detector: Bool?) -> Int { state.figurePanels(chosen: pattern, detector: detector).first?.overlays.count ?? -1 }
        XCTAssertEqual(outlines(nil), 1, "in the Virtual Detector task the pane draws it")
        XCTAssertEqual(outlines(false), 0, "unticked: none, whatever the task")
        state.navigation.analysisMode = .disks
        XCTAssertEqual(outlines(nil), 0, "in another task the pane draws none")
        XCTAssertEqual(outlines(true), 1, "ticked: drawn, whatever the task left behind")
        XCTAssertEqual(AppState().detectorOverlay.count, 0, "no pattern, nothing to outline")
    }

    /// A TIFF is tagged sRGB, like the PNG. Mutation: `encodeImage` writes the TIFF with the device colour space - red.
    func testTheTIFFIsTaggedSRGB() throws {
        let data = try XCTUnwrap(AppState.encodeImage(solid(8, 8, 1, 2, 3), type: .tiff, properties: nil))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertTrue((props[kCGImagePropertyProfileName] as? String ?? "").contains("sRGB"), "profile: \(String(describing: props[kCGImagePropertyProfileName]))")
    }

    // MARK: the inspector section

    /// What the section ticks: the person's choice over each image's default.
    func testTheTicksOverrideTheDefaults() {
        let choices = [FigureChoice(id: "a", label: "A", isDefault: true), FigureChoice(id: "b", label: "B", isDefault: false)]
        XCTAssertEqual(FigureExportSection.chosen(choices, ticks: [:]), ["a"])
        XCTAssertEqual(FigureExportSection.chosen(choices, ticks: ["a": false, "b": true]), ["b"])
        XCTAssertEqual(FigureExportSection.chosen(choices, ticks: ["z": true]), ["a"], "an image the window no longer has is not chosen")
    }

    /// The section fits the narrowest inspector column with the longest names: a long product name, a spectrum image's maps, and the
    /// size and regions rows. Mutation: the choice row's label is an `InspectorRow` (fixed size) - red.
    func testTheFigureSectionFitsTheNarrowestColumn() {
        let state = windowWithPatternAndResult()
        state.publishProduct(kind: "virtual_annulus", displayName: String(repeating: "Virtual detector annular dark field ", count: 3), valueUnits: "i",
                             payload: .scalar(FloatImage(width: 4, height: 4, pixels: [Float](repeating: 1, count: 16))))
        state.openSpectrumImage(DemoSpectrumImageSource.make())
        let model = state.spectroscopyRoom.model
        model.tiles = [tile(13, 8, 8), tile(14, 8, 8)]; model.mixed = [13]; model.gridWidth = 8; model.gridHeight = 8; model.backdrop = [Float](repeating: 0.5, count: 64)
        let host = NSHostingController(rootView: FigureExportSection().environment(state).environment(state.preferences))
        let width = host.sizeThatFits(in: CGSize(width: 1, height: 10_000)).width
        XCTAssertGreaterThan(width, 10, "the probe measured something")
        XCTAssertLessThanOrEqual(width, LayoutPolicy.inspectorWidth.min - 32, "the section needs \(width) pt")
    }
}
