import XCTest
@testable import mac4DSTEM

/// The VoiceOver label cursor for "Label centres on click" (audit 3.1): the step, the clamp and the start.
@MainActor
final class DiskLabelCursorTests: XCTestCase {
    /// One step is 1/50 of the side, never below one pixel.
    func testStepIsFiftieth() {
        XCTAssertEqual(DiskLabelCursor.step(extent: 128), 2)
        XCTAssertEqual(DiskLabelCursor.step(extent: 500), 10)
        XCTAssertEqual(DiskLabelCursor.step(extent: 40), 1)
        XCTAssertEqual(DiskLabelCursor.step(extent: 1), 1)
    }

    /// The cursor starts at the pattern centre, and a stored position outside the pattern is clamped to it.
    func testResolvedStartsAtCentreAndClamps() {
        XCTAssertEqual(DiskLabelCursor.resolved(nil, patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 63, y: 31))
        XCTAssertEqual(DiskLabelCursor.resolved(DiskLabelCursor.Pixel(x: 500, y: -4), patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 127, y: 0))
    }

    /// Each named move goes one step in its direction (y grows downward, as the pane draws it).
    func testMovesStepInTheNamedDirection() {
        let start = DiskLabelCursor.Pixel(x: 64, y: 32)
        XCTAssertEqual(DiskLabelCursor.moved(start, by: .right, patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 66, y: 32))
        XCTAssertEqual(DiskLabelCursor.moved(start, by: .left, patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 62, y: 32))
        XCTAssertEqual(DiskLabelCursor.moved(start, by: .down, patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 64, y: 33))
        XCTAssertEqual(DiskLabelCursor.moved(start, by: .up, patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 64, y: 31))
    }

    /// Moves past an edge stop on the last pixel, inside 0 ... extent - 1, never off the pattern.
    func testMovesClampToPatternEdges() {
        XCTAssertEqual(DiskLabelCursor.moved(DiskLabelCursor.Pixel(x: 0, y: 0), by: .left,
                                             patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 0, y: 0))
        XCTAssertEqual(DiskLabelCursor.moved(DiskLabelCursor.Pixel(x: 0, y: 0), by: .up,
                                             patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 0, y: 0))
        XCTAssertEqual(DiskLabelCursor.moved(DiskLabelCursor.Pixel(x: 127, y: 63), by: .right,
                                             patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 127, y: 63))
        XCTAssertEqual(DiskLabelCursor.moved(DiskLabelCursor.Pixel(x: 127, y: 62), by: .down,
                                             patternWidth: 128, patternHeight: 64),
                       DiskLabelCursor.Pixel(x: 127, y: 63))
    }

    /// The spoken position names the pixel the label action will use.
    func testSpokenValueNamesPixel() {
        XCTAssertEqual(DiskLabelCursor.spokenValue(DiskLabelCursor.Pixel(x: 64, y: 71)),
                       "Label cursor x 64, y 71 px")
    }
}
