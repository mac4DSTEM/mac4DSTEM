import XCTest
@testable import mac4DSTEM

/// Coverage for `CIFImport`: the local-file CIF parser that produces a
/// validated `.imported` `CrystalModel`. Every fixture is a real CIF text
/// literal (no binary fixtures), matching the app's built-in presets where
/// convenient so results can be checked against `Crystal.gold`/`Crystal.silicon`.
final class CIFImportTests: XCTestCase {

    // MARK: - Helpers

    private func siteKey(_ site: AtomSite) -> String {
        func round(_ v: Double) -> Double { (v * 1e6).rounded() / 1e6 }
        return "\(site.z):\(round(site.fractional.x)),\(round(site.fractional.y)),\(round(site.fractional.z)):\(round(site.occupancy))"
    }

    private func sortedKeys(_ sites: [AtomSite]) -> [String] {
        sites.map(siteKey).sorted()
    }

    private func assertThrows(
        _ cif: String, fileBaseName: String = "test", expected: CIFImportError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CIFImport.crystalModel(from: cif, fileBaseName: fileBaseName), file: file, line: line
        ) { error in
            XCTAssertEqual(error as? CIFImportError, expected, file: file, line: line)
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

    func testGoldP1ReproducesBuiltInGoldCellAndSites() throws {
        let model = try CIFImport.crystalModel(from: goldP1CIF, fileBaseName: "gold")
        XCTAssertEqual(model.source, .imported)
        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.crystal.a, Crystal.gold.a, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.b, Crystal.gold.b, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.c, Crystal.gold.c, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.alphaDeg, Crystal.gold.alphaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.betaDeg, Crystal.gold.betaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.gammaDeg, Crystal.gold.gammaDeg, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.sites.count, 4)
        XCTAssertEqual(sortedKeys(model.crystal.sites), sortedKeys(Crystal.gold.sites))
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
        let model = try CIFImport.crystalModel(from: goldSymmetryCIF, fileBaseName: "gold_symm")
        XCTAssertEqual(model.crystal.sites.count, 4, "expected face-centering to produce exactly 4 distinct sites")
        XCTAssertEqual(sortedKeys(model.crystal.sites), sortedKeys(Crystal.gold.sites))
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
        let model = try CIFImport.crystalModel(from: siliconCIF, fileBaseName: "silicon")
        XCTAssertEqual(model.crystal.sites.count, 8)
        XCTAssertEqual(sortedKeys(model.crystal.sites), sortedKeys(Crystal.silicon.sites))
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
        let model = try CIFImport.crystalModel(from: cif, fileBaseName: "gold_su")
        XCTAssertEqual(model.crystal.a, 4.0782, accuracy: 1e-9)
        XCTAssertEqual(model.crystal.alphaDeg, 90.0, accuracy: 1e-9)
    }

    // MARK: - Rejected point group

    func testOrthorhombicCellIsRejectedAsUnsupportedPointGroup() {
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
        XCTAssertThrowsError(try CIFImport.crystalModel(from: cif, fileBaseName: "ortho")) { error in
            guard case .unsupportedPointGroup = error as? CIFImportError else {
                return XCTFail("expected .unsupportedPointGroup, got \(error)")
            }
        }
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
        let model = try CIFImport.crystalModel(from: cif, fileBaseName: "nickel")
        XCTAssertEqual(model.crystal.sites.map(\.z), [28, 28, 28, 28])
    }

    // MARK: - The metric proposes a family; the structure has to confirm it

    /// A trigonal structure is conventionally published in the hexagonal
    /// setting (a = b, γ = 120°) while carrying only a 3-fold along c. Cell
    /// parameters alone therefore admit quartz, calcite, alumina and hematite
    /// as `.hexagonal`, giving them a 12-operator fundamental zone and an IPF
    /// key they do not have. `tools/cif-symmetry-test/` covers the full matrix
    /// of accept/reject structures; this pins the user-visible contract.
    func testTrigonalCellInHexagonalSettingIsRejectedNotOverSymmetrized() {
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
        XCTAssertThrowsError(try CIFImport.crystalModel(from: cif, fileBaseName: "quartz")) { error in
            guard case .symmetryNotSupportedByStructure = error as? CIFImportError else {
                return XCTFail("expected symmetryNotSupportedByStructure, got \(error)")
            }
        }
    }

    /// The mirror case: a cubic *metric* by coincidence. Tetragonal contents
    /// (4-fold about c, no ⟨111⟩ 3-fold) in a cell whose axes happen to be
    /// equal must not be admitted as `.cubic`.
    func testAccidentallyCubicMetricWithoutA111ThreeFoldIsRejected() {
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
        XCTAssertThrowsError(try CIFImport.crystalModel(from: cif, fileBaseName: "tetra")) { error in
            guard case .symmetryNotSupportedByStructure = error as? CIFImportError else {
                return XCTFail("expected symmetryNotSupportedByStructure, got \(error)")
            }
        }
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
        let model = try CIFImport.crystalModel(from: cif, fileBaseName: "magnesium")
        XCTAssertEqual(model.symmetry, .hexagonal)
    }
}
