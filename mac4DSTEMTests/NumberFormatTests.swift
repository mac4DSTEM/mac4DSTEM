//
//  NumberFormatTests.swift
//  `Num`: the numbers in pane overlays and the status line carry the locale's decimal mark, printf's digits, no grouping.
//

import XCTest
@testable import mac4DSTEM

final class NumberFormatTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    func testFixedUsesTheLocaleDecimalMark() {
        XCTAssertEqual(Num.fixed(0.25, 2, locale: us), "0.25")
        XCTAssertEqual(Num.fixed(0.25, 2, locale: de), "0,25")
        XCTAssertEqual(Num.fixed(0.012_5, 4, locale: de), "0,0125")
    }

    func testFixedNeverGroups() {
        XCTAssertEqual(Num.fixed(12_345.678, 1, locale: us), "12345.7")
        XCTAssertEqual(Num.fixed(12_345.678, 1, locale: de), "12345,7")
    }

    func testFixedKeepsPrintfDigitsOnATie() {
        // %.1f rounds the binary 0.35 down; FormatStyle reads 0.4. The digits must not move with the region.
        XCTAssertEqual(Num.fixed(0.35, 1, locale: us), String(format: "%.1f", 0.35))
        XCTAssertEqual(Num.fixed(0.35, 1, locale: de), String(format: "%.1f", 0.35).replacingOccurrences(of: ".", with: ","))
    }

    func testFixedWritesNoNegativeZero() {
        XCTAssertEqual(Num.fixed(-0.000_4, 2, locale: de), "0,00")
        XCTAssertEqual(Num.fixed(-0.0, 0, locale: us), "0")
        XCTAssertEqual(Num.fixed(-1.25, 1, locale: de), String(format: "%.1f", -1.25).replacingOccurrences(of: ".", with: ","))
    }

    func testZeroPlacesHasNoDecimalMark() {
        XCTAssertEqual(Num.fixed(87.6, 0, locale: de), "88")
    }

    func testSignificantDigits() {
        XCTAssertEqual(Num.sig(0.012_345_6, 3, locale: us), "0.0123")
        XCTAssertEqual(Num.sig(0.012_345_6, 3, locale: de), "0,0123")
        XCTAssertEqual(Num.sig(2.5, 3, locale: de), "2,5")
        XCTAssertEqual(Num.sig(1_234, 3, locale: us), "1.23e+03")
    }
}
