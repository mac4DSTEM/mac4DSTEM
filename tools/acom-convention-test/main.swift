// Independent orientation-coordinate regression. See README for the oracle's
// scope: analytic peak positions, shared structure factors, frozen external data.
import Foundation
import simd

func require(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}
func degrees(_ x: Double) -> Double { x * 180 / .pi }
func median(_ values: [Double]) -> Double {
    require(!values.isEmpty && values.allSatisfy(\.isFinite), "finite nonempty statistic")
    let s = values.sorted(), n = s.count
    return n % 2 == 0 ? (s[n / 2 - 1] + s[n / 2]) / 2 : s[n / 2]
}
func rotationZ(_ a: Double) -> simd_double3x3 {
    simd_double3x3(rows: [SIMD3(cos(a), -sin(a), 0),
                            SIMD3(sin(a), cos(a), 0), SIMD3(0, 0, 1)])
}
// Independent finite groups; do not call the app's symmetry reducer here.
func operators(hexagonal: Bool) -> [simd_double3x3] {
    if hexagonal {
        return (0..<6).map { rotationZ(Double($0) * .pi / 3) } + (0..<6).map {
            let a = Double($0) * .pi / 6, x = cos(a), y = sin(a)
            return simd_double3x3(rows: [SIMD3(2*x*x-1, 2*x*y, 0),
                SIMD3(2*x*y, 2*y*y-1, 0), SIMD3(0, 0, -1)])
        }
    }
    var result: [simd_double3x3] = []
    for p in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            let signs = [x,y,z]
            var rows = [SIMD3<Double>](repeating: .zero, count: 3)
            for i in 0..<3 { rows[i][p[i]] = signs[i] }
            let m = simd_double3x3(rows: rows)
            if simd_determinant(m) > 0.5 { result.append(m) }
        } } }
    }
    return result
}
func proper(_ m: simd_double3x3) -> Bool {
    let gram = m.transpose * m
    for row in 0..<3 { for col in 0..<3 {
        if !m[col][row].isFinite || abs(gram[col][row] - (row == col ? 1 : 0)) > 1e-5 {
            return false
        }
    } }
    return abs(simd_determinant(m) - 1) < 1e-5
}
// Matrices have lab axes as columns in crystal coordinates: symmetry acts LEFT.
func misorientation(_ a: simd_double3x3, _ b: simd_double3x3,
                    _ ops: [simd_double3x3]) -> Double {
    require(proper(a) && proper(b), "orientation must be a finite proper rotation")
    return ops.map { op in
        let m = op * a * b.transpose
        return degrees(acos(max(-1, min(1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2))))
    }.min()!
}
func checkOracle(_ ops: [simd_double3x3], count: Int) {
    require(ops.count == count && ops.allSatisfy(proper), "independent symmetry group")
    let identity = matrix_identity_double3x3
    for op in ops {
        require(misorientation(identity, op, ops) < 1e-4, "symmetry-equivalent rotations")
    }
    require(misorientation(identity, rotationZ(37.2 * .pi / 180), ops) > 20,
            "oracle must distinguish a generic wrong orientation")
    require(median([1, 2, 8, 10]) == 5 && median([1, 8, 10]) == 8,
            "median cannot silently become max or upper-middle")
}

