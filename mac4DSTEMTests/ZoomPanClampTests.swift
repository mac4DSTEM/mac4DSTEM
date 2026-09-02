import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// R16 (S22 feedback, 2026-09-01): panning may reveal the image's edge but
/// must never push the image out of the pane. Pins the pure rule the
/// gesture/scroll handlers all route through — |offset| ≤ size·(1 − 1/zoom)/2,
/// derived from the display shader's 1/zoom-wide sampling window
/// (`Colormaps.metal:33`).
final class ZoomPanClampTests: XCTestCase {

    func testPanIsBlockedAtOneXAndBelow() {
        let size = CGSize(width: 400, height: 300)
        XCTAssertEqual(
            ZoomPanState.clampedOffset(CGSize(width: 50, height: -80), zoom: 1, in: size),
            .zero, "at 1× the image fills the pane — a plain click scrubs, panning is meaningless"
        )
        XCTAssertEqual(
            ZoomPanState.clampedOffset(CGSize(width: 50, height: -80), zoom: 0.5, in: size),
            .zero, "zoomed out, the image fits entirely — it stays centred"
        )
    }

    func testZoomedPanStopsExactlyAtTheEdge() {
        let size = CGSize(width: 400, height: 300)
        // zoom 2 → limit size·(1 − 1/2)/2 = size/4 = (100, 75).
        let clamped = ZoomPanState.clampedOffset(
            CGSize(width: 500, height: -500), zoom: 2, in: size
        )
        XCTAssertEqual(clamped.width, 100)
        XCTAssertEqual(clamped.height, -75)
        // Inside the band, the pan passes through untouched.
        XCTAssertEqual(
            ZoomPanState.clampedOffset(CGSize(width: 40, height: -60), zoom: 2, in: size),
            CGSize(width: 40, height: -60)
        )
    }

    func testZoomingOutPullsAPannedImageBackInside() {
        let size = CGSize(width: 400, height: 400)
        // Panned to the zoom-4 limit (150pt), then the zoom drops to 2:
        // the limit is now 100pt and the offset must come back with it.
        XCTAssertEqual(
            ZoomPanState.clampedOffset(CGSize(width: 150, height: 150), zoom: 2, in: size),
            CGSize(width: 100, height: 100)
        )
    }
}
