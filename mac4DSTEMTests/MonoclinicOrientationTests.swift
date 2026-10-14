//
//  MonoclinicOrientationTests.swift
//  Tier 1 (orientation angles are numbers a scientist reads): beta'' (Mg5Si6, C2/m)
//  orientation maps. Registration: docs/archive/v5/beta-double-prime-orientation-
//  registration-2026-10-14.md (P1-P4); band: .../beta-double-prime-orientation-design-
//  2026-10-14.md (P2: disorientation <= 7.7 deg, >= 95 % of >= 500 draws).
//
//  Frame: py4DSTEM's (`Crystal.latReal`): a along +x, b (the unique axis) along +y when
//  alpha = gamma = 90. Every group fact below is derived from the lattice built here, or from
//  an operator list written in THIS file, never from the production operators alone.
//

import XCTest
import DSTEMCore
import DSTEMSession
import simd
@testable import mac4DSTEM

final class MonoclinicOrientationTests: XCTestCase {

    // MARK: - Fixtures

    /// Andersen et al., Acta Mater. 46 (1998) 3283: C2/m, a = 15.16, b = 4.05, c = 6.74 A, beta = 105.3.
    /// (The same cell as References/crystal-structures/beta_double_prime_Mg5Si6.cif.)
    static let betaDoublePrimeCIF = """
    data_beta_double_prime_Mg5Si6
    _cell_length_a                    15.16
    _cell_length_b                    4.05
    _cell_length_c                    6.74
    _cell_angle_alpha                 90.0
    _cell_angle_beta                  105.3
    _cell_angle_gamma                 90.0
    _symmetry_space_group_name_H-M    'C 2/m'
    _symmetry_Int_Tables_number       12
    loop_
    _symmetry_equiv_pos_as_xyz
      'x,y,z'
      '-x,y,-z'
      '-x,-y,-z'
      'x,-y,z'
      '1/2+x,1/2+y,z'
      '1/2-x,1/2+y,-z'
      '1/2-x,1/2-y,-z'
      '1/2+x,1/2-y,z'
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    _atom_site_occupancy
      Mg1   Mg    0.0000   0.0000   0.0000  1.0
      Mg2   Mg    0.3459   0.0000   0.0890  1.0
      Mg3   Mg    0.4300   0.0000   0.6520  1.0
      Si1   Si    0.0565   0.0000   0.6490  1.0
      Si2   Si    0.1885   0.0000   0.2240  1.0
      Si3   Si    0.2171   0.0000   0.6170  1.0
    """

    private func betaDoublePrimeModel() throws -> CrystalModel {
        try CIFImport.crystalModel(from: Self.betaDoublePrimeCIF, fileBaseName: "bdp")
    }

    /// The operator list is written HERE: C2 about the unique axis b = +y, E.
    private let c2b = simd_double3x3(rows: [[-1, 0, 0], [0, 1, 0], [0, 0, -1]])

    private func angle(_ a: simd_double3x3, _ b: simd_double3x3) -> Double {
        let r = simd_transpose(a) * b
        let cosine = min(1, max(-1, (simd_trace(r) - 1) / 2))
        return acos(cosine)
    }

    private func randomRotation(_ rng: inout MonoclinicRNG) -> simd_double3x3 {
        let q = simd_quatd(ix: rng.gauss(), iy: rng.gauss(), iz: rng.gauss(), r: rng.gauss())
        return simd_double3x3(simd_normalize(q))
    }

    // MARK: - P1: the group closes

