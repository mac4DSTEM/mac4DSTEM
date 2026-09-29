//
//  AlMgSiPresetTests.swift
//  The Al–Mg–Si phase-mapping preset (Add Phase ▸ Presets): exactly three
//  slots, their zones, the classifier — and nothing else. The cube's
//  calibration (ellipse, Q, R) is a property of that dataset and is never
//  part of a preset (CLAUDE.md, the threshold rule).
//
//  Mutations these were broken against (each must turn a test red):
//   1. flip the two β″ zones ([0 1 0] / [0 0 1] swapped)       -> testSlotsAndZones
//   2. mark a β″ slot as the matrix, or drop the Al matrix      -> testSlotsAndZones
//   3. leave the classifier at .search                          -> testSlotsAndZones
//   4. also reset `matching` to defaults / write Q or an
//      orientation relationship into the preset                 -> testLeavesTolerancesAndCalibrationUntouched
//   5. append to `phases` instead of replacing it               -> testReplacesAnExistingList
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class AlMgSiPresetTests: XCTestCase {

    /// Any structure that is not Al stands in for the β″ CIF the user supplies.
    private var beta: CrystalModel { CrystalModelLibrary.model(id: "mg_hcp")! }

    func testSlotsAndZones() throws {
        let product = PhaseMappingProduct()
        product.applyAlMgSiPreset(precipitate: beta)

        XCTAssertEqual(product.phases.count, 3)
        XCTAssertEqual(product.phases.map(\.isMatrix), [true, false, false])
        XCTAssertEqual(product.phases.map(\.model.id), ["al_fcc", beta.id, beta.id])
        XCTAssertEqual(product.phases.map(\.zoneAxis),
                       [SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(0, 0, 1)])
        XCTAssertTrue(product.phases.allSatisfy { $0.orientationRelationshipText.isEmpty },
                      "\"Parallel to matrix\" stays empty")
        XCTAssertTrue(product.phases.allSatisfy { $0.excitationSlabInvAngstrom == nil })
        XCTAssertEqual(product.matching.classificationRule, .knownVariants)
        XCTAssertEqual(product.reference.minimumIntensityFraction,
                       PhaseMappingRuleDefaults.minimumIntensityFraction(for: .knownVariants))
        XCTAssertNil(product.runRefusal, "the preset is a runnable list, with distinct slots")
    }

    func testLeavesTolerancesAndCalibrationUntouched() throws {
        let state = AppState()
        // A deliberately non-default tolerance set and a calibration to compare.
        state.phaseMapping.matching.pairRadiusInvAngstrom = 0.0123
        state.phaseMapping.matching.matrixToleranceInvAngstrom = 0.0234
        state.phaseMapping.matching.residualCutoffInvAngstrom = 0.0345
        state.phaseMapping.matching.maximumVectorInvAngstrom = 1.5
        state.phaseMapping.reference.kMaxInvAngstrom = 1.7
        state.phaseMapping.reference.inPlaneStepDeg = 3.5
        let tolerancesBefore = state.phaseMapping.matching
        let referenceBefore = state.phaseMapping.reference
        let scaleBefore = state.acomSession.exploratoryScale
        let ellipseBefore = state.calibrationSession.lastEllipseFit
        let rotationBefore = state.lastRotationResult

        state.phaseMapping.applyAlMgSiPreset(precipitate: beta)

        var expectedMatching = tolerancesBefore
        expectedMatching.classificationRule = .knownVariants
        XCTAssertEqual(state.phaseMapping.matching, expectedMatching,
                       "only the classifier changes; every tolerance is as it was")
        var expectedReference = referenceBefore
        expectedReference.minimumIntensityFraction =
            PhaseMappingRuleDefaults.minimumIntensityFraction(for: .knownVariants)
        XCTAssertEqual(state.phaseMapping.reference, expectedReference,
                       "only the rule's own intensity floor follows the classifier")
        XCTAssertEqual(state.acomSession.exploratoryScale, scaleBefore)
        XCTAssertEqual(state.calibrationSession.lastEllipseFit == nil, ellipseBefore == nil)
        XCTAssertEqual(state.lastRotationResult == nil, rotationBefore == nil)
    }

    func testReplacesAnExistingList() throws {
        let product = PhaseMappingProduct()
        _ = product.add(CrystalModelLibrary.model(id: "cu_fcc")!)
        _ = product.add(CrystalModelLibrary.model(id: "fe_bcc")!)
        product.applyAlMgSiPreset(precipitate: beta)
        XCTAssertEqual(product.phases.map(\.model.id), ["al_fcc", beta.id, beta.id],
                       "the preset replaces the list; it does not extend it")
    }
}
