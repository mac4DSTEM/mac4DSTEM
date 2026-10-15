import XCTest
import DiffractoCore
import DiffractoScattering
import DSTEMCore
@testable import mac4DSTEM

/// Tier 1 consumer test of the switch to DiffractoKit 0.0.3 (docs/archive/v5/diffractokit-switch-registration-2026-10-15.md,
/// predictions P2 and P3). The values are RECORDED from 7f192da9 + the pin seam (c86733b2), BEFORE any switch code, with
/// the app's own `Crystal.reflections(kMax:tolerance: 1e-4)` and `CrystalModel`: for every preset the kept reflections
/// after the 1e-4 cut at kMax 1.2, 1.6 and 2.0 Å⁻¹ (h, k, l and the bit patterns of |g|, Re F, Im F and |F|², sorted by
/// hkl so the order within an equal-|g| ring, which the kit defines differently, does not matter), and the model's
/// `contentFingerprint`, `revisionID` and `provenance` (they key sidecars and libraries, so they must not move).
/// The digest is FNV-1a 64 over, per reflection, Int64 h, k, l and UInt64 bitPattern of the four doubles, little-endian.
/// Recorder and values: scratchpad lane-X/before/presets-and-cifs.txt (482,002 reflections across the whole corpus,
/// all bit-equal after the switch).
final class KitSwitchFreezeTests: XCTestCase {

    private static func fnv(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return hash
    }

    private static func hex(_ value: UInt64) -> String { String(format: "%016llx", value) }

    private static func le(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }

    private static func digest(_ reflections: [KinematicReflection]) -> String {
        var bytes: [UInt8] = []
        let sorted = reflections.sorted { ($0.h, $0.k, $0.l) < ($1.h, $1.k, $1.l) }
        bytes.reserveCapacity(sorted.count * 56)
        for r in sorted {
            for index in [r.h, r.k, r.l] { bytes += le(UInt64(bitPattern: Int64(index))) }
            for value in [r.gLength, r.structureFactorRe, r.structureFactorIm, r.intensity] { bytes += le(value.bitPattern) }
        }
        return hex(fnv(bytes))
    }

    /// The models exactly as the recorder built them (ids, names, symmetry, source decide `revisionID` and `provenance`).
    private func model(_ key: String) throws -> CrystalModel {
        switch key {
        case "beta":
            return CrystalModel(id: "preset_betaDoublePrime", displayName: "betaDoublePrime",
                                structure: Crystal.betaDoublePrime, symmetry: .monoclinic, source: .builtIn)
        case "hcp":
            return CrystalModel(id: "ideal_hcp", displayName: "ideal hcp",
                                structure: Crystal.hcp(a: 3.2094, c: 3.2094 * (8.0 / 3.0).squareRoot(), z: 12),
                                symmetry: .hexagonal, source: .builtIn)
        default:
            return try XCTUnwrap(CrystalModelLibrary.model(id: key), key)
        }
    }

