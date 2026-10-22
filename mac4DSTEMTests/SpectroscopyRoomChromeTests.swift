import XCTest
import SwiftUI
@testable import mac4DSTEM

/// The room's header row and results panel (workspace alignment design D2 and D3, 2026-10-22).
@MainActor
final class SpectroscopyRoomChromeTests: XCTestCase {
    /// "Quantified" is plain text once a fit has rows, nothing before. Mutation: shown with no fit - red.
    func testTheHeaderSaysQuantifiedOnlyAfterAFit() {
        let model = SpectroscopyRoomModel.fixture
        model.hasFit = false
        XCTAssertNil(SpectroscopyRoomHeader.statusText(model))
        model.hasFit = true
        XCTAssertEqual(SpectroscopyRoomHeader.statusText(model), model.results.isEmpty ? nil : "Quantified")
    }

    /// The results panel's width: the default 320, never under 240, never over 45 % of a wide room. Mutation: the clamp dropped - red.
    func testTheResultsWidthIsClamped() {
        XCTAssertEqual(SpectroscopyResultsPanel.width(stored: nil, roomWidth: 1400), 320)
        XCTAssertEqual(SpectroscopyResultsPanel.width(stored: 100, roomWidth: 1400), 240)
        XCTAssertEqual(SpectroscopyResultsPanel.width(stored: 900, roomWidth: 1400), 630)
        XCTAssertEqual(SpectroscopyResultsPanel.width(stored: 500, roomWidth: 400), 240, "a narrow room keeps the floor")
    }

    /// The inspector is settings only: neither the region tool nor the map mode nor the results are among its sections.
    func testTheInspectorNoLongerHoldsTheHeadersControls() {
        XCTAssertFalse(SpectroscopyInspectorSections.Part.allCases.map(\.title).contains("Results"))
        // The chips the header draws are the ones the inspector used to draw, with their identifiers.
        XCTAssertEqual(RegionSection.toolChips.map(\.accessibilityID), ["spectroscopy.regionTool.rectangle", "spectroscopy.regionTool.Ellipse", "spectroscopy.regionTool.polygon", "spectroscopy.regionTool.line"])
        XCTAssertTrue(ElementsSection.mapChips(quantified: true).contains { $0.accessibilityID == "spectroscopy.mapMode.net" })
    }
}
