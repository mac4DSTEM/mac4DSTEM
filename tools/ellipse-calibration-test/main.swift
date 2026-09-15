import Foundation

struct Fixture: Decodable {
    let cases: [RingCase]
    let profileCases: [ProfileCase]
    let overlapCase: ProfileCase
    let spotCases: [SpotCase]
}
struct SpotCase: Decodable {
    let name: String
    let height: Int
    let width: Int
    let centerQX: Double
    let centerQY: Double
    let innerRadius: Double
    let outerRadius: Double
    /// "fit" or "refuse" — what this fixture's geometry entitles it to on the
    /// default (acceptSparseCoverage: false) path.
    let expect: String
    let why: String
    /// Same, on the anyway (acceptSparseCoverage: true) path. 2026-09-15.
    let expectAnyway: String
    let whyAnyway: String
    /// The planted ellipse — a=b, theta=0 when the fixture is circular.
    let a: Double
    let b: Double
    let theta: Double
    let pixels: [Float]
}
struct RingCase: Decodable {
    let name: String
    let height: Int
    let width: Int
    let centerQX: Double
    let centerQY: Double
    let a: Double
    let b: Double
    let theta: Double
    let innerRadius: Double
    let outerRadius: Double
    let pixels: [Float]
}

struct ProfileCase: Decodable {
    let name: String
    let height: Int
    let width: Int
    let centerQX: Double
    let centerQY: Double
    let a: Double
    let b: Double
    let theta: Double
    let centralIntensity: Double
    let ringIntensity: Double
    let centralSigma: Double
    let innerSigma: Double
    let outerSigma: Double
    let background: Double
    let innerRadius: Double
    let outerRadius: Double
    let pixels: [Float]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func angleError(_ lhs: Double, _ rhs: Double) -> Double {
    let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi)
    return min(raw, .pi - raw)
}

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
for test in fixture.cases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    let fit = try EllipseCalibration.fit1D(
        pattern: pattern, centerQX: test.centerQX + 0.8, centerQY: test.centerQY - 0.6,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    )
    guard abs(fit.centerQX - test.centerQX) < 0.08,
          abs(fit.centerQY - test.centerQY) < 0.08,
          abs(fit.a - test.a) < 0.18,
          abs(fit.b - test.b) < 0.18,
          angleError(fit.theta, test.theta) < 0.008,
          fit.normalizedResidual < 0.12 else {
        fail("\(test.name) differs: \(fit)")
    }
    print("PASS: \(test.name) center/axes/theta residual \(fit.normalizedResidual)")
}

for test in fixture.profileCases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    let fit = try EllipseCalibration.fitBestAvailable(
        pattern: pattern,
        centerQX: test.centerQX + 0.7, centerQY: test.centerQY - 0.5,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    )
    guard fit.model == .asymmetricGaussian,
          abs(fit.centerQX - test.centerQX) < 0.2,
          abs(fit.centerQY - test.centerQY) < 0.2,
          abs(fit.a - test.a) < 0.3,
          abs(fit.b - test.b) < 0.3,
          angleError(fit.theta, test.theta) < 0.015,
          let profile = fit.profile,
          abs(profile.innerSigma - test.innerSigma) < 0.35,
          abs(profile.outerSigma - test.outerSigma) < 0.35,
          abs(profile.background - test.background) < 0.5,
          fit.normalizedResidual < 0.08 else {
        fail("\(test.name) profile differs: \(fit)")
    }
    print("PASS: \(test.name) 11-parameter asymmetric profile")
}

let overlap = fixture.overlapCase
let overlapPattern = DiffractionPattern(
    qy: overlap.height, qx: overlap.width, pixels: overlap.pixels
)
let fallback = try EllipseCalibration.fitBestAvailable(
    pattern: overlapPattern,
    centerQX: overlap.centerQX, centerQY: overlap.centerQY,
    innerRadius: overlap.innerRadius, outerRadius: overlap.outerRadius,
    maximumConicResidual: 0.4, maximumProfileResidual: 0.001
)
guard fallback.model == .conic,
      fallback.profile == nil,
      fallback.profileFallbackReason != nil,
      fallback.a.isFinite, fallback.b.isFinite else {
    fail("overlapping-ring profile failure did not preserve the conic calibration")
}
print("PASS: overlapping/noisy profile retains safe conic fallback")

