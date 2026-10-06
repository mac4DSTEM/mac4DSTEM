//
//  SpectroscopyRoomR5Tests.swift
//  Lane R5 (drive fixes): the room's two bands never scroll as a whole, the sidebar selects one row, the ColorMix mixes every
//  ticked element and says who is not ticked. Each test names the mutation it catches.
//

import XCTest
import SwiftUI
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SpectroscopyRoomPlanTests: XCTestCase {
    private let header = LayoutPolicy.paneHeaderHeight + 1

    /// The rooms from the drive: the full 1470 x 923 window's centre column, 1280 x 800 and 1000 x 800 windows' (a column is
    /// the window less the sidebar and inspector, so the narrow ones are literal and reduced).
    private let rooms: [CGSize] = [CGSize(width: 1100, height: 880), CGSize(width: 1470, height: 923), CGSize(width: 1280, height: 800),
                                   CGSize(width: 1000, height: 800), CGSize(width: 640, height: 760), CGSize(width: 560, height: 700), CGSize(width: 900, height: 450)]

    private func check(_ n: Int, _ aspect: CGFloat, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for room in rooms {
            let p = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: n, aspect: aspect)
            let tag = "\(what) in \(Int(room.width)) x \(Int(room.height))"
            XCTAssertGreaterThanOrEqual(p.bottomHeight, 220 - 0.01, "\(tag): the spectrum row keeps its minimum", file: file, line: line)
            XCTAssertEqual(p.mapsHeight + p.bottomHeight, room.height, accuracy: 0.01, "\(tag): the two bands are the room", file: file, line: line)
            if !p.scrolls {
                for r in [p.arrangement.colorMix] + p.arrangement.tiles {
                    XCTAssertLessThanOrEqual(r.maxY, p.gridAvail.height + 0.01, "\(tag): every tile inside the maps block", file: file, line: line)
                    XCTAssertLessThanOrEqual(r.maxX, p.gridAvail.width + 0.01, "\(tag): inside the width", file: file, line: line)
                }
            } else {
                XCTAssertGreaterThan(p.arrangement.size.height, p.gridAvail.height, "\(tag): scrolls only because it is taller than the block", file: file, line: line)
            }
        }
    }

    /// Square 1024 x 1024 with HAADF + four elements (the real Velox SI of drive shot 26) and with the proposals' seven more.
    /// Mutation: `mapsFraction` made 1 (the maps take the room) - red on the spectrum row's minimum.
    func testASquareScanKeepsTheSpectrumRowOnScreen() { check(5, 1, "square x5"); check(8, 1, "square x8") }

    /// The owner's Velox strip, 215 x 926, in both orientations of the question.
    /// Mutation: `minimumBottomHeight` made 0 - red.
    func testTheTallVeloxStripKeepsTheSpectrumRowOnScreen() { check(5, 215.0 / 926.0, "strip x5"); check(1, 215.0 / 926.0, "strip x1") }

    /// A square scan at 1470 x 923 side by side (the mock's behaviour) rather than scrolling: nothing scrolls and tiles stay at
    /// or above the floor.
    /// Mutation: `layout` ignoring the floor when choosing columns (`minimumSide: 0`) - red (a sliver arrangement is kept).
    func testTilesStayAtTheFloorBeforeAnythingScrolls() {
        let p = SpectroscopyRoomPlan.make(room: CGSize(width: 1470, height: 923), headerHeight: header, tileCount: 5, aspect: 1)
        XCTAssertFalse(p.scrolls)
        XCTAssertGreaterThanOrEqual(p.arrangement.tiles.map { max($0.width, $0.height) }.min() ?? 0, MapGridLayout.minimumTileSide)
        // 8 tiles in a 920-wide column: the best-scoring column count (5) leaves 144 pt tiles, the floor picks 4 instead.
        let q = SpectroscopyRoomPlan.make(room: CGSize(width: 920, height: 830), headerHeight: header, tileCount: 8, aspect: 1)
        XCTAssertGreaterThanOrEqual(q.arrangement.tiles.map { max($0.width, $0.height) }.min() ?? 0, MapGridLayout.minimumTileSide)
        XCTAssertFalse(q.scrolls)
    }

    /// When even the floor cannot fit, the block scrolls and the room does not: the plan's bands still add up.
    /// Mutation: `scrolls` always false - red.
    func testATooSmallBlockScrollsInsideItselfOnly() {
        let p = SpectroscopyRoomPlan.make(room: CGSize(width: 560, height: 700), headerHeight: header, tileCount: 8, aspect: 1)
        XCTAssertTrue(p.scrolls)
        XCTAssertGreaterThanOrEqual(p.bottomHeight, 220)
    }

    /// An arrangement is relative to its own top-left (the view centres it): the demo's ColorMix is no longer pushed right of
    /// its frame (drive shot 01: ~470 pt empty at its left).
    /// Mutation: the n == 0 ColorMix x set back to `(avail.width - w) / 2` - red.
    func testTheArrangementStartsAtItsOwnOrigin() {
        let alone = MapGridLayout.arrange(tileCount: 0, aspect: 1, in: CGSize(width: 900, height: 400))
        XCTAssertEqual(alone.colorMix.minX, 0)
        let many = MapGridLayout.arrange(tileCount: 5, aspect: 4.0 / 3.0, in: CGSize(width: 1000, height: 400))
        XCTAssertEqual(many.colorMix.minX, 0)
        XCTAssertLessThanOrEqual(many.size.width, 1000.01)
    }

    /// The quantification panel never takes more than half the row, so the spectrum keeps the other half.
    /// Mutation: the `room.width / 2` cap removed - red.
    func testTheQuantPanelLeavesHalfTheRowToTheSpectrum() {
        let p = SpectroscopyRoomPlan.make(room: CGSize(width: 500, height: 700), headerHeight: header, tileCount: 2, aspect: 1)
        XCTAssertLessThanOrEqual(p.quantWidth, 250.01)
    }
}

