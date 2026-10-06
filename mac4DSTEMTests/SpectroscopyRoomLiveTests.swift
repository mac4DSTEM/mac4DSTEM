//
//  SpectroscopyRoomLiveTests.swift
//  v5.0 R4 (ADR 056): the rebuilt Spectroscopy room — the maps grid's arrangement for real aspect ratios, the live region
//  (hit, move, resize, polygon, coalesced sums, Pin), the active map and per-map colour and contrast, Auto ID on open, and the
//  map modes. Every test names the mutation it catches; each was broken once and seen red (docs in the lane report).
//

import XCTest
import SwiftUI
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

// MARK: - Pure geometry

final class SpectroscopyRoomGeometryTests: XCTestCase {
    /// R6 REPLACED the R4/R5 tests of `MapGridLayout.arrange` / `stacked` / `layout` (testTheDemoAspectGivesTheMocksBlock,
    /// testTheVeloxStripKeepsItsAspectAndFits, testNoTilesLeavesTheColorMixAlone, testTheStackedArrangementCapsATallColorMix,
    /// testTilesNeverShrinkBelowTheFloorBeforeStacking): those asserted the area-score arrangement and the 150-pt floor, which
    /// let the ColorMix shrink to tile size (drive 2, shot r5-01). Their successors below assert the dominant ColorMix.
    private func assertValid(_ p: MapGridLayout.Plan, aspect: CGFloat, in avail: CGSize, count: Int, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.tiles.count, count, what, file: file, line: line)
        XCTAssertEqual(p.colorMix.width / p.colorMix.height, aspect, accuracy: 1e-3, "\(what): the ColorMix keeps the data's aspect", file: file, line: line)
        for r in p.tiles { XCTAssertEqual(r.width / r.height, aspect, accuracy: 1e-3, "\(what): a tile keeps the data's aspect", file: file, line: line) }
        let box = CGRect(origin: .zero, size: avail)
        XCTAssertTrue(box.insetBy(dx: -0.01, dy: -0.01).contains(p.colorMix), "\(what): the ColorMix is inside the block", file: file, line: line)
        XCTAssertTrue(box.insetBy(dx: -0.01, dy: -0.01).contains(p.tileArea), "\(what): the tile container is inside the block", file: file, line: line)
        XCTAssertFalse(p.colorMix.intersects(p.tileArea.insetBy(dx: 0.5, dy: 0.5)), "\(what): the ColorMix is never inside the tile grid", file: file, line: line)
        for (i, r) in p.tiles.enumerated() {
            XCTAssertGreaterThanOrEqual(r.minX, -0.01, what, file: file, line: line); XCTAssertGreaterThanOrEqual(r.minY, -0.01, what, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxX, p.tileContent.width + 0.01, "\(what): tile \(i) inside its content", file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxY, p.tileContent.height + 0.01, "\(what): tile \(i) inside its content", file: file, line: line)
            // No tile clipped: along the axis that does not scroll it is inside the container; along the scrolling one it is reached by scrolling.
            if p.scroll != .vertical { XCTAssertLessThanOrEqual(r.maxY, p.tileArea.height + 0.01, "\(what): tile \(i) not clipped vertically", file: file, line: line) }
            if p.scroll != .horizontal { XCTAssertLessThanOrEqual(r.maxX, p.tileArea.width + 0.01, "\(what): tile \(i) not clipped horizontally", file: file, line: line) }
            if p.scroll == .none { XCTAssertLessThanOrEqual(p.tileContent.height, p.tileArea.height + 0.01, what, file: file, line: line) }
            XCTAssertGreaterThanOrEqual(max(r.width, r.height), MapGridLayout.minimumTileSide - 0.01, "\(what): tile \(i) at or above the floor", file: file, line: line)
        }
        for i in 0..<p.tiles.count { for j in (i + 1)..<max(p.tiles.count, i + 1) where p.tiles[i].intersects(p.tiles[j].insetBy(dx: 0.5, dy: 0.5)) {
            XCTFail("\(what): tiles \(i) and \(j) overlap", file: file, line: line)
        } }
        if let t = p.tiles.first { XCTAssertGreaterThanOrEqual(p.colorMix.width * p.colorMix.height, 2.5 * t.width * t.height - 0.5, "\(what): the ColorMix is the dominant map", file: file, line: line) }
    }

    /// The GMS demo (64 x 48) in the mock's 1470-wide window: the ColorMix beside a 2-column, 3-row block of tiles, as drawn,
    /// the ColorMix the full height.
    /// Mutation: the aspect ignored (tiles squared) or the column search dropped (one column) - red.
    func testTheDemoAspectGivesTheMocksBlock() {
        let avail = CGSize(width: 1000, height: 400)
        let p = MapGridLayout.plan(tileCount: 6, aspect: 64.0 / 48.0, in: avail)
        assertValid(p, aspect: 64.0 / 48.0, in: avail, count: 6, "demo")
        let columns = Set(p.tiles.map { $0.minX.rounded() }).count, rows = Set(p.tiles.map { $0.minY.rounded() }).count
        XCTAssertEqual([columns, rows], [2, 3], "two columns of three rows, like the mock")
        XCTAssertEqual(p.colorMix.height, avail.height, accuracy: 0.5, "the ColorMix takes the full height")
        XCTAssertEqual(p.kind, .sideBySide); XCTAssertEqual(p.scroll, .none)
    }

    /// The drive's cases (R6): a square 1024^2 scan with 5, 9 and 12 tiles and the 215 x 926 strip with 5, in the maps blocks
    /// of a 1470 x 923 window's column, 1280 x 800 and 1000 x 800 (the plan's own `gridAvail`): the ColorMix is the dominant,
    /// leading map, never inside the tile grid, and no tile is clipped. Mutation: `dominance` 2.5 -> 0.5 or the tile cap
    /// removed (`min(byWidth, byHeight, cap)` -> without cap) - red for one or two tiles (a tile as big as the ColorMix).
    func testTheColorMixDominatesInTheDrivesRooms() {
        let header = LayoutPolicy.paneHeaderHeight + 1
        let rooms = [CGSize(width: 1100, height: 923), CGSize(width: 1470 - 460, height: 923), CGSize(width: 1280 - 380, height: 800), CGSize(width: 1000 - 380, height: 800), CGSize(width: 1000, height: 800)]
        for room in rooms {
            for (n, aspect) in [(1, CGFloat(1)), (2, 1), (5, 1), (9, 1), (12, 1), (5, 215.0 / 926.0)] {
                let plan = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: n, aspect: aspect)
                let tag = "\(n) tiles aspect \(aspect) in \(Int(room.width)) x \(Int(room.height))"
                assertValid(plan.maps, aspect: aspect, in: plan.gridAvail, count: n, tag)
                XCTAssertEqual(plan.maps.kind, .sideBySide, "\(tag): side by side while a tile column fits beside the ColorMix")
                XCTAssertEqual(plan.maps.colorMix.minX, 0, "\(tag): the ColorMix is the leading map")
                XCTAssertLessThanOrEqual(plan.maps.colorMix.maxX, plan.maps.tileArea.minX + 0.01)
            }
        }
    }

    /// Too many tiles for the block at the floor: the tile grid scrolls vertically inside its own area, the ColorMix keeps its
    /// size (drive shot r5-01: it was shrunk to tile size).
    /// Mutation: the scroll branch's fallback (`best == nil`) given the ColorMix a smaller size, or `scroll` always .none - red.
    func testTooManyTilesScrollTheTileGridNotTheColorMix() {
        let avail = CGSize(width: 640, height: 300)
        let few = MapGridLayout.plan(tileCount: 2, aspect: 1, in: avail)
        let many = MapGridLayout.plan(tileCount: 30, aspect: 1, in: avail)
        XCTAssertEqual(many.scroll, .vertical)
        XCTAssertGreaterThan(many.tileContent.height, many.tileArea.height)
        XCTAssertEqual(many.colorMix, few.colorMix, "the ColorMix does not shrink for the tiles")
        assertValid(many, aspect: 1, in: avail, count: 30, "30 tiles")
    }

    /// A genuinely narrow block (no tile column beside a ColorMix of half the width): the ColorMix on top, the tiles in a
    /// horizontally scrolling row beneath it, never clipped by the block's bottom.
    /// Mutation: the narrow test `mw < avail.width / 2` made false - red (it stays side by side).
    func testANarrowBlockStacksWithAHorizontalTileRow() {
        let avail = CGSize(width: 190, height: 420)
        let p = MapGridLayout.plan(tileCount: 5, aspect: 1, in: avail)
        XCTAssertEqual(p.kind, .stacked)
        XCTAssertLessThanOrEqual(p.colorMix.maxY, p.tileArea.minY)
        XCTAssertEqual(p.scroll, .horizontal)
        XCTAssertLessThanOrEqual(p.tileArea.maxY, avail.height + 0.01)
        XCTAssertGreaterThanOrEqual(p.colorMix.width * p.colorMix.height, 2.5 * p.tiles[0].width * p.tiles[0].height)
        XCTAssertGreaterThan(p.colorMix.width, p.tiles[0].width * 1.5)
    }

    func testNoTilesLeavesTheColorMixAlone() {
        let p = MapGridLayout.plan(tileCount: 0, aspect: 1, in: CGSize(width: 300, height: 200))
        XCTAssertEqual(p.colorMix.height, 200, accuracy: 0.5); XCTAssertTrue(p.tiles.isEmpty); XCTAssertEqual(p.tileArea, .zero)
    }

    /// Pins are a layer, on by default, drawn faint.
    /// Mutation: `pins = true` made false - red.
    func testPinsAreOnByDefaultAndDrawnFaint() {
        XCTAssertTrue(SpectrumLayers().pins)
        XCTAssertEqual(SpectrumLayers.pinOpacity, 0.6, accuracy: 1e-9)
    }

    // MARK: the live region

    private let grid = (w: 64, h: 48)

    /// A press on a corner or edge handle resizes, inside moves, outside draws; a corner beats an edge midpoint at a tie.
    /// Mutation: `hit` testing `.inside` before the handles — red (a handle press would move the region).
    func testHitTestFindsHandlesInsideAndOutside() {
        let s = SpectrumRegionShape.rectangle(PixelRect(x0: 10, y0: 10, x1: 30, y1: 20))
        XCTAssertEqual(RegionEditing.hit(s, at: PixelPoint(x: 10.2, y: 9.8), tolerance: 1), .handle(.topLeft))
        XCTAssertEqual(RegionEditing.hit(s, at: PixelPoint(x: 30, y: 15), tolerance: 1), .handle(.right))
        XCTAssertEqual(RegionEditing.hit(s, at: PixelPoint(x: 20, y: 10), tolerance: 1), .handle(.top))
        XCTAssertEqual(RegionEditing.hit(s, at: PixelPoint(x: 20, y: 15), tolerance: 1), .inside)
        XCTAssertEqual(RegionEditing.hit(s, at: PixelPoint(x: 40, y: 40), tolerance: 1), .outside)
        let poly = SpectrumRegionShape.polygon([PixelPoint(x: 5, y: 5), PixelPoint(x: 25, y: 5), PixelPoint(x: 15, y: 25)])
        XCTAssertEqual(RegionEditing.hit(poly, at: PixelPoint(x: 25.4, y: 4.7), tolerance: 1), .handle(.vertex(1)))
        XCTAssertEqual(RegionEditing.hit(poly, at: PixelPoint(x: 15, y: 10), tolerance: 1), .inside)
        XCTAssertEqual(RegionEditing.hit(poly, at: PixelPoint(x: 5, y: 20), tolerance: 1), .outside)
    }

    /// A move keeps the size and stops at the grid's edge; a resize rounds to pixel borders, flips past the opposite edge and
    /// never leaves less than a pixel.
    /// Mutation: the move's clamp removed (the region slides off the grid), or the flip's `min/max` normalisation dropped — red.
    func testMoveAndResizeStayOnTheGridAndKeepAPixel() {
        let r = PixelRect(x0: 10, y0: 10, x1: 30, y1: 20)
        XCTAssertEqual(RegionEditing.moved(.rectangle(r), dx: 5, dy: -3, grid: grid), .rectangle(PixelRect(x0: 15, y0: 7, x1: 35, y1: 17)))
        XCTAssertEqual(RegionEditing.moved(.rectangle(r), dx: 500, dy: -500, grid: grid), .rectangle(PixelRect(x0: 44, y0: 0, x1: 64, y1: 10)))
        XCTAssertEqual(RegionEditing.resized(r, handle: .right, to: PixelPoint(x: 40.4, y: 99), grid: grid), PixelRect(x0: 10, y0: 10, x1: 40, y1: 20))
        XCTAssertEqual(RegionEditing.resized(r, handle: .bottomRight, to: PixelPoint(x: 5, y: 5), grid: grid), PixelRect(x0: 5, y0: 5, x1: 10, y1: 10), "dragged past the opposite corner: flipped")
        XCTAssertEqual(RegionEditing.resized(r, handle: .left, to: PixelPoint(x: 30, y: 0), grid: grid).width, 1, "never less than a pixel")
        XCTAssertEqual(RegionEditing.resized(r, handle: .top, to: PixelPoint(x: 0, y: -50), grid: grid).y0, 0, "clamped to the grid")
        let tri = SpectrumRegionShape.polygon([PixelPoint(x: 5, y: 5), PixelPoint(x: 25, y: 5), PixelPoint(x: 15, y: 25)])
        guard case .polygon(let moved) = RegionEditing.moved(tri, dx: 100, dy: 0, grid: grid) else { return XCTFail("a polygon stays a polygon") }
        XCTAssertEqual(moved.map(\.x).max() ?? 0, 64, accuracy: 1e-9, "stops at the right edge, same size")
        XCTAssertEqual((moved.map(\.x).max() ?? 0) - (moved.map(\.x).min() ?? 0), 20, accuracy: 1e-9)
    }

    func testADragSpansTheStartAndEndPixelsAndIsNilOffTheGrid() {
        XCTAssertNil(RegionEditing.drawnRect(from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 2, y: 2), grid: (0, 0)))
    }

    // MARK: polygon masks (Core)

    /// A polygon takes the pixels whose centre it holds (even-odd): the rectangle as a polygon is the rectangle, a triangle
    /// holds the right count, fewer than three corners hold none, and a figure-eight's lobes each count.
    /// Mutation: the half-open `< xsCross[k + 1]` made `<=` (a shared edge counted twice) or the centre offset dropped — red.
    func testPolygonMasksFollowPixelCentres() {
        let (nx, ny) = (10, 8)
        let rect = SpectrumRegionShape.rectangle(PixelRect(x0: 2, y0: 1, x1: 7, y1: 5)).mask(nx: nx, ny: ny)
        let asPoly = SpectrumRegionShape.polygon([PixelPoint(x: 2, y: 1), PixelPoint(x: 7, y: 1), PixelPoint(x: 7, y: 5), PixelPoint(x: 2, y: 5)]).mask(nx: nx, ny: ny)
        XCTAssertEqual(asPoly, rect)
        // The left edge at x = 2.4 falls between pixel 2's corner (2.0) and its centre (2.5): the centre rule decides, so
        // pixel 2 is IN (2.5 >= 2.4). Tested against the corner (2.0 >= 2.4) it flips OUT: 4 rows x 5 columns = 20 become 16.
        let offGrid = SpectrumRegionShape.polygon([PixelPoint(x: 2.4, y: 1), PixelPoint(x: 7, y: 1), PixelPoint(x: 7, y: 5), PixelPoint(x: 2.4, y: 5)]).mask(nx: nx, ny: ny)
        XCTAssertEqual(offGrid.filter { $0 }.count, 20)
        XCTAssertTrue(offGrid[1 * nx + 2] && offGrid[4 * nx + 2], "pixel 2's centre (2.5) is right of the edge at 2.4")
        let tri = SpectrumRegionShape.polygon([PixelPoint(x: 0, y: 0), PixelPoint(x: 8, y: 0), PixelPoint(x: 0, y: 8)]).mask(nx: nx, ny: ny)
        // centres (i + .5, j + .5) with i + j + 1 < 8, i.e. i + j <= 6: 7 + 6 + 5 + 4 + 3 + 2 + 1
        XCTAssertEqual(tri.filter { $0 }.count, 28)
        XCTAssertEqual(SpectrumRegionShape.polygon([PixelPoint(x: 1, y: 1), PixelPoint(x: 5, y: 5)]).mask(nx: nx, ny: ny).filter { $0 }.count, 0)
        let bowtie = SpectrumRegionShape.polygon([PixelPoint(x: 0, y: 0), PixelPoint(x: 6, y: 6), PixelPoint(x: 6, y: 0), PixelPoint(x: 0, y: 6)]).mask(nx: nx, ny: ny)
        XCTAssertTrue(bowtie[3 * nx + 0] && bowtie[3 * nx + 4], "both lobes at the waist's row")
        XCTAssertFalse(bowtie[3 * nx + 2], "the waist pixel between the crossing edges is outside (even-odd)")
        XCTAssertFalse(bowtie[0 * nx + 3], "the top middle is outside")
        // off the grid: clamped, never a trap
        XCTAssertEqual(SpectrumRegionShape.polygon([PixelPoint(x: -5, y: -5), PixelPoint(x: 50, y: -5), PixelPoint(x: 50, y: 50), PixelPoint(x: -5, y: 50)]).mask(nx: nx, ny: ny).filter { $0 }.count, nx * ny)
    }

    // MARK: spectrum range

    /// The strip opens on the listed lines: Mg Kα to Cu Kα gives about 0.85 to 8.7 keV, not the axis's 80.
    /// Mutation: the markers' kinds not filtered (a suspect's energy widens it) or the padding dropped — red.
    func testTheStripOpensOnTheListedLines() {
        let m = [LineMarker(label: "Mg Kα", energy: 1.254, elementZ: 12), LineMarker(label: "Cu Kα", energy: 8.04, elementZ: 29),
                 LineMarker(label: "Ar Kα?", energy: 40, elementZ: nil, kind: .suspect)]
        let r = SpectrumAutoZoom.range(markers: m, domain: 0...80, minimumSpan: 0.04)
        XCTAssertEqual(r.lowerBound, 0.854, accuracy: 1e-9); XCTAssertEqual(r.upperBound, 8.844, accuracy: 1e-9)
        XCTAssertEqual(SpectrumAutoZoom.range(markers: [], domain: 0...80, minimumSpan: 0.04), 0...20, "no lines: the first 20 keV")
        let one = SpectrumAutoZoom.range(markers: [LineMarker(label: "Al Kα", energy: 1.487, elementZ: 13)], domain: 0...20, minimumSpan: 0.04)
        XCTAssertGreaterThanOrEqual(one.upperBound - one.lowerBound, 1, "one line: still a readable span")
    }
}

