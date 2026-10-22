import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
@testable import mac4DSTEM

/// Lane S (UI audit 2026-10-14, Spectroscopy rows): every test names the mutation that turns it red.
@MainActor
final class SpectroscopyLaneSTests: XCTestCase {

    // MARK: Row 1 - caveats are read, not hovered

    private func outcome(reasons: [String] = [], notes: [String] = [], suspects: [AutoIDSuspect] = []) -> AutoIDOutcome {
        AutoIDOutcome(region: "r", suggestions: reasons.enumerated().map { ElementSuggestion(z: 29 + $0.offset, reason: $0.element) },
                      suspects: suspects, notTested: [], notes: notes)
    }

    /// `showsDetails` is true exactly when the proposer said something; `noteLines` holds every line of it (now the Found row's tip).
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

    /// The Found row's tip is the definition, the help and, since the workspace alignment (2026-10-22: no walls of text in a
    /// disclosure), the proposer's reasons and notes, which the Details disclosure used to show.
    /// Mutation: `foundHover` drops the reasons - red.
    func testFoundHoverCarriesTheDefinitionTheHelpAndTheReasons() {
        let o = outcome(reasons: ["Cu: a very particular reason"], notes: ["a very particular note"])
        let tip = ElementsSection.foundHover(o, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(tip.contains("a very particular reason") && tip.contains("a very particular note"))
        XCTAssertTrue(tip.contains(ElementsSection.foundHelp) && tip.contains("Currie"))
        XCTAssertFalse(ElementsSection.foundHover(outcome(), locale: Locale(identifier: "en_US")).hasSuffix("\n"), "no trailing blank when nothing was said")
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
        XCTAssertEqual(RegionExtent.edited(r, .width, to: -3, grid: grid), rect(10, 8, 11, 20), "a negative width does not flip the rectangle")
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

    // MARK: Row 4 - the right-click choices as rows

    /// A click selects the element (and flips its role as before); an element that cannot be picked is not selected, and a
    /// selection that has become unavailable shows no rows.
    /// Mutation: `pick` skips the `isAvailable` guard, or no longer calls `click` - red.
    func testClickingACellSelectsItAndAnUnavailableOneIsNotSelected() {
        let m = SpectroscopyRoomModel.fixture
        m.elements = ElementSelection()
        m.selectedElement = nil
        PeriodicTableView.pick(m, 29)
        XCTAssertEqual(m.selectedElement, 29)
        XCTAssertEqual(m.elements.role(29), .quantify, "the click still flips the role")
        XCTAssertEqual(SelectedElementRows.shown(m), 29)
        PeriodicTableView.pick(m, 2)   // He: no usable line at this window
        XCTAssertEqual(m.selectedElement, 29, "an unavailable cell does not take the selection")
        m.selectedElement = 2
        XCTAssertNil(SelectedElementRows.shown(m))
        m.selectedElement = nil
        XCTAssertNil(SelectedElementRows.shown(m))
    }

    /// The rows reach what the menu reaches: Fit only and a line family land in the same selection state; the summary names a
    /// chosen family.
    /// Mutation: `linesSummary` always "Default" - red.
    func testTheRowsChooseFitOnlyAndALineFamily() {
        let m = SpectroscopyRoomModel.fixture
        m.elements = ElementSelection()
        PeriodicTableView.pick(m, 29)
        m.elements.set(29, .fitOnly)
        XCTAssertEqual(m.elements.role(29), .fitOnly)
        XCTAssertEqual(SelectedElementRows.linesSummary(m, 29), "Default")
        m.elements.setFamily(29, .L)
        XCTAssertTrue(SelectedElementRows.linesSummary(m, 29).hasPrefix("L"))
        m.elements.resetLines(29)
        XCTAssertEqual(SelectedElementRows.linesSummary(m, 29), "Default")
    }

    // MARK: Row 5 - the menu bar and the inspector share one rule

    private func pinned(_ id: Int) -> PinnedRegion {
        PinnedRegion(id: id, label: "p\(id)", tint: .pink, shape: nil, pixels: 1, spectrum: [1], sourceRegion: nil)
    }

    /// The room's menu items exist only in the Spectroscopy room, with a spectrum image behind it.
    /// Mutation: `showsItems` ignores the area, or ignores the image - red.
    func testTheRoomsMenuItemsShowOnlyInTheRoomWithAnImage() {
        XCTAssertTrue(SpectroscopyMenuRule.showsItems(area: .spectroscopy, hasSpectrumImage: true))
        XCTAssertFalse(SpectroscopyMenuRule.showsItems(area: .spectroscopy, hasSpectrumImage: false))
        for area in WorkspaceArea.allCases where area != .spectroscopy {
            XCTAssertFalse(SpectroscopyMenuRule.showsItems(area: area, hasSpectrumImage: true), "\(area)")
        }
    }

    /// Each export is on exactly when its inspector button is: results and method after Quantify, the spectrum once one is shown,
    /// the maps once a tile exists. Doing a disabled one changes nothing; an enabled one hands the panel its text, or asks for the folder.
    /// Mutation: `canExportResults` tests `methodJSON`, `exportSpectrum` loses its guard, or `exportMaps` sets nothing - red.
    func testEachExportIsOnWhenItsInspectorButtonIsAndDoesWhatItDoes() {
        let m = SpectroscopyRoomModel.fixture
        m.tiles = []; m.export = ExportSettings()
        for on in [SpectroscopyMenuRule.canExportResults(m), SpectroscopyMenuRule.canExportMethod(m),
                   SpectroscopyMenuRule.canExportSpectrum(m), SpectroscopyMenuRule.canExportMaps(m)] { XCTAssertFalse(on) }
        SpectroscopyMenuRule.exportResults(m); SpectroscopyMenuRule.exportMethod(m)
        SpectroscopyMenuRule.exportSpectrum(m); SpectroscopyMenuRule.exportMaps(m)
        XCTAssertNil(m.pendingExport); XCTAssertFalse(m.pickingMapsFolder)

        m.export.csv = "a,b"
        XCTAssertTrue(SpectroscopyMenuRule.canExportResults(m)); XCTAssertFalse(SpectroscopyMenuRule.canExportMethod(m))
        SpectroscopyMenuRule.exportResults(m)
        XCTAssertEqual(m.pendingExport, ExportSection.resultsExport(m.export))
        XCTAssertEqual(m.pendingExport?.isJSON, false)
        m.pendingExport = nil
        m.export.methodJSON = "{}"
        SpectroscopyMenuRule.exportMethod(m)
        XCTAssertEqual(m.pendingExport?.isJSON, true)
        m.pendingExport = nil

        m.export.spectrumOf = SpectrumLabel(imageName: "img", regionName: "Whole map")
        XCTAssertEqual(SpectroscopyMenuRule.canExportSpectrum(m), ExportSection.canExportSpectrum(m.export))
        SpectroscopyMenuRule.exportSpectrum(m)
        XCTAssertTrue(m.pendingExport?.name.hasSuffix("-spectrum") == true)

        m.tiles = [MapTile.synthetic(z: 13)]
        XCTAssertTrue(SpectroscopyMenuRule.canExportMaps(m))
        SpectroscopyMenuRule.exportMaps(m)
        XCTAssertTrue(m.pickingMapsFolder)
    }

    /// Pin needs the controller's hook and fewer than three pins; the menu does what the button does.
    /// Mutation: the limit compares `>` instead of `>=`, or `pin` calls `onPin` with no guard - red.
    func testPinIsOnWithAHookAndRoomForAnother() {
        let m = SpectroscopyRoomModel.fixture
        var calls = 0
        m.onPin = nil; m.pins = []
        XCTAssertFalse(SpectroscopyMenuRule.canPin(m))
        SpectroscopyMenuRule.pin(m)
        m.onPin = { calls += 1 }
        XCTAssertTrue(SpectroscopyMenuRule.canPin(m))
        SpectroscopyMenuRule.pin(m)
        XCTAssertEqual(calls, 1)
        m.pins = (1...SpectroscopyRoomModel.maximumPins).map(pinned)
        XCTAssertFalse(SpectroscopyMenuRule.canPin(m))
        SpectroscopyMenuRule.pin(m)
        XCTAssertEqual(calls, 1, "three pinned: the menu item refuses as the button does")
    }

    // MARK: Row 6 - locale-aware decimals in the results cells

    /// In en_US every cell is character for character what `String(format:)` printed before, ties included; in de_DE the same
    /// digits take a comma and no period survives; the record locale keeps today's text on every Mac.
    /// Mutation: `number` formats without the locale (de_DE keeps a period), or through `String(format:locale:)` / a FormatStyle (a
    /// tie such as 0.35 rounds differently from `%.1f`: measured) - red.
    func testResultCellsKeepTheirDigitsAndTakeTheLocalesSeparator() {
        let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        for (v, s) in [(88.1, 0.9), (0.25, 0.35), (1.005, 2.675), (97.65, 0.05), (0.0, 0.0), (100.0, 1.25), (-0.15, 12.349)] {
            let before = String(format: "%.1f \u{00B1} %.1f", v, s)
            XCTAssertEqual(ResultFormat.plusMinus(v, s, digits: 1, locale: en), before)
            XCTAssertEqual(ResultFormat.plusMinus(v, s, digits: 1, locale: de), before.replacingOccurrences(of: ".", with: ","))
            XCTAssertEqual(ResultFormat.plusMinus(v, s, digits: 1, locale: ResultFormat.recordLocale), before)
        }
        var row = ResultRow(z: 12, netCounts: 27, netSigma: 10, kFreeRatio: 0.0239, kFreeSigma: 0.0003, atPercent: 5.6, atSigma: 1.1,
                            wtPercent: 4.5, wtSigma: 0.9, sigmaTerms: "")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: en).abundance, "5.6 \u{00B1} 1.1")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: de).abundance, "5,6 \u{00B1} 1,1")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .weight, hasFit: true, locale: de).abundance, "4,5 \u{00B1} 0,9")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: en).kFree, "0.0239 \u{00B1} 0.0003")
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: de).kFree, "0,0239 \u{00B1} 0,0003")
        row.kFreeSigma = nil
        XCTAssertEqual(ResultFormat.fitCells(row, unit: .atomic, hasFit: true, locale: de).kFree, "1", "the reference reads 1")
        let ratio = RatioLine(label: "Mg / Si net ratio", value: 1.092, sigma: 0.021, note: "")
        XCTAssertEqual(ResultFormat.ratio(ratio, locale: en), "1.092 \u{00B1} 0.021")
        XCTAssertEqual(ResultFormat.ratio(ratio, locale: de), "1,092 \u{00B1} 0,021")
    }

    // MARK: Row 7 - no work-package names in user text

    /// The unregistered note speaks plainly (no "WP3"), appears only beside a 4D cube, and is one string for both places that show it.
    /// Mutation: the old sentence restored, or the note returned without a cube - red.
    func testTheUnregisteredNoteNamesNoWorkPackage() {
        let note = SpectroscopyPlaceholderFormat.registrationNote(hasFourDCube: true)
        XCTAssertEqual(note, SpectroscopyPlaceholderFormat.unregisteredNote)
        XCTAssertFalse(note?.contains("WP") ?? true)
        XCTAssertNil(SpectroscopyPlaceholderFormat.registrationNote(hasFourDCube: false))
    }

    // MARK: Row 8 - no bare Buttons beside the glass ones

    /// A source contract in the manner of `run-tests.sh inventory`: in the Spectroscopy inspector file every action button is an
    /// `InspectorAdaptiveButton` (glass); the only plain `Button(` left are the k-table's Edit… and Done, Pin in its labelled row. A new bare button must be named here on purpose.
    /// Mutation: `InspectorAdaptiveButton(Self.csvTitle` turned back into `Button(Self.csvTitle` - red.
    func testTheInspectorsActionButtonsAreGlass() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM/UI/Spectroscopy/SpectroscopyInspectors.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let allowed = ["Edit\\u{2026}", "Done", "Pin"]
        let bare = source.split(separator: "\n").map(String.init).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("//"), let r = t.range(of: "Button(") else { return false }
            let before = t[t.startIndex..<r.lowerBound]
            return !before.hasSuffix("Adaptive")
        }.filter { line in !allowed.contains { line.contains("Button(\"\($0)\"") } }
        XCTAssertEqual(bare, [], "bare Button(s) in the Spectroscopy inspector")
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "InspectorAdaptiveButton(").count - 1, 7)
    }
}
