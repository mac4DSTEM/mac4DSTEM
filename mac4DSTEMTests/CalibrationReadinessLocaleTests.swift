// Prepare's readiness row writes every number through one path, in the reader's locale, and never wraps inside a phrase that
// belongs together ("Imported from file", "Fit RMS", a number and its unit).

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class CalibrationReadinessLocaleTests: XCTestCase {
    private func report(_ locale: Locale) -> CalibrationReadinessReport {
        var c = Calibration()
        c.probeRadius = 4.5
        c.qPixelSize = 0.02; c.qPixelUnits = "1/A"
        c.rPixelSize = 0.5; c.rPixelUnits = "nm"
        var p = CalibrationProvenance()
        p.probe = .importedFile
        return CalibrationReadinessReport.make(calibration: c, provenance: p, locale: locale)
    }

    func testOneSeparatorInTheWholeRow() throws {
        for (id, separator, other) in [("de_DE", ",", "."), ("en_US", ".", ",")] {
            let items = report(Locale(identifier: id)).items
            let origin = try XCTUnwrap(items.first { $0.kind == .originProbe }).detail
            let q = try XCTUnwrap(items.first { $0.kind == .qScale }).detail
            let r = try XCTUnwrap(items.first { $0.kind == .rScale }).detail
            XCTAssertTrue(origin.contains("4\(separator)5"), "\(id): \(origin)")
            XCTAssertTrue(q.contains("0\(separator)02"), "\(id): \(q)")
            XCTAssertTrue(r.contains("0\(separator)5"), "\(id): \(r)")
            XCTAssertFalse(origin.contains("4\(other)5"), "\(id): \(origin)")
        }
    }

    func testTheSourceStaysOnOneLine() throws {
        let origin = try XCTUnwrap(report(Locale(identifier: "en_US")).items.first { $0.kind == .originProbe }).detail
        XCTAssertTrue(origin.contains("Imported\u{00A0}from\u{00A0}file"), origin)
        XCTAssertTrue(origin.contains("4.5\u{00A0}px"), origin)
    }
}
