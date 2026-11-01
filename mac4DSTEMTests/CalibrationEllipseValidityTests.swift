//
//  CalibrationEllipseValidityTests.swift
//  Lane F-B row 29: `hasEllipse` accepted
//  b <= 0 and a < 0 while the readiness row required a > 0 && b > 0, so a file with such an
//  ellipse had e = b/a <= 0 applied to every Bragg vector while the row read "No
//  detector-distortion correction".
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class CalibrationEllipseValidityTests: XCTestCase {

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

    /// The refusal is said by name: which values, and why. No ellipse in the file, or a valid one, says nothing.
    func testRow29TheRefusalNamesTheValueAndTheReason() throws {
        let negative = try XCTUnwrap(PixelCalibration.ellipseRefusal(a: 19.5, b: -1, theta: 0.3))
        XCTAssertTrue(negative.contains("b = -1"), negative)
        XCTAssertTrue(negative.contains("semi-axis b is not a positive number"), negative)
        XCTAssertFalse(negative.contains("semi-axis a"), negative)
        let partial = try XCTUnwrap(PixelCalibration.ellipseRefusal(a: nil, b: 1, theta: 0.3))
        XCTAssertTrue(partial.contains("a = missing"), partial)
        XCTAssertTrue(partial.contains("incomplete"), partial)
        let nan = try XCTUnwrap(PixelCalibration.ellipseRefusal(a: .nan, b: 1, theta: 0.3))
        XCTAssertTrue(nan.contains("semi-axis a is not a positive number"), nan)
        XCTAssertNil(PixelCalibration.ellipseRefusal(a: nil, b: nil, theta: 0))
        XCTAssertNil(PixelCalibration.ellipseRefusal(a: 19.5, b: 17.9, theta: 0.3))
    }

    /// A session file whose ellipse has b <= 0 reopens with no ellipse AND the reason. Before, the triple was dropped
    /// with nothing said: the Ellipse row read "not set". Break it by dropping the `else` branch in
    /// `SessionSidecarReading`.
    func testRow29ASavedNonPositiveEllipseIsRefusedByName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalibrationEllipseValidityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (b, refused) in [(-17.9, true), (17.9, false)] {
            var saved = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
            saved.ellipseA = 19.5
            saved.ellipseB = b
            saved.ellipseTheta = 0.4
            let url = dir.appendingPathComponent("b\(b).mac4dstem.h5")
            try BraggVectorEMDWriter.mergeCalibration(saved, qWidth: 32, qHeight: 32, to: url,
                                                      loadSpecification: nil, replayRecord: nil)
            let read = try XCTUnwrap(BraggVectorEMDWriter.loadSession(from: url).calibration)
            if refused {
                XCTAssertNil(read.ellipseA)
                let note = try XCTUnwrap(read.ellipseRefusalNote)
                XCTAssertTrue(note.contains("semi-axis b is not a positive number"), note)
            } else {
                XCTAssertEqual(read.ellipseB, 17.9)
                XCTAssertNil(read.ellipseRefusalNote)
            }
        }
    }
}
