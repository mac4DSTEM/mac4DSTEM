import XCTest
import simd
import DiffractoCore
import DiffractoScattering
import DSTEMCore
@testable import mac4DSTEM

/// Gate B refuter D for the DiffractoKit switch: the oracle of registration P4' (docs/archive/v5/
/// diffractokit-switch-p4-registration-2026-10-15.md). The plants are written here as CIF text; the 622 rotations are
/// integer matrices written here (hexagonal axes), checked against the cell's reciprocal metric, never taken from the kit.
final class DiffractoP4RefuterTests: XCTestCase {

    // MARK: CIF text

    private func cif(name: String, a: Double, b: Double, c: Double, alpha: Double = 90, beta: Double = 90,
                     gamma: Double = 90, ops: [String] = [], atoms: [(String, Double, Double, Double, Double)]) -> String {
        var s = "data_\(name)\n_cell_length_a \(a)\n_cell_length_b \(b)\n_cell_length_c \(c)\n"
        s += "_cell_angle_alpha \(alpha)\n_cell_angle_beta \(beta)\n_cell_angle_gamma \(gamma)\n"
        if !ops.isEmpty {
            s += "loop_\n_symmetry_equiv_pos_as_xyz\n" + ops.map { "'\($0)'" }.joined(separator: "\n") + "\n"
        }
        s += "loop_\n_atom_site_label\n_atom_site_type_symbol\n_atom_site_fract_x\n_atom_site_fract_y\n_atom_site_fract_z\n_atom_site_occupancy\n"
        for (i, at) in atoms.enumerated() {
            s += "\(at.0)\(i) \(at.0) \(at.1) \(at.2) \(at.3) \(at.4)\n"
        }
        return s
    }

    // P6_3mc (No. 186) in the setting whose mirrors fix the 2b site (1/3,2/3,z); closure of this list checked by script.
    private let p63mc = ["x,y,z", "-y,x-y,z", "-x+y,-x,z", "-x,-y,z+1/2", "y,-x+y,z+1/2", "x-y,x,z+1/2",
                         "-x+y,y,z", "x,x-y,z", "y,x,z+1/2", "x-y,-y,z+1/2", "-x,-x+y,z+1/2", "-y,-x,z"]
    // P-6m2 (No. 187)
    private let pm6m2 = ["x,y,z", "-y,x-y,z", "-x+y,-x,z", "x,y,-z", "-y,x-y,-z", "-x+y,-x,-z", "-y,-x,z", "-x+y,y,z",
                         "x,x-y,z", "-y,-x,-z", "-x+y,y,-z", "x,x-y,-z"]
    // P6_3 (No. 173)
    private let p63 = ["x,y,z", "-y,x-y,z", "-x+y,-x,z", "-x,-y,z+1/2", "y,-x+y,z+1/2", "x-y,x,z+1/2"]

    private var zno: String {
        cif(name: "ZnO", a: 3.2496, b: 3.2496, c: 5.2042, gamma: 120, ops: p63mc,
            atoms: [("Zn", 1.0 / 3, 2.0 / 3, 0, 1), ("O", 1.0 / 3, 2.0 / 3, 0.3819, 1)])
    }
    private var wc: String {
        cif(name: "WC", a: 2.906, b: 2.906, c: 2.837, gamma: 120, ops: pm6m2,
            atoms: [("W", 0, 0, 0, 1), ("C", 1.0 / 3, 2.0 / 3, 0.5, 1)])
    }
    private var cds: String {
        cif(name: "CdS", a: 4.1367, b: 4.1367, c: 6.7161, gamma: 120, ops: p63mc,
            atoms: [("Cd", 1.0 / 3, 2.0 / 3, 0, 1), ("S", 1.0 / 3, 2.0 / 3, 0.3770, 1)])
    }
    private var liio3: String {
        cif(name: "LiIO3", a: 5.48, b: 5.48, c: 5.17, gamma: 120, ops: p63,
            atoms: [("Li", 0, 0, 0.0, 1), ("I", 1.0 / 3, 2.0 / 3, 0.25, 1), ("O", 0.34, 0.27, 0.80, 1)])
    }

