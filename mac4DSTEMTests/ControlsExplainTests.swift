//
//  ControlsExplainTests.swift
//  Seen on the 5.3.0 walk: DPC in detector pixels under a green "Quantitative" badge, "43388/43495 peaks" without grouping.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class ControlsExplainTests: XCTestCase {
    /// The badge follows the units the run used. Red before: detector px was Quantitative.
    @MainActor
    func testDPCInDetectorPixelsIsNotQuantitative() {
        let state = AppState()
        XCTAssertEqual(state.quantitativeStatus(for: "dpc_magnitude", units: "detector_px"), .relative)
        XCTAssertEqual(state.quantitativeStatus(for: "dpc_com_x", units: "detector_px"), .relative)
        XCTAssertEqual(state.quantitativeStatus(for: "dpc_magnitude_mrad", units: "mrad"), .quantitative)
        XCTAssertEqual(state.quantitativeStatus(for: "strain_fit_residual", units: "detector_px"), .quantitative,
                       "a fit residual in pixels is a measured number")
    }

    func testTheBasisSupportCountsAreGrouped() {
        XCTAssertEqual(StrainBasisText.support(fraction: 0.9975, supporting: 43388, of: 43495, locale: Locale(identifier: "en_US")),
                       "100% \u{00B7} 43,388 of 43,495 peaks")
        XCTAssertEqual(StrainBasisText.support(fraction: 0.5, supporting: 43388, of: 86776, locale: Locale(identifier: "de_DE")),
                       "50% \u{00B7} 43.388 of 86.776 peaks")
    }
}
