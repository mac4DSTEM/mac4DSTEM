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
}