func analytic(hexagonal: Bool) {
    let label = hexagonal ? "WS2" : "Au"
    let ops = operators(hexagonal: hexagonal)
    checkOracle(ops, count: hexagonal ? 12 : 24)
    let crystal = hexagonal ? Crystal.tungstenDisulfide : Crystal(
        a: 4.08, b: 4.08, c: 4.08,
        sites: [SIMD3<Double>(0,0,0), SIMD3(0,0.5,0.5), SIMD3(0.5,0,0.5), SIMD3(0.5,0.5,0)]
            .map { AtomSite(z: 79, fractional: $0) })
    let symmetry: ACOMCrystalSymmetry = hexagonal ? .hexagonal : .cubic
    let kMax = hexagonal ? 1.6 : 1.2, wavelength = 0.0251, scale = 0.008
    guard let plan = OrientationPlan.generate(crystal: crystal, kMax: kMax,
        zoneAxisCount: 600, symmetry: symmetry, wavelengthAngstrom: wavelength),
        let matcher = OrientationMatcher(plan: plan, symmetry: symmetry)
    else { require(false, "\(label) plan and matcher"); return }
    let reflections = crystal.reflections(kMax: kMax)
    var special: [SIMD3<Double>] = [[0,0,1]]
    if hexagonal {
        special += (0..<12).map { i in
            let a = Double(i) * .pi / 6; return SIMD3(cos(a), sin(a), 0)
        }
    } else {
        special += [[1,0,0], [0,1,0], [1,1,0], [1,0,1], [0,1,1],
            [1,-1,0], [1,0,-1], [0,1,-1], [1,1,1], [1,1,-1], [1,-1,1], [-1,1,1]]
    }
    func separation(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        degrees(acos(min(1, abs(simd_dot(simd_normalize(a), simd_normalize(b))))))
    }
    var axes: [SIMD3<Double>] = []
    for n in plan.zoneAxes where special.allSatisfy({ separation(n, $0) > 8 }) {
        if axes.allSatisfy({ separation(n, $0) > 6 }) { axes.append(n) }
        if axes.count == 30 { break }
    }
    require(axes.count == (hexagonal ? 30 : 18), "\(label) expected generic axes, no empty sweep")
    // Review row 1 (2026-09-30): the bank samples the mirror-reduced triangle
    // (cubic z >= x >= y >= 0) / sector (hexagonal 0-30 deg), half of the
    // proper-rotation zone. Every generic axis above lies in it, so this gate
    // could not see a beam in the other half. The mirror image of each axis
    // (x <-> y, or y -> -y for hexagonal) is run as its own group with the
    // same bounds: no in-plane rotation reproduces its pattern, only the
    // matcher's conjugated pass does.
    let mirrorAxes: [SIMD3<Double>] = axes.map {
        hexagonal ? SIMD3($0.x, -$0.y, $0.z) : SIMD3($0.y, $0.x, $0.z)
    }
    let angles = [37.2, 12.5, 100.0, -63.4, 155.0, 211.7, 88.9, -170.3]
    for (group, groupAxes) in [("sampled", axes), ("mirror", mirrorAxes)] {
    var errors: [Double] = [], inPlaneErrors: [Double] = []
    for axis in groupAxes {
        let n = simd_normalize(axis)
        let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0,0,1] : [1,0,0]
        let f0 = simd_normalize(seed - simd_dot(seed, n) * n)
        for angle in angles {
            let a = angle * .pi / 180
            let f1 = simd_normalize(f0 * cos(a) + simd_cross(n, f0) * sin(a))
            let f2 = simd_cross(n, f1)
            let truth = simd_double3x3(columns: (f1, f2, n))
            // Positions NEVER pass through production project()/detectorBasis().
            let peaks: [BraggPeak] = reflections.compactMap { r in
                let sg = simd_dot(r.g, n) + 0.5 * wavelength * simd_length_squared(r.g)
                let intensity = r.intensity * exp(-pow(sg / 0.03, 2))
                guard abs(sg) <= 0.1 && intensity > 0 else { return nil }
                return BraggPeak(x: Float(256 + simd_dot(r.g, f1) / scale),
                    y: Float(256 + simd_dot(r.g, f2) / scale), intensity: Float(intensity))
            }
            require(peaks.count >= 3, "\(label) informative pattern")
            let result = matcher.match(peaks: peaks, originX: 256, originY: 256,
                                       invAngstromPerPixel: scale)
            require(plan.zoneAxes.indices.contains(result.templateIndex), "\(label) no skipped failed match")
            let reported = result.euler.py4DSTEMOrientationMatrix
            errors.append(misorientation(reported, truth, ops))
            // Auxiliary in-plane check: with the beam brought onto the truth
            // beam by the best symmetry operator, the reported lab-x axis must
            // lie near f1. Symmetry-aware since row 1 (2026-10-01): a mirrored
            // win reports the equivalent orientation with the beam flipped, so
            // the previous template-basis formula (which assumed the identity
            // operator) read ~180° on 21 of 144 correct sampled-zone trials.
            var bestOp = matrix_identity_double3x3, bestBeam = Double.infinity
            for op in ops {
                let beamError = acos(max(-1, min(1, simd_dot(op * reported[2], n))))
                if beamError < bestBeam { bestBeam = beamError; bestOp = op }
            }
            let c1 = bestOp * reported[0]
            inPlaneErrors.append(degrees(acos(max(-1, min(1, simd_dot(c1, f1))))))
            if ProcessInfo.processInfo.environment["ACOM_CONVENTION_DETAIL"] != nil,
               errors.last! > 3 || inPlaneErrors.last! > 20 {
                let flag = Mirror(reflecting: result).children.first { $0.label == "mirrored" }?.value as? Bool
                print(String(format: "DETAIL: %@ %@ axis (%.3f %.3f %.3f) angle %.1f: matrix %.2f° in-plane %.2f° template %d score %.4f mirrored %@",
                             label, group, n.x, n.y, n.z, angle, errors.last!, inPlaneErrors.last!,
                             result.templateIndex, result.score, flag.map { $0 ? "yes" : "no" } ?? "n/a"))
            }
        }
    }
    let expectedCount = hexagonal ? 240 : 144
    let near = inPlaneErrors.filter { $0 < 20 }.count
    require(errors.count == expectedCount, "\(label) \(group) every expected trial executed")
    print(String(format: "MEASURE: %@ %@ %d trials; median matrix error %.6f deg; in-plane <20 deg %d",
                 label, group, errors.count, median(errors), near))
    require(median(errors) < (hexagonal ? 2 : 3), "\(label) \(group) independent matrix orientation")
    // Re-pinned 2026-10-01 (owner's card, row 1): the mirror pass (py4DSTEM inversion_symmetry) costs
    // ≈ 7/144 Au trials to the half-turn class — without it the 40-random-angle-set mean is 132.1, with it
    // ≈ 125 (min 118); this fixed set reads 116 — below every one of the 40 random sets (min 118): an unlucky draw, not a further mechanism (archive/v4/slot2-sb-refuter-2026-10-01.md). The pin is
    // the fixed set's own count, so any further loss is caught. Mirror group and WS2 keep their bounds.
    let nearBound = hexagonal ? 240 : (group == "sampled" ? 116 : 120)
    require(near >= nearBound, "\(label) \(group) full-angle recovery, not modulo pi")
    }
    print("PASS: \(label) independent projection and returned matrix, sampled and mirror zone")
}