// MARK: - The room: active map, colour and contrast

@MainActor
final class SpectroscopyRoomMapsTests: XCTestCase {
    /// Exactly one map is active, and ticking a tile (in the ColorMix) is a different thing: it never moves the outline.
    /// Mutation: `toggleMix` setting `active` — red.
    func testTheTickIsNotTheActiveMap() {
        let m = SpectroscopyRoomModel.fixture
        XCTAssertEqual(m.active, .colorMix)
        m.active = .element(12)
        let before = m.mixed
        m.toggleMix(13); m.toggleMix(14)
        XCTAssertNotEqual(m.mixed, before, "the ticks changed")
        XCTAssertEqual(m.active, .element(12), "and the outline did not move")
        m.active = .haadf
        XCTAssertEqual(m.active, .haadf, "one value: setting it replaces the old one")
    }

    private func tiles() -> [MapTile] {
        [MapTile(z: 12, width: 4, height: 1, values: [1, 0.5, 0.25, 0]), MapTile(z: 13, width: 4, height: 1, values: [0, 0.5, 1, 1])]
    }
    private func bytes(_ img: CGImage?) throws -> [UInt8] { Array(try XCTUnwrap(img?.dataProvider?.data as Data?)) }

    /// A map's contrast window and gamma change ONLY that map's tile and its share of the ColorMix; another map's tile is
    /// byte-identical, and the other element's contribution to the mix is untouched.
    /// Mutation: `displays` read by the wrong key in the composite (both maps take Mg's window) — red.
    func testChangingOneMapsContrastChangesOnlyThatMapAndTheMix() throws {
        let t = tiles()
        let red: ColorMixComposite.RGB = (1, 0, 0), blue: ColorMixComposite.RGB = (0, 0, 1)
        let identity = MapDisplay()
        let windowed = MapDisplay(lo: 0.4, hi: 1, gamma: 1)
        let mixBefore = try bytes(ColorMixRaster.image(tiles: t, mixed: [12, 13], colors: [12: red, 13: blue], backdrop: [], width: 4, height: 1))
        let mixAfter = try bytes(ColorMixRaster.image(tiles: t, mixed: [12, 13], colors: [12: red, 13: blue], backdrop: [], width: 4, height: 1, displays: [12: windowed]))
        XCTAssertNotEqual(mixBefore, mixAfter, "the mix follows the changed map")
        // the blue channel (13's contribution) is untouched; only the red channel (12's) moved
        for px in 0..<4 { XCTAssertEqual(mixBefore[px * 4 + 2], mixAfter[px * 4 + 2], "pixel \(px): Al's channel is the same") }
        XCTAssertNotEqual((0..<4).map { mixBefore[$0 * 4] }, (0..<4).map { mixAfter[$0 * 4] })
        // the tiles: Al's bitmap does not depend on Mg's display
        let alBefore = try bytes(ElementTileRaster.image(tile: t[1], color: blue, display: identity))
        let alAfter = try bytes(ElementTileRaster.image(tile: t[1], color: blue, display: identity))
        XCTAssertEqual(alBefore, alAfter)
        let mgBefore = try bytes(ElementTileRaster.image(tile: t[0], color: red, display: identity))
        let mgAfter = try bytes(ElementTileRaster.image(tile: t[0], color: red, display: windowed))
        XCTAssertNotEqual(mgBefore, mgAfter)
        // a different colour changes the tile and the mix's share, and the cache key sees it
        let green: ColorMixComposite.RGB = (0, 1, 0)
        XCTAssertNotEqual(try bytes(ElementTileRaster.image(tile: t[0], color: green, display: identity)), mgBefore)
        XCTAssertNotEqual(MapStyle.stamp(color: red, display: identity), MapStyle.stamp(color: green, display: identity))
        XCTAssertNotEqual(MapStyle.stamp(color: red, display: identity), MapStyle.stamp(color: red, display: windowed))
        // model level: per-element state, absent = identity, identity stored as absent
        let model = SpectroscopyRoomModel.fixture
        model.mapDisplays[.element(12)] = windowed
        XCTAssertEqual(model.display(.element(12)), windowed)
        XCTAssertEqual(model.display(.element(13)), model.defaultDisplay(.element(13)), "another map stays at its own default window (R8)")
        model.elementColors[12] = .purple
        XCTAssertNotEqual(model.color(12), ElementPalette.color(12)); XCTAssertEqual(model.color(13), ElementPalette.color(13))
    }

