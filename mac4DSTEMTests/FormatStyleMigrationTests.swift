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
}
