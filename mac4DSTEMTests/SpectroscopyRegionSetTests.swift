import XCTest
import SwiftUI
import ShellSpectroscopy
import SpectroEDX
@testable import mac4DSTEM

/// The drawn regions as MacEMUI's region set (2026-10-22): the id mapping, the set built from the room's regions and what an edit of
/// the Regions list does to them.
@MainActor
final class SpectroscopyRegionSetTests: XCTestCase {
    private func model() -> SpectroscopyRoomModel {
        let m = SpectroscopyRoomModel.fixture
        m.regions = [RegionSummary(id: 0, name: "Whole map", pixels: 48, counts: 0, tint: .gray),
                     RegionSummary(id: 1, name: "Region 1", pixels: 12, counts: 0, tint: .purple, isDrawn: true),
                     RegionSummary(id: 2, name: "Region 2", pixels: 12, counts: 0, tint: .teal, isDrawn: true)]
        m.drawnShapes = [1: .rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3)), 2: .ellipse(PixelRect(x0: 4, y0: 3, x1: 8, y1: 6))]
        m.regionStyles = [1: DrawnRegionStyle(tint: SpectroscopyRoomModel.liveRegionColor),
                          2: DrawnRegionStyle(tint: RegionPalette.color(at: 0).color)]
        m.selectedRegion = 2
        return m
    }

    /// The id a region has in the set maps back, for small, large and negative values; a foreign UUID maps to nothing.
    /// Mutation: the byte order swapped between the two directions - red.
    func testTheRegionUUIDRoundTrips() {
        for id in [0, 1, 2, 255, 256, 70_000, Int(Int32.max)] { XCTAssertEqual(SpectroscopyRoomModel.regionID(SpectroscopyRoomModel.regionUUID(id)), id) }
        XCTAssertNotEqual(SpectroscopyRoomModel.regionUUID(1), SpectroscopyRoomModel.regionUUID(256))
        XCTAssertNil(SpectroscopyRoomModel.regionID(UUID()))
    }

    /// The set holds the drawn regions only, in order, with the right geometry, and the selected region is its selection.
    /// Mutation: the whole map included, or the rectangle's far corner taken as its width - red.
    func testTheSetHoldsTheDrawnRegionsWithTheirGeometry() {
        let set = model().regionSet
        XCTAssertEqual(set.regions.map(\.name), ["Region 1", "Region 2"])
        XCTAssertEqual(set.regions[0].geometry, .rectangle(x0: 0, y0: 0, x1: 4, y1: 3))
        XCTAssertEqual(set.regions[1].geometry, .ellipse(x0: 4, y0: 3, x1: 8, y1: 6))
        XCTAssertEqual(set.selectedID, SpectroscopyRoomModel.regionUUID(2))
    }

    /// The other regions are the shown ones that are not selected: what the map outlines beside the live region.
    /// Mutation: hidden regions outlined, or the selected one outlined twice - red.
    func testTheOtherRegionsAreTheShownUnselectedOnes() {
        let m = model()
        XCTAssertEqual(m.otherRegionSet.regions.map(\.name), ["Region 1"])
        m.regionStyles[1]?.isVisible = false
        XCTAssertTrue(m.otherRegionSet.regions.isEmpty)
    }

    /// A rename, a recolour and a hide in the list are kept in the room's styles; a name equal to the session's is no override.
    /// Mutation: the rename written to the session's name (lost when the session syncs), or a recolour dropped - red.
    func testListEditsAreKeptInTheStyles() {
        let m = model()
        var set = m.regionSet
        let id = set.regions[0].id
        set.rename(id, to: "Matrix")
        set.setColor(id, RegionColor(red: 0.1, green: 0.2, blue: 0.3))
        set.setVisible(id, false)
        m.apply(set)
        XCTAssertEqual(m.regionName(1), "Matrix")
        XCTAssertEqual(m.regionStyles[1]?.isVisible, false)
        XCTAssertEqual(RegionColor(m.regionColor(1), resolvedIn: EnvironmentValues()).red, 0.1, accuracy: 0.01)
        var back = m.regionSet
        back.rename(back.regions[0].id, to: "Region 1")
        m.apply(back)
        XCTAssertNil(m.regionStyles[1]?.name, "the session's own name is no override")
    }

    /// A delete in the list asks the controller to remove that region, and only that one; a click selects.
    /// Mutation: every region removed, or the selection ignored - red.
    func testListDeleteAndSelectGoToTheRoom() {
        let m = model()
        var removed: [Int] = []
        m.onRemoveRegion = { removed.append($0) }
        var set = m.regionSet
        set.remove(set.regions[0].id)
        m.apply(set)
        XCTAssertEqual(removed, [1])
        var pick = m.regionSet
        pick.select(pick.regions[0].id)
        m.apply(pick)
        XCTAssertEqual(m.selectedRegion, 1)
    }

    /// The Delete key removes the selected drawn region only: never the whole map, never a region that is not selected.
    func testDeleteRemovesTheSelectedDrawnRegionOnly() {
        let m = model()
        XCTAssertEqual(RegionKeys.removableID(m.regions, selected: 2), 2)
        XCTAssertNil(RegionKeys.removableID(m.regions, selected: 0))
        XCTAssertNil(RegionKeys.removableID(m.regions, selected: nil))
    }

    // MARK: lines and the Profile tab

    /// A line is listed after the regions, selecting it shows the Profile tab, and deleting it brings the Spectrum tab back.
    /// Mutation: the line left out of the set, the tab not following the selection, or the tab kept after the last line goes - red.
    func testALineIsListedSelectsTheProfileTabAndGoesWithItsDelete() {
        let m = model()
        XCTAssertFalse(m.availablePanes.contains(.profile), "no line, no Profile tab")
        XCTAssertTrue(m.availablePanes.contains(.table), "maps, so a Table tab")
        m.addLine(from: PixelPoint(x: 2, y: 16), to: PixelPoint(x: 30, y: 16))
        XCTAssertEqual(m.regionSet.regions.map(\.name), ["Region 1", "Region 2", "Line 1"])
        XCTAssertEqual(m.regionSet.regions[2].geometry, .line(RegionPoint(x: 2, y: 16), RegionPoint(x: 30, y: 16)))
        XCTAssertTrue(m.availablePanes.contains(.profile)); XCTAssertEqual(m.shownPane, .profile, "drawing a line shows its profile")
        var pick = m.regionSet
        pick.select(pick.regions[0].id)
        m.apply(pick)
        XCTAssertEqual(m.shownPane, .spectrum, "a region's row brings the spectrum back"); XCTAssertNil(m.selectedLine)
        var gone = m.regionSet
        gone.remove(gone.regions[2].id)
        m.apply(gone)
        XCTAssertTrue(m.lines.isEmpty); XCTAssertFalse(m.availablePanes.contains(.profile))
        m.pane = .profile
        XCTAssertEqual(m.shownPane, .spectrum, "no line, no Profile tab, whatever was chosen")
    }

    /// The Profile tab plots each mixed element map along the line in the map's own unit: a column ramp read along a horizontal line.
    /// Mutation: the unmixed element plotted, or the 0...1 values plotted without their scale - red.
    func testTheProfileSeriesAreTheMixedElementMapsAlongTheLine() throws {
        let m = SpectroscopyRoomModel.fixture
        let w = 16, h = 4
        let ramp = (0..<(w * h)).map { Float($0 % w) / 15 }
        m.tiles = [MapTile(z: 12, width: w, height: h, values: ramp, scale: 15), MapTile(z: 14, width: w, height: h, values: ramp, scale: 15)]
        m.mixed = [12]
        m.scanPixel = (size: 0.5, unit: "nm")
        m.addLine(from: PixelPoint(x: 2.5, y: 1.5), to: PixelPoint(x: 10.5, y: 1.5))
        let series = m.profileSeries
        XCTAssertEqual(series.map(\.id), ["Mg"], "the mixed element only")
        XCTAssertEqual(series[0].values.count, 9)
        XCTAssertEqual(series[0].values[0], 2, accuracy: 1e-4); XCTAssertEqual(series[0].values[8], 10, accuracy: 1e-4)
        XCTAssertEqual(series[0].length, 4, accuracy: 1e-9, "8 px at 0.5 nm")
        XCTAssertEqual(m.profileUnit, "nm")
    }
}