    /// The window and gamma arithmetic: the window clips and stretches, gamma is the colour bar's `pow(f, 1 / gamma)`.
    /// Mutation: gamma applied as `pow(f, gamma)` — red.
    func testMapDisplayArithmetic() {
        let d = MapDisplay(lo: 0.2, hi: 0.6, gamma: 2)
        XCTAssertEqual(d.apply(0.1), 0); XCTAssertEqual(d.apply(0.9), 1)
        XCTAssertEqual(d.apply(0.4), Float(pow(0.5, 0.5)), accuracy: 1e-6)
        XCTAssertEqual(MapDisplay().apply(0.37), 0.37)
        XCTAssertTrue(MapDisplay().isIdentity)
    }

    /// HAADF goes through its colormap: gray is the identity, another colormap is not.
    /// Mutation: the LUT index taken before the display window — red when a window is set.
    func testHAADFUsesItsColormapAndWindow() throws {
        let v: [Float] = [0, 0.5, 1, 0.25]
        let gray = try bytes(ElementTileRaster.haadf(values: v, width: 4, height: 1, colormap: .gray, display: MapDisplay()))
        XCTAssertEqual(gray[0], 0); XCTAssertEqual(gray[8], 255); XCTAssertEqual(gray[4], gray[5]); XCTAssertEqual(gray[4], gray[6])
        let vir = try bytes(ElementTileRaster.haadf(values: v, width: 4, height: 1, colormap: .viridis, display: MapDisplay()))
        XCTAssertNotEqual(gray, vir)
        let win = try bytes(ElementTileRaster.haadf(values: v, width: 4, height: 1, colormap: .gray, display: MapDisplay(lo: 0.5, hi: 1, gamma: 1)))
        XCTAssertEqual(win[4], 0, "0.5 is the window's floor")
    }