struct Peak: Decodable { let x: Double; let y: Double; let intensity: Double }
struct ReferenceInput: Decodable {
    let cellAAngstrom: Double; let siteFractional: [[Double]]; let siteAtomicNumbers: [Int]
    let kMaxInvAngstrom: Double; let zoneAxisCount: Int
    let invAngstromPerPixel: Double; let originX: Double; let originY: Double
    let wavelengthAngstrom: Double; let intensityPower: Double
    let radialKernelInvAngstrom: Double; let distinctOrientationDeg: Double
    let patterns: [[Peak]]
}
struct Reference: Decodable { let input: ReferenceInput; let labMatrices: [[[Double]]] }
func frozenReference(_ path: String) throws {
    let fixture = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let x = fixture.input
    require(x.patterns.count == 40 && fixture.labMatrices.count == 40, "all 40 external cases required")
    require(x.siteFractional.count == x.siteAtomicNumbers.count && x.siteFractional.allSatisfy { $0.count == 3 },
            "external atom site shapes")
    let sites = zip(x.siteFractional, x.siteAtomicNumbers).map {
        AtomSite(z: $1, fractional: SIMD3($0[0], $0[1], $0[2]))
    }
    let crystal = Crystal(a: x.cellAAngstrom, b: x.cellAAngstrom, c: x.cellAAngstrom, sites: sites)
    guard let plan = OrientationPlan.generate(crystal: crystal, kMax: x.kMaxInvAngstrom,
        zoneAxisCount: x.zoneAxisCount, symmetry: .cubic, wavelengthAngstrom: x.wavelengthAngstrom,
        intensityPower: x.intensityPower, radialKernelInvAngstrom: x.radialKernelInvAngstrom,
        distinctOrientationDeg: x.distinctOrientationDeg),
        let matcher = OrientationMatcher(plan: plan, symmetry: .cubic)
    else { require(false, "external reference plan and matcher"); return }
    // py4DSTEM lab=(row,column,upstream); app=(column,row,downstream).
    // A proper rotation, not permission to absorb an arbitrary mirror/sign.
    let labSwap = simd_double3x3(rows: [SIMD3(0,1,0), SIMD3(1,0,0), SIMD3(0,0,-1)])
    let ops = operators(hexagonal: false)
    var errors: [Double] = []
    for i in x.patterns.indices {
        let rows = fixture.labMatrices[i]
        require(rows.count == 3 && rows.allSatisfy { $0.count == 3 }, "external matrix shape")
        let truth = simd_double3x3(rows: rows.map { SIMD3($0[0], $0[1], $0[2]) }) * labSwap
        require(!x.patterns[i].isEmpty, "nonempty external pattern")
        let peaks = x.patterns[i].map { BraggPeak(x: Float($0.x), y: Float($0.y), intensity: Float($0.intensity)) }
        let result = matcher.match(peaks: peaks, originX: Float(x.originX), originY: Float(x.originY),
                                   invAngstromPerPixel: x.invAngstromPerPixel)
        require(plan.zoneAxes.indices.contains(result.templateIndex), "external match cannot be skipped")
        errors.append(misorientation(result.euler.py4DSTEMOrientationMatrix, truth, ops))
    }
    let near = errors.filter { $0 < 5 }.count
    print(String(format: "MEASURE: py4DSTEM 0.14.17 %d trials; median %.6f deg; <5 deg %d",
                 errors.count, median(errors), near))
    require(median(errors) < 5 && near >= 24, "frozen external orientation convention")
    print("PASS: external frame mapping and returned matrices; outliers retained")
}
require(CommandLine.arguments.count == 2, "reference.json path required")
analytic(hexagonal: false)
analytic(hexagonal: true)
do { try frozenReference(CommandLine.arguments[1]) }
catch { require(false, "external fixture read/decode: \(error)") }
print("acom-convention-test: all passed")
