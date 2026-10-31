//
//  PeakOverlayGeometryTests.swift
//  Where a Bragg-peak marker lands on a non-square pattern, and when the overlay draws a disk or only a marker.
//  Moved from the peak-overlay-test harness into the unit suite.
//

import CoreGraphics
import XCTest
@testable import mac4DSTEM

final class PeakOverlayGeometryTests: XCTestCase {
    private let fitted = CGSize(width: 640, height: 320)

    func testPeakCentresMapPixelCentresIntoTheFittedBox() {
        let cases: [(String, Float, Float, CGPoint)] = [
            ("first_pixel", 0, 0, CGPoint(x: 5, y: 5)),
            ("interior_integer", 12, 8, CGPoint(x: 125, y: 85)),
            ("subpixel", 12.25, 8.5, CGPoint(x: 127.5, y: 90)),
            ("last_pixel", 63, 31, CGPoint(x: 635, y: 315)),
        ]
        for (name, x, y, expected) in cases {
            let actual = PeakOverlayGeometry.center(x: x, y: y, patternWidth: 64, patternHeight: 32, box: fitted)
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, name)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, name)
        }
    }

    func testTheDiskRadiusFollowsTheProbeAndStaysCircularInASqueezedBox() throws {
        let fittedRadius = try XCTUnwrap(
            PeakOverlayGeometry.radius(probeRadius: 3, patternWidth: 64, patternHeight: 32, box: fitted))
        XCTAssertEqual(fittedRadius, 30, accuracy: 1e-9)
        let squeezed = try XCTUnwrap(PeakOverlayGeometry.radius(
            probeRadius: 3, patternWidth: 64, patternHeight: 32, box: CGSize(width: 640, height: 300)))
        XCTAssertEqual(squeezed, 28.125, accuracy: 1e-9)
    }

    /// No probe kernel means no invented disk extent: the overlay draws a marker instead.
    func testNoUsableProbeDrawsAMarkerNotADisk() {
        for (name, probe) in [("no_kernel", nil), ("nan_probe", Float.nan), ("zero_probe", Float(0))] as [(String, Float?)] {
            XCTAssertNil(PeakOverlayGeometry.radius(probeRadius: probe, patternWidth: 64, patternHeight: 32, box: fitted), name)
        }
    }
}
