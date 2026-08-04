//
//  tools/cif-symmetry-test — parity/regression fixture for CIFImport's
//  point-group admission.
//
//  Why this exists: `classifyFamily` reads the *cell metric* only. A trigonal
//  structure is conventionally published in the hexagonal setting (a = b,
//  γ = 120°) while carrying only a 3-fold along c, so the metric alone admits
//  quartz, calcite, alumina and hematite as `.hexagonal` — a 12-operator
//  fundamental zone and an IPF key they do not have. Symmetrically, a
//  tetragonal cell with accidentally equal axes is metrically cubic.
//
//  `verifyFamily` therefore requires the family's defining rotation to be a
//  real symmetry of the expanded atom set (up to a translation, so screw axes
//  still pass). This fixture pins both directions:
//
//    * structures that MUST be rejected — right metric, wrong symmetry;
//    * structures that MUST still be admitted — including the two shipped
//      built-in lattices (diamond Si via a 3-fold with a glide-like offset,
//      HCP Mg via the 6₃ screw), because a check that rejects those has
//      broken the importer instead of fixing it.
//
//  Run via tools/run-tests.sh scientific.
//

import Foundation

// MARK: - Cases

private struct Case {
    let name: String
    let cif: String
    /// `nil` = must be admitted with this symmetry; otherwise must be rejected.
    let expectedSymmetry: ACOMCrystalSymmetry?
    let mustReject: Bool
    let why: String
}

/// α-quartz, P3₂21 (#154). Point group 32 → 6 proper rotations, 3-fold only.
/// The classic false positive: perfect hexagonal metric, trigonal structure.
private let quartz = """
data_alpha_quartz
_cell_length_a 4.9134
_cell_length_b 4.9134
_cell_length_c 5.4052
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 120.0
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z'
'-y,x-y,z+2/3'
'-x+y,-x,z+1/3'
'y,x,-z'
'x-y,-y,-z+1/3'
'-x,-x+y,-z+2/3'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Si1 Si 0.4697 0.0000 0.0000 1.0
O1  O  0.4135 0.2669 0.1191 1.0
"""

/// Calcite, R-3c (#167), hexagonal setting. Point group -3m → 3-fold only.
private let calcite = """
data_calcite
_cell_length_a 4.9880
_cell_length_b 4.9880
_cell_length_c 17.0680
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 120.0
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z'
'-y,x-y,z'
'-x+y,-x,z'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Ca1 Ca 0.0000 0.0000 0.0000 1.0
C1  C  0.0000 0.0000 0.2500 1.0
O1  O  0.2578 0.0000 0.2500 1.0
"""

/// Tetragonal contents (4-fold about c only) in a cell whose axes are
/// accidentally equal, so the metric reads cubic. Must not become `.cubic`:
/// there is no 3-fold along ⟨111⟩.
private let accidentallyCubicMetric = """
data_tetragonal_a_equals_c
_cell_length_a 4.0000
_cell_length_b 4.0000
_cell_length_c 4.0000
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 90.0
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z'
'-x,-y,z'
'-y,x,z'
'y,-x,z'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Ti1 Ti 0.0000 0.0000 0.0000 1.0
O1  O  0.3000 0.3000 0.0000 1.0
"""

/// FCC gold, listed as P1 with all four sites explicit — the ordinary
/// "no symmetry loop" case. Genuinely cubic; must be admitted.
private let goldP1 = """
data_gold
_cell_length_a 4.0782
_cell_length_b 4.0782
_cell_length_c 4.0782
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 90.0
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Au1 Au 0.0000 0.0000 0.0000 1.0
Au2 Au 0.0000 0.5000 0.5000 1.0
Au3 Au 0.5000 0.0000 0.5000 1.0
Au4 Au 0.5000 0.5000 0.0000 1.0
"""

/// Diamond-structure silicon, Fd-3m. The ⟨111⟩ 3-fold here is accompanied by
/// a translation; a t = 0 check would wrongly reject this shipped model.
private let siliconDiamond = """
data_silicon
_cell_length_a 5.4310
_cell_length_b 5.4310
_cell_length_c 5.4310
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 90.0
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Si1 Si 0.0000 0.0000 0.0000 1.0
Si2 Si 0.0000 0.5000 0.5000 1.0
Si3 Si 0.5000 0.0000 0.5000 1.0
Si4 Si 0.5000 0.5000 0.0000 1.0
Si5 Si 0.2500 0.2500 0.2500 1.0
Si6 Si 0.2500 0.7500 0.7500 1.0
Si7 Si 0.7500 0.2500 0.7500 1.0
Si8 Si 0.7500 0.7500 0.2500 1.0
"""

/// HCP magnesium, P6₃/mmc. Truly hexagonal, but its 6-fold is the 6₃ *screw*
/// (t = (0,0,½)). This is the case that forces the translation search — it is
/// also a shipped built-in model, so rejecting it would be a regression.
private func magnesiumHCP(decimals: Int) -> String {
    func round(_ value: Double) -> String {
        String(format: "%.\(decimals)f", value)
    }
    return """
    data_magnesium
    _cell_length_a 3.2094
    _cell_length_b 3.2094
    _cell_length_c 5.2108
    _cell_angle_alpha 90.0
    _cell_angle_beta  90.0
    _cell_angle_gamma 120.0
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    _atom_site_occupancy
    Mg1 Mg \(round(1.0 / 3.0)) \(round(2.0 / 3.0)) 0.2500 1.0
    Mg2 Mg \(round(2.0 / 3.0)) \(round(1.0 / 3.0)) 0.7500 1.0
    """
}

