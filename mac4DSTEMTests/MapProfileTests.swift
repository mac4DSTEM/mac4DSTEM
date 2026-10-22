import XCTest
@testable import DSTEMCore

/// The map profile adapts a map to ImagoCore's `LineProfile`; the kit's own numbers are pinned in ImagoKit. These pin the adaptation: the
/// room's continuous scan pixels (pixel i covers [i, i+1)) against the kit's pixel centres, and the scan's unit.
final class MapProfileTests: XCTestCase {
    /// A map whose value is its column: a horizontal line through the centres of columns 2 to 10 reads 2 ... 10, one sample per pixel.
    /// Mutation: the half-pixel shift dropped (the room's coordinates handed to the kit as they are) - every sample reads 0.5 too high.
    func testARampReadsItsColumnsAtThePixelCentres() throws {
        let w = 16, h = 4
        let ramp = (0..<(w * h)).map { Float($0 % w) }
        let p = try XCTUnwrap(MapProfile.along(values: ramp, width: w, height: h, from: (2.5, 1.5), to: (10.5, 1.5), pixelSize: nil, unit: nil))
        XCTAssertEqual(p.samples, (2...10).map(Double.init))
        XCTAssertEqual(p.positions.last ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(p.unit, "px")
    }

    /// With a pixel size the positions are in the scan's unit: 8 px at 0.5 nm is 4 nm.
    func testAPixelSizeGivesTheUnit() throws {
        let w = 16, h = 4
        let p = try XCTUnwrap(MapProfile.along(values: [Float](repeating: 1, count: w * h), width: w, height: h,
                                               from: (2.5, 1.5), to: (10.5, 1.5), pixelSize: 0.5, unit: "nm"))
        XCTAssertEqual(p.unit, "nm")
        XCTAssertEqual(p.positions.last ?? 0, 4, accuracy: 1e-9)
    }

    /// A map whose size does not match its values has no profile.
    func testAMismatchedMapHasNoProfile() {
        XCTAssertNil(MapProfile.along(values: [1, 2, 3], width: 2, height: 2, from: (0, 0), to: (1, 1), pixelSize: nil, unit: nil))
    }
}

/// The region table hands each region's mask to ImagoCore's labelled statistics; these pin the hand-over, not the kit's numbers.
final class RegionMapTableTests: XCTestCase {
    /// A column ramp under a 4 x 2 box and under the whole map: the means are the kit's (2.5 for columns 2...3 of a 0..7 ramp is 2.5).
    /// Mutation: the mask inverted, or the whole map's `nil` mask read as empty - red.
    func testTheMeanUnderARegionAndUnderTheWholeMap() {
        let w = 8, h = 2
        let ramp = (0..<(w * h)).map { Float($0 % w) }
        var box = [Bool](repeating: false, count: w * h)
        for r in 0..<h { for c in 2...3 { box[r * w + c] = true } }
        let rows = RegionMapTable.rows(maps: [ramp], width: w, height: h, regions: [(name: "Whole map", mask: nil), (name: "Box", mask: box)])
        XCTAssertEqual(rows[0].pixels, 16); XCTAssertEqual(rows[0].cells[0]?.mean ?? -1, 3.5, accuracy: 1e-12)
        XCTAssertEqual(rows[1].pixels, 4); XCTAssertEqual(rows[1].cells[0]?.mean ?? -1, 2.5, accuracy: 1e-12)
        XCTAssertEqual(rows[1].cells[0]?.spread ?? -1, 0.5, accuracy: 1e-12, "the population spread of {2, 3}")
    }

    /// A region with no pixel has a row with no numbers, not a mean of nothing.
    func testAnEmptyRegionHasNoNumbers() {
        let rows = RegionMapTable.rows(maps: [[1, 2, 3, 4]], width: 2, height: 2, regions: [(name: "Nothing", mask: [false, false, false, false])])
        XCTAssertEqual(rows[0].pixels, 0); XCTAssertNil(rows[0].cells[0])
    }
}
