//
//  PrecipitateDensityTextTests.swift
//  Issue #104: the object table's density cell says "no scan scale" only when there is no scale.
//

import XCTest
@testable import mac4DSTEM

final class PrecipitateDensityTextTests: XCTestCase {
    func testCalibratedScanWithNoDensityReadsADash() {
        XCTAssertEqual(PrecipitateObjectsWindow.densityText(nil, unit: "nm"), "—")
    }

    func testNoScaleReadsNoScanScale() {
        XCTAssertEqual(PrecipitateObjectsWindow.densityText(nil, unit: nil), "no scan scale")
        XCTAssertEqual(PrecipitateObjectsWindow.densityText(1e-4, unit: nil), "no scan scale")
    }

    func testADensityIsFormatted() {
        XCTAssertEqual(PrecipitateObjectsWindow.densityText(1e-4, unit: "nm"), PrecipitateFormat.density(1e-4, unit: "nm"))
    }
}
