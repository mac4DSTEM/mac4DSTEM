import XCTest
import SwiftUI
@testable import mac4DSTEM

/// The room's inspector sections and results panel (EDS adoption, 2026-10-22): no header strip above the maps, no results-panel
/// width rule (the Spectrum / Results split is MacEMUI's `HorizontalPaneSplit`).
@MainActor
final class SpectroscopyRoomChromeTests: XCTestCase {
    /// The inspector is settings only and runs Maps, Tools, Elements, Region, Spectrum, Quantification, Fitting, Export; the results
    /// are not a section. Mutation: two cases of `Part` swapped, the Maps or Tools section dropped, or Results put back - red.
    func testTheInspectorSectionsRunMapsToolsElementsFirst() {
        let titles = SpectroscopyInspectorSections.Part.allCases.map(\.title)
        XCTAssertEqual(titles, ["Maps", "Tools", "Elements", "Region", "Spectrum", "Quantification", "Fitting", "Export"])
        XCTAssertFalse(titles.contains("Results"))
    }
}