    // (model, contentFingerprint, FNV of revisionID, FNV of the sorted provenance "k=v" lines, [(kMax, count, digest)])
    private static let recorded: [(String, String, String, String, [(Double, Int, String)])] = [
        ("au_fcc", "cad6fd3edb39d0e5", "2145245d7593e5f9", "20cdf1b09a6a74dd", [(1.2, 112, "0240c5249ad47279"), (1.6, 282, "35d699baf643821a"), (2.0, 536, "deba48fcd92336b5")]),
        ("al_fcc", "4a62ab07feaebf7a", "7bbceb4a5ca1f153", "126a7e8d8c83d08b", [(1.2, 112, "56a3c8fef48a508d"), (1.6, 282, "6dedb26a8a26e71a"), (2.0, 536, "cd65a69f3082ed09")]),
        ("ni_fcc", "ca2a9890c2bd534a", "b185b777875004af", "33521095b704d714", [(1.2, 64, "d695c837a87fc271"), (1.6, 168, "ad11c1a1ced77469"), (2.0, 338, "e5d3f18fe8f33b02")]),
        ("cu_fcc", "43d64fe16231d9b7", "9d5a26c4f9c5efd5", "3fba9c992fdb0845", [(1.2, 64, "ebf8338207d951b9"), (1.6, 180, "fd71cd6614539b19"), (2.0, 410, "a613000ff7e1697a")]),
        ("fe_bcc", "89d954c32f1a0a16", "cae240e3ed060337", "4ecf439bfe9898a1", [(1.2, 78, "0d3a268a88a6f0f2"), (1.6, 200, "4bc77cdc392de091"), (2.0, 380, "964ed5e931a963a5")]),
        ("si_diamond", "cdb2a9cf2df4e3fd", "77221119024d48ab", "417c263cae67659c", [(1.2, 214, "fb5b4d4d7507744a"), (1.6, 536, "f59462136869809d"), (2.0, 992, "6fbea777944e2449")]),
        ("mg_hcp", "c10116ffee65f386", "68c729fd220b717d", "4fbf0c9e65b1b1e1", [(1.2, 270, "9531ca540a8d7e0a"), (1.6, 656, "d3c7633661e211cd"), (2.0, 1282, "1705b73d4a39c36a")]),
        ("ws2_2h", "8b8feee518bc5dd0", "b5533cfef1d1f892", "4a88011424dd579d", [(1.2, 638, "9f76cdbe018e78b2"), (1.6, 1518, "6ac0d13c59a8bab2"), (2.0, 2940, "1cb09794c468ff1d")]),
        ("beta", "68e8e8b2cd41da82", "ed98236af57f362b", "899e22c6d3234aed", [(1.2, 1442, "cbd9f322fc7e7954"), (1.6, 3420, "b25f72bef8096963"), (2.0, 6596, "319aa6f03d1357f0")]),
        ("hcp", "41c07676ce90eb11", "ab581ae0a66718cf", "bb58d8f78aa0a967", [(1.2, 270, "1b794e221fa44382"), (1.6, 656, "aa26d3acfd23d4c9"), (2.0, 1282, "0ee5c571ec6355ba")]),
    ]

    func testPresetModelIdentityIsByteEqualToTheAppsOwnBeforeTheKitSwitch() throws {
        for (key, fingerprint, revisionDigest, provenanceDigest, _) in Self.recorded {
            let m = try model(key)
            XCTAssertEqual(m.contentFingerprint, fingerprint, "\(key) contentFingerprint")
            XCTAssertEqual(Self.hex(Self.fnv(Array(m.revisionID.utf8))), revisionDigest, "\(key) revisionID")
            let provenance = m.provenance.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            XCTAssertEqual(Self.hex(Self.fnv(Array(provenance.utf8))), provenanceDigest, "\(key) provenance")
        }
    }

    func testPresetKeptReflectionsAreBitEqualToTheAppsOwnBeforeTheKitSwitch() throws {
        for (key, _, _, _, expectations) in Self.recorded {
            let m = try model(key)
            for (kMax, count, expected) in expectations {
                let kept = try m.structure.kinematicReflections(kMax: kMax).kept
                XCTAssertEqual(kept.count, count, "\(key) kept count at kMax \(kMax)")
                XCTAssertEqual(Self.digest(kept), expected, "\(key) |g|, Re F, Im F, |F|² at kMax \(kMax)")
            }
        }
    }
}

/// Tier 1 consumer tests of the app's own decisions on top of the kit (registration P4): the mapping from the kit's Laue
/// class to the orientation reduction, and the refusals the app keeps.
final class KitSwitchMappingTests: XCTestCase {

    private func cif(cell: String, atoms: [String]) -> String {
        """
        data_t
        \(cell)
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        \(atoms.enumerated().map { "Fe\($0.offset + 1) Fe \($0.element)" }.joined(separator: "\n"))
        """
    }

    private func cell(_ a: Double, _ b: Double, _ c: Double, _ al: Double, _ be: Double, _ ga: Double) -> String {
        "_cell_length_a \(a)\n_cell_length_b \(b)\n_cell_length_c \(c)\n_cell_angle_alpha \(al)\n_cell_angle_beta \(be)\n_cell_angle_gamma \(ga)"
    }

