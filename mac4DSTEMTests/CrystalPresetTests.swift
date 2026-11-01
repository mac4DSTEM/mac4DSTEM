import XCTest
import DiffractoCore
import DiffractoScattering
import DSTEMCore
import DiffractoOrientation
@testable import mac4DSTEM

/// The preset models' identity: `contentFingerprint`, `revisionID` and `provenance` key sidecars and libraries, so they are
/// held exact (digests recorded 2026-10-15). The kept reflection counts per preset at kMax 1.2, 1.6 and 2.0 Å⁻¹.
/// The digest is FNV-1a 64 over the UTF-8 bytes.
final class CrystalPresetTests: XCTestCase {

    private static func fnv(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return hash
    }

    private static func hex(_ value: UInt64) -> String { String(format: "%016llx", value) }

    /// The models exactly as the recorder built them (ids, names, symmetry, source decide `revisionID` and `provenance`).
    private func model(_ key: String) throws -> CrystalModel {
        switch key {
        case "beta":
            return CrystalModel(id: "preset_betaDoublePrime", displayName: "betaDoublePrime",
                                structure: CrystalPresets.betaDoublePrime, symmetry: .monoclinic, source: .builtIn)
        case "hcp":
            return CrystalModel(id: "ideal_hcp", displayName: "ideal hcp",
                                structure: CrystalPresets.hcp(a: 3.2094, c: 3.2094 * (8.0 / 3.0).squareRoot(), z: 12),
                                symmetry: .hexagonal, source: .builtIn)
        default:
            return try XCTUnwrap(CrystalModelLibrary.model(id: key), key)
        }
    }

    // (model, contentFingerprint, FNV of revisionID, FNV of the sorted provenance "k=v" lines, [(kMax, kept count)])
    private static let recorded: [(String, String, String, String, [(Double, Int)])] = [
        ("au_fcc", "cad6fd3edb39d0e5", "2145245d7593e5f9", "20cdf1b09a6a74dd", [(1.2, 112), (1.6, 282), (2.0, 536)]),
        ("al_fcc", "4a62ab07feaebf7a", "7bbceb4a5ca1f153", "126a7e8d8c83d08b", [(1.2, 112), (1.6, 282), (2.0, 536)]),
        ("ni_fcc", "ca2a9890c2bd534a", "b185b777875004af", "33521095b704d714", [(1.2, 64), (1.6, 168), (2.0, 338)]),
        ("cu_fcc", "43d64fe16231d9b7", "9d5a26c4f9c5efd5", "3fba9c992fdb0845", [(1.2, 64), (1.6, 180), (2.0, 410)]),
        ("fe_bcc", "89d954c32f1a0a16", "cae240e3ed060337", "4ecf439bfe9898a1", [(1.2, 78), (1.6, 200), (2.0, 380)]),
        ("si_diamond", "cdb2a9cf2df4e3fd", "77221119024d48ab", "417c263cae67659c", [(1.2, 214), (1.6, 536), (2.0, 992)]),
        ("mg_hcp", "c10116ffee65f386", "68c729fd220b717d", "4fbf0c9e65b1b1e1", [(1.2, 270), (1.6, 656), (2.0, 1282)]),
        ("ws2_2h", "8b8feee518bc5dd0", "b5533cfef1d1f892", "4a88011424dd579d", [(1.2, 638), (1.6, 1518), (2.0, 2940)]),
        ("beta", "68e8e8b2cd41da82", "ed98236af57f362b", "899e22c6d3234aed", [(1.2, 1442), (1.6, 3420), (2.0, 6596)]),
        ("hcp", "41c07676ce90eb11", "ab581ae0a66718cf", "bb58d8f78aa0a967", [(1.2, 270), (1.6, 656), (2.0, 1282)]),
    ]

    func testPresetModelIdentityIsStable() throws {
        for (key, fingerprint, revisionDigest, provenanceDigest, _) in Self.recorded {
            let m = try model(key)
            XCTAssertEqual(m.contentFingerprint, fingerprint, "\(key) contentFingerprint")
            XCTAssertEqual(Self.hex(Self.fnv(Array(m.revisionID.utf8))), revisionDigest, "\(key) revisionID")
            let provenance = m.provenance.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            XCTAssertEqual(Self.hex(Self.fnv(Array(provenance.utf8))), provenanceDigest, "\(key) provenance")
        }
    }

    /// How many reflections each preset keeps after the 1e-4 cut: the set the app builds its templates from. The values
    /// (|g|, F) are DiffractoKit's and its parity tests own them.
    func testPresetKeptReflectionCounts() throws {
        for (key, _, _, _, expectations) in Self.recorded {
            let m = try model(key)
            for (kMax, count) in expectations {
                XCTAssertEqual(try m.structure.kinematicReflections(kMax: kMax).kept.count, count, "\(key) kept count at kMax \(kMax)")
            }
        }
    }
}

/// The app's own decisions on top of the kit: the mapping from the kit's Laue
/// class to the orientation reduction, and the refusals the app keeps.
final class CrystalSymmetryMappingTests: XCTestCase {

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
            CrystalModel(id: "t", displayName: "t", structure: CrystalPresets.simpleCubic(a: 4, z: z), symmetry: .identity, source: .custom)
                .validationIssues.map(\.code)
        }
        XCTAssertEqual(codes(104), ["unsupported_element"])
        XCTAssertEqual(codes(0), ["unsupported_element"])
        XCTAssertEqual(codes(119), ["unsupported_element"])
        XCTAssertEqual(codes(26), [])
        XCTAssertEqual(CrystalPresets.simpleCubic(a: 4, z: 104).unsupportedElements, [104])
        XCTAssertEqual(CrystalPresets.simpleCubic(a: 4, z: 26).unsupportedElements, [])
    }

    /// The consumers that used to read an empty list for a structure the kit refuses: no template plan, no zone-axis
    /// fit, and a library that names the phase.
    func testStructuresTheKitRefusesGiveNoPlanAndANamedLibraryFailure() throws {
        let bad = CrystalPresets.simpleCubic(a: 4, z: 104)
        XCTAssertNil(OrientationPlan.generate(crystal: bad, kMax: 1.2, zoneAxisCount: 12))
        let tooClose = CrystalPresets.structure(a: 4, b: 4, c: 4, sites: [
            AtomSite(z: 13, fractional: [0, 0, 0]), AtomSite(z: 13, fractional: [0.01, 0, 0])])
        func library(_ candidate: CrystalStructure) throws -> PhaseReferenceLibrary {
            try PhaseReferenceLibrary.build(phases: [
                PhaseDefinition(id: "m", displayName: "Matrix", crystal: CrystalPresets.aluminum, role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
                PhaseDefinition(id: "c", displayName: "Candidate", crystal: candidate, role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
            ])
        }
        XCTAssertThrowsError(try library(bad)) { error in
            XCTAssertEqual(error as? PhaseReferenceLibrary.Failure, .unsupportedElements(phase: "Candidate", z: [104]))
        }
        XCTAssertThrowsError(try library(tooClose)) { error in
            guard case .structureRefused(let phase, let reason)? = error as? PhaseReferenceLibrary.Failure else {
                return XCTFail("expected structureRefused, got \(error)")
            }
            XCTAssertEqual(phase, "Candidate")
            XCTAssertTrue(reason.contains("0.0400"), reason)
            XCTAssertTrue(AppState.phaseLibraryFailureMessage(.structureRefused(phase: phase, reason: reason)).contains("Candidate"))
        }
    }
}
