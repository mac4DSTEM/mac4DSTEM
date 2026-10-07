import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Velox sheet row 1a, lane L1: the tiles and the Maps export are honest about the display kernel. Each test names its mutation.
@MainActor
final class SpectroscopyVeloxL1Tests: XCTestCase {

    private func sym(_ z: Int) -> String { PeriodicLayout.symbol(z) }
    private func tile(_ z: Int, _ values: [Float], scale: Float, counts: [Double] = []) -> MapTile {
        var t = MapTile(z: z, width: 2, height: 2, values: values); t.scale = scale; t.counts = counts; return t
    }
    private func liveModel() -> SpectroscopyRoomModel {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = [tile(13, [0, 0.5, 0.25, 1], scale: 200), tile(14, [1, 0, 0.5, 0.1], scale: 10)]
        m.mixed = [13]; m.gridWidth = 2; m.gridHeight = 2; m.backdrop = [0.1, 0.2, 0.3, 0.4]
        m.export.mapsStem = "scan"
        return m
    }

    /// Mutation: `kernelText` returns the label for `.none` too, or drops the label - red.
    func testTheTileHeaderNamesTheKernelOnlyWhenOneIsSet() {
        XCTAssertNil(MapTileView.kernelText(mode: .netCounts, smoothing: .none))
        XCTAssertEqual(MapTileView.kernelText(mode: .netCounts, smoothing: .box3), "net \u{00B7} 3 \u{00D7} 3")
        XCTAssertEqual(MapTileView.kernelText(mode: .integrated, smoothing: .gaussian1), "int \u{00B7} \u{03C3} 1 px")
        XCTAssertNil(MapTileView.kernelHelp(smoothing: .none))
        XCTAssertEqual(MapTileView.kernelHelp(smoothing: .box3),
                       "Displayed through a 3 \u{00D7} 3 count-conserving kernel; the raw map is what the export writes.")
    }

    /// Mutation: `text` appends the label when nothing is mixed, or never - red.
    func testTheColorMixHeaderGainsTheKernelOnce() {
        XCTAssertEqual(ColorMixHeader.text(mixed: ["O", "Mg", "Al", "Si"], smoothing: .box3), "O \u{00B7} Mg \u{00B7} Al \u{00B7} Si \u{00B7} 3 \u{00D7} 3")
        XCTAssertEqual(ColorMixHeader.text(mixed: ["O", "Al"], smoothing: .none), "O \u{00B7} Al")
        XCTAssertEqual(ColorMixHeader.text(mixed: [], smoothing: .box3), "")
        XCTAssertFalse(ColorMixHeader.help(mixed: ["O"], notMixed: []).contains("3 \u{00D7} 3"), "the help names the mix, not the kernel")
    }

    /// Mutation: `histogramTitle` ignores the kernel, or tags the HAADF too - red.
    func testTheHistogramSaysItsValuesAreSmoothed() {
        let m = liveModel()
        XCTAssertEqual(m.histogramTitle(.element(13)), "Histogram")
        m.smoothing = .box3
        XCTAssertEqual(m.histogramTitle(.element(13)), "Histogram \u{00B7} smoothed, 3 \u{00D7} 3")
        XCTAssertEqual(m.histogramTitle(.haadf), "Histogram", "the HAADF is not smoothed")
    }

    /// Mutation: `pngName` drops the mode or the tag, or tags when nothing is set - red.
    func testThePNGNameCarriesTheKernelAndNothingWithout() {
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al"), "a-Al.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al", mode: .netCounts, smoothing: .none), "a-Al.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al", mode: .netCounts, smoothing: .box3), "a-Al-net-3x3.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "ColorMix", mode: .integrated, smoothing: .gaussian2), "a-ColorMix-int-s2px.png")
    }

    /// Mutation: `files` ignores `model.smoothing`, tags the HAADF, or tags the CSV - red.
    func testFilesTagTheElementsAndTheColorMixButNotTheHAADFOrTheCSV() throws {
        let m = liveModel(); m.smoothing = .box3
        XCTAssertEqual(try MapsExport.files(m).map(\.name),
                       ["scan-HAADF.png", "scan-\(sym(13))-net-3x3.png", "scan-\(sym(14))-net-3x3.png", "scan-ColorMix-net-3x3.png", "scan-maps.csv"])
    }

    /// Mutation: `csv` writes `values x scale` (clamped, 0 here) instead of `counts`, or rounds the negative to 0 - red.
    func testTheCSVWritesTheRawSignedCountsAndSaysSo() throws {
        let al = tile(13, [0, 0.5, 0.25, 1], scale: 200, counts: [-3.5, 100, 50, 200])
        let si = tile(14, [1, 0, 0.5, 0.1], scale: 10, counts: [10, -1, 5, 1])
        let text = try MapsExport.csv(stem: "demo", mode: .netCounts, tiles: [al, si], symbol: sym)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("# raw net counts per pixel as the file gives them (negative = background exceeded the window), unsmoothed"))
        XCTAssertFalse(text.contains("display values"))
        XCTAssertEqual(lines.filter { !$0.hasPrefix("#") }, ["x,y,\(sym(13)),\(sym(14))", "0,0,-3.5,10", "1,0,100,-1", "0,1,50,5", "1,1,200,1"])
    }

    /// The raw counts are what the file holds whatever kernel is on screen: smoothing changes `values`, never the CSV.
    /// Mutation: `files` builds the CSV from `values` when `model.smoothing != .none` - red.
    func testASmoothedModelStillWritesRawCounts() throws {
        let m = liveModel(); m.smoothing = .box3
        m.tiles[0].counts = [-3.5, 100, 50, 200]; m.tiles[1].counts = [10, -1, 5, 1]
        let csv = String(decoding: try XCTUnwrap(MapsExport.files(m).last).data, as: UTF8.self)
        XCTAssertTrue(csv.contains("\n0,0,-3.5,10\n"))
        XCTAssertTrue(csv.contains("unsmoothed"))
    }

    /// A tile without counts (the fixture) falls back to value x scale and the header says "(display values)".
    /// Mutation: the fallback line says "raw" and "unsmoothed", or the fallback is dropped (crash/empty) - red.
    func testWithoutCountsTheCSVFallsBackAndSaysDisplayValues() throws {
        let al = tile(13, [0, 0.5, 0.25, 1], scale: 200)
        let mixed = tile(14, [1, 0, 0.5, 0.1], scale: 10, counts: [9, 9, 9, 9])
        let text = try MapsExport.csv(stem: "d", mode: .netCounts, tiles: [al, mixed], symbol: sym)
        XCTAssertTrue(text.contains("(display values: value x scale)"))
        XCTAssertFalse(text.contains("unsmoothed"))
        XCTAssertTrue(text.contains("\n1,0,100,0\n"), "one tile without counts puts the whole file on display values, not a mixed one")
    }

    /// At% / wt% maps hold percentages, not counts: even with counts present the CSV stays on display values.
    /// Mutation: drop the mode check in `csv`'s `raw` - red.
    func testPercentModesNeverClaimRawCounts() throws {
        let t = tile(13, [0, 0.5, 0.25, 1], scale: 100, counts: [1, 2, 3, 4])
        XCTAssertTrue(try MapsExport.csv(stem: "d", mode: .atomic, tiles: [t], symbol: sym).contains("display values"))
    }
}