let convention = fixture.cases[0]
var calibration = Calibration()
calibration.ellipseA = convention.a
calibration.ellipseB = convention.b
calibration.ellipseTheta = convention.theta
// py4DSTEM major-axis point is (qx=a cosθ, qy=a sinθ); app offset is
// (dx=qy, dy=qx). Correction must circularize it to radius b.
let rawDX = Float(convention.a * sin(convention.theta))
let rawDY = Float(convention.a * cos(convention.theta))
let corrected = calibration.ellipseCorrectedOffset(dx: rawDX, dy: rawDY)
guard abs(hypot(corrected.x, corrected.y) - Float(convention.b)) < 1e-5 else {
    fail("py4DSTEM qx/qy to app x/y ellipse transform differs")
}
print("PASS: py4DSTEM/app detector-axis correction convention")

let blank = DiffractionPattern(qy: 40, qx: 60, pixels: [Float](repeating: 1, count: 2400))
do {
    _ = try EllipseCalibration.fit1D(
        pattern: blank, centerQX: 20, centerQY: 30, innerRadius: 8, outerRadius: 18
    )
    fail("constant input unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientSignal {}
print("PASS: blank annulus rejected")

var spots = [Float](repeating: 0, count: 60 * 80)
for (qx, qy) in [(15, 40), (45, 40), (30, 25), (30, 55)] {
    spots[qx * 80 + qy] = 10
}
do {
    _ = try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20
    )
    fail("four-spot degeneracy unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientAngularCoverage {}
print("PASS: angularly degenerate input rejected")
do {
    _ = try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20,
        acceptSparseCoverage: true
    )
    fail("four-spot degeneracy unexpectedly fitted anyway")
} catch EllipseCalibration.FitError.insufficientAngularCoverage {}
print("PASS: angularly degenerate input rejected anyway (below the hard floor too)")
// Spots, rings, and what an ellipse fitted to them is entitled to claim.
// Every pattern here is CIRCULAR by construction, so any a/b a fit reports is
// a statement about the arrangement of the diffracting grains, not about the
// detector. See `EllipseCalibration.fit1D`'s coverage bound for why the rule
// is degeneracy and not a statistic; `reference.py` carries each case's reason.
for test in fixture.spotCases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    do {
        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius)
        guard test.expect == "fit" else {
            fail("\(test.name) was fitted (a/b \(fit.a / fit.b)) when it should be "
                 + "refused — \(test.why)")
        }
        // AND THE ANSWER MUST BE THE DETECTOR'S. Every fixture here is
        // circular; a fit that reports distortion has measured the grains.
        guard abs(fit.a / fit.b - 1) < 0.02 else {
            fail("\(test.name) reported a/b \(fit.a / fit.b) on a detector with no "
                 + "distortion in it")
        }
        print(String(format: "PASS: %@ fitted isotropic (a/b %.4f, %d of 36 bins)",
                     test.name, fit.a / fit.b, fit.occupiedAngularBins))
    } catch let error as EllipseCalibration.FitError {
        guard test.expect == "refuse" else {
            fail("\(test.name) was refused (\(error)) when it should fit — \(test.why)")
        }
        print("PASS: \(test.name) refused — \(test.why)")
    }
}