/// Fluorapatite, P6₃/m (#176). Laue class **6/m**: it has the 6-fold along c
/// but NO 2-fold along a, so it is not 6/mmm. A single-generator check admits
/// it and hands it a 12-operator group and an IPF key that folds 60° to 30°.
private let fluorapatite = """
data_fluorapatite
_cell_length_a 9.3973
_cell_length_b 9.3973
_cell_length_c 6.8782
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 120.0
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z'
'-y,x-y,z'
'-x+y,-x,z'
'-x,-y,z+1/2'
'y,-x+y,z+1/2'
'x-y,x,z+1/2'
'-x,-y,-z'
'y,-x+y,-z'
'x-y,x,-z'
'x,y,-z+1/2'
'-y,x-y,-z+1/2'
'-x+y,-x,-z+1/2'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Ca1 Ca 0.3333333 0.6666667 0.0011 1.0
Ca2 Ca 0.2416 0.2411 0.2500 1.0
P1  P  0.3985 0.3682 0.2500 1.0
O1  O  0.3283 0.4849 0.2500 1.0
O2  O  0.5875 0.4652 0.2500 1.0
O3  O  0.3435 0.2579 0.0705 1.0
F1  F  0.0000 0.0000 0.2500 1.0
"""

/// Pyrite FeS₂, Pa-3 (#205). Laue class **m-3**: it has the ⟨111⟩ 3-fold but
/// no 4-fold along c, so it is not m-3m. The cubic mirror of the apatite case.
private let pyrite = """
data_pyrite
_cell_length_a 5.4179
_cell_length_b 5.4179
_cell_length_c 5.4179
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 90.0
loop_
_symmetry_equiv_pos_as_xyz
'x,y,z'
'-x+1/2,-y,z+1/2'
'-x,y+1/2,-z+1/2'
'x+1/2,-y+1/2,-z'
'z,x,y'
'z+1/2,-x+1/2,-y'
'-z+1/2,-x,y+1/2'
'-z,x+1/2,-y+1/2'
'y,z,x'
'-y,z+1/2,-x+1/2'
'y+1/2,-z+1/2,-x'
'-y+1/2,-z,x+1/2'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Fe1 Fe 0.0000 0.0000 0.0000 1.0
S1  S  0.3851 0.3851 0.3851 1.0
"""

/// FCC gold carrying a split atom displaced along **x only** — a dumbbell,
/// which is at best tetragonal. `split` is the displacement in fractional
/// units.
///
/// This pins the tolerance from both sides. A displacement *below*
/// `symmetryPositionTolerance` is deliberately invisible — 0.0009 fractional
/// is 0.0037 Å in this cell, an order of magnitude under the rounding noise
/// the tolerance exists to absorb, so calling that structure cubic is right.
/// A displacement *above* it is a real symmetry break and must be rejected;
/// this is also what exercises the bijection check, since both members of a
/// close pair would otherwise be allowed to match the same target site.
private func goldSplitAtom(split: Double) -> String {
    """
    data_gold_split
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90.0
    _cell_angle_beta  90.0
    _cell_angle_gamma 90.0
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    _atom_site_occupancy
    Au1 Au 0.0000 0.0000 0.0000 1.0
    Au2 Au \(String(format: "%.4f", split)) 0.0000 0.0000 1.0
    Au3 Au 0.5000 0.5000 0.0000 1.0
    Au4 Au 0.5000 0.0000 0.5000 1.0
    Au5 Au 0.0000 0.5000 0.5000 1.0
    """
}

/// CdI₂-type, P-3m1. Genuinely trigonal: the 6-fold would have to swap the
/// (⅓,⅔) and (⅔,⅓) columns, whose z differ. Must reject.
private let cadmiumIodide = """
data_cdi2
_cell_length_a 4.2400
_cell_length_b 4.2400
_cell_length_c 6.8600
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 120.0
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Cd1 Cd 0.0000000 0.0000000 0.0000 1.0
I1  I  0.3333333 0.6666667 0.2490 1.0
I2  I  0.6666667 0.3333333 0.7510 1.0
"""

/// Genuinely hexagonal magnesium whose two symmetry-equivalent sites carry
/// slightly different refined occupancies — routine in a disordered structure
/// exported as P1. Must still be admitted: occupancy is dimensionless and
/// cannot share the fractional-position tolerance.
private let magnesiumRefinedOccupancies = """
data_magnesium_occ
_cell_length_a 3.2094
_cell_length_b 3.2094
_cell_length_c 5.2108
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 120.0
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Mg1 Mg 0.3333333 0.6666667 0.2500 0.980
Mg2 Mg 0.6666667 0.3333333 0.7500 0.975
"""

