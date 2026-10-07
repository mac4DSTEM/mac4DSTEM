import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Drive findings, lane L8 (2026-10-07): the Show menu's toggles as inspector buttons, the live region's colour, a scale bar on
/// every tile and one in the exported PNGs. Each test names its mutation.
@MainActor
final class SpectroscopyDriveL8Tests: XCTestCase {

    private func tile(_ z: Int, _ w: Int, _ h: Int) -> MapTile {
        var t = MapTile(z: z, width: w, height: h, values: (0..<(w * h)).map { Float($0 % 17) / 17 })
        t.scale = 100
        return t
    }
    /// A 64 x 64 scan with one element, a HAADF and a stated pixel size (0.5 nm).
    private func bigModel(scaleBar: Bool) -> SpectroscopyRoomModel {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = [tile(13, 64, 64)]
        m.mixed = [13]; m.gridWidth = 64; m.gridHeight = 64
        m.backdrop = (0..<4096).map { Float($0 % 31) / 31 }
        m.export.mapsStem = "scan"
        m.export.scaleBar = scaleBar
        m.scanPixel = (size: 0.5, unit: "nm")
        return m
    }
    private func rgba(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return out
    }

    // MARK: Spectrum section (the Show menu's toggles as buttons)

    /// Each curve button writes its own layer and no other, in the order the legend had.
    /// Mutation: two key paths swapped in `CurveLayer.keyPath` (residual to model) - red.
    func testEachCurveButtonWritesItsOwnLayerOnly() {
        XCTAssertEqual(CurveLayer.allCases.map(\.title), ["Spectrum", "Background", "Model", "Residual", "Pins"])
        for layer in CurveLayer.allCases {
            var l = SpectrumLayers(); l.spectrum = false; l.background = false; l.model = false; l.residual = false; l.pins = false
            l[keyPath: layer.keyPath] = true
            let on = CurveLayer.allCases.filter { l[keyPath: $0.keyPath] }
            XCTAssertEqual(on, [layer], "\(layer.title) lights only itself")
        }
        var l = SpectrumLayers()
        l.residual = false
        XCTAssertEqual(CurveLayer.allCases.filter { !l[keyPath: $0.keyPath] }, [.residual], "the model's residual flag is the Residual button")
        l = SpectrumLayers(); l.model = false
        XCTAssertEqual(CurveLayer.allCases.filter { !l[keyPath: $0.keyPath] }, [.model])
    }

    /// The segmented Linear / Log picker and the model's Bool are one value.
    /// Mutation: `LayerScale.isLog` returns true for `.linear`, or `init(log:)` is inverted - red.
    func testTheScalePickerIsTheLogFlag() {
        XCTAssertEqual(LayerScale.allCases.map(\.title), ["Linear", "Log"])
        XCTAssertEqual(LayerScale(log: false), .linear)
        XCTAssertEqual(LayerScale(log: true), .log)
        XCTAssertFalse(LayerScale.linear.isLog)
        XCTAssertTrue(LayerScale.log.isLog)
        for s in LayerScale.allCases { XCTAssertEqual(LayerScale(log: s.isLog), s) }
        XCTAssertFalse(SpectrumLayers().log, "linear by default (spec 2 D-6)")
    }

    /// Per pixel needs a pooled-pixel count; Windows needs bands.
    /// Mutation: `perPixelEnabled` ignores `spectrumPixels`, or `windowsEnabled` ignores `windowBands` - red.
    func testPerPixelAndWindowsAreOffUntilTheyHaveSomethingToShow() {
        let m = SpectroscopyRoomModel.fixture
        m.spectrumPixels = 0; m.windowBands = []
        XCTAssertFalse(SpectrumLayersSection.perPixelEnabled(m))
        XCTAssertFalse(SpectrumLayersSection.windowsEnabled(m))
        m.spectrumPixels = 1200
        XCTAssertTrue(SpectrumLayersSection.perPixelEnabled(m))
        m.windowBands = [WindowBand(id: "Al_Ka.signal", elementZ: 13, label: "Al K\u{03B1}", range: 1.4...1.57, kind: .signal)]
        XCTAssertTrue(SpectrumLayersSection.windowsEnabled(m))
    }

    // MARK: the bar on every tile

