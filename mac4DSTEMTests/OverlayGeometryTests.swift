import CoreGraphics
import DSTEMCore
import XCTest
@testable import mac4DSTEM

/// Detector coordinates name pixel *centres* — `VirtualDetector.fillRadial`
/// computes `dx = Float(x) - centerX` over integer pixel indices. Every overlay
/// that draws such a coordinate therefore owes it a half-pixel offset.
///
/// `ApertureControl` did not pay it, so the aperture was drawn at the pixel's
/// top-left corner and read as visibly off-axis on a small detector (reported
/// 2026-08-05). Both directions now go through `PeakOverlayGeometry`; these
/// pin the convention and the round trip.
final class OverlayGeometryTests: XCTestCase {

    private let box = CGSize(width: 512, height: 512)
    private let width = 128
    private let height = 128

    func testAPixelIsDrawnAtItsCentreNotItsCorner() {
        // 512pt / 128px = 4pt per pixel; pixel 0 therefore spans 0…4 and its
        // centre is at 2, not 0.
        let origin = PeakOverlayGeometry.center(
            x: 0, y: 0, patternWidth: width, patternHeight: height, box: box
        )
        XCTAssertEqual(origin.x, 2, accuracy: 0.001)
        XCTAssertEqual(origin.y, 2, accuracy: 0.001)

        let sixtyFour = PeakOverlayGeometry.center(
            x: 64, y: 64, patternWidth: width, patternHeight: height, box: box
        )
        XCTAssertEqual(sixtyFour.x, 258, accuracy: 0.001)
        XCTAssertEqual(sixtyFour.y, 258, accuracy: 0.001)

        // The last pixel must stay inside the box.
        let last = PeakOverlayGeometry.center(
            x: Float(width - 1), y: Float(height - 1),
            patternWidth: width, patternHeight: height, box: box
        )
        XCTAssertLessThan(last.x, box.width)
        XCTAssertLessThan(last.y, box.height)
        XCTAssertEqual(last.x, 510, accuracy: 0.001)
    }

    func testPixelAndCentreAreExactInverses() {
        for (x, y) in [(0, 0), (64, 64), (127, 127), (3, 100)] {
            let point = PeakOverlayGeometry.center(
                x: Float(x), y: Float(y),
                patternWidth: width, patternHeight: height, box: box
            )
            let back = PeakOverlayGeometry.pixel(
                at: point, patternWidth: width, patternHeight: height, box: box
            )
            XCTAssertEqual(back.x, Float(x), accuracy: 0.001, "x round trip at \(x)")
            XCTAssertEqual(back.y, Float(y), accuracy: 0.001, "y round trip at \(y)")
        }
    }

    /// Dropping the cursor in the middle of the view must select the middle
    /// pixel, which for an even-sized detector is the boundary 63.5 — not 64.
    func testTheCentreOfTheViewMapsToTheCentreOfTheDetector() {
        let middle = PeakOverlayGeometry.pixel(
            at: CGPoint(x: box.width / 2, y: box.height / 2),
            patternWidth: width, patternHeight: height, box: box
        )
        XCTAssertEqual(middle.x, 63.5, accuracy: 0.001)
        XCTAssertEqual(middle.y, 63.5, accuracy: 0.001)
    }

    func testDegenerateGeometryIsHandledRatherThanDividingByZero() {
        XCTAssertEqual(
            PeakOverlayGeometry.center(
                x: 5, y: 5, patternWidth: 0, patternHeight: 0, box: box
            ),
            .zero
        )
        let zeroBox = PeakOverlayGeometry.pixel(
            at: CGPoint(x: 10, y: 10),
            patternWidth: width, patternHeight: height, box: .zero
        )
        XCTAssertEqual(zeroBox.x, 0)
        XCTAssertEqual(zeroBox.y, 0)
    }
}

/// The real-space ROI drives `displayedPattern` in *every* task, so it must be
/// drawn in every task — otherwise Bragg disks and Strain show a region-summed
/// CBED while the scan image draws a bare point crosshair, which is what the
/// probe kernel and the current-CBED peak count are then built from.
@MainActor
final class RealSpaceROIVisibilityTests: XCTestCase {

    func testAnROIIsAdvertisedWheneverItIsInForce() {
        let state = AppState()

        for mode in AnalysisMode.allCases {
            state.navigation.analysisMode = mode

            state.realSpaceShape = .point
            XCTAssertFalse(
                state.realSpaceROIIsRelevant,
                "\(mode): a point is not a region and must not draw an ROI"
            )

            for shape in RegionShape.allCases where shape != .point {
                state.realSpaceShape = shape
                XCTAssertTrue(
                    state.realSpaceROIIsRelevant,
                    "\(mode) with a \(shape) ROI: displayedPattern substitutes the "
                        + "summed pattern here, so the region must be visible"
                )
            }
        }
    }

    /// The exact condition `displayedPattern` uses to substitute the summed
    /// pattern is the condition the overlay is gated on — they cannot drift.
    func testVisibilityMatchesTheConditionThatSubstitutesThePattern() {
        let state = AppState()
        for shape in RegionShape.allCases {
            state.realSpaceShape = shape
            XCTAssertEqual(state.realSpaceROIIsRelevant, shape != .point, "\(shape)")
        }
    }
}
