//
//  CalibrationEllipseRow29Tests.swift
//  Lane F-B row 29 (docs/archive/v4/review-2026-09-30-findings.md): `hasEllipse` accepted
//  b <= 0 and a < 0 while the readiness row required a > 0 && b > 0, so a file with such an
//  ellipse had e = b/a <= 0 applied to every Bragg vector while the row read "No
//  detector-distortion correction".
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class CalibrationEllipseRow29Tests: XCTestCase {

    private func calibration(a: Double, b: Double) -> Calibration {
        var c = Calibration()
        c.ellipseA = a
        c.ellipseB = b
        c.ellipseTheta = 0.4
        return c
    }

    func testRow29NonPositiveAxesAreNotAnEllipseAndCorrectNothing() {
        for (a, b) in [(19.5, 0.0), (19.5, -17.9), (-19.5, 17.9), (-19.5, -17.9), (0.0, 5.0)] {
            let c = calibration(a: a, b: b)
            XCTAssertFalse(c.hasEllipse, "a \(a), b \(b)")
            let out = c.ellipseCorrectedOffset(dx: 3, dy: 4)
            XCTAssertEqual(out.x, 3, "a \(a), b \(b) must leave the vector alone")
            XCTAssertEqual(out.y, 4, "a \(a), b \(b) must leave the vector alone")
        }
    }

    func testRow29ValidEllipseStillCorrects() {
        let c = calibration(a: 19.5, b: 17.97)
        XCTAssertTrue(c.hasEllipse)
        let out = c.ellipseCorrectedOffset(dx: 3, dy: 4)
        XCTAssertNotEqual(out.x, 3)
    }

    /// An a < b ellipse is a valid transform (py4DSTEM's `_transform` uses e = b/a with no
    /// ordering), so an imported one is kept; only manual entry enforces a >= b.
    func testRow29SemiMinorFirstFileEllipseIsKept() {
        XCTAssertTrue(calibration(a: 17.97, b: 19.5).hasEllipse)
    }

    /// The adoption lines in H5Reader / BraggVectorEMDWriter go through this one predicate.
    func testRow29AcceptedEllipseDropsTheWholeTripleOnABadAxis() {
        XCTAssertNil(Calibration.acceptedEllipse(a: 19.5, b: -1, theta: 0.3))
        XCTAssertNil(Calibration.acceptedEllipse(a: nil, b: 1, theta: 0.3))
        let ok = Calibration.acceptedEllipse(a: 19.5, b: 17.9, theta: 0.3)
        XCTAssertEqual(ok?.a, 19.5)
        XCTAssertEqual(ok?.b, 17.9)
        XCTAssertEqual(ok?.theta, 0.3)
    }
}
