import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// SwiftUI review lane C (2026-10-07): accessibility of the Spectroscopy periodic table and the maps grid. Only the pure helpers
/// the views take their VoiceOver text and action sets from are held here; keyboard focus and the rotor need a drive.
@MainActor
final class SwiftUIReviewCTests: XCTestCase {
    /// The role actions a cell offers are the context menu's role rows: all three on a detectable element, none on a
    /// not-detectable one (H: below the detector window).
    /// Mutation: `roleActions` returns `ElementRole.allCases` unconditionally - red on the H assertion.
    func testRoleActionsFollowAvailability() {
        XCTAssertEqual(PeriodicTableView.roleActions(z: 13).map(\.title), ["Quantify", "Fit only", "Off"])
        XCTAssertTrue(PeriodicTableView.roleActions(z: 1).isEmpty)
    }

    /// A click on a not-detectable cell stays inert (the cell is also `.disabled`, but the model is the guarantee).
    /// Mutation: the guard in `ElementSelection.click` removed - red.
    func testClickOnUnavailableCellIsInert() {
        var sel = ElementSelection()
        let before = sel.roles
        sel.click(1)
        XCTAssertEqual(sel.roles, before)
    }

    /// The ColorMix canvas reads "No region" without an outline and the capsule's own caption (grouped pixel count) with one.
    /// Mutation: `regionValue` returns the caption unconditionally - red on the no-outline assertion.
    func testColorMixValueIsNoRegionOrTheCaption() {
        XCTAssertEqual(MapTileView.regionValue(hasOutline: false, pixels: 1234), "No region")
        XCTAssertEqual(MapTileView.regionValue(hasOutline: true, pixels: 1234), MapTileView.regionCaption(pixels: 1234))
        XCTAssertTrue(MapTileView.regionValue(hasOutline: true, pixels: 0).hasPrefix("Region"))
    }
}
