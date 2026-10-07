import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Spec 2 lane J: the Maps export (PNG per map as shown, one CSV of net counts, one folder). Each test names its mutation.
@MainActor
final class SpectroscopySpec2JTests: XCTestCase {

    private func tile(_ z: Int, _ values: [Float], scale: Float, w: Int = 2, h: Int = 2) -> MapTile {
        var t = MapTile(z: z, width: w, height: h, values: values); t.scale = scale; return t
    }
    private func sym(_ z: Int) -> String { PeriodicLayout.symbol(z) }

    /// Mutation: drop the `* scale` in `csv` (writes the 0...1 picture values) - red.
    func testTheCSVHoldsNetCountsInPixelOrderAndTileOrder() throws {
        let al = tile(13, [0, 0.5, 0.25, 1], scale: 200), si = tile(14, [1, 0, 0.5, 0.1], scale: 10)
        let text = try MapsExport.csv(stem: "demo", mode: .netCounts, tiles: [al, si], symbol: sym)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.hasPrefix("#") }.count, 3, "file, mode and units, what the numbers are")
        XCTAssertTrue(lines[0].contains("demo"))
        XCTAssertTrue(lines[1].contains("net") && lines[1].contains("net counts"), "the header names the mode and the units")
        let body = lines.filter { !$0.hasPrefix("#") }
        XCTAssertEqual(body, ["x,y,\(sym(13)),\(sym(14))", "0,0,0,10", "1,0,100,0", "0,1,50,5", "1,1,200,1"])
    }

    /// Mutation: swap the loops (x outer, y inner) in `csv` - red.
    func testAnOddGridKeepsRowMajorXY() throws {
        let t = tile(26, [1, 2, 3, 4, 5, 6], scale: 1, w: 3, h: 2)
        let body = try MapsExport.csv(stem: "s", mode: .integrated, tiles: [t], symbol: sym).split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
        XCTAssertEqual(Array(body.dropFirst()), ["0,0,1", "1,0,2", "2,0,3", "0,1,4", "1,1,5", "2,1,6"])
    }

    /// Mutation: drop the `notMeasuredWhy` header line in `csv` - red.
    func testANotMeasuredMapKeepsItsNoteInTheHeader() throws {
        var t = tile(8, [0, 1, 0, 1], scale: 1); t.notMeasuredWhy = "window below the noise"
        let text = try MapsExport.csv(stem: "s", mode: .netCounts, tiles: [t], symbol: sym)
        XCTAssertTrue(text.contains("# \(sym(8)): not a measurement: window below the noise"))
    }

    /// Mutation: remove the grid check in `csv` - red (it would index out of range or write a ragged file).
    func testMapsOnDifferentGridsOrNoMapsRefuse() {
        XCTAssertThrowsError(try MapsExport.csv(stem: "s", mode: .netCounts, tiles: [], symbol: sym))
        XCTAssertThrowsError(try MapsExport.csv(stem: "s", mode: .netCounts,
                                                tiles: [tile(13, [0, 0, 0, 0], scale: 1), tile(14, [0, 0, 0, 0, 0, 0], scale: 1, w: 3, h: 2)], symbol: sym))
    }

    /// Mutation: `stem` keeps the extension or the spaces - red.
    func testNamesAreStemDashSymbolAndMapsCSV() {
        XCTAssertEqual(MapsExport.stem(imageName: "Al Mg-Si.dm4"), "Al_Mg-Si")
        XCTAssertEqual(MapsExport.stem(imageName: ""), "spectroscopy")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al"), "a-Al.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "ColorMix"), "a-ColorMix.png")
        XCTAssertEqual(MapsExport.csvName(stem: "a"), "a-maps.csv")
    }

    /// Mutation: `pngData` encodes as JPEG/TIFF (signature changes) or returns the raw bytes - red; also checks the size is the grid's.
    func testAPNGStartsWithTheSignatureAndKeepsTheGrid() throws {
        let img = try XCTUnwrap(MapBitmap.image(width: 2, height: 2) { i in (UInt8(i * 60), 0, 0) })
        let data = try XCTUnwrap(MapBitmap.pngData(img))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let back = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(back.width, 2); XCTAssertEqual(back.height, 2)
    }

    private func liveModel() -> SpectroscopyRoomModel {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = [tile(13, [0, 0.5, 0.25, 1], scale: 200), tile(14, [1, 0, 0.5, 0.1], scale: 10)]
        m.mixed = [13]; m.gridWidth = 2; m.gridHeight = 2; m.backdrop = [0.1, 0.2, 0.3, 0.4]
        m.export.mapsStem = "scan"
        return m
    }

    /// Mutation: `files` skips the HAADF, the ColorMix or the CSV - red.
    func testTheModelMakesOneFilePerMapPlusHAADFColorMixAndCSV() throws {
        let files = try MapsExport.files(liveModel())
        XCTAssertEqual(files.map(\.name), ["scan-HAADF.png", "scan-\(sym(13)).png", "scan-\(sym(14)).png", "scan-ColorMix.png", "scan-maps.csv"])
        for f in files.dropLast() { XCTAssertEqual(Array(f.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47]) }
    }

    /// The element file is the screen's raster (colour, window, gamma applied): a half-contrast window changes the pixels.
    /// Mutation: `files` passes `MapDisplay()` instead of `model.display(...)` - red.
    func testTheElementPNGFollowsTheMapsDisplay() throws {
        let a = liveModel(), b = liveModel()
        b.mapDisplays[.element(13)] = MapDisplay(lo: 0.5, hi: 1, gamma: 1)
        let fa = try MapsExport.files(a), fb = try MapsExport.files(b)
        XCTAssertNotEqual(fa[1].data, fb[1].data)
        XCTAssertEqual(fa[2].data, fb[2].data, "the other element is untouched")
    }

    /// The HAADF file is the screen's too: its window and its colormap. Mutation: `files` passes `MapDisplay()` or ignores `haadfColormap` - red.
    func testTheHAADFPNGFollowsItsWindowAndColormap() throws {
        let base = try MapsExport.files(liveModel())[0].data
        let w = liveModel(); w.mapDisplays[.haadf] = MapDisplay(lo: 0.3, hi: 0.4, gamma: 1)
        XCTAssertNotEqual(try MapsExport.files(w)[0].data, base)
        let c = liveModel(); c.haadfColormap = ColormapKind.allCases.first { $0 != .gray } ?? .gray
        XCTAssertNotEqual(try MapsExport.files(c)[0].data, base)
    }

    /// No HAADF, nothing ticked: no HAADF file and no ColorMix file; the elements and the CSV remain.
    /// Mutation: `files` writes a ColorMix without a ticked element or backdrop - red.
    func testNoHAADFAndNothingTickedWritesOnlyElementsAndCSV() throws {
        let m = liveModel(); m.gridWidth = 0; m.gridHeight = 0; m.backdrop = []; m.mixed = []
        XCTAssertEqual(try MapsExport.files(m).map(\.name), ["scan-\(sym(13)).png", "scan-\(sym(14)).png", "scan-maps.csv"])
    }

    /// Mutation: `write` returns the folder's listing or writes outside `folder` - red.
    func testWriteCreatesTheFilesAndReportsTheirNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mapsexport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MapsExport.files(liveModel())
        let names = try MapsExport.write(files, to: dir)
        XCTAssertEqual(names, files.map(\.name))
        for f in files { XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(f.name)), f.data) }
        XCTAssertEqual(MapsExport.note(written: names, folder: dir), "Wrote 5 files to \(dir.lastPathComponent)")
        XCTAssertThrowsError(try MapsExport.write(files, to: dir.appendingPathComponent("missing")), "a folder that is not there is an error, not a silent 0")
    }

    /// The Maps button is on with one tile and no fit; off with none. Mutation: gate it on `export.csv` - red.
    func testTheMapsButtonNeedsOnlyATile() {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = []; XCTAssertFalse(ExportSection.canExportMaps(m))
        m.tiles = [tile(13, [0, 0, 0, 0], scale: 1)]; m.export.csv = nil
        XCTAssertTrue(ExportSection.canExportMaps(m))
    }
}
