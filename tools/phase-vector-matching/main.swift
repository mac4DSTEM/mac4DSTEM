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
//   • Part B generates synthetic patterns from a projection written in this
//     file (`harnessProject`) straight off `Crystal`, never through
//     `PhaseReferenceLibrary`, and Part A asserts the two agree.
//
//     **HOW FAR THAT INDEPENDENCE GOES.** Selection, scaling AND — since
//     2026-09-14 — the in-plane frame: `harnessFrame` builds its own
//     right-handed pair about the beam from a seed, the way
//     `tools/acom-convention-test` does, and Part B's peaks never pass
//     through `ACOMOrientation.detectorBasis`. Until then both sides shared
//     that call, so a handedness flip there (e2 = cross(e1, n) for
//     cross(n, e1)) mirrored both together and all 27 checks stayed green —
//     the L3 trap, measured by Gate B 2026-09-12. Now the harness frame is
//     a pure rotation of the production frame ONLY if production is
//     right-handed; β″ [010] is an oblique (chiral) net, so under the flip
//     A4 cannot find one rotation that maps every pair and P2 collapses.
//     Measured 2026-09-14 under exactly that mutation: A4 and P2 both red.
//     Which handedness is PHYSICALLY right is still acom-convention-test's
//     question, pinned against py4DSTEM; this gate pins that phase mapping
//     shares ACOM's answer rather than mirroring it.
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
/// in-plane components are `g` projected on an orthonormal pair spanning the
/// plane ⊥ n — `harnessFrame`'s pair, built here and NOT the production
/// `detectorBasis`, so the two frames agree only up to a rotation about n
/// and only if both have the same handedness (file header).
func harnessBeam(_ crystal: Crystal, zone uvw: SIMD3<Int>) -> SIMD3<Double> {
    let r = Double(uvw.x) * crystal.latReal[0]
        + Double(uvw.y) * crystal.latReal[1]
        + Double(uvw.z) * crystal.latReal[2]
    return r / simd_length(r)
}

/// A right-handed (f1, f2, n) with a seed that differs from production's on
/// purpose: the same construction as `tools/acom-convention-test`.
func harnessFrame(_ n: SIMD3<Double>) -> (f1: SIMD3<Double>, f2: SIMD3<Double>) {
    let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0, 0, 1] : [1, 0, 0]
    let f1 = simd_normalize(seed - simd_dot(seed, n) * n)
    return (f1, simd_cross(n, f1))
}

/// The in-plane angle of the harness frame's f1 as PRODUCTION's frame sees
/// it, degrees. A plant at θ in the harness frame is θ − this in production's,
/// which is what a fitted in-plane rotation must be compared against.
func frameOffsetDeg(_ n: SIMD3<Double>) -> Double {
    let e = ACOMOrientation.detectorBasis(zoneAxis: n)
    let f1 = harnessFrame(n).f1
    return atan2(simd_dot(f1, e.columns.1), simd_dot(f1, e.columns.0)) * 180 / .pi
}

