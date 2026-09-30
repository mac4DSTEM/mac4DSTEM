//
//  PhaseMappingResultSwitchTests.swift
//  Polish 2026-09-30 (Crystal Maps › Phase mapping): the matrix picker's
//  labels, the Evidence row's help, and the way back from the objects picture
//  and the match distance to the phase map. Wording and switching rules live
//  in pure functions, so they are tested without a view.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseMappingResultSwitchTests: XCTestCase {

    private func slot(_ modelIndex: Int, matrix: Bool = false,
                      _ u: Int, _ v: Int, _ w: Int) -> PhaseMappingSlot {
        PhaseMappingSlot(model: CrystalModelLibrary.models[modelIndex], isMatrix: matrix, u: u, v: v, w: w)
    }

    // MARK: 1. Matrix picker labels

    /// Mutation: `pickerLabels` returning the bare display name for a shared name.
    func testTwoSlotsOfOneStructureAreToldApartByZoneAxis() {
        let slots = [slot(0, matrix: true, 0, 0, 1), slot(1, 0, 1, 0), slot(1, 0, 0, 1)]
        let labels = PhaseMappingSlot.pickerLabels(slots)
        let name = CrystalModelLibrary.models[1].displayName
        XCTAssertEqual(labels[1], "\(name) [0 1 0]")
        XCTAssertEqual(labels[2], "\(name) [0 0 1]")
        XCTAssertEqual(Set(labels).count, 3, "two rows read identically")
    }

    /// A name that occurs once stays bare (the Phases rows already show its axis).
    /// Mutation: the zone axis appended unconditionally.
    func testAUniqueNameStaysBare() {
        let slots = [slot(0, matrix: true, 0, 0, 1), slot(1, 0, 1, 0)]
        XCTAssertEqual(PhaseMappingSlot.pickerLabels(slots),
                       slots.map { $0.model.displayName })
    }

    /// Same structure at the same axis (refused at run, but the list can hold
    /// it while the user edits): still no two identical rows. Mutation: the
    /// running number dropped.
    func testSameNameAndAxisGetsARunningNumber() {
        let slots = [slot(1, 0, 1, 0), slot(1, 0, 1, 0), slot(0, matrix: true, 0, 0, 1)]
        let labels = PhaseMappingSlot.pickerLabels(slots)
        XCTAssertEqual(Set(labels).count, 3, "\(labels)")
        XCTAssertTrue(labels[0].hasSuffix("#1") && labels[1].hasSuffix("#2"), "\(labels)")
        XCTAssertEqual(labels[2], slots[2].model.displayName)
    }

    // MARK: 2. Evidence help

    /// The row follows the SELECTED position; nothing in this app follows the pointer.
    /// Mutation: the old wording restored.
    func testEvidenceHelpNamesTheSelectedPositionNotTheCursor() {
        XCTAssertFalse(PhaseMapPresentation.evidenceHelp.lowercased().contains("cursor"))
        XCTAssertTrue(PhaseMapPresentation.evidenceHelp.contains("selected"))
    }

    // MARK: 3. The way back to the phase map

    /// Mutation: the "displayed == owned" branch removed, or its target changed.
    func testEachOwnerReadsShowPhaseMapWhileItsPictureIsOnScreen() {
        let objects = PhaseResultPicture.control(owning: .objects, displayedKind: "precipitate_objects")
        XCTAssertEqual(objects.title, "Show Phase Map")
        XCTAssertEqual(objects.target, .phaseMap)
        let distance = PhaseResultPicture.control(owning: .distance, displayedKind: "phase_match_distance")
        XCTAssertEqual(distance.title, "Show Phase Map")
        XCTAssertEqual(distance.target, .phaseMap)
    }

    /// Anything else on screen — the map, the other picture, another analysis's
    /// product, nothing — leaves each button its own job.
    func testOtherwiseEachOwnerKeepsItsOwnPicture() {
        for shown in ["phase_map", "phase_match_distance", "acom_orientation", nil] as [String?] {
            let c = PhaseResultPicture.control(owning: .objects, displayedKind: shown)
            XCTAssertEqual(c.title, "Show Objects"); XCTAssertEqual(c.target, .objects)
        }
        for shown in ["phase_map", "precipitate_objects", "acom_orientation", nil] as [String?] {
            let c = PhaseResultPicture.control(owning: .distance, displayedKind: shown)
            XCTAssertEqual(c.title, "Show Match Distance"); XCTAssertEqual(c.target, .distance)
        }
    }

    func testProductKindsMapToTheirPictures() {
        XCTAssertEqual(PhaseResultPicture(productKind: "phase_map"), .phaseMap)
        XCTAssertEqual(PhaseResultPicture(productKind: "precipitate_objects"), .objects)
        XCTAssertEqual(PhaseResultPicture(productKind: "phase_match_distance"), .distance)
        XCTAssertNil(PhaseResultPicture(productKind: "strain_exx"))
    }

    // MARK: the action: objects (or distance) -> phase map, nothing recomputed

    private func fixtureMap() -> PhaseMap {
        var map = PhaseMap(width: 6, height: 6, matrixEntryIndex: 0,
                           phaseNames: ["Al", "T1"], matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for (r, c) in [(1, 1), (1, 2), (2, 1), (2, 2)] {
            map.results[r * 6 + c].verdict = .indexed; map.results[r * 6 + c].phaseIndex = 1
        }
        return map
    }

    /// Mutation: `showPhaseResult(.phaseMap)` publishing the objects picture (or nothing).
    @MainActor
    func testShowPhaseResultSwitchesTheDisplayedProductBothWays() async throws {
        let appState = AppState()
        appState.phaseMapping.publish(fixtureMap(), ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: "fixture", reference: PhaseReferenceSettings(),
            matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan,
            worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0))))
        await appState.publishPrecipitateClassificationFromPhaseMap()

        appState.showPhaseResult(.phaseMap)
        XCTAssertEqual(appState.displayedProduct?.kind, "phase_map")
        appState.showPhaseResult(.objects)
        XCTAssertEqual(appState.displayedProduct?.kind, "precipitate_objects")
        // The way back: what the owner's button now does while objects are shown.
        let back = PhaseResultPicture.control(owning: .objects, displayedKind: appState.displayedProduct?.kind)
        appState.showPhaseResult(back.target)
        XCTAssertEqual(appState.displayedProduct?.kind, "phase_map")
        appState.showPhaseResult(.distance)
        XCTAssertEqual(appState.displayedProduct?.kind, "phase_match_distance")
        let back2 = PhaseResultPicture.control(owning: .distance, displayedKind: appState.displayedProduct?.kind)
        appState.showPhaseResult(back2.target)
        XCTAssertEqual(appState.displayedProduct?.kind, "phase_map")
    }
}
