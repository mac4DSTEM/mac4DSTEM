//
//  SpectroscopyUXABTests.swift
//  UX lane AB (spec 2026-10-06): the proposal cap, the opening zoom, the tile motion rule and
//  the ColorMix header. Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class SpectroscopyUXABTests: XCTestCase {
    /// #1: at most three proposals get a tile, the strongest first (the given order is already by significance); fewer stay as they are.
    /// Mutation: `ProposedTileCap.maximum` changed from 3 to 4 - red.
    func testProposedTilesAreCappedAtThreeInGivenOrder() {
        XCTAssertEqual(ProposedTileCap.maximum, 3)
        XCTAssertEqual(ProposedTileCap.apply(["Cu", "Al", "O", "Eu", "Hf", "Co", "Ho"]), ["Cu", "Al", "O"])
        XCTAssertEqual(ProposedTileCap.apply(["Cu", "Al"]), ["Cu", "Al"])
        XCTAssertEqual(ProposedTileCap.apply([String]()), [])
    }

    /// #5: with only proposals' markers the strip opens on their lines, not on the first 20 keV.
    /// Mutation: `.proposed` dropped from the zoom's marker kinds - red.
    func testOpeningZoomFollowsProposedLines() {
        let m = [LineMarker(label: "Cu K\u{03B1}", energy: 8.04, elementZ: 29, kind: .proposed),
                 LineMarker(label: "Al K\u{03B1}", energy: 1.487, elementZ: 13, kind: .proposed)]
        let r = SpectrumAutoZoom.range(markers: m, domain: 0...80, minimumSpan: 0.04)
        XCTAssertEqual(r.lowerBound, 1.087, accuracy: 1e-9); XCTAssertEqual(r.upperBound, 8.844, accuracy: 1e-9)
    }

    /// #5: with no lines at all the opening view ends where 99.5 % of the counts lie (floor 2 keV, cap 20, never past the axis).
    /// Mutation: the fraction 0.995 changed to 0.5 - red.
    func testOpeningZoomWithoutLinesFollowsTheCountsEnergy() {
        var data = [Double](repeating: 0, count: 8000)       // 0.01 keV per channel: 80 keV axis
        for i in 0..<900 { data[i] = 100 }                    // everything below 9 keV
        data[3000] = 10                                       // a stray 30 keV count, far below 0.5 % of the total
        let e = SpectrumAutoZoom.countsEnergy(data: data, energyStart: 0, energyStep: 0.01)
        XCTAssertEqual(try XCTUnwrap(e), 9, accuracy: 0.1)
        XCTAssertEqual(SpectrumAutoZoom.range(markers: [], domain: 0...80, minimumSpan: 0.04, countsEnergy: e), 0...e!)
        XCTAssertEqual(SpectrumAutoZoom.range(markers: [], domain: 0...80, minimumSpan: 0.04, countsEnergy: 0.7).upperBound, 2, "floor 2 keV")
        XCTAssertEqual(SpectrumAutoZoom.range(markers: [], domain: 0...80, minimumSpan: 0.04, countsEnergy: 55).upperBound, 20, "cap 20 keV")
        XCTAssertEqual(SpectrumAutoZoom.range(markers: [], domain: 0...5, minimumSpan: 0.04, countsEnergy: 55).upperBound, 5, "inside the axis")
        XCTAssertNil(SpectrumAutoZoom.countsEnergy(data: [0, 0, 0], energyStart: 0, energyStep: 0.01), "no counts: no energy")
    }

    /// U2: "Accept proposed" accepts only the proposals that have a tile (the capped list); the other four stay proposed, unlisted.
    /// Mutation: `acceptProposed` loops over `elements.suggestions` instead of `shownProposals` - red.
    @MainActor func testAcceptProposedAcceptsOnlyTheShownTiles() {
        let m = SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
        let zs = [29, 13, 8, 63, 67, 72, 27]   // Cu Al O Eu Ho Hf Co, strongest first
        m.elements = ElementSelection(suggestions: zs.map { ElementSuggestion(z: $0, reason: "", proposedRole: .quantify) })
        XCTAssertEqual(m.shownProposals.map(\.z), [29, 13, 8])
        m.acceptProposed()
        XCTAssertEqual(Set(m.elements.activeZ), [29, 13, 8])
        XCTAssertEqual(m.elements.suggestions.map(\.z), [63, 67, 72, 27], "the rest stay proposed")
    }

    /// U2: a line above the fit range's end does not stretch the opening view; with no fit range the counts energy is the ceiling.
    /// Mutation: the `<= ceiling` filter dropped - red.
    func testOpeningZoomIgnoresLinesAboveTheFitEnd() {
        let m = [LineMarker(label: "Cu K\u{03B1}", energy: 8.04, elementZ: 29),
                 LineMarker(label: "Hf K\u{03B2}", energy: 63, elementZ: 72, kind: .proposed)]
        let r = SpectrumAutoZoom.range(markers: m, domain: 0...80, minimumSpan: 0.04, fitEnd: 20)
        XCTAssertEqual(r.upperBound, 8.844, accuracy: 1e-9)
        XCTAssertEqual(SpectrumAutoZoom.range(markers: m, domain: 0...80, minimumSpan: 0.04, countsEnergy: 12).upperBound, 8.844, accuracy: 1e-9)
        XCTAssertEqual(SpectrumAutoZoom.range(markers: m, domain: 0...80, minimumSpan: 0.04).upperBound, 69.3, accuracy: 1e-9, "no ceiling known: as before")
    }

    /// Spec 2 D-2 (was UX #2's tick): clicking a tile picks it into the ColorMix, it no longer accepts a proposal (Auto ID applies its
    /// picks; the periodic table's click is the other way in).
    /// Mutation: `pick` calling `elements.click` - red.
    @MainActor func testClickingATileTogglesTheMixAndLeavesTheProposalsAlone() {
        let m = SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
        let cu = 29, al = 13
        m.elements = ElementSelection(suggestions: [ElementSuggestion(z: cu, reason: "Cu", proposedRole: .quantify)])
        m.pick(.element(cu))
        XCTAssertNotEqual(m.elements.role(cu), .quantify)
        XCTAssertFalse(m.elements.suggestions.isEmpty)
        m.pick(.element(al))
        XCTAssertTrue(m.mixed.contains(al))
    }

    /// #12: tiles move with `.snappy` only when Reduce Motion is off; nothing else here animates.
    /// Mutation: the flag inverted - red.
    func testTileReorderAnimatesOnlyWithoutReduceMotion() {
        XCTAssertNotNil(TileMotion.animation(reduceMotion: false))
        XCTAssertNil(TileMotion.animation(reduceMotion: true))
    }

    /// #10: the ColorMix header carries the mixed symbols only; what is not ticked moves to the tile's help.
    /// Mutation: `help` returns the header text unchanged - red.
    func testColorMixHeaderDropsTheParentheticalAndHelpKeepsIt() {
        XCTAssertEqual(ColorMixHeader.text(mixed: ["O", "Al", "Si"]), "O \u{00B7} Al \u{00B7} Si")
        let help = ColorMixHeader.help(mixed: ["O", "Al", "Si"], notMixed: ["Mg"])
        XCTAssertTrue(help.contains("Mg not ticked"), help)
        XCTAssertTrue(help.contains("O \u{00B7} Al \u{00B7} Si"), help)
        XCTAssertFalse(ColorMixHeader.help(mixed: ["O"], notMixed: []).contains("not ticked"))
    }
}