    /// The ColorMix leaves a proposed tile out, whatever its tick.
    /// Mutation: the `!t.proposed` filter removed from the composite — red.
    func testAProposedTileNeverEntersTheMix() throws {
        var t = tiles()
        t[1].proposed = true
        let img = try bytes(ColorMixRaster.image(tiles: t, mixed: [12, 13], colors: [12: (1, 0, 0), 13: (0, 0, 1)], backdrop: [], width: 4, height: 1))
        for px in 0..<4 { XCTAssertEqual(img[px * 4 + 2], 0, "no blue from the proposed Al") }
    }

    /// The map modes: only int and net are maps; wt% and at% are region quantities (ADR 054 item 3).
    func testOnlyIntAndNetAreMapModes() {
        XCTAssertEqual(MapMode.allCases.filter(\.isAvailable), [.integrated, .netCounts])
        XCTAssertEqual(MapMode.allCases.map(\.rawValue), ["int", "net", "wt%", "at%"])
    }

    /// "int" is the exact signal-window sum per pixel, net is that less the background windows.
    /// Mutation: `integratedMaps` returning the net maps — red (the background term is nonzero here).
    func testIntegratedMapsAreTheSignalSumsAndNetSubtractsTheBackground() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 400)
        let windows = ElementWindows.build(elements: [("Al", nil)], axis: axis, beamEnergyKeV: nil)
        let w = try XCTUnwrap(windows.first?.window)
        var counts = [UInt32](repeating: 0, count: 2 * 400)
        for p in 0..<2 { for c in 0..<400 { counts[p * 400 + c] = UInt32(3 + p + (w.signal.contains(c) ? 10 : 0)) } }
        let image = DenseSpectrumImage(ny: 1, nx: 2, channels: 400, counts: counts)
        let integrated = try XCTUnwrap(ElementWindows.integratedMaps(image: image, windows: windows).first ?? nil)
        let net = try XCTUnwrap(ElementWindows.maps(image: image, windows: windows).first ?? nil)
        for p in 0..<2 {
            XCTAssertEqual(integrated[p], Double(w.signal.count * (13 + p)), accuracy: 1e-9)
            XCTAssertLessThan(net[p], integrated[p], "the background windows hold counts: net is less")
        }
    }
}

