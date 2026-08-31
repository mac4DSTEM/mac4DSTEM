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
//  It also covers the **symmetry-expansion path** (backlog #14), which the
//  original fixture never reached: every "must admit" case supplied its cell
//  contents explicitly, so `expand` never ran on one. Those cases assert the
//  resulting SITE COUNT, because an over- or under-populated cell is admitted
//  with the right symmetry and the wrong structure factors — site multiplicity
//  multiplies straight into |F|² and nothing downstream notices.
//
//  Three verdicts, and the distinction matters: a structure can lack a
//  symmetry, or be written too coarsely to tell (`.precision` — still a
//  rejection, but the opposite claim about the user's structure), or be
//  refused by the model contract after passing every symmetry test.
//
//  Run via tools/run-tests.sh scientific.
//

import Foundation

// MARK: - Cases

private enum Rejection {
    /// Right metric, wrong symmetry — `verifyFamily` must catch it.
    case symmetry
    /// Right metric, coordinates too coarse to tell a symmetry break from
    /// their own rounding. Still a rejection; a *different* claim about the
    /// user's structure, and the only true one at that precision.
    case precision
    /// Admitted by the symmetry checks, then refused by the model contract.
    /// `code` is the `CrystalModelValidationIssue` code that must appear.
    case invalidModel(code: String)
}

private struct Case {
    let name: String
    let cif: String
    /// `nil` = must be rejected; otherwise must be admitted with this symmetry.
    let expectedSymmetry: ACOMCrystalSymmetry?
    /// How it must be rejected, when `expectedSymmetry` is nil.
    let rejection: Rejection?
    /// Cell contents that must come out of symmetry expansion, when it matters.
    let expectedSiteCount: Int?
    let why: String

