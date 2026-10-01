// Row 1 (review 2026-09-30) reproduction and gate: beam axes in the MIRROR
// half of the proper-rotation zone. The bank samples z ≥ x ≥ y ≥ 0 (cubic) /
// the 0–30° sector (hexagonal); a direction in the mirror triangle has no
// template on its proper orbit and its pattern is the 2-D mirror of one — which
// no in-plane rotation reproduces, so the matcher needs py4DSTEM's conjugated
// pass (`inversion_symmetry`, crystal_ACOM.py:877, :1272-1323, :1548-1550).
//
// Independent truth, as in acom-convention-test: peak positions are dot
// products onto a right-handed basis built HERE (never production `project`
// / `detectorBasis`), the orientation is compared as a full matrix under an
// independent proper-group operator list. Reports CPU time per pattern and
// CPU/Metal agreement so the second pass is measured, not assumed.
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
func percentile(_ values: [Double], _ p: Double) -> Double {
    let s = values.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}
func rotationZ(_ a: Double) -> simd_double3x3 {
    simd_double3x3(rows: [SIMD3(cos(a), -sin(a), 0), SIMD3(sin(a), cos(a), 0), SIMD3(0, 0, 1)])
}
// Independent finite groups; never the app's symmetry reducer.
func operators(hexagonal: Bool) -> [simd_double3x3] {
    if hexagonal {
        return (0..<6).map { rotationZ(Double($0) * .pi / 3) } + (0..<6).map {
            let a = Double($0) * .pi / 6, x = cos(a), y = sin(a)
            return simd_double3x3(rows: [SIMD3(2*x*x-1, 2*x*y, 0), SIMD3(2*x*y, 2*y*y-1, 0), SIMD3(0, 0, -1)])
        }
    }
    var result: [simd_double3x3] = []
    for p in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
            let signs = [x, y, z]
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
        if !m[col][row].isFinite || abs(gram[col][row] - (row == col ? 1 : 0)) > 1e-5 { return false }
    } }
    return abs(simd_determinant(m) - 1) < 1e-5
}
// Lab axes are columns in crystal coordinates: symmetry acts on the LEFT.
func misorientation(_ a: simd_double3x3, _ b: simd_double3x3, _ ops: [simd_double3x3]) -> Double {
    require(proper(a) && proper(b), "orientation must be a finite proper rotation")
    return ops.map { op in
        let m = op * a * b.transpose
        return degrees(acos(max(-1, min(1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2))))
    }.min()!
}
/// Angle between the truth beam and the returned beam under the proper group
/// (the row's own metric; blind to the in-plane angle).
func axisError(_ a: simd_double3x3, _ b: simd_double3x3, _ ops: [simd_double3x3]) -> Double {
    ops.map { op in degrees(acos(max(-1, min(1, simd_dot(op * a.columns.2, b.columns.2))))) }.min()!
}
/// Is some proper image of `n` inside the sampled triangle / sector?
func onSampledZone(_ n: SIMD3<Double>, hexagonal: Bool, ops: [simd_double3x3]) -> Bool {
    let eps = 1e-9
    for op in ops {
        let v = op * n
        if hexagonal {
            let az = atan2(v.y, v.x)
            if v.z >= -eps && az >= -eps && az <= .pi / 6 + eps { return true }
        } else if v.z >= v.x - eps && v.x >= v.y - eps && v.y >= -eps { return true }
    }
    return false
}
/// Deterministic xorshift so the random set is the same on every run.
struct Xorshift: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
}
func mirroredFlag(_ result: OrientationResult) -> Bool? {
    // Read through Mirror so this harness compiles against a tree that does
    // not yet carry the flag (the HEAD reproduction run).
    Mirror(reflecting: result).children.first { $0.label == "mirrored" }?.value as? Bool
}

struct Trial {
    let label: String
    let truth: simd_double3x3
    let peaks: [BraggPeak]
    let sampled: Bool
}

