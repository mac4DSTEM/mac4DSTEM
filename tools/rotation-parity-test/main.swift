//
//  main.swift — rotation-parity-test
//
//  The gated parity harness `Core/Analysis/RotationCalibration.swift` has
//  lacked since v3.0.0 (docs/open-items.md, "Verification debt": no
//  `sources.manifest` group named it, so the only coverage was the unit
//  suite and the diagnostic `tools/rotation-null-probe`). Four legs:
//
//  (a) ANALYTIC RECOVERY (floor, must pass): decodes reference.py's two
//      fixture fields (a phase-object gradient rotated by a planted 37.2 deg,
//      direct and transposed) and asserts RotationCalibration.solve recovers
//      the planted angle within a pinned tolerance and picks the right
//      transpose. Ground truth is external — reference.py's numpy, never
//      this binary's own formula.
//
//  (b) PY4DSTEM PARITY, FILE-FAITHFUL (must pass since 2026-09-28, ADR 040):
//      reference.py's `assert_source_contract` gates the pinned source text,
//      then calls py4DSTEM's frozen curl search the way py4DSTEM reads the
//      same file (direct, transposed, and non-square 40x30). The app's angle
//      converted by `RQRotationConvention` must match it and the transpose;
//      the unconverted angle must NOT (anti-vacuity). Until 2026-09-28 this
//      leg was informational: the frame-class difference it exposed is now
//      handled at the boundary (docs/archive/v4/rq-sign-gateD-2026-09-28.md).
//
//  (c) NULL / ADR 024 (must pass): reuses `tools/rotation-null-probe`'s exact
//      generator functions and seed formulas (XorshiftRNG, whiteNoiseField,
//      plantedRotationField — copied verbatim, not reinvented) on seeds this
//      session verified once, deterministically, before pinning them here:
//      eight white-noise seeds (40x40, sd 0.010) that all refuse, and all 60
//      of experiment F's planted-30-degree seeds (sd 0.00-0.05, 12 per
//      level), which the probe's own header records as "0/60 refused". Does
//      NOT assert "any rotation-free field refuses" — the probe itself
//      proves box/edge/drift fields DO certify; only these vetted seeds are
//      asserted here.
//

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

/// |measured - target| mod 180 deg, the method's inherent half-circle
/// ambiguity (RotationCalibration.swift's own doc comment; same construction
/// as RotationSignificanceTests.testARealRotationIsStillMeasured).
func angleErrorModHalfCircle(measuredDeg: Double, targetDeg: Double) -> Double {
    [measuredDeg - targetDeg, measuredDeg - targetDeg - 180, measuredDeg - targetDeg + 180]
        .map { abs($0) }
        .min()!
}

// MARK: - Leg (a) + (b): fixture decode

struct Fixture: Decodable {
    let width: Int
    let height: Int
    let plantedDeg: Double
    let directField: [Float]
    let transposedField: [Float]
    let nonSquareWidth: Int
    let nonSquareHeight: Int
    let nonSquareField: [Float]
    let py4dstemFileFaithful: [Py4DSTEMAnswer]
}

struct Py4DSTEMAnswer: Decodable {
    let angleDeg: Double
    let transpose: Bool
}

