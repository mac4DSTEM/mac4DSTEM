import AppKit
import SwiftUI
import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Spec 2 lane D (2026-10-06 night): the inspector's six sections, Auto ID's Picked row, the periodic table in the table's own shape
/// with its Lines energies, the Results badge, and the Export section's three buttons.
@MainActor
final class SpectroscopySpec2DTests: XCTestCase {
    private func model() -> SpectroscopyRoomModel {
        SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1], background: [], model: [], overlay: nil))
    }

    // MARK: sections

    /// D-5: Elements, Region, Results, Quantification, Fitting, Export, in that order; Map display and Expert are gone.
    /// Mutation: two cases of `Part` swapped (Region before Elements) - red.
    func testTheInspectorHasSixSectionsInOrder() {
        XCTAssertEqual(SpectroscopyInspectorSections.Part.allCases.map(\.title),
                       ["Elements", "Region", "Results", "Quantification", "Fitting", "Export"])
    }

    // MARK: Auto ID

    private func outcome(_ zs: [Int], notes: [String] = []) -> AutoIDOutcome {
        AutoIDOutcome(region: "r", suggestions: zs.map { ElementSuggestion(z: $0, reason: "reason \($0)") },
                      suspects: [AutoIDSuspect(label: "Tm+Tm sum? (or Ar K\u{03B1})", energy: 2.96, question: "a sum-peak question")],
                      notTested: [AutoIDRefusal(element: "C", reason: "below the lowest tested line")], notes: notes)
    }

    /// The Picked row lists the outcome's suggestions in the outcome's order, whatever the picks are now.
    /// Mutation: the list sorted by Z (Mg, Al, Si) - red.
    func testPickedListsTheOutcomesElementsInItsOrder() {
        XCTAssertEqual(ElementsSection.pickedList(outcome([13, 14, 12])), "Al, Si, Mg")
        XCTAssertEqual(ElementsSection.pickedList(outcome([])), "none")
    }

    /// Its hover keeps every reason, the sum-peak question, the not-tested entry and the proposer's notes.
    /// Mutation: `notes` drops the suspects line - red.
    func testPickedHoverCarriesEveryReasonQuestionAndRefusal() {
        let o = outcome([13, 14], notes: ["a look-elsewhere note"])
        let t = ElementsSection.notes(o, o.suggestions)
        for part in ["Al: reason 13", "Si: reason 14", "Tm+Tm sum? (or Ar K\u{03B1}) a sum-peak question", "Not tested: C (below the lowest tested line)", "a look-elsewhere note"] {
            XCTAssertTrue(t.contains(part), "missing \(part) in: \(t)")
        }
    }

    // MARK: Lines menu

    /// "K · Kα 1.487 · Kβ 1.560 keV" for Al, computed from the line table here too (never a literal the table has not given).
    /// Mutation: the beta line taken from the first line of the family instead of the Kb line (or 2 decimals) - red.
    func testLinesTitleListsAlphaAndBetaWithThreeDecimals() throws {
        let al = XRayLines.lines(of: "Al")
        let ka = try XCTUnwrap(al.first { $0.name == "Ka" }), kb = try XCTUnwrap(al.first { $0.name == "Kb" })
        XCTAssertEqual(ElementLines.title(family: .K, z: 13),
                       "K \u{00B7} K\u{03B1} \(String(format: "%.3f", ka.energy)) \u{00B7} K\u{03B2} \(String(format: "%.3f", kb.energy)) keV")
        XCTAssertTrue(try XCTUnwrap(ElementLines.title(family: .K, z: 13)).hasPrefix("K \u{00B7} K\u{03B1} 1.48"))
        // A family the table has no line for is nil (the entry is disabled); so is an element with no lines at all.
        XCTAssertNil(ElementLines.title(family: .L, z: 13))
        XCTAssertNil(ElementLines.title(family: .K, z: 1))
        // Cu has all three families' alpha lines; the L family reads La and Lb1.
        let cu = XRayLines.lines(of: "Cu")
        let la = try XCTUnwrap(cu.first { $0.name == "La" }), lb = try XCTUnwrap(cu.first { $0.name == "Lb1" })
        XCTAssertEqual(ElementLines.title(family: .L, z: 29),
                       "L \u{00B7} L\u{03B1} \(String(format: "%.3f", la.energy)) \u{00B7} L\u{03B2} \(String(format: "%.3f", lb.energy)) keV")
    }

    // MARK: grid

    /// D-9: 18 columns, periods 1 to 6, Al in period 3 group 13, the lanthanide slot empty in period 6 column 3, the fold unchanged,
    /// every element once between the grid and the fold.
    /// Mutation: one `nil` dropped from period 2 (17 columns) - red.
    func testTheGridHas18ColumnsAnd6RowsWithAlWhereThePTEHasIt() {
        let rows = PeriodicTableGrid.rows
        XCTAssertEqual(rows.count, 6)
        for (i, r) in rows.enumerated() { XCTAssertEqual(r.count, 18, "period \(i + 1)") }
        XCTAssertEqual(rows[2][12], 13, "Al")
        XCTAssertEqual(rows[1][12], 5, "B above it")
        XCTAssertEqual(rows[0][0], 1); XCTAssertEqual(rows[0][17], 2)
        XCTAssertNil(rows[5][2], "the lanthanide slot is the fold's place")
        XCTAssertEqual(rows[5][3], 72, "Hf")
        XCTAssertEqual(PeriodicLayout.folded, Array(57...71) + Array(87...118), "the fold is unchanged")
        let grid = rows.joined().compactMap { $0 }
        XCTAssertEqual(grid.count, Set(grid).count, "no element twice")
        XCTAssertEqual((grid + PeriodicLayout.folded).sorted(), Array(1...118), "every element once, in the grid or the fold")
    }

    /// D-9: cell = (width - 17 gaps) / 18 at gap 2; the symbol is half the cell, 9 to 13 pt.
    /// Mutation: the gap factor 17 changed to 18 - red; the clamp's floor 9 changed to 10 - red.
    func testCellAndSymbolSizeFollowTheRule() {
        XCTAssertEqual(PeriodicTableGrid.cellSize(width: 248), 214.0 / 18, accuracy: 1e-9)
        XCTAssertEqual(PeriodicTableGrid.cellSize(width: 400), 366.0 / 18, accuracy: 1e-9)
        XCTAssertEqual(PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: 248)), 9, "0.5 x 11.9 is under the floor")
        XCTAssertEqual(PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: 400)), 366.0 / 36, accuracy: 1e-9)
        XCTAssertEqual(PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: 1000)), 13, "the ceiling")
    }

    /// The laid-out table fills any width it is offered, at or above 248 pt (and asks for no more than 248 when offered none).
    /// Mutation: the layout answers its ideal width whatever is proposed - red at 400.
    func testTheTableFillsTheWidthItIsGiven() {
        let host = NSHostingController(rootView: PeriodicTableView(model: model()))
        for w in [248.0, 400.0] {
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: w, height: 10_000)).width, w, accuracy: 0.5, "at \(w)")
        }
        let narrow = host.sizeThatFits(in: CGSize(width: 1, height: 10_000)).width
        XCTAssertLessThanOrEqual(narrow, 248, "the minimum width")
        let h248 = host.sizeThatFits(in: CGSize(width: 248, height: 10_000)).height
        let h400 = host.sizeThatFits(in: CGSize(width: 400, height: 10_000)).height
        XCTAssertGreaterThan(h400, h248, "wider, taller cells")
    }

    // MARK: Results

    /// The badge row of Results: a fit that is unvalidated shows it; before a fit, or once validated, it does not.
    /// Mutation: `showsBadge` ignores `hasFit` - red.
    func testTheResultsBadgeFollowsTheFitAndTheValidation() {
        let m = model()
        m.hasFit = true; m.validation = "none"
        XCTAssertTrue(ResultsSection.showsBadge(m))
        m.hasFit = false
        XCTAssertFalse(ResultsSection.showsBadge(m))
        m.hasFit = true; m.validation = "passed on a dataset with truth"
        XCTAssertFalse(ResultsSection.showsBadge(m))
    }

    /// The honesty label of the at% column is the same words as before the move.
    /// Mutation: the label constant reworded - red.
    func testNoAbsorptionLabelKeepsItsWords() {
        XCTAssertEqual(ResultFormat.noAbsorptionLabel, "\u{00B7} no absorption")
        XCTAssertEqual(ResultFormat.abundanceHeader(unit: .atomic, noAbsorption: true), "at% \u{00B1} \u{03C3} " + ResultFormat.noAbsorptionLabel)
    }

    // MARK: Export

    /// D-14: Results CSV and Method JSON wait for the fit; Spectrum CSV needs only a shown spectrum, and is named "<stem>-spectrum".
    /// Mutation: the spectrum name built with "-method", or `spectrumExport` also waiting for the fit's csv - red.
    func testExportButtonsHandOutWhatExistsAndNameIt() throws {
        var e = ExportSettings()
        e.fileStem = "Al-Mg-Si"
        XCTAssertNil(ExportSection.resultsExport(e)); XCTAssertNil(ExportSection.methodExport(e)); XCTAssertNil(ExportSection.spectrumExport(e))
        e.spectrumCSV = "energy_keV,counts\n0.0,1\n"
        XCTAssertNil(ExportSection.resultsExport(e), "no fit yet")
        let s = try XCTUnwrap(ExportSection.spectrumExport(e))
        XCTAssertEqual(s, PendingExport(text: "energy_keV,counts\n0.0,1\n", isJSON: false, name: "Al-Mg-Si-spectrum"))
        e.csv = "a,b"; e.methodJSON = "{}"
        XCTAssertEqual(ExportSection.resultsExport(e), PendingExport(text: "a,b", isJSON: false, name: "Al-Mg-Si"))
        XCTAssertEqual(ExportSection.methodExport(e), PendingExport(text: "{}", isJSON: true, name: "Al-Mg-Si-method"))
        XCTAssertEqual([ExportSection.csvTitle, ExportSection.jsonTitle, ExportSection.spectrumTitle],
                       ["Results CSV\u{2026}", "Method JSON\u{2026}", "Spectrum CSV\u{2026}"])
    }
}
