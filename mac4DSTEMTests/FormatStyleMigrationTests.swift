import XCTest
@testable import mac4DSTEM

/// Pins the display strings of the formatter sites that move from NumberFormatter / DateFormatter to FormatStyle
/// (2026-10-08 API sweep, lane V). Each value was printed by the OLD formatter code, in en_US and de_DE, before the
/// swap; the swapped code must reproduce it byte for byte (U+202F is the narrow no-break space the app groups with).
final class FormatStyleMigrationTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let en = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: - Dates (C1)

    /// ActivityLog's status clock: fixed "HH:mm:ss" (24-hour in both locales), midnight, noon, late, single digits.
    func testActivityLogClockIsUnchanged() {
        let instants = ["2026-10-08T00:00:00Z", "2026-10-08T12:00:05Z", "2026-10-08T14:03:22Z",
                        "2026-10-08T23:59:59Z", "2026-01-05T09:07:03Z"]
        let enStrings = ["00:00:00", "12:00:05", "14:03:22", "23:59:59", "09:07:03"]
        for (iso, expected) in zip(instants, enStrings) {
            XCTAssertEqual(ActivityLog.clockText(instant(iso), locale: en, timeZone: utc), expected, "en_US \(iso)")
            XCTAssertEqual(ActivityLog.clockText(instant(iso), locale: de, timeZone: utc), expected, "de_DE \(iso)")
        }
    }

    /// The Materials Project provenance line's fetch time: medium date, short time (U+202F before AM/PM in English).
    func testMaterialsProjectFetchTimeIsUnchanged() {
        let nnbsp = "\u{202F}"
        let enStrings = ["Oct 8, 2026 at 12:00\(nnbsp)AM", "Oct 8, 2026 at 12:00\(nnbsp)PM", "Oct 8, 2026 at 2:03\(nnbsp)PM",
                         "Oct 8, 2026 at 11:59\(nnbsp)PM", "Jan 5, 2026 at 9:07\(nnbsp)AM"]
        let deStrings = ["08.10.2026, 00:00", "08.10.2026, 12:00", "08.10.2026, 14:03", "08.10.2026, 23:59", "05.01.2026, 09:07"]
        let instants = ["2026-10-08T00:00:00Z", "2026-10-08T12:00:05Z", "2026-10-08T14:03:22Z",
                        "2026-10-08T23:59:59Z", "2026-01-05T09:07:03Z"]
        for (i, iso) in instants.enumerated() {
            XCTAssertEqual(MaterialsProjectImportSheet.displayDate(instant(iso), locale: en, timeZone: utc), enStrings[i], "en_US \(iso)")
            XCTAssertEqual(MaterialsProjectImportSheet.displayDate(instant(iso), locale: de, timeZone: utc), deStrings[i], "de_DE \(iso)")
        }
    }

    // MARK: - Numbers (C2)

    private let nnbsp = "\u{202F}"

    /// HistogramReadout's counts line at scale > 1: whole numbers, thin grouping, a hyphen-minus for negatives.
    func testHistogramCountsReadoutIsUnchanged() {
        let cases: [(value: Float, scale: Float, expected: String)] = [
            (1, 4120, "4\(nnbsp)120"), (0.5, 4120, "2\(nnbsp)060"), (0, 4120, "0"), (-1, 4120, "-4\(nnbsp)120"),
            (0.123, 9999, "1\(nnbsp)230"), (1, 999.5, "1\(nnbsp)000"), (3, 1.5, "5"), (1, 1_000_000_000, "1\(nnbsp)000\(nnbsp)000\(nnbsp)000"),
            (-2.5, 1000, "-2\(nnbsp)500"),
        ]
        for locale in [en, de] {
            for c in cases {
                XCTAssertEqual(HistogramReadout.text(value: c.value, scale: c.scale, unit: "", locale: locale), c.expected,
                               "\(locale.identifier) \(c.value) x \(c.scale)")
            }
        }
        XCTAssertEqual(HistogramReadout.text(value: 1, scale: 4120, unit: "counts", locale: en), "4\(nnbsp)120 counts")
    }

    /// SpectroscopyPlaceholderFormat.number: a decimal in the locale's own mark, a true minus (U+2212), half-even at the last digit.
    func testSpectrumNumberReadoutIsUnchanged() {
        let enUpTo3: [(Double, String)] = [
            (20, "20"), (2.5, "2.5"), (0.0275, "0.028"), (-0.0001, "0"), (-1932.4, "\u{2212}1\(nnbsp)932.4"),
            (1234567.891, "1\(nnbsp)234\(nnbsp)567.891"), (0.5, "0.5"), (1.0625, "1.062"), (0.125, "0.125"), (-20, "\u{2212}20"),
            (0, "0"), (1e6, "1\(nnbsp)000\(nnbsp)000"), (2.0005, "2"), (100, "100"), (4, "4"),
        ]
        let deUpTo3: [(Double, String)] = [
            (20, "20"), (2.5, "2,5"), (0.0275, "0,028"), (-0.0001, "0"), (-1932.4, "\u{2212}1\(nnbsp)932,4"),
            (1234567.891, "1\(nnbsp)234\(nnbsp)567,891"), (0.5, "0,5"), (1.0625, "1,062"), (0.125, "0,125"), (-20, "\u{2212}20"),
            (0, "0"), (1e6, "1\(nnbsp)000\(nnbsp)000"), (2.0005, "2"), (100, "100"), (4, "4"),
        ]
        for (v, expected) in enUpTo3 {
            XCTAssertEqual(SpectroscopyPlaceholderFormat.number(v, fraction: 0...3, locale: en), expected, "en_US 0...3 \(v)")
        }
        for (v, expected) in deUpTo3 {
            XCTAssertEqual(SpectroscopyPlaceholderFormat.number(v, fraction: 0...3, locale: de), expected, "de_DE 0...3 \(v)")
        }
        XCTAssertEqual(SpectroscopyPlaceholderFormat.number(1234567.891, fraction: 0...2, locale: en), "1\(nnbsp)234\(nnbsp)567.89")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.number(1234567.891, fraction: 0...2, locale: de), "1\(nnbsp)234\(nnbsp)567,89")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.number(0.0275, fraction: 0...2, locale: en), "0.03")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.number(0.0275, fraction: 0...2, locale: de), "0,03")
    }

    /// The counts cells (ResultFormat.counts, SpectrumReadout.counts): en_US grouping, whole numbers, half-even on .5.
    func testCountsCellsAreUnchanged() {
        let cases: [(Double, String)] = [
            (412380, "412\(nnbsp)380"), (0, "0"), (2.5, "2"), (3.5, "4"), (1234.5, "1\(nnbsp)234"), (999999.5, "1\(nnbsp)000\(nnbsp)000"),
            (-4120, "-4\(nnbsp)120"), (-2.5, "-2"), (1e12, "1\(nnbsp)000\(nnbsp)000\(nnbsp)000\(nnbsp)000"), (0.4, "0"),
            (1380, "1\(nnbsp)380"), (1.5, "2"),
        ]
        for (v, expected) in cases {
            XCTAssertEqual(ResultFormat.counts(v), expected, "ResultFormat.counts \(v)")
            XCTAssertEqual(SpectrumReadout.counts(v), expected, "SpectrumReadout.counts \(v)")
        }
    }
}
