//
//  SpectroscopyEDSAdoptionTests.swift
//  The Spectroscopy room on MacEMUI 0.3.0 (EDS adoption, 2026-10-22): the region bridge (what the drawing layer reports becomes the
//  room's calls), selection and delete, the colour mix and the grid items, the tile caption, the Maps caption, the periodic table's
//  actions, the pinned MacEMUI package, and rule 11 (the display filter on by default, display only). Pure: no view is drawn here.
//  Every test names the mutation that turns it red.
//

import XCTest
import SwiftUI
import ShellSpectroscopy
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
import SpectroCore
import SpectroEDX

@MainActor
final class SpectroscopyEDSAdoptionTests: XCTestCase {
    private var keep: [AppState] = []

    private func emptyModel() -> SpectroscopyRoomModel {
        SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
    }

    /// The fixture with regions 1...3 drawn, and the room's callbacks recorded.
    private final class Calls {
        var begins: [Int?] = []
        var edits: [(shape: SpectrumRegionShape, final: Bool)] = []
        var removed: [Int] = []
    }

    private func recordingModel() -> (SpectroscopyRoomModel, Calls) {
        let m = SpectroscopyRoomModel.fixture
        for i in m.regions.indices where m.regions[i].id != 0 { m.regions[i].isDrawn = true }
        let calls = Calls()
        m.onBeginRegionEdit = { calls.begins.append($0) }
        m.onRegionEdit = { calls.edits.append(($0, $1)) }
        m.onRemoveRegion = { calls.removed.append($0) }
        SpectroscopyRegionBridge.beginDrag(m, nil)   // the bridge's "a new shape's drag began" flag is static: start from none
        return (m, calls)
    }

    private let box = SpectrumRegionShape.rectangle(PixelRect(x0: 1, y0: 1, x1: 3, y1: 3))
    private let boxGeometry = RegionGeometry.rectangle(x0: 1, y0: 1, x1: 3, y1: 3)

    // MARK: 1. The region bridge

    /// A shape drawn without a drag in front of it starts a new region, then takes the final shape.
    /// Mutation: `finish` not telling the room a new region begins (no `onBeginRegionEdit(nil)`), or sending `final: false` - red.
    func testAFinishedShapeBeginsANewRegionAndIsFinal() {
        let (m, calls) = recordingModel()
        SpectroscopyRegionBridge.finish(m, box)
        XCTAssertEqual(calls.begins, [nil])
        XCTAssertEqual(calls.edits.map(\.shape), [box]); XCTAssertEqual(calls.edits.map(\.final), [true])
    }

