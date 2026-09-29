//
//  PrecipitateObjectsLineageTests.swift
//  S12: the objects picture redrawn at a new minimum size is a run of its own
//  in the lineage. The minimum size is a parameter of the "precipitate_objects"
//  node; redrawing under the old node made the picture (and an export of it)
//  name a run whose recorded setting it did not use.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PrecipitateObjectsLineageTests: XCTestCase {

    /// An 8 x 8 map: matrix everywhere but a 2 x 2 candidate block (4 px) and a
    /// 1-px candidate, so the minimum size 1 -> 3 changes what is counted.
    private func classifiedState() async -> AppState {
        let state = AppState()
        state.addPhaseMappingSlot(CrystalModelLibrary.models[0])
        state.addPhaseMappingSlot(CrystalModelLibrary.models[1])
        var map = PhaseMap(width: 8, height: 8, matrixEntryIndex: 0,
                           phaseNames: state.phaseMapping.phases.map(\.model.displayName),
                           matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for i in [18, 19, 26, 27, 37] { map.results[i].verdict = .indexed; map.results[i].phaseIndex = 1 }
        state.phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: state.phaseMapping.phaseSignature,
            reference: state.phaseMapping.reference, matching: state.phaseMapping.matching,
            libraryEntryCount: 10, matrixEntryIndex: 0, matrixInPlaneDegrees: 0,
            worstChanceMatchPercent: 1, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: true, peakCount: 10,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0))))
        await state.publishPrecipitateClassificationFromPhaseMap()
        return state
    }

    private func activeObjectsNode(_ state: AppState) -> SessionLineage.Node? {
        state.replay.lineage.activeNodes().first { $0.kind == "precipitate_objects" }
    }

    /// Mutation: drop the `recordObjectsRunIfMinimumSizeChanged()` call from
    /// `publishPrecipitateObjectsProduct` -> the node keeps "1" and every
    /// assertion after the redraw goes red (the pre-S12 state); compare the
    /// recorded value with `String(report.minimumAreaPx)` inverted -> the
    /// unchanged-size half goes red (a redraw at the same size must not
    /// record a run).
    func testARedrawAtANewMinimumSizeIsRecordedAsItsOwnRun() async throws {
        let state = await classifiedState()
        let first = try XCTUnwrap(activeObjectsNode(state))
        XCTAssertEqual(first.parameters["minimum_object_area_px"], "1", "the run's own setting")
        state.publishPrecipitateObjectsProduct()
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], first.id)
        let nodesBefore = state.replay.lineage.nodes.count

        // A redraw at the SAME size records nothing new.
        state.publishPrecipitateObjectsProduct()
        XCTAssertEqual(state.replay.lineage.nodes.count, nodesBefore)
        XCTAssertEqual(activeObjectsNode(state)?.parameters["minimum_object_area_px"], "1")

        // A new minimum size: the run that drew the picture says so.
        state.precipitateClassification.minimumObjectAreaPx = 3
        state.refreshPrecipitateObjectsProductIfShown()
        let second = try XCTUnwrap(activeObjectsNode(state))
        XCTAssertEqual(second.parameters["minimum_object_area_px"], "3", "the node records what drew the picture")
        XCTAssertEqual(state.displayedProduct?.provenance["minimum_object_area_px"], "3")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], second.id,
                       "the picture names the run that drew it")
        XCTAssertEqual(state.replay.producedStep["precipitate_objects"], second.id)
    }

    /// The same, when the earlier run is no longer replaceable in place (an
    /// export consumed it): the redraw is a NEW node, and the old one keeps
    /// the size the exported file was drawn at. Mutations: as above (no record
    /// at all -> the new-node assertions go red).
    func testARedrawAfterAnExportKeepsTheExportedRunAsItWas() async throws {
        let state = await classifiedState()
        state.publishPrecipitateObjectsProduct()
        let first = try XCTUnwrap(activeObjectsNode(state))
        state.recordExportRun(format: "png", fileName: "objects.png", productKind: "precipitate_objects",
                              productStep: first.id)
        XCTAssertTrue(state.replay.lineage.hasChildren(first.id), "precondition: the export consumed the run")

        state.precipitateClassification.minimumObjectAreaPx = 3
        state.refreshPrecipitateObjectsProductIfShown()
        let second = try XCTUnwrap(activeObjectsNode(state))
        XCTAssertNotEqual(second.id, first.id, "a new run, not the exported one rewritten")
        XCTAssertEqual(state.replay.lineage.node(id: first.id)?.parameters["minimum_object_area_px"], "1")
        XCTAssertEqual(second.parameters["minimum_object_area_px"], "3")
        XCTAssertEqual(state.displayedProduct?.provenance["lineage_step"], second.id)
    }
}
