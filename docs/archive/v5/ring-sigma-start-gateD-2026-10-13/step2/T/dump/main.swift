import Foundation

struct Fixture: Decodable {
    let cases: [RingCase]
    let profileCases: [ProfileCase]
    let overlapCase: ProfileCase
    let spotCases: [SpotCase]
    let sweepCases: [SweepCase]
}
/// One ring of the clean sweep (2026-10-12): the pixels sit in a raw float32
/// file written by reference.py, `optimum*` is scipy's minimum of fit1D's own
/// objective from fit1D's own start.
struct SweepCase: Decodable {
    let name: String
    let file: String
    let height: Int
    let width: Int
    let radius: Double
    let eps: Double
    let gapDegrees: Double
    let centerQX: Double
    let centerQY: Double
    let startQX: Double
    let startQY: Double
    let a: Double
    let b: Double
    /// nil on a circle, where the angle is undefined.
    let theta: Double?
    let innerRadius: Double
    let outerRadius: Double
    let sampleCount: Int
    let occupiedBins: Int
    let optimumCenterQX: Double
    let optimumCenterQY: Double
    let optimumA: Double
    let optimumB: Double
    let optimumTheta: Double
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


// ---- lane T DUMP instrumentation (added; no pass/fail logic changed) ----
// DUMP_SKIP (env, comma list, default empty = the tool's own logic exactly) skips only the pass/fail CHECKS of the
// named sections after their fit calls have run and been dumped, so a variant that FAILs early can still be dumped
// to the end. Keys: profile:<name>, spot:<name>, anyway:<name>, seeded, sweep.
let dumpSkip = Set((ProcessInfo.processInfo.environment["DUMP_SKIP"] ?? "").split(separator: ",").map(String.init))
struct SkippedChecks: Error {}
func skipChecks(_ key: String) -> Bool { dumpSkip.contains(key) }
func dumpNum(_ x: Double) -> String { String(format: "%.9g", x) }
func dumpClean(_ s: String) -> String {
    s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
}
func dumpFit(_ caseName: String, _ fn: String, _ f: EllipseCalibrationFit) {
    let p = f.profile
    let model = f.model == .conic ? "conic" : "asymmetricGaussian"
    var line = "DUMP|case=\(caseName)|fn=\(fn)|model=\(model)|a=\(dumpNum(f.a))|b=\(dumpNum(f.b))"
    line += "|theta=\(dumpNum(f.theta))|cx=\(dumpNum(f.centerQX))|cy=\(dumpNum(f.centerQY))"
    line += "|resid=\(dumpNum(f.normalizedResidual))"
    line += "|sin=\(p.map { dumpNum($0.innerSigma) } ?? "nil")|sout=\(p.map { dumpNum($0.outerSigma) } ?? "nil")"
    line += "|fallback=\(dumpClean(f.profileFallbackReason ?? "nil"))"
    line += "|cres=\(dumpNum(f.conicResidual))|n=\(f.sampleCount)|bins=\(f.occupiedAngularBins)"
    line += "|i1=\(p.map { dumpNum($0.ringIntensity) } ?? "nil")|bg=\(p.map { dumpNum($0.background) } ?? "nil")"
    print(line)
}
func dumpThrew(_ caseName: String, _ fn: String, _ error: Error) {
    print("DUMP|case=\(caseName)|fn=\(fn)|threw=\(dumpClean("\(error)"))")
}
func traced(_ caseName: String, _ fn: String, _ body: () throws -> EllipseCalibrationFit) throws -> EllipseCalibrationFit {
    do {
        let fit = try body()
        dumpFit(caseName, fn, fit)
        return fit
    } catch {
        dumpThrew(caseName, fn, error)
        throw error
    }
}
// ---- end lane T instrumentation ----

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
for test in fixture.cases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    let fit = try traced(test.name, "fit1D") { try EllipseCalibration.fit1D(
        pattern: pattern, centerQX: test.centerQX + 0.8, centerQY: test.centerQY - 0.6,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    ) }
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
    let fit = try traced(test.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
        pattern: pattern,
        centerQX: test.centerQX + 0.7, centerQY: test.centerQY - 0.5,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    ) }
    if skipChecks("profile:" + test.name) { continue }
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
let fallback = try traced(overlap.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
    pattern: overlapPattern,
    centerQX: overlap.centerQX, centerQY: overlap.centerQY,
    innerRadius: overlap.innerRadius, outerRadius: overlap.outerRadius,
    maximumConicResidual: 0.4, maximumProfileResidual: 0.001
) }
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
    _ = try traced("blank_annulus", "fit1D") { try EllipseCalibration.fit1D(
        pattern: blank, centerQX: 20, centerQY: 30, innerRadius: 8, outerRadius: 18
    ) }
    fail("constant input unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientSignal {}
print("PASS: blank annulus rejected")

var spots = [Float](repeating: 0, count: 60 * 80)
for (qx, qy) in [(15, 40), (45, 40), (30, 25), (30, 55)] {
    spots[qx * 80 + qy] = 10
}
do {
    _ = try traced("four_spot", "fit1D") { try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20
    ) }
    fail("four-spot degeneracy unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientAngularCoverage {}
print("PASS: angularly degenerate input rejected")
do {
    _ = try traced("four_spot_anyway", "fit1D") { try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20,
        acceptSparseCoverage: true
    ) }
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
        let fit = try traced(test.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
        if skipChecks("spot:" + test.name) { continue }
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
        if skipChecks("spot:" + test.name) { continue }
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
        let fit = try traced(test.name, "fitBestAvailable-anyway") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius,
            acceptSparseCoverage: true) }
        if skipChecks("anyway:" + test.name) { continue }
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
        if skipChecks("anyway:" + test.name) { continue }
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
    let fit = try traced("spotty_ring_6_azimuths_seed3.2", "fitBestAvailable-anyway") { try EllipseCalibration.fitBestAvailable(
        pattern: pattern, centerQX: test.centerQX + 2.5, centerQY: test.centerQY - 2.0,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius,
        acceptSparseCoverage: true) }
    if skipChecks("seeded") { throw SkippedChecks() }
    guard fit.sparseCoverage, abs(fit.a / fit.b - 1) < 0.02,
          abs(fit.centerQX - test.centerQX) < 0.1, abs(fit.centerQY - test.centerQY) < 0.1 else {
        fail("spotty_ring_6_azimuths seeded 3.2 px off: a/b \(fit.a / fit.b), centre "
             + "(\(fit.centerQX), \(fit.centerQY)) against (\(test.centerQX), \(test.centerQY))")
    }
    print(String(format: "PASS: spotty_ring_6_azimuths fitted anyway from a seed 3.2 px off "
                 + "(a/b %.4f, centre recovered to %.3f px)", fit.a / fit.b,
                 hypot(fit.centerQX - test.centerQX, fit.centerQY - test.centerQY)))
} catch is SkippedChecks {
} catch {
    // The seed-centre mutation lands here: moreThanOneRing(38.2, 44.5).
    fail("spotty_ring_6_azimuths seeded 3.2 px off was refused: \(error)")
}