func harnessProject(_ crystal: Crystal, zone uvw: SIMD3<Int>, kMax: Double,
                    sgMax: Double) -> [(h: Int, k: Int, l: Int, q: SIMD2<Double>, weight: Double)] {
    let n = harnessBeam(crystal, zone: uvw)
    let frame = harnessFrame(n)
    var out: [(h: Int, k: Int, l: Int, q: SIMD2<Double>, weight: Double)] = []
    for refl in crystal.reflections(kMax: kMax) {
        let sg = simd_dot(refl.g, n)
        if abs(sg) > sgMax { continue }
        let q = SIMD2(simd_dot(refl.g, frame.f1), simd_dot(refl.g, frame.f2))
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

    // The SHIPPED library defaults except the two the synthetic detector
    // fixes (kMax and the slab). Gate B finding 8 (2026-09-12): the first
    // version also overrode `minimumIntensityFraction` to 0.02 against a
    // shipped 0.05, so the gate never ran the value the app uses.
    var settings = PhaseReferenceSettings()
    settings.kMaxInvAngstrom = kMax
    settings.excitationSlabInvAngstrom = sgMax
    settings.inPlaneStepDeg = 2
    // The LITERALS are the pin, not a comparison against the defaults — the
    // first version of this check compared `settings.x` to
    // `PhaseReferenceSettings().x`, which is the same value on both sides and
    // could not fail for any default. Moving either number is then a
    // deliberate edit to this line, which is the point.
    check("A0 the library runs the shipped visibility cut and density cap",
          settings.minimumIntensityFraction == 0.05 && settings.maximumVectorsPerEntry == 48,
          String(format: "min intensity %.3f (shipped 0.050), cap %d (shipped 48)",
                 settings.minimumIntensityFraction, settings.maximumVectorsPerEntry))

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

    // A1e/A2c — THE EXTINCTION CONDITIONS, whose ground truth is the space
    // group and not this code. Gate B finding 1 (2026-09-12): changing β″'s
    // C-centring translation from (½,½,0) to (½,½,½) left all 22 atoms, both
    // element counts, every cell parameter, the shortest interatomic contact
    // (2.2700 Å, unchanged, because the shortest pair is in-layer) and all 21
    // gated checks passing — while changing the reflection condition from
    // h + k even to h + k + l even, which is a different lattice and half of
    // β″'s reference vectors. Nothing pinned it, because every other check
    // reads the CELL and this reads where the atoms sit in it.
    let betaAll = beta.reflections(kMax: kMax)
    check("A2c β″ obeys the C-centring condition h + k even",
          !betaAll.isEmpty && betaAll.allSatisfy { ($0.h + $0.k) % 2 == 0 },
          "\(betaAll.count) reflections, "
          + "\(betaAll.filter { ($0.h + $0.k) % 2 != 0 }.count) with h + k odd "
          + "(C2/m, No. 12); an I- or A-centred cell would fail here")
    let alAll = al.reflections(kMax: kMax)
    check("A1e fcc obeys h, k, l all even or all odd",
          !alAll.isEmpty && alAll.allSatisfy {
              let parity = [$0.h % 2 != 0, $0.k % 2 != 0, $0.l % 2 != 0]
              return parity.allSatisfy { $0 } || parity.allSatisfy { !$0 }
          },
          "\(alAll.count) reflections, none of mixed parity")

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

    // A4 — the library's projection agrees with the independent one written above,
    // up to ONE rotation about the beam per zone — the rotation between the two
    // frames, taken from the outermost shared reflection and then required of
    // every other. A mirrored production frame has no such rotation on the
    // oblique β″ [010] net, which is what makes this the handedness check.
    // This is what stops Part B from testing the code against itself.
    var worstParity = 0.0
    var parityPairs = 0
    for (crystal, zone) in [(al, SIMD3(0, 0, 1)), (beta, SIMD3(0, 1, 0)), (beta, SIMD3(0, 0, 1))] {
        let mine = harnessProject(crystal, zone: zone, kMax: kMax, sgMax: sgMax)
        let theirs = PhaseReferenceLibrary.projectedVectors(
            reflections: crystal.reflections(kMax: kMax), crystal: crystal,
            zoneAxis: zone, settings: settings)
        var pairs: [(SIMD2<Double>, SIMD2<Double>)] = []
        for t in theirs {
            guard let m = mine.first(where: { $0.h == t.h && $0.k == t.k && $0.l == t.l }) else {
                worstParity = .infinity; continue
            }
            pairs.append((m.q, t.q))
        }
        guard let anchor = pairs.max(by: { simd_length($0.1) < simd_length($1.1) }) else {
            worstParity = .infinity; continue
        }
        let phi = atan2(anchor.0.y, anchor.0.x) - atan2(anchor.1.y, anchor.1.x)
        for (m, t) in pairs {
            worstParity = max(worstParity, simd_distance(m, rotated(t, phi)))
            parityPairs += 1
        }
    }
    check("A4 library projection == the harness's independent projection, up to one rotation per zone",
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
    // The plant is 13.7° in the HARNESS frame; production's frame differs by a
    // rotation about the beam, so the angle a production entry should carry
    // is 13.7° − that offset. (The vector-set checks below need no such
    // conversion: both sets are detector positions.)
    let plantedInProductionDeg = 13.7 - frameOffsetDeg(harnessBeam(al, zone: SIMD3(0, 0, 1)))
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
    // outermost |q| here (√20/a = 1.104 Å⁻¹) is 0.0058 Å⁻¹ — the number the
    // check itself prints. An earlier version of this comment said ~0.004,
    // understating its own measurement by 45 % (Gate B, 2026-09-12). 0.01
    // admits it and nothing else.
    check("P5a the fitted matrix entry reproduces the planted vector set",
          plantedDistance < 0.01,
          String(format: "worst nearest-neighbour %.5f Å⁻¹; fitted angle %.1f°, planted 13.7° "
                 + "= %.1f° in production's frame (equal modulo the 4-fold projected symmetry: %.1f°)",
                 plantedDistance, fittedRotation, plantedInProductionDeg,
                 (fittedRotation - plantedInProductionDeg).truncatingRemainder(dividingBy: 90)))
    let flipped = harnessProject(al, zone: SIMD3(0, 0, 1), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, -plantedMatrixRotation) }
    let flippedDistance = setDistance(flipped)
    // Gate B finding 11: the modulo line was PRINTED and not asserted, so a
    // transposed rotation printed 62.3° instead of 0.3° and still passed.
    var modulo = abs((fittedRotation - plantedInProductionDeg).truncatingRemainder(dividingBy: 90))
    modulo = min(modulo, 90 - modulo)
    check("P5c and the angle reconciles modulo the projected symmetry",
          modulo <= settings.inPlaneStepDeg,
          String(format: "%.1f° residual against a %.1f° step", modulo, settings.inPlaneStepDeg))
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
                directBeamRadiusInvAngstrom: s.directBeamRadiusInvAngstrom,
                maximumVectorInvAngstrom: s.maximumVectorInvAngstrom)
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
    // The contrast must be POSITIVE, not merely non-zero. Gate B finding 4
    // (2026-09-12): ranking phases by matched count instead of by distance
    // leaves P6 green and makes the reported contrast NEGATIVE (−0.00045 Å⁻¹
    // at σ = 2 px) — the winner then has a WORSE mean distance than the
    // runner-up, and the number shown to the user means nothing.
    check("P6b the reported contrast over the runner-up is positive",
          clean.meanContrast > 0,
          String(format: "%+.5f Å⁻¹ — a negative contrast means the winner scored "
                 + "worse than the phase it beat", clean.meanContrast))
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
    // Both halves together, and the reason is that they are NOT independent:
    // at the shipped cap of 48, `minimumIntensityFraction` changes nothing
    // between 0 and 0.05 on this fixture — the cap removes more than the
    // intensity cut does (Gate B finding 8, 2026-09-12). The intensity cut
    // starts to matter only when the cap is off, which is what this measures.
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
    // M3 — TWO measurements, not one, and the first version conflated them.
    // Gate B finding 2 (2026-09-12) measured that removing the chance guard
    // ALONE changes nothing at any multiple from 0 to 12: the 99.2 % → 5.5 %
    // collapse the docs credited to it is entirely the matched-vector floor.
    // At the shipped settings the guard's bar is ~0.9 matched vectors against
    // a floor of 3, so it binds only above ~31 surviving vectors per pattern
    // — and the repo's own real cube has a median of 7. Printing them apart is
    // what stops the wrong one being credited again.
    for (label, mutate) in [
        ("chance guard alone", { (s: inout PhaseVectorSettings) in s.chanceMatchMultiple = 0 }),
        ("matched-vector floor alone", { (s: inout PhaseVectorSettings) in s.minimumMatchedVectors = 1 }),
        ("both", { (s: inout PhaseVectorSettings) in
            s.chanceMatchMultiple = 0; s.minimumMatchedVectors = 1 }),
    ] {
        var relaxed = matchSettings
        mutate(&relaxed)
        guard let m = PhaseVectorMatcher.map(bragg: bragg, library: library, settings: relaxed,
                                             originX: originX, originY: originY,
                                             invAngstromPerPixel: invAngstromPerPixel)
        else { continue }
        let d = accuracy(m)
        measure("M3 \(label) removed",
                String(format: "matrix %.1f %%, β″ %.1f %%, random %.1f %% (baseline %.1f / %.1f / %.1f)",
                       100 * d.matrix, 100 * d.beta, 100 * d.random,
                       100 * acc.matrix, 100 * acc.beta, 100 * acc.random))
    }
    // And the binding condition itself, which is the thing worth knowing.
    let shippedEntry = library.entries[library.candidateEntryIndices[0]]
    let perVector = shippedEntry.chanceMatchFraction(
        pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: kMax)
    measure("M3b when the chance guard starts to bind",
            String(format: "%.1f surviving vectors — below that the %d-vector floor is "
                   + "the binding constraint, not the guard",
                   Double(matchSettings.minimumMatchedVectors)
                   / (matchSettings.chanceMatchMultiple * perVector),
                   matchSettings.minimumMatchedVectors))

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

    // P8b — CLOSEST, not merely inside the radius. Gate B finding 11
    // (2026-09-12): returning the FIRST reference within the radius instead of
    // the nearest passed all 60 000 probes above, because no two references in
    // either shipped library lie within one pair DIAMETER — β″'s h0l spacing
    // is 0.137 Å⁻¹ against 2ρ = 0.04 — so the two rules coincide on that
    // fixture. They diverge for a long-axis cell, where a* falls below ρ. This
    // fixture is that case, built deliberately.
    let crowded = (0..<5).map {
        ReferenceVector(h: $0, k: 0, l: 0, q: SIMD2(0.5 + Double($0) * 0.008, 0),
                        length: 0.5 + Double($0) * 0.008, relativeIntensity: 1)
    }
    var closestWins = true
    for step in 0...40 {
        let u = SIMD2(0.49 + Double(step) * 0.0015, 0.0)
        guard let hit = PhaseVectorMatcher.nearest(u, in: crowded, radius: 0.02),
              let truth = bruteNearest(u, crowded, 0.02) else { continue }
        if hit.index != truth.index || abs(hit.distance - truth.distance) > 1e-15 {
            closestWins = false
        }
    }
    check("P8b and it returns the CLOSEST reference, not the first in range",
          closestWins,
          "5 references 0.008 Å⁻¹ apart inside a 0.02 Å⁻¹ radius — "
          + "first-in-range and nearest differ here and agree in the shipped libraries")

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
    print("\n== Part E — the matrix challenges a candidate label (2026-09-14)")
    // ============================================================================
    //
    // WHY THIS PART EXISTS. The challenge shipped with a DEFAULT-EMPTY
    // `matrixChallenge:` argument, and this harness — the gate for the
    // matcher's invariants — called `classify` without it. Gate B caught that
    // every number in Part B measured the OLD path while the new one was
    // gated by nothing at all. Vectors here come from `harnessProject`, the
    // harness's own projection, never from the library under test.

    // β″ on [001], NOT the [010] Part B plants: [001] is the entry that shares
    // a sublattice with Al ⟨110⟩ and therefore the one that produced the false
    // label. A library with the wrong candidate cannot reproduce the defect,
    // and a check that cannot reproduce the defect proves nothing.
    var challengeSettings = settings
    challengeSettings.inPlaneStepDeg = 2
    let challengeLibrary = try PhaseReferenceLibrary.build(phases: [
        PhaseDefinition(id: "al", displayName: "Al", crystal: al,
                        role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
        PhaseDefinition(id: "beta001", displayName: "β″[001]", crystal: beta,
                        role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
    ], settings: challengeSettings)
    let challengeBases = PhaseVectorMatcher.matrixChallengeBases(library: challengeLibrary)
    check("C0 the challenge pool covers the low-index directions",
          challengeBases.count >= 40,
          "\(challengeBases.count) matrix orientations for \(PhaseReferenceLibrary.lowIndexZoneAxes.count) axes")

    // A SECOND MATRIX GRAIN: the matrix crystal on a zone axis the user did
    // not name, at a rotation that is not a multiple of the library step.
    let secondGrain = harnessProject(al, zone: SIMD3(0, 1, 1), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, 41.3 * Double.pi / 180) }
    let challengeScratch = PhaseVectorMatcher.Scratch(
        capacity: max(challengeBases.map(\.vectors.count).max() ?? 1,
                      challengeLibrary.entries.map(\.vectors.count).max() ?? 1))
    func verdict(_ vectors: [SIMD2<Double>], challenged: Bool) -> PhaseVerdict {
        PhaseVectorMatcher.classify(
            vectors: vectors, library: challengeLibrary, settings: matchSettings,
            matrixEntry: nil,
            candidateEntryIndices: challengeLibrary.candidateEntryIndices,
            scratch: challengeScratch,
            matrixChallenge: challenged ? challengeBases : []).verdict
    }
    check("C1a without the challenge a second matrix grain IS mislabelled (the defect)",
          verdict(secondGrain, challenged: false) == .indexed,
          "verdict \(verdict(secondGrain, challenged: false))")
    check("C1b with it, the matrix takes the position back",
          verdict(secondGrain, challenged: true) == .matrix,
          "verdict \(verdict(secondGrain, challenged: true))")

    // AND IT MUST SURVIVE SPURIOUS PEAKS FARTHER OUT THAN ANY REFLECTION.
    // The first implementation seeded its rotations on the three LONGEST
    // vectors; three spurious maxima beyond the outermost real one took the
    // catch rate from 100 % to 0 % (Gate B, 2026-09-14).
    var spurious = secondGrain
    let beyond = (secondGrain.map { simd_length($0) }.max() ?? 0.5) * 1.35
    for i in 0..<3 {
        let a = Double(i) * 2.0
        spurious.append(SIMD2(beyond * cos(a), beyond * sin(a)))
    }
    check("C2 spurious peaks beyond every reflection do not blind the challenge",
          verdict(spurious, challenged: true) == .matrix,
          "verdict \(verdict(spurious, challenged: true)) with 3 peaks at \(String(format: "%.3f", beyond)) Å⁻¹")

    // AND IT MUST NOT ERASE A SPARSE PRECIPITATE. Jittered, because an exact
    // plant makes the winner's distance 0 and the comparison vacuous — Gate B
    // caught the first version of this check that way. The jitter is Gaussian
    // at 0.004 Å⁻¹, a third of a detector pixel on the demo cube and inside
    // the pair radius's own stated measurement budget; at that jitter, with
    // "at least as many" instead of "strictly more", 26.5 % of three-vector
    // precipitates were taken by the matrix.
    let betaOnOhOne = harnessProject(beta, zone: SIMD3(0, 0, 1), kMax: kMax, sgMax: sgMax)
        .map { rotated($0.q, 37.2 * Double.pi / 180) }
    var jitterRng = Rng()
    var stolen = 0, trials = 0
    for count in [3, 3, 4, 5, 6] {
        for _ in 0..<100 {
            let planted = betaOnOhOne.prefix(count).map { q -> SIMD2<Double> in
                q + SIMD2(jitterRng.gaussian() * 0.004, jitterRng.gaussian() * 0.004)
            }
            trials += 1
            if verdict(Array(planted), challenged: true) == .matrix { stolen += 1 }
        }
    }
    check("C3 a sparse jittered precipitate is never taken by the matrix",
          stolen == 0,
          "\(stolen) of \(trials) three-to-six-vector precipitates relabelled")

    // ============================================================================
    print("\nphase-vector-matching: \(checks) gated checks, \(failures.count) failed")
    if !failures.isEmpty {
        for f in failures { FileHandle.standardError.write("  FAILED: \(f)\n".data(using: .utf8)!) }
        exit(1)
    }
    print("phase-vector-matching: all passed")

  }
}