private let cases: [Case] = [
    Case(name: "alpha_quartz_P3221", cif: quartz, expectedSymmetry: nil, mustReject: true,
         why: "trigonal (3-fold only) in the hexagonal setting"),
    Case(name: "calcite_R-3c", cif: calcite, expectedSymmetry: nil, mustReject: true,
         why: "trigonal (-3m) in the hexagonal setting"),
    Case(name: "tetragonal_accidental_cubic_metric", cif: accidentallyCubicMetric,
         expectedSymmetry: nil, mustReject: true,
         why: "cubic metric by coincidence, no 3-fold along <111>"),
    Case(name: "gold_fcc_P1", cif: goldP1, expectedSymmetry: .cubic, mustReject: false,
         why: "genuinely cubic, no symmetry loop supplied"),
    Case(name: "silicon_diamond_Fd-3m", cif: siliconDiamond, expectedSymmetry: .cubic,
         mustReject: false, why: "cubic <111> 3-fold carries a translation"),
    // Precision sweep. Magnesium is genuinely P6_3/mmc at every precision; a
    // check that only passes on 7-decimal coordinates is measuring rounding,
    // not symmetry. 3 decimals is entirely ordinary in published CIFs.
    Case(name: "magnesium_hcp_3dp", cif: magnesiumHCP(decimals: 3),
         expectedSymmetry: .hexagonal, mustReject: false,
         why: "hexagonal via the 6-3 screw, coordinates at 3 decimals"),
    Case(name: "magnesium_hcp_4dp", cif: magnesiumHCP(decimals: 4),
         expectedSymmetry: .hexagonal, mustReject: false,
         why: "hexagonal via the 6-3 screw, coordinates at 4 decimals"),
    Case(name: "magnesium_hcp_7dp", cif: magnesiumHCP(decimals: 7),
         expectedSymmetry: .hexagonal, mustReject: false,
         why: "hexagonal via the 6-3 screw, t = (0,0,1/2)"),
    Case(name: "magnesium_refined_occupancies", cif: magnesiumRefinedOccupancies,
         expectedSymmetry: .hexagonal, mustReject: false,
         why: "equivalent sites differ by 0.005 occupancy — refinement noise"),
    // Laue class within the family: one generator is not the group.
    Case(name: "fluorapatite_P63m_laue_6overm", cif: fluorapatite, expectedSymmetry: nil,
         mustReject: true, why: "Laue 6/m — 6-fold along c but no 2-fold along a"),
    Case(name: "pyrite_Pa-3_laue_m-3", cif: pyrite, expectedSymmetry: nil,
         mustReject: true, why: "Laue m-3 — <111> 3-fold but no 4-fold along c"),
    Case(name: "cdi2_P-3m1_trigonal", cif: cadmiumIodide, expectedSymmetry: nil,
         mustReject: true, why: "trigonal — 6-fold would swap columns at different z"),
    Case(name: "gold_split_atom_0p05_real_break", cif: goldSplitAtom(split: 0.05),
         expectedSymmetry: nil, mustReject: true,
         why: "0.05 fractional (0.20 A) dumbbell along x — a real symmetry break"),
    Case(name: "gold_split_atom_0p0009_below_tolerance", cif: goldSplitAtom(split: 0.0009),
         expectedSymmetry: .cubic, mustReject: false,
         why: "0.0009 fractional (0.0037 A) is under the tolerance by design"),
]

// MARK: - Runner

@main
enum CIFSymmetryTest {
    static func main() {
        var failures: [String] = []

        for testCase in cases {
            let result = Result {
                try CIFImport.crystalModel(from: testCase.cif, fileBaseName: testCase.name)
            }
            switch (result, testCase.mustReject) {
            case (.success(let model), true):
                failures.append(
                    "\(testCase.name): expected REJECT (\(testCase.why)) but was admitted "
                    + "as .\(model.symmetry.rawValue)"
                )
            case (.failure(let error), true):
                guard case CIFImportError.symmetryNotSupportedByStructure = error else {
                    failures.append(
                        "\(testCase.name): rejected, but for the wrong reason — "
                        + "\((error as? LocalizedError)?.errorDescription ?? "\(error)")"
                    )
                    continue
                }
                print("PASS: rejected \(testCase.name) — \(testCase.why)")
            case (.success(let model), false):
                guard model.symmetry == testCase.expectedSymmetry else {
                    failures.append(
                        "\(testCase.name): admitted as .\(model.symmetry.rawValue), "
                        + "expected .\(testCase.expectedSymmetry!.rawValue)"
                    )
                    continue
                }
                print("PASS: admitted \(testCase.name) as .\(model.symmetry.rawValue) — \(testCase.why)")
            case (.failure(let error), false):
                failures.append(
                    "\(testCase.name): expected ADMIT (\(testCase.why)) but was rejected — "
                    + "\((error as? LocalizedError)?.errorDescription ?? "\(error)")"
                )
            }
        }

        guard failures.isEmpty else {
            for failure in failures { print("FAIL: \(failure)") }
            print("cif-symmetry-test: \(failures.count) failure(s)")
            exit(1)
        }
        print("cif-symmetry-test: all passed")
    }
}
