import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// S13 (2026-09-30 night) — CIF trust. A CIF that names a space group by its
/// IT number but lists FEWER symmetry operations than that group has in the
/// conventional setting was expanded with what it listed: rock salt written
/// with only its 48 point operations (no F-centring) imported as the CsCl
/// structure, cubic and m-3m-consistent, so every downstream check passed
/// (Gate B escape E2). Diagnosis and reproducing CIFs: session scratchpad
/// `s13/diagnosis.md`.
final class CIFSpaceGroupOrderTests: XCTestCase {

    // MARK: - Fixtures

    /// The 48 point operations of m-3m: every signed permutation of x, y, z.
    private static let pointOps: [String] = {
        var out: [String] = []
        let perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for perm in perms {
            for signs in 0..<8 {
                let parts = (0..<3).map { axis -> String in
                    let negative = (signs >> axis) & 1 == 1
                    return (negative ? "-" : "") + ["x", "y", "z"][perm[axis]]
                }
                out.append(parts.joined(separator: ","))
            }
        }
        return out
    }()

    /// The three F-centring translations, appended to a point operation.
    private static func centred(_ op: String, _ index: Int) -> String {
        let t: [[String]] = [["", "", ""], ["1/2", "1/2", "0"], ["1/2", "0", "1/2"], ["0", "1/2", "1/2"]]
        let comps = op.split(separator: ",").map(String.init)
        return zip(comps, t[index]).map { c, s in s.isEmpty || s == "0" ? c : "\(c)+\(s)" }.joined(separator: ",")
    }

    /// All 192 operations of Fm-3m in its conventional cell.
    private static var fm3mFull: [String] {
        (0..<4).flatMap { c in pointOps.map { centred($0, c) } }
    }

    private func loop(_ ops: [String]) -> String {
        "loop_\n_symmetry_equiv_pos_as_xyz\n" + ops.map { "'\($0)'" }.joined(separator: "\n") + "\n"
    }

    /// Rock salt: Mg at 0,0,0 and O at ½,½,½ under whatever operations are listed.
    private func mgo(ops: [String], itNumber: Int?, angle: Int = 90) -> String {
        let it = itNumber.map { "_symmetry_Int_Tables_number \($0)\n" } ?? ""
        return """
        data_MgO
        _symmetry_space_group_name_H-M 'F m -3 m'
        \(it)_cell_length_a 4.2120
        _cell_length_b 4.2120
        _cell_length_c 4.2120
        _cell_angle_alpha \(angle)
        _cell_angle_beta \(angle)
        _cell_angle_gamma \(angle)
        \(loop(ops))loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Mg1 Mg 0.0 0.0 0.0
        O1 O 0.5 0.5 0.5

        """
    }

