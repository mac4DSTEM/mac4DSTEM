import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// UX lane DE: the quant panel's one voice, the Fit inspector's wording, the periodic table's size.
final class SpectroscopyUXDETests: XCTestCase {
    /// #7: the stale "Quantify inspector" text is gone; an applied note and other refusals keep their meaning.
    func testAbsorptionNoteIsOneShortTruthfulLine() {
        XCTAssertEqual(QuantifyPresentation.absorptionNoteText("not applied: no thickness is typed (nm): type one in the Quantify inspector"),
                       "Off: no thickness typed.")
        XCTAssertEqual(QuantifyPresentation.absorptionNoteText("not applied: the mass-absorption table is not available"),
                       "Off: the mass-absorption table is not available")
        XCTAssertEqual(QuantifyPresentation.absorptionNoteText("4 detectors \u{00B7} TOA from file"), "4 detectors \u{00B7} TOA from file")
        XCTAssertNil(QuantifyPresentation.absorptionNoteText(nil))
    }

    /// #6: the Fit quality value keeps the fit's number verbatim and only turns "(Pearson)" into "· Pearson".
    func testFitQualityValueKeepsTheNumber() {
        XCTAssertEqual(QuantifyPresentation.fitQualityValue("\u{03C7}\u{00B2}\u{1D63} 3318 (Pearson)"), "\u{03C7}\u{00B2}\u{1D63} 3318 \u{00B7} Pearson")
        XCTAssertEqual(QuantifyPresentation.fitQualityValue("\u{03C7}\u{00B2}\u{1D63} 1.04 (Pearson)"), "\u{03C7}\u{00B2}\u{1D63} 1.04 \u{00B7} Pearson")
        XCTAssertEqual(QuantifyPresentation.fitQualityValue("reduced deviance 1.02"), "reduced deviance 1.02")
    }

    /// #7: provenance moves from a caption in the row to the field's help.
    func testBeamEnergyProvenanceIsTheHelp() {
        XCTAssertEqual(QuantifyPresentation.beamEnergyHelp("from the file"), "Beam energy, from the file")
        XCTAssertEqual(QuantifyPresentation.beamEnergyHelp(nil), "Beam energy")
    }

    /// Spec 2 D-9 (was #9, ADR 056's 22-pt cells): the table scales with the width and never asks for more than the inspector's
    /// narrowest content column, 248 pt, nor sets a symbol under 9 pt.
    /// Mutation: `PeriodicTableGrid.minimumWidth` raised to 300 - red.
    func testPeriodicTableFitsTheNarrowestColumnAndScales() {
        XCTAssertLessThanOrEqual(PeriodicTableGrid.minimumWidth, 248)
        XCTAssertEqual(PeriodicTableGrid.cellSize(width: 248), (248 - 17 * 2) / 18, accuracy: 1e-9)
        XCTAssertEqual(PeriodicTableGrid.cellSize(width: 400), (400 - 17 * 2) / 18, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: 248)), 9)
    }
}
