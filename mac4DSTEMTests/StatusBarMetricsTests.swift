import AppKit
import DSTEMCore
import XCTest
@testable import mac4DSTEM

/// The status bar's elapsed / throughput / ETA line: what it says, and the
/// slot it says it in.
///
/// The slot is the part that matters. The first version of this feature was
/// reverted the day it was written because its text carried `.fixedSize()`
/// and re-measured itself every second, which is the constraint loop that
/// aborted the app 2.5 minutes into a disk detection on a real dataset
/// (`docs/open-items.md`). The width is therefore a claim under test, not a
/// taste: the longest line the formatter can produce inside the bound this
/// test names must fit the reserved width, so the text truncates rather than
/// resizing its container.
final class StatusBarMetricsTests: XCTestCase {
    // MARK: - What the line says

    func testEachNumberAppearsOnlyOnceTheRunHasMeasuredIt() {
        let elapsedOnly = AnalysisOperationMetrics(
            elapsed: 53, unitsPerSecond: nil, eta: nil
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(elapsedOnly, for: "Disk detection"), "53 s"
        )

        let noETA = AnalysisOperationMetrics(
            elapsed: 150, unitsPerSecond: 78.8, eta: nil
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(noETA, for: "Disk detection"),
            "2:30 · 78.8 positions/s"
        )

        let full = AnalysisOperationMetrics(
            elapsed: 150, unitsPerSecond: 78.8, eta: 155
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(full, for: "Disk detection"),
            "2:30 · 78.8 positions/s · ETA 2:35"
        )
    }

    /// The virtual detector walks patterns; everything else walks scan
    /// positions. The status bar must not disagree with the inspector about
    /// which, so both take the unit from the same place.
    func testTheThroughputUnitFollowsTheOperation() {
        let metrics = AnalysisOperationMetrics(
            elapsed: 10, unitsPerSecond: 12.0, eta: nil
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(metrics, for: "Virtual detector"),
            "10 s · 12.0 patterns/s"
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(metrics, for: nil),
            "10 s · 12.0 positions/s"
        )
    }

    /// A rate of zero reads as a stall and an ETA the run cannot estimate is
    /// a number the user would plan around. Both are absent instead.
    func testAnUnmeasuredRunPrintsOnlyItsElapsedTime() {
        let unmeasured = AnalysisOperationMetrics(
            elapsed: 0, unitsPerSecond: nil, eta: nil
        )
        let line = OperationMetricsFormat.line(unmeasured, for: "Strain mapping")
        XCTAssertEqual(line, "0 s")
        XCTAssertFalse(line.contains("ETA"))
        XCTAssertFalse(line.contains("/s"))
    }

    // MARK: - The slot it says it in

    /// The bound this test defends: up to an hour elapsed, up to an hour of
    /// ETA, up to 999.9 units per second, in either unit. A longer run
    /// truncates inside the slot, which is safe — what is not safe is the
    /// slot changing size, and it cannot, because the width is a constant.
    func testTheReservedSlotFitsTheLongestLineTheFormatterProduces() {
        let font = statusBarFont()
        var widest = (line: "", width: CGFloat(0))

        for operation in ["Disk detection", "Virtual detector"] {
            for elapsed in [0.0, 53, 150, 59 * 60 + 59] as [TimeInterval] {
                for rate in [nil, 0.1, 78.8, 999.9] as [Double?] {
                    for eta in [nil, 5, 155, 59 * 60 + 59] as [TimeInterval?] {
                        let line = OperationMetricsFormat.line(
                            AnalysisOperationMetrics(
                                elapsed: elapsed, unitsPerSecond: rate, eta: eta
                            ),
                            for: operation
                        )
                        let width = (line as NSString)
                            .size(withAttributes: [.font: font]).width
                        if width > widest.width { widest = (line, width) }
                    }
                }
            }
        }

        XCTAssertLessThanOrEqual(
            widest.width, LayoutPolicy.operationMetricsWidth,
            """
            The widest line the formatter can produce inside the documented \
            bound is "\(widest.line)" at \(widest.width) pt, which does not \
            fit LayoutPolicy.operationMetricsWidth \
            (\(LayoutPolicy.operationMetricsWidth) pt). Widen the constant — \
            do NOT let the text size itself.
            """
        )
    }

    /// `.caption2.monospacedDigit()`, which is what the status bar draws in.
    /// Measured rather than assumed: the constant above is only defensible
    /// against the font that actually renders it.
    private func statusBarFont() -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: .caption2)
        return NSFont.monospacedDigitSystemFont(
            ofSize: base.pointSize, weight: .regular
        )
    }
}
