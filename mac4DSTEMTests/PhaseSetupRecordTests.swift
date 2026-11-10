//
//  PhaseSetupRecordTests.swift
//  Guards: a saved phase-mapping run writes its phase list, its exact settings and the text of each imported CIF
//          into the session's lineage, and a reopened session gets them back (#128). Before, the session kept the
//          map's picture and the run's words only, and the phases were entered again by hand.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
@testable import mac4DSTEM

@MainActor
final class PhaseSetupRecordTests: XCTestCase {

    private func cif(a: Double = 4.0782) -> String {
        """
        data_gold
        _cell_length_a \(a)
        _cell_length_b \(a)
        _cell_length_c \(a)
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
    }

    private var aluminium: CrystalModel { CrystalModelLibrary.model(id: "al_fcc")! }

    /// A matrix and one imported structure at two zone axes, with settings off their defaults.
    private func setup() throws -> (record: PhaseSetupRecord, phases: [PhaseMappingSlot],
                                    reference: PhaseReferenceSettings, matching: PhaseVectorSettings) {
        let imported = try CIFModelImport.crystalModel(from: cif(), fileBaseName: "precipitate")
        let phases = [
            PhaseMappingSlot(model: aluminium, isMatrix: true, u: 0, v: 0, w: 1),
            PhaseMappingSlot(model: imported, isMatrix: false, u: 0, v: 1, w: 0,
                             orientationRelationshipText: "(0 1 0) || (0 0 1)", excitationSlabInvAngstrom: 0.0123456789),
            PhaseMappingSlot(model: imported, isMatrix: false, u: 0, v: 0, w: 1),
        ]
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2345678901234567
        reference.minimumIntensityFraction = 0.1 + 0.2   // not a short decimal
        reference.maximumEntries += 7
        var matching = PhaseVectorSettings()
        matching.classificationRule = .knownVariants
        matching.matrixToleranceInvAngstrom = 0.017_000_000_000_000_3
        matching.minimumMatchedVectors += 2
        matching.completenessAwareCrossPhaseRanking.toggle()
        let record = PhaseSetupRecord(
            phases: phases, reference: reference, matching: matching,
            cifSources: [imported.id: .init(text: cif(), fileBaseName: "precipitate")])
        return (record, phases, reference, matching)
    }

    func testTheSetupComesBackFromItsJSONWithNothingHeld() throws {
        let saved = try setup()
        let json = try XCTUnwrap(saved.record.jsonString)
        let read = try XCTUnwrap(PhaseSetupRecord.decoded(from: json))
        XCTAssertEqual(read, saved.record)

        let restored = try read.restored(held: []).get()
        XCTAssertEqual(restored.phases.map(\.signature), saved.phases.map(\.signature),
                       "structure, matrix flag, zone axis, orientation relationship and slab of every slot")
        XCTAssertEqual(restored.reference, saved.reference, "exact values, not rounded ones")
        XCTAssertEqual(restored.matching, saved.matching)
        XCTAssertEqual(restored.imported.map(\.model.id), [saved.phases[1].model.id],
                       "one CIF at two zone axes is rebuilt once")
        XCTAssertEqual(restored.phases[1].model.source, .imported)
    }

    func testAStructureThatCannotBeRebuiltRefusesTheWholeList() throws {
        let saved = try setup()
        let slim = saved.record.withoutCIFTexts
        XCTAssertEqual(slim.restored(held: []).failure, .structureMissing(name: saved.phases[1].model.displayName))
        // The window still holds the model (same id, same content): nothing is missing.
        XCTAssertEqual(try slim.restored(held: [saved.phases[1].model]).get().phases.count, 3)

        // A CIF text that builds another structure under the same id is not the structure the run used.
        var other = saved.record
        for index in other.slots.indices where other.slots[index].cif != nil {
            other.slots[index].cif?.text = cif(a: 4.2)
        }
        XCTAssertEqual(other.restored(held: []).failure, .structureChanged(name: saved.phases[1].model.displayName))

        XCTAssertNil(PhaseSetupRecord.decoded(from: "{}"))
        var newer = saved.record
        newer.version += 1
        XCTAssertNil(PhaseSetupRecord.decoded(from: try XCTUnwrap(newer.jsonString)), "a newer record is not half-read")
    }

    /// The path a session file takes: the run's node, the lineage as JSON, a new window adopting it.
    func testAReopenedSessionHasItsPhasesAndSettingsBack() throws {
        let saved = try setup()
        let writer = AppState()
        writer.recordLineageRun(kind: "phase_mapping", parameters: [
            "phases": "Al|gold|gold", PhaseSetupRecord.lineageKey: try XCTUnwrap(saved.record.jsonString),
        ])
        let lineage = try SessionLineage.validated(try XCTUnwrap(writer.replay.lineage.jsonString)).get()

        let reopened = AppState()
        reopened.replay.adopt(nil, lineage: lineage, recordedOn: nil)
        reopened.restorePhaseSetupFromLineage()
        XCTAssertEqual(reopened.phaseMapping.phases.map(\.signature), saved.phases.map(\.signature))
        XCTAssertEqual(reopened.phaseMapping.reference, saved.reference)
        XCTAssertEqual(reopened.phaseMapping.matching, saved.matching)
        XCTAssertEqual(reopened.acomSession.importedCrystalModels.map(\.id), [saved.phases[1].model.id])
        XCTAssertNotNil(reopened.acomSession.importedCIFSources[saved.phases[1].model.id],
                        "so the next save carries the text again")

        // A window that already has a phase list keeps it.
        let busy = AppState()
        busy.addPhaseMappingSlot(CrystalModelLibrary.model(id: "au_fcc")!)
        busy.replay.adopt(nil, lineage: lineage, recordedOn: nil)
        busy.restorePhaseSetupFromLineage()
        XCTAssertEqual(busy.phaseMapping.phases.map(\.model.id), ["au_fcc"])
    }

    func testOnlyTheNewestRunCarriesTheCIFTexts() throws {
        let saved = try setup()
        let json = try XCTUnwrap(saved.record.jsonString)
        var lineage = SessionLineage()
        let first = lineage.recordRun(kind: "phase_mapping", parameters: [PhaseSetupRecord.lineageKey: json], frame: nil)
        lineage.markProduct(step: first, as: "phase_map")   // a saved map: the next run is its own node
        let second = lineage.recordRun(kind: "phase_mapping", parameters: [PhaseSetupRecord.lineageKey: json], frame: nil)
        XCTAssertNotEqual(first, second)
        lineage.rewriteParameter(PhaseSetupRecord.lineageKey, onNodesOfKind: "phase_mapping", except: second) {
            PhaseSetupRecord.decoded(from: $0)?.withoutCIFTexts.jsonString
        }
        let older = try XCTUnwrap(PhaseSetupRecord.decoded(from: try XCTUnwrap(lineage.node(id: first)?.parameters[PhaseSetupRecord.lineageKey])))
        XCTAssertEqual(older, saved.record.withoutCIFTexts, "its list and settings stay")
        XCTAssertEqual(lineage.node(id: second)?.parameters[PhaseSetupRecord.lineageKey], json)

        // A replayable kind's parameters are the recipe and are never rewritten.
        let disks = lineage.recordRun(kind: "disk_detection", parameters: ["sigma": "1"], frame: nil)
        lineage.rewriteParameter("sigma", onNodesOfKind: "disk_detection", except: "") { _ in nil }
        XCTAssertEqual(lineage.node(id: disks)?.parameters["sigma"], "1")
    }

    func testTheLineagePaneDoesNotListTheStoredSetup() throws {
        var lineage = SessionLineage()
        let id = lineage.recordRun(kind: "phase_mapping", parameters: ["phases": "Al", PhaseSetupRecord.lineageKey: "{}"], frame: nil)
        let node = try XCTUnwrap(lineage.node(id: id))
        XCTAssertEqual(LineageGraphModel.listedParameters(of: node).map(\.key), ["phases"])
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