// MARK: - The room's controller: live region, Pin, Auto ID on open

@MainActor
final class SpectroscopyRoomLiveRegionTests: XCTestCase {
    /// A dense image with a Cu line (8.04 keV) in the top-left pixels and Al (1.487) everywhere; 200 kV in the metadata.
    static func image(nx: Int = 8, ny: Int = 6) -> LoadedSpectrumImage {
        let channels = 1024
        var counts = [UInt32](repeating: 0, count: nx * ny * channels)
        for y in 0..<ny { for x in 0..<nx {
            let cu = x < nx / 2 && y < ny / 2
            for c in 0..<channels {
                let e = Double(c) * 0.01
                var v = 6 * exp(-e / 2) + 40 * exp(-pow(e - 1.487, 2) / (2 * 0.0035))
                if cu { v += 25 * exp(-pow(e - 8.04, 2) / (2 * 0.0100)) }
                counts[(y * nx + x) * channels + c] = UInt32(v.rounded())
            }
        } }
        var meta = SpectrumImageMetadata(fileName: "synthetic", filePath: "", scanWidth: nx, scanHeight: ny, channelCount: channels,
                                         energyOffsetEV: 0, energyDispersionEV: 10, scanPixelSize: 1, scanPixelUnit: "nm")
        meta.beamEnergyKeV = 200
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: counts), metadata: meta,
                                   energyAxis: EnergyAxis(offset: 0, scale: 0.01, size: channels))
    }

    /// The states stay alive for the test: the controller holds its session weakly, and an AppState that went away takes it along.
    private var keep: [AppState] = []

    private func open(autoID: Bool = false) -> (AppState, SpectroscopyRoomController, LoadedSpectrumImage) {
        let state = AppState()
        keep.append(state)
        state.spectroscopyRoom.model.autoIDEnabled = autoID
        let image = Self.image()
        state.openSpectrumImage(image)
        return (state, state.spectroscopyRoom, image)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func total(_ m: SpectroscopyRoomModel) -> Double { m.series.data.reduce(0, +) }

    /// One live region: the first edit creates it, later edits move it in place (same id, still two regions), and the
    /// spectrum is the latest shape's. Many edits in a row are coalesced, one sum at a time with the newest waiting.
    /// Mutations: `editRegion` adding a region per edit (count grows) — red; the `liveBusy`/`livePending` guard removed so every
    /// edit starts its own sum (`liveSums` reaches 60) — red.
    func testADragMovesOneRegionInPlaceAndCoalescesItsSums() async throws {
        let (_, c, image) = open()
        let m = c.model
        try await waitFor("the first sums") { self.total(m) > 0 }
        for i in 0..<60 {
            let x0 = i % 4
            c.editRegion(.rectangle(PixelRect(x0: x0, y0: 0, x1: x0 + 3, y1: 2)), final: false)
        }
        XCTAssertEqual(m.regions.count, 2, "the whole map and the one live region")
        let last = SpectrumRegionShape.rectangle(PixelRect(x0: 3, y0: 0, x1: 6, y1: 2))
        let expected = Double(image.sum(mask: last.mask(nx: 8, ny: 6)).reduce(0, +))
        try await waitFor("the newest shape's spectrum") { abs(self.total(m) - expected) < 0.5 }
        XCTAssertLessThan(c.liveSums, 60, "coalesced: the sums that ran are far fewer than the edits (ran \(c.liveSums))")
        XCTAssertEqual(m.regions.count, 2)
        XCTAssertEqual(m.regionOutline, last)
        XCTAssertTrue(m.spectrumSubtitle.hasSuffix("live"), "the strip says it is live while the pointer is down")
        // the end of the drag: the full recompute (rows follow, the region's counts, the settled title)
        c.editRegion(last, final: true)
        try await waitFor("the settled spectrum") { !m.spectrumSubtitle.hasSuffix("live") && abs(self.total(m) - expected) < 0.5 }
        XCTAssertEqual(m.regionSettings.pixels, "6")
        XCTAssertEqual(m.regions.count, 2)
    }

    /// A region on the live path never leaves a stale cached spectrum behind: after the final edit the sum is the final shape's
    /// even though an earlier shape's spectrum was cached under the same region id.
    /// Mutation: the `cache.forget(region:)` in the final edit removed — red.
    func testTheFinalEditForgetsTheCachedSpectrumOfTheOldShape() async throws {
        let (_, c, image) = open()
        let m = c.model
        try await waitFor("the first sums") { self.total(m) > 0 }
        let a = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)), b = SpectrumRegionShape.rectangle(PixelRect(x0: 4, y0: 3, x1: 8, y1: 6))
        c.editRegion(a, final: true)
        try await waitFor("shape a") { abs(self.total(m) - Double(image.sum(mask: a.mask(nx: 8, ny: 6)).reduce(0, +))) < 0.5 && m.regionOutline == a }
        c.editRegion(b, final: true)
        let expected = Double(image.sum(mask: b.mask(nx: 8, ny: 6)).reduce(0, +))
        try await waitFor("shape b") { abs(self.total(m) - expected) < 0.5 }
        XCTAssertEqual(m.regionSettings.pixels, "12")
    }

    /// Pin copies the live region's spectrum; the live region moves on without touching it; at most three; unpin drops one.
    /// Mutations: the pin storing a reference that follows the live spectrum (its sum changes) — red; the cap raised to 4 — red.
    func testPinFreezesACopyUpToThree() async throws {
        let (_, c, image) = open()
        let m = c.model
        let a = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3))
        c.editRegion(a, final: true)
        let aTotal = Double(image.sum(mask: a.mask(nx: 8, ny: 6)).reduce(0, +))
        try await waitFor("region a") { abs(self.total(m) - aTotal) < 0.5 && !m.spectrumSubtitle.hasSuffix("live") }
        c.pinRegion()
        XCTAssertEqual(m.pins.count, 1)
        XCTAssertEqual(m.pins[0].spectrum.reduce(0, +), aTotal, accuracy: 0.5)
        XCTAssertEqual(m.pins[0].pixels, 12)
        let b = SpectrumRegionShape.rectangle(PixelRect(x0: 4, y0: 3, x1: 8, y1: 6))
        c.editRegion(b, final: true)
        try await waitFor("region b") { abs(self.total(m) - Double(image.sum(mask: b.mask(nx: 8, ny: 6)).reduce(0, +))) < 0.5 }
        XCTAssertEqual(m.pins[0].spectrum.reduce(0, +), aTotal, accuracy: 0.5, "the pin did not move with the live region")
        c.pinRegion(); c.pinRegion(); c.pinRegion()
        XCTAssertEqual(m.pins.count, SpectroscopyRoomModel.maximumPins)
        XCTAssertEqual(Set(m.pins.map(\.id)).count, 3, "three distinct pins, three distinct colours")
        c.unpin(m.pins[1].id)
        XCTAssertEqual(m.pins.count, 2)
        c.pinRegion()
        XCTAssertEqual(m.pins.count, 3); XCTAssertEqual(Set(m.pins.map(\.id)).count, 3, "the freed id is reused, not duplicated")
    }

    /// The comparison overlay is the whole map's spectrum scaled to the region's counts; the whole map itself has none.
    /// Mutation: the scale dropped (the overlay is the raw whole-map sum) — red.
    func testTheComparisonOverlayIsScaledToTheRegion() async throws {
        let (_, c, image) = open()
        let m = c.model
        try await waitFor("the first sums") { self.total(m) > 0 }
        XCTAssertNil(m.series.overlay, "the whole map has nothing to compare with")
        let a = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3))
        c.editRegion(a, final: true)
        let aTotal = Double(image.sum(mask: a.mask(nx: 8, ny: 6)).reduce(0, +))
        try await waitFor("the overlay") { abs(self.total(m) - aTotal) < 0.5 && m.series.overlay != nil }
        XCTAssertEqual(m.series.overlay?.reduce(0, +) ?? 0, aTotal, accuracy: 1.0)
        m.compare = .none
        c.refresh()?.cancel()
        try await waitFor("no overlay") { m.series.overlay == nil }
    }

    /// R10 (spec 2 D-3 changed it): Auto ID applies its picks, so the first spectrum carries the picked element's COLOURED marker
    /// and no muted duplicate; a later pick elsewhere re-runs `apply` and keeps it.
    /// Mutations: the picks not applied (the landing maps proposals only) - red; `proposedMarkers` kept for an applied pick - red.
    func testAnAppliedPickCarriesTheColouredMarkerNotAMutedOne() async throws {
        let Cu = 29
        let (_, on, _) = open(autoID: true)
        try await waitFor("Cu's row") { on.model.results.contains { $0.z == Cu } }
        XCTAssertTrue(on.model.markers.contains { $0.elementZ == Cu && $0.kind == .line }, "Cu K\u{03B1} is a picked element's marker")
        XCTAssertFalse(on.model.markers.contains { $0.elementZ == Cu && $0.kind == .proposed }, "an applied pick is not also muted")
        on.model.elements.click(26); on.elementsChanged()   // a pick elsewhere re-runs `apply`: Cu keeps its marker
        try await waitFor("Fe's row") { on.model.results.contains { $0.z == 26 } }
        XCTAssertTrue(on.model.markers.contains { $0.elementZ == Cu && $0.kind == .line })
    }

    /// Auto ID on open: after the first sums, the proposer runs and its picks are applied (spec 2 D-3): the planted Cu line is a
    /// row and a tile at once, nothing is left proposed, and the rows are those of the same picks made by hand.
    /// Mutations: the open not running Auto ID - red; the picks not applied - red; the picks' rows computed apart from the listed
    /// elements (so they differ from the hand-picked ones) - red.
    func testAutoIDOnOpenPicksAndMapsWithoutMovingAListedNumber() async throws {
        let Al = 13, Cu = 29
        // reference: Auto ID off, Al listed
        let (_, off, _) = open(autoID: false)
        off.model.elements.click(Al); off.elementsChanged()
        try await waitFor("the reference row") { off.model.results.count == 1 && off.model.tiles.count == 1 }
        let reference = try XCTUnwrap(off.model.results.first)

        let (_, on, _) = open(autoID: true)
        try await waitFor("Auto ID's outcome") { on.model.autoID.outcome != nil || on.model.autoID.failure != nil }
        XCTAssertNil(on.model.autoID.failure)
        try await waitFor("Cu's row and tile") { on.model.results.contains { $0.z == Cu } && on.model.tiles.contains { $0.z == Cu && !$0.proposed } }
        XCTAssertTrue(on.model.elements.suggestions.isEmpty, "applied, not left to accept")
        XCTAssertFalse(on.model.tiles.contains { $0.proposed }, "no proposed tile")
        XCTAssertTrue(on.model.mixed.contains(Cu))
        // The picks are listed elements like any other (a neighbour's window can legitimately move a net count), so the invariant
        // is: the same elements picked by hand give exactly the same rows.
        let picked = on.model.elements.activeZ
        XCTAssertTrue(picked.contains(Cu))
        let (_, hand, _) = open(autoID: false)
        for z in picked { hand.model.elements.click(z) }
        hand.elementsChanged()
        try await waitFor("the hand-picked rows") { hand.model.results.count == on.model.results.count && hand.model.tiles.count == on.model.tiles.count }
        for row in on.model.results {
            let other = try XCTUnwrap(hand.model.results.first { $0.z == row.z })
            XCTAssertEqual(row.netCounts, other.netCounts, accuracy: 1e-9, "Auto ID's pick \(row.z) differs from the same pick by hand")
            XCTAssertEqual(row.netSigma, other.netSigma, accuracy: 1e-9)
        }
        XCTAssertNotEqual(reference.netCounts, 0, "the Al-only reference is a real measurement")
    }

    /// R4c (Gate B 2026-10-06 section 4), as spec 2 D-3 changed it: a landing that APPLIES a pick changes the listed elements, so
    /// the live fit follows (a refresh: Cu joins the table and the fit's check restarts); a landing with nothing to apply maps
    /// the proposals only and leaves `generation` and the in-flight unlisted-line check alone.
    /// Mutation: the applied landing calling `proposalsChanged()` and not `elementsChanged()` (Cu never reaches the fit) - red.
    func testALandingAutoIDRefitsOnlyWhenItAppliedAPick() async throws {
        let (_, c, _) = open(autoID: false)
        c.model.elements.click(13); c.elementsChanged()
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "")
        let generation = c.generation
        c.runAutoID()
        try await waitFor("Auto ID's outcome") { c.model.autoID.outcome != nil || c.model.autoID.failure != nil }
        XCTAssertNil(c.model.autoID.failure)
        XCTAssertTrue(c.model.elements.quantified.contains(29), "the planted Cu line is picked")
        XCTAssertGreaterThan(c.generation, generation, "a pick changed the listed elements: the fit followed")
        try await waitFor("Cu in the fit") { c.model.results.contains { $0.z == 29 } }
        await c.checkTask?.value
        // Run again until a run finds nothing new to apply (each run may list more elements): that landing neither refreshes nor
        // starts a new fit and check.
        var settled = false
        for _ in 0..<6 {
            await c.checkTask?.value
            try await waitFor("the fit to land") { !c.model.isFitting }
            let before = (c.generation, c.checkTask)
            c.runAutoID()
            XCTAssertTrue(c.model.autoID.running)
            try await waitFor("the next run") { !c.model.autoID.running }
            if c.generation == before.0 {
                XCTAssertEqual(c.checkTask, before.1, "the check was not cancelled or replaced")
                settled = true; break
            }
        }
        XCTAssertTrue(settled, "Auto ID settles: a run with nothing new to apply")
    }

    /// Auto ID off: nothing runs on open.
    /// Mutation: `autoIDOnOpen` ignoring the switch (`true ? Task {…} : nil`) — red.
    func testAutoIDOffRunsNothingOnOpen() async throws {
        let (_, off, _) = open(autoID: false)
        try await waitFor("the first sums") { self.total(off.model) > 0 }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(off.model.autoID.running); XCTAssertNil(off.model.autoID.outcome); XCTAssertNil(off.model.autoID.failure)
    }

    /// A click made while a run is going does not lose the run: the refresh the click causes cancels it and it starts again
    /// when that refresh lands (the switch is on). Started by hand here so the open's own run cannot make this vacuous.
    /// Mutation: `autoIDRestart = model.autoIDEnabled` made `= false` in `refresh` — red (no outcome ever lands).
    func testAClickDuringARunRestartsIt() async throws {
        let (_, c, _) = open(autoID: false)
        try await waitFor("the first sums") { self.total(c.model) > 0 }
        c.model.autoIDEnabled = true
        c.runAutoID()
        XCTAssertTrue(c.model.autoID.running, "precondition: the run started")
        c.model.elements.click(13); c.elementsChanged()      // the refresh cancels the run
        try await waitFor("an outcome after the click", timeout: 20) { c.model.autoID.outcome != nil }
        XCTAssertFalse(c.model.autoID.running)
    }

    /// Opening a spectrum image resets the per-image view state: colours, contrast, pins, the active map, the live region.
    /// Mutation: `bind` not clearing `elementColors` — red.
    func testBindingAnImageStartsTheViewStateOver() async throws {
        let (state, c, _) = open()
        c.model.elementColors[13] = .purple; c.model.mapDisplays[.haadf] = MapDisplay(lo: 0.3, hi: 1, gamma: 2)
        c.model.active = .element(13); c.model.haadfColormap = .viridis
        c.editRegion(.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)), final: true)
        c.pinRegion()
        state.openSpectrumImage(Self.image())
        let m = c.model
        XCTAssertTrue(m.elementColors.isEmpty); XCTAssertTrue(m.mapDisplays.isEmpty); XCTAssertTrue(m.pins.isEmpty)
        XCTAssertEqual(m.active, .colorMix); XCTAssertEqual(m.haadfColormap, .gray); XCTAssertNil(c.liveRegionID); XCTAssertNil(m.regionOutline)
    }

    /// The comparison line: a region's quantification shows the same method on the whole map; the whole map shows none.
    /// Mutations: the line computed for region 0 as well — red; the caveat dropped from `m.abundanceNote` in `present` — red.
    func testARegionsQuantificationCarriesAWholeMapComparisonLine() async throws {
        let (state, c, _) = open()
        for z in [13, 29] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        await c.checkTask?.value
        XCTAssertNil(c.model.wholeMapLine, "the whole map is its own comparison")
        c.editRegion(.rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3)), final: true)
        await c.lastRefresh?.value
        // A2: the region's at% is shown at once (the check blanks nothing), so the comparison line is not gated by the check either.
        try await waitFor("the comparison line") { c.model.wholeMapLine != nil }
        XCTAssertTrue(c.model.wholeMapLine?.hasPrefix("Whole map, same listed elements, for comparison: ") == true)
        XCTAssertTrue(c.model.wholeMapLine?.hasSuffix(" at%") == true)
        // ... and it stays when the check names a candidate that moves a net: A2 ships the quantity, the caveat reaches the model.
        let fit = try XCTUnwrap(c.lastFit)
        let zr = UnlistedLineCheck.Candidate(element: "Zr", group: "Zr_La", net: 900, detectionLimit: 400, sumPeakQuestion: false)
        c.landCheck(UnlistedLineChecker.withholding(fit, UnlistedLineCheck(candidates: [zr], moves: [.init(element: "Al", before: 100, after: 400, sigma: 10)])), region: c.model.selectedRegion ?? 0, generation: c.generation)
        XCTAssertNotNil(c.model.wholeMapLine, "a check that moves a net blanks no at%, so the whole-map line stays")
        XCTAssertTrue(c.model.abundanceNote?.hasPrefix("at% caveat: assumes the listed elements only; unlisted: Zr (net 900)") == true, c.model.abundanceNote ?? "nil")
    }

    /// The tile grid and the whole room draw for both aspects (the GMS demo and the owner's strip), wide and narrow. A smoke
    /// test (no trap, an image comes out); the arrangement's own correctness is `SpectroscopyRoomGeometryTests`.
    func testTheRoomDrawsForTheDemoAndTheStripAspects() throws {
        for (w, h) in [(64, 48), (215, 926), (926, 215)] {
            let m = SpectroscopyRoomModel.fixture
            m.gridWidth = w; m.gridHeight = h
            m.backdrop = [Float](repeating: 0.5, count: w * h)
            m.tiles = [13, 12, 14, 29].map { z in MapTile(z: z, width: w, height: h, values: [Float](repeating: 0.5, count: w * h)) }
                + [MapTile(z: 8, width: w, height: h, values: [Float](repeating: 0.1, count: w * h), proposed: true)]
            m.mixed = [13, 12, 14]
            m.regionOutline = .rectangle(PixelRect(x0: 1, y0: 1, x1: max(2, w / 3), y1: max(2, h / 3)))
            for width: CGFloat in [1100, 600] {
                let r = ImageRenderer(content: SpectroscopyRoomContent(model: m).frame(width: width, height: 800))
                XCTAssertNotNil(r.cgImage, "\(w)x\(h) at \(width)")
            }
        }
    }
}

