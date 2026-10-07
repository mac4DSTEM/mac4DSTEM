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

    /// X2: the scan preview's spoken value is the position without the visible caption's "click" clause, and the steppers' names
    /// carry the pane they belong to.
    func testScanPreviewSpokenValueAndStepperNames() {
        XCTAssertEqual(ScanPickStepping.spokenValue(position: (ry: 29, rx: 8)), "Pattern at scan (29, 8)")
        XCTAssertFalse(ScanPickStepping.spokenValue(position: (ry: 1, rx: 2)).localizedCaseInsensitiveContains("click"))
        XCTAssertEqual(ScanPickStepping.spokenValue(position: nil), "No pattern picked")
        XCTAssertEqual(ScanPickStepping.stepperLabel(axis: "Scan X"), "Scan X, real-space preview")
        XCTAssertEqual(ScanPickStepping.stepperLabel(axis: "Scan Y"), "Scan Y, real-space preview")
    }

    /// X3: the pin chip's hint says what happens, not a pixel count (the count is its value).
    func testPinChipHintSaysWhatHappens() {
        XCTAssertEqual(SpectrumStripLogic.unpinHint, "Removes the pin")
        XCTAssertFalse(SpectrumStripLogic.unpinHint.contains("pixel"))
    }
}
