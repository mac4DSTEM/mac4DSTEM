//
//  MonoclinicOrientationTests.swift
//  Tier 1 (orientation angles are numbers a scientist reads): beta'' (Mg5Si6, C2/m)
//  orientation maps. Registration: archived docs/archive/v5/beta-double-prime-orientation-
//  registration-2026-10-14.md (P1-P4); band: .../beta-double-prime-orientation-design-
//  2026-10-14.md (P2: disorientation <= 7.7 deg, >= 95 % of >= 500 draws).
//
//  Frame: py4DSTEM's (`Crystal.latReal`): a along +x, b (the unique axis) along +y when
//  alpha = gamma = 90. Every group fact below is derived from the lattice built here, or from
//  an operator list written in THIS file, never from the production operators alone.
//

import XCTest
import DiffractoCore
import DiffractoScattering
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
import simd
@testable import mac4DSTEM

final class MonoclinicOrientationTests: XCTestCase {

    /// The kit's 2/m symmetry: the group, the fold and (through `ACOMCrystalSymmetry.monoclinic`) the sampler and key.
    private let monoclinicKit = CrystalOrientationSymmetry(laueClass: .twoOverM)

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
        try CIFModelImport.crystalModel(from: Self.betaDoublePrimeCIF, fileBaseName: "bdp")
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
        let ops = monoclinicKit.operators
        XCTAssertEqual(ops.count, 2)
        let b = simd_normalize(try betaDoublePrimeModel().structure.cell.realLattice[1])
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
            let folded = try! monoclinicKit.reduceDirection(n)
            XCTAssertGreaterThanOrEqual(folded.y, -1e-12)
            let azimuth = atan2(folded.z, folded.x)
            XCTAssertGreaterThanOrEqual(azimuth, -1e-12)
            XCTAssertLessThan(azimuth, Double.pi + 1e-12)
            for image in [-n, c2b * n, mirror * n, -(c2b * n)] {
                XCTAssertLessThan(simd_length(try! monoclinicKit.reduceDirection(image) - folded), 1e-9)
            }
        }
        // The zone sampler returns exactly `count` points, all inside the zone and distinct.
        for count in [3, 12, 96, 200] {
            let zone = ACOMCrystalSymmetry.monoclinic.sampleFundamentalZone(count: count)
            XCTAssertEqual(zone.count, count)
            for p in zone {
                XCTAssertEqual(simd_length(p), 1, accuracy: 1e-12)
                XCTAssertLessThan(simd_length(try! monoclinicKit.reduceDirection(p) - p), 1e-9, "inside the zone")
            }
        }
    }

    /// IPF key (HSV disk: hue 120 deg + 2 phi, saturation = polar angle / 90 deg, value 1): b is
    /// white, +x (a) green, phi = 60 deg blue; invariant under the group; no seam at 0 / 180.
    func testIPFKeyCornersInvarianceAndNoSeam() {
        let key = ACOMCrystalSymmetry.monoclinic.ipfColor(direction:)
        XCTAssertLessThan(simd_length(key([0, 1, 0]) - SIMD3(1, 1, 1)), 1e-6)
        XCTAssertLessThan(simd_length(key([1, 0, 0]) - SIMD3(0, 1, 0)), 1e-6)
        XCTAssertLessThan(simd_length(key([-1, 0, 0]) - key([1, 0, 0])), 1e-6, "no seam across the 180 deg azimuth")
        let tilted = SIMD3<Double>(0.5, 0.6, 0.3)
        XCTAssertLessThan(simd_length(key(tilted) - key(c2b * tilted)), 1e-6)
        XCTAssertLessThan(simd_length(key(tilted) - key(-tilted)), 1e-6)
        XCTAssertLessThan(simd_length(key(SIMD3(0.7, 0.3, -0.2)) - key(SIMD3(-0.7, 0.3, 0.2))), 1e-6)
        XCTAssertEqual(ACOMCrystalSymmetry.monoclinic.displayName, "Monoclinic 2/m")
    }

    /// Refuter RB: (x, y, z) and (-x, y, z) are inequivalent under 2/m and must differ. Injectivity is
    /// tested by inverting the key: on a dense grid of the zone (polar 2..90 deg, azimuth 0..180 deg,
    /// step 2 deg, 180 excluded) the HSV colour gives back the direction's polar angle (saturation)
    /// and azimuth (hue) to 1e-4. A pairwise colour distance cannot test this: every key converges at
    /// the pole b, where the zone itself is one point. Mutation (the old (1 - cos 2 phi)/2 key) goes red.
    func testIPFKeyIsInjectiveOnTheFundamentalZone() {
        func invert(_ c: SIMD3<Float>) -> (tilt: Double, azimuth: Double) {
            let r = Double(c.x), g = Double(c.y), b = Double(c.z)
            let mx = max(r, g, b), mn = min(r, g, b), chroma = mx - mn
            var hue: Double
            if chroma < 1e-12 { hue = 0 }
            else if mx == r { hue = ((g - b) / chroma).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (b - r) / chroma + 2 }
            else { hue = (r - g) / chroma + 4 }
            hue *= 60; if hue < 0 { hue += 360 }
            var azimuth = (hue - 120) / 2; if azimuth < 0 { azimuth += 180 }
            return (chroma / max(mx, 1e-12) * 90, azimuth)
        }
        for tiltDeg in stride(from: 2.0, through: 90.0, by: 2.0) {
            for azDeg in stride(from: 0.0, to: 180.0, by: 2.0) {
                let t = tiltDeg * .pi / 180, a = azDeg * .pi / 180
                let d = SIMD3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
                let back = invert(ACOMCrystalSymmetry.monoclinic.ipfColor(direction: d))
                XCTAssertEqual(back.tilt, tiltDeg, accuracy: 1e-3, "polar \(tiltDeg), azimuth \(azDeg)")
                let dAz = abs(back.azimuth - azDeg)
                XCTAssertLessThan(min(dAz, 180 - dAz), 1e-3, "polar \(tiltDeg), azimuth \(azDeg)")
            }
        }
        let d = SIMD3<Double>(0.5, 0.6, 0.3)
        let mirrored = SIMD3<Double>(-0.5, 0.6, 0.3)
        XCTAssertGreaterThan(simd_length(ACOMCrystalSymmetry.monoclinic.ipfColor(direction: d)
            - ACOMCrystalSymmetry.monoclinic.ipfColor(direction: mirrored)), 0.2)
    }

    /// No seam: colour is continuous in azimuth across phi = 0 = 180 deg, and every group image
    /// of a dense sample gets the same colour.
    func testIPFKeyIsContinuousAtTheSeamAndInvariantOverADenseSample() {
        let key = ACOMCrystalSymmetry.monoclinic.ipfColor(direction:)
        let t = 60.0 * .pi / 180
        func at(_ azDeg: Double) -> SIMD3<Float> {
            let a = azDeg * .pi / 180
            return key(SIMD3(sin(t) * cos(a), cos(t), sin(t) * sin(a)))
        }
        XCTAssertLessThan(simd_length(at(179.9) - at(0.1)), 0.02)
        XCTAssertLessThan(simd_length(at(0.1) - at(0)), 0.02)
        var rng = MonoclinicRNG(state: 0x1F2E3D4C5B6A7988)
        let mirror = simd_double3x3(rows: [[1, 0, 0], [0, -1, 0], [0, 0, 1]])
        for _ in 0..<300 {
            let n = simd_normalize(SIMD3(rng.gauss(), rng.gauss(), rng.gauss()))
            for image in [-n, c2b * n, mirror * n] {
                XCTAssertLessThan(simd_length(key(image) - key(n)), 1e-5)
            }
        }
    }

    /// Refuter RB: the map's IPF legend is a pure function of the symmetry. Mutation (monoclinic
    /// falls back to the cubic key) goes red.
    func testIPFLegendChoiceIsAPureFunctionOfTheSymmetry() {
        XCTAssertEqual(IPFLegendKind.kind(for: .cubic), .cubic)
        XCTAssertEqual(IPFLegendKind.kind(for: .hexagonal), .hexagonal)
        XCTAssertEqual(IPFLegendKind.kind(for: .monoclinic), .monoclinic)
        XCTAssertEqual(IPFLegendKind.kind(for: .identity), .cubic, "unreduced keeps the cubic key it always had")
        XCTAssertEqual(IPFLegendKind.kind(for: nil), .cubic)
    }

    // MARK: - CrystalModel and CIFImport

    func testModelValidationByCellMetric() throws {
        func model(alpha: Double, beta: Double, gamma: Double) -> CrystalModel {
            CrystalModel(id: "t", displayName: "t",
                         structure: CrystalPresets.structure(a: 15.16, b: 4.05, c: 6.74, alphaDeg: alpha, betaDeg: beta, gammaDeg: gamma,
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
        XCTAssertEqual(try CIFModelImport.crystalModel(from: cif, fileBaseName: "p1").symmetry, .identity)
    }

    // MARK: - Unvalidated stays labelled

    /// A monoclinic map self-reports `validation: "none"` and the note, through the run's provenance
    /// into the inspector badge predicate and the export caption; cubic and hexagonal products do not.
    /// Mutation (drop the keys in `CrystalModel.provenance`): red.
    func testMonoclinicProductIsBadgedUnvalidatedAndCubicIsNot() throws {
        let model = try betaDoublePrimeModel()
        XCTAssertEqual(model.provenance["validation"], "none")
        XCTAssertEqual(model.provenance["validation_note"], "monoclinic orientation — no β″ truth set")
        let semantics = ACOMRunSemantics(
            materialModelID: model.id, materialDescription: model.displayName,
            scale: ACOMScaleSemantics(invAngstromPerPixel: 0.01, provenance: .manual),
            materialProvenance: model.provenance)
        XCTAssertTrue(ProductInfoSections.isUnvalidated(provenance: semantics.provenance))
        XCTAssertEqual(semantics.provenance["validation_note"], "monoclinic orientation — no β″ truth set")
        for other in CrystalModelLibrary.models {
            XCTAssertNil(other.provenance["validation"], "\(other.displayName) is not an unvalidated product")
            XCTAssertFalse(ProductInfoSections.isUnvalidated(provenance: other.provenance))
        }
    }

    // MARK: - P2 / P4: round trip through the matcher

    private func monoclinicPlan(count: Int) throws -> (plan: OrientationPlan, crystal: CrystalStructure) {
        let crystal = try betaDoublePrimeModel().structure
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: crystal, kMax: 1.2, zoneAxisCount: count, symmetry: .monoclinic, wavelengthAngstrom: 0.02508))
        return (plan, crystal)
    }

    /// Peaks of a kinematic pattern for the lab frame (f1, f2, n) in crystal coordinates, built here
    /// (never with production `project`), as in tools/harnesses/acom-mirror-test.
    private func peaks(crystal: CrystalStructure, truth: simd_double3x3, reflections: [KinematicReflection]) -> [BraggPeak] {
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

    /// P4. The pattern of R and of C2*R is the same pattern (C2 about b is a symmetry of the crystal), so
    /// the matcher returns ONE matrix for both, which is 180 deg from one of the two truths. Unreduced
    /// that is an error against half the truths; reduced by 2/m both truths and the recovered matrix are
    /// one orientation. Isolates the GROUP from the library: only draws on which the matcher found the
    /// pattern at all (plain angle to the nearer truth within the band) are scored here; the rest are P2.
    /// Mutation (reduce = identity): the reduced distance to the farther truth stays ~180 deg: red.
    func testP4TheC2AmbiguityIsMergedByMonoclinicAndNotByIdentity() throws {
        let (plan, crystal) = try monoclinicPlan(count: 400)
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        var rng = MonoclinicRNG(state: 0x853C49E6748FEA9B)
        var found = 0, scored = 0
        while scored < 60 {
            let v = SIMD3(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
            let length = simd_length(v)
            guard length > 0.2 && length <= 1 else { continue }
            let truth = truthMatrix(axis: v / length, inPlaneDeg: rng.uniform(0, 360))
            let image = c2b * truth
            scored += 1
            let p = peaks(crystal: crystal, truth: truth, reflections: reflections)
            let pImage = peaks(crystal: crystal, truth: image, reflections: reflections)
            XCTAssertEqual(p.count, pImage.count, "C2 about b is a symmetry: the two truths excite the same reflections")
            let result = matcher.match(peaks: p, originX: 256, originY: 256, invAngstromPerPixel: 0.008)
            let matrix = result.euler.py4DSTEMOrientationMatrix
            let nearer = min(angle(matrix, truth), angle(matrix, image)) * 180 / .pi
            let farther = max(angle(matrix, truth), angle(matrix, image)) * 180 / .pi
            guard nearer <= 7.7 else { continue }
            found += 1
            XCTAssertGreaterThan(farther, 172, "the two truths are a half turn apart, so unreduced one of them is far")
            for t in [truth, image] {
                XCTAssertLessThan(
                    angle(ACOMCrystalSymmetry.monoclinic.reduce(matrix).matrix,
                          ACOMCrystalSymmetry.monoclinic.reduce(t).matrix) * 180 / .pi, 7.7)
            }
        }
        XCTAssertGreaterThanOrEqual(found, 40, "the group test needs patterns the matcher found; the rest are P2")
    }

    /// RECORD (item B, closed 2026-10-14, ADR 050): P2 as registered failed at the default library, 86.5 % of
    /// 600 draws within 7.7 deg at 200 templates against a band of 95 % (archived docs/archive/v5/
    /// beta-double-prime-orientation-results-2026-10-14.md). 200 templates is no longer a shipped path for a
    /// monoclinic phase (`ACOMQualityPreset.templateCount(for:)`), so that case is not asserted here.
    ///
    /// P2' (item B2, registered before any run on these draws): at Balanced a monoclinic phase has 800
    /// templates; on 600 FRESH draws (item B's base seed 0x2545F4914F6CDD1D plus 1_000_000) the disorientation
    /// to truth is <= 7.7 deg for >= 97 %. Mutation (multiplier 1x): the library is 200 templates, 86 %: red.
    func testP2PrimeFreshDrawsAtTheMonoclinicLibraryAreRecoveredWithinTheStep() throws {
        let templates = ACOMQualityPreset.balanced.templateCount(for: .monoclinic)
        let within = try roundTripFraction(templates: templates, draws: 600,
                                           seed: 0x2545F4914F6CDD1D &+ 1_000_000)
        XCTAssertGreaterThanOrEqual(within, 0.97)
    }

    /// P6 (reported, not gated: wall-clock is machine and load dependent): match time per pattern at 800 vs
    /// 200 templates on the same patterns; registered band 3.5-4.5x.
    func testP6MatchTimeScalesWithTheLibrary() throws {
        let crystal = try betaDoublePrimeModel().structure
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        var rng = MonoclinicRNG(state: 0x2545F4914F6CDD1D &+ 1_000_000)
        var patterns: [[BraggPeak]] = []
        while patterns.count < 100 {
            let v = SIMD3(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
            let length = simd_length(v)
            guard length > 0.2 && length <= 1 else { continue }
            patterns.append(peaks(crystal: crystal, truth: truthMatrix(axis: v / length, inPlaneDeg: rng.uniform(0, 360)),
                                  reflections: reflections))
        }
        var seconds: [Int: Double] = [:]
        for count in [200, 800] {
            let (plan, _) = try monoclinicPlan(count: count)
            let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
            _ = matcher.match(peaks: patterns[0], originX: 256, originY: 256, invAngstromPerPixel: 0.008)  // warm
            let start = Date()
            for _ in 0..<3 { for p in patterns { _ = matcher.match(peaks: p, originX: 256, originY: 256, invAngstromPerPixel: 0.008) } }
            seconds[count] = Date().timeIntervalSince(start) / Double(3 * patterns.count)
        }
        print(String(format: "MEASURE: P6 match per pattern 200 templates %.3f ms, 800 templates %.3f ms, ratio %.2f",
                     seconds[200]! * 1000, seconds[800]! * 1000, seconds[800]! / seconds[200]!))
    }

    /// Fraction of random draws recovered within 7.7 deg (min over the independent 2/m list).
    private func roundTripFraction(templates: Int, draws: Int, seed: UInt64) throws -> Double {
        let (plan, crystal) = try monoclinicPlan(count: templates)
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        var rng = MonoclinicRNG(state: seed)
        var errors: [Double] = []
        while errors.count < draws {
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
        print(String(format: "MEASURE: beta'' round trip %d templates n=%d median %.2f p90 %.2f p95 %.2f max %.2f deg; within 7.7 deg %.3f; within 3.9 deg %.3f",
                     templates, errors.count, sorted[errors.count / 2], sorted[Int(Double(errors.count) * 0.9)],
                     sorted[Int(Double(errors.count) * 0.95)], sorted.last!, within,
                     Double(errors.filter { $0 <= 3.9 }.count) / Double(errors.count)))
        return within
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
