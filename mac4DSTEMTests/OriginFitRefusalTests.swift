//
//  OriginFitRefusalTests.swift
//  An origin fit the kit refuses is said, with its reason, instead of an empty fit (no surface, NaN residual) that let
//  the calibration go on (#302).
//

import XCTest
import DSTEMCore

final class OriginFitRefusalTests: XCTestCase {
    /// Every position's origin failed (a dark or blank cube): refused, and the sentence says why.
    func testAScanWithNoMeasuredOriginIsRefused() {
        let nan = [Float](repeating: .nan, count: 6)
        XCTAssertThrowsError(try OriginCalibration.fitOriginTrimmedOrRefuse(
            measuredX: nan, measuredY: nan, width: 3, height: 2, fitFunction: .plane)) { error in
            XCTAssertEqual(error.localizedDescription, "The origin could not be fitted: no scan position has a measured origin.")
        }
        // The non-refusing fit (kept for the Friedel fallback's residual) is the empty one this replaced in the calibration.
        XCTAssertTrue(OriginCalibration.fitOriginTrimmed(measuredX: nan, measuredY: nan, width: 3, height: 2, fitFunction: .plane)
            .fittedX.isEmpty)
    }

    /// Too few positions for a plane is not refused: the kit fits their mean (`OriginFit.fitTrimmed`).
    func testTooFewPositionsFitTheirMean() throws {
        let fit = try OriginCalibration.fitOriginTrimmedOrRefuse(measuredX: [64, 64.2], measuredY: [63.8, 64], width: 2, height: 1,
                                                                 fitFunction: .plane)
        XCTAssertEqual(fit.fittedX.count, 2)
    }

    /// A scan the plane fits gives the same surface the non-refusing fit gives.
    func testAFittableScanMatchesTheExistingFit() throws {
        let w = 4, h = 3
        let x = (0..<(w * h)).map { Float(64) + 0.1 * Float($0 % w) }, y = (0..<(w * h)).map { Float(63) + 0.05 * Float($0 / w) }
        let refused = try OriginCalibration.fitOriginTrimmedOrRefuse(measuredX: x, measuredY: y, width: w, height: h, fitFunction: .plane)
        let plain = OriginCalibration.fitOriginTrimmed(measuredX: x, measuredY: y, width: w, height: h, fitFunction: .plane)
        XCTAssertEqual(refused.fittedX, plain.fittedX)
        XCTAssertEqual(refused.fittedY, plain.fittedY)
    }
}
