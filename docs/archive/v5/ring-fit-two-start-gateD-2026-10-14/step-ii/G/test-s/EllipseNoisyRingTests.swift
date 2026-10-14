import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The profile ring fit (`EllipseCalibration.fitAmorphousRing`, behind the Fit
/// button's `fitBestAvailable`) can end in a basin that carries no ring: a ring drained
/// into the background (I1 at 0, a ring sigma at its 0.25 px floor) or one that left the
/// ring for a neighbouring feature and the centre 10-40 px away. The residual cap does
/// not refuse either, because noise inflates the normalised residual of any model
/// (`archive/v5/ring-fit-two-start-gateD-2026-10-14.md`). A fit whose mean radius moved
/// more than 8 % from the conic fit it started from is another feature, not the
/// calibration ring: it is refused, and the Fit falls back to the conic and says why.
///
/// These two rings are noisy 192 x 192 plants on which py4DSTEM's start was accepted
/// wrong, found by scanning 2568 plants (128-256 px square, R 40-100, ellipticity 0-3 %,
/// a 60 degree gap or none, noise 0.03 and 0.10, a few seeds each; no data file) with
/// this same renderer: it accepted a profile fit off by more than 1 % in (a + b) / 2 on
/// 221 of them, all at noise 0.10 (92 at 192 px, 32 at 224, 97 at 256, none below 192);
/// 87 of the 221 are the dead ring, 130 the drifting kind (ring sigmas of 1-7 px, the
/// centre 10-40 px off), 4 neither. Both outcomes are basins of the optimiser, not
/// rounding accidents: the centre guess moved by 1e-9, 1e-6 and 1e-3 px leaves the dead
/// ring unchanged and moves the drifting one's mean radius by 0.1 % of R. The dead ring
/// ends 17.7 % and the drifting one 41.7 % from the conic fit's radius.
///
/// On both the Fit must refuse the profile model and say why: no profile fit is returned,
/// the conic is, and `profileFallbackReason` names the move from the conic fit. The test
/// does not pin the conic's own radius (1.3 % and 1.0 % high on these plants), only that
/// the wrong profile fit is not accepted.
final class EllipseNoisyRingTests: XCTestCase {
    /// I = exp(-((rho - 1) R)^2 / 2 s^2), rho the conic's elliptical radius in
    /// py4DSTEM's (A, B, C) convention with qx the row, s = 3 px, R = (a + b) / 2,
    /// a / b = 1 + eps, a along theta; optional 60 degree gap starting at (47 seed)
    /// mod 360 degrees; additive Gaussian noise (SplitMix64 seeded seed + 1,
    /// Box-Muller pairs over even and odd linear index), Float pixels.
    private struct Plant {
        let size: Int, radius: Double, eps: Double, thetaDegrees: Double, gap: Double, noise: Double, seed: Int
        var b: Double { 2 * radius / (2 + eps) }
        var a: Double { b * (1 + eps) }
        var centerQX: Double { Double(size) / 2 + 0.37 + 2.5 * sin(1.3 * Double(seed) + 0.2) }
        var centerQY: Double { Double(size) / 2 - 0.41 + 2.5 * cos(1.9 * Double(seed) + 0.7) }

        func render() -> DiffractionPattern {
            let theta = thetaDegrees * .pi / 180
            let sin2 = sin(theta) * sin(theta), cos2 = cos(theta) * cos(theta)
            let A = sin2 / (b * b) + cos2 / (a * a)
            let C = cos2 / (b * b) + sin2 / (a * a)
            let B = 2 * (b * b - a * a) * sin(theta) * cos(theta) / (a * a * b * b)
            let mean = (a + b) / 2
            let gapStart = Double((47 * seed) % 360)
            var state = UInt64(seed) &+ 1
            func uniform() -> Double {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return (Double((z ^ (z >> 31)) >> 11) + 0.5) / 9_007_199_254_740_992.0
            }
            var pixels = [Float](repeating: 0, count: size * size)
            var spare = 0.0
            for qx in 0..<size {
                for qy in 0..<size {
                    let dx = Double(qx) - centerQX, dy = Double(qy) - centerQY
                    let rho = max(0, A * dx * dx + B * dx * dy + C * dy * dy).squareRoot()
                    let distance = (rho - 1) * mean
                    var value = exp(-(distance * distance) / (2 * 3.0 * 3.0))
                    if gap > 0 {
                        var angle = atan2(dy, dx) * 180 / .pi
                        angle = (angle - gapStart).truncatingRemainder(dividingBy: 360)
                        if angle < 0 { angle += 360 }
                        if angle < gap { value = 0 }
                    }
                    if noise > 0 {
                        if (qx * size + qy) % 2 == 0 {
                            let u1 = uniform(), u2 = uniform()
                            let r = (-2 * log(u1)).squareRoot()
                            value += noise * r * cos(2 * .pi * u2)
                            spare = noise * r * sin(2 * .pi * u2)
                        } else {
                            value += spare
                        }
                    }
                    pixels[qx * size + qy] = Float(value)
                }
            }
            return DiffractionPattern(qy: size, qx: size, pixels: pixels)
        }
    }

    /// A click's error from the plant (1.3, -0.9 px), the annulus (b - 20, a + 20).
    private func assertFallsBackToTheConic(_ plant: Plant, _ name: String) {
        let fit: EllipseCalibrationFit
        do {
            fit = try EllipseCalibration.fitBestAvailable(
                pattern: plant.render(),
                centerQX: plant.centerQX + 1.3, centerQY: plant.centerQY - 0.9,
                innerRadius: plant.b - 20, outerRadius: plant.a + 20)
        } catch {
            XCTFail("\(name) was refused outright (the conic seed fits it): \(error)")
            return
        }
        if let profile = fit.profile {
            XCTAssertLessThanOrEqual(abs((fit.a + fit.b) / 2 / plant.radius - 1), 0.01,
                                     "\(name): profile fit accepted with mean radius \((fit.a + fit.b) / 2) against \(plant.radius) (I1 \(profile.ringIntensity), sigmas \(profile.innerSigma), \(profile.outerSigma))")
        }
        XCTAssertNil(fit.profile, "\(name): a profile fit was returned")
        XCTAssertEqual(fit.model, .conic, name)
        let reason = fit.profileFallbackReason ?? "nil"
        XCTAssertTrue(reason.contains("moved the ring") && reason.contains("from the conic fit"),
                      "\(name): fallback reason was \(reason)")
    }

    /// The dead ring: R 70, eps 1 %, theta 0, a 60 degree gap, noise 0.10, seed 3.
    /// Py4DSTEM's start ends at I1 0 with a ring sigma at 0.25 px, 17.7 % from the conic's radius.
    func testNoisyGappedRingFallsBackToTheConicNamingTheMove() {
        assertFallsBackToTheConic(Plant(size: 192, radius: 70, eps: 0.01, thetaDegrees: 0, gap: 60, noise: 0.10, seed: 3),
                                  "dead ring n192-R70-e10-t0.0-g60-s100-k3")
    }

    /// The drifting ring: R 70, eps 1 %, theta 112.5, no gap, noise 0.10, seed 2.
    /// Py4DSTEM's start keeps ring sigmas of 2.9 and 3.9 px but ends 39 px off centre, 41.7 % from the conic's radius.
    func testNoisyRingDoesNotDriftOffCentreFallsBackToTheConic() {
        assertFallsBackToTheConic(Plant(size: 192, radius: 70, eps: 0.01, thetaDegrees: 112.5, gap: 0, noise: 0.10, seed: 2),
                                  "drifting ring n192-R70-e10-t112.5-g0-s100-k2")
    }
}
