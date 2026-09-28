//
//  PhaseMappingReproductionTests.swift
//  The app's phase list must be able to state the probe's Thronsen configuration
//  (`tools/phase-map-probe/thronsen.swift`, `Thronsen.phases(constrained: true)`):
//  θ′ twice (edge-on [100], face-on [001]), a per-phase excitation slab, and the
//  orientation relationships typed as text. B1 reproduction, 2026-09-28.
//

import XCTest
import simd
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseMappingReproductionTests: XCTestCase {

    /// Mutations this must catch: the slot identity back to `model.id`, or the
    /// "skip a phase already in the list" guard restored in `addPhaseMappingSlot`.
    @MainActor
    func testSameStructureTwiceIsTwoPhasesAtItsTwoZoneAxes() throws {
        let matrix = CrystalModelLibrary.models[0], precipitate = CrystalModelLibrary.models[1]
        let appState = AppState()
        appState.addPhaseMappingSlot(matrix)
        appState.addPhaseMappingSlot(precipitate)
        appState.addPhaseMappingSlot(precipitate)
        XCTAssertEqual(appState.phaseMapping.phases.count, 3, "the second copy was skipped")
        XCTAssertEqual(Set(appState.phaseMapping.phases.map(\.id)).count, 3, "two slots share an identity")
        appState.phaseMapping.phases[2].u = 1; appState.phaseMapping.phases[2].w = 0
        XCTAssertNil(appState.phaseMapping.runRefusal)
        let definitions = try XCTUnwrap(appState.phaseDefinitions())
        XCTAssertEqual(Set(definitions.map(\.id)).count, 3, "the engine sees one phase id twice")
        XCTAssertEqual(definitions[1].zoneAxes, [SIMD3(0, 0, 1)])
        XCTAssertEqual(definitions[2].zoneAxes, [SIMD3(1, 0, 0)])
    }

    /// Mutation: the duplicate check removed from `runRefusal`.
    @MainActor
    func testTheSameStructureTwiceAtOneZoneAxisIsRefused() {
        let appState = AppState()
        appState.addPhaseMappingSlot(CrystalModelLibrary.models[0])
        appState.addPhaseMappingSlot(CrystalModelLibrary.models[1])
        appState.addPhaseMappingSlot(CrystalModelLibrary.models[1])
        let refusal = appState.phaseMapping.runRefusal
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("twice") ?? false, refusal ?? "nil")
    }

    /// Mutation: `excitationSlabInvAngstrom` not passed in `phaseDefinitions()`.
    @MainActor
    func testPerPhaseSlabReachesTheEngineAndNilKeepsTheGlobal() throws {
        let appState = AppState()
        appState.phaseMapping.phases = [
            PhaseMappingSlot(model: CrystalModelLibrary.models[0], isMatrix: true, u: 0, v: 0, w: 1),
            PhaseMappingSlot(model: CrystalModelLibrary.models[1], isMatrix: false, u: 1, v: 0, w: 0,
                             excitationSlabInvAngstrom: 0.3),
            PhaseMappingSlot(model: CrystalModelLibrary.models[2], isMatrix: false, u: 0, v: 0, w: 1),
        ]
        let definitions = try XCTUnwrap(appState.phaseDefinitions())
        XCTAssertEqual(definitions[1].excitationSlabInvAngstrom, 0.3)
        XCTAssertNil(definitions[2].excitationSlabInvAngstrom, "nil must leave the library's global slab")
        XCTAssertNil(definitions[0].excitationSlabInvAngstrom)
    }

    /// Mutation: the slab left out of `signature`, so a changed slab would not mark the map stale.
    func testASlabChangeMarksTheListChanged() {
        var slot = PhaseMappingSlot(model: CrystalModelLibrary.models[1], isMatrix: false, u: 1, v: 0, w: 0)
        let before = slot.signature
        slot.excitationSlabInvAngstrom = 0.3
        XCTAssertNotEqual(slot.signature, before)
    }

    /// The recipe's three strings must parse to exactly the probe's pairs
    /// (`Thronsen.phases(constrained: true)`). Mutation: any pair swapped or dropped.
    func testThronsenRecipeRelationshipsParseToTheProbesPairs() throws {
        let edgeOn = try XCTUnwrap(PhaseMappingSlot.parseOrientationRelationships("(002) ∥ (200), (002) ∥ (020)"))
        XCTAssertEqual(edgeOn, [
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(0, 2, 0))),
        ])
        let faceOn = try XCTUnwrap(PhaseMappingSlot.parseOrientationRelationships("(200) ∥ (200), (200) ∥ (020)"))
        XCTAssertEqual(faceOn, [
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(0, 2, 0))),
        ])
        let t1 = try XCTUnwrap(PhaseMappingSlot.parseOrientationRelationships("[210] ∥ [1-10], [210] ∥ [110]"))
        XCTAssertEqual(t1, [
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, -1, 0))),
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, 1, 0))),
        ])
    }
}
