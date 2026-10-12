import XCTest
@testable import mac4DSTEM

/// The spectrum's VoiceOver candidate actions query the centre of the visible span (the energy the keyboard user has panned to);
/// the right-click menu shares the same candidate list. The view's action list is not unit-testable; these pin the pure parts.
final class SpectrumStripAccessibilityCandidatesTests: XCTestCase {
    /// Mutation: `queryEnergy` returning the left edge (fraction 0.0) instead of the centre - red.
    func testTheQueryEnergyIsTheCentreOfTheVisibleSpan() {
        let vp = SpectrumViewport(domain: 0...10).withWindow(lo: 1.0, hi: 2.0)
        XCTAssertEqual(SpectrumStripLogic.queryEnergy(viewport: vp), 1.5, accuracy: 1e-12)
    }

    /// Mutation: `candidates(at:listed:)` dropping the listed elements or the line tolerance - red. The centre of a window
    /// around Al K-alpha (1.4865 keV, Z 13) lists Al K-alpha among the lines.
    func testTheCentreOfAWindowOnAluminiumKAlphaListsIt() {
        let vp = SpectrumViewport(domain: 0...10).withWindow(lo: 1.45, hi: 1.55)
        let found = SpectrumStripLogic.candidates(at: SpectrumStripLogic.queryEnergy(viewport: vp), listed: [13])
        XCTAssertTrue(found.contains { $0.label == "Al K\u{03B1}" && $0.kind == .line && $0.z == 13 }, "\(found)")
    }

    /// No tabulated alpha line near the centre (150 keV lies above every Ka, La and Ma line of the table, and a 0.6 keV tolerance
    /// there reaches none): no candidates, so no actions are offered.
    func testAnEmptyCentreListsNothing() {
        let vp = SpectrumViewport(domain: 0...200).withWindow(lo: 149.9, hi: 150.1)
        XCTAssertTrue(SpectrumStripLogic.candidates(at: SpectrumStripLogic.queryEnergy(viewport: vp), listed: [13]).isEmpty)
    }
}

private extension SpectrumViewport {
    func withWindow(lo: Double, hi: Double) -> SpectrumViewport {
        var v = self
        v.lo = lo; v.hi = hi
        return v
    }
}
