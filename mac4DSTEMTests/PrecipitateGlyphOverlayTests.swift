// The precipitate glyph overlay (design rooms-2026-10-21 §3): one ellipse per object from the table's rows, the same object at the
// same fraction of the picture on every pane of the scan, counted-only and the hover hit test.

import XCTest
import CoreGraphics
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
@testable import mac4DSTEM

final class PrecipitateGlyphOverlayTests: XCTestCase {
    /// 8 x 6 scan, phase 1: A a 3 px bar (interior), B a 1 px speck (interior), C 2 px on the right edge.
    private func report(minimum: Int = 2) -> PrecipitateObjectReport {
        var labels = [Int32](repeating: 0, count: 8 * 6)
        for x in 2...4 { labels[2 * 8 + x] = 1 }
        labels[4 * 8 + 5] = 1
        labels[1 * 8 + 7] = 1; labels[2 * 8 + 7] = 1
        let objects = PrecipitateSegmentation.classObjects(
            labels: labels, width: 8, height: 6, roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [-1]),
            pixelSize: nil, pixelUnit: nil)
        return PrecipitateObjectReport.make(objects: objects, phaseNames: ["Al", "θ′"], matrixPhaseIndex: 0,
                                            pixelSize: 2, pixelUnit: "nm", minimumAreaPx: minimum)
    }

    func testOneGlyphPerObjectFromTheTablesOwnRows() throws {
        let r = report()
        let set = PrecipitateGlyphSet.make(r)
        XCTAssertEqual(set.glyphs.count, r.rows.count)
        let a = try XCTUnwrap(set.glyphs.first { $0.counted })
        let row = try XCTUnwrap(r.rows.first { $0.id == a.id })
        XCTAssertEqual(a.centreX, row.centroidX); XCTAssertEqual(a.centreY, row.centroidY)
        XCTAssertEqual(a.semiMajor, row.lengthPx / 2); XCTAssertEqual(a.semiMinor, row.widthPx / 2)
        XCTAssertTrue(a.readout.hasPrefix("#\(a.id) θ′ "), a.readout)
        XCTAssertTrue(a.readout.hasSuffix("nm"), a.readout)
    }

    func testCountedOnlyDropsEdgeAndSmallObjects() {
        let set = PrecipitateGlyphSet.make(report())
        XCTAssertEqual(set.shown(PrecipitateOverlaySettings(countedOnly: true)).count, 1, "only A is counted")
        XCTAssertEqual(set.shown(PrecipitateOverlaySettings(countedOnly: false)).count, 3)
    }

    /// The geometry through the display transform: the same object lands at the same fraction of a 64 x 48 pane and of a
    /// 320 x 240 one (a virtual image and an EDX map of the same scan), and keeps its aspect and angle.
    func testTheSameObjectIsAtTheSameFractionOnEveryPane() throws {
        let set = PrecipitateGlyphSet.make(report())
        let g = try XCTUnwrap(set.glyphs.first { $0.counted })
        let small = PrecipitateGlyphGeometry.place(g, gridWidth: set.width, gridHeight: set.height, paneSize: CGSize(width: 64, height: 48))
        let big = PrecipitateGlyphGeometry.place(g, gridWidth: set.width, gridHeight: set.height, paneSize: CGSize(width: 320, height: 240))
        XCTAssertEqual(small.centre.x / 64, big.centre.x / 320, accuracy: 1e-12)
        XCTAssertEqual(small.centre.y / 48, big.centre.y / 240, accuracy: 1e-12)
        XCTAssertEqual(small.semiMajor / small.semiMinor, big.semiMajor / big.semiMinor, accuracy: 1e-9)
        XCTAssertEqual(small.angleDegrees, big.angleDegrees)
        // A at row 2, columns 2...4: centre (3, 2) in pixel indices, drawn at the pixel centre of the 8 x 6 grid.
        XCTAssertEqual(small.centre.x, (3 + 0.5) * 8, accuracy: 1e-6)
        XCTAssertEqual(small.centre.y, (2 + 0.5) * 8, accuracy: 1e-6)
    }

    func testHitTestFindsTheObjectUnderAPixel() throws {
        let set = PrecipitateGlyphSet.make(report())
        let on = PrecipitateOverlaySettings(countedOnly: false)
        XCTAssertNotNil(set.hit(x: 3, y: 2, settings: on))
        XCTAssertNil(set.hit(x: 0, y: 0, settings: on))
        XCTAssertNil(set.hit(x: 5, y: 4, settings: PrecipitateOverlaySettings(countedOnly: true)), "the speck B is not counted")
    }

    func testOverlayIsOffByDefault() {
        XCTAssertFalse(PrecipitateOverlaySettings().onPanes)
    }

    func testHoverIsNilWhileTheOverlayIsOff() {
        let state = AppState()
        state.updatePrecipitateHover(x: 3, y: 2)
        XCTAssertNil(state.precipitateHoverID)
        state.updatePrecipitateHover(x: nil, y: nil)
        XCTAssertNil(state.precipitateHoverID)
    }
}
