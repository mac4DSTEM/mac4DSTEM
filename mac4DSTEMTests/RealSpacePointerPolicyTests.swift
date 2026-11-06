import XCTest
@testable import mac4DSTEM

/// Backlog #35 — who owns a plain drag in the real-space pane.
///
/// The regression that would hurt most is the *common* one: at zoom 1 a click
/// must still scrub the scan position, because that is the gesture a user makes
/// a hundred times a session. So that case is asserted first and hardest.
final class RealSpacePointerPolicyTests: XCTestCase {

    func testTheDefaultZoomStillScrubsOnAPlainClick() {
        XCTAssertEqual(RealSpacePointerPolicy.mode(zoom: 1), .scrub)
    }

    /// Zooming *out* keeps click-to-scrub. The image is then smaller than its
    /// pane, so there is nothing to pan to; taking the gesture away would cost
    /// the user something and give nothing back.
    func testZoomingOutKeepsScrubbing() {
        for zoom in [0.25, 0.5, 0.9, 0.999] as [CGFloat] {
            XCTAssertEqual(RealSpacePointerPolicy.mode(zoom: zoom), .scrub,
                           "zoom \(zoom) should still scrub")
        }
    }

    func testZoomingInHandsThePlainDragToPanning() {
        for zoom in [1.05, 2, 8, 64] as [CGFloat] {
            XCTAssertEqual(RealSpacePointerPolicy.mode(zoom: zoom), .panAndGrab,
                           "zoom \(zoom) should pan")
        }
    }

    /// A pinch or a wheel notch that lands back on nominal 1.0 leaves float
    /// error behind. Flipping mode on that would make the pane feel haunted.
    func testFloatNoiseAroundOneDoesNotFlipTheMode() {
        XCTAssertEqual(RealSpacePointerPolicy.mode(zoom: 1 + 1e-9), .scrub)
        XCTAssertEqual(RealSpacePointerPolicy.mode(zoom: 1 - 1e-9), .scrub)
    }

    // MARK: - Marker geometry

    /// Scan coordinates name pixel centres, so pixel 0 of a 10-pixel axis sits
    /// half a pixel in, not at the edge. Same convention as
    /// `PeakOverlayGeometry`, and the reason the marker and its grab handle
    /// share one function.
    func testTheMarkerSitsAtThePixelCentre() {
        let center = RealSpacePointerPolicy.markerCenter(
            scan: ScanPos(x: 0, y: 0), imageWidth: 10, imageHeight: 10,
            box: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(center.x, 5, accuracy: 1e-9)
        XCTAssertEqual(center.y, 5, accuracy: 1e-9)
    }

    func testTheMarkerUsesEachAxisOwnScale() {
        let center = RealSpacePointerPolicy.markerCenter(
            scan: ScanPos(x: 3, y: 1), imageWidth: 4, imageHeight: 2,
            box: CGSize(width: 400, height: 100)
        )
        XCTAssertEqual(center.x, 350, accuracy: 1e-9)
        XCTAssertEqual(center.y, 75, accuracy: 1e-9)
    }

    /// The handle drag and the whole-pane scrub must agree about which pixel a
    /// point is in, or grabbing the marker would nudge it.
    ///
    /// Round-tripping the centre *alone* is not enough, and this was verified
    /// by mutation rather than assumed: deleting the half-pixel offset from
    /// `markerCenter` leaves the plain round trip green, because the marker just
    /// slides to its pixel's leading edge, which still floors to the same pixel.
    /// So the assertion is that the marker sits **strictly inside** its band —
    /// a nudge either way stays on the same pixel. That is also the property
    /// that actually matters when a user grabs the handle.
    func testTheMarkerCentreIsStrictlyInsideItsOwnPixelBand() {
        let box = CGSize(width: 640, height: 480)
        let nudge: CGFloat = 0.4   // well under the 10pt/7.5pt pixel pitch
        for x in [0, 1, 7, 63] {
            for y in [0, 1, 5, 47] {
                let scan = ScanPos(x: x, y: y)
                let center = RealSpacePointerPolicy.markerCenter(
                    scan: scan, imageWidth: 64, imageHeight: 48, box: box
                )
                for dx in [-nudge, 0, nudge] {
                    for dy in [-nudge, 0, nudge] {
                        XCTAssertEqual(
                            RealSpacePointerPolicy.scanPosition(
                                at: CGPoint(x: center.x + dx, y: center.y + dy),
                                imageWidth: 64, imageHeight: 48, box: box
                            ),
                            scan,
                            "marker for \(scan) nudged by (\(dx), \(dy)) left its own pixel"
                        )
                    }
                }
            }
        }
    }

    /// Each pixel owns the area it covers: a point anywhere inside pixel 2's
    /// band is pixel 2, including its leading edge.
    func testAPointInsideAPixelBandBelongsToThatPixel() {
        let box = CGSize(width: 100, height: 100)
        for offset in [0.0, 0.1, 9.9] as [CGFloat] {
            let scan = RealSpacePointerPolicy.scanPosition(
                at: CGPoint(x: 20 + offset, y: 20 + offset),
                imageWidth: 10, imageHeight: 10, box: box
            )
            XCTAssertEqual(scan, ScanPos(x: 2, y: 2), "offset \(offset)")
        }
    }

    /// A degenerate box appears for one layout pass whenever a pane is being
    /// resized; dividing by it would produce an infinite scan index.
    func testADegenerateBoxDoesNotProduceANonFiniteIndex() {
        let scan = RealSpacePointerPolicy.scanPosition(
            at: CGPoint(x: 10, y: 10), imageWidth: 10, imageHeight: 10,
            box: .zero
        )
        XCTAssertEqual(scan, ScanPos(x: 0, y: 0))
        XCTAssertEqual(
            RealSpacePointerPolicy.markerCenter(
                scan: ScanPos(x: 1, y: 1), imageWidth: 0, imageHeight: 0,
                box: CGSize(width: 10, height: 10)
            ),
            .zero
        )
    }
}