// The anyway path (2026-09-15): acceptSparseCoverage: true. Same fixtures,
// `expectAnyway`/`whyAnyway` this time — the coverage floor drops to a third
// of the bins, and an accepted fit below the five-sixths default bound must
// come back marked `sparseCoverage`.
for test in fixture.spotCases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    do {
        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius,
            acceptSparseCoverage: true)
        guard test.expectAnyway == "fit" else {
            fail("\(test.name) was fitted anyway (a/b \(fit.a / fit.b)) when it should be "
                 + "refused — \(test.whyAnyway)")
        }
        guard fit.sparseCoverage == (fit.occupiedAngularBins < 30) else {
            fail("\(test.name) sparseCoverage \(fit.sparseCoverage) disagrees with "
                 + "occupiedAngularBins \(fit.occupiedAngularBins) (bound is 30)")
        }
        if test.name == "sparse_ring_6_azimuths_elliptic" {
            // THE POSITIVE CASE: a real 6% ellipticity, sparse coverage, and
            // the anyway path must measure the DETECTOR, not refuse it.
            // Tolerances measured 2026-09-15 at a 0.066 px, b 0.05 px, theta
            // 0.0002 rad off the planted ellipse; kept tight against that
            // (not the 0.3/0.3/0.02 used for the profile-fit fixtures) rather
            // than loosened to a round number.
            guard abs(fit.a - test.a) < 0.15, abs(fit.b - test.b) < 0.15,
                  angleError(fit.theta, test.theta) < 0.003 else {
                fail("\(test.name) elliptic fit differs: got a \(fit.a) b \(fit.b) "
                     + "theta \(fit.theta), planted a \(test.a) b \(test.b) theta \(test.theta)")
            }
            print(String(format: "PASS: %@ fitted elliptic anyway (a %.3f b %.3f theta "
                         + "%.4f, %d of 36 bins, sparseCoverage %@, tolerance a/b<0.15 "
                         + "theta<0.003)", test.name, fit.a, fit.b, fit.theta,
                         fit.occupiedAngularBins, "\(fit.sparseCoverage)"))
        } else {
            // Every other fitted fixture is circular by construction: the
            // anyway path changes what is ADMITTED, never what a fit reports.
            guard abs(fit.a / fit.b - 1) < 0.02 else {
                fail("\(test.name) reported a/b \(fit.a / fit.b) anyway on a detector "
                     + "with no distortion in it")
            }
            print(String(format: "PASS: %@ fitted isotropic anyway (a/b %.4f, %d of 36 "
                         + "bins, sparseCoverage %@)", test.name, fit.a / fit.b,
                         fit.occupiedAngularBins, "\(fit.sparseCoverage)"))
        }
    } catch let error as EllipseCalibration.FitError {
        guard test.expectAnyway == "refuse" else {
            fail("\(test.name) was refused anyway (\(error)) when it should fit — "
                 + "\(test.whyAnyway)")
        }
        switch test.name {
        case "grains_3_one_annulus", "grains_6_one_annulus":
            guard case .moreThanOneRing = error else {
                fail("\(test.name) refused anyway with \(error), expected "
                     + "moreThanOneRing — \(test.whyAnyway)")
            }
        case "halo_spots_50to1":
            guard case .insufficientAngularCoverage = error else {
                fail("\(test.name) refused anyway with \(error), expected "
                     + "insufficientAngularCoverage — \(test.whyAnyway)")
            }
        default:
            fail("\(test.name) refused anyway with unexpected error \(error) — "
                 + "\(test.whyAnyway)")
        }
        print("PASS: \(test.name) refused anyway — \(test.whyAnyway)")
    }
}

// The one-ring check must measure about the FITTED centre. Gate B
// (2026-09-15) applied a mutation that measures about the SEED centre, and it
// survived because every spot case above is seeded exactly. Seeded 3.2 px off
// on the 41 px ring, seed-centre radii span 1.18 — past the 1.10 bound — so
// that mutation refuses this legitimate ring, while the real code re-centres
// and fits it. (The occupancy count is about the seed too, which is why this
// is one targeted check and not an offset on the whole loop: 3 px moves a
// spot across a sector boundary on grains_3_one_annulus and changes WHICH
// refusal it gets.)
do {
    guard let test = fixture.spotCases.first(where: { $0.name == "spotty_ring_6_azimuths" })
    else { fail("spotty_ring_6_azimuths fixture missing") }
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    let fit = try EllipseCalibration.fitBestAvailable(
        pattern: pattern, centerQX: test.centerQX + 2.5, centerQY: test.centerQY - 2.0,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius,
        acceptSparseCoverage: true)
    guard fit.sparseCoverage, abs(fit.a / fit.b - 1) < 0.02,
          abs(fit.centerQX - test.centerQX) < 0.1, abs(fit.centerQY - test.centerQY) < 0.1 else {
        fail("spotty_ring_6_azimuths seeded 3.2 px off: a/b \(fit.a / fit.b), centre "
             + "(\(fit.centerQX), \(fit.centerQY)) against (\(test.centerQX), \(test.centerQY))")
    }
    print(String(format: "PASS: spotty_ring_6_azimuths fitted anyway from a seed 3.2 px off "
                 + "(a/b %.4f, centre recovered to %.3f px)", fit.a / fit.b,
                 hypot(fit.centerQX - test.centerQX, fit.centerQY - test.centerQY)))
} catch {
    // The seed-centre mutation lands here: moreThanOneRing(38.2, 44.5).
    fail("spotty_ring_6_azimuths seeded 3.2 px off was refused: \(error)")
}

print("ellipse-calibration-test: all passed")
