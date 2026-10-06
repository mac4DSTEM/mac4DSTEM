import XCTest
@testable import mac4DSTEM

/// Spec 2 lane C: the spectrum strip's pure decisions (linear default, full range, y stretch, zoom edges, suspects, highlight).
/// The drawing is verified on screen by the supervisor's drive.
final class SpectroscopySpec2CTests: XCTestCase {
    private func marker(_ label: String, _ e: Double, _ kind: LineMarker.Kind, z: Int? = nil) -> LineMarker {
        LineMarker(label: label, energy: e, elementZ: z, kind: kind)
    }

    /// Mutation: `var log = true` - red.
    func testLogScaleIsOffByDefault() {
        XCTAssertFalse(SpectrumLayers().log)
        XCTAssertTrue(SpectrumLayers().pins, "the other layers keep their defaults")
    }

    /// Double-click is the no-line range: 0 to the 99.5 % energy, floor 2, cap 20, inside the axis - not the lines' span.
    /// Mutation: `fullRange` passes the markers through (the lines' span) - red; cap or floor changed - red.
    func testFullRangeIgnoresTheLinesAndStopsAtTheCountsEnergy() {
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: 8.5), 0...8.5)
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: 55), 0...20, "cap 20 keV")
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: 0.7), 0...2, "floor 2 keV")
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: nil), 0...20)
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...5, minimumSpan: 0.04, countsEnergy: 55), 0...5, "inside the axis")
        // against the lines' span (Home) it is a different window
        let lines = [marker("Cu Kα", 8.05, .line, z: 29)]
        let home = SpectrumAutoZoom.range(markers: lines, domain: 0...80, minimumSpan: 0.04, countsEnergy: 12)
        XCTAssertNotEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: 12), home)
        XCTAssertEqual(SpectrumStripLogic.fullRange(domain: 0...80, minimumSpan: 0.04, countsEnergy: 12), 0...12)
    }

    /// The y stretch divides the drawn top, starts at 1, is cumulative from the drag start and is clamped to 1...50.
    /// Mutations: multiply instead of divide - red; clamp removed - red; sign of the drag flipped - red; not from `start` - red.
    func testYScaleDividesTheTopAndClamps() {
        var vp = SpectrumViewport(domain: 0...20)
        XCTAssertEqual(vp.yScale, 1)
        XCTAssertEqual(vp.scaledTop(1000), 1000)
        vp.yScale = 4
        XCTAssertEqual(vp.scaledTop(1000), 250, accuracy: 1e-12)
        XCTAssertEqual(vp.scaledTop(1000, floor: 600), 600, "a floor (log: 2x the bottom decade) holds the top up")
        let d = SpectrumViewport.yScalePointsPerDoubling
        XCTAssertEqual(SpectrumViewport.yScale(from: 1, dragDY: -d), 2, accuracy: 1e-12, "up stretches")
        XCTAssertEqual(SpectrumViewport.yScale(from: 3, dragDY: -d), 6, accuracy: 1e-12, "cumulative from the start value")
        XCTAssertEqual(SpectrumViewport.yScale(from: 4, dragDY: d), 2, accuracy: 1e-12, "down shrinks")
        XCTAssertEqual(SpectrumViewport.yScale(from: 1, dragDY: 5 * d), 1, "never below auto")
        XCTAssertEqual(SpectrumViewport.yScale(from: 1, dragDY: -100 * d), 50, "never above 50")
        XCTAssertEqual(SpectrumViewport.yScale(from: 7, dragDY: 0), 7, accuracy: 1e-12)
        XCTAssertEqual(SpectrumViewport.yScale(from: 7, dragDY: .nan), 7, "a non-finite drag changes nothing")
    }

    /// The y stretch is not part of the energy window: zoom and pan leave it alone.
    /// Mutation: `zoom` or `clamp` resets yScale - red.
    func testZoomAndPanLeaveTheYScaleAlone() {
        var vp = SpectrumViewport(domain: 0...20); vp.yScale = 5
        vp.zoom(factor: 3, anchor: 0.4); vp.pan(byFraction: 0.2)
        XCTAssertEqual(vp.yScale, 5)
    }

    /// Zooming out from a window at the edge stays inside the domain and ends on the whole domain.
    /// Mutation: the zoom-out span not capped at the domain, or `clamp()` dropped - red.
    func testZoomOutFromTheEdgeStopsAtTheDomain() {
        for (lo, hi) in [(0.0, 2.0), (18.0, 20.0), (9.0, 11.0)] {
            var vp = SpectrumViewport(domain: 0...20, minimumSpan: 0.02)
            vp.lo = lo; vp.hi = hi
            for a in [0.0, 0.3, 1.0] {
                var z = vp
                z.zoom(factor: 0.1, anchor: a)
                XCTAssertGreaterThanOrEqual(z.lo, 0); XCTAssertLessThanOrEqual(z.hi, 20)
                XCTAssertEqual(z.lo, 0, accuracy: 1e-12); XCTAssertEqual(z.hi, 20, accuracy: 1e-12, "past the domain: the domain, no empty space")
            }
        }
        // partial zoom out near the edge: still inside, wider
        var vp = SpectrumViewport(domain: 0...20); vp.lo = 17; vp.hi = 19.5
        vp.zoom(factor: 0.5, anchor: 0.9)
        XCTAssertLessThanOrEqual(vp.hi, 20 + 1e-12); XCTAssertGreaterThanOrEqual(vp.lo, 0)
        XCTAssertEqual(vp.span, 5, accuracy: 1e-9)
    }

    /// Two zooms about the same anchor keep the energy under the anchor.
    /// Mutation: zoom about `lo` (anchor ignored) - red.
    func testConsecutiveZoomsKeepTheAnchorEnergy() {
        var vp = SpectrumViewport(domain: 0...20, minimumSpan: 0.02)
        vp.lo = 4; vp.hi = 12
        let anchor = 0.7
        let e = vp.energy(atFraction: anchor)
        vp.zoom(factor: 2, anchor: anchor)
        XCTAssertEqual(vp.energy(atFraction: anchor), e, accuracy: 1e-9)
        vp.zoom(factor: 1.5, anchor: anchor)
        XCTAssertEqual(vp.energy(atFraction: anchor), e, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(vp.lo, 0); XCTAssertLessThanOrEqual(vp.hi, 20)
    }

    /// The pinch anchor is the start x in the frame's space as a fraction of the frame width, clamped to 0...1.
    /// Mutation: the clamp dropped, or the left gutter not subtracted - red.
    func testPinchAnchorIsTakenInFrameCoordinatesAndClamped() {
        XCTAssertEqual(SpectrumStripLogic.anchor(startX: 46, plotLeft: 46, plotWidth: 400), 0, accuracy: 1e-12)
        XCTAssertEqual(SpectrumStripLogic.anchor(startX: 246, plotLeft: 46, plotWidth: 400), 0.5, accuracy: 1e-12)
        XCTAssertEqual(SpectrumStripLogic.anchor(startX: 10, plotLeft: 46, plotWidth: 400), 0, "in the gutter: the left edge")
        XCTAssertEqual(SpectrumStripLogic.anchor(startX: 900, plotLeft: 46, plotWidth: 400), 1, "right of the frame: the right edge")
        XCTAssertEqual(SpectrumStripLogic.anchor(startX: 100, plotLeft: 46, plotWidth: 0), 1, "a collapsed frame does not divide by zero")
    }

    /// A suspect is never drawn (no line, no name); lines, proposals and the edge are, inside the window only.
    /// Mutation: the suspect filter dropped, or the window filter dropped - red.
    func testSuspectsAreNotInTheDrawnMarkers() {
        let ms = [marker("Cu Kα", 8.05, .line, z: 29), marker("Hf+Hf sum?", 9.0, .suspect), marker("Ga Lα?", 1.1, .suspect, z: 31),
                  marker("Mg Kα", 1.25, .proposed, z: 12), marker("Al K edge", 1.56, .edge), marker("Ti Kα", 4.5, .line, z: 22)]
        XCTAssertEqual(SpectrumStripLogic.drawnMarkers(ms, lo: 0, hi: 10).map(\.label), ["Cu Kα", "Mg Kα", "Al K edge", "Ti Kα"])
        XCTAssertEqual(SpectrumStripLogic.drawnMarkers(ms, lo: 0, hi: 5).map(\.label), ["Mg Kα", "Al K edge", "Ti Kα"])
    }

    /// The highlighted element's markers are 1.8 pt and bold; the others 0.8 pt; nothing is highlighted when nothing is set.
    /// Mutation: width swapped, or nil matching a nil elementZ (the edge) - red.
    func testHighlightedElementsDrawThicker() {
        let cu = marker("Cu Kα", 8.05, .line, z: 29), ti = marker("Ti Kα", 4.5, .line, z: 22), edge = marker("Al K edge", 1.56, .edge)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(cu, highlightedZ: 29), 1.8)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(ti, highlightedZ: 29), 0.8)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(cu, highlightedZ: nil), 0.8)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(edge, highlightedZ: nil), 0.8, "no highlight: a marker with no element is not highlighted")
        XCTAssertTrue(SpectrumStripLogic.isHighlighted(cu, highlightedZ: 29))
        XCTAssertFalse(SpectrumStripLogic.isHighlighted(ti, highlightedZ: 29))
        XCTAssertFalse(SpectrumStripLogic.isHighlighted(edge, highlightedZ: nil))
    }

    /// The region tools now include the ellipse (lane B draws it); each tool has its own symbol.
    /// Mutation: the case or its symbol removed - red.
    func testDrawToolsIncludeTheEllipse() {
        XCTAssertEqual(DrawTool.allCases, [.rectangle, .ellipse, .polygon])
        XCTAssertEqual(DrawTool.ellipse.rawValue, "Ellipse")
        XCTAssertEqual(DrawTool.ellipse.symbol, "oval")
        XCTAssertEqual(Set(DrawTool.allCases.map(\.symbol)).count, 3)
    }
}