    private func assertThrows(
        _ cif: String, expected: CIFImportError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CIFImport.crystalModel(from: cif, fileBaseName: "t"), file: file, line: line
        ) { error in
            XCTAssertEqual(error as? CIFImportError, expected, file: file, line: line)
        }
    }

    // MARK: - The order table

    func testOrderTableSpotChecksAgainstInternationalTables() {
        // number: general-position operation count in the conventional setting.
        let known: [Int: Int] = [
            1: 1, 2: 2, 5: 4, 12: 8, 14: 4, 15: 8, 19: 4, 22: 16, 62: 8, 63: 16, 69: 32,
            70: 32, 74: 16, 88: 16, 123: 16, 139: 32, 141: 32, 143: 3, 146: 9, 148: 18, 155: 18,
            166: 36, 167: 36, 168: 6, 176: 12, 194: 24, 196: 48, 198: 12, 199: 24, 202: 96,
            204: 48, 205: 24, 206: 48, 216: 96, 220: 48, 221: 48, 225: 192, 227: 192,
            228: 192, 229: 96, 230: 96,
        ]
        for (number, order) in known {
            XCTAssertEqual(CIFImport.spaceGroupOrder(number), order, "space group \(number)")
        }
    }

    func testOrderTableCoversExactlyTheTwoHundredThirtyGroups() {
        XCTAssertNil(CIFImport.spaceGroupOrder(0))
        XCTAssertNil(CIFImport.spaceGroupOrder(231))
        XCTAssertNil(CIFImport.spaceGroupOrder(-4))
        let orders = (1...230).map { CIFImport.spaceGroupOrder($0) }
        XCTAssertFalse(orders.contains(nil))
        // Every general position has a multiplicity of the form point group × centring,
        // so only these values occur in ITA; a typo in a range lands outside the set.
        let allowed: Set<Int> = [1, 2, 3, 4, 6, 8, 9, 12, 16, 18, 24, 32, 36, 48, 96, 192]
        XCTAssertTrue(Set(orders.compactMap { $0 }).isSubset(of: allowed))
        // How many of the 230 groups have each order, counted from ITA's
        // Bravais-lattice and crystal-class lists rather than from the ranges under test.
        var histogram: [Int: Int] = [:]
        for order in orders.compactMap({ $0 }) { histogram[order, default: 0] += 1 }
        XCTAssertEqual(histogram[192], 4, "Fm-3m Fm-3c Fd-3m Fd-3c")
        XCTAssertEqual(histogram[96], 8, "F m-3 / d-3 / 432 / 4_132 / -43m / -43c and Im-3m Ia-3d")
        XCTAssertEqual(histogram[48], 11, "Pm-3m..Pn-3m (4), F23, Im-3 Ia-3, I432 I4_132, I-43m I-43d")
        XCTAssertEqual(histogram[36], 2, "R-3m R-3c in hexagonal axes")
        XCTAssertEqual(histogram[32], 6, "Fmmm Fddd and I4/mmm I4/mcm I4_1/amd I4_1/acd")
        XCTAssertEqual(histogram[24], 15)
        XCTAssertEqual(histogram[18], 4, "R-3 R32 R3m R3c in hexagonal axes")
        XCTAssertEqual(histogram[9], 1, "R3")
        XCTAssertEqual(histogram[3], 3, "P3 P3_1 P3_2")
        XCTAssertEqual(histogram[1], 1)
        XCTAssertEqual(orders.compactMap { $0 }.count, 230)
    }

    func testRhombohedralAxesNeedOnlyAThirdOfTheHexagonalCount() {
        // 166 R-3m: 36 in hexagonal axes (γ = 120), 12 in rhombohedral axes.
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 166, alphaDeg: 90, betaDeg: 90, gammaDeg: 120), 36)
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 166, alphaDeg: 60, betaDeg: 60, gammaDeg: 60), 12)
        // A primitive-cell F group needs only the centring-free part; the conventional cell needs all 192.
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 225, alphaDeg: 90, betaDeg: 90, gammaDeg: 90), 192)
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 225, alphaDeg: 60, betaDeg: 60, gammaDeg: 60), 48)
        // A primitive group is never relaxed, whatever the cell angles say.
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 221, alphaDeg: 60, betaDeg: 60, gammaDeg: 60), 48)
        // Orthorhombic C: conventional (all 90) needs 16; the oblique primitive cell needs 8.
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 63, alphaDeg: 90, betaDeg: 90, gammaDeg: 90), 16)
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 63, alphaDeg: 90, betaDeg: 90, gammaDeg: 104), 8)
        // Monoclinic C2/m: β free, α = γ = 90 is the conventional cell.
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 12, alphaDeg: 90, betaDeg: 105, gammaDeg: 90), 8)
        XCTAssertEqual(CIFImport.requiredOperationCount(spaceGroup: 12, alphaDeg: 71, betaDeg: 80, gammaDeg: 75), 4)
        XCTAssertNil(CIFImport.requiredOperationCount(spaceGroup: 300, alphaDeg: 90, betaDeg: 90, gammaDeg: 90))
    }

    // MARK: - The refusal (reproduced escape E2)

    /// Rock salt with only its 48 point operations named as Fm-3m (225): imported
    /// as CsCl (2 atoms). It must refuse, naming the group, the count listed and the count needed.
    func testFm3mListingOnlyItsPointOperationsIsRefusedNamingTheGap() {
        let cif = mgo(ops: Self.pointOps, itNumber: 225)
        assertThrows(cif, expected: .incompleteSymmetryOperations(
            spaceGroupNumber: 225, declaredName: "F m -3 m", listed: 48, required: 192))
        XCTAssertThrowsError(try CIFImport.crystalModel(from: cif, fileBaseName: "t")) { error in
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(text.contains("48"), text)
            XCTAssertTrue(text.contains("192"), text)
            XCTAssertTrue(text.contains("225"), text)
            XCTAssertTrue(text.contains("incomplete"), text)
        }
    }

    /// The complete list is untouched: 192 operations expand Mg + O to rock salt (8 atoms).
    func testCompleteFm3mListStillImportsAsRockSalt() throws {
        let model = try CIFImport.crystalModel(
            from: mgo(ops: Self.fm3mFull, itNumber: 225), fileBaseName: "t")
        XCTAssertEqual(model.crystal.sites.count, 8)
        XCTAssertEqual(model.spaceGroupNumber, 225)
    }

    /// More rows than the group has (a duplicated block) is unchanged behaviour.
    func testDuplicatedRowsAboveTheOrderAreNotRefused() throws {
        let model = try CIFImport.crystalModel(
            from: mgo(ops: Self.fm3mFull + Self.fm3mFull, itNumber: 225), fileBaseName: "t")
        XCTAssertEqual(model.crystal.sites.count, 8)
    }

    /// Padding a 48-operation list to 192 ROWS by repeating it does not make it complete:
    /// the count is of distinct operations.
    func testRepeatedRowsDoNotHideAnIncompleteList() {
        let padded = Self.pointOps + Self.pointOps + Self.pointOps + Self.pointOps
        XCTAssertEqual(padded.count, 192)
        assertThrows(mgo(ops: padded, itNumber: 225), expected: .incompleteSymmetryOperations(
            spaceGroupNumber: 225, declaredName: "F m -3 m", listed: 48, required: 192))
    }

    /// A file that names no IT number is unchanged behaviour: no table lookup, no refusal
    /// (the same 48 operations import, as they did before this change).
    func testAListWithNoNamedGroupNumberIsUnchanged() throws {
        let model = try CIFImport.crystalModel(
            from: mgo(ops: Self.pointOps, itNumber: nil), fileBaseName: "t")
        XCTAssertEqual(model.crystal.sites.count, 2)
        XCTAssertNil(model.spaceGroupNumber)
    }

    /// A primitive (60°) cell of Fm-3m legitimately lists the 48 centring-free operations:
    /// the check must not refuse it (it imports as an unreduced 2-atom cell).
    func testPrimitiveCellOfACentredGroupIsNotRefusedForLackingTheCentring() throws {
        let model = try CIFImport.crystalModel(
            from: mgo(ops: Self.pointOps, itNumber: 225, angle: 60), fileBaseName: "t")
        XCTAssertEqual(model.crystal.sites.count, 2)
    }

    /// An operation coefficient too large for an Int (and NaN-adjacent garbage) must be
    /// counted, not trapped on: the file is refused as incomplete, the app does not crash.
    func testAGarbledHugeCoefficientIsRefusedNotTrapped() {
        let cif = mgo(ops: ["x,y,z", "1000000000000000000000x,y,z", "-x,-y,-z"], itNumber: 225)
        assertThrows(cif, expected: .incompleteSymmetryOperations(
            spaceGroupNumber: 225, declaredName: "F m -3 m", listed: 3, required: 192))
    }

    // MARK: - A second block holding only a symmetry loop (D006 residual)

    private var structureBlock: String {
        """
        data_structure
        _symmetry_space_group_name_H-M 'P 1'
        _cell_length_a 4.2120
        _cell_length_b 4.2120
        _cell_length_c 4.2120
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        Mg1 Mg 0.0 0.0 0.0
        O1 O 0.5 0.5 0.5

        """
    }

    func testSecondBlockWithOnlyASymmetryLoopIsRefusedByName() {
        let cif = structureBlock + "\ndata_symops\n" + loop(Self.fm3mFull)
        assertThrows(cif, expected: .symmetryOperationsOutsideStructure(blockNames: ["symops"]))
    }

    func testSymmetryOnlyBlockBeforeTheStructureBlockIsRefusedToo() {
        let cif = "data_symops\n" + loop(Self.fm3mFull) + "\n" + structureBlock
        assertThrows(cif, expected: .symmetryOperationsOutsideStructure(blockNames: ["symops"]))
    }

    /// The structure block alone still imports, and a second block without a symmetry loop
    /// (a journal-only global block) still does not count.
    func testStructureBlockAloneAndAJournalBlockAreUnchanged() throws {
        let alone = try CIFImport.crystalModel(from: structureBlock, fileBaseName: "t")
        XCTAssertEqual(alone.crystal.sites.count, 2)
        let withJournal = try CIFImport.crystalModel(
            from: "data_global\n_publ_section_title 'x'\n\n" + structureBlock, fileBaseName: "t")
        XCTAssertEqual(withJournal.crystal.sites.count, 2)
    }

    /// The symmetry loop inside the structure block itself is of course fine.
    func testSymmetryLoopInsideTheStructureBlockIsUnchanged() throws {
        let model = try CIFImport.crystalModel(
            from: mgo(ops: Self.fm3mFull, itNumber: 225), fileBaseName: "t")
        XCTAssertEqual(model.crystal.sites.count, 8)
    }
}

