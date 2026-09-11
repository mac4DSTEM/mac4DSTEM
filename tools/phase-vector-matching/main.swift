//
//  tools/phase-vector-matching/main.swift
//  The gate for vector-matched phase mapping: `PhaseReferenceLibrary` (the
//  reference vectors) and `PhaseVectorMatcher` (the score and the verdict).
//
//  WHAT GROUND TRUTH IS HERE, because "ground truth is analytic or py4DSTEM
//  itself, never the code under test's own output" is a repo rule and this
//  feature has no py4DSTEM counterpart:
//
//   • Part A checks the reference vectors against ARITHMETIC — |g| for fcc
//     {200}/{220} is 2/a and 2√2/a, and |g(h0l)| for a monoclinic cell comes
//     from the reciprocal metric, both computed here in closed form.
//   • Part B generates synthetic patterns from an INDEPENDENT projection
//     written in this file (`harnessProject`) straight off `Crystal`, never
//     through `PhaseReferenceLibrary`. Part A asserts the two agree, so a
//     disagreement turns the gate red instead of cancelling out. The L3 lesson
//     — a harness that passed a transposed decode because both sides
//     transposed together — is exactly what this structure is avoiding.
//
//  PRE-REGISTERED PASS CRITERIA (written before the first run):
//    P1  ≥ 95 % of matrix-only positions verdict .matrix
//    P2  ≥ 90 % of β″ positions labelled β″
//    P3  ≥ 90 % of random-vector positions verdict .notIndexed
//    P4  100 % of empty positions verdict .noData
//    P5  the fitted matrix in-plane rotation is within one step of the planted
//        13.7°, which a sign error cannot satisfy (it would give 346.3°)
//    P6  on a pattern of pure ALUMINIUM with gold and aluminium both candidates,
//        the winner is ALUMINIUM. This is the 2026-09-11 refutation re-run:
//        the template-matched route returned GOLD at contrast −0.008.
//    P7  β″ expands to Mg₁₀Si₁₂ = 22 atoms (Andersen et al. 1998)
//    P8  the length-band prune is exact — brute-force nearest neighbour gives
//        bit-identical verdicts
//
//  MEASUREMENTS, not criteria. These print numbers and never fail the gate,
//  because their answers are not known in advance and a threshold invented to
//  make them pass would be a guess:
//    M1  the noise σ at which aluminium and gold stop separating
//    M2  what removing the visibility cut (minimumIntensityFraction = 0) does
//    M3  what removing the completeness requirement does
//    M4  what removing the not-indexed threshold does
//

import Foundation
import simd

// MARK: - Reporting

var failures: [String] = []
var checks = 0

func check(_ name: String, _ ok: Bool, _ detail: String) {
    checks += 1
    print(ok ? "[ok  ] \(name): \(detail)" : "[FAIL] \(name): \(detail)")
    if !ok { failures.append(name) }
}

func measure(_ name: String, _ detail: String) {
    print("[meas] \(name): \(detail)")
}

// MARK: - Deterministic noise

