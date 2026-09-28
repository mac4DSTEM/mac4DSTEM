import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Owner decision 5 (2026-09-28): an ellipse typed in Prepare, in py4DSTEM's
/// convention — semi-axes a, b in pixels, θ the tilt of the a axis from qx
/// (the row axis) in degrees (`py4DSTEM/process/calibration/ellipse.py`
/// `fit_ellipse_1D` docstring). The owner's calibrated Al-Mg-Si cube is the
/// worked case: a 19.50, b 17.97, θ 20.5° (`archive/v4/almgsi-gateD-2026-09-24.md`
/// part 7), where the detector's x/y angle is 69.5° — the value a wrong
/// frame would take.
///
/// Ground truth is analytic, not the app: points sampled on py4DSTEM's
/// ellipse must map to a circle of radius b under the correction. 20.5° is
/// deliberately not symmetric — at 0°, 45° or 90° a swapped or mirrored
/// frame would still pass.
@MainActor
final class ManualEllipseTests: XCTestCase {
    private let a = 19.50, b = 17.97, thetaDegrees = 20.5

    /// Corrected radii of 36 points on py4DSTEM's ellipse (a, b, θ from qx),
    /// through the app's frame: py4DSTEM qx is the app's detector y (dy),
    /// qy its x (dx).
    private func correctedRadii(_ calibration: Calibration) -> [Double] {
        let theta = thetaDegrees * .pi / 180
        return (0..<36).map { i in
            let t = Double(i) * .pi / 18
            let qx = a * cos(t) * cos(theta) - b * sin(t) * sin(theta)
            let qy = a * cos(t) * sin(theta) + b * sin(t) * cos(theta)
            let c = calibration.ellipseCorrectedOffset(dx: Float(qy), dy: Float(qx))
            return hypot(Double(c.x), Double(c.y))
        }
    }

    func testATypedEllipseMapsPy4DSTEMsEllipseToACircleOfRadiusB() {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualEllipse(a: a, b: b, thetaDegrees: thetaDegrees))
        for r in correctedRadii(session.calibration) {
            XCTAssertEqual(r, b, accuracy: 1e-3)
        }
    }

    /// Anti-vacuity: the same check fails, by about a pixel, when the angle
    /// is typed in the detector's x/y frame. Without this the test above
    /// could be passing for any θ.
    func testTheDetectorXYAngleIsNotTheConventionAndTheCheckSeesIt() {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualEllipse(a: a, b: b, thetaDegrees: 90 - thetaDegrees))
        let radii = correctedRadii(session.calibration)
        XCTAssertGreaterThan(radii.max()! - radii.min()!, 0.5)
    }

    /// The typed route and the file route (the owner's copy of 2026-09-25
    /// carried a, b, θ as py4DSTEM keys, θ in radians) give the same
    /// correction.
    func testATypedEllipseEqualsTheSameEllipseImportedFromAFile() {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualEllipse(a: a, b: b, thetaDegrees: thetaDegrees))
        let fromFile = Calibration(ellipseA: a, ellipseB: b, ellipseTheta: thetaDegrees * .pi / 180)
        XCTAssertEqual(correctedRadii(session.calibration), correctedRadii(fromFile))
    }

    /// Through the app, as the Apply Ellipse button calls it: the session
    /// tests alone stay green if the glue swaps a and b or drops the degree
    /// conversion (the DM4 lesson, Gate B 2026-09-28).
    func testTheAppWritesTheTypedValuesInTheirPlaces() {
        let appState = AppState()
        appState.applyManualEllipse(a: a, b: b, thetaDegrees: thetaDegrees)
        let calibration = appState.calibrationSession.calibration
        XCTAssertEqual(calibration.ellipseA, a)
        XCTAssertEqual(calibration.ellipseB, b)
        XCTAssertEqual(calibration.ellipseTheta!, thetaDegrees * .pi / 180, accuracy: 1e-12)
        XCTAssertEqual(appState.calibrationSession.provenance.ellipse, .manual)
    }

    func testATypedEllipseIsMarkedManualAndRetiresTheLastFit() {
        let session = CalibrationSession()
        session.lastEllipseFit = EllipseCalibrationFit(
            centerQX: 64, centerQY: 64, a: 1.03, b: 0.97, theta: 0.4,
            normalizedResidual: 0.02, conicResidual: 0.02, sampleCount: 900,
            occupiedAngularBins: 33, model: .conic, profile: nil,
            profileFallbackReason: nil
        )
        session.ellipseFitAnywayOffer = 20
        XCTAssertNil(session.applyManualEllipse(a: a, b: b, thetaDegrees: thetaDegrees))
        XCTAssertEqual(session.provenance.ellipse, .manual)
        XCTAssertNil(session.lastEllipseFit, "the model and residual rows described another ellipse")
        XCTAssertNil(session.ellipseFitAnywayOffer)
    }

    /// py4DSTEM's a is the semi-major axis. The owner's axes typed in the
    /// wrong order with θ kept would be accepted and leave a 17.97–21.16 px
    /// spread (Gate B refuter, 2026-09-28), so a < b is refused; a circle
    /// (a = b) is not.
    func testTheShorterAxisAsAIsRefusedAndACircleIsNot() {
        let session = CalibrationSession()
        XCTAssertNotNil(session.applyManualEllipse(a: b, b: a, thetaDegrees: thetaDegrees))
        XCTAssertNil(session.calibration.ellipseA, "a refusal writes nothing")
        XCTAssertNil(session.applyManualEllipse(a: b, b: b, thetaDegrees: thetaDegrees))
    }

    /// A value that cannot be an ellipse writes nothing: the earlier ellipse
    /// and its provenance stand, as after a refused fit.
    func testValuesThatCannotBeAnEllipseAreRefusedAndChangeNothing() {
        let session = CalibrationSession()
        XCTAssertNil(session.applyManualEllipse(a: a, b: b, thetaDegrees: thetaDegrees))
        let before = session.calibration
        for (ra, rb, rt) in [(0.0, b, thetaDegrees), (a, -1.0, thetaDegrees),
                             (Double.nan, b, thetaDegrees), (a, b, Double.infinity)] {
            XCTAssertNotNil(session.applyManualEllipse(a: ra, b: rb, thetaDegrees: rt),
                            "a \(ra), b \(rb), θ \(rt) must be refused")
        }
        XCTAssertEqual(session.calibration.ellipseA, before.ellipseA)
        XCTAssertEqual(session.calibration.ellipseB, before.ellipseB)
        XCTAssertEqual(session.calibration.ellipseTheta, before.ellipseTheta)
        XCTAssertEqual(session.provenance.ellipse, .manual)
    }
}