/// #32 — `isSymmetry`'s bijection check had no fixture. The matcher accepts a site image
/// within a tolerance of a target; without a "claimed" set two different sites can both
/// land on the same target and the map is accepted although it is not a permutation.
final class CIFSymmetryBijectionTests: XCTestCase {

    /// FCC gold plus a split atom: two extra Au 0.0163 A from the origin atom along x and y
    /// (0.0040 fractional — inside the 5e-3 match tolerance of the origin atom, but 0.0057 from
    /// each other and from where the 3-fold sends them). No translation makes the 3-fold a
    /// permutation of these seven sites, so the cell is NOT cubic; a matcher that lets two sites
    /// share one target says it is.
    private let splitAtomFCC = """
    data_gold_split
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
    Au1 Au 0.0000 0.0000 0.0000
    Au2 Au 0.5000 0.5000 0.0000
    Au3 Au 0.5000 0.0000 0.5000
    Au4 Au 0.0000 0.5000 0.5000
    Au5 Au 0.0040 0.0000 0.0000
    Au6 Au 0.0000 0.0040 0.0000
    """

    func testTwoSitesCannotShareOneTargetInTheSymmetryMap() {
        XCTAssertThrowsError(
            try CIFImport.crystalModel(from: splitAtomFCC, fileBaseName: "t")
        ) { error in
            XCTAssertEqual(
                error as? CIFImportError,
                .symmetryNotSupportedByStructure(
                    family: "cubic", expected: "3-fold axis along ⟨111⟩"))
        }
    }
}
