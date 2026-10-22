//
//  SpectroscopyRoomR5Tests.swift
//  Lane R5 (drive fixes): the room's two bands never scroll as a whole, the sidebar selects one row, the ColorMix mixes every
//  ticked element and says who is not ticked. Each test names the mutation it catches.
//

import ShellLayout
import XCTest
import SwiftUI
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ColorMixCompositeTests: XCTestCase {
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
        XCTAssertEqual(m.display(.element(13)), m.defaultDisplay(.element(13))); XCTAssertEqual(m.display(.haadf), m.defaultDisplay(.haadf))   // R8: the default is each map's own stretch
        m.displayBinding(.element(12)).wrappedValue = m.defaultDisplay(.element(12))
        XCTAssertNil(m.mapDisplays[.element(12)], "the default window is stored as absent")
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

/// R6: the quant table's Net ± σ cell is one line, never wrapped or truncated (drive 2: "88 515 / ± 413", "250 367 ±…").
final class QuantNetCellTests: XCTestCase {
    /// The parts carry the narrow no-break spaces (U+202F) around the sign, so no line break can fall inside the pair; a long
    /// pair is flagged compact (σ smaller and secondary), a short one is not.
    /// Mutation: the separator made " ± " with ordinary spaces, or `compactAbove` raised to 99 - red.
    func testTheCellIsOneUnbreakablePairAndALongOneIsCompact() {
        let short = ResultFormat.netCell(88_515, 413)
        XCTAssertEqual(short.net, "88\u{202F}515"); XCTAssertEqual(short.sigma, "413")
        XCTAssertEqual(short.separator, "\u{202F}\u{00B1}\u{202F}")
        XCTAssertFalse(short.compact)
        let long = ResultFormat.netCell(6_155_340, 3_905)
        XCTAssertEqual(long.net, "6\u{202F}155\u{202F}340")
        XCTAssertTrue(long.compact)
        for c in [short, long] { XCTAssertFalse((c.net + c.separator + c.sigma).contains(" "), "no breaking space anywhere in the cell") }
    }
}

/// Lane R8 (drive 2): map contrast, one unlisted block, the scale bar.
final class SpectroscopyRoomR8Tests: XCTestCase {
    /// 10 000 values in 0...0.1 plus one hot pixel at 1.0: the default window ignores the hot pixel.
    /// Mutation: `defaultWindow` uses min/max (q(0)/q(1)) instead of q(low)/q(high) - hi becomes 1.0, red.
    func testDefaultWindowIgnoresAHotPixel() {
        var v = (0..<10_000).map { Float($0) / 100_000 }
        v.append(1)
        v.append(.nan)
        let w = MapContrast.defaultWindow(of: v)
        XCTAssertLessThan(w.hi, 0.11); XCTAssertGreaterThan(w.hi, 0.09); XCTAssertLessThan(w.lo, 0.001)
        XCTAssertEqual(w.gamma, 1)
    }

    func testDefaultWindowDegenerateCases() {
        XCTAssertEqual(MapContrast.defaultWindow(of: []), MapDisplay())
        XCTAssertEqual(MapContrast.defaultWindow(of: [Float](repeating: 0.3, count: 50)), MapDisplay())
        // A sparse map: 99.5 % is the floor; the window runs to the maximum instead of collapsing.
        var sparse = [Float](repeating: 0, count: 1000); sparse[5] = 0.8
        XCTAssertEqual(MapContrast.defaultWindow(of: sparse).hi, 0.8)
    }

    /// The model's default is the percentile window; a user window stays; Reset (mapDisplays = [:]) returns to the default.
    /// Mutation: `display` returns `mapDisplays[map] ?? MapDisplay()` - the first assertion goes red.
    func testModelDisplayDefaultsToTheStretchAndAUserWindowStays() {
        let m = SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
        var v = (0..<1000).map { Float($0) / 10_000 }; v[0] = 1
        m.tiles = [MapTile(z: 8, width: 40, height: 25, values: v)]; m.tileRevision += 1
        XCTAssertLessThan(m.display(.element(8)).hi, 0.2)
        let b = m.displayBinding(.element(8))
        var d = b.wrappedValue; d.lo = 0.01; b.wrappedValue = d
        XCTAssertEqual(m.display(.element(8)).lo, 0.01)
        m.mapDisplays = [:]
        XCTAssertLessThan(m.display(.element(8)).hi, 0.2)
        var same = b.wrappedValue; same.gamma = 1; b.wrappedValue = same
        XCTAssertTrue(m.mapDisplays.isEmpty, "the default window is stored as absent")
    }

    /// One block: the check's pending line alone; the caveat sentence with its buttons; otherwise unchanged.
    /// Mutation: drop the `u.checking` branch's `caveat ? nil` - the pending state shows two lines, red.
    func testUnlistedBlockMergesTheCaveatIntoOneLine() {
        let caveat = "at% caveat: assumes the listed elements only; unlisted: Zr (net 3 589)"
        let found = UnlistedLineNote(text: "Unlisted lines found: Zr", detail: "d", candidates: [40])
        let a = QuantifyPresentation.unlistedBlock(found, abundanceNote: caveat)
        XCTAssertEqual(a.line?.text, caveat); XCTAssertEqual(a.line?.candidates, [40]); XCTAssertNil(a.note)
        let p = QuantifyPresentation.unlistedBlock(.checkingNote, abundanceNote: "at% caveat: unlisted-line check running")
        XCTAssertTrue(p.line?.checking == true); XCTAssertNil(p.note)
        let refusal = "at% not computed: x"
        let r = QuantifyPresentation.unlistedBlock(found, abundanceNote: refusal)
        XCTAssertEqual(r.line?.text, found.text); XCTAssertEqual(r.note, refusal)
        XCTAssertEqual(QuantifyPresentation.unlistedBlock(nil, abundanceNote: caveat).note, caveat)
    }

    /// 0.5 nm per pixel drawn at 2 pt per pixel (0.25 nm/pt), target 64 pt = 16 nm -> 20 nm (80 pt, 1-2-5 rounding of 16 is 20).
    /// Mutation: `nice125` replaced by the raw value in `plan` - the label is "16 nm", red.
    func testScaleBarPlanPicksARoundLength() throws {
        let p = try XCTUnwrap(MapScaleBar.plan(pixelSize: 0.5, unit: "nm", pointsPerPixel: 2))
        XCTAssertEqual(p.label, "20 nm"); XCTAssertEqual(p.lengthPoints, 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(MapScaleBar.plan(pixelSize: 5, unit: "nm", pointsPerPixel: 0.2)).label, "2 \u{00B5}m")
        XCTAssertEqual(try XCTUnwrap(MapScaleBar.plan(pixelSize: 1e-9, unit: "m", pointsPerPixel: 1)).label, "50 nm")
        XCTAssertEqual(try XCTUnwrap(MapScaleBar.plan(pixelSize: 3, unit: "foo", pointsPerPixel: 1)).label, "200 foo")
        XCTAssertNil(MapScaleBar.plan(pixelSize: 0, unit: "nm", pointsPerPixel: 1))
        XCTAssertNil(MapScaleBar.plan(pixelSize: 1, unit: "nm", pointsPerPixel: 0))
    }
}