    /// Mutation (drop an operator): `operators` of count 1 goes red. Mutation (wrong axis, C2 about x):
    /// the lattice-derived b is no longer fixed and this goes red.
    func testP1GroupHasTwoProperOperatorsClosedAboutTheLatticeB() throws {
        let ops = MonoclinicOrientationSymmetry.operators
        XCTAssertEqual(ops.count, 2)
        let b = simd_normalize(try betaDoublePrimeModel().crystal.latReal[1])
        XCTAssertEqual(simd_length(b - SIMD3(0, 1, 0)), 0, accuracy: 1e-12,
                       "the unique axis of an alpha = gamma = 90 cell is +y in this frame")
        var identityCount = 0
        for s in ops {
            XCTAssertEqual(simd_determinant(s), 1, accuracy: 1e-12)
            XCTAssertLessThan(maxDiff(simd_transpose(s) * s, matrix_identity_double3x3), 1e-12, "orthogonal")
            XCTAssertLessThan(maxDiff(s * s, matrix_identity_double3x3), 1e-12, "S^2 = E")
            if maxDiff(s, matrix_identity_double3x3) < 1e-12 { identityCount += 1 } else {
                XCTAssertLessThan(simd_length(s * b - b), 1e-12, "the 2-fold axis is the lattice b")
                XCTAssertEqual(simd_trace(s), -1, accuracy: 1e-12, "a half turn")
            }
            for t in ops {  // closure
                let product = s * t
                XCTAssertTrue(ops.contains { maxDiff($0, product) < 1e-12 }, "closed")
            }
        }
        XCTAssertEqual(identityCount, 1)
    }

    private func maxDiff(_ a: simd_double3x3, _ b: simd_double3x3) -> Double {
        var m = 0.0
        for c in 0..<3 { for r in 0..<3 { m = max(m, abs(a[c][r] - b[c][r])) } }
        return m
    }

    /// Two matrices related by C2 about b reduce to ONE representative; the reported
    /// disorientation never exceeds 180 deg and 180 is attained (registration: "to be checked").
    /// Mutation (identity-only reduce): the C2-related pair differs and this goes red.
    func testReduceMergesC2RelatedOrientationsAndBoundsTheAngle() {
        var rng = MonoclinicRNG(state: 0x9E3779B97F4A7C15)
        var maxAngle: Float = 0
        for _ in 0..<400 {
            let m = randomRotation(&rng)
            let a = ACOMCrystalSymmetry.monoclinic.reduce(m)
            let b = ACOMCrystalSymmetry.monoclinic.reduce(c2b * m)
            XCTAssertLessThan(maxDiff(a.matrix, b.matrix), 1e-9, "C2-related inputs reduce to one matrix")
            XCTAssertEqual(a.disorientationRad, b.disorientationRad, accuracy: 1e-5)
            XCTAssertLessThanOrEqual(a.disorientationRad, Float.pi + 1e-5)
            maxAngle = max(maxAngle, a.disorientationRad)
        }
        XCTAssertLessThanOrEqual(maxAngle, Float.pi + 1e-5)
        // diag(1,-1,-1) and its C2y image diag(-1,-1,1) are both half turns: 180 deg is attained.
        let half = simd_double3x3(rows: [[1, 0, 0], [0, -1, 0], [0, 0, -1]])
        XCTAssertEqual(ACOMCrystalSymmetry.monoclinic.reduce(half).disorientationRad, Float.pi, accuracy: 1e-5)
        // And the reduction really is a reduction: a small rotation about b is left alone, its C2 image is not.
        let small = rotation(about: [0, 1, 0], by: 0.1)
        XCTAssertEqual(ACOMCrystalSymmetry.monoclinic.reduce(c2b * small).disorientationRad, 0.1, accuracy: 1e-5)
    }

    private func rotation(about axis: SIMD3<Double>, by theta: Double) -> simd_double3x3 {
        simd_double3x3(simd_quatd(angle: theta, axis: simd_normalize(axis)))
    }

    // MARK: - P3: the 12 Al variants

