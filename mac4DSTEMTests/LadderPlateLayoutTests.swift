import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The scale bar's plate and text are laid out in points and drawn at 1x, 2x or 3x pixels per point, so a 2x or 3x figure is the 1x
/// figure with more pixels. The plate's padding and the gap under the text were fixed pixel counts (6 and 4), so at 2x and 3x the
/// plate shrank against the bar and its text; the floors on the margin, the bar and the text did not scale either. Tier 2: the bar's
/// words and length are untouched (pinned by `FigureExportTests`), only the plate around them.
final class LadderPlateLayoutTests: XCTestCase {
    typealias Layout = FigureRendering.LadderPlateLayout

    /// Mutation: pad or gap back to a fixed 6 / 4 pixels -> red; floors left unscaled (heights 100, 200) -> red.
    func testTheTwoXAndThreeXPlateIsTheOneXPlateScaled() {
        for oneXHeight in [96, 192, 384, 1_000, 4_200] {       // below and above the floors of margin, bar and text
            let one = Layout(outHeight: oneXHeight, deviceScale: 1)
            for scale in 2...3 {
                let scaled = Layout(outHeight: oneXHeight * scale, deviceScale: scale)
                let k = CGFloat(scale)
                XCTAssertEqual(scaled.margin, one.margin * k, "margin, 1x height \(oneXHeight), \(scale)x")
                XCTAssertEqual(scaled.barHeight, one.barHeight * k, "bar thickness, \(oneXHeight), \(scale)x")
                XCTAssertEqual(scaled.fontSize, one.fontSize * k, "text size, \(oneXHeight), \(scale)x")
                XCTAssertEqual(scaled.pad, one.pad * k, "plate padding, \(oneXHeight), \(scale)x")
                XCTAssertEqual(scaled.gap, one.gap * k, "gap under the text, \(oneXHeight), \(scale)x")
            }
        }
    }

    /// The 1x plate is what `burnScaleBar` always drew (pinned byte for byte by its own tests): 6 and 4 pixels, margin max(10, h/30).
    func testTheOneXPlateIsUnchanged() {
        let layout = Layout(outHeight: 384, deviceScale: 1)
        XCTAssertEqual(layout, Layout(outHeight: 384, deviceScale: 0), "a scale below 1 is 1")
        XCTAssertEqual(layout.pad, 6); XCTAssertEqual(layout.gap, 4)
        XCTAssertEqual(layout.margin, 12)          // 384 / 30 = 12
        XCTAssertEqual(layout.barHeight, 3)        // 384 / 150 = 2 -> floor 3
        XCTAssertEqual(layout.fontSize, 13)        // 384 / 28 = 13
    }
}
