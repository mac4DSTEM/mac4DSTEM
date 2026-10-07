import XCTest
import SwiftUI
@testable import mac4DSTEM

/// The accessibility fixes the drive and Apple's documentation confirmed (2026-10-07, lane X).
@MainActor
final class AccessibilityDriveFixesTests: XCTestCase {
    /// X1: the spectrum's +/=/- keys zoom with no modifier and with ⇧ (some layouts type "+" so), and pass on with ⌘, ⌃ or ⌥.
    func testZoomKeysIgnoreCommandControlOption() {
        XCTAssertTrue(SpectrumStripLogic.zoomKeyAccepts([]))
        XCTAssertTrue(SpectrumStripLogic.zoomKeyAccepts([.shift]))
        XCTAssertFalse(SpectrumStripLogic.zoomKeyAccepts([.command]))
        XCTAssertFalse(SpectrumStripLogic.zoomKeyAccepts([.control]))
        XCTAssertFalse(SpectrumStripLogic.zoomKeyAccepts([.option]))
        XCTAssertFalse(SpectrumStripLogic.zoomKeyAccepts([.shift, .control]))
        XCTAssertFalse(SpectrumStripLogic.zoomKeyAccepts([.shift, .option]))
    }
}
