import XCTest
@testable import mac4DSTEM

/// The spectrum's VoiceOver candidate actions query the centre of the visible span (the energy the keyboard user has panned to);
/// the right-click menu shares the same candidate list. The view's action list is not unit-testable; these pin the pure parts.
final class SpectrumStripAccessibilityCandidatesTests: XCTestCase {

}

private extension SpectrumViewport {
    func withWindow(lo: Double, hi: Double) -> SpectrumViewport {
        var v = self
        v.lo = lo; v.hi = hi
        return v
    }
}