    /// beta'' needles run along Al <001> with b parallel to the needle (LITERATURE CONVENTION,
    /// Andersen et al. 1998; not derived here). Only b || [001]Al enters the count; the in-plane
    /// direction (a || [320]Al here) is an example, not a claim. Variants are the cubic images of one
    /// orientation: V_g = R g, g in the 24 proper cubic operators (written here).
    /// Mutations: drop C2 (24 distinct), C2 about x (24 distinct): both go red.
    func testP3TwelveAlVariantsAreDistinctUnder2mAndOneCubicOrbit() {
        // R maps Al coordinates to beta'' Cartesian: rows are the Al images of the beta'' axes.
        let aAl = simd_normalize(SIMD3<Double>(3, 2, 0)), bAl = SIMD3<Double>(0, 0, 1)
        let cAl = simd_cross(aAl, bAl)   // x cross y = z, right-handed
        let r = simd_double3x3(rows: [[aAl.x, aAl.y, aAl.z], [bAl.x, bAl.y, bAl.z], [cAl.x, cAl.y, cAl.z]])
        let cubic = Self.cubicProperGroup()
        XCTAssertEqual(cubic.count, 24)
        var reducedKeys = Set<String>()
        var reducedMatrices: [simd_double3x3] = []
        for g in cubic {
            let variant = r * g
            let reduced = ACOMCrystalSymmetry.monoclinic.reduce(variant).matrix
            if reducedKeys.insert(Self.key(reduced)).inserted { reducedMatrices.append(reduced) }
        }
        XCTAssertEqual(reducedMatrices.count, 12, "24 / |stabiliser| = 24 / 2 distinct variants")
        // One orbit: every representative is some cubic image of the first, up to 2/m.
        let first = reducedMatrices[0]
        for m in reducedMatrices {
            let related = cubic.contains { g in
                Self.key(ACOMCrystalSymmetry.monoclinic.reduce(first * g).matrix) == Self.key(m)
            }
            XCTAssertTrue(related, "a variant outside the cubic orbit")
        }
        // The contrast: unreduced, all 24 cubic images are distinct matrices.
        XCTAssertEqual(Set(cubic.map { Self.key(ACOMCrystalSymmetry.identity.reduce(r * $0).matrix) }).count, 24)
    }

    static func key(_ m: simd_double3x3) -> String {
        var s = ""
        for c in 0..<3 { for r in 0..<3 { s += String(format: "%.6f,", (m[c][r] * 1e6).rounded() / 1e6 + 0.0) } }
        return s.replacingOccurrences(of: "-0.000000", with: "0.000000")
    }

