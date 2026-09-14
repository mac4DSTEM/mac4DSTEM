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

        // Throughput left this line on 2026-09-12 and is the inspector's
        // alone. A measured rate must NOT appear here, which is what these two
        // now pin: the first is the case that used to print a rate and no ETA,
        // and it must now print neither.
        let noETA = AnalysisOperationMetrics(
            elapsed: 150, unitsPerSecond: 78.8, eta: nil
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(noETA, for: "Disk detection"), "2:30"
        )

        let full = AnalysisOperationMetrics(
            elapsed: 150, unitsPerSecond: 78.8, eta: 155
        )
        XCTAssertEqual(
            OperationMetricsFormat.line(full, for: "Disk detection"),
            "2:30 · ETA 2:35"
        )
        XCTAssertFalse(OperationMetricsFormat.line(full, for: "Disk detection")
                        .contains("/s"))
    }

    /// The virtual detector walks patterns; everything else walks scan
    /// positions. The INSPECTOR must still get that right — it is the only
    /// surface that prints a rate now — so the unit rule is pinned on
    /// `throughput(_:for:)` directly rather than through the status line,
    /// which stopped carrying it on 2026-09-12.
    func testTheThroughputUnitFollowsTheOperation() {
        XCTAssertEqual(OperationMetricsFormat.throughput(12.0, for: "Virtual detector"),
                       "12.0 patterns/s")
        XCTAssertEqual(OperationMetricsFormat.throughput(12.0, for: nil),
                       "12.0 positions/s")
        XCTAssertEqual(OperationMetricsFormat.throughput(12.0, for: "Disk detection"),
                       "12.0 positions/s")
        // And the status line ignores the operation entirely now, which is
        // what keeps its width bounded by the sweep below.
        let metrics = AnalysisOperationMetrics(elapsed: 10, unitsPerSecond: 12.0, eta: nil)
        XCTAssertEqual(OperationMetricsFormat.line(metrics, for: "Virtual detector"),
                       OperationMetricsFormat.line(metrics, for: nil))
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

    /// The bound this test defends: **a hundred hours** in both fields.
    ///
    /// The sweep deliberately runs past an hour, and that is the point. The
    /// version of this test that stood until 2026-09-12 stopped at 59:59 in
    /// each field, which was enough while throughput dominated the width — and
    /// would have been exactly the wrong bound afterwards, because with the
    /// rate gone the two DURATIONS are what grows the string, and
    /// `duration(_:)` keeps counting minutes rather than growing an hours
    /// field. Narrowing the sweep to fit a smaller constant would be fitting
    /// the gate to the answer.
    func testTheReservedSlotFitsTheLongestLineTheFormatterProduces() {
        let font = statusBarFont()
        var widest = (line: "", width: CGFloat(0))

        for operation in ["Disk detection", "Virtual detector"] {
            for elapsed in [0.0, 53, 150, 59 * 60 + 59, 5999 * 60 + 59] as [TimeInterval] {
                for rate in [nil, 0.1, 78.8, 999.9] as [Double?] {
                    for eta in [nil, 5, 155, 59 * 60 + 59, 5999 * 60 + 59] as [TimeInterval?] {
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
            widest.width, LayoutPolicy.operationReadoutWidth,
            """
            The widest line the formatter can produce inside the documented \
            bound is "\(widest.line)" at \(widest.width) pt, which does not \
            fit LayoutPolicy.operationReadoutWidth \
            (\(LayoutPolicy.operationReadoutWidth) pt). Widen the constant — \
            do NOT let the text size itself.
            """
        )
    }

    /// The percent slot's test stood here and is DELETED with the slot it
    /// measured, 2026-09-12. The label is gone: a numeric percentage beside a
    /// progress bar is the same fact drawn twice, `ProgressView` has no
    /// percentage API and the HIG never asks for one. The number reaches
    /// VoiceOver on the bar's `.accessibilityValue` instead, where it cannot
    /// wrap — which also closes the wrap defect this test was written for.

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
