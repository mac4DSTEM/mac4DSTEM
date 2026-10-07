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

    /// X4: the image pane's hint is one brief phrase, one sentence, and names the zoom actions.
    func testImagePaneHintIsOneBriefPhrase() {
        let hint = ZoomPan.accessibilityHint
        XCTAssertEqual(hint.filter { $0 == "." }.count, 1, "one sentence")
        XCTAssertTrue(hint.hasSuffix("."))
        XCTAssertLessThanOrEqual(hint.count, 60)
        XCTAssertTrue(hint.contains("Zoom in") && hint.contains("Zoom out"))
    }

    /// X5: a pan step is a fifth of the pane, in the named direction, clamped to the image; nothing at zoom 1.
    func testPanStepMovesAFifthAndStaysInsideThePane() {
        let box = CGSize(width: 400, height: 200)
        var z = ZoomPan(); z.zoom = 2     // allowed offset: +-100 x, +-50 y
        z.pan(.left, in: box);  XCTAssertEqual(z.offset, CGSize(width: 80, height: 0))
        z.pan(.right, in: box); XCTAssertEqual(z.offset, .zero)
        z.pan(.right, in: box); XCTAssertEqual(z.offset, CGSize(width: -80, height: 0))
        z.pan(.up, in: box);    XCTAssertEqual(z.offset, CGSize(width: -80, height: 40))
        z.pan(.down, in: box);  z.pan(.down, in: box)
        XCTAssertEqual(z.offset, CGSize(width: -80, height: -40))
        // Repeated steps stop at the edge instead of leaving the pane.
        for _ in 0..<10 { z.pan(.right, in: box); z.pan(.down, in: box) }
        XCTAssertEqual(z.offset, CGSize(width: -100, height: -50))
        for _ in 0..<10 { z.pan(.left, in: box); z.pan(.up, in: box) }
        XCTAssertEqual(z.offset, CGSize(width: 100, height: 50))
        // Unzoomed: nothing to pan.
        var flat = ZoomPan()
        for d in ZoomPan.PanDirection.allCases { flat.pan(d, in: box) }
        XCTAssertEqual(flat.offset, .zero)
    }

    /// X6: the scan moves (shared by the marker handle and the navigator inset) are one pixel in the named direction (y grows
    /// downwards), under the names the main pane has always had.
    func testScanMovesStepOnePixelUnderTheKnownNames() {
        XCTAssertEqual(ScanMove.left.delta.dx, -1); XCTAssertEqual(ScanMove.left.delta.dy, 0)
        XCTAssertEqual(ScanMove.right.delta.dx, 1); XCTAssertEqual(ScanMove.right.delta.dy, 0)
        XCTAssertEqual(ScanMove.up.delta.dx, 0);    XCTAssertEqual(ScanMove.up.delta.dy, -1)
        XCTAssertEqual(ScanMove.down.delta.dx, 0);  XCTAssertEqual(ScanMove.down.delta.dy, 1)
        XCTAssertEqual(ScanMove.allCases.map(\.actionName),
                       ["Move scan left", "Move scan right", "Move scan up", "Move scan down"])
    }
}
