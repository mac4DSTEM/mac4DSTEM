import XCTest
import DiffractoCore
import DiffractoScattering
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Coverage for `CIFImport`: the local-file CIF parser that produces a
/// validated `.imported` `CrystalModel`. Every fixture is a real CIF text
/// literal (no binary fixtures), matching the app's built-in presets where
/// convenient so results can be checked against `CrystalPresets.gold`/`CrystalPresets.silicon`.
final class CIFImportTests: XCTestCase {

    // MARK: - Helpers

    private func siteKey(_ site: AtomSite) -> String {
        func round(_ v: Double) -> Double { (v * 1e6).rounded() / 1e6 }
        return "\(site.z):\(round(site.fractional.x)),\(round(site.fractional.y)),\(round(site.fractional.z)):\(round(site.occupancy))"
    }

    private func sortedKeys(_ sites: [AtomSite]) -> [String] {
        sites.map(siteKey).sorted()
    }

    /// The kit's reader refused the file (its `CIFImportError`, wrapped by the app as `.cif`).
    private func assertThrows(
        _ cif: String, fileBaseName: String = "test", expected: CIFImportError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertThrows(cif, fileBaseName: fileBaseName, expected: CIFModelImportError.cif(expected), file: file, line: line)
    }

    /// The app's own refusal (`CIFModelImportError`: an element outside the scattering table, a failed model contract).
    private func assertThrows(
        _ cif: String, fileBaseName: String = "test", expected: CIFModelImportError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CIFModelImport.crystalModel(from: cif, fileBaseName: fileBaseName), file: file, line: line
        ) { error in
            XCTAssertEqual(error as? CIFModelImportError, expected, file: file, line: line)
        }
    }

    // MARK: - Gold FCC, P1 style (all sites listed explicitly)

    private let goldP1CIF = """
    data_gold
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Au1 Au 0.0 0.0 0.0
    Au2 Au 0.5 0.5 0.0
    Au3 Au 0.5 0.0 0.5
    Au4 Au 0.0 0.5 0.5
    """

    /// A generic VESTA block name falls back to the file name; a real block
    /// name is kept; an empty one falls back. Break-first: the VESTA pattern
    /// check removed makes the first assertion return "VESTA_phase_1", so
    /// this must go red.
    func testGenericVESTABlockNameFallsBackToTheFileName() {
        XCTAssertEqual(CIFImport.displayName(dataBlockName: "VESTA_phase_1", fileBaseName: "T1_thronsen2024"),
                       "T1_thronsen2024")
        XCTAssertEqual(CIFImport.displayName(dataBlockName: "Al_Fm-3m", fileBaseName: "Al"), "Al_Fm-3m")
        XCTAssertEqual(CIFImport.displayName(dataBlockName: "", fileBaseName: "Al"), "Al")
        XCTAssertEqual(CIFImport.displayName(dataBlockName: nil, fileBaseName: "Al"), "Al")
        XCTAssertEqual(CIFImport.displayName(dataBlockName: "VESTA_phase_1_modified", fileBaseName: "x"),
                       "VESTA_phase_1_modified", "only the exact placeholder is generic")
    }

    func testGoldP1ReproducesBuiltInGoldCellAndSites() throws {
        let model = try CIFModelImport.crystalModel(from: goldP1CIF, fileBaseName: "gold")
        XCTAssertEqual(model.source, .imported)
        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.structure.cell.a, CrystalPresets.gold.cell.a, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.b, CrystalPresets.gold.cell.b, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.c, CrystalPresets.gold.cell.c, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.alphaDeg, CrystalPresets.gold.cell.alphaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.betaDeg, CrystalPresets.gold.cell.betaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.gammaDeg, CrystalPresets.gold.cell.gammaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.structure.sites.count, 4)
        XCTAssertEqual(sortedKeys(model.structure.sites), sortedKeys(CrystalPresets.gold.sites))
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
    }

    // MARK: - Symmetry expansion: one asymmetric-unit atom -> full FCC basis

    private let goldSymmetryCIF = """
    data_gold_symm
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _symmetry_equiv_pos_as_xyz
    'x, y, z'
    'x+1/2, y+1/2, z'
    'x+1/2, y, z+1/2'
    'x, y+1/2, z+1/2'
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Au1 Au 0 0 0
    """

    func testSymmetryLoopExpandsSingleAtomToFullFCCBasisAndDedupes() throws {
        let model = try CIFModelImport.crystalModel(from: goldSymmetryCIF, fileBaseName: "gold_symm")
        XCTAssertEqual(model.structure.sites.count, 4, "expected face-centering to produce exactly 4 distinct sites")
        XCTAssertEqual(sortedKeys(model.structure.sites), sortedKeys(CrystalPresets.gold.sites))
    }

    // MARK: - Silicon diamond: 8 sites

    private let siliconCIF = """
    data_silicon
    _cell_length_a 5.4309
    _cell_length_b 5.4309
    _cell_length_c 5.4309
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Si1 Si 0.0  0.0  0.0
    Si2 Si 0.5  0.5  0.0
    Si3 Si 0.5  0.0  0.5
    Si4 Si 0.0  0.5  0.5
    Si5 Si 0.25 0.25 0.25
    Si6 Si 0.75 0.75 0.25
    Si7 Si 0.75 0.25 0.75
    Si8 Si 0.25 0.75 0.75
    """

    func testSiliconDiamondGivesEightSites() throws {
        let model = try CIFModelImport.crystalModel(from: siliconCIF, fileBaseName: "silicon")
        XCTAssertEqual(model.structure.sites.count, 8)
        XCTAssertEqual(sortedKeys(model.structure.sites), sortedKeys(CrystalPresets.silicon.sites))
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
    }

    // MARK: - Standard-uncertainty parentheses

    func testStandardUncertaintyParenthesesAreStripped() throws {
        let cif = """
        data_gold_su
        _cell_length_a 4.0782(3)
        _cell_length_b 4.0782(3)
        _cell_length_c 4.0782(3)
        _cell_angle_alpha 90.0(0)
        _cell_angle_beta 90.0(0)
        _cell_angle_gamma 90.0(0)
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Au1 Au 0.0 0.0 0.0
        """
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "gold_su")
        XCTAssertEqual(model.structure.cell.a, 4.0782, accuracy: 1e-9)
        XCTAssertEqual(model.structure.cell.alphaDeg, 90.0, accuracy: 1e-9)
    }

    // MARK: - Rejected point group

    func testOrthorhombicCellImportsUnreducedAndRefusesOrientationMapping() throws {
        let cif = """
        data_orthorhombic
        _cell_length_a 5.0
        _cell_length_b 6.0
        _cell_length_c 7.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Fe1 Fe 0 0 0
        """
        // BEHAVIOUR CHANGED 2026-09-11, deliberately. This cell used to be
        // refused at import. It now loads as `.identity` — "Unreduced" — so a
        // structure the app cannot orientation-map can still be used for phase
        // IDENTIFICATION, which needs a cell and a basis and no point group.
        // β″ in Al-Mg-Si is monoclinic C2/m, and refusing here blocked the
        // phase mapping in archived docs/v3-features.md#vector-matching before it started.
        //
        // Both halves are asserted, because admitting the model without the
        // refusal below would let `identity.ipfColor` draw |x|,|y|,|z| as RGB —
        // not a wrong IPF key, but no key at all wearing the look of one.
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "ortho")
        XCTAssertEqual(model.symmetry, .identity, "an orthorhombic cell imports as Unreduced")
        XCTAssertEqual(model.structure.cell.a, 5.0, accuracy: 1e-9, "the cell is read, not coerced")
        XCTAssertEqual(model.structure.cell.c, 7.0, accuracy: 1e-9)

        // The crystal is VALID. What it cannot do is orientation mapping, and
        // those are deliberately different properties: a first attempt recorded
        // this as a validation issue, which made `CIFModelImport.crystalModel` throw
        // `.invalidModel` — so the structure never loaded at all and the change
        // achieved nothing. Caught by probe before it shipped.
        XCTAssertTrue(model.isUsable, "the cell, basis and structure factors are all fine")
        XCTAssertTrue(model.validationIssues.isEmpty)
        XCTAssertFalse(
            model.supportsOrientationMapping,
            "AppState.resolvedACOMModel gates on this, so ACOM must not accept the model"
        )
        XCTAssertNotNil(
            model.orientationMappingIssue,
            "the refusal must carry a reason for ACOMSession.modelSelectionIssue to surface"
        )
        // And the half that makes admitting it worthwhile at all: phase
        // identification needs reflections, and gets them.
        XCTAssertFalse(try model.structure.kinematicReflections(kMax: 1.6).kept.isEmpty)
    }

    // MARK: - Element with no scattering factor

    func testElementBeyondScatteringTableIsRejected() {
        // Rf (Z=104) is a real, recognizable chemical symbol but has no
        // Lobato scattering-factor parameters (table only covers 1...103).
        let cif = """
        data_rutherfordium
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Rf1 Rf 0 0 0
        """
        assertThrows(cif, fileBaseName: "rf", expected: .unsupportedElement(symbol: "Rf", z: 104))
    }

    // MARK: - Malformed-input error cases

    func testMissingCellTagNamesTheTag() {
        let cif = """
        data_missing_tag
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Fe1 Fe 0 0 0
        """
        assertThrows(cif, fileBaseName: "missing", expected: .missingTag("_cell_angle_gamma"))
    }

    func testUnparsableNumberNamesTagAndValue() {
        let cif = """
        data_bad_number
        _cell_length_a abc
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Fe1 Fe 0 0 0
        """
        assertThrows(cif, fileBaseName: "badnum",
                     expected: .unparsableNumber(tag: "_cell_length_a", value: "abc"))
    }

    func testUnknownElementSymbolNamesSiteAndSymbol() {
        let cif = """
        data_bogus_element
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        X1 Xx 0 0 0
        """
        assertThrows(cif, fileBaseName: "bogus",
                     expected: .unknownElementSymbol("Xx", atomSiteLabel: "X1"))
    }

    func testNoAtomSiteLoopIsRejected() {
        let cif = """
        data_no_atoms
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        """
        assertThrows(cif, fileBaseName: "noatoms", expected: .noAtomSites)
    }

    func testUnsupportedSymmetryOperationNamesTheExpression() {
        let cif = """
        data_bad_symmetry
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _symmetry_equiv_pos_as_xyz
        x^2,y,z
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Fe1 Fe 0 0 0
        """
        assertThrows(cif, fileBaseName: "badsymm",
                     expected: .unsupportedSymmetryOperation("x^2,y,z"))
    }

    /// Upstream finding F5 (macTEM's CIF-import refuter, 2026-10-14): `x/2` was read as `x + 2` (the `/2` left after `x`
    /// parsed as the number 2, a translation). A crystallographic operation has an integer matrix, so a fractional
    /// coefficient (`x/2`, `1/2x`), a malformed fraction (`/2`, `2/`, `1//2`) or a term run into a variable (`xy`, `x2`,
    /// `x.5`; refuter RF5) is refused and named, never read as something else; fractions and decimals still parse.
    func testFractionalCoefficientsAndMalformedFractionsAreRefusedNotMisread() throws {
        func cif(_ op: String) -> String {
            """
            data_symop
            _cell_length_a 4.0
            _cell_length_b 4.0
            _cell_length_c 4.0
            _cell_angle_alpha 90
            _cell_angle_beta 90
            _cell_angle_gamma 90
            loop_
            _symmetry_equiv_pos_as_xyz
            x,y,z
            \(op)
            loop_
            _atom_site_label
            _atom_site_type_symbol
            _atom_site_fract_x
            _atom_site_fract_y
            _atom_site_fract_z
            Fe1 Fe 0.1 0.2 0.3
            """
        }
        for bad in ["x/2,y,z", "1/2x,y,z", "x,y/5,z", "x,y,/2", "2/,y,z", "x,y,z+1//2",
                    "xy,y,z", "x2,y,z", "x.5,y,z", "-x/2+1/2,y,z"] {
            assertThrows(cif(bad), fileBaseName: "symop", expected: .unsupportedSymmetryOperation(bad))
        }
        // Valid spellings still import: a triclinic cell, so no family check asks for symmetry these lack.
        for good in ["x+1/2,y,z", "1/2+x,1/2+y,z", "x,y,z+0.5", "-x,-y,-z", "-x+1,-y,-z+1/2"] {
            let text = cif(good).replacingOccurrences(of: "_cell_length_b 4.0", with: "_cell_length_b 5.0")
                .replacingOccurrences(of: "_cell_length_c 4.0", with: "_cell_length_c 6.0")
                .replacingOccurrences(of: "_cell_angle_alpha 90", with: "_cell_angle_alpha 80")
                .replacingOccurrences(of: "_cell_angle_beta 90", with: "_cell_angle_beta 85")
                .replacingOccurrences(of: "_cell_angle_gamma 90", with: "_cell_angle_gamma 95")
            XCTAssertNoThrow(try CIFModelImport.crystalModel(from: text, fileBaseName: "symop"), good)
        }
    }

    // MARK: - Element symbol derivation from label when type_symbol is absent

    func testElementDerivedFromLabelWhenTypeSymbolMissing() throws {
        let cif = """
        data_label_only
        _cell_length_a 3.5240
        _cell_length_b 3.5240
        _cell_length_c 3.5240
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Ni1 0.0 0.0 0.0
        Ni2+ 0.5 0.5 0.0
        Ni3 0.5 0.0 0.5
        Ni4 0.0 0.5 0.5
        """
        // All four FCC sites are listed, not just two: the importer now checks
        // that a cubic *metric* is backed by a real ⟨111⟩ 3-fold, and a
        // half-populated cell has no such axis. The point of this test is
        // still element-symbol derivation from the label ("Ni2+" → Ni).
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "nickel")
        XCTAssertEqual(model.structure.sites.map(\.z), [28, 28, 28, 28])
    }

    // MARK: - The metric proposes a family; the structure has to confirm it

    /// A trigonal structure is conventionally published in the hexagonal
    /// setting (a = b, γ = 120°) while carrying only a 3-fold along c. Cell
    /// parameters alone therefore admit quartz, calcite, alumina and hematite
    /// as `.hexagonal`, giving them a 12-operator fundamental zone and an IPF
    /// key they do not have. `tools/harnesses/cif-symmetry-test/` covers the full matrix
    /// of accept/reject structures; this pins the user-visible contract.
    ///
    /// CHANGED 2026-10-15 (DiffractoKit 0.0.3, kit item 3; registration P4). This test was
    /// `testTrigonalCellInHexagonalSettingIsRejectedNotOverSymmetrized` and asserted a refusal
    /// (`symmetryNotSupportedByStructure`). The kit reads the Laue class from the atoms and admits every
    /// class, so the file now IMPORTS, as `.identity` ("Unreduced"): the over-symmetrisation it guarded
    /// against (a 12-operator fundamental zone and an IPF key the structure does not have) is still
    /// impossible, which is what is asserted. Kit plant: DiffractoCoreTests `CIFImportTests`
    /// `testTrigonalInHexagonalAxesIsThreeBarM` (quartz with its operation loop).
    func testTrigonalCellInHexagonalSettingImportsUnreducedNeverHexagonal() throws {
        // α-quartz, P3₂21 — point group 32, 3-fold only.
        let cif = """
        data_alpha_quartz
        _cell_length_a 4.9134
        _cell_length_b 4.9134
        _cell_length_c 5.4052
        _cell_angle_alpha 90.0
        _cell_angle_beta 90.0
        _cell_angle_gamma 120.0
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Si1 Si 0.4697 0.0000 0.0000
        O1 O 0.4135 0.2669 0.1191
        """
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "quartz")
        XCTAssertEqual(model.symmetry, .identity, "a hexagonal metric with 3-fold contents is Unreduced, not 6/mmm")
        XCTAssertNotEqual(model.structure.laueClass, .sixOverMmm)
        XCTAssertFalse(model.supportsOrientationMapping, "no fundamental zone and no IPF key for it")
        XCTAssertTrue(model.isUsable, "the structure still identifies a phase")
    }

    /// The mirror case: a cubic *metric* by coincidence. Tetragonal contents
    /// (4-fold about c, no ⟨111⟩ 3-fold) in a cell whose axes happen to be
    /// equal must not be admitted as `.cubic`.
    ///
    /// CHANGED 2026-10-15 (kit item 3; registration P4): was
    /// `testAccidentallyCubicMetricWithoutA111ThreeFoldIsRejected` and asserted a refusal. It now imports as
    /// `.identity`; never `.cubic` is what is asserted. Kit plant: DiffractoCoreTests `SymmetryDetectionTests`
    /// `testTetragonalAtomsInACubicMetricAre4OverMmm`.
    func testAccidentallyCubicMetricWithoutA111ThreeFoldImportsUnreducedNeverCubic() throws {
        let cif = """
        data_tetragonal_a_equals_c
        _cell_length_a 4.0
        _cell_length_b 4.0
        _cell_length_c 4.0
        _cell_angle_alpha 90.0
        _cell_angle_beta 90.0
        _cell_angle_gamma 90.0
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Ti1 Ti 0.0 0.0 0.0
        O1 O 0.3 0.3 0.0
        """
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "tetra")
        XCTAssertEqual(model.symmetry, .identity, "a cubic metric without the ⟨111⟩ 3-fold is Unreduced, not m-3m")
        XCTAssertNotEqual(model.structure.laueClass, .mThreeBarM)
        XCTAssertFalse(model.supportsOrientationMapping)
    }

    /// The check must allow the rotation to carry a translation, or it would
    /// reject shipped built-in models. HCP magnesium's 6-fold is the 6₃ screw
    /// (t = (0,0,½)); requiring t = 0 would wrongly call it trigonal.
    func testHexagonalViaScrewAxisIsStillAdmitted() throws {
        let cif = """
        data_magnesium
        _cell_length_a 3.2094
        _cell_length_b 3.2094
        _cell_length_c 5.2108
        _cell_angle_alpha 90.0
        _cell_angle_beta 90.0
        _cell_angle_gamma 120.0
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Mg1 Mg 0.3333333 0.6666667 0.25
        Mg2 Mg 0.6666667 0.3333333 0.75
        """
        let model = try CIFModelImport.crystalModel(from: cif, fileBaseName: "magnesium")
        XCTAssertEqual(model.symmetry, .hexagonal)
    }

    // MARK: - Missing symmetry operations (core-crystal-02) and truncated
    // loops (core-crystal-04), both reproduced at runtime 2026-09-01.

    /// Rock-salt MgO's two-site asymmetric unit declaring Fm-3m with no
    /// operator loop. Both sites are invariant under both cubic generators,
    /// so the family verifier cannot catch this shape — before the guard it
    /// imported silently as the CsCl structure.
    private let mgoNoOpsCIF = """
    data_MgO
    _symmetry_space_group_name_H-M 'F m -3 m'
    _space_group_IT_number 225
    _cell_length_a 4.212
    _cell_length_b 4.212
    _cell_length_c 4.212
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Mg 0.0 0.0 0.0
    O 0.5 0.5 0.5
    """

    func testNonP1DeclarationWithoutOperationsIsRefusedNamingTheGroup() {
        assertThrows(
            mgoNoOpsCIF,
            expected: .missingSymmetryOperations(spaceGroup: "F m -3 m")
        )
    }

    func testP1DeclarationWithoutOperationsIsStillAdmitted() throws {
        let declaredP1 = "data_gold\n_symmetry_space_group_name_H-M 'P 1'\n_space_group_IT_number 1\n"
            + goldP1CIF.split(separator: "\n").dropFirst().joined(separator: "\n")
        let model = try CIFModelImport.crystalModel(from: declaredP1, fileBaseName: "gold")
        XCTAssertEqual(model.structure.sites.count, 4)
    }

    /// `?` and `.` are CIF null placeholders — a nulled-out space-group tag
    /// is an absent declaration, not a non-P1 one.
    func testNullSpaceGroupPlaceholderDoesNotRefuse() throws {
        let nulled = "data_gold\n_symmetry_space_group_name_H-M ?\n"
            + goldP1CIF.split(separator: "\n").dropFirst().joined(separator: "\n")
        let model = try CIFModelImport.crystalModel(from: nulled, fileBaseName: "gold")
        XCTAssertEqual(model.structure.sites.count, 4)
    }

    /// An operator loop holding only the identity expands nothing — the same
    /// trap as no loop; with only an IT number, the refusal names the number.
    func testIdentityOnlyOperatorLoopWithNonP1NumberIsRefused() {
        let cif = """
        data_au
        _space_group_IT_number 225
        _cell_length_a 4.0782
        _cell_length_b 4.0782
        _cell_length_c 4.0782
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _space_group_symop_operation_xyz
        'x, y, z'
        loop_
        _atom_site_label
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Au1 0.0 0.0 0.0
        """
        assertThrows(cif, expected: .missingSymmetryOperations(spaceGroup: "No. 225"))
    }

    /// A loop whose value count is not a whole number of rows was previously
    /// floor-divided, silently deleting the partial trailing row — an atom,
    /// in the loop that matters. It must refuse, naming the loop.
    func testTruncatedAtomLoopIsRefusedNotFloorDivided() {
        let truncated = String(goldP1CIF.dropLast(" 0.5".count))
        assertThrows(
            truncated,
            expected: .truncatedLoop(firstTag: "_atom_site_label", columns: 5, values: 19)
        )
    }

    /// Two CIFs with the same file stem get the same id (`imported_<stem>`)
    /// and must NOT get the same content fingerprint; the same text twice
    /// must. The fingerprint is what a recipe uses to tell them apart on
    /// replay (open item "CIF import can silently accept a wrong crystal" (b),
    /// closed 2026-09-05).
    func testSameFilenameDifferentCellHaveOneIDAndTwoFingerprints() throws {
        let gold = try CIFModelImport.crystalModel(from: goldP1CIF, fileBaseName: "phase")
        let again = try CIFModelImport.crystalModel(from: goldP1CIF, fileBaseName: "phase")
        // A multi-line literal strips its common indentation, so the edits
        // below target the runtime text; each is checked to have taken.
        let stretchedText = goldP1CIF.replacingOccurrences(of: "4.0782", with: "4.2000")
        XCTAssertNotEqual(stretchedText, goldP1CIF, "the fixture edit must take, or the test compares a CIF to itself")
        let stretched = try CIFModelImport.crystalModel(from: stretchedText, fileBaseName: "phase")
        XCTAssertEqual(gold.id, stretched.id, "the id is the file stem; that is the collision")
        XCTAssertEqual(gold.contentFingerprint, again.contentFingerprint)
        XCTAssertNotEqual(gold.contentFingerprint, stretched.contentFingerprint)
        XCTAssertEqual(gold.contentFingerprint.count, 16)
        XCTAssertNotNil(UInt64(gold.contentFingerprint, radix: 16), "fixed-width hex, stable across processes")
        // A basis change with the same cell is a different crystal too.
        let threeSitesText = goldP1CIF.replacingOccurrences(of: "Au4 Au 0.0 0.5 0.5", with: "")
        XCTAssertNotEqual(threeSitesText, goldP1CIF, "the fixture edit must take")
        let threeSites = try CIFModelImport.crystalModel(from: threeSitesText, fileBaseName: "phase")
        XCTAssertEqual(threeSites.structure.sites.count, 3)
        XCTAssertNotEqual(gold.contentFingerprint, threeSites.contentFingerprint)
    }
}