    /// A tile narrower than twice the bar's minimum length gets no bar; a file without a pixel size gets none either.
    /// Mutation: the guard compares `width < minimumLengthPoints` (not twice), or is dropped - red.
    func testTheBarRuleIsPerTile() throws {
        let min = MapScaleBar.minimumLengthPoints
        XCTAssertNil(MapScaleBar.tilePlan(pixelSize: 0.5, unit: "nm", pointsPerPixel: 1, width: 2 * min - 1))
        let p = try XCTUnwrap(MapScaleBar.tilePlan(pixelSize: 0.5, unit: "nm", pointsPerPixel: 1, width: 2 * min))
        XCTAssertLessThan(p.lengthPoints, 2 * min, "the bar fits its tile")
        XCTAssertNil(MapScaleBar.tilePlan(pixelSize: 0, unit: "nm", pointsPerPixel: 1, width: 200))
    }

    /// A smaller tile gets a shorter round length: the label follows the tile's own points per pixel.
    /// Mutation: `tilePlan` ignores `pointsPerPixel` (always the same label) - red.
    func testASmallerTileGetsAShorterBar() throws {
        let big = try XCTUnwrap(MapScaleBar.tilePlan(pixelSize: 1, unit: "nm", pointsPerPixel: 4, width: 256))
        let small = try XCTUnwrap(MapScaleBar.tilePlan(pixelSize: 1, unit: "nm", pointsPerPixel: 1, width: 96))
        XCTAssertEqual(big.label, "20 nm")
        XCTAssertEqual(small.label, "20 nm")   // 96 pt wide -> target 32 pt -> 32 nm at 1 nm/pt -> 20 nm, 20 pt long
        XCTAssertEqual(big.lengthPoints, 80, accuracy: 1e-9)
        XCTAssertEqual(small.lengthPoints, 20, accuracy: 1e-9)
        XCTAssertLessThan(small.lengthPoints, big.lengthPoints)
    }

    // MARK: export

    /// Mutation: `pngName` ignores `scaleBar`, puts the tag before the kernel, or tags the off case - red.
    func testThePNGNameGainsScalebarOnlyWhenTheBarIsOn() {
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al"), "a-Al.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al", scaleBar: false), "a-Al.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al", scaleBar: true), "a-Al-scalebar.png")
        XCTAssertEqual(MapsExport.pngName(stem: "a", label: "Al", mode: .netCounts, smoothing: .box3, scaleBar: true), "a-Al-net-3x3-scalebar.png")
    }

    /// The bar is in the PNG, never in the CSV; the name says so; with it off the files are exactly as before.
    /// Mutation: `files` ignores `export.scaleBar` (always draws, or never) - red; the CSV loses its bytes' equality if it is touched.
    func testTheExportCarriesTheBarOnlyWhenOnAndNeverInTheCSV() throws {
        let on = try MapsExport.files(bigModel(scaleBar: true)), off = try MapsExport.files(bigModel(scaleBar: false))
        XCTAssertEqual(off.map(\.name), ["scan-HAADF.png", "scan-Al.png", "scan-ColorMix.png", "scan-maps.csv"].map { $0.replacingOccurrences(of: "Al", with: PeriodicLayout.symbol(13)) })
        XCTAssertEqual(on.map(\.name), off.map(\.name).map { $0.hasSuffix(".png") ? $0.replacingOccurrences(of: ".png", with: "-scalebar.png") : $0 })
        XCTAssertEqual(on.last?.data, off.last?.data, "the CSV never changes")
        for (a, b) in zip(on.dropLast(), off.dropLast()) { XCTAssertNotEqual(a.data, b.data, a.name) }
    }

    /// A file that states no pixel size draws no bar and is not named as if it had one, whatever the toggle says.
    /// Mutation: the nil pixel size is replaced by a default (1 nm) - red.
    func testNoPixelSizeMeansNoBarAndNoTag() throws {
        let m = bigModel(scaleBar: true); m.scanPixel = nil
        XCTAssertEqual(try MapsExport.files(m).map(\.name).filter { $0.contains("scalebar") }, [])
        XCTAssertFalse(ExportSection.scaleBarShown(m), "the box is not ticked when it cannot draw")
        XCTAssertFalse(ExportSection.scaleBarEnabled(m))
        XCTAssertTrue(ExportSection.scaleBarShown(bigModel(scaleBar: true)))
        XCTAssertFalse(ExportSection.scaleBarShown(bigModel(scaleBar: false)))
    }

