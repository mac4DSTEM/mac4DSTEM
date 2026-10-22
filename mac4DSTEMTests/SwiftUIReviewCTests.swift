import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// SwiftUI review lane C (2026-10-07): accessibility of the Spectroscopy periodic table and the maps grid. Only the pure helpers
/// the views take their VoiceOver text and action sets from are held here; keyboard focus and the rotor need a drive.
@MainActor
final class SwiftUIReviewCTests: XCTestCase {
    /// A click on a not-detectable cell stays inert (the cell is also `.disabled`, but the model is the guarantee).
    /// Mutation: the guard in `ElementSelection.click` removed - red.
    func testClickOnUnavailableCellIsInert() {
        var sel = ElementSelection()
        let before = sel.roles
        sel.click(1)
        XCTAssertEqual(sel.roles, before)
    }
}
