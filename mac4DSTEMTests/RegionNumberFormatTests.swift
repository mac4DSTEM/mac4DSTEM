//
//  RegionNumberFormatTests.swift
//  On-screen numbers follow the Mac's Region. Seen on a Mac with a decimal comma (5.3.0 walk): "1,65 ± 0,34" in Spectroscopy
//  and "1.7 ± 0.3" for the same fit in Results, "3,072 positions" beside "63,5 px", "θ 103.8°" beside "a 16,97 px", and
//  "Cu 0.2 ± 0.0 at%". A record, an export and the agent door keep the C spelling.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class RegionNumberFormatTests: XCTestCase {
    private let german = Locale(identifier: "de_DE"), american = Locale(identifier: "en_US")

    func testACountIsGroupedAsTheRegionGroupsIt() {
        XCTAssertEqual(CalibrationUnitConversion.displayCount(29_964, locale: german), "29.964")
        XCTAssertEqual(CalibrationUnitConversion.displayCount(29_964, locale: american), "29,964")
        XCTAssertEqual(CalibrationUnitConversion.displayCount(151, locale: german), "151")
    }

    func testAnAngleCarriesTheRegionsDecimalMark() {
        XCTAssertEqual(RQRotationConvention.degreesText(103.8, locale: german), "103,8°")
        XCTAssertEqual(RQRotationConvention.degreesText(103.8, locale: american), "103.8°")
        XCTAssertEqual(RQRotationConvention.degreesText(-0.04, locale: german), "0,0°", "a value that rounds to zero is still plain zero")
        // The detector ellipse's line, as the status bar prints it once a distortion is applied: one mark throughout.
        XCTAssertEqual(CalibrationUnitConversion.ellipseSummary(a: 16.97, b: 16.15, thetaDegrees: 103.8, locale: german),
                       "a 16,97 px · b 16,15 px · θ 103,8°")
    }

    /// The value follows its σ: two significant digits of σ, the value to the same place. A σ of 0.042 no longer reads "± 0.0".
    func testAValueAndItsSigmaAreWrittenByTheTablesRule() {
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(1.6512, 0.3391, locale: american), "1.65 \u{00B1} 0.34")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(96.412, 0.4801, locale: german), "96,41 \u{00B1} 0,48")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(0.1803, 0.0421, locale: american), "0.180 \u{00B1} 0.042")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(51.5, 5.2, locale: american), "51.5 \u{00B1} 5.2")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(51.5, 12.0, locale: american), "52 \u{00B1} 12")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(0.2, 0.000001, locale: german), "0,2000 \u{00B1} < 0,0001", "never a σ of zero")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(0.2, nil, locale: american), "0.2")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(0.2, 0, locale: american), "0.2")
        XCTAssertEqual(CalibrationUnitConversion.plusMinus(0.1803, 0.0421, locale: nil), "0.180 \u{00B1} 0.042", "the record's spelling")
    }

    /// The record keeps the C spelling; Results shows it with the Region's mark. Mutation: the row returns the stored text - red.
    func testResultsShowsARecordedQuantificationWithTheRegionsMark() {
        let replay = SessionReplay()
        SpectroscopySession().recordQuantification(in: replay, regionKind: "wholeMap", regionName: "Whole map", extra: [
            "result_at": "Mg 1.65 \u{00B1} 0.34 \u{00B7} Al 96.41 \u{00B1} 0.48 \u{00B7} Cu 0.180 \u{00B1} 0.042",
            "result_wt": "Mg 1.5 \u{00B1} 0.3", "result_unit": "at%"])
        let node = replay.lineage.nodes[0]
        let shown = QuantificationRows.row(node, locale: german)
        XCTAssertEqual(shown.result, "Mg 1,65 \u{00B1} 0,34 \u{00B7} Al 96,41 \u{00B1} 0,48 \u{00B7} Cu 0,180 \u{00B1} 0,042 at%")
        XCTAssertEqual(shown.parameters.first { $0.key == "result_wt%" }?.value, "Mg 1,5 \u{00B1} 0,3")
        XCTAssertEqual(QuantificationRows.row(node, locale: american).result,
                       "Mg 1.65 \u{00B1} 0.34 \u{00B7} Al 96.41 \u{00B1} 0.48 \u{00B7} Cu 0.180 \u{00B1} 0.042 at%")
        XCTAssertEqual(CalibrationUnitConversion.localizedRecordLine("Region 1.2 of v2.0: 3 px", locale: german), "Region 1,2 of v2,0: 3 px",
                       "only a mark between two digits changes")
    }
}
