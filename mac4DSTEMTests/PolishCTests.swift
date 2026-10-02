//
//  PolishCTests.swift
//  Lane C (Slot 4½ polish, 2026-10-02): the text of Prepare's calibration rows.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class PolishCTests: XCTestCase {
    /// "[pix]" (a bullseye file's own spelling) is a pixel unit and shows as "px".
    func testBracketPixIsAPixelUnitShownAsPx() {
        for spelling in ["[pix]", "pix", "[px]", "px", "Pixels"] {
            XCTAssertTrue(CalibrationUnitConversion.isPixelUnit(spelling), spelling)
            XCTAssertEqual(CalibrationUnitConversion.displayLabel(spelling), "px", spelling)
        }
        // Physical spellings are untouched, and "[pix]" is still not a physical unit.
        XCTAssertEqual(CalibrationUnitConversion.displayLabel("1/nm"), "nm⁻¹")
        XCTAssertFalse(CalibrationUnitConversion.isPhysicalReciprocalUnit("[pix]"))
        let calibration = Calibration(qPixelSize: 1, qPixelUnits: "[pix]")
        let report = CalibrationReadinessReport.make(calibration: calibration, provenance: CalibrationProvenance())
        let q = report.items.first { $0.kind == .qScale }
        XCTAssertEqual(q?.detail, "Reciprocal dimensions remain in pixels (1 px/px)")
    }

    /// The scale subtitle uses the reader's decimal separator.
    func testDisplayNumberFollowsTheLocale() {
        let de = Locale(identifier: "de_DE")
        XCTAssertEqual(CalibrationUnitConversion.displayNumber(0.25, locale: de), "0,25")
        XCTAssertEqual(CalibrationUnitConversion.displayNumber(0.25, locale: Locale(identifier: "en_US")), "0.25")
        XCTAssertEqual(CalibrationUnitConversion.displayNumber(1234.5, locale: de), "1234,5", "no grouping")
    }

    /// a and b carry px; θ never prints a negative zero.
    func testEllipseSummaryHasUnitsAndNoNegativeZero() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(CalibrationUnitConversion.ellipseSummary(a: 23.75, b: 21.71, thetaDegrees: 47.4, locale: en),
                       "a 23.75 px · b 21.71 px · θ 47.4°")
        XCTAssertEqual(CalibrationUnitConversion.ellipseSummary(a: 20, b: 19, thetaDegrees: -0.01, locale: en),
                       "a 20 px · b 19 px · θ 0.0°")
        XCTAssertTrue(CalibrationUnitConversion.ellipseSummary(a: 23.75, b: 21.71, thetaDegrees: 1,
                      locale: Locale(identifier: "de_DE")).hasPrefix("a 23,75 px"))
    }
}