// MARK: - Cost of a live drag on the owner's file shape

@MainActor
final class SpectroscopyLiveRegionCostTests: XCTestCase {
    /// A 926 x 215 x 4096 sparse store (the owner's Velox shape; about 16 M events).
    static func bigImage() throws -> SparseSpectrumImage {
        let nx = 926, ny = 215, channels = 4096, perPixel = 80
        var rowOffsets = [Int](repeating: 0, count: nx * ny + 1)
        var channelIndex = [UInt16](), counts = [UInt32]()
        channelIndex.reserveCapacity(nx * ny * perPixel); counts.reserveCapacity(nx * ny * perPixel)
        var state: UInt64 = 0x9E3779B97F4A7C15
        for p in 0..<(nx * ny) {
            var c = -1
            for k in 0..<perPixel {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                c = min(c + 1 + Int(state >> 60) % (channels / perPixel - 1), channels - perPixel + k)   // ascending, in the axis
                channelIndex.append(UInt16(c)); counts.append(UInt32(1 + k % 3))
            }
            rowOffsets[p + 1] = (p + 1) * perPixel
        }
        return try SparseSpectrumImage(ny: ny, nx: nx, channels: channels, rowOffsets: rowOffsets, channelIndex: channelIndex, counts: counts)
    }

    private func log(_ line: String) {
        print(line)
        if let path = ProcessInfo.processInfo.environment["R4_LOG"] {
            let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// One live sum over a 300 x 100 rectangle of the owner's shape costs milliseconds, so a drag's spectrum can follow the
    /// pointer. The measured time goes to the log (R4_LOG) for the report; the bound is a ceiling, not a target.
    /// Mutation: `SparseSpectrumImage.sum` ignoring the mask (`where true`) — the 16 M-event sum then costs several times more.
    func testALiveSumOverARectangleOfTheOwnersShapeIsFast() throws {
        let image = try Self.bigImage()
        let nx = image.nx, ny = image.ny
        let shape = SpectrumRegionShape.rectangle(PixelRect(x0: 300, y0: 50, x1: 600, y1: 150))
        var sum = image.sum(mask: shape.mask(nx: nx, ny: ny))   // warm
        let t0 = Date()
        var runs = 0
        for i in 0..<10 {
            sum = image.sum(mask: RegionEditing.moved(shape, dx: i * 5, dy: 0, grid: (nx, ny)).mask(nx: nx, ny: ny)); runs += 1
        }
        let perUpdate = Date().timeIntervalSince(t0) / Double(runs)
        log("LIVE-SUM-COST 926x215x4096, 300x100 rectangle: \(String(format: "%.1f", perUpdate * 1000)) ms per update (mask + sum), \(sum.reduce(0, +)) counts")
        XCTAssertLessThan(perUpdate, 0.04, "measured \(perUpdate * 1000) ms")
        // Exact: every pixel holds 80 events with counts 1 + k % 3, i.e. 159 counts; the rectangle (moved by 45, still on the grid) is
        // 300 x 100 = 30 000 pixels, so 4 770 000. A sum that ignores the mask counts all 199 090 pixels instead (31 655 910).
        XCTAssertEqual(sum.reduce(0, +), 30_000 * 159)
    }

    /// The controller on that store: 120 live edits issued back to back (a fast drag), coalesced; reports how many sums ran,
    /// the mean cost of one, and the wall time until the spectrum is the last shape's.
    func testTheControllerFollowsAFastDragOnTheOwnersShape() async throws {
        let big = try Self.bigImage()
        var meta = SpectrumImageMetadata(fileName: "owner-shape", filePath: "", scanWidth: big.nx, scanHeight: big.ny, channelCount: big.channels,
                                         energyOffsetEV: 0, energyDispersionEV: 20)
        meta.beamEnergyKeV = 200
        let image = LoadedSpectrumImage(image: big, metadata: meta, energyAxis: EnergyAxis(offset: 0, scale: 0.02, size: big.channels))
        let state = AppState()
        state.spectroscopyRoom.model.autoIDEnabled = false
        state.openSpectrumImage(image)
        let c = state.spectroscopyRoom, m = c.model
        let end = Date().addingTimeInterval(60)
        while m.series.data.reduce(0, +) == 0, Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        let sums0 = c.liveSums, secs0 = c.liveSumSeconds
        let t0 = Date()
        var last = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 1, y1: 1))
        for i in 0..<120 {
            last = .rectangle(PixelRect(x0: 100 + i * 3, y0: 50, x1: 400 + i * 3, y1: 150))
            c.editRegion(last, final: false)
            try await Task.sleep(nanoseconds: 8_000_000)          // ~ a 120 Hz pointer
        }
        let expected = Double(big.sum(mask: last.mask(nx: big.nx, ny: big.ny)).reduce(0, +))
        while abs(m.series.data.reduce(0, +) - expected) > 0.5, Date() < end { try await Task.sleep(nanoseconds: 5_000_000) }
        let wall = Date().timeIntervalSince(t0)
        let ran = c.liveSums - sums0
        log("LIVE-DRAG controller, 120 edits at ~120 Hz: \(ran) sums ran, \(String(format: "%.1f", (c.liveSumSeconds - secs0) / Double(max(ran, 1)) * 1000)) ms mean per sum (incl. the hop to the main actor), settled \(String(format: "%.0f", wall * 1000)) ms after the first edit")
        XCTAssertEqual(m.series.data.reduce(0, +), expected, accuracy: 0.5, "the spectrum is the last shape's")
        XCTAssertLessThanOrEqual(ran, 120, "never more sums than edits (at this speed each lands before the next edit; the coalescing itself is testADragMovesOneRegionInPlaceAndCoalescesItsSums)")
    }
}