    /// A new shape's drag tells the room it begins once, the spectrum follows with non-final edits, and the end adds one final edit
    /// and no second begin.
    /// Mutation: `dragBegun` not set (a begin per drag update) or not honoured by `finish` (a second begin at the end) - red.
    func testADragBeginsOnceFollowsNonFinalAndFinishesFinal() {
        let (m, calls) = recordingModel()
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: nil, geometry: boxGeometry))
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: nil, geometry: boxGeometry))
        SpectroscopyRegionBridge.finish(m, box)
        XCTAssertEqual(calls.begins, [nil], "exactly one begin")
        XCTAssertEqual(calls.edits.map(\.final), [false, false, true])
        XCTAssertEqual(calls.edits.map(\.shape), [box, box, box])
    }

    /// The end of a drag (nil) clears the flag: the next new shape begins again.
    /// Mutation: `beginDrag(nil)` not resetting `dragBegun` - the second drag records no begin, red.
    func testTheEndOfADragLetsTheNextShapeBeginAgain() {
        let (m, calls) = recordingModel()
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: nil, geometry: boxGeometry))
        SpectroscopyRegionBridge.beginDrag(m, nil)
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: nil, geometry: boxGeometry))
        XCTAssertEqual(calls.begins, [nil, nil])
    }

    /// Dragging an existing region begins THAT region's edit (its id), with a non-final shape; a line pools nothing, so a line's drag and a
    /// line's id are ignored.
    /// Mutation: the region's id dropped (begin(nil)), the line geometry forwarded as a shape, or a line's UUID read as a region - red.
    func testDraggingARegionBeginsItsOwnEditAndALineIsIgnored() {
        let (m, calls) = recordingModel()
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: SpectroscopyRoomModel.regionUUID(2), geometry: boxGeometry))
        XCTAssertEqual(calls.begins, [2])
        XCTAssertEqual(calls.edits.map(\.final), [false]); XCTAssertEqual(calls.edits.map(\.shape), [box])
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: nil, geometry: .line(RegionPoint(x: 0, y: 0), RegionPoint(x: 5, y: 5))))
        SpectroscopyRegionBridge.beginDrag(m, RegionDragUpdate(id: SpectroscopyRoomModel.lineUUID(0), geometry: boxGeometry))
        XCTAssertEqual(calls.begins, [2], "nothing added by a line")
        XCTAssertEqual(calls.edits.count, 1)
    }

    /// A released edit of a region is its begin plus a final shape with the corners rounded to whole pixels.
    /// Mutation: the corners truncated (`Int(x)`) instead of rounded, or the edit sent non-final - red.
    func testAnEditedRegionIsFinalWithRoundedCorners() {
        let (m, calls) = recordingModel()
        SpectroscopyRegionBridge.edit(m, SpectroscopyRoomModel.regionUUID(2), .ellipse(x0: 1.4, y0: 2.6, x1: 5.6, y1: 7.4))
        XCTAssertEqual(calls.begins, [2])
        XCTAssertEqual(calls.edits.map(\.shape), [.ellipse(PixelRect(x0: 1, y0: 3, x1: 6, y1: 7))])
        XCTAssertEqual(calls.edits.map(\.final), [true])
    }

    /// A released edit of a line moves that line's ends, keeps it selected and tells the room nothing about regions.
    /// Mutation: the edit written to another line, the line left unselected, or forwarded as a region edit - red.
    func testAnEditedLineMovesItsEnds() {
        let (m, calls) = recordingModel()
        m.addLine(from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 4, y: 4))
        m.addLine(from: PixelPoint(x: 0, y: 9), to: PixelPoint(x: 9, y: 9))
        m.selectedLine = nil
        SpectroscopyRegionBridge.edit(m, SpectroscopyRoomModel.lineUUID(0), .line(RegionPoint(x: 2, y: 3), RegionPoint(x: 8, y: 9)))
        XCTAssertEqual(m.lines[0].from, PixelPoint(x: 2, y: 3)); XCTAssertEqual(m.lines[0].to, PixelPoint(x: 8, y: 9))
        XCTAssertEqual(m.lines[1].from, PixelPoint(x: 0, y: 9), "the other line is untouched")
        XCTAssertEqual(m.selectedLine, 0)
        XCTAssertTrue(calls.begins.isEmpty); XCTAssertTrue(calls.edits.isEmpty)
    }

    /// The shape of a geometry: boxes to rounded whole pixels, a polygon's vertices as they are, a line none.
    /// Mutation: a line given a shape, or the ellipse mapped to a rectangle - red.
    func testShapeOfAGeometry() {
        XCTAssertEqual(SpectroscopyRegionBridge.shape(.rectangle(x0: 1.2, y0: 2, x1: 3.7, y1: 4)), .rectangle(PixelRect(x0: 1, y0: 2, x1: 4, y1: 4)))
        XCTAssertEqual(SpectroscopyRegionBridge.shape(.ellipse(x0: 0, y0: 0, x1: 5, y1: 6)), .ellipse(PixelRect(x0: 0, y0: 0, x1: 5, y1: 6)))
        let v = [RegionPoint(x: 0, y: 0), RegionPoint(x: 4, y: 0), RegionPoint(x: 2, y: 3)]
        XCTAssertEqual(SpectroscopyRegionBridge.shape(.polygon(v)), .polygon(v.map { PixelPoint(x: $0.x, y: $0.y) }))
        XCTAssertNil(SpectroscopyRegionBridge.shape(.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 1, y: 1))))
    }

    // MARK: 2. Selection

    /// A click on nothing returns to the whole map: no line, the spectrum pane, region 0.
    /// Mutation: `select(nil)` leaving the selected region or line, or the pane on Profile - red.
    func testSelectingNothingSelectsTheWholeMap() {
        let (m, _) = recordingModel()
        m.addLine(from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 4, y: 4))
        XCTAssertEqual(m.pane, .profile)
        SpectroscopyRegionBridge.select(m, nil)
        XCTAssertEqual(m.selectedRegion, 0); XCTAssertNil(m.selectedLine); XCTAssertEqual(m.pane, .spectrum)
    }

    /// A click on a region selects it and shows the spectrum; a click on a line selects the line and shows the profile.
    /// Mutation: the region's id and the line's id swapped, the line left unselected, or the pane not set - red.
    func testSelectingARegionOrALine() {
        let (m, _) = recordingModel()
        m.addLine(from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 4, y: 4))
        SpectroscopyRegionBridge.select(m, SpectroscopyRoomModel.regionUUID(3))
        XCTAssertEqual(m.selectedRegion, 3); XCTAssertNil(m.selectedLine); XCTAssertEqual(m.pane, .spectrum)
        SpectroscopyRegionBridge.select(m, SpectroscopyRoomModel.lineUUID(0))
        XCTAssertEqual(m.selectedLine, 0); XCTAssertEqual(m.pane, .profile)
        XCTAssertEqual(m.selectedRegion, 3, "a line does not change the selected region")
    }

    // MARK: 3. Delete

    /// ⌫ removes the selected line first and does not touch the regions.
    /// Mutation: the line branch missing (the region goes instead) or the line left selected - red.
    func testDeleteRemovesTheSelectedLine() {
        let (m, calls) = recordingModel()
        m.addLine(from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 4, y: 4))
        SpectroscopyRegionBridge.deleteSelected(m)
        XCTAssertTrue(m.lines.isEmpty); XCTAssertNil(m.selectedLine)
        XCTAssertTrue(calls.removed.isEmpty)
    }

    /// ⌫ with a drawn region selected asks the room to remove that region.
    /// Mutation: the wrong id (the first drawn region) or no call - red.
    func testDeleteRemovesTheSelectedDrawnRegion() {
        let (m, calls) = recordingModel()
        m.selectedRegion = 3
        SpectroscopyRegionBridge.deleteSelected(m)
        XCTAssertEqual(calls.removed, [3])
    }

    /// ⌫ with the whole map selected removes nothing.
    /// Mutation: the `isDrawn` guard (`RegionKeys.removableID`) bypassed - red.
    func testDeleteNeverRemovesTheWholeMap() {
        let (m, calls) = recordingModel()
        m.selectedRegion = 0
        SpectroscopyRegionBridge.deleteSelected(m)
        XCTAssertTrue(calls.removed.isEmpty)
    }

    // MARK: 4. The colour mix and the grid

    /// The HAADF is out of the mix by default (Velox).
    /// Mutation: `mixHAADF` back to true - red.
    func testTheHAADFIsOutOfTheMixByDefault() {
        XCTAssertFalse(emptyModel().mixHAADF)
        XCTAssertFalse(SpectroscopyRoomModel.fixture.mixHAADF)
    }

    /// The anchor tile has an image when an element is mixed, or when the HAADF is in and a backdrop exists; otherwise it shows the placeholder.
    /// Mutation: `mixHasImage` true with the HAADF in but no backdrop, or ignoring the HAADF flag - red.
    func testTheMixHasAnImageOnlyWithSomethingInIt() {
        let m = emptyModel()
        XCTAssertFalse(m.mixHasImage)
        m.pick(.haadf)                                       // in the mix, but no HAADF behind it yet
        XCTAssertFalse(m.mixHasImage)
        m.gridWidth = 2; m.gridHeight = 2; m.backdrop = [0.1, 0.2, 0.3, 0.4]
        XCTAssertTrue(m.mixHasImage)
        m.pick(.haadf)
        XCTAssertFalse(m.mixHasImage, "a backdrop that is out of the mix is no image")
        m.pick(.element(13))
        XCTAssertFalse(m.mixHasImage, "an element with no tile behind it draws nothing")
        m.tiles = [MapTile(z: 13, width: 2, height: 2, values: [0, 1, 0, 1])]
        XCTAssertTrue(m.mixHasImage)
        XCTAssertEqual(SpectroscopyRoomModel.mixPlaceholder, "Select maps on the right to build the colour mix")
    }

    /// The right-hand items are the HAADF first (when there is one), then the element tiles; the mix is the anchor and never an item.
    /// Mutation: the colour mix listed among the items, the HAADF listed last, or listed without a backdrop - red.
    func testTheGridItemsAreTheHAADFThenTheElements() {
        let m = emptyModel()
        m.gridWidth = 2; m.gridHeight = 2
        m.tiles = [MapTile(z: 13, width: 2, height: 2, values: [0, 1, 0, 1]), MapTile(z: 14, width: 2, height: 2, values: [1, 0, 1, 0])]
        XCTAssertEqual(m.gridItems.map(\.id), [.element(13), .element(14)], "no backdrop: no HAADF tile")
        m.backdrop = [0.1, 0.2, 0.3, 0.4]
        XCTAssertEqual(m.gridItems.map(\.id), [.haadf, .element(13), .element(14)])
        XCTAssertFalse(m.gridItems.contains { $0.id == .colorMix })
    }

    // MARK: 5. The tile caption

    /// The detail line names the chosen lines without the symbol, the per-pixel composition, and "filtered" when a kernel is set.
    /// Mutation: the symbol prefix kept, "per-pixel" dropped for wt% and at%, or "filtered" shown with no kernel - red.
    func testTheTileCaptionPartsAreJoinedInOrder() {
        XCTAssertEqual(MapTileCaption.detail(map: .element(13), mode: .atomic, smoothing: .box3, lineLabel: "Al K\u{03B1}+K\u{03B2}", mixed: []),
                       "K\u{03B1}+K\u{03B2} \u{00B7} at% \u{00B7} per-pixel \u{00B7} filtered")
        XCTAssertNil(MapTileCaption.detail(map: .element(13), mode: .integrated, smoothing: .none, lineLabel: nil, mixed: []))
        XCTAssertEqual(MapTileCaption.detail(map: .colorMix, mode: .netCounts, smoothing: .none, lineLabel: nil, mixed: ["O", "Al"]), "O + Al")
        XCTAssertNil(MapTileCaption.detail(map: .haadf, mode: .netCounts, smoothing: .box3, lineLabel: nil, mixed: []))
    }

    // MARK: 6. The Maps section's caption

    private func tile(footer: String?) -> MapTile {
        var t = MapTile(z: 13, width: 1, height: 1, values: [1]); t.footer = footer; return t
    }

    /// One secondary line: a quantification failure wins over everything; in a composition mode the first tile's footer; before a fit
    /// "wt% and at% need Quantify"; after a fit in net mode nothing.
    /// Mutation: the order of the three cases changed, the footer shown in net mode, or the hint kept after a fit - red.
    func testTheMapsCaptionPicksOneLine() {
        let m = emptyModel()
        m.tiles = [tile(footer: "per-pixel, no \u{03C3} \u{00B7} validation: none")]
        m.hasFit = false; m.mapMode = .netCounts
        XCTAssertEqual(MapsSection.caption(m), "wt% and at% need Quantify")
        m.quantMapsFailure = "Quantify refused: no k"
        XCTAssertEqual(MapsSection.caption(m), "Quantify refused: no k", "a failure wins even before a fit")
        m.hasFit = true; m.mapMode = .atomic
        XCTAssertEqual(MapsSection.caption(m), "Quantify refused: no k")
        m.quantMapsFailure = nil
        XCTAssertEqual(MapsSection.caption(m), "per-pixel, no \u{03C3} \u{00B7} validation: none")
        m.mapMode = .netCounts
        XCTAssertNil(MapsSection.caption(m))
    }

    // MARK: 7. The periodic table's actions

    /// A quantified element is `.quantify`; helium has no usable line and is `.unavailable`.
    /// Mutation: the shell's state mapped case by case wrongly (quantify shown as fit only) or the availability reason dropped - red.
    func testTheTableStatesFollowTheModel() {
        let m = SpectroscopyRoomModel.fixture
        m.elements = ElementSelection(); m.elements.set(13, .quantify)
        let a = SpectroscopyPeriodicTable.actions(m)
        XCTAssertEqual(a.state(13), .quantify)
        if case .unavailable = a.state(2) {} else { XCTFail("He has no usable line at this window") }
        m.elements.set(13, .fitOnly)
        XCTAssertEqual(a.state(13), .fitOnly)
        XCTAssertEqual(a.role(13), .fitOnly)
    }

    /// A click picks the element (role and selection), a role choice sets the role, hovering highlights the element's lines.
    /// Mutation: `click` not selecting the element, `setRole` ignoring the choice, or `hover(nil)` leaving the highlight - red.
    func testTheTableClickRoleAndHoverReachTheModel() {
        let m = SpectroscopyRoomModel.fixture
        m.elements = ElementSelection(); m.selectedElement = nil; m.highlightedZ = nil
        let a = SpectroscopyPeriodicTable.actions(m)
        a.click(29)
        XCTAssertEqual(m.elements.role(29), .quantify); XCTAssertEqual(m.selectedElement, 29)
        a.setRole(29, .fitOnly)
        XCTAssertEqual(m.elements.role(29), .fitOnly)
        a.hover(29); XCTAssertEqual(m.highlightedZ, 29)
        a.hover(nil); XCTAssertNil(m.highlightedZ)
    }

    /// Aluminium offers the K family with its alpha line checked by default; the table's mapped list is the quantified elements.
    /// Mutation: `families` empty or the alpha line unchecked, `mapped` listing fit-only elements - red.
    func testTheTableFamiliesAndTheMappedList() throws {
        let m = SpectroscopyRoomModel.fixture
        m.elements = ElementSelection(); m.elements.set(13, .quantify); m.elements.set(29, .quantify); m.elements.set(14, .fitOnly)
        let a = SpectroscopyPeriodicTable.actions(m)
        let k = try XCTUnwrap(a.families(13).first { $0.family == "K" })
        XCTAssertTrue(k.isSelected)
        XCTAssertEqual(try XCTUnwrap(k.lines.first { $0.id == "Al_Ka" }).isChecked, true)
        XCTAssertEqual(k.lines.filter(\.isChecked).map(\.id), ["Al_Ka"], "only the alpha line by default")
        XCTAssertEqual(a.mapped(), m.elements.quantified)
        XCTAssertEqual(a.mapped(), [13, 29])
        a.toggleLine(13, "Al_Kb")
        XCTAssertTrue(a.hasChosenLines(13)); XCTAssertTrue(m.elements.checkedLines(13).contains("Al_Kb"))
        a.resetLines(13)
        XCTAssertFalse(a.hasChosenLines(13))
    }

    // MARK: 8. The package

    private var appRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    /// The app builds on the released MacEMUI 0.3.0, in the package and in the Xcode project (the local-path interim ended at the tag).
    /// Mutation: the pin back to a local path in Package.swift, or the project's reference back to `../MacEMUI` - red.
    func testMacEMUIIsPinnedToTheReleasedTag() throws {
        let package = try String(contentsOf: appRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(".package(url: \"https://github.com/mac4DSTEM/MacEMUI\", exact: \"0.3.0\")"))
        XCTAssertFalse(package.contains(".package(path: \"../MacEMUI\")"))
        let project = try String(contentsOf: appRoot.appendingPathComponent("mac4DSTEM.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("XCRemoteSwiftPackageReference \"MacEMUI\""))
        XCTAssertFalse(project.contains("XCLocalSwiftPackageReference \"../MacEMUI\""))
    }

    // MARK: 9. Rule 11

    private func open(_ state: AppState) -> SpectroscopyRoomController {
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        return state.spectroscopyRoom
    }

    /// An opened image starts with the display filter on (3 x 3), the Select tool, the HAADF out of the mix; opening again resets them.
    /// Mutation: `bind` not setting `smoothing = .box3` (or not resetting the tool and the HAADF flag) - red.
    func testBindingSetsTheDefaultsOfTheRoom() {
        let state = AppState(); keep.append(state)
        var c = open(state)
        XCTAssertEqual(c.model.smoothing, .box3)
        XCTAssertEqual(c.model.regionTool, .pointer)
        XCTAssertFalse(c.model.mixHAADF)
        c.model.smoothing = .none; c.model.regionTool = .line; c.model.mixHAADF = true
        c = open(state)
        XCTAssertEqual(c.model.smoothing, .box3); XCTAssertEqual(c.model.regionTool, .pointer); XCTAssertFalse(c.model.mixHAADF)
    }

    /// A composition tile under the default filter draws the filtered picture and keeps the raw percent as its counts (the export and
    /// the readout are raw); a failed pixel does not spread into its neighbours.
    /// Mutation: `counts` set to the filtered percent, the picture built from the raw percent, or NaN passed to the kernel - red.
    func testTheFilterIsDisplayOnlyOnACompositionTile() {
        let percent: [Double] = [0, 0, 0, 0, 90, 0, 0, 0, 0]
        let summary = QuantMapsSummary(failedPixels: 0, maskedPixels: 0, validation: "none", absorptionNote: "no absorption correction")
        let raw = QuantMapsPass.tile(z: 13, percent: percent, width: 3, height: 3, summary: summary, mode: .atomic, smoothing: .none)
        let filtered = QuantMapsPass.tile(z: 13, percent: percent, width: 3, height: 3, summary: summary, mode: .atomic, smoothing: .box3)
        XCTAssertNotEqual(filtered.values, raw.values, "the picture is filtered")
        XCTAssertEqual(filtered.counts, percent); XCTAssertEqual(raw.counts, percent)
        let shown = QuantMapsPass.filtered(percent: percent, width: 3, height: 3, smoothing: .box3)
        XCTAssertEqual(shown[4], 10, accuracy: 1e-9, "90 spread over the 3 x 3 neighbourhood")
        let holed = QuantMapsPass.filtered(percent: [10, 10, 10, 10, .nan, 10, 10, 10, 10], width: 3, height: 3, smoothing: .box3)
        XCTAssertTrue(holed.allSatisfy(\.isFinite), "a failed pixel counts as 0, it does not poison the picture")
    }
}
