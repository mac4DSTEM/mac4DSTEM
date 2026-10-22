import XCTest
import SwiftUI
import DSTEMCore
@testable import mac4DSTEM
import SpectroCore
import SpectroEDX

/// Spec 2 lane B: the maps as pickers (D-2), regions on the ColorMix only (D-1), highlight (D-15), region editing (D-16).
@MainActor
final class SpectroscopySpec2BTests: XCTestCase {
    private func model() -> SpectroscopyRoomModel {
        SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
    }
    private func bytes(_ img: CGImage?) throws -> [UInt8] { Array(try XCTUnwrap(img?.dataProvider?.data as Data?)) }

    /// A click on an element tile flips its place in the mix; the outline (`isInMix`) follows; the highlight is set.
    /// Mutations: `pick` not toggling `mixed` - red; `isInMix` reading `active` - red; the highlight not set - red.
    func testClickingAnElementTileTogglesTheMixAndHighlightsIt() {
        let m = model()
        XCTAssertFalse(m.isInMix(.element(13)))
        m.pick(.element(13))
        XCTAssertTrue(m.mixed.contains(13)); XCTAssertTrue(m.isInMix(.element(13)))
        XCTAssertEqual(m.highlightedZ, 13)
        m.pick(.element(13))
        XCTAssertFalse(m.mixed.contains(13)); XCTAssertFalse(m.isInMix(.element(13)))
    }

    /// The HAADF tile toggles the grey layer under the mix, which starts OUT (as Velox); the ColorMix tile is not a picker.
    /// Mutations: `mixHAADF` starting true - red; HAADF toggling `mixed` instead - red; `pick(.colorMix)` toggling the backdrop - red.
    func testClickingTheHAADFTileTogglesTheBackdropOnly() {
        let m = model()
        XCTAssertFalse(m.mixHAADF); XCTAssertFalse(m.isInMix(.haadf))
        m.pick(.haadf)
        XCTAssertTrue(m.mixHAADF); XCTAssertTrue(m.isInMix(.haadf)); XCTAssertTrue(m.mixed.isEmpty)
        m.pick(.colorMix)
        XCTAssertTrue(m.mixHAADF); XCTAssertTrue(m.mixed.isEmpty)
        m.pick(.haadf)
        XCTAssertFalse(m.mixHAADF); XCTAssertFalse(m.isInMix(.haadf))
    }

    private func tile() -> MapTile { MapTile(z: 13, width: 3, height: 1, values: [1, 0, 0]) }

    /// No backdrop: a pixel with no element is black. With the backdrop: grey where no element sits, the element's colour where it does.
    /// Mutations: the backdrop blended even when empty/off (a 0.5 fallback) - red; the element pixel's colour lost under the backdrop - red.
    func testTheMixSitsOnBlackWithoutTheBackdropAndOnGreyWithIt() throws {
        let red: ColorMixComposite.RGB = (1, 0, 0)
        let off = try bytes(ColorMixRaster.image(tiles: [tile()], mixed: [13], colors: [13: red], backdrop: [], width: 3, height: 1))
        XCTAssertEqual(Array(off[4..<8]), [0, 0, 0, 255], "no element, no backdrop: black")
        XCTAssertEqual(Array(off[0..<4]), [255, 0, 0, 255])
        let on = try bytes(ColorMixRaster.image(tiles: [tile()], mixed: [13], colors: [13: red], backdrop: [0.5, 0.5, 1], width: 3, height: 1))
        XCTAssertEqual(Array(on[0..<4]), [255, 0, 0, 255], "a full-strength element hides the backdrop")
        XCTAssertEqual(Array(on[4..<8]), [128, 128, 128, 255], "no element: the backdrop's grey")
        XCTAssertEqual(Array(on[8..<12]), [255, 255, 255, 255])
    }

    /// Nothing mixed and no backdrop: no image at all (the tile draws black); nothing mixed with the backdrop: the grey scan.
    func testNothingMixedWithoutBackdropIsNoImage() {
        XCTAssertNil(ColorMixRaster.image(tiles: [tile()], mixed: [], colors: [:], backdrop: [], width: 3, height: 1))
        XCTAssertNotNil(ColorMixRaster.image(tiles: [tile()], mixed: [], colors: [:], backdrop: [0, 0, 0], width: 3, height: 1))
    }

    /// The raster cache is keyed by `mixHAADF`.
    /// Mutation: `mixHAADF` dropped from `Key` (always equal) - red.
    func testTheCacheKeyDiffersByTheBackdropFlag() {
        let cache = ColorMixRasterCache()
        var key = ColorMixRasterCache.Key(revision: 1, mixed: [13], width: 3, height: 1, backdropCount: 3, mixHAADF: true)
        var made = 0
        func build() -> CGImage? { made += 1; return nil }
        _ = cache.image(for: key, build: build); _ = cache.image(for: key, build: build)
        XCTAssertEqual(made, 1)
        key.mixHAADF = false; _ = cache.image(for: key, build: build)
        XCTAssertEqual(made, 2)
    }

    /// ⌫ removes the drawn live region (never the whole map's row); none drawn: nothing.
    /// Mutation: the `isDrawn` filter removed (first region) - red.
    func testTheDeleteKeyTargetsTheDrawnRegion() {
        let whole = RegionSummary(id: 1, name: "Whole map", pixels: 9, counts: 1, tint: .gray)
        var drawn = RegionSummary(id: 2, name: "Region", pixels: 4, counts: 1, tint: .yellow); drawn.isDrawn = true
        XCTAssertEqual(RegionKeys.removableID([whole, drawn], selected: 2), 2)
        XCTAssertNil(RegionKeys.removableID([whole], selected: 0))
        XCTAssertNil(RegionKeys.removableID([], selected: nil))
    }
}
