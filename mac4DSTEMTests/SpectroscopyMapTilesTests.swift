import XCTest
import ShellSpectroscopy
@testable import mac4DSTEM

/// The maps block on MacEMUI's `MapTileGrid` (2026-10-22): the hover chip's text per map mode and the tile-size state.
@MainActor
final class SpectroscopyMapTilesTests: XCTestCase {
    private func tile(counts: [Double] = []) -> MapTile {
        MapTile(z: 12, width: 3, height: 2, values: [0, 0.25, 0.5, 0.75, 1, 0.1], counts: counts, scale: 400)
    }

    /// A counts tile reads its raw counts with the mode's unit; a pixel off the grid is clamped to the nearest one.
    /// Mutation: the row or the column swapped in the index - the planted 5th pixel reads another number.
    func testTheChipReadsTheCountsUnderThePointer() {
        let t = tile(counts: [10, 20, 30, 41_238, 50, 60])
        XCTAssertEqual(MapHoverReadout.text(symbol: "Mg", tile: t, mode: .netCounts, column: 0, row: 1), "Mg 41\u{202F}238 net counts")
        XCTAssertEqual(MapHoverReadout.text(symbol: "Mg", tile: t, mode: .integrated, column: 99, row: 99), "Mg 60 integrated counts")
        XCTAssertEqual(MapHoverReadout.text(symbol: "Mg", tile: t, mode: .integrated, column: -4, row: -4), "Mg 10 integrated counts")
    }

    /// A composition tile reads one decimal and the mode's own name; with no counts the value is the 0...1 pixel times the scale.
    func testTheChipReadsACompositionAndTheScaledValue() {
        XCTAssertEqual(MapHoverReadout.text(symbol: "Si", tile: tile(counts: [0, 0, 0, 0, 36.24, 0]), mode: .atomic, column: 1, row: 1), "Si 36.2 at%")
        XCTAssertEqual(MapHoverReadout.text(symbol: "Si", tile: tile(), mode: .integrated, column: 1, row: 0), "Si 100 integrated counts")
        XCTAssertNil(MapHoverReadout.text(symbol: "Si", tile: MapTile(z: 14, width: 0, height: 0, values: []), mode: .integrated, column: 0, row: 0))
    }
}