    /// 2/m means two different things to the kit and to ACOM: the kit's is any unique axis, ACOM's `.monoclinic` is b
    /// unique only (its frame has b along +y). The same four atoms, 2-fold about the unique axis, in a cell oblique
    /// about b are `.monoclinic`; oblique about c, `.identity`. Mutation: dropping the unique-axis test.
    func testTwoOverMIsMonoclinicOnlyWithBUnique() throws {
        let b = try CIFModelImport.crystalModel(
            from: cif(cell: cell(5, 6, 7, 90, 100, 90),
                      atoms: ["0.1 0.2 0.3", "0.9 0.2 0.7", "0.9 0.8 0.7", "0.1 0.8 0.3"]), // (x,y,z) (-x,y,-z) (-x,-y,-z) (x,-y,z)
            fileBaseName: "bunique")
        XCTAssertEqual(b.structure.laueClass, .twoOverM)
        XCTAssertEqual(b.symmetry, .monoclinic)
        let c = try CIFModelImport.crystalModel(
            from: cif(cell: cell(5, 6, 7, 90, 90, 100),
                      atoms: ["0.1 0.2 0.3", "0.9 0.8 0.3", "0.9 0.8 0.7", "0.1 0.2 0.7"]), // (x,y,z) (-x,-y,z) (-x,-y,-z) (x,y,-z)
            fileBaseName: "cunique")
        XCTAssertEqual(c.structure.laueClass, .twoOverM)
        XCTAssertEqual(c.symmetry, .identity, "2/m with c unique is not the b-unique reduction ACOM implements")
        XCTAssertFalse(c.supportsOrientationMapping)
    }

    /// Z outside the electron scattering table (1 to 103) is the app's `unsupported_element`, once per site; the kit's own
    /// `invalid_atomic_number` (outside 1 to 118) is not reported twice. A plain Z = 104 is valid for the kit and refused
    /// by the app. Mutation: dropping the filter on `invalid_atomic_number`, or the app's own check.
    func testElementsOutsideTheScatteringTableAreTheAppsRefusalOnce() {
        func codes(_ z: Int) -> [String] {
            CrystalModel(id: "t", displayName: "t", structure: Crystal.sc(a: 4, z: z), symmetry: .identity, source: .custom)
                .validationIssues.map(\.code)
        }
        XCTAssertEqual(codes(104), ["unsupported_element"])
        XCTAssertEqual(codes(0), ["unsupported_element"])
        XCTAssertEqual(codes(119), ["unsupported_element"])
        XCTAssertEqual(codes(26), [])
        XCTAssertEqual(Crystal.sc(a: 4, z: 104).unsupportedElements, [104])
        XCTAssertEqual(Crystal.sc(a: 4, z: 26).unsupportedElements, [])
    }

    /// The consumers that used to read an empty list for a structure the kit refuses: no template plan, no zone-axis
    /// fit, and a library that names the phase.
    func testStructuresTheKitRefusesGiveNoPlanAndANamedLibraryFailure() throws {
        let bad = Crystal.sc(a: 4, z: 104)
        XCTAssertNil(OrientationPlan.generate(crystal: bad, kMax: 1.2, zoneAxisCount: 12))
        let tooClose = Crystal.structure(a: 4, b: 4, c: 4, sites: [
            AtomSite(z: 13, fractional: [0, 0, 0]), AtomSite(z: 13, fractional: [0.01, 0, 0])])
        func library(_ candidate: CrystalStructure) throws -> PhaseReferenceLibrary {
            try PhaseReferenceLibrary.build(phases: [
                PhaseDefinition(id: "m", displayName: "Matrix", crystal: Crystal.aluminum, role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
                PhaseDefinition(id: "c", displayName: "Candidate", crystal: candidate, role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
            ])
        }
        XCTAssertThrowsError(try library(bad)) { error in
            XCTAssertEqual(error as? PhaseReferenceLibrary.Failure, .unsupportedElements(phase: "Candidate", z: [104]))
        }
        XCTAssertThrowsError(try library(tooClose)) { error in
            guard case .invalidStructure(let phase, let reason)? = error as? PhaseReferenceLibrary.Failure else {
                return XCTFail("expected invalidStructure, got \(error)")
            }
            XCTAssertEqual(phase, "Candidate")
            XCTAssertTrue(reason.contains("0.0400"), reason)
            XCTAssertTrue(AppState.phaseLibraryFailureMessage(.invalidStructure(phase: phase, reason: reason)).contains("Candidate"))
        }
    }
}
