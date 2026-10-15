import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Refuter D, item 3: the row/column convention at AppState.calibrateEllipse on NON-square patterns, through the app's own
/// entry point (not the harness). Values printed as bit patterns are compared with the pre-switch code (7f192da9's
/// EllipseCalibration.swift compiled standalone on the same pixels).
@MainActor
final class EllipseNonSquareAppStateRefuterTests: XCTestCase {
    private struct RD_SM64 { var s: UInt64; mutating func next() -> Double { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; z ^= z >> 31; return Double(z >> 11) / Double(1 << 53) } }
    private func rdRingPixels(width: Int, height: Int, cRow: Double, cCol: Double, a: Double, b: Double, theta: Double, sigma: Double, seed: UInt64) -> [Float] {
        var rng = RD_SM64(s: seed)
        var px = [Float](repeating: 0, count: width * height)
        let ct = cos(theta), st = sin(theta)
        for r in 0..<height { for c in 0..<width {
            let dr = Double(r) - cRow, dc = Double(c) - cCol
            // coordinates along the semi-major axis (tilted theta from the ROW axis) and the semi-minor
            let u = dr * ct + dc * st, v = -dr * st + dc * ct
            let rho = (u * u / (a * a) + v * v / (b * b)).squareRoot()
            let radial = (rho - 1) * (a + b) / 2
            let value = 100 * exp(-radial * radial / (2 * sigma * sigma)) + 2 * rng.next()
            px[r * width + c] = Float(value)
        } }
        return px
    }
    private let rdCases: [(Int, Int, Double, Double, Double, Double, Double)] = [
        (80, 64, 34, 30, 22, 18, 0.4), (50, 90, 40, 22, 19, 17, 1.0), (64, 80, 30, 34, 22, 18, 0.4), (96, 48, 20, 55, 21, 19.5, 2.3)]

    func testCalibrateEllipseOnNonSquarePatternsRecoversRowColumnTruthAndMatchesPreSwitchBits() async throws {
        var fits: [[Double]] = []   // per case: centerQX, centerQY, a, b, theta, normalizedResidual
        for (i, k) in rdCases.enumerated() {
            let (w, h, cr, cc, a, b, th) = k
            let app = AppState()
            await app.openDemoFixture(calibrated: true)
            app.meanPattern = DiffractionPattern(qy: h, qx: w, pixels: rdRingPixels(width: w, height: h, cRow: cr, cCol: cc, a: a, b: b, theta: th, sigma: 2, seed: UInt64(100 + i)))
            app.navigation.analysisMode = .virtualDetector
            // the aperture centre is (x = column, y = row); the app hands the fit (row, column)
            app.aperture = Aperture(centerX: Float(cc - 0.9), centerY: Float(cr + 0.7), inner: 0, outer: 10)
            app.calibrationSession.ellipseFitInnerRadius = 10
            app.calibrationSession.ellipseFitOuterRadius = 30
            await app.calibrateEllipse()
            let fit = try XCTUnwrap(app.calibrationSession.lastEllipseFit, "case \(i) did not fit: \(app.statusText)")
            fits.append([fit.centerQX, fit.centerQY, fit.a, fit.b, fit.theta, fit.normalizedResidual])
            XCTAssertEqual(fit.centerQX, cr, accuracy: 0.05, "case \(i): the fit's centerQX is the ROW")
            XCTAssertEqual(fit.centerQY, cc, accuracy: 0.05, "case \(i): the fit's centerQY is the COLUMN")
            XCTAssertEqual(fit.a, a, accuracy: 0.05); XCTAssertEqual(fit.b, b, accuracy: 0.05)
            XCTAssertEqual(fit.theta, th, accuracy: 0.01)
            XCTAssertEqual(app.calibrationSession.calibration.ellipseTheta, fit.theta)
        }
        // Old values (7f192da9's EllipseCalibration.swift, standalone -O, same pixels): bit patterns of cqx cqy a b theta res.
        let expected: [[UInt64]] = [
            [4629981658662369884, 4629137681650380847, 4626885692158328426, 4625760090874246504, 4600883453294973430, 4573222263564240288],
            [4630826244857649607, 4626885599076081185, 4626041530532316234, 4625478833459682102, 4607179251661257553, 4573035947952047484],
            [4629137384674142927, 4629981786327970412, 4626885640210897348, 4625759179499901574, 4600872130238966553, 4573217646114708752],
            [4626322768737394462, 4632937431348229012, 4626604513563305054, 4626182430775386306, 4612360510235552389, 4573158931434066744],
        ]
        // Compared as numbers, not parsed back from printed text (the first version split a printed line and dropped its first
        // integer, which only worked while the model name held no integer).
        XCTAssertEqual(fits.count, expected.count)
        for (i, (fit, old)) in zip(fits, expected).enumerated() {
            XCTAssertEqual(fit.count, 6)
            for (new, oldBits) in zip(fit, old) {
                let b = Double(bitPattern: oldBits)
                // Measured: up to 911 ulp (a, case 1: 1.7e-13 relative) between the Xcode test host and the standalone build.
                XCTAssertEqual(new, b, accuracy: 1e-11 * abs(b), "case \(i)")
            }
        }
    }
}