/// xorshift64*, seeded by a constant. Box-Muller for the Gaussian. Nothing
/// here may use a system RNG: a gate that is not reproducible is not a gate.
struct Rng {
    var state: UInt64 = 0x9E3779B97F4A7C15
    mutating func next() -> UInt64 {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return state &* 2685821657736338717
    }
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func gaussian() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - The independent projection

/// Project a crystal's reflections at beam direction [uvw], written here from
/// the crystallography rather than called from the code under test.
///
/// A zone axis is a real-space direction, so the beam is `u·a₁ + v·a₂ + w·a₃`.
/// A reflection belongs to the zero-order Laue zone when `g·n ≈ 0`; the
/// in-plane components are `g` projected on any orthonormal pair spanning the
/// plane ⊥ n. The pair used is the app's own `ACOMOrientation.detectorBasis`,
/// deliberately: the aim is to check the SELECTION and the SCALING
/// independently, not to invent a second in-plane frame that would make every
/// comparison fail for a reason that is not a defect.
func harnessProject(_ crystal: Crystal, zone uvw: SIMD3<Int>, kMax: Double,
                    sgMax: Double) -> [(h: Int, k: Int, l: Int, q: SIMD2<Double>, weight: Double)] {
    let r = Double(uvw.x) * crystal.latReal[0]
        + Double(uvw.y) * crystal.latReal[1]
        + Double(uvw.z) * crystal.latReal[2]
    let n = r / simd_length(r)
    let basis = ACOMOrientation.detectorBasis(zoneAxis: n)
    var out: [(h: Int, k: Int, l: Int, q: SIMD2<Double>, weight: Double)] = []
    for refl in crystal.reflections(kMax: kMax) {
        let sg = simd_dot(refl.g, n)
        if abs(sg) > sgMax { continue }
        let q = SIMD2(simd_dot(refl.g, basis.columns.0), simd_dot(refl.g, basis.columns.1))
        let len = simd_length(q)
        if !(len > 1e-9) || len > kMax { continue }
        out.append((refl.h, refl.k, refl.l, q, refl.intensity))
    }
    return out
}

func rotated(_ q: SIMD2<Double>, _ theta: Double) -> SIMD2<Double> {
    SIMD2(cos(theta) * q.x - sin(theta) * q.y, sin(theta) * q.x + cos(theta) * q.y)
}

// MARK: - Geometry of the synthetic detector

let invAngstromPerPixel = 0.008
let originX: Float = 128, originY: Float = 128
let kMax = 1.2
let sgMax = 0.05

func peaks(from qs: [SIMD2<Double>], noiseSigmaPixels: Double,
           includeDirectBeam: Bool, rng: inout Rng) -> [BraggPeak] {
    var out: [BraggPeak] = []
    if includeDirectBeam { out.append(BraggPeak(x: originX, y: originY, intensity: 10)) }
    for q in qs {
        let px = Double(originX) + q.x / invAngstromPerPixel + noiseSigmaPixels * rng.gaussian()
        let py = Double(originY) + q.y / invAngstromPerPixel + noiseSigmaPixels * rng.gaussian()
        out.append(BraggPeak(x: Float(px), y: Float(py), intensity: 1))
    }
    return out
}

@main
enum Harness {
  static func main() throws {
    // ============================================================================
    print("== Part A — the reference vectors against arithmetic")
    // ============================================================================

    var settings = PhaseReferenceSettings()
    settings.kMaxInvAngstrom = kMax
    settings.excitationSlabInvAngstrom = sgMax
    settings.minimumIntensityFraction = 0.02
    settings.inPlaneStepDeg = 2

    // A1 — aluminium fcc down [001]. |g(200)| = 2/a, |g(220)| = 2√2/a, and the
    // forbidden 100/110 must be absent: fcc extinguishes mixed-parity hkl.
    let al = Crystal.aluminum
    let alVectors = PhaseReferenceLibrary.projectedVectors(
        reflections: al.reflections(kMax: kMax), crystal: al,
        zoneAxis: SIMD3(0, 0, 1), settings: settings)
    let a0 = al.a
    let expected200 = 2 / a0, expected220 = 2 * 2.0.squareRoot() / a0
    let lengths = alVectors.map(\.length).sorted()
    let shortest = lengths.first ?? .nan
    check("A1a fcc {200} = 2/a",
          abs(shortest - expected200) < 1e-9,
          String(format: "shortest |q| %.9f, 2/a %.9f", shortest, expected200))
    let has220 = lengths.contains { abs($0 - expected220) < 1e-9 }
    check("A1b fcc {220} = 2√2/a", has220,
          String(format: "expected %.9f among %d lengths", expected220, lengths.count))
    let forbidden = lengths.contains { abs($0 - 1 / a0) < 1e-6 || abs($0 - 2.0.squareRoot() / a0) < 1e-6 }
    check("A1c fcc mixed-parity reflections absent", !forbidden,
          "no |q| at 1/a or √2/a — 100 and 110 are extinguished")
    check("A1d the [001] set is the l = 0 zone",
          alVectors.allSatisfy { $0.l == 0 },
          "\(alVectors.count) vectors, every one l = 0 (Laue-zone spacing 1/a = "
          + String(format: "%.4f Å⁻¹ > sgMax %.2f)", 1 / a0, sgMax))

    // A2 — β″, monoclinic C2/m, down [001]. The reciprocal metric of a b-unique
    // monoclinic cell: a* = 1/(a sinβ), c* = 1/(c sinβ), cos β* = −cos β.
    let beta = Crystal.betaDoublePrime
    check("P7 β″ expands to 22 atoms",
          beta.sites.count == 22
          && beta.sites.filter({ $0.z == 12 }).count == 10
          && beta.sites.filter({ $0.z == 14 }).count == 12,
          "\(beta.sites.count) sites, Mg \(beta.sites.filter { $0.z == 12 }.count), "
          + "Si \(beta.sites.filter { $0.z == 14 }.count) — Andersen et al. 1998 states Mg₁₀Si₁₂")

    let betaRad = beta.betaDeg * .pi / 180
    let aStar = 1 / (beta.a * sin(betaRad))
    let cStar = 1 / (beta.c * sin(betaRad))
    let cosBetaStar = -cos(betaRad)
    func monoclinicLength(_ h: Int, _ l: Int) -> Double {
        let hh = Double(h), ll = Double(l)
        return (hh * hh * aStar * aStar + ll * ll * cStar * cStar
                + 2 * hh * ll * aStar * cStar * cosBetaStar).squareRoot()
    }
    let betaVectors = PhaseReferenceLibrary.projectedVectors(
        reflections: beta.reflections(kMax: kMax), crystal: beta,
        zoneAxis: SIMD3(0, 1, 0), settings: settings)
    check("A2a β″ [010] is the k = 0 zone",
          !betaVectors.isEmpty && betaVectors.allSatisfy { $0.k == 0 },
          "\(betaVectors.count) vectors, every one k = 0")
    var worstMonoclinic = 0.0
    for v in betaVectors {
        worstMonoclinic = max(worstMonoclinic, abs(v.length - monoclinicLength(v.h, v.l)))
    }
    check("A2b β″ |q(h0l)| matches the monoclinic reciprocal metric",
          worstMonoclinic < 1e-9,
          String(format: "worst |Δ| %.3e Å⁻¹ over %d vectors; a* %.6f c* %.6f cosβ* %.6f",
                 worstMonoclinic, betaVectors.count, aStar, cStar, cosBetaStar))

    // A3 — the zone axis is a REAL-SPACE direction. For a monoclinic cell [001]
    // is not the Cartesian (0,0,1), and this is the mutation that would otherwise
    // be invisible: it costs nothing on every cubic phase and silently rotates
    // every monoclinic one.
    let betaC = PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: beta)!
    let naive = SIMD3<Double>(0, 0, 1)
    let misorientationDeg = acos(min(1, abs(simd_dot(betaC, naive)))) * 180 / .pi
    check("A3a β″ [001] is c/|c|, not the Cartesian triple",
          abs(betaC.x - cos(betaRad)) < 1e-12 && abs(betaC.z - sin(betaRad)) < 1e-12,
          String(format: "(%.6f, %.6f, %.6f); expected (cos β, 0, sin β)", betaC.x, betaC.y, betaC.z))
    check("A3b and the difference is large enough to be a real defect",
          misorientationDeg > 10,
          String(format: "%.2f° from the naive (0,0,1)", misorientationDeg))

