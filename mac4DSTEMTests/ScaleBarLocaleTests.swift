import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class ScaleBarLocaleTests: XCTestCase {
    private let de = Locale(identifier: "de_DE")
    private let en = Locale(identifier: "en_US")

    func testGermanUsesCommaAndNoGrouping() {
        XCTAssertEqual(ScaleBar.format(0.05, locale: de), "0,05")
        XCTAssertEqual(ScaleBar.format(2000, locale: de), "2000")
        XCTAssertEqual(ScaleBar.format(50000, locale: de), "50000")
        XCTAssertEqual(ScaleBar.format(0.05, locale: en), "0.05")
    }

    func testEnglishMatchesLegacyFormatForEveryNiceValue() {
        func legacy(_ v: Double) -> String {
            if v >= 10 { return String(format: "%.0f", v) }
            if v >= 1 { return String(format: "%g", v) }
            return String(format: "%.3g", v)
        }
        for n in -4...4 {
            for m in [1.0, 2.0, 5.0] {
                let v = m * pow(10, Double(n))
                XCTAssertEqual(ScaleBar.format(v, locale: en), legacy(v), "\(v)")
            }
        }
    }

    func testBurnedLocaleIsPointEvenWhereTheScreenIsComma() {
        let posix = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(ScaleBar.format(0.5, locale: posix), "0.5")
        XCTAssertEqual(ScaleBar.format(0.5, locale: de), "0,5")
    }

    func testSamplingFollowsLocale() throws {
        let de1 = try XCTUnwrap(SessionResultPresentation.sampling(row: 0.25, column: 0.25, units: "A", locale: de))
        XCTAssertTrue(de1.contains("0,25"), de1)
        let en1 = try XCTUnwrap(SessionResultPresentation.sampling(row: 0.25, column: 0.25, units: "A", locale: en))
        XCTAssertTrue(en1.contains("0.25"), en1)
        let two = try XCTUnwrap(SessionResultPresentation.sampling(row: 0.5, column: 0.25, units: "A", locale: de))
        XCTAssertTrue(two.contains("0,5 × 0,25"), two)
    }
}

/// One decimal mark per screen: the colorbar's range, the histogram's readout and the scale bar print the same mark
/// (a de_DE Mac showed "0,2 Å⁻¹" beside "0.88 / 1.16e+04", design review 2026-10-21).
final class ColorbarLocaleTests: XCTestCase {
    private let de = Locale(identifier: "de_DE"), en = Locale(identifier: "en_US")

    func testColorbarRangeUsesTheReadersDecimalMark() {
        XCTAssertEqual(Colorbar.format(0.88, locale: de), "0,88")
        XCTAssertEqual(Colorbar.format(11600, locale: de), "1,16e+04")
        XCTAssertEqual(Colorbar.format(-0.02908, locale: de), "-0,02908")
        XCTAssertEqual(Colorbar.format(0.88, locale: en), "0.88")
        XCTAssertEqual(Colorbar.format(11600, locale: en), "1.16e+04")
        XCTAssertEqual(Colorbar.format(0, locale: de), "0")
    }

    func testHistogramReadoutUsesTheReadersDecimalMark() {
        XCTAssertEqual(HistogramReadout.text(value: 0.123456, scale: 1, unit: "", locale: de), "0,123")
        XCTAssertEqual(HistogramReadout.text(value: 0.123456, scale: 1, unit: "", locale: en), "0.123")
    }
}
