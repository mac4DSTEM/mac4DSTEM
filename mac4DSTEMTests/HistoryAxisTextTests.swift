import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The history plots print their axes: the y range of the finite samples and what x counts (audit 2026-10-14, "History plots have
/// no axis values"). Presentation of numbers the plot already draws; the values are the samples' own, not recomputed. Tier 2.
final class HistoryAxisTextTests: XCTestCase {

    func testTheYRangeIsTheFiniteSamplesMinimumAndMaximum() {
        let geometry = ScientificSeriesGeometry.make(values: [0.5, .nan, 2, 0.125, .infinity], scale: .linear)
        XCTAssertEqual(HistoryAxisText.yRange(geometry, scale: .linear), "0.125 – 2 · linear")
    }

    func testALogPlotPrintsTheValuesNotTheirLogarithms() {
        let geometry = ScientificSeriesGeometry.make(values: [0.01, 0, 1, -3, 0.1], scale: .logarithmic)
        XCTAssertEqual(HistoryAxisText.yRange(geometry, scale: .logarithmic), "0.01 – 1 · log scale",
                       "zero and negative samples are gaps on a log axis and are not in the range")
    }

    func testNoFiniteSampleSaysNothing() {
        let geometry = ScientificSeriesGeometry.make(values: [.nan, .nan], scale: .linear)
        XCTAssertNil(HistoryAxisText.yRange(geometry, scale: .linear))
    }

    func testTheXAxisNamesWhatIsCounted() {
        XCTAssertEqual(HistoryAxisText.xCount(42, name: "iteration"), "42 iterations")
        XCTAssertEqual(HistoryAxisText.xCount(1, name: "iteration"), "1 iteration")
        XCTAssertEqual(HistoryAxisText.xCount(3, name: "alignment step"), "3 alignment steps")
    }
}
