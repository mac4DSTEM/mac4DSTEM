//
//  SpectroscopySpec2KTests.swift
//  Lane K (drive-2 fixes, 2026-10-07): one grouping of pixel counts, the room's divider extremes, the "Found" row, elements with
//  no X-ray line. Every test names the mutation it catches; each was broken once and seen red (the lane report lists them).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SpectroscopySpec2KTests: XCTestCase {
    private let thin = "\u{202F}"
    private var keep: [AppState] = []

    private func waitFor(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: 1. pixel counts grouped one way

    /// The capsule on the ColorMix groups with the narrow no-break space like the spectrum header and the table.
    /// Mutation: the caption back to `\(pixels)` interpolated (a German locale prints "160.400") - red.
    func testTheRegionCapsuleGroupsPixelsWithAThinSpace() {
        XCTAssertEqual(MapTileView.regionCaption(pixels: 160_400), "Region \u{00B7} 160\(thin)400 px \u{00B7} live")
        XCTAssertEqual(MapTileView.regionCaption(pixels: 6), "Region \u{00B7} 6 px \u{00B7} live")
    }

    /// Both `spectrumSubtitle` lines (the whole map's and the live region's) group their pixel count.
    /// Mutations: either line's `ResultFormat.counts(Double(...))` back to a bare Int - red (the other stays green).
    func testBothSpectrumSubtitlesGroupPixels() async throws {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image(nx: 40, ny: 30))   // 1 200 pixels
        let c = state.spectroscopyRoom; let m = c.model
        c.autoIDOnOpen?.cancel()
        try await waitFor("the whole map's spectrum") { m.spectrumSubtitle.hasSuffix(" px") }
        XCTAssertTrue(m.spectrumSubtitle.hasSuffix("1\(thin)200 px"), m.spectrumSubtitle)
        let all = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 40, y1: 30))
        c.editRegion(all, final: false)
        try await waitFor("the live sum") { m.spectrumSubtitle.hasSuffix("live") }
        XCTAssertTrue(m.spectrumSubtitle.hasSuffix("1\(thin)200 px \u{00B7} live"), m.spectrumSubtitle)
    }

    // MARK: 2. divider extremes

    /// A maps block under 48 pt is not drawn: maps 0, the spectrum the whole room; from 48 pt it is the block it was.
    /// Mutations: the threshold removed (a 40-pt block stays) - red; `<` made `<=` (48 pt itself collapses) - red.
    func testAMapsBlockUnder48PtIsNotDrawn() {
        let room = CGSize(width: 1100, height: 700), header: CGFloat = 28
        let tiny = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 40 / 700)
        XCTAssertEqual(tiny.mapsHeight, 0)
        XCTAssertEqual(tiny.bottomHeight, room.height)
        XCTAssertEqual(tiny.gridAvail.height, 0)
        let edge = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 48 / 700)
        XCTAssertEqual(edge.mapsHeight, 48, accuracy: 1e-9)
        XCTAssertEqual(edge.mapsHeight + edge.bottomHeight, room.height, accuracy: 1e-9)
        let none = SpectroscopyRoomPlan.make(room: room, headerHeight: header, tileCount: 5, aspect: 1, mapsFraction: 0)
        XCTAssertEqual(none.mapsHeight, 0)
    }

    /// The default split is not touched (only a block under 48 pt collapses): a short room still keeps its maps.
    /// Mutation: the collapse made unconditional (`maps = 0` for every given fraction) - red.
    func testTheCollapseLeavesALargerBlockAlone() {
        let p = SpectroscopyRoomPlan.make(room: CGSize(width: 1100, height: 900), headerHeight: 28, tileCount: 5, aspect: 1, mapsFraction: 0.5)
        XCTAssertEqual(p.mapsHeight, 450, accuracy: 1e-9)
    }

    /// The plot draws only from 80 pt of height; under it the header row alone remains.
    /// Mutations: the floor lowered (30) - red; `>=` made `>` (80 itself) - red.
    func testThePlotDrawsOnlyFrom80Pt() {
        XCTAssertFalse(SpectrumPlotFit.draws(plotHeight: 79.9))
        XCTAssertFalse(SpectrumPlotFit.draws(plotHeight: 30))
        XCTAssertFalse(SpectrumPlotFit.draws(plotHeight: 0))
        XCTAssertTrue(SpectrumPlotFit.draws(plotHeight: 80))
        XCTAssertTrue(SpectrumPlotFit.draws(plotHeight: 300))
    }

    // MARK: 3. Found

    /// The row is "Found", with a help that says what it lists and where a wrong one is removed.
    /// Mutation: the title back to "Picked" - red.
    func testTheAutoIDRowIsFound() {
        XCTAssertEqual(ElementsSection.foundTitle, "Found")
        XCTAssertEqual(ElementsSection.foundHelp, "What Auto ID found and picked; remove a wrong one in the table")
    }

    // MARK: 4. elements with no line

    /// Hs and Og have no line in the table: unavailable (a pick there fits and maps nothing); Z <= 4 keeps its wording; Al is
    /// pickable; every element is unavailable exactly when Z <= 4 or the table lists no line for it.
    /// Mutations: the table check removed (Hs available) - red; the Z <= 4 wording changed - red; the check inverted - red.
    func testAnElementWithNoLineIsUnavailable() {
        XCTAssertEqual(ElementSelection.unavailableReason(z: PeriodicLayout.z(of: "Hs")!), "No X-ray line in the table")
        XCTAssertEqual(ElementSelection.unavailableReason(z: PeriodicLayout.z(of: "Og")!), "No X-ray line in the table")
        XCTAssertNil(ElementSelection.unavailableReason(z: PeriodicLayout.z(of: "Al")!))
        XCTAssertEqual(ElementSelection.unavailableReason(z: 1), "No usable X-ray line at this detector window")
        XCTAssertEqual(ElementSelection.unavailableReason(z: 4), "No usable X-ray line at this detector window")
        for z in 1...PeriodicLayout.symbols.count {
            let none = XRayLines.lines(of: PeriodicLayout.symbol(z)).isEmpty
            XCTAssertEqual(ElementSelection.unavailableReason(z: z) != nil, z <= 4 || none, PeriodicLayout.symbol(z))
        }
        var e = ElementSelection(); e.click(PeriodicLayout.z(of: "Hs")!)
        XCTAssertTrue(e.manual.isEmpty, "a click on Hs picks nothing")
    }
}