final class ColorMixCaptionTests: XCTestCase {
    /// There is no cap: four ticked elements are four names; an unticked one is named, not silently dropped.
    /// Mutation: `prefix(3)` on the names (a cap) or the `notMixed` clause dropped - red.
    func testCaptionNamesEveryTickedElementAndTheUntickedOnes() {
        XCTAssertEqual(ColorMixCaption.text(mixed: ["O", "Mg", "Al", "Si"], notMixed: []), "O · Mg · Al · Si")
        XCTAssertEqual(ColorMixCaption.text(mixed: ["O", "Al", "Si"], notMixed: ["Mg"]), "O · Al · Si (Mg not ticked)")
        XCTAssertEqual(ColorMixCaption.text(mixed: [], notMixed: ["Mg"]), "Mg not ticked")
        XCTAssertEqual(ColorMixCaption.text(mixed: [], notMixed: []), "")
    }

    /// The composite adds every ticked element, each in its own colour (four here), and clamps; a fourth element is not ignored.
    /// Mutation: the composite loop stopping after three tiles - red.
    func testFourTickedElementsAreAllMixed() {
        func t(_ z: Int) -> MapTile { MapTile(z: z, width: 1, height: 1, values: [0.2]) }
        let tiles = [t(8), t(12), t(13), t(14)]
        let colors: [Int: ColorMixComposite.RGB] = [8: (1, 0, 0), 12: (0, 1, 0), 13: (0, 0, 1), 14: (1, 1, 1)]
        let four = ColorMixComposite.rgb(at: 0, tiles: tiles, mixed: [8, 12, 13, 14], colors: colors)
        let three = ColorMixComposite.rgb(at: 0, tiles: tiles, mixed: [8, 12, 13], colors: colors)
        XCTAssertEqual(four.r, 0.4, accuracy: 1e-6); XCTAssertEqual(three.r, 0.2, accuracy: 1e-6)
        XCTAssertEqual(four.g, 0.4, accuracy: 1e-6); XCTAssertEqual(four.b, 0.4, accuracy: 1e-6)
    }

    /// One map's colour or display changes only that map (the model behind the chip's popover and the inspector section).
    /// Mutation: `displayBinding`'s setter writing every map's key - red.
    @MainActor func testOneMapsDisplayAndColourAreItsOwn() {
        let m = SpectroscopyRoomModel.fixture
        m.displayBinding(.element(12)).wrappedValue = MapDisplay(lo: 0.2, hi: 1, gamma: 2)
        XCTAssertEqual(m.display(.element(12)).gamma, 2)
        XCTAssertTrue(m.display(.element(13)).isIdentity); XCTAssertTrue(m.display(.haadf).isIdentity)
        m.displayBinding(.element(12)).wrappedValue = MapDisplay()
        XCTAssertNil(m.mapDisplays[.element(12)], "the identity is stored as absent")
        m.colorBinding(13).wrappedValue = .purple
        XCTAssertEqual(m.color(12), ElementPalette.color(12))
        XCTAssertNotEqual(m.color(13), ElementPalette.color(13))
        XCTAssertEqual(m.mapTitle(.element(12)), "Mg"); XCTAssertEqual(m.mapTitle(.haadf), "HAADF")
    }
}

@MainActor
final class SpectroscopySidebarSelectionTests: XCTestCase {
    /// Every row the sidebar lists in the room (the Workspace rows, the room's own section; the room list never lists other
    /// rooms' task sections) - exactly one carries the selected tag.
    /// Mutation: the binding's getter returning `.workspace(.spectroscopy)` for the room (a second row would match elsewhere)
    /// or `.workspace(.prepare)` - red.
    func testExactlyOneListedRowIsSelectedInTheRoom() {
        let state = AppState()
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())   // a spectrum-only window, the drive's case
        let listed: [WorkspaceRoute] = WorkspaceArea.allCases.map { .workspace($0) } + SpectroscopyTool.allCases.map { .spectroscopyTool($0) }
        let selected = state.workspaceRoute.wrappedValue
        XCTAssertEqual(listed.filter { $0 == selected }.count, 1)
        XCTAssertEqual(selected, .spectroscopyTool(.edx))
        XCTAssertNotEqual(selected, .workspace(.prepare))
    }

    /// The list is rebuilt exactly when its selection could go stale: entering/leaving the room, a window turning spectrum-only.
    /// Mutation: the identity ignoring `spectrumOnly` or `area` - red.
    func testTheListIsRebuiltWhenTheRoomOrTheWindowKindChanges() {
        let id = WorkspaceRoute.sidebarListIdentity
        XCTAssertNotEqual(id(.prepare, true), id(.spectroscopy, true), "entering the room")
        XCTAssertNotEqual(id(.prepare, false), id(.prepare, true), "the window turning spectrum-only")
        XCTAssertEqual(id(.prepare, false), id(.image, false), "moving between 4D rooms keeps the list (and its keyboard focus)")
    }
}
