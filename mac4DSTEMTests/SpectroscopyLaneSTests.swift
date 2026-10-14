import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
import SpectroCore
@testable import mac4DSTEM

/// Lane S (UI audit 2026-10-14, Spectroscopy rows): every test names the mutation that turns it red.
@MainActor
final class SpectroscopyLaneSTests: XCTestCase {

    // MARK: Row 1 - caveats are read, not hovered

    private func outcome(reasons: [String] = [], notes: [String] = [], suspects: [AutoIDSuspect] = []) -> AutoIDOutcome {
        AutoIDOutcome(region: "r", suggestions: reasons.enumerated().map { ElementSuggestion(z: 29 + $0.offset, reason: $0.element) },
                      suspects: suspects, notTested: [], notes: notes)
    }

    /// The Details disclosure is drawn exactly when the proposer said something, and holds every line the hover used to hold.
    /// Mutation: `showsDetails` returns false, or `noteLines` drops `o.notes` - red.
    func testAutoIDDetailsHoldEveryReasonAndNote() {
        let o = outcome(reasons: ["Cu: net 900 counts"], notes: ["look-elsewhere: 3 of 40 tested"],
                        suspects: [AutoIDSuspect(label: "Al+Al sum?", energy: 3.0, question: "sum peak or Ar", stats: "net 8 counts")])
        XCTAssertTrue(ElementsSection.showsDetails(o))
        let lines = ElementsSection.noteLines(o, o.suggestions)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Cu: ") && lines[0].contains("net 900 counts"))
        XCTAssertTrue(lines.contains("look-elsewhere: 3 of 40 tested"))
        XCTAssertTrue(lines.contains { $0.contains("Al+Al sum?") && $0.contains("sum peak or Ar") })
        XCTAssertFalse(ElementsSection.showsDetails(outcome()), "nothing said: no disclosure")
    }

    /// The Found row's tip is the definition and the help only: the reasons it used to carry are now on screen.
    /// Mutation: `foundHover` appends `notes(...)` again - red.
    func testFoundHoverNoLongerCarriesTheReasons() {
        let o = outcome(reasons: ["Cu: a very particular reason"], notes: ["a very particular note"])
        let tip = ElementsSection.foundHover(o, locale: Locale(identifier: "en_US"))
        XCTAssertFalse(tip.contains("a very particular"))
        XCTAssertTrue(tip.contains(ElementsSection.foundHelp) && tip.contains("Currie"))
    }

    /// The row sentence under a results row: the failure, else the conflict note, else nothing; the icon's tip is a short kind.
    /// Mutation: `rowNote` prefers the conflict over the failure, or `rowNoteKind` returns the sentence - red.
    func testResultRowNotePrefersTheFailureAndTheIconTipIsShort() {
        var row = ResultRow(z: 12, netCounts: 27, netSigma: 10, kFreeRatio: 0.06, kFreeSigma: 0.02, atPercent: 0, atSigma: 0,
                            wtPercent: 0, wtSigma: 0, sigmaTerms: "")
        XCTAssertNil(ResultsSection.rowNote(row))
        row.conflictNote = "background overlaps Si Kα"
        XCTAssertEqual(ResultsSection.rowNote(row), "background overlaps Si Kα")
        row.failure = "no line on the axis"
        XCTAssertEqual(ResultsSection.rowNote(row), "no line on the axis")
        XCTAssertEqual(ResultsSection.rowNoteKind(row), "Fit failed")
        row.failure = nil
        XCTAssertEqual(ResultsSection.rowNoteKind(row), "Fit note")
        XCTAssertLessThan(ResultsSection.rowNoteKind(row).count, (row.conflictNote ?? "").count)
    }

    // MARK: Row 2 - fixed, distinct hues

    /// The region, the model, the background and the pins are four different fixed hues, none the accent colour (which the person
    /// sets and which a selection also uses); the Spectrum chip is the region's colour while a region is shown.
    /// Mutation: `liveRegionColor` = `Color.accentColor`, or `CurveLayer.modelHue` = the region colour - red.
    func testTheCurvesAndTheRegionAreDistinctFixedHues() {
        let region = SpectroscopyRoomModel.liveRegionColor
        XCTAssertNotEqual(region, Color.accentColor)
        let hues: [Color] = [region, CurveLayer.modelHue, CurveLayer.backgroundHue, CurveLayer.pins.color]
        for (i, a) in hues.enumerated() { for b in hues[(i + 1)...] { XCTAssertNotEqual(a, b) } }
        XCTAssertNotEqual(CurveLayer.modelHue, Color.accentColor)
    }

    /// A chip is lit in the colour its curve is drawn in.
    /// Mutation: `CurveLayer.color(role:)` ignores the role for `.spectrum` - red.
    func testTheSpectrumChipFollowsTheCurveColour() {
        XCTAssertEqual(CurveLayer.spectrum.color(role: .region), SpectrumInteraction.curveColor(.region))
        XCTAssertEqual(CurveLayer.spectrum.color(role: .wholeMap), Color.primary)
        XCTAssertEqual(CurveLayer.model.color(role: .region), CurveLayer.modelHue)
        let chips = SpectrumLayersSection.curveChips(role: .region)
        XCTAssertEqual(chips.first { $0.id == .spectrum }?.symbolColor, SpectroscopyRoomModel.liveRegionColor)
        XCTAssertEqual(chips.first { $0.id == .model }?.symbolColor, CurveLayer.modelHue)
    }