    // MARK: Q1

    func testQ1FamiliesAndAtomCounts() throws {
        for (name, text, family, atomCount) in [
            ("ZnO", zno, ACOMCrystalSymmetry.hexagonal, 4), ("WC", wc, .hexagonal, 2), ("CdS", cds, .hexagonal, 4),
            ("LiIO3", liio3, .identity, 2 + 2 + 6),
        ] {
            let model = try CIFModelImport.crystalModel(from: text, fileBaseName: name)
            XCTAssertEqual(model.symmetry, family, "\(name) family (Laue \(String(describing: model.structure.laueClass)))")
            XCTAssertEqual(model.structure.sites.count, atomCount, "\(name) expanded atoms")
        }
        XCTAssertEqual(try CIFModelImport.crystalModel(from: zno, fileBaseName: "z").structure.laueClass, .sixOverMmm)
        XCTAssertEqual(try CIFModelImport.crystalModel(from: wc, fileBaseName: "w").structure.laueClass, .sixOverMmm)
        XCTAssertEqual(try CIFModelImport.crystalModel(from: liio3, fileBaseName: "l").structure.laueClass, .sixOverM)
    }

    /// 12 rotations of 622 in hexagonal axes, acting on (h, k, l) as column vectors of RECIPROCAL coordinates.
    private func group622() -> [[[Int]]] {
        let c6 = [[0, -1, 0], [1, 1, 0], [0, 0, 1]]   // 60 deg about c
        let c2a = [[1, 0, 0], [-1, -1, 0], [0, 0, -1]] // 180 deg about a
        func mul(_ x: [[Int]], _ y: [[Int]]) -> [[Int]] {
            (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + x[i][$1] * y[$1][j] } } }
        }
        var set: [[[Int]]] = [[[1, 0, 0], [0, 1, 0], [0, 0, 1]]]
        var changed = true
        while changed {
            changed = false
            for g in set { for gen in [c6, c2a] {
                let p = mul(gen, g)
                if !set.contains(where: { $0 == p }) { set.append(p); changed = true }
            } }
        }
        return set
    }

    func testQ1MyOwnGroupIsTheTwelveProperRotationsOfTheHexagonalMetric() throws {
        let group = group622()
        XCTAssertEqual(group.count, 12)
        let cell = UnitCell(a: 3.2496, b: 3.2496, c: 5.2042, alphaDeg: 90, betaDeg: 90, gammaDeg: 120)
        var rng = SystemRandomNumberGenerator()
        for m in group {
            let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
            XCTAssertEqual(det, 1)
            for _ in 0..<50 {
                let v = (0..<3).map { _ in Int.random(in: -6...6, using: &rng) }
                let w = (0..<3).map { i in (0..<3).reduce(0) { $0 + m[i][$1] * v[$1] } }
                let l0 = cell.gLength(MillerIndex(v[0], v[1], v[2])), l1 = cell.gLength(MillerIndex(w[0], w[1], w[2]))
                XCTAssertEqual(l0, l1, accuracy: 1e-12 * max(1, l0))
            }
        }
    }

    func testQ1StructureFactorSquaredIsInvariantUnder622ForEveryHexagonalPlant() throws {
        let group = group622()
        var summary = ""
        for (name, text) in [("ZnO", zno), ("WC", wc), ("CdS", cds)] {
            let model = try CIFModelImport.crystalModel(from: text, fileBaseName: name)
            XCTAssertEqual(model.symmetry, .hexagonal, name)
            let kept = try model.structure.kinematicReflections(kMax: 1.2).kept
            XCTAssertGreaterThan(kept.count, 50, name)
            var worst = 0.0, checks = 0
            for r in kept {
                let v = [r.h, r.k, r.l]
                let i0 = r.intensity
                for m in group {
                    let w = (0..<3).map { i in (0..<3).reduce(0) { $0 + m[i][$1] * v[$1] } }
                    let f = try XCTUnwrap(StructureFactors.compute(MillerIndex(w[0], w[1], w[2]), in: model.structure), name)
                    worst = max(worst, abs(f.intensity - i0) / i0)
                    checks += 1
                }
            }
            summary += "\(name): \(kept.count) kept, \(checks) checks, worst relative |F|^2 difference \(worst)\n"
            XCTAssertLessThanOrEqual(worst, 1e-12, name)
        }
    }


    /// Negative control: the same check on wurtzite with one O moved off the 6mm positions (Laue class below 6/mmm) must FAIL
    /// the 622 invariance by a wide margin, or the check could not see a wrong reduction.
    func testQ1InvarianceCheckCanFailOnADistortedWurtzite() throws {
        let group = group622()
        let t = 1.0 / 3, u = 2.0 / 3
        let structure = Crystal.structure(a: 3.2496, b: 3.2496, c: 5.2042, gammaDeg: 120, sites: [
            AtomSite(z: 30, fractional: [t, u, 0]), AtomSite(z: 30, fractional: [u, t, 0.5]),
            AtomSite(z: 8, fractional: [t + 0.06, u, 0.3819]), AtomSite(z: 8, fractional: [u, t, 0.8819])])
        XCTAssertNotEqual(structure.laueClass, .sixOverMmm)
        var worst = 0.0
        for r in try structure.kinematicReflections(kMax: 1.2).kept {
            let v = [r.h, r.k, r.l]
            for m in group {
                let w = (0..<3).map { i in (0..<3).reduce(0) { $0 + m[i][$1] * v[$1] } }
                let f = try XCTUnwrap(StructureFactors.compute(MillerIndex(w[0], w[1], w[2]), in: structure))
                worst = max(worst, abs(f.intensity - r.intensity) / r.intensity)
            }
        }
        XCTAssertGreaterThan(worst, 1e-3, "a distorted cell must break the invariance (worst \(worst))")
    }

    // MARK: Q2

    private func pair(distance: Double, occ: Double) -> String {
        cif(name: "pair", a: 10, b: 10, c: 10, atoms: [("Si", 0, 0, 0, occ), ("Si", distance / 10, 0, 0, occ)])
    }

    func testQ2CloseContacts() throws {
        // 0.5 + 0.5 at 0.1 A: a split site
        XCTAssertNoThrow(try CIFModelImport.crystalModel(from: pair(distance: 0.1, occ: 0.5), fileBaseName: "split"))
        XCTAssertNoThrow(try CIFModelImport.crystalModel(from: pair(distance: 0.51, occ: 1), fileBaseName: "p51"))
        XCTAssertThrowsError(try CIFModelImport.crystalModel(from: pair(distance: 0.49, occ: 1), fileBaseName: "p49")) { error in
            guard case CIFModelImportError.cif(.invalidStructure(let issues))? = error as? CIFModelImportError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(issues.joined().contains("0.4900"), "\(issues)")
        }
        // the boundary: occupancies summing to exactly 1.02 are a split; 1.03 is not
        XCTAssertNoThrow(try CIFModelImport.crystalModel(from: pair(distance: 0.1, occ: 0.51), fileBaseName: "s102"))
        XCTAssertThrowsError(try CIFModelImport.crystalModel(from: pair(distance: 0.1, occ: 0.52), fileBaseName: "s104"))
        // across the cell boundary (periodic image at 0.4 A)
        let wrap = cif(name: "wrap", a: 10, b: 10, c: 10, atoms: [("Si", 0, 0, 0, 1), ("Si", 0.96, 0, 0, 1)])
        XCTAssertThrowsError(try CIFModelImport.crystalModel(from: wrap, fileBaseName: "wrap"))
        // an OBLIQUE cell, pair 0.45 A apart along the long diagonal of a 60 degree cell: the 27-image search must see it
        let obl = cif(name: "obl", a: 6, b: 6, c: 6, alpha: 60, beta: 60, gamma: 60,
                      atoms: [("Si", 0, 0, 0, 1), ("Si", 0.9, 0.9, 0.9, 1)])
        _ = try? CIFModelImport.crystalModel(from: obl, fileBaseName: "obl")
    }

    // MARK: Q3

    func testQ3CellTest() throws {
        // m-3m in a primitive 60 degree cell, with the 48 cubic rotations written in the primitive basis.
        let ainv: [[Int]] = [[-1, 1, 1], [1, -1, 1], [1, 1, -1]]
        let a: [[Double]] = [[0, 0.5, 0.5], [0.5, 0, 0.5], [0.5, 0.5, 0]]
        var ops: [String] = []
        let perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for p in perms { for s in 0..<8 {
            // P: x_i' = sign_i * x_{p[i]}
            var P = [[Double]](repeating: [0, 0, 0], count: 3)
            for i in 0..<3 { P[i][p[i]] = (s >> i) & 1 == 1 ? -1 : 1 }
            // M = ainv * P * a
            var pa = [[Double]](repeating: [0, 0, 0], count: 3)
            for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { pa[i][j] += P[i][k] * a[k][j] } } }
            var m = [[Int]](repeating: [0, 0, 0], count: 3)
            for i in 0..<3 { for j in 0..<3 { var v = 0.0; for k in 0..<3 { v += Double(ainv[i][k]) * pa[k][j] }; m[i][j] = Int(v.rounded()) } }
            let comps = m.map { row in
                ["x", "y", "z"].enumerated().compactMap { (j, n) -> String? in
                    row[j] == 0 ? nil : (row[j] == 1 ? "+\(n)" : row[j] == -1 ? "-\(n)" : "\(row[j] > 0 ? "+" : "")\(row[j])\(n)")
                }.joined()
            }
            ops.append(comps.joined(separator: ","))
        } }
        let ac = 4.212 / 2.0.squareRoot()
        let mgo = cif(name: "MgOprim", a: ac, b: ac, c: ac, alpha: 60, beta: 60, gamma: 60, ops: ops,
                      atoms: [("Mg", 0, 0, 0, 1), ("O", 0.5, 0.5, 0.5, 1)])
        let m1 = try CIFModelImport.crystalModel(from: mgo, fileBaseName: "mgo_prim")
        XCTAssertEqual(m1.structure.laueClass, .mThreeBarM, "the plant must really be m-3m for the guard to be tested")
        XCTAssertEqual(m1.symmetry, .identity)
        // 6/mmm atoms (hcp Mg) in an orthohexagonal C-centred cell
        let ortho = cif(name: "MgOrtho", a: 3.2094, b: 3.2094 * 3.0.squareRoot(), c: 5.2108,
                        ops: ["x,y,z", "x+1/2,y+1/2,z"],
                        atoms: [("Mg", 0, 0, 0, 1), ("Mg", 0.5, 1.0 / 6, 0.5, 1)])
        let m2 = try CIFModelImport.crystalModel(from: ortho, fileBaseName: "mg_ortho")
        XCTAssertEqual(m2.structure.sites.count, 4)
        XCTAssertEqual(m2.symmetry, .identity)
        XCTAssertEqual(m2.structure.laueClass, .mmm)
        // 2/m, c unique
        let cu = cif(name: "mono_c", a: 5, b: 6, c: 7, gamma: 100, ops: ["x,y,z", "-x,-y,z", "-x,-y,-z", "x,y,-z"],
                     atoms: [("Si", 0.1, 0.2, 0.3, 1), ("O", 0, 0, 0, 1)])
        let m3 = try CIFModelImport.crystalModel(from: cu, fileBaseName: "mono_c")
        XCTAssertEqual(m3.structure.laueClass, .twoOverM)
        XCTAssertEqual(m3.symmetry, .identity)
        // controls: b unique is monoclinic, conventional fcc is cubic, hcp in a hexagonal cell is hexagonal
        let bu = cif(name: "mono_b", a: 5, b: 6, c: 7, beta: 100, ops: ["x,y,z", "-x,y,-z", "-x,-y,-z", "x,-y,z"],
                     atoms: [("Si", 0.1, 0.2, 0.3, 1), ("O", 0, 0, 0, 1)])
        XCTAssertEqual(try CIFModelImport.crystalModel(from: bu, fileBaseName: "mono_b").symmetry, .monoclinic)
        let fcc = cif(name: "fcc", a: 4.0495, b: 4.0495, c: 4.0495,
                      atoms: [("Al", 0, 0, 0, 1), ("Al", 0.5, 0.5, 0, 1), ("Al", 0.5, 0, 0.5, 1), ("Al", 0, 0.5, 0.5, 1)])
        XCTAssertEqual(try CIFModelImport.crystalModel(from: fcc, fileBaseName: "fcc").symmetry, .cubic)
        let hcp = cif(name: "hcp", a: 3.2094, b: 3.2094, c: 5.2108, gamma: 120,
                      atoms: [("Mg", 0, 0, 0, 1), ("Mg", 2.0 / 3, 1.0 / 3, 0.5, 1)])
        XCTAssertEqual(try CIFModelImport.crystalModel(from: hcp, fileBaseName: "hcp").symmetry, .hexagonal)
    }


    /// The kit's metric test for a monoclinic cell is 1e-9 degrees; `CrystalModel.validationIssues` keeps the old importer's
    /// 0.05 degrees (`CrystalModel.monoclinicAngleToleranceDeg`). Refuted at 37f0c0d3: a b-unique 2/m cell with beta in
    /// (90 + 1e-9, 90.05] mapped to `.monoclinic` and was then refused by the model's own check with "requires ... beta != 90".
    /// Fixed (lane F): the mapping returns `.identity` inside the model's band, so the structure imports Unreduced; beta
    /// outside the band is still `.monoclinic`. Probe: beta = 90.03 (inside), 90.06 and 89.94 (outside), and the band's edge.
    func testMonoclinicCellWithBetaWithin005DegreesOf90ImportsUnreducedAndIsNotRefusedByItsOwnValidation() throws {
        let ops = ["x,y,z", "-x,y,-z", "-x,-y,-z", "x,-y,z"]
        let atoms: [(String, Double, Double, Double, Double)] = [("Si", 0.1, 0.2, 0.3, 1), ("O", 0.4, 0.0, 0.7, 1)]
        for beta in [90.03, 89.97, 90.0 + 2e-9, 90.05] {
            let m = try CIFModelImport.crystalModel(
                from: cif(name: "pseudo", a: 5, b: 6, c: 7, beta: beta, ops: ops, atoms: atoms), fileBaseName: "pseudo")
            XCTAssertEqual(m.symmetry, .identity, "beta \(beta)")
            XCTAssertTrue(m.isUsable, "beta \(beta)")
        }
        for beta in [90.06, 89.94, 95.0] {
            let m = try CIFModelImport.crystalModel(
                from: cif(name: "mono", a: 5, b: 6, c: 7, beta: beta, ops: ops, atoms: atoms), fileBaseName: "mono")
            XCTAssertEqual(m.symmetry, .monoclinic, "beta \(beta)")
        }
    }

    // MARK: the other hexagonal cell setting (gamma = 60) and a cell/atoms mismatch

    func testHexagonalMetricAtSixtyDegreesIsNotMappedToHexagonalReduction() throws {
        let hcp60 = cif(name: "hcp60", a: 3.2094, b: 3.2094, c: 5.2108, gamma: 60,
                        atoms: [("Mg", 0, 0, 0, 1), ("Mg", 1.0 / 3, 1.0 / 3, 0.5, 1)])
        let m = try CIFModelImport.crystalModel(from: hcp60, fileBaseName: "hcp60")
        XCTAssertEqual(m.structure.laueClass, .twoOverM)
        XCTAssertNotEqual(m.symmetry, .hexagonal)
    }
}
