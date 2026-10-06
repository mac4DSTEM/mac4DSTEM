//
//  SpectroscopySpec2ATests.swift
//  Spectroscopy spec 2, lane A (layout): the two dividers (D-7) and the spectrum alone in the bottom band (D-4). Pure geometry;
//  each test names the mutation it catches.
//

import XCTest
import SwiftUI
@testable import mac4DSTEM

final class SpectroscopySpec2ATests: XCTestCase {
    private let header = LayoutPolicy.paneHeaderHeight + 1
    private let room = CGSize(width: 1100, height: 800)

    // MARK: the horizontal divider

    /// The fraction is the start plus the cumulative translation over the room's height (a drag is reversible).
    /// Mutation: `start + translation / available` made `translation / available` (not cumulative) or `start - ...` - red.
    func testFractionIsCumulativeFromTheDragStart() {
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: 80, available: 800, from: 0.5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: -80, available: 800, from: 0.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: 0, available: 800, from: 0.58), 0.58, accuracy: 1e-9)
    }

    /// Clamped to 0...1; with a bottom floor the top of the range leaves the floor to the spectrum's header.
    /// Mutation: the lower clamp `max(.., 0)` or the upper `min(.., top)` removed - red.
    func testFractionClamps() {
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: -5000, available: 800, from: 0.5), 0)
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: 5000, available: 800, from: 0.5), 1)
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: 5000, available: 800, from: 0.5, bottomFloor: 27), 1 - 27.0 / 800, accuracy: 1e-9)
        XCTAssertEqual(SpectroscopyRoomPlan.fraction(afterDrag: 10, available: 0, from: 0.5), 0.5, "no room: unchanged, no division by zero")
    }

    /// 0 = maps hidden, the spectrum the whole height; the bands are the room.
    /// Mutation: the given fraction's lower clamp raised (`max(f, 0)` -> `max(f, 0.3)`) - red.
    func testZeroHidesTheMaps() {
        let p = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 0)
        XCTAssertEqual(p.mapsHeight, 0)
        XCTAssertEqual(p.bottomHeight, room.height)
        XCTAssertEqual(p.gridAvail.height, 0)
    }

    /// 1 = the spectrum is its header row (+ rule) only, so it can be dragged back.
    /// Mutation: the `headerHeight` floor set to 0 - red (the spectrum disappears entirely).
    func testOneLeavesTheSpectrumItsHeaderRow() {
        let p = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 1)
        XCTAssertEqual(p.bottomHeight, header, accuracy: 1e-9)
        XCTAssertEqual(p.mapsHeight + p.bottomHeight, room.height, accuracy: 1e-9)
    }

    /// A value between is the person's, with no 220-pt floor; nil is the default split with its floor.
    /// Mutation: the given branch made to use `minimumBottomHeight` (floor 220 on 0.9) or the nil branch to ignore it - red.
    func testAGivenFractionIsHonouredAndNilIsTheDefault() {
        let given = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 0.9)
        XCTAssertEqual(given.mapsHeight, 0.9 * room.height, accuracy: 1e-9)
        XCTAssertEqual(given.bottomHeight, 0.1 * room.height, accuracy: 1e-9)
        let dflt = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1)
        XCTAssertEqual(dflt.bottomHeight, max(room.height * (1 - SpectroscopyRoomPlan.mapsFraction), SpectroscopyRoomPlan.minimumBottomHeight), accuracy: 1e-9)
        let short = SpectroscopyRoomPlan.make(room: CGSize(width: 1100, height: 300), headerHeight: header, tileCount: 5, aspect: 1)
        XCTAssertGreaterThanOrEqual(short.bottomHeight, SpectroscopyRoomPlan.minimumBottomHeight, "the default keeps its floor")
    }

    /// The maps block is the grid alone: its available height is the block less the padding, no header row.
    /// Mutation: `headerHeight` subtracted from the grid's height again (the old MapsHeader) - red.
    func testTheMapsBlockIsTheGridAlone() {
        let p = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 0.5)
        XCTAssertEqual(p.gridAvail.height, p.mapsHeight - 2 * SpectroscopyRoomPlan.gridPadding, accuracy: 1e-9)
        XCTAssertEqual(p.gridAvail.width, room.width - 2 * SpectroscopyRoomPlan.gridPadding, accuracy: 1e-9)
    }

    // MARK: the vertical divider

    private let avail = CGSize(width: 1000, height: 600)

    /// nil is today's rule: the ColorMix as large as the block allows (here height-limited: 600 x 600).
    /// Mutation: the nil path changed (the override applied with a default fraction) - red.
    func testNilMixFractionIsTheRuleUnchanged() {
        let p = MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail)
        XCTAssertEqual(p.colorMix.width, 600, accuracy: 0.01)
        XCTAssertEqual(MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail, mixFraction: nil), p)
    }

    /// A given fraction sets the ColorMix's width (at the data's aspect).
    /// Mutation: the override ignored - red.
    func testAGivenMixFractionSetsTheColorMixWidth() {
        let p = MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail, mixFraction: 0.4)
        XCTAssertEqual(p.colorMix.width, 400, accuracy: 0.01)
        XCTAssertEqual(p.colorMix.height, 400, accuracy: 0.01)
        XCTAssertEqual(p.kind, .sideBySide)
        XCTAssertEqual(p.tileArea.minX, 400 + MapGridLayout.gap, accuracy: 0.01)
    }

    /// The ColorMix keeps at least 20 % of the width.
    /// Mutation: the `minimumMixFraction` lower bound removed - red.
    func testTheColorMixKeepsTwentyPercent() {
        let p = MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail, mixFraction: 0.01)
        XCTAssertEqual(p.colorMix.width, 0.2 * avail.width, accuracy: 0.01)
    }

    /// A tile column of at least `minimumTileSide` stays beside the ColorMix, and the ColorMix at its aspect stays inside the block.
    /// Mutation: the tile-column term of `upper` removed (width 700 -> ColorMix 693, no tile column) or the fit term removed
    /// (a tall ColorMix) - red.
    func testTheTileColumnAndTheBlockHeightLimitTheColorMix() {
        let wide = CGSize(width: 700, height: 1000)          // width-limited
        let p = MapGridLayout.plan(tileCount: 5, aspect: 1, in: wide, mixFraction: 0.99)
        XCTAssertGreaterThanOrEqual(p.tileArea.width, MapGridLayout.minimumTileSide - 0.01)
        XCTAssertLessThanOrEqual(p.colorMix.maxX + MapGridLayout.gap + MapGridLayout.minimumTileSide, wide.width + 0.01)
        let q = MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail, mixFraction: 0.9)   // height-limited: 600 high at most
        XCTAssertLessThanOrEqual(q.colorMix.height, avail.height + 0.01)
        XCTAssertGreaterThanOrEqual(q.tileArea.width, MapGridLayout.minimumTileSide - 0.01)
    }

    /// A narrow block is the stacked kind whatever the fraction: no divider to follow.
    /// Mutation: the stacked decision skipped when a fraction is given (`if mixFraction == nil, mw < avail.width / 2`) - red.
    func testTheStackedKindIgnoresTheFraction() {
        let narrow = CGSize(width: 180, height: 800)
        for f: CGFloat in [0.2, 0.5, 0.9] {
            let p = MapGridLayout.plan(tileCount: 4, aspect: 1, in: narrow, mixFraction: f)
            XCTAssertEqual(p, MapGridLayout.plan(tileCount: 4, aspect: 1, in: narrow), "fraction \(f)")
            XCTAssertEqual(p.kind, .stacked)
        }
    }

    /// The room plan hands the mix fraction on.
    /// Mutation: `make` drops `mixFraction` - red.
    func testTheRoomPlanPassesTheMixFractionOn() {
        let a = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mixFraction: 0.3)
        XCTAssertEqual(a.maps.colorMix.width, 0.3 * a.gridAvail.width, accuracy: 0.01)
    }

    /// The drag: cumulative from the start, kept in 0.2...1.
    /// Mutation: not cumulative, or the clamp removed - red.
    func testMixFractionAfterDrag() {
        XCTAssertEqual(MapGridLayout.mixFraction(afterDrag: 100, available: 1000, from: 0.5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(MapGridLayout.mixFraction(afterDrag: -100, available: 1000, from: 0.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(MapGridLayout.mixFraction(afterDrag: -5000, available: 1000, from: 0.5), MapGridLayout.minimumMixFraction)
        XCTAssertEqual(MapGridLayout.mixFraction(afterDrag: 5000, available: 1000, from: 0.5), 1)
    }
}