    // A4 — the library's projection agrees with the independent one written above.
    // This is what stops Part B from testing the code against itself.
    var worstParity = 0.0
    var parityPairs = 0
    for (crystal, zone) in [(al, SIMD3(0, 0, 1)), (beta, SIMD3(0, 1, 0)), (beta, SIMD3(0, 0, 1))] {
        let mine = harnessProject(crystal, zone: zone, kMax: kMax, sgMax: sgMax)
        let theirs = PhaseReferenceLibrary.projectedVectors(
            reflections: crystal.reflections(kMax: kMax), crystal: crystal,
            zoneAxis: zone, settings: settings)
        for t in theirs {
            guard let m = mine.first(where: { $0.h == t.h && $0.k == t.k && $0.l == t.l }) else {
                worstParity = .infinity; continue
            }
            worstParity = max(worstParity, simd_distance(m.q, t.q))
            parityPairs += 1
        }
    }
    check("A4 library projection == the harness's independent projection",
          worstParity < 1e-12,
          String(format: "worst |Δq| %.3e Å⁻¹ over %d shared reflections", worstParity, parityPairs))

    // ============================================================================
    print("\n== Part B — the matcher on planted truth")
    // ============================================================================

    let scanW = 64, scanH = 64
    let plantedMatrixRotation = 13.7 * Double.pi / 180
    let plantedBetaRotation = 37.2 * Double.pi / 180     // sign-discriminating; never 90°
    let noiseSigmaPixels = 0.25                          // ~0.002 Å⁻¹ at this scale