    static func cubicProperGroup() -> [simd_double3x3] {
        var result: [simd_double3x3] = []
        for p in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
                let signs = [x, y, z]
                var rows = [[Double]](repeating: [0, 0, 0], count: 3)
                for i in 0..<3 { rows[i][p[i]] = signs[i] }
                let m = simd_double3x3(rows: rows)
                if simd_determinant(m) > 0.5 { result.append(m) }
            } } }
        }
        return result
    }

    // MARK: - Zone, key

    /// The direction reduction is the 2/m fold: y >= 0, azimuth about b in [0, 180).
    /// Mutation (drop the C2 fold): n and C2 n differ and this goes red.
    func testDirectionFoldIsInvariantUnderTheLaueGroupAndLandsInTheQuarterSphere() {
        var rng = MonoclinicRNG(state: 0xD1B54A32D192ED03)
        let mirror = simd_double3x3(rows: [[1, 0, 0], [0, -1, 0], [0, 0, 1]])
        for _ in 0..<300 {
            let n = simd_normalize(SIMD3(rng.gauss(), rng.gauss(), rng.gauss()))
            let folded = MonoclinicOrientationSymmetry.reduceDirection(n)
            XCTAssertGreaterThanOrEqual(folded.y, -1e-12)
            let azimuth = atan2(folded.z, folded.x)
            XCTAssertGreaterThanOrEqual(azimuth, -1e-12)
            XCTAssertLessThan(azimuth, Double.pi + 1e-12)
            for image in [-n, c2b * n, mirror * n, -(c2b * n)] {
                XCTAssertLessThan(simd_length(MonoclinicOrientationSymmetry.reduceDirection(image) - folded), 1e-9)
            }
        }
        // The zone sampler returns exactly `count` points, all inside the zone and distinct.
        for count in [3, 12, 96, 200] {
            let zone = MonoclinicOrientationSymmetry.sampleFundamentalZone(count: count)
            XCTAssertEqual(zone.count, count)
            for p in zone {
                XCTAssertEqual(simd_length(p), 1, accuracy: 1e-12)
                XCTAssertLessThan(simd_length(MonoclinicOrientationSymmetry.reduceDirection(p) - p), 1e-9, "inside the zone")
            }
        }
    }

    /// IPF key: b red, +x (a) green, +z blue; invariant under the group; no seam at 0 / 180.
    func testIPFKeyCornersInvarianceAndNoSeam() {
        let key = MonoclinicOrientationSymmetry.ipfColor(direction:)
        XCTAssertLessThan(simd_length(key([0, 1, 0]) - SIMD3(1, 0, 0)), 1e-6)
        XCTAssertLessThan(simd_length(key([1, 0, 0]) - SIMD3(0, 1, 0)), 1e-6)
        XCTAssertLessThan(simd_length(key([0, 0, 1]) - SIMD3(0, 0, 1)), 1e-6)
        XCTAssertLessThan(simd_length(key([-1, 0, 0]) - key([1, 0, 0])), 1e-6, "no seam across the 180 deg azimuth")
        let tilted = SIMD3<Double>(0.5, 0.6, 0.3)
        XCTAssertLessThan(simd_length(key(tilted) - key(c2b * tilted)), 1e-6)
        XCTAssertLessThan(simd_length(key(tilted) - key(-tilted)), 1e-6)
        XCTAssertLessThan(simd_length(key(SIMD3(0.7, 0.3, -0.2)) - key(SIMD3(-0.7, 0.3, 0.2))), 1e-6)
        XCTAssertEqual(ACOMCrystalSymmetry.monoclinic.displayName, "Monoclinic 2/m")
    }

    // MARK: - CrystalModel and CIFImport

    func testModelValidationByCellMetric() throws {
        func model(alpha: Double, beta: Double, gamma: Double) -> CrystalModel {
            CrystalModel(id: "t", displayName: "t",
                         crystal: Crystal(a: 15.16, b: 4.05, c: 6.74, alphaDeg: alpha, betaDeg: beta, gammaDeg: gamma,
                                          sites: [AtomSite(z: 12, fractional: SIMD3(0, 0, 0))]),
                         symmetry: .monoclinic, source: .imported)
        }
        XCTAssertTrue(model(alpha: 90, beta: 105.3, gamma: 90).isUsable)
        XCTAssertTrue(model(alpha: 90, beta: 105.3, gamma: 90).supportsOrientationMapping)
        XCTAssertTrue(model(alpha: 90, beta: 90, gamma: 90).validationIssues.contains { $0.code == "monoclinic_symmetry_mismatch" },
                      "beta = 90 is orthorhombic, not monoclinic")
        XCTAssertTrue(model(alpha: 89, beta: 105.3, gamma: 90).validationIssues.contains { $0.code == "monoclinic_symmetry_mismatch" })
        XCTAssertTrue(model(alpha: 90, beta: 105.3, gamma: 91).validationIssues.contains { $0.code == "monoclinic_symmetry_mismatch" })
    }

    func testCIFOfACenteredC2mCellImportsAsMonoclinicAndMapsOrientations() throws {
        let model = try betaDoublePrimeModel()
        XCTAssertEqual(model.symmetry, .monoclinic)
        XCTAssertTrue(model.isUsable)
        XCTAssertTrue(model.supportsOrientationMapping)
        XCTAssertNil(model.orientationMappingIssue)
    }

    /// A monoclinic METRIC with sites that have neither a 2-fold along b nor a mirror
    /// perpendicular to it (Laue class -1 at best) must not be called 2/m: it stays Unreduced.
    func testMonoclinicMetricWithoutTheSymmetryStaysUnreduced() throws {
        let cif = """
        data_p1
        _cell_length_a 6.0
        _cell_length_b 4.0
        _cell_length_c 5.0
        _cell_angle_alpha 90
        _cell_angle_beta 100
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Al1 Al 0.0 0.0 0.0
        O1 O 0.3 0.2 0.4
        """
        XCTAssertEqual(try CIFImport.crystalModel(from: cif, fileBaseName: "p1").symmetry, .identity)
    }

    // MARK: - P2 / P4: round trip through the matcher

    private func monoclinicPlan(count: Int) throws -> (plan: OrientationPlan, crystal: Crystal) {
        let crystal = try betaDoublePrimeModel().crystal
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: crystal, kMax: 1.2, zoneAxisCount: count, symmetry: .monoclinic, wavelengthAngstrom: 0.02508))
        return (plan, crystal)
    }

    /// Peaks of a kinematic pattern for the lab frame (f1, f2, n) in crystal coordinates, built here
    /// (never with production `project`), as in tools/acom-mirror-test.
    private func peaks(crystal: Crystal, truth: simd_double3x3, reflections: [Reflection]) -> [BraggPeak] {
        let f1 = truth.columns.0, f2 = truth.columns.1, n = truth.columns.2
        let scale = 0.008, origin = 256.0, curvature = 0.02508 / 2
        return reflections.compactMap { r in
            let sg = simd_dot(r.g, n) + curvature * simd_length_squared(r.g)
            let intensity = r.intensity * exp(-pow(sg / 0.03, 2))
            guard abs(sg) <= 0.1 && intensity > 0 else { return nil }
            return BraggPeak(x: Float(origin + simd_dot(r.g, f1) / scale),
                             y: Float(origin + simd_dot(r.g, f2) / scale), intensity: Float(intensity))
        }
    }

    private func truthMatrix(axis: SIMD3<Double>, inPlaneDeg: Double) -> simd_double3x3 {
        let n = simd_normalize(axis)
        let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0, 0, 1] : [1, 0, 0]
        let f0 = simd_normalize(seed - simd_dot(seed, n) * n)
        let a = inPlaneDeg * .pi / 180
        let f1 = simd_normalize(f0 * cos(a) + simd_cross(n, f0) * sin(a))
        return simd_double3x3(columns: (f1, simd_cross(n, f1), n))
    }

    /// Disorientation to truth under the independent 2/m list {E, C2 about +y}.
    private func disorientationDeg(_ recovered: simd_double3x3, _ truth: simd_double3x3) -> Double {
        min(angle(recovered, truth), angle(c2b * recovered, truth)) * 180 / .pi
    }

    /// P4. The pattern of R and of C2*R is the same pattern (C2 about b is a symmetry of the crystal):
    /// unreduced, the recovered matrix is 180 deg from one of the two truths; reduced by 2/m,
    /// both truths and the recovered matrix are one orientation.
    /// Mutation (reduce = identity): the plain angle to one truth stays ~180 deg and this goes red.
    func testP4TheC2AmbiguityIsMergedByMonoclinicAndNotByIdentity() throws {
        let (plan, crystal) = try monoclinicPlan(count: 200)
        let reflections = crystal.reflections(kMax: 1.2)
        let matcher = try XCTUnwrap(OrientationMatcher(plan: plan, symmetry: .monoclinic))
        let unreduced = try XCTUnwrap(OrientationMatcher(plan: plan, symmetry: .identity))
        let axes: [SIMD3<Double>] = [[0.3, 0.8, 0.5], [-0.6, 0.5, 0.62], [0.2, 0.3, -0.93], [0.9, 0.2, 0.4]]
        var worstPlain = 0.0
        for (index, axis) in axes.enumerated() {
            let truth = truthMatrix(axis: axis, inPlaneDeg: 17.3 + 40 * Double(index))
            let image = c2b * truth
            for t in [truth, image] {
                let p = peaks(crystal: crystal, truth: t, reflections: reflections)
                let reduced = matcher.match(peaks: p, originX: 256, originY: 256, invAngstromPerPixel: 0.008)
                let raw = unreduced.match(peaks: p, originX: 256, originY: 256, invAngstromPerPixel: 0.008)
                // Reduced: the recovered orientation is within the band of BOTH C2-related truths.
                let r = reduced.euler.py4DSTEMOrientationMatrix
                XCTAssertLessThan(angle(ACOMCrystalSymmetry.monoclinic.reduce(r).matrix,
                                        ACOMCrystalSymmetry.monoclinic.reduce(truth).matrix) * 180 / .pi, 10,
                                  "axis \(axis)")
                worstPlain = max(worstPlain, angle(raw.euler.py4DSTEMOrientationMatrix, truth) * 180 / .pi,
                                 angle(raw.euler.py4DSTEMOrientationMatrix, image) * 180 / .pi)
            }
        }
        XCTAssertGreaterThan(worstPlain, 150, "unreduced, the recovered matrix is a half turn from one truth")
    }

    /// P2 (band set in the design note before this ran): disorientation to truth <= 7.7 deg for >= 95 %
    /// of 600 draws; random directions over the whole sphere, random in-plane angles, fixed seed.
    func testP2RoundTripRecoversRandomOrientationsWithinTheLibraryStep() throws {
        let (plan, crystal) = try monoclinicPlan(count: 200)
        let reflections = crystal.reflections(kMax: 1.2)
        let matcher = try XCTUnwrap(OrientationMatcher(plan: plan, symmetry: .monoclinic))
        var rng = MonoclinicRNG(state: 0x2545F4914F6CDD1D)
        var errors: [Double] = []
        while errors.count < 600 {
            let v = SIMD3(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
            let length = simd_length(v)
            guard length > 0.2 && length <= 1 else { continue }
            let truth = truthMatrix(axis: v / length, inPlaneDeg: rng.uniform(0, 360))
            let p = peaks(crystal: crystal, truth: truth, reflections: reflections)
            guard p.count >= 3 else { continue }
            let result = matcher.match(peaks: p, originX: 256, originY: 256, invAngstromPerPixel: 0.008)
            XCTAssertGreaterThanOrEqual(result.templateIndex, 0)
            errors.append(disorientationDeg(result.euler.py4DSTEMOrientationMatrix, truth))
        }
        let sorted = errors.sorted()
        let within = Double(errors.filter { $0 <= 7.7 }.count) / Double(errors.count)
        print(String(format: "MEASURE: beta'' round trip n=%d median %.2f p90 %.2f p95 %.2f max %.2f deg; within 7.7 deg %.3f; within 4.5 deg %.3f",
                     errors.count, sorted[errors.count / 2], sorted[Int(Double(errors.count) * 0.9)],
                     sorted[Int(Double(errors.count) * 0.95)], sorted.last!, within,
                     Double(errors.filter { $0 <= 4.5 }.count) / Double(errors.count)))
        XCTAssertGreaterThanOrEqual(within, 0.95)
    }
}

/// Deterministic generator local to this file.
struct MonoclinicRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { Double.random(in: lo...hi, using: &self) }
    mutating func gauss() -> Double {
        let u1 = max(1e-12, uniform(0, 1)), u2 = uniform(0, 1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

private extension simd_double3x3 {
    init(rows: [[Double]]) {
        self.init(columns: (SIMD3(rows[0][0], rows[1][0], rows[2][0]),
                            SIMD3(rows[0][1], rows[1][1], rows[2][1]),
                            SIMD3(rows[0][2], rows[1][2], rows[2][2])))
    }
}