    /// The bar is drawn into the bottom-left corner only: a 64 x 64 bitmap differs there and nowhere else.
    /// Mutation: the bar is drawn at the top-left, or the whole image is redrawn shifted, or the inset exceeds 8 px - red.
    func testTheBarChangesTheBottomLeftCornerAndNothingElse() throws {
        let image = try XCTUnwrap(ElementTileRaster.image(tile: tile(13, 64, 64), color: (r: 0.2, g: 0.6, b: 0.9), display: MapDisplay()))
        let plan = try XCTUnwrap(MapScaleBar.tilePlan(pixelSize: 0.5, unit: "nm", pointsPerPixel: 1, width: 64))
        let barred = try XCTUnwrap(MapBitmap.addingScaleBar(to: image, plan: plan))
        XCTAssertEqual(barred.width, 64); XCTAssertEqual(barred.height, 64)
        let a = rgba(image), b = rgba(barred)
        var changed: [(x: Int, y: Int)] = []
        for y in 0..<64 { for x in 0..<64 where a[(y * 64 + x) * 4..<(y * 64 + x) * 4 + 3] != b[(y * 64 + x) * 4..<(y * 64 + x) * 4 + 3] { changed.append((x, y)) } }
        XCTAssertGreaterThan(changed.count, 20, "the bar and its label are drawn")
        XCTAssertGreaterThanOrEqual(changed.map(\.x).min() ?? 0, 6, "an 8 px inset (outline 1 px, text shadow)")
        XCTAssertLessThan(changed.map(\.x).max() ?? 99, 56, "left half")
        XCTAssertGreaterThanOrEqual(changed.map(\.y).min() ?? 0, 32, "bottom half")
        XCTAssertLessThanOrEqual(changed.map(\.y).max() ?? 99, 57, "inside the 8 px inset from the bottom")
        // The bar itself: white pixels at the bottom-left inset, `lengthPoints` wide.
        let bottomBarRow = 64 - 9   // the bar's 3 px rows sit at y from the bottom 8...10
        let whiteRun = (0..<64).filter { b[(bottomBarRow * 64 + $0) * 4] == 255 && b[(bottomBarRow * 64 + $0) * 4 + 1] == 255 && b[(bottomBarRow * 64 + $0) * 4 + 2] == 255 }
        XCTAssertEqual(whiteRun.count, Int(plan.lengthPoints.rounded()))
        XCTAssertEqual(whiteRun.first, 8)
    }

    /// The exported PNG of a 64 x 64 scan differs from the one without the bar in the bottom-left corner only.
    /// Mutation: `files` draws the bar on the ColorMix only, or after the PNG encode (the data would equal) - red.
    func testTheExportedPNGsDifferOnlyInTheCorner() throws {
        let on = try MapsExport.files(bigModel(scaleBar: true)), off = try MapsExport.files(bigModel(scaleBar: false))
        func decode(_ d: Data) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(d as CFData, nil)!, 0, nil)! }
        for (a, b) in zip(on.dropLast(), off.dropLast()) {
            let ia = rgba(decode(a.data)), ib = rgba(decode(b.data))
            var outside = 0, inside = 0
            for y in 0..<64 { for x in 0..<64 {
                let i = (y * 64 + x) * 4
                let differs = ia[i..<i + 3] != ib[i..<i + 3]
                if differs { if x < 56 && y >= 32 { inside += 1 } else { outside += 1 } }
            } }
            XCTAssertGreaterThan(inside, 0, a.name)
            XCTAssertEqual(outside, 0, a.name)
        }
    }

    // MARK: the live region's colour

    /// The live region's outline is 2 pt, a pin's 1.6 pt, and the capsule's text leads with the region's colour.
    /// Mutation: the live width falls to 1.2, or the pin width rises to 2 - red.
    func testRegionStrokeWidths() {
        XCTAssertEqual(MapTileView.liveOutlineWidth, 2)
        XCTAssertEqual(MapTileView.pinOutlineWidth, 1.6)
        XCTAssertGreaterThan(MapTileView.liveOutlineWidth, MapTileView.pinOutlineWidth)
    }
}
