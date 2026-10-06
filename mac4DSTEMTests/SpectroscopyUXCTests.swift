import XCTest
@testable import mac4DSTEM

/// UX lane C: the quiet spectrum strip. Pure seams only; the drawing is verified on screen by the supervisor's drive.
final class SpectroscopyUXCTests: XCTestCase {
    private func marker(_ label: String, _ e: Double, _ kind: LineMarker.Kind) -> LineMarker {
        LineMarker(label: label, energy: e, elementZ: nil, kind: kind)
    }

    /// A marker (and so its label) is drawn only when its energy is inside the viewport.
    /// Mutation: `inView` always true - red.
    func testOnlyMarkersInViewAreDrawn() {
        let ms = [marker("Cu Kα", 8.05, .line), marker("Hf Kα", 15.0, .line), marker("Mg Kα", 1.25, .line)]
        let v = MarkerLabelLayout.inView(ms, lo: 0.2, hi: 10)
        XCTAssertEqual(v.map(\.label), ["Cu Kα", "Mg Kα"])
        XCTAssertEqual(MarkerLabelLayout.inView(ms, lo: 14, hi: 20).map(\.label), ["Hf Kα"])
        XCTAssertEqual(MarkerLabelLayout.inView(ms, lo: 15, hi: 20).map(\.label), ["Hf Kα"], "the bound itself is in view")
        XCTAssertTrue(MarkerLabelLayout.inView(ms, lo: 9, hi: 12).isEmpty)
    }

    /// A clipped residual says which frame edge it sits on; one inside the frame says none.
    /// Mutation: the sign test flipped - red.
    func testClipSideNamesTheEdge() {
        XCTAssertEqual(ResidualNormalisation.clipSide(3.5), 1)
        XCTAssertEqual(ResidualNormalisation.clipSide(-7), -1)
        XCTAssertEqual(ResidualNormalisation.clipSide(3.0), 0)
        XCTAssertEqual(ResidualNormalisation.clipSide(-2.9), 0)
        XCTAssertEqual(ResidualNormalisation.clipSide(.nan), 0)
    }

    /// Axis text is 10 pt now: its estimated width is wider than the old 9-pt estimate, never narrower.
    /// Mutation: the factor back to 5 - red.
    func testAxisLabelWidthIsForTenPoint() {
        XCTAssertGreaterThanOrEqual(AxisTicks.labelWidth("10.5"), 4 * 5.6)
        XCTAssertGreaterThan(AxisTicks.labelWidth("keV"), 3 * 5 + 2)
    }
}