func makeTrial(label: String, axis: SIMD3<Double>, angleDeg: Double, reflections: [Reflection],
               wavelength: Double?, scale: Double, origin: Double, ops: [simd_double3x3],
               hexagonal: Bool) -> Trial {
    let n = simd_normalize(axis)
    let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0, 0, 1] : [1, 0, 0]
    let f0 = simd_normalize(seed - simd_dot(seed, n) * n)
    let a = angleDeg * .pi / 180
    let f1 = simd_normalize(f0 * cos(a) + simd_cross(n, f0) * sin(a))
    let f2 = simd_cross(n, f1)
    let truth = simd_double3x3(columns: (f1, f2, n))
    let curvature = (wavelength ?? 0) / 2
    let peaks: [BraggPeak] = reflections.compactMap { r in
        let sg = simd_dot(r.g, n) + curvature * simd_length_squared(r.g)
        let intensity = r.intensity * exp(-pow(sg / 0.03, 2))
        guard abs(sg) <= 0.1 && intensity > 0 else { return nil }
        return BraggPeak(x: Float(origin + simd_dot(r.g, f1) / scale),
                         y: Float(origin + simd_dot(r.g, f2) / scale), intensity: Float(intensity))
    }
    require(peaks.count >= 3, "\(label) informative pattern")
    return Trial(label: label, truth: truth, peaks: peaks,
                 sampled: onSampledZone(n, hexagonal: hexagonal, ops: ops))
}