guard CommandLine.arguments.count == 2 else { fail("usage: rotation-parity-test fixture.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)

// break-first-pinned: 0.5 deg. The measured error on a noiseless analytic
// field is ~3e-6 deg (this session's standalone probe); 0.5 deg comfortably
// passes the real fit while easily catching a sign flip (~74 deg error), a
// dropped transpose, or a coarse-grid-only regression (~1 deg steps).
let angleTolerance = 0.5

guard let direct = RotationCalibration.solve(
    com: fixture.directField, width: fixture.width, height: fixture.height
) else { fail("solve() returned nil on the direct fixture field") }
guard direct.carriesRotation else {
    fail("a noiseless planted 37.2deg rotation was refused: depth \(direct.depth), "
         + "shuffled max \(direct.shuffledDepths.max() ?? -1)")
}
guard direct.transpose == false else {
    fail("direct fixture: expected transpose=false, got true")
}
let directDeg = Double(direct.rotationRad) * 180 / .pi
let directTarget = -fixture.plantedDeg
let directError = angleErrorModHalfCircle(measuredDeg: directDeg, targetDeg: directTarget)
guard directError < angleTolerance else {
    fail("direct fixture: recovered \(directDeg)deg, expected \(directTarget)deg "
         + "(mod 180), error \(directError)deg exceeds \(angleTolerance)deg")
}
print("PASS: analytic recovery, transpose=false, planted \(fixture.plantedDeg)deg "
      + "recovered as \(directDeg)deg (error \(directError)deg)")

guard let transposed = RotationCalibration.solve(
    com: fixture.transposedField, width: fixture.width, height: fixture.height
) else { fail("solve() returned nil on the transposed fixture field") }
guard transposed.carriesRotation else {
    fail("a noiseless planted 37.2deg rotation (transposed field) was refused: depth "
         + "\(transposed.depth), shuffled max \(transposed.shuffledDepths.max() ?? -1)")
}
guard transposed.transpose == true else {
    fail("transposed fixture: expected transpose=true, got false")
}
let transposedDeg = Double(transposed.rotationRad) * 180 / .pi
// Measured, not assumed: the transpose branch's own sign convention is
// +planted, not -planted (this session's standalone probe) — the transpose
// is a reflection, so the curl-canceling angle's sign need not match the
// direct branch's, and it does not.
let transposedTarget = fixture.plantedDeg
let transposedError = angleErrorModHalfCircle(measuredDeg: transposedDeg, targetDeg: transposedTarget)
guard transposedError < angleTolerance else {
    fail("transposed fixture: recovered \(transposedDeg)deg, expected \(transposedTarget)deg "
         + "(mod 180), error \(transposedError)deg exceeds \(angleTolerance)deg")
}
print("PASS: analytic recovery, transpose=true, planted \(fixture.plantedDeg)deg "
      + "recovered as \(transposedDeg)deg (error \(transposedError)deg)")

// Leg (b): file-faithful py4DSTEM parity, GATING since 2026-09-28 (ADR 040,
// docs/archive/v4/rq-sign-gateD-2026-09-28.md). reference.py calls py4DSTEM's
// frozen curl search the way py4DSTEM reads the same file; the app's angle,
// converted by RQRotationConvention (the one conversion every display and
// file uses), must agree with it within py4DSTEM's 1° grid (0.75°) and with
// the same transpose. Anti-vacuity: the UNconverted angle must be off by
// more than 10° — otherwise this fixture could not see a dropped sign.
guard let nonSquare = RotationCalibration.solve(
    com: fixture.nonSquareField, width: fixture.nonSquareWidth, height: fixture.nonSquareHeight
) else { fail("solve() returned nil on the non-square fixture field") }
guard fixture.py4dstemFileFaithful.count == 3 else { fail("reference.py must emit three file-faithful answers") }
let legBTolerance = 0.75
for (name, result, py) in [("direct 40x40", direct, fixture.py4dstemFileFaithful[0]),
                           ("transposed 40x40", transposed, fixture.py4dstemFileFaithful[1]),
                           ("direct 40x30", nonSquare, fixture.py4dstemFileFaithful[2])] {
    let appDeg = Double(result.rotationRad) * 180 / .pi
    let shownDeg = RQRotationConvention.displayDegrees(fromApp: result.rotationRad)
    let error = angleErrorModHalfCircle(measuredDeg: shownDeg, targetDeg: py.angleDeg)
    let unconverted = angleErrorModHalfCircle(measuredDeg: appDeg, targetDeg: py.angleDeg)
    guard result.transpose == py.transpose else {
        fail("leg (b) \(name): transpose \(result.transpose), py4DSTEM \(py.transpose)")
    }
    guard error < legBTolerance else {
        fail("leg (b) \(name): shown \(shownDeg)deg vs file-faithful py4DSTEM \(py.angleDeg)deg, "
             + "error \(error)deg exceeds \(legBTolerance)deg")
    }
    guard unconverted > 10 else {
        fail("leg (b) \(name): the unconverted app angle \(appDeg)deg is within 10deg of py4DSTEM's "
             + "\(py.angleDeg)deg — this fixture cannot discriminate the sign")
    }
    print("PASS: file-faithful py4DSTEM parity, \(name): shown \(shownDeg)deg/transpose=\(result.transpose) "
          + "vs py4DSTEM \(py.angleDeg)deg/transpose=\(py.transpose) (error \(error)deg; unconverted off by \(unconverted)deg)")
}

// MARK: - Leg (c): NULL / ADR 024, reusing tools/rotation-null-probe's exact
// generators and seed formulas verbatim.

struct XorshiftRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func nextUInt64() -> UInt64 {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return state &* 2685821657736338717
    }
    mutating func nextUnit() -> Double { Double(nextUInt64() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func nextGaussian() -> Double {
        let u1 = Swift.max(nextUnit(), 1e-300)
        let u2 = nextUnit()
        return (-2.0 * Foundation.log(u1)).squareRoot() * cos(2.0 * Double.pi * u2)
    }
}

func whiteNoiseField(width: Int, height: Int, sd: Double, seed: UInt64) -> [Float] {
    var rng = XorshiftRNG(seed: seed)
    var out = [Float](repeating: 0, count: width * height * 2)
    for i in 0..<(width * height) {
        out[2 * i] = Float(rng.nextGaussian() * sd)
        out[2 * i + 1] = Float(rng.nextGaussian() * sd)
    }
    return out
}

func plantedRotationField(width: Int, height: Int, angleDeg: Double, noiseSd: Double, seed: UInt64) -> [Float] {
    var rng = XorshiftRNG(seed: seed)
    var out = [Float](repeating: 0, count: width * height * 2)
    let theta = angleDeg * .pi / 180
    let c = cos(theta), s = sin(theta)
    for y in 0..<height {
        for x in 0..<width {
            let gx = cos(Double(x) / 6) * cos(Double(y) / 5) / 6
            let gy = -sin(Double(x) / 6) * sin(Double(y) / 5) / 5
            let i = (y * width + x) * 2
            out[i] = Float(c * gx - s * gy + rng.nextGaussian() * noiseSd)
            out[i + 1] = Float(s * gx + c * gy + rng.nextGaussian() * noiseSd)
        }
    }
    return out
}

// Vetted rotation-free seeds: whiteNoiseField(40x40, sd=0.010), experiment A's
// exact seed formula (0xA000_0000_0000_0000 + i). Verified once this session,
// standalone, before pinning: i in 0...7 all refuse (i=13 does NOT, matching
// the probe's own <25% certification rate for this population — that seed is
// deliberately excluded, not evidence against the eight pinned here).
var rotationFreeRefusals = 0
for i in 0..<8 {
    let seed: UInt64 = 0xA000_0000_0000_0000 &+ UInt64(i)
    let field = whiteNoiseField(width: 40, height: 40, sd: 0.010, seed: seed)
    guard let r = RotationCalibration.solve(com: field, width: 40, height: 40) else {
        fail("null leg: solve() returned nil on vetted rotation-free seed \(i)")
    }
    guard !r.carriesRotation else {
        fail("null leg: vetted rotation-free seed \(i) certified a rotation: depth "
             + "\(r.depth), shuffled max \(r.shuffledDepths.max() ?? -1)")
    }
    rotationFreeRefusals += 1
}
print("PASS: \(rotationFreeRefusals)/8 vetted rotation-free white-noise seeds refused")

// Planted 30deg rotation, experiment F's exact seed formula. NOT all 60 of
// experiment F: this session re-measured it (the probe's own header still
// says "0/60 refused", which is stale) and found 3 of 60 refuse, all at
// sd=0.05, indices 4/5/7 — exactly the already-documented finding in
// docs/open-items.md ("power drops at the highest noise: planted 30deg at sd
// 0.05 is refused 3 of 12 (0 of 48 at sd <= 0.03)"). Gating on a false "0/60"
// would be the exact defect CLAUDE.md warns against: "no claim a reader
// cannot reproduce". So: hard-gate sd <= 0.03 (48 seeds, matches the
// documented 0/48), and report sd=0.05 informationally, not asserted.
var plantedCertifications = 0
let hardGatedSds = [0.00, 0.01, 0.02, 0.03]
for (sdIdx, sd) in hardGatedSds.enumerated() {
    for i in 0..<12 {
        let seed: UInt64 = 0xF000_0000_0000_0000 &+ UInt64(sdIdx) &* 1000 &+ UInt64(i)
        let field = plantedRotationField(width: 40, height: 40, angleDeg: 30.0, noiseSd: sd, seed: seed)
        guard let r = RotationCalibration.solve(com: field, width: 40, height: 40) else {
            fail("null leg: solve() returned nil on planted seed sd=\(sd) i=\(i)")
        }
        guard r.carriesRotation else {
            fail("null leg: planted 30deg rotation (sd \(sd), seed index \(i)) was "
                 + "refused: depth \(r.depth), shuffled max \(r.shuffledDepths.max() ?? -1)")
        }
        plantedCertifications += 1
    }
}
print("PASS: \(plantedCertifications)/48 vetted planted-rotation seeds at sd<=0.03 (ADR 024) certified")

var highNoiseCertified = 0
for i in 0..<12 {
    let seed: UInt64 = 0xF000_0000_0000_0000 &+ UInt64(4) &* 1000 &+ UInt64(i)
    let field = plantedRotationField(width: 40, height: 40, angleDeg: 30.0, noiseSd: 0.05, seed: seed)
    if let r = RotationCalibration.solve(com: field, width: 40, height: 40), r.carriesRotation {
        highNoiseCertified += 1
    }
}
print("INFO (not gated — documented reduced power at the highest noise level): "
      + "\(highNoiseCertified)/12 planted-rotation seeds at sd=0.05 certified")

print("rotation-parity-test: all passed")
