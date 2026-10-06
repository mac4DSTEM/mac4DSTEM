import XCTest
@testable import mac4DSTEM

/// Spec 2 lane F: the histogram's real values and its editable window edges.
final class SpectroscopySpec2FTests: XCTestCase {
    func testTextAtScaleOneIsTheOldThreeSignificantDigits() {
        XCTAssertEqual(HistogramReadout.text(value: 0.123456, scale: 1, unit: ""), "0.123")
        XCTAssertEqual(HistogramReadout.text(value: 1234.5, scale: 1, unit: ""), "1.23e+03")
    }

    func testTextShowsGroupedCountsWithUnit() {
        XCTAssertEqual(HistogramReadout.text(value: 1, scale: 4120, unit: "counts"), "4\u{202F}120 counts")
        XCTAssertEqual(HistogramReadout.text(value: 0, scale: 4120, unit: "counts"), "0 counts")
        XCTAssertEqual(HistogramReadout.text(value: 0.5, scale: 4120, unit: ""), "2\u{202F}060")
        XCTAssertEqual(HistogramReadout.text(value: 1, scale: 1_234_567, unit: ""), "1\u{202F}234\u{202F}567")
    }

    func testCommitDividesByScale() {
        XCTAssertEqual(HistogramReadout.commit(typed: 2060, scale: 4120, other: 1, isLow: true), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramReadout.commit(typed: 2060, scale: 4120, other: 0, isLow: false), 0.5, accuracy: 1e-6)
    }

    func testCommitClampsToUnitRange() {
        XCTAssertEqual(HistogramReadout.commit(typed: -50, scale: 4120, other: 1, isLow: true), 0)
        XCTAssertEqual(HistogramReadout.commit(typed: 9000, scale: 4120, other: 0, isLow: false), 1)
    }

    func testCommitKeepsTheEdgesOrdered() {
        // Low typed above the high edge: stays 0.01 below it.
        XCTAssertEqual(HistogramReadout.commit(typed: 4000, scale: 4120, other: 0.5, isLow: true), 0.49, accuracy: 1e-6)
        // High typed below the low edge: stays 0.01 above it.
        XCTAssertEqual(HistogramReadout.commit(typed: 100, scale: 4120, other: 0.5, isLow: false), 0.51, accuracy: 1e-6)
    }

    func testCommitMapsThroughTheDataRange() {
        // Data spans 0.2...0.8; the value 0.5 is the middle of the window range.
        XCTAssertEqual(HistogramReadout.commit(typed: 0.5, scale: 1, other: 1, isLow: true, dataMin: 0.2, dataMax: 0.8), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramReadout.edge(fraction: 0.5, dataMin: 0.2, dataMax: 0.8), 0.5, accuracy: 1e-6)
        XCTAssertEqual(HistogramReadout.edge(fraction: 0, dataMin: 0.2, dataMax: 0.8), 0.2, accuracy: 1e-6)
        XCTAssertEqual(HistogramReadout.edge(fraction: 1, dataMin: 0.2, dataMax: 0.8), 0.8, accuracy: 1e-6)
    }

    func testNonPositiveScaleIsTreatedAsOne() {
        XCTAssertEqual(HistogramReadout.commit(typed: 0.3, scale: 0, other: 1, isLow: true), 0.3, accuracy: 1e-6)
        XCTAssertEqual(HistogramReadout.text(value: 0.5, scale: -3, unit: ""), "0.5")
    }
}