    // MARK: Row 3 - the region typed, and the pointer

    private let grid = (w: 64, h: 48)
    private func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> SpectrumRegionShape { .rectangle(PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)) }

    /// x and y move the region by whole pixels and keep its size; at the grid's edge it stops.
    /// Mutation: `.x` resizes instead of moving (uses the `.right` handle), or the `moved` clamp is dropped - red.
    func testTypingXOrYMovesTheRegionAndStopsAtTheEdge() {
        let r = rect(10, 8, 30, 20)
        XCTAssertEqual(RegionExtent.edited(r, .x, to: 15, grid: grid), rect(15, 8, 35, 20))
        XCTAssertEqual(RegionExtent.edited(r, .y, to: 0, grid: grid), rect(10, 0, 30, 12))
        XCTAssertEqual(RegionExtent.edited(r, .x, to: 500, grid: grid), rect(44, 8, 64, 20), "stops at the right edge, size kept")
        XCTAssertEqual(RegionExtent.edited(r, .y, to: -9, grid: grid), rect(10, 0, 30, 12))
    }

    /// Width and height move the far edge, at least one pixel, inside the grid; the origin stays.
    /// Mutation: the `max(value, 1)` floor removed (0 flips the rectangle) or width moves the left edge - red.
    func testTypingWidthOrHeightResizesWithTheDragsRules() {
        let r = rect(10, 8, 30, 20)
        XCTAssertEqual(RegionExtent.edited(r, .width, to: 5, grid: grid), rect(10, 8, 15, 20))
        XCTAssertEqual(RegionExtent.edited(r, .height, to: 40, grid: grid), rect(10, 8, 30, 48), "kept in the grid")
        XCTAssertEqual(RegionExtent.edited(r, .width, to: 0, grid: grid), rect(10, 8, 11, 20), "at least one pixel")
        XCTAssertEqual(RegionExtent.edited(r, .height, to: -3, grid: grid), rect(10, 8, 30, 9))
        XCTAssertEqual(RegionExtent.edited(.ellipse(PixelRect(x0: 2, y0: 2, x1: 12, y1: 12)), .width, to: 4, grid: grid),
                       .ellipse(PixelRect(x0: 2, y0: 2, x1: 6, y1: 12)), "an ellipse keeps its kind")
    }

    /// A polygon is read, not typed; a value that changes nothing is no edit.
    /// Mutation: `isEditable` true for `.polygon`, or the `out == shape` check removed - red.
    func testAPolygonIsReadOnlyAndAnUnchangedValueIsNoEdit() {
        let poly = SpectrumRegionShape.polygon([PixelPoint(x: 3, y: 4), PixelPoint(x: 13, y: 4), PixelPoint(x: 8, y: 14)])
        XCTAssertFalse(RegionExtent.isEditable(poly))
        XCTAssertNil(RegionExtent.edited(poly, .x, to: 9, grid: grid))
        XCTAssertEqual(RegionExtent.values(poly).width, 10)
        XCTAssertEqual(RegionSection.extentText(poly), "x 3 \u{00B7} y 4 \u{00B7} 10 \u{00D7} 10 px")
        XCTAssertNil(RegionExtent.edited(rect(10, 8, 30, 20), .width, to: 20, grid: grid))
    }

    /// A typed value reaches the controller as a final edit, exactly once; with no region nothing is sent.
    /// Mutation: `commit` sends `final: false`, or sends without the `edited` check - red.
    func testACommittedValueIsAFinalRegionEdit() {
        let m = SpectroscopyRoomModel.fixture
        var seen: [(SpectrumRegionShape, Bool)] = []
        m.onRegionEdit = { seen.append(($0, $1)) }
        m.regionOutline = nil
        RegionSection.commit(m, .width, 7)
        XCTAssertTrue(seen.isEmpty, "no live region, no edit")
        let g = m.gridSize
        m.regionOutline = .rectangle(PixelRect(x0: 1, y0: 1, x1: min(g.w, 9), y1: min(g.h, 9)))
        RegionSection.commit(m, .width, 3)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, .rectangle(PixelRect(x0: 1, y0: 1, x1: 4, y1: min(g.h, 9))))
        XCTAssertEqual(seen.first?.1, true)
    }

    /// The cursor comes from the hit the drag uses: a handle resizes, the inside moves, outside is the arrow; a handle's side is the
    /// frame-resize position of that side.
    /// Mutation: `.inside` maps to nil, or two sides swapped in `framePosition` - red.
    func testThePointerFollowsTheHitTest() {
        XCTAssertEqual(RegionExtent.pointer(for: .inside), .move)
        XCTAssertNil(RegionExtent.pointer(for: .outside))
        XCTAssertEqual(RegionExtent.pointer(for: .handle(.topLeft)), .resize(.topLeft))
        let sides: [(RegionHandle, FrameResizePosition)] = [
            (.topLeft, .topLeading), (.top, .top), (.topRight, .topTrailing), (.right, .trailing),
            (.bottomRight, .bottomTrailing), (.bottom, .bottom), (.bottomLeft, .bottomLeading), (.left, .leading)]
        for (h, p) in sides { XCTAssertEqual(MapTileView.framePosition(h), p) }
        XCTAssertNil(MapTileView.framePosition(.vertex(2)))
        XCTAssertNil(MapTileView.pointerStyle(nil, dragging: false))
        XCTAssertNotNil(MapTileView.pointerStyle(.move, dragging: true))
    }
}
