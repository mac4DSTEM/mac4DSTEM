import XCTest
@testable import mac4DSTEM

/// Lane P2 (SwiftUI review, polish drive 2026-10-04): the ACOM Q-scale read-out
/// follows the locale's decimal mark, with the same six significant digits the
/// old `%.6g` printed.
final class SwiftUIReviewP2Tests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    func testQScaleReadoutUsesTheLocaleDecimalMark() {
        XCTAssertEqual(ACOMQScaleReadout.text(0.0275, locale: en), "0.0275 Å⁻¹/px")
        XCTAssertEqual(ACOMQScaleReadout.text(0.0275, locale: de), "0,0275 Å⁻¹/px")
        XCTAssertEqual(ACOMQScaleReadout.text(0.02, locale: en), "0.02 Å⁻¹/px")
        XCTAssertEqual(ACOMQScaleReadout.text(0.02, locale: de), "0,02 Å⁻¹/px")
    }

    func testQScaleReadoutKeepsSixSignificantDigits() {
        XCTAssertEqual(ACOMQScaleReadout.text(0.0123456789, locale: en), "0.0123457 Å⁻¹/px")
        XCTAssertEqual(ACOMQScaleReadout.text(0.0123456789, locale: de), "0,0123457 Å⁻¹/px")
    }
}