// THE CLEAN SWEEP (2026-10-12). Every ring below is a clean plant that has an
// optimum, and fit1D must find it. Its LM stop rule once tested convergence only
// after an ACCEPTED step; at the optimum the cost change of a step is roundoff,
// every step was refused, damping grew until the candidate equalled the point,
// and the 100-pass cap threw didNotConverge on about one clean ring in seven
// (docs/archive/v5/ellipse-stop-rule-gateD-2026-10-12.md). None of the cases
// above is big enough to hit it. Four checks per ring, in the order tried:
//   - it FITS (a throw is a FAIL naming the ring and the error; every ring is
//     tried before the run stops, so the count is in the log),
//   - fit1D reads the pixels scipy was given (annulus pixel count and occupied
//     angular bins equal reference.py's),
//   - the centre is within 0.05 px of the plant's,
//   - fit1D equals scipy's optimum of the same objective (the weighted conic
//     (A dx^2 + B dx dy + C dy^2 - 1) * I, same samples, same start): centre
//     1e-5 px, a and b 1e-7 relative, theta 1e-6 rad (not on a circle, where
//     it is undefined). Measured 2026-10-12 on these 48 rings: at most 1.1e-7
//     px, 6.4e-10 and 1.7e-8 rad, against 7e-8 px and 2.6e-10 between scipy's
//     own two parameter scalings, so each tolerance sits 60x or more above the
//     agreement. This is also what pins the OBJECTIVE: an unweighted or
//     sqrt-weighted variant lands on a different minimum and fails here, not
//     at the plant.
// The radius bias is printed, never gated: the objective's minimum sits at
// R (1 + 1.75 (s/R)^2) on a ring of width s (an r dr measure, the conic's r^2,
// the squared intensity), and py4DSTEM's fit_ellipse_1D has the same objective.
let sweepCentreTolerance = 1e-5
let sweepAxesTolerance = 1e-7
let sweepThetaTolerance = 1e-6
var sweepFailures = [String]()
var sweepFailedRings = Set<String>()
var worstPlant = 0.0, worstCentre = 0.0, worstAxes = 0.0, worstTheta = 0.0
var biasByRadius = [Double: (clean: [Double], gapped: [Double])]()
guard !fixture.sweepCases.isEmpty else { fail("the clean sweep is empty") }
for test in fixture.sweepCases {
    let pixels = try Data(contentsOf: URL(fileURLWithPath: test.file)).withUnsafeBytes {
        Array($0.bindMemory(to: Float.self))
    }
    guard pixels.count == test.height * test.width else {
        fail("\(test.name) fixture file holds \(pixels.count) pixels, expected \(test.height * test.width)")
    }
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: pixels)
    // lane T: fitBestAvailable on the same pattern, centre guess and annulus as the sweep's fit1D; outside the checks.
    do {
        _ = try traced(test.name, "fitBestAvailable-sweep") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.startQX, centerQY: test.startQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
    } catch {}
    let fit: EllipseCalibrationFit
    do {
        fit = try traced(test.name, "fit1D") { try EllipseCalibration.fit1D(
            pattern: pattern, centerQX: test.startQX, centerQY: test.startQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
    } catch {
        sweepFailures.append("\(test.name) was refused: \(error)")
        sweepFailedRings.insert(test.name)
        continue
    }
    if fit.sampleCount != test.sampleCount || fit.occupiedAngularBins != test.occupiedBins {
        sweepFailures.append("\(test.name) reads \(fit.sampleCount) pixels in \(fit.occupiedAngularBins) bins, "
                             + "reference.py \(test.sampleCount) in \(test.occupiedBins)")
        sweepFailedRings.insert(test.name)
    }
    let plant = max(abs(fit.centerQX - test.centerQX), abs(fit.centerQY - test.centerQY))
    let centre = max(abs(fit.centerQX - test.optimumCenterQX), abs(fit.centerQY - test.optimumCenterQY))
    let axes = max(abs(fit.a - test.optimumA) / test.optimumA, abs(fit.b - test.optimumB) / test.optimumB)
    let theta = test.theta == nil ? 0 : angleError(fit.theta, test.optimumTheta)
    worstPlant = max(worstPlant, plant); worstCentre = max(worstCentre, centre)
    worstAxes = max(worstAxes, axes); worstTheta = max(worstTheta, theta)
    if plant >= 0.05 {
        sweepFailures.append("\(test.name) centre is \(plant) px from the plant (limit 0.05)")
        sweepFailedRings.insert(test.name)
    }
    if centre >= sweepCentreTolerance || axes >= sweepAxesTolerance || theta >= sweepThetaTolerance {
        sweepFailures.append("\(test.name) differs from scipy's optimum: centre \(centre) px, "
                             + "axes \(axes) relative, theta \(theta) rad; fit1D \(fit)")
        sweepFailedRings.insert(test.name)
    }
    let bias = (fit.a + fit.b) / 2 / test.radius - 1
    if test.gapDegrees == 0 {
        biasByRadius[test.radius, default: ([], [])].clean.append(bias)
    } else {
        biasByRadius[test.radius, default: ([], [])].gapped.append(bias)
    }
}
guard sweepFailures.isEmpty else {
    fail("clean sweep: \(sweepFailedRings.count) of \(fixture.sweepCases.count) rings failed\n  "
         + sweepFailures.joined(separator: "\n  "))
}
print(String(format: "PASS: clean sweep, %d rings fitted: centre within %.3f px of the plant; against "
             + "scipy's optimum at most %.2e px, %.2e relative in a and b, %.2e rad in theta",
             fixture.sweepCases.count, worstPlant, worstCentre, worstAxes, worstTheta))
func percent(_ values: [Double]) -> String {
    values.isEmpty ? "     -" : String(format: "%+.4f", 100 * values.reduce(0, +) / Double(values.count))
}
for radius in biasByRadius.keys.sorted() {
    let bias = biasByRadius[radius]!
    print(String(format: "INFO: radius bias (a+b)/2 over R at R %3.0f px, s 3 px: unbroken ring %@ %%, "
                 + "60 degree arc missing %@ %%; 1.75 (s/R)^2 = %.4f %%",
                 radius, percent(bias.clean), percent(bias.gapped), 100 * 1.75 * pow(3 / radius, 2)))
}

print("ellipse-calibration-test: all passed")
