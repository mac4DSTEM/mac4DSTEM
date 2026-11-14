//
//  TypedOrientationRelationshipTests.swift
//  #342: the parity setup's orientation relationships typed as a person types them (the phase rows' text, the door's
//  `orientation_relationship`) give the parity setup's phase definitions: the same relationships, zone axes and slabs.
//

import XCTest
import DSTEMCore
import DiffractoCore
import DSTEMSession
import DiffractoOrientation
@testable import mac4DSTEM

@MainActor
final class TypedOrientationRelationshipTests: XCTestCase {
    /// The Thronsen CIFs (Paul's References folder, beside the repo; `MACEM_REFERENCES` elsewhere, as ThronsenParityTests).
    private static let cifs: URL = {
        let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("References")
        return root.appendingPathComponent("mac4DSTEM/crystal-structures")
    }()

    private func model(_ file: String) throws -> CrystalModel {
        let url = Self.cifs.appendingPathComponent(file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("\(file) is not on this machine") }
        return try CIFModelImport.crystalModel(from: text, fileBaseName: url.deletingPathExtension().lastPathComponent)
    }

    /// The phase list as a person types it: `t1` and `theta` are the relationship texts of T1 and of both θ′ rows.
    private func typedDefinitions(t1: String, thetaEdge: String, thetaFace: String) throws -> [PhaseDefinition] {
        let state = AppState()
        state.phaseMapping.orientationSource = .typedZones   // the parity method: Thronsen et al.'s typed zone axes
        state.phaseMapping.phases = [
            PhaseMappingSlot(model: try model("Al_thronsen2024.cif"), isMatrix: true, u: 0, v: 0, w: 1),
            PhaseMappingSlot(model: try model("thetaprime_thronsen2024.cif"), isMatrix: false, u: 1, v: 0, w: 0,
                             orientationRelationshipText: thetaEdge, excitationSlabInvAngstrom: 0.3),
            PhaseMappingSlot(model: try model("thetaprime_thronsen2024.cif"), isMatrix: false, u: 0, v: 0, w: 1,
                             orientationRelationshipText: thetaFace, excitationSlabInvAngstrom: 0.3),
            PhaseMappingSlot(model: try model("T1_thronsen2024.cif"), isMatrix: false, u: 0, v: -4, w: 1,
                             orientationRelationshipText: t1),
        ]
        return try XCTUnwrap(state.phaseDefinitions(), state.phaseMapping.runRefusal ?? "not runnable")
    }

    /// The relationships of a definition as an unordered set (variants have no order).
    private func set(_ d: PhaseDefinition) -> Set<String> { Set(d.orientationRelationships.map { "\($0)" }) }

    private func assertParity(_ typed: [PhaseDefinition], file: StaticString = #filePath, line: UInt = #line) {
        let parity = ThronsenReference.phases()
        XCTAssertEqual(typed.count, parity.count, file: file, line: line)
        for (t, p) in zip(typed, parity) {
            XCTAssertEqual(t.role, p.role, p.displayName, file: file, line: line)
            XCTAssertEqual(t.zoneAxes, p.zoneAxes, p.displayName, file: file, line: line)
            XCTAssertEqual(set(t), set(p), p.displayName, file: file, line: line)
            XCTAssertEqual(t.excitationSlabInvAngstrom, p.excitationSlabInvAngstrom, p.displayName, file: file, line: line)
        }
    }

    /// Both pairs typed, as the parity setup lists them.
    func testTheParityRelationshipsTypedGiveTheParityDefinitions() throws {
        assertParity(try typedDefinitions(t1: "[2 1 0] ∥ [1 -1 0], [2 1 0] || [1 1 0]",
                                          thetaEdge: "(002) ∥ (200), (002) ∥ (020)", thetaFace: "(200) ∥ (200); (200) ∥ (020)"))
    }

    /// One pair each, as the paper states a relationship (the 14 Nov door run, 84.47 %): the matrix's symmetry about [001] gives the
    /// second variant. Mutation: no expansion - one variant each, red.
    func testOnePairTypedGivesBothVariants() throws {
        assertParity(try typedDefinitions(t1: "[2 1 0] ∥ [1 -1 0]", thetaEdge: "(002) ∥ (200)", thetaFace: "(200) ∥ (200)"))
    }

    /// No relationship typed stays free (no constraint), and a phase list without a matrix is left as typed.
    func testAnEmptyRelationshipStaysFree() throws {
        let defs = try typedDefinitions(t1: "", thetaEdge: "", thetaFace: "")
        XCTAssertTrue(defs.allSatisfy { $0.orientationRelationships.isEmpty })
    }
}

/// The same expansion without the CIFs (CI has no References): the parity setup's crystals, one pair each.
final class OrientationRelationshipVariantsTests: XCTestCase {
    func testOnePairGivesTheParityVariantsOnAl001() {
        let parity = ThronsenReference.phases()
        for p in parity where p.role == .candidate {
            let one = OrientationRelationshipVariants.expanded(Array(p.orientationRelationships.prefix(1)),
                                                               matrix: CrystalPresets.aluminum, matrixZone: SIMD3(0, 0, 1))
            XCTAssertEqual(Set(one.map { "\($0)" }), Set(p.orientationRelationships.map { "\($0)" }), p.displayName)
        }
    }

    func testTypedPairsAreKeptAndNotDoubled() {
        let both = ThronsenReference.phases()[3].orientationRelationships   // T1's two pairs
        let expanded = OrientationRelationshipVariants.expanded(both, matrix: CrystalPresets.aluminum, matrixZone: SIMD3(0, 0, 1))
        XCTAssertEqual(expanded.count, 2)
        XCTAssertEqual(expanded.first, both.first)
        XCTAssertEqual(OrientationRelationshipVariants.text(both[0]), "[2 1 0] ∥ [1 -1 0]")
    }
}