func run(hexagonal: Bool, wavelength: Double?) -> Bool {
    let family = hexagonal ? "WS2" : "Al"
    let tag = "\(family) \(wavelength == nil ? "flat-Ewald" : String(format: "λ %.5f Å", wavelength!))"
    let ops = operators(hexagonal: hexagonal)
    require(ops.count == (hexagonal ? 12 : 24) && ops.allSatisfy(proper), "independent symmetry group")
    let crystal = hexagonal ? Crystal.tungstenDisulfide : Crystal.aluminum
    let symmetry: ACOMCrystalSymmetry = hexagonal ? .hexagonal : .cubic
    let kMax = hexagonal ? 1.6 : 1.2, scale = 0.008, origin = 256.0
    guard let plan = OrientationPlan.generate(crystal: crystal, kMax: kMax, zoneAxisCount: 600,
                                              symmetry: symmetry, wavelengthAngstrom: wavelength),
          let matcher = OrientationMatcher(plan: plan, symmetry: symmetry)
    else { require(false, "\(tag) plan and matcher"); return false }
    let reflections = crystal.reflections(kMax: kMax)

    // Named axes: five in the sampled zone, their five mirror images.
    var named: [Trial] = []
    let cubicSampled: [SIMD3<Double>] = [[2,1,3], [3,1,5], [5,2,7], [4,1,6], [7,3,9]]
    let hexSampled: [SIMD3<Double>] = (0..<5).map { i in
        let az = (5 + 4 * Double(i)) * .pi / 180, tilt = (25 + 10 * Double(i)) * .pi / 180   // azimuth 5–21°, inside 0–30°
        return SIMD3(sin(tilt) * cos(az), sin(tilt) * sin(az), cos(tilt))
    }
    for axis in (hexagonal ? hexSampled : cubicSampled) {
        let mirror: SIMD3<Double> = hexagonal ? SIMD3(axis.x, -axis.y, axis.z) : SIMD3(axis.y, axis.x, axis.z)
        for (which, v) in [("sampled", axis), ("mirror", mirror)] {
            let label = hexagonal
                ? String(format: "%@ (%.3f %.3f %.3f)", which, v.x, v.y, v.z)
                : String(format: "%@ (%g,%g,%g)", which, v.x, v.y, v.z)
            named.append(makeTrial(label: label, axis: v, angleDeg: 17.3, reflections: reflections,
                                   wavelength: wavelength, scale: scale, origin: origin, ops: ops,
                                   hexagonal: hexagonal))
        }
    }
    require(named.filter(\.sampled).count == 5 && named.filter { !$0.sampled }.count == 5,
            "\(tag) the named axes split 5 sampled / 5 mirror under the independent zone test")

    // Random directions and in-plane angles, same sequence every run.
    var rng = Xorshift(state: hexagonal ? 0x9E3779B97F4A7C15 : 0xD1B54A32D192ED03)
    var random: [Trial] = []
    while random.count < 200 {
        let v = SIMD3(Double.random(in: -1...1, using: &rng), Double.random(in: -1...1, using: &rng),
                      Double.random(in: -1...1, using: &rng))
        let length = simd_length(v)
        guard length > 0.2 && length <= 1 else { continue }
        random.append(makeTrial(label: "random \(random.count)", axis: v / length,
                                angleDeg: Double.random(in: 0..<360, using: &rng), reflections: reflections,
                                wavelength: wavelength, scale: scale, origin: origin, ops: ops,
                                hexagonal: hexagonal))
    }

    let all = named + random
    var errors: [Double] = []
    var results: [OrientationResult] = []
    let started = Date()
    for trial in all {
        let result = matcher.match(peaks: trial.peaks, originX: Float(origin), originY: Float(origin),
                                   invAngstromPerPixel: scale)
        require(plan.zoneAxes.indices.contains(result.templateIndex), "\(tag) no skipped failed match")
        results.append(result)
        errors.append(misorientation(result.euler.py4DSTEMOrientationMatrix, trial.truth, ops))
    }
    // Flat-Ewald templates are exactly π-periodic in azimuth (OrientationPlan
    // `project`), so the in-plane angle is only known modulo 180° and the
    // full-matrix misorientation reads 25–40° on half of ANY set. That run
    // is gated on the beam-axis error instead — the row's own metric — and
    // the λ runs on the full matrix.
    let axisErrors = zip(results, all).map { axisError($0.euler.py4DSTEMOrientationMatrix, $1.truth, ops) }
    let gated = wavelength == nil ? axisErrors : errors
    let metric = wavelength == nil ? "beam-axis error" : "misorientation"
    let perPattern = Date().timeIntervalSince(started) / Double(all.count)
    for (index, trial) in named.enumerated() {
        let r = results[index]
        print(String(format: "  %-32@ misorientation %7.2f°  axis %6.2f°  template %3d  score %.3f  mirrored %@",
                     trial.label, errors[index], axisErrors[index], r.templateIndex, r.score,
                     mirroredFlag(r).map { $0 ? "yes" : "no" } ?? "n/a"))
    }
    let namedSampled = zip(named, gated).filter { $0.0.sampled }.map(\.1)
    let namedMirror = zip(named, gated).filter { !$0.0.sampled }.map(\.1)
    let randomErrors = Array(gated[named.count...])
    let randomSampled = zip(random, randomErrors).filter { $0.0.sampled }.map(\.1)
    let randomMirror = zip(random, randomErrors).filter { !$0.0.sampled }.map(\.1)
    let flagged = results.compactMap(mirroredFlag).filter { $0 }.count
    // Separation of the two passes: the winner template's forward (conj(E)·T)
    // and mirrored (E·T) best correlations, per trial, split by zone. Printed for
    // the record only: sampled-zone mirrored wins are NOT float ties (gaps
    // 0.014–0.37, archive/v4/slot2-fa-refuter-2026-10-01.md).
    if let fft = FFT1D(n: plan.geometry.nAzimuthal) {
        let na = plan.geometry.nAzimuthal, nr = plan.geometry.nRadial
        var gaps: [String: [Double]] = [:]
        for (trial, result) in zip(all, results) {
            guard let e = matcher.experimentalFFT(peaks: trial.peaks, originX: Float(origin), originY: Float(origin),
                                                  invAngstromPerPixel: scale) else { continue }
            let off = result.templateIndex * nr * na
            var best: [Float] = []
            for sign in [Float(1), Float(-1)] {
                var re = [Float](repeating: 0, count: na), im = re
                for r in 0..<nr { for a in 0..<na {
                    let i = r * na + a, er = e.real[i], ei = sign * e.imaginary[i]
                    let tr = plan.templateFFTRe[off + i], ti = plan.templateFFTIm[off + i]
                    re[a] += er * tr + ei * ti; im[a] += er * ti - ei * tr
                } }
                fft.transform(re: &re, im: &im, forward: false)
                best.append(re.max()! / Float(na))
            }
            let key = (trial.sampled ? "sampled" : "mirror") + " zone, " + ((mirroredFlag(result) ?? false) ? "mirrored win" : "forward win")
            gaps[key, default: []].append(Double(best[1] - best[0]))
        }
        for key in gaps.keys.sorted() {
            let g = gaps[key]!.sorted()
            print(String(format: "MEASURE: %@ pass gap (mirror − forward) %@: n=%d min %.2e median %.2e max %.2e",
                         tag, key, g.count, g.first!, median(g), g.last!))
        }
    }
    let sampledOver3 = zip(random, randomErrors).filter { $0.0.sampled && $0.1 > 3 }.count
    let mirrorOver3 = zip(random, randomErrors).filter { !$0.0.sampled && $0.1 > 3 }.count
    print(String(format: "MEASURE: %@ random > 3°: sampled %d of %d, mirror %d of %d", tag, sampledOver3,
                 randomSampled.count, mirrorOver3, randomMirror.count))
    print(String(format: "MEASURE: %@ (%@) named sampled median %.3f° max %.3f°; named mirror median %.3f° max %.3f°",
                 tag, metric, median(namedSampled), namedSampled.max()!, median(namedMirror), namedMirror.max()!))
    print(String(format: "MEASURE: %@ (%@) random n=%d (sampled %d / mirror %d): sampled median %.3f° p90 %.3f° max %.3f°; mirror median %.3f° p90 %.3f° max %.3f°; > 3° %d of %d; mirrored flag set on %d",
                 tag, metric, random.count, randomSampled.count, randomMirror.count,
                 median(randomSampled), percentile(randomSampled, 0.9), randomSampled.max()!,
                 median(randomMirror), percentile(randomMirror, 0.9), randomMirror.max()!,
                 randomErrors.filter { $0 > 3 }.count, randomErrors.count, flagged))
    print(String(format: "MEASURE: %@ CPU single matcher %.3f ms per pattern (%d templates, %d patterns)",
                 tag, perPattern * 1000, plan.count, all.count))

    // Metal must carry the same pass: compare choices on every pattern.
    let vectors = BraggVectors(scanWidth: all.count, scanHeight: 1, peaks: all.map(\.peaks))
    let metalStart = Date()
    if let metal = OrientationMatching.matchAll(bragg: vectors, plan: plan, originX: Float(origin),
                                                originY: Float(origin), invAngstromPerPixel: scale,
                                                backend: .metal) {
        let metalSeconds = Date().timeIntervalSince(metalStart)
        var templateAgree = 0, angleAgree = 0
        var scoreError: Float = 0
        for (index, cpu) in results.enumerated() {
            let gpu = metal.results[index]
            scoreError = max(scoreError, abs(cpu.score - gpu.score))
            guard cpu.templateIndex == gpu.templateIndex, mirroredFlag(cpu) == mirroredFlag(gpu) else { continue }
            templateAgree += 1
            let raw = abs(cpu.inPlaneAngle - gpu.inPlaneAngle).truncatingRemainder(dividingBy: 2 * .pi)
            if min(raw, 2 * .pi - raw) < 1e-6 { angleAgree += 1 }
        }
        print(String(format: "MEASURE: %@ Metal %.3f ms per pattern; template+flag agreement %d/%d; angle agreement %d; max score error %.2e",
                     tag, metalSeconds / Double(all.count) * 1000, templateAgree, all.count, angleAgree, scoreError))
        require(templateAgree >= all.count - 2 && scoreError < 2e-4,
                "\(tag) CPU/Metal parity (template, mirrored flag, score)")
    } else {
        print("MEASURE: \(tag) Metal backend unavailable here; parity not measured")
    }
    let sampledOK = median(namedSampled) < 3 && median(randomSampled) < 3
    let mirrorOK = median(namedMirror) < 3 && median(randomMirror) < 3
    print("\(mirrorOK && sampledOK ? "PASS" : "FAIL"): \(tag) sampled-zone \(sampledOK ? "recovered" : "LOST"), mirror-zone \(mirrorOK ? "recovered" : "LOST")")
    return mirrorOK && sampledOK
}

var allPassed = true
for wavelength in [nil, 0.02508] as [Double?] {
    allPassed = run(hexagonal: false, wavelength: wavelength) && allPassed
}
allPassed = run(hexagonal: true, wavelength: 0.02508) && allPassed
require(allPassed, "mirror-zone orientations must be recovered as well as sampled-zone ones")
print("acom-mirror-test: all passed")