    enum Truth: UInt8 { case matrix, beta, random, empty }

    func truth(_ x: Int, _ y: Int) -> Truth {
        if x >= 8 && x < 24 && y >= 8 && y < 40 { return .beta }
        if x >= 40 && x < 56 && y >= 8 && y < 24 { return .random }
        if x >= 40 && x < 56 && y >= 40 && y < 56 { return .empty }
        return .matrix
    }

    let alPlane = harnessProject(al, zone: SIMD3(0, 0, 1), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, plantedMatrixRotation) }
    let betaPlane = harnessProject(beta, zone: SIMD3(0, 1, 0), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, plantedBetaRotation) }
    check("B0 the planted phases have vectors to match",
          alPlane.count >= 4 && betaPlane.count >= 6,
          "Al [001] \(alPlane.count) vectors, β″ [010] \(betaPlane.count) vectors")

    var rng = Rng()
    var patterns: [[BraggPeak]] = []
    patterns.reserveCapacity(scanW * scanH)
    for y in 0..<scanH {
        for x in 0..<scanW {
            switch truth(x, y) {
            case .matrix:
                patterns.append(peaks(from: alPlane, noiseSigmaPixels: noiseSigmaPixels,
                                      includeDirectBeam: true, rng: &rng))
            case .beta:
                // A precipitate sits INSIDE the matrix: both sets are present. This
                // is the case the template-matched route could not do.
                patterns.append(peaks(from: alPlane + betaPlane, noiseSigmaPixels: noiseSigmaPixels,
                                      includeDirectBeam: true, rng: &rng))
            case .random:
                var qs: [SIMD2<Double>] = []
                for _ in 0..<8 {
                    let r = 0.3 + 0.7 * rng.uniform(), a = 2 * Double.pi * rng.uniform()
                    qs.append(SIMD2(r * cos(a), r * sin(a)))
                }
                patterns.append(peaks(from: alPlane + qs, noiseSigmaPixels: noiseSigmaPixels,
                                      includeDirectBeam: true, rng: &rng))
            case .empty:
                patterns.append([])
            }
        }
    }
    let bragg = BraggVectors(scanWidth: scanW, scanHeight: scanH, peaks: patterns)

    func buildLibrary(minimumIntensityFraction: Double,
                      maximumVectorsPerEntry: Int) throws -> PhaseReferenceLibrary {
        var s = settings
        s.minimumIntensityFraction = minimumIntensityFraction
        s.maximumVectorsPerEntry = maximumVectorsPerEntry
        return try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: al,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: beta,
                            role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
        ], settings: s)
    }

    let library = try buildLibrary(minimumIntensityFraction: settings.minimumIntensityFraction,
                                   maximumVectorsPerEntry: settings.maximumVectorsPerEntry)
    measure("library size", "\(library.entries.count) entries "
            + "(\(library.matrixEntryIndices.count) matrix, \(library.candidateEntryIndices.count) candidate), "
            + "vectors per entry: Al \(library.entries[library.matrixEntryIndices[0]].vectors.count), "
            + "β″ \(library.entries[library.candidateEntryIndices[0]].vectors.count)")

    // The SHIPPED defaults, deliberately not overridden: a gate that tests
    // settings nobody runs tests nothing.
    let matchSettings = PhaseVectorSettings()
    measure("matcher settings",
            String(format: "direct beam %.3f, matrix tolerance %.3f, pair radius %.3f, "
                   + "not indexed above %.3f Å⁻¹ (all defaults)",
                   matchSettings.directBeamRadiusInvAngstrom,
                   matchSettings.matrixToleranceInvAngstrom,
                   matchSettings.pairRadiusInvAngstrom,
                   matchSettings.notIndexedAboveInvAngstrom))
    let chanceMatrix = library.entries[library.matrixEntryIndices[0]]
        .chanceMatchFraction(pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: kMax)
    let chanceCandidate = library.entries[library.candidateEntryIndices[0]]
        .chanceMatchFraction(pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: kMax)
    measure("chance-match fraction at the shipped pair radius",
            String(format: "Al %.1f %%, β″ %.1f %% — how often a vector pointing nowhere "
                   + "in particular matches this entry by accident", 100 * chanceMatrix, 100 * chanceCandidate))

    func accuracy(_ map: PhaseMap) -> (matrix: Double, beta: Double, random: Double, empty: Double) {
        var n = [0, 0, 0, 0], hit = [0, 0, 0, 0]
        let betaIndex = library.phases.firstIndex { $0.id == "beta" }!
        for y in 0..<scanH {
            for x in 0..<scanW {
                let t = truth(x, y)
                let r = map.results[y * scanW + x]
                n[Int(t.rawValue)] += 1
                let correct: Bool
                switch t {
                case .matrix: correct = r.verdict == .matrix
                case .beta:   correct = r.verdict == .indexed && Int(r.phaseIndex) == betaIndex
                case .random: correct = r.verdict == .notIndexed
                case .empty:  correct = r.verdict == .noData
                }
                if correct { hit[Int(t.rawValue)] += 1 }
            }
        }
        func f(_ i: Int) -> Double { n[i] == 0 ? .nan : Double(hit[i]) / Double(n[i]) }
        return (f(0), f(1), f(2), f(3))
    }

    let started = Date()
    guard let map = PhaseVectorMatcher.map(
        bragg: bragg, library: library, settings: matchSettings,
        originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel
    ) else { print("[FAIL] the matcher returned nil"); exit(1) }
    let elapsed = Date().timeIntervalSince(started)
    let acc = accuracy(map)
    measure("run time", String(format: "%.2f s for %d positions × %d entries",
                               elapsed, scanW * scanH, library.entries.count))
    check("P1 matrix-only positions", acc.matrix >= 0.95,
          String(format: "%.1f %% verdict .matrix (criterion ≥ 95 %%)", 100 * acc.matrix))
    check("P2 β″ positions", acc.beta >= 0.90,
          String(format: "%.1f %% labelled β″ (criterion ≥ 90 %%)", 100 * acc.beta))
    check("P3 random-vector positions", acc.random >= 0.90,
          String(format: "%.1f %% verdict .notIndexed (criterion ≥ 90 %%)", 100 * acc.random))
    check("P4 empty positions", acc.empty >= 0.999,
          String(format: "%.1f %% verdict .noData (criterion 100 %%)", 100 * acc.empty))

    // P5 — the fitted matrix orientation. CHECKED AS A VECTOR SET, not as an
    // angle, and the first version of this check was wrong in a way worth
    // recording: it compared the fitted angle to the planted 13.7° and failed
    // at 284.0°, an error of 89.7°. That was the TEST being wrong, not the
    // code — the {200}/{220} set of an fcc [001] projection is 4-fold
    // symmetric, so 13.7° and 283.7° produce the same spots and no method
    // that looks at spots can tell them apart. What is actually determined is
    // the vector SET, so that is what is asserted; the angle is reported as a
    // measurement beside it. The consequence for the UI is real and is why
    // this is in the gate: an in-plane rotation from this matcher is only
    // meaningful modulo the projected symmetry of the phase, and must never be
    // presented as an absolute orientation.
    let fittedRotation = library.entries[map.matrixEntryIndex].inPlaneRotationRad * 180 / .pi
    let fittedSet = library.entries[map.matrixEntryIndex].vectors.map(\.q)
    func setDistance(_ planted: [SIMD2<Double>]) -> Double {
        var worst = 0.0
        for p in planted {
            var best = Double.infinity
            for f in fittedSet { best = min(best, simd_distance(p, f)) }
            worst = max(worst, best)
        }
        return worst
    }
    let plantedDistance = setDistance(alPlane)
    // A 2° step against a 13.7° plant leaves 0.3° of residual, which at the
    // outermost |q| here is ~0.004 Å⁻¹. 0.01 admits that and nothing else.
    check("P5a the fitted matrix entry reproduces the planted vector set",
          plantedDistance < 0.01,
          String(format: "worst nearest-neighbour %.5f Å⁻¹; fitted angle %.1f°, planted 13.7° "
                 + "(equal modulo the 4-fold projected symmetry: %.1f°)",
                 plantedDistance, fittedRotation,
                 (fittedRotation - 13.7).truncatingRemainder(dividingBy: 90)))
    let flipped = harnessProject(al, zone: SIMD3(0, 0, 1), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, -plantedMatrixRotation) }
    let flippedDistance = setDistance(flipped)
    check("P5b and a SIGN-FLIPPED plant does not satisfy it",
          flippedDistance > 0.05,
          String(format: "worst nearest-neighbour %.5f Å⁻¹ at −13.7° — the check has teeth",
                 flippedDistance))

    // ============================================================================
    print("\n== Part C — the 2026-09-11 refutation, re-run")
    // ============================================================================
    // A pattern containing ONLY aluminium, with gold and aluminium both candidates.
    // The template-matched route scored Au 0.98758 against Al 0.97949 and returned
    // GOLD, because one radial bin was 0.05 Å⁻¹ and the two differ by 6 % of it.

    let au = Crystal.gold
    let si = Crystal.silicon
    func metalLibrary(_ s: PhaseReferenceSettings) throws -> PhaseReferenceLibrary {
        try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "si", displayName: "Si", crystal: si,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "al", displayName: "Al", crystal: al,
                            role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "au", displayName: "Au", crystal: au,
                            role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
        ], settings: s)
    }
    let metals = try metalLibrary(settings)
    let alOnly = harnessProject(al, zone: SIMD3(0, 0, 1), kMax: kMax, sgMax: sgMax).map(\.q)
    let gAl = 2 / al.a, gAu = 2 / au.a
    measure("Al vs Au geometry",
            String(format: "|g(200)| %.5f vs %.5f Å⁻¹, separation %.5f Å⁻¹ "
                   + "(%.1f %% of the %.3f Å⁻¹ pair radius)",
                   gAl, gAu, abs(gAl - gAu), 100 * abs(gAl - gAu) / matchSettings.pairRadiusInvAngstrom,
                   matchSettings.pairRadiusInvAngstrom))

    func classifyPureAl(noise: Double, seed: UInt64, library: PhaseReferenceLibrary,
                        settings s: PhaseVectorSettings, repeats: Int = 200)
        -> (alWins: Int, auWins: Int, other: Int, meanContrast: Double) {
        var r = Rng(state: seed)
        let alIndex = library.phases.firstIndex { $0.id == "al" }!
        let auIndex = library.phases.firstIndex { $0.id == "au" }!
        var alWins = 0, auWins = 0, other = 0
        var contrastSum = 0.0, contrastN = 0
        let scratch = PhaseVectorMatcher.Scratch(capacity: library.entries.map(\.vectors.count).max() ?? 1)
        for _ in 0..<repeats {
            let p = peaks(from: alOnly, noiseSigmaPixels: noise, includeDirectBeam: true, rng: &r)
            let v = PhaseVectorMatcher.experimentalVectors(
                peaks: p, originX: originX, originY: originY,
                invAngstromPerPixel: invAngstromPerPixel,
                directBeamRadiusInvAngstrom: s.directBeamRadiusInvAngstrom)
            // No matrix entry: nothing should be removed, the pattern IS aluminium.
            let result = PhaseVectorMatcher.classify(
                vectors: v, library: library, settings: s, matrixEntry: nil,
                candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
            if result.verdict == .indexed && Int(result.phaseIndex) == alIndex { alWins += 1 }
            else if result.verdict == .indexed && Int(result.phaseIndex) == auIndex { auWins += 1 }
            else { other += 1 }
            if result.phaseContrast.isFinite { contrastSum += Double(result.phaseContrast); contrastN += 1 }
        }
        return (alWins, auWins, other, contrastN == 0 ? .nan : contrastSum / Double(contrastN))
    }

    let clean = classifyPureAl(noise: 0, seed: 0x1234_5678, library: metals, settings: matchSettings)
    check("P6 pure aluminium is labelled aluminium, not gold",
          clean.alWins == 200 && clean.auWins == 0,
          "Al \(clean.alWins)/200, Au \(clean.auWins)/200, neither \(clean.other)/200; "
          + String(format: "mean contrast over the runner-up %.5f Å⁻¹", clean.meanContrast))

    measure("M1 Al/Au separation against position noise", "")
    for sigma in [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 4.0] {
        let r = classifyPureAl(noise: sigma, seed: 0xABCD_0000 &+ UInt64(sigma * 100),
                               library: metals, settings: matchSettings)
        print(String(format: "         σ %.2f px (%.4f Å⁻¹): Al %3d, Au %3d, neither %3d, contrast %+.5f Å⁻¹",
                     sigma, sigma * invAngstromPerPixel, r.alWins, r.auWins, r.other, r.meanContrast))
    }

    // ============================================================================
    print("\n== Part D — negative controls: does each guard bite?")
    // ============================================================================

    // N1 — the visibility cut. `minimumIntensityFraction` exists to stop a library
    // holding every kinematically allowed vector, which would give every phase a
    // near neighbour for every peak. Its effect is MEASURED, not asserted: if it
    // turns out to change nothing, the file header's claim is wrong and gets
    // corrected rather than defended.
    // BOTH halves of the cut are removed: capping the count alone made this
    // measurement vacuous (it printed "48 → 48", comparing the cap against
    // itself), which is precisely the kind of check Gate B exists to catch.
    let dense = try buildLibrary(minimumIntensityFraction: 0, maximumVectorsPerEntry: 0)
    let denseChance = dense.entries[dense.candidateEntryIndices[0]]
        .chanceMatchFraction(pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: kMax)
    measure("M2 visibility cut AND density cap removed",
            "vectors per β″ entry \(library.entries[library.candidateEntryIndices[0]].vectors.count) "
            + "→ \(dense.entries[dense.candidateEntryIndices[0]].vectors.count), "
            + String(format: "chance-match %.1f %% → %.1f %%", 100 * chanceCandidate, 100 * denseChance))
    if let denseMap = PhaseVectorMatcher.map(
        bragg: bragg, library: dense, settings: matchSettings,
        originX: originX, originY: originY, invAngstromPerPixel: invAngstromPerPixel) {
        let d = accuracy(denseMap)
        print(String(format: "         matrix %.1f %% (was %.1f), β″ %.1f %% (was %.1f), "
                     + "random %.1f %% (was %.1f)",
                     100 * d.matrix, 100 * acc.matrix, 100 * d.beta, 100 * acc.beta,
                     100 * d.random, 100 * acc.random))
    }

    // N2 — the completeness requirement. A pure mean-distance score lets a phase
    // explaining one vector out of ten beat one explaining nine.
    var noCompleteness = matchSettings
    noCompleteness.chanceMatchMultiple = 0
    noCompleteness.minimumMatchedVectors = 1
    if let m = PhaseVectorMatcher.map(bragg: bragg, library: library, settings: noCompleteness,
                                      originX: originX, originY: originY,
                                      invAngstromPerPixel: invAngstromPerPixel) {
        let d = accuracy(m)
        measure("M3 chance guard and matched-vector floor removed",
                String(format: "matrix %.1f %% (was %.1f), β″ %.1f %% (was %.1f), random %.1f %% (was %.1f)",
                       100 * d.matrix, 100 * acc.matrix, 100 * d.beta, 100 * acc.beta,
                       100 * d.random, 100 * acc.random))
    }

    // N3 — the not-indexed threshold. With it removed, a random pattern must be
    // forced into a phase; if it is not, the threshold is not what refuses them.
    var noRefusal = matchSettings
    noRefusal.notIndexedAboveInvAngstrom = .greatestFiniteMagnitude
    if let m = PhaseVectorMatcher.map(bragg: bragg, library: library, settings: noRefusal,
                                      originX: originX, originY: originY,
                                      invAngstromPerPixel: invAngstromPerPixel) {
        let d = accuracy(m)
        var forced = 0
        for y in 0..<scanH {
            for x in 0..<scanW where truth(x, y) == .random {
                if m.results[y * scanW + x].verdict == .indexed { forced += 1 }
            }
        }
        measure("M4 not-indexed threshold removed",
                String(format: "%d random positions forced into a phase; random accuracy %.1f %% (was %.1f)",
                       forced, 100 * d.random, 100 * acc.random))
    }

    // N4 — the length-band prune must be exact. Brute force over every reference
    // vector has to give identical answers; if it does not, the optimisation is a
    // silent approximation.
    func bruteNearest(_ u: SIMD2<Double>, _ refs: [ReferenceVector], _ radius: Double)
        -> (index: Int, distance: Double)? {
        var best = -1, bestD = Double.infinity
        for (i, v) in refs.enumerated() {
            let d = simd_distance(u, v.q)
            if d < bestD { bestD = d; best = i }
        }
        return (best >= 0 && bestD <= radius) ? (best, bestD) : nil
    }
    var pruneMismatch = 0, pruneComparisons = 0
    var pruneRng = Rng(state: 0x5150_5150)
    for entryIndex in [library.matrixEntryIndices[0], library.candidateEntryIndices[0],
                       library.candidateEntryIndices[library.candidateEntryIndices.count / 3]] {
        let refs = library.entries[entryIndex].vectors
        for _ in 0..<20000 {
            let r = 1.4 * pruneRng.uniform(), a = 2 * Double.pi * pruneRng.uniform()
            let u = SIMD2(r * cos(a), r * sin(a))
            let fast = PhaseVectorMatcher.nearest(u, in: refs, radius: matchSettings.pairRadiusInvAngstrom)
            let slow = bruteNearest(u, refs, matchSettings.pairRadiusInvAngstrom)
            pruneComparisons += 1
            if fast?.index != slow?.index || (fast?.distance ?? -1) != (slow?.distance ?? -1) {
                pruneMismatch += 1
            }
        }
    }
    check("P8 the length-band prune is exact", pruneMismatch == 0,
          "\(pruneComparisons) random probes against brute force, \(pruneMismatch) mismatches")

    // N5 — the refusals a library must make.
    do {
        _ = try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: al, role: .candidate,
                            zoneAxes: [SIMD3(0, 0, 1)]),
        ], settings: settings)
        check("N5a a library with no matrix is refused", false, "it was accepted")
    } catch let e as PhaseReferenceLibrary.Failure {
        check("N5a a library with no matrix is refused",
              e == .matrixPhaseNotUnique(count: 0), "\(e)")
    } catch { check("N5a a library with no matrix is refused", false, "\(error)") }

    do {
        var tiny = settings
        tiny.inPlaneStepDeg = 0.1
        tiny.maximumEntries = 100
        _ = try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: al, role: .matrix, zoneAxes: []),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: beta, role: .candidate, zoneAxes: []),
        ], settings: tiny)
        check("N5b an oversized library is refused", false, "it was accepted")
    } catch let e as PhaseReferenceLibrary.Failure {
        if case .libraryTooLarge(let requested, let limit) = e {
            check("N5b an oversized library is refused", true,
                  "\(requested) entries requested against a limit of \(limit)")
        } else {
            check("N5b an oversized library is refused", false, "\(e)")
        }
    } catch { check("N5b an oversized library is refused", false, "\(error)") }

    // ============================================================================
    print("\nphase-vector-matching: \(checks) gated checks, \(failures.count) failed")
    if !failures.isEmpty {
        for f in failures { FileHandle.standardError.write("  FAILED: \(f)\n".data(using: .utf8)!) }
        exit(1)
    }
    print("phase-vector-matching: all passed")

  }
}