    init(
        name: String, cif: String, expectedSymmetry: ACOMCrystalSymmetry? = nil,
        rejection: Rejection? = nil, expectedSiteCount: Int? = nil, why: String
    ) {
        self.name = name
        self.cif = cif
        self.expectedSymmetry = expectedSymmetry
        self.rejection = rejection
        self.expectedSiteCount = expectedSiteCount
        self.why = why
    }
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

/// FCC gold with **one of its four sites displaced** along x by `shift`
/// fractional units — the cell stays four atoms, so this isolates the symmetry
/// tolerance from the "is this cell over-populated" question below.
///
/// It pins the tolerance from both sides. A displacement under
/// `symmetryPositionTolerance` is deliberately invisible — 0.0009 fractional
/// is 0.0037 Å, an order of magnitude under the rounding noise the tolerance
/// exists to absorb, so calling that structure cubic is right. A displacement
/// above it is a real symmetry break and must be rejected.
private func goldShiftedSite(shift: Double) -> String {
    """
    data_gold_shifted
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
    Au2 Au \(String(format: "%.4f", 0.5 + shift)) 0.5000 0.0000 1.0
    Au3 Au 0.5000 0.0000 0.5000 1.0
    Au4 Au 0.0000 0.5000 0.5000 1.0
    """
}

/// FCC gold with a fifth atom sitting 0.0009 fractional (0.0037 Å) from the
/// corner site. This is metrically and symmetrically cubic — the extra atom is
/// well inside the symmetry tolerance, so `verifyFamily` cannot see it — but
/// two gold atoms cannot be 0.004 Å apart. It is the shape a mis-expanded
/// asymmetric unit takes, so the model contract has to be the thing that
/// refuses it (backlog #14), and this is the case that proves the symmetry
/// checks alone were never going to.
private let goldDuplicateAtom = """
data_gold_duplicate
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
Au2 Au 0.0009 0.0000 0.0000 1.0
Au3 Au 0.5000 0.5000 0.0000 1.0
Au4 Au 0.5000 0.0000 0.5000 1.0
Au5 Au 0.0000 0.5000 0.5000 1.0
"""

// MARK: - The symmetry-expansion path (backlog #14)
//
// Every "must admit" case above supplies its cell contents explicitly, so
// `expand` never runs on them — which is exactly why this defect survived the
// first fixture. These cases go through the symop loop, and they assert the
// *site count*, because an over-expanded cell is admitted with the right
// symmetry and the wrong structure factors: site multiplicity multiplies
// straight into |F|², and nothing else in the pipeline notices.

/// P6₃/mmc — all 24 operators, magnesium's single 2c site at (⅓, ⅔, ¼).
/// Must expand to exactly 2 atoms at every precision a real CIF is written to.
private func magnesiumSymopLoop(decimals: Int) -> String {
    func r(_ value: Double) -> String { String(format: "%.\(decimals)f", value) }
    return """
    data_magnesium_symop
    _cell_length_a 3.2094
    _cell_length_b 3.2094
    _cell_length_c 5.2108
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
    'y,x,-z'
    'x-y,-y,-z'
    '-x,-x+y,-z'
    '-y,-x,-z+1/2'
    '-x+y,y,-z+1/2'
    'x,x-y,-z+1/2'
    '-x,-y,-z'
    'y,-x+y,-z'
    'x-y,x,-z'
    'x,y,-z+1/2'
    '-y,x-y,-z+1/2'
    '-x+y,-x,-z+1/2'
    '-y,-x,z'
    '-x+y,y,z'
    'x,x-y,z'
    'y,x,z+1/2'
    'x-y,-y,z+1/2'
    '-x,-x+y,z+1/2'
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    _atom_site_occupancy
    Mg1 Mg \(r(1.0 / 3.0)) \(r(2.0 / 3.0)) 0.2500 1.0
    """
}

/// Fm-3m gold from one corner site plus the full 24-operator coset — the cubic
/// mirror of the magnesium case. Must expand to exactly 4 atoms. Its
/// coordinates are exact halves, so it isolates operator handling from
/// rounding entirely.
private let goldSymopLoop = """
data_gold_symop
_cell_length_a 4.0782
_cell_length_b 4.0782
_cell_length_c 4.0782
_cell_angle_alpha 90.0
_cell_angle_beta  90.0
_cell_angle_gamma 90.0
loop_
_space_group_symop_operation_xyz
'x,y,z'
'-x,-y,z'
'-x,y,-z'
'x,-y,-z'
'z,x,y'
'z,-x,-y'
'-z,-x,y'
'-z,x,-y'
'y,z,x'
'-y,z,-x'
'y,-z,-x'
'-y,-z,x'
'x,y+1/2,z+1/2'
'-x,-y+1/2,z+1/2'
'-x,y+1/2,-z+1/2'
'x,-y+1/2,-z+1/2'
'x+1/2,y,z+1/2'
'-x+1/2,-y,z+1/2'
'-x+1/2,y,-z+1/2'
'x+1/2,-y,-z+1/2'
'x+1/2,y+1/2,z'
'-x+1/2,-y+1/2,z'
'-x+1/2,y+1/2,-z'
'x+1/2,-y+1/2,-z'
loop_
_atom_site_label
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
_atom_site_occupancy
Au1 Au 0.0000 0.0000 0.0000 1.0
"""

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

// MARK: - Cases from the adversarial review of the #14 fix
//
// Every case below refuted a version of the fix that had already passed the
// whole suite above. They are the fixture's most valuable half.

/// The magnesium symop case with ⅓ and ⅔ **truncated** rather than rounded —
/// `0.333/0.666`, `0.3333/0.6666`. Truncation error reaches a full ulp of the
/// last decimal, twice what rounding allows, and a merge tolerance derived
/// from `0.5·10⁻ᵈ` therefore fails to merge. The first fix rejected this at 3,
/// 4 and 6 decimals while admitting it at 5 and 7 — erratic, precision-
/// dependent behaviour on one of the two ordinary spellings of a shipped
/// built-in structure.
private func magnesiumSymopTruncated(decimals: Int) -> String {
    let scale = pow(10.0, Double(decimals))
    func truncate(_ value: Double) -> String {
        String(format: "%.\(decimals)f", (value * scale).rounded(.down) / scale)
    }
    return magnesiumSymopLoop(decimals: decimals)
        .replacingOccurrences(
            of: "Mg1 Mg \(String(format: "%.\(decimals)f", 1.0 / 3.0))"
                + " \(String(format: "%.\(decimals)f", 2.0 / 3.0))",
            with: "Mg1 Mg \(truncate(1.0 / 3.0)) \(truncate(2.0 / 3.0))"
        )
}

/// FCC gold with a face-centre site displaced along x, **everything written to
/// 2 decimals**. The displacement is real (0.163 Å at shift 0.54 — the scale of
/// a ferroelectric off-centering), but at 2 decimals it is indistinguishable
/// from rounding, so the only honest answer is to refuse.
///
/// This is the case that killed deriving `symmetryPositionTolerance` from the
/// file's own precision: that let the coarse coordinate *breaking* the symmetry
/// supply the excuse for tolerating the break, and admitted this as full m-3m
/// cubic — fabricating an IPF colour key, the exact outcome the point-group
/// gate exists to prevent.
private func goldCoarseShifted(_ x: String) -> String {
    """
    data_gold_coarse
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
    Au1 Au 0.00 0.00 0.00 1.0
    Au2 Au \(x) 0.50 0.00 1.0
    Au3 Au 0.50 0.00 0.50 1.0
    Au4 Au 0.00 0.50 0.50 1.0
    """
}

/// Two genuinely distinct full-occupancy sites 0.20 Å apart along a long c
/// axis. Unphysical, so rejecting is right — but an earlier 0.30 Å merge cap
/// *merged* them at 2 decimals and admitted the cell one atom short, silently.
/// Under-population corrupts structure factors exactly as over-population
/// does, so the answer must not depend on how many decimals were typed.
private func twoCloseSites(_ z1: String, _ z2: String) -> String {
    """
    data_two_close
    _cell_length_a 3.2094
    _cell_length_b 3.2094
    _cell_length_c 20.0000
    _cell_angle_alpha 90.0
    _cell_angle_beta  90.0
    _cell_angle_gamma 120.0
    loop_
    _symmetry_equiv_pos_as_xyz
    'x,y,z'
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    _atom_site_occupancy
    Mg1 Mg 0.0000 0.0000 \(z1) 1.0
    Mg2 Mg 0.0000 0.0000 \(z2) 1.0
    """
}

/// Split-site disorder: both 2c columns split into half-occupied pairs
/// straddling the mirror, 0.42 Å apart. Ordinary refinement practice, and
/// genuinely hexagonal — the 6₃ screw still maps the site set onto itself.
/// A close-contact check with no occupancy awareness rejects this, telling a
/// crystallographer their correct disorder model is over-populated.
private let splitSiteDisorder = """
data_split_site
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
Mg1 Mg 0.3333333 0.6666667 0.2100 0.5
Mg2 Mg 0.3333333 0.6666667 0.2900 0.5
Mg3 Mg 0.6666667 0.3333333 0.7100 0.5
Mg4 Mg 0.6666667 0.3333333 0.7900 0.5
"""

/// Genuinely cubic gold spelled with coordinates outside [0,1), which is legal
/// CIF. The P1 path used to keep them raw, which hid close contacts from a
/// detector that only searches the neighbouring cells.
private let outOfRangeCoordinates = """
data_out_of_range
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
Au1 Au 1.0000 1.0000 1.0000 1.0
Au2 Au 1.5000 1.5000 1.0000 1.0
Au3 Au -0.5000 0.0000 0.5000 1.0
Au4 Au 0.0000 -0.5000 -0.5000 1.0
"""

/// 2H-WS₂, the Schutte/de Boer/Jellinek 1987 refinement (J. Solid State Chem.
/// 70, 207–209; a = 3.1532, c = 12.323, z(S) = 0.6225), written as the six
/// explicit sites with no symmetry loop — detection has to find the 6₃ screw
/// in a TWO-SPECIES basis, which no other admitted case exercises: Mg's screw
/// maps like sites to like, here it must map W→W and S→S at different z.
private let ws2Schutte = """
data_ws2_2h
_cell_length_a 3.1532
_cell_length_b 3.1532
_cell_length_c 12.323
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
W1 W 0.333333 0.666667 0.250000 1.0
W2 W 0.666667 0.333333 0.750000 1.0
S1 S 0.333333 0.666667 0.622500 1.0
S2 S 0.333333 0.666667 0.877500 1.0
S3 S 0.666667 0.333333 0.377500 1.0
S4 S 0.666667 0.333333 0.122500 1.0
"""

private let cases: [Case] = [
    Case(name: "alpha_quartz_P3221", cif: quartz, rejection: .symmetry,
         why: "trigonal (3-fold only) in the hexagonal setting"),
    Case(name: "calcite_R-3c", cif: calcite, rejection: .symmetry,
         why: "trigonal (-3m) in the hexagonal setting"),
    Case(name: "tetragonal_accidental_cubic_metric", cif: accidentallyCubicMetric,
         rejection: .symmetry,
         why: "cubic metric by coincidence, no 3-fold along <111>"),
    Case(name: "gold_fcc_P1", cif: goldP1, expectedSymmetry: .cubic, expectedSiteCount: 4,
         why: "genuinely cubic, no symmetry loop supplied"),
    Case(name: "silicon_diamond_Fd-3m", cif: siliconDiamond, expectedSymmetry: .cubic,
         expectedSiteCount: 8, why: "cubic <111> 3-fold carries a translation"),
    // Precision sweep. Magnesium is genuinely P6_3/mmc at every precision; a
    // check that only passes on 7-decimal coordinates is measuring rounding,
    // not symmetry. 3 decimals is entirely ordinary in published CIFs.
    Case(name: "magnesium_hcp_3dp", cif: magnesiumHCP(decimals: 3),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "hexagonal via the 6-3 screw, coordinates at 3 decimals"),
    Case(name: "magnesium_hcp_4dp", cif: magnesiumHCP(decimals: 4),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "hexagonal via the 6-3 screw, coordinates at 4 decimals"),
    Case(name: "magnesium_hcp_7dp", cif: magnesiumHCP(decimals: 7),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "hexagonal via the 6-3 screw, t = (0,0,1/2)"),
    Case(name: "magnesium_refined_occupancies", cif: magnesiumRefinedOccupancies,
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "equivalent sites differ by 0.005 occupancy — refinement noise"),
    Case(name: "ws2_2h_schutte1987", cif: ws2Schutte,
         expectedSymmetry: .hexagonal, expectedSiteCount: 6,
         why: "hexagonal 6-3 screw over a TWO-species basis (W 2c + S 4f)"),
    // Laue class within the family: one generator is not the group.
    Case(name: "fluorapatite_P63m_laue_6overm", cif: fluorapatite, rejection: .symmetry,
         why: "Laue 6/m — 6-fold along c but no 2-fold along a"),
    Case(name: "pyrite_Pa-3_laue_m-3", cif: pyrite, rejection: .symmetry,
         why: "Laue m-3 — <111> 3-fold but no 4-fold along c"),
    Case(name: "cdi2_P-3m1_trigonal", cif: cadmiumIodide, rejection: .symmetry,
         why: "trigonal — 6-fold would swap columns at different z"),
    Case(name: "gold_shifted_site_0p05_real_break", cif: goldShiftedSite(shift: 0.05),
         rejection: .symmetry,
         why: "0.05 fractional (0.20 A) displacement of a face-centre site — a real break"),
    Case(name: "gold_shifted_site_0p0009_below_tolerance", cif: goldShiftedSite(shift: 0.0009),
         expectedSymmetry: .cubic, expectedSiteCount: 4,
         why: "0.0009 fractional (0.0037 A) is under the symmetry tolerance by design"),
    // Backlog #14: the symmetry-expansion path, which no case above reaches.
    Case(name: "gold_duplicate_atom_rejected_by_model", cif: goldDuplicateAtom,
         rejection: .invalidModel(code: "atomic_sites_too_close"),
         why: "cubic to every symmetry test, but two Au 0.0037 A apart is not a structure"),
    Case(name: "magnesium_symop_loop_2dp", cif: magnesiumSymopLoop(decimals: 2),
         rejection: .precision,
         why: "2 decimals cannot resolve the 6-fold from its own rounding — refuse, "
              + "do not widen the gate"),
    Case(name: "magnesium_symop_loop_3dp", cif: magnesiumSymopLoop(decimals: 3),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "24 operators on one 2c site, coordinates at 3 decimals — the #14 case"),
    Case(name: "magnesium_symop_loop_4dp", cif: magnesiumSymopLoop(decimals: 4),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "24 operators on one 2c site, coordinates at 4 decimals"),
    Case(name: "magnesium_symop_loop_7dp", cif: magnesiumSymopLoop(decimals: 7),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "24 operators on one 2c site, coordinates at 7 decimals"),
    Case(name: "gold_symop_loop_Fm-3m", cif: goldSymopLoop,
         expectedSymmetry: .cubic, expectedSiteCount: 4,
         why: "24 operators on one corner site — exact halves, expansion only"),
    // Adversarial-review regressions. Each of these passed nothing above.
    Case(name: "magnesium_symop_truncated_3dp", cif: magnesiumSymopTruncated(decimals: 3),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "1/3, 2/3 TRUNCATED to 3 decimals — the other ordinary CIF spelling"),
    Case(name: "magnesium_symop_truncated_4dp", cif: magnesiumSymopTruncated(decimals: 4),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "truncated to 4 decimals — a rounding-only error bound misses this"),
    Case(name: "magnesium_symop_truncated_6dp", cif: magnesiumSymopTruncated(decimals: 6),
         expectedSymmetry: .hexagonal, expectedSiteCount: 2,
         why: "truncated to 6 decimals — precise data, and it must not be erratic"),
    Case(name: "gold_coarse_shift_0p163A_unresolvable", cif: goldCoarseShifted("0.54"),
         rejection: .precision,
         why: "0.163 A break written at 2 decimals — must NOT be admitted as m-3m cubic"),
    Case(name: "gold_coarse_shift_0p041A_unresolvable", cif: goldCoarseShifted("0.51"),
         rejection: .precision,
         why: "0.041 A break at 2 decimals — same verdict at the small end of the band"),
    Case(name: "two_close_sites_2dp", cif: twoCloseSites("0.11", "0.12"),
         rejection: .invalidModel(code: "atomic_sites_too_close"),
         why: "0.20 A apart at full occupancy — reject, never silently merge to one atom"),
    Case(name: "two_close_sites_4dp", cif: twoCloseSites("0.1100", "0.1200"),
         rejection: .invalidModel(code: "atomic_sites_too_close"),
         why: "the same structure at 4 decimals — the verdict must not depend on spelling"),
    Case(name: "split_site_disorder_0p42A", cif: splitSiteDisorder,
         expectedSymmetry: .hexagonal, expectedSiteCount: 4,
         why: "half-occupied split sites 0.42 A apart — routine disorder, must be admitted"),
    Case(name: "coordinates_outside_unit_cell", cif: outOfRangeCoordinates,
         expectedSymmetry: .cubic, expectedSiteCount: 4,
         why: "legal CIF spelling outside [0,1); must be wrapped, not left raw"),
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
            switch (result, testCase.expectedSymmetry) {
            case (.success(let model), .none):
                failures.append(
                    "\(testCase.name): expected REJECT (\(testCase.why)) but was admitted "
                    + "as .\(model.symmetry.rawValue) with \(model.crystal.sites.count) sites"
                )

            case (.failure(let error), .none):
                let expected = testCase.rejection ?? .symmetry
                let described = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                switch (expected, error) {
                case (.symmetry, CIFImportError.symmetryNotSupportedByStructure):
                    print("PASS: rejected \(testCase.name) — \(testCase.why)")
                case (.precision, CIFImportError.symmetryUnresolvableAtWrittenPrecision):
                    print("PASS: rejected \(testCase.name) as unresolvable — \(testCase.why)")
                case (.invalidModel(let code), CIFImportError.invalidModel(let issues)):
                    // The message is the user-facing half of this contract, so
                    // match on it rather than only on the case: an issue that
                    // stops naming its cause has regressed even if it fires.
                    guard issues.contains(where: { $0.contains("interatomic") || $0.contains(code) })
                    else {
                        failures.append(
                            "\(testCase.name): rejected by the model contract, but no issue "
                            + "matched \"\(code)\" — \(issues.joined(separator: "; "))"
                        )
                        continue
                    }
                    print("PASS: rejected \(testCase.name) by the model contract — \(testCase.why)")
                default:
                    failures.append(
                        "\(testCase.name): rejected, but for the wrong reason — \(described)"
                    )
                }

            case (.success(let model), .some(let expectedSymmetry)):
                guard model.symmetry == expectedSymmetry else {
                    failures.append(
                        "\(testCase.name): admitted as .\(model.symmetry.rawValue), "
                        + "expected .\(expectedSymmetry.rawValue)"
                    )
                    continue
                }
                if let expectedSiteCount = testCase.expectedSiteCount,
                   model.crystal.sites.count != expectedSiteCount {
                    failures.append(
                        "\(testCase.name): admitted as .\(model.symmetry.rawValue) but the cell "
                        + "holds \(model.crystal.sites.count) atoms, expected \(expectedSiteCount)"
                        + " — site multiplicity goes straight into the structure factors"
                    )
                    continue
                }
                // Universal invariant, not a per-case expectation: an admitted
                // model's sites live in the unit cell. Raw out-of-range
                // coordinates are invisible to any neighbour-cell search.
                let outside = model.crystal.sites.filter {
                    let f = [$0.fractional.x, $0.fractional.y, $0.fractional.z]
                    return f.contains { $0 < 0 || $0 >= 1 }
                }
                if !outside.isEmpty {
                    failures.append(
                        "\(testCase.name): \(outside.count) admitted site(s) lie outside "
                        + "[0,1) in fractional coordinates"
                    )
                    continue
                }
                let sites = testCase.expectedSiteCount.map { ", \($0) sites" } ?? ""
                print("PASS: admitted \(testCase.name) as .\(model.symmetry.rawValue)\(sites)"
                      + " — \(testCase.why)")

            case (.failure(let error), .some):
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
