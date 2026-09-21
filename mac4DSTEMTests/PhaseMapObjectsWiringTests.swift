//
//  PhaseMapObjectsWiringTests.swift
//  Session S3 (`docs/v3-precipitates-and-materials-project-plan.md`): the
//  classifier-rule UI default, the additive provenance keys, the
//  PhaseMap → ClassMapObjects bridge, the pixel-size refusal, and the
//  clear-on-dataset-change coupling. `PhaseMapObjectsTests.swift` already
//  covers `PrecipitateSegmentation.classObjects` itself; this file covers
//  only what Session S3 wired ON TOP of it.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PhaseMapObjectsWiringTests: XCTestCase {

    // MARK: - Fixture: a 6 x 6 map, matrix phase 0, precipitate phase 1 in
    // two 8-connected blobs, two not-indexed positions.
    //
    //   col: 0 1 2 3 4 5
    // row0:  0 0 0 0 0 N
    // row1:  0 1 1 0 0 0     blob A: 2 x 2 at (1,1)-(2,2), phase 1
    // row2:  0 1 1 0 0 0
    // row3:  0 0 0 0 0 0
    // row4:  0 0 0 0 1 1     blob B: 1 x 2 at (4,4)-(4,5), phase 1
    // row5:  N 0 0 0 0 0
    //
    // Not indexed: (0,5) and (5,0). Total 36; not indexed 2; phase-1 pixels
    // 6 (4 + 2); matrix 28. Analysed area = 36 - 2 = 34.

    private func sixBySixMap() -> PhaseMap {
        var map = PhaseMap(width: 6, height: 6, matrixEntryIndex: 0,
                           phaseNames: ["Al", "T1"], matrixPhaseIndex: 0)
        for i in map.results.indices {
            map.results[i].verdict = .matrix
            map.results[i].phaseIndex = 0
        }
        func indexed(_ row: Int, _ col: Int, phase: Int32) {
            let i = row * 6 + col
            map.results[i].verdict = .indexed
            map.results[i].phaseIndex = phase
        }
        indexed(1, 1, phase: 1); indexed(1, 2, phase: 1)
        indexed(2, 1, phase: 1); indexed(2, 2, phase: 1)
        indexed(4, 4, phase: 1); indexed(4, 5, phase: 1)
        map.results[0 * 6 + 5].verdict = .notIndexed
        map.results[5 * 6 + 0].verdict = .notIndexed
        return map
    }

    private func runRecord() -> PhaseMappingProduct.RunRecord {
        PhaseMappingProduct.RunRecord(
            phaseSignature: "fixture", reference: PhaseReferenceSettings(),
            matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan,
            worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0
        )
    }

    // MARK: - (a) The picker's rule -> Minimum-intensity default, both ways

    func testMinimumIntensityFractionDefaultsByRule() {
        XCTAssertEqual(PhaseMappingRuleDefaults.minimumIntensityFraction(for: .knownVariants), 0,
                       "the paper's references are geometric, not intensity-ranked")
        XCTAssertEqual(PhaseMappingRuleDefaults.minimumIntensityFraction(for: .search),
                       PhaseReferenceSettings().minimumIntensityFraction,
                       "search keeps the shipped default, read from the settings struct itself")
    }

    // MARK: - (b) Provenance additions: present for known variants, and the
    // default's own output must not move at all.

    func testProvenanceAdditionsOnlyForKnownVariants() {
        var search = PhaseVectorSettings()
        search.classificationRule = .search
        XCTAssertTrue(PhaseMappingRuleDefaults.provenanceAdditions(for: search).isEmpty,
                      "the shipped default's phaseProvenance string must be byte-identical to before this session")

        var known = PhaseVectorSettings()
        known.classificationRule = .knownVariants
        known.residualCutoffInvAngstrom = 0.07
        known.directMatrixMaximumVectors = 1
        let additions = PhaseMappingRuleDefaults.provenanceAdditions(for: known)
        XCTAssertEqual(additions["classification_rule"], "known_variants")
        XCTAssertEqual(additions["residual_cutoff_inv_angstrom"], "0.07")
        XCTAssertEqual(additions["direct_matrix_maximum_vectors"], "1")
        XCTAssertEqual(additions.count, 3, "exactly the three named keys, nothing else")
    }

    // MARK: - (c) The bridge: PhaseMap -> labels/roles -> classObjects
    //
    // BREAK-FIRST, done by hand and reverted (not left in the tree — the
    // bridge has no runtime switch to gate a permanent mutation test on):
    // with `PhaseMapObjectsBridge.labeledMap`'s roles construction changed to
    // fold `notIndexedLabel` into `matrix` instead of `notIndexed`
    // (`matrix.insert(notIndexedLabel)`, `notIndexed: []`), the two
    // not-indexed positions stop being excluded from the analysed area and
    // `result.analysedPixels` came back 36, not 34 — this test went red on
    // exactly the assertion it exists to protect. Reverted before committing.

    func testBridgeProducesTwoObjectsForPhaseOneAndDenominator34() throws {
        let map = sixBySixMap()
        let labeled = PhaseMapObjectsBridge.labeledMap(from: map)
        XCTAssertEqual(labeled.roles.matrix, [0])
        XCTAssertEqual(labeled.roles.precipitateClasses, [1])
        XCTAssertEqual(labeled.roles.notIndexed, [PhaseMapObjectsBridge.notIndexedLabel])

        let result = PrecipitateSegmentation.classObjects(
            labels: labeled.labels, width: map.width, height: map.height,
            roles: labeled.roles, pixelSize: nil, pixelUnit: nil
        )
        XCTAssertEqual(result.analysedPixels, 34, "36 positions minus the 2 not-indexed")
        XCTAssertEqual(result.notIndexedPixels, 2)
        let phaseOne = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertEqual(phaseOne.objects.count, 2, "the two 8-connected blobs, kept apart")
        XCTAssertEqual(phaseOne.pixelCount, 6)
    }

    // MARK: - (d) No real-space calibration -> counted, never a density

    func testUncalibratedDatasetPublishesCountsWithoutDensity() throws {
        let appState = AppState()
        appState.phaseMapping.publish(sixBySixMap(), ranWith: runRecord())
        appState.calibrationSession.calibration.rPixelSize = nil
        appState.calibrationSession.calibration.rPixelUnits = nil

        appState.publishPrecipitateClassificationFromPhaseMap()

        let result = try XCTUnwrap(appState.precipitateClassification.result)
        let phaseOne = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertEqual(phaseOne.objects.count, 2, "objects are still counted without a pixel size")
        XCTAssertNil(phaseOne.density.arealDensity, "no calibration, no density — never a number")
        XCTAssertNil(phaseOne.density.pixelSize)
    }

    func testCalibratedDatasetPublishesDensity() throws {
        let appState = AppState()
        appState.phaseMapping.publish(sixBySixMap(), ranWith: runRecord())
        appState.calibrationSession.calibration.rPixelSize = 2.0
        appState.calibrationSession.calibration.rPixelUnits = "nm"

        appState.publishPrecipitateClassificationFromPhaseMap()

        let result = try XCTUnwrap(appState.precipitateClassification.result)
        let phaseOne = try XCTUnwrap(result.classes.first { $0.label == 1 })
        // Blob B sits at columns 4-5 of a 6-wide map, so it touches the right
        // scan edge and is excluded from the density count (matching
        // `PhaseMapObjectsTests`'s own A2/edge convention) — only blob A is
        // counted. Caught by running this once before adding the comment:
        // the first version assumed both blobs were interior and asserted
        // 2.0 in the numerator, which failed against the real edge flag
        // (0.014705882... expected vs 0.007352941... actual) — fixed here,
        // not in the production code, since the production code was right.
        let expected = 1.0 / (34.0 * 2.0 * 2.0)
        let density = try XCTUnwrap(phaseOne.density.arealDensity)
        XCTAssertEqual(density, expected, accuracy: 1e-9)
        XCTAssertEqual(phaseOne.density.pixelUnit, "nm")
    }

    // MARK: - (e) Clearing drops the published result

    func testClearingTheProductDropsThePublishedResult() {
        let product = PrecipitateClassificationProduct()
        let result = PrecipitateSegmentation.classObjects(
            labels: [0], width: 1, height: 1,
            roles: PrecipitateSegmentation.LabelRoles(
                precipitateClasses: [], matrix: [0], notIndexed: []),
            pixelSize: nil, pixelUnit: nil
        )
        product.publish(result)
        XCTAssertNotNil(product.result)
        product.clear()
        XCTAssertNil(product.result, "a cleared product must not outlive the dataset it described")
    }

    func testAppStatePublishesThenClearsAlongsideThePhaseMap() {
        let appState = AppState()
        appState.phaseMapping.publish(sixBySixMap(), ranWith: runRecord())
        appState.calibrationSession.calibration.rPixelSize = 2.0
        appState.calibrationSession.calibration.rPixelUnits = "nm"
        appState.publishPrecipitateClassificationFromPhaseMap()
        XCTAssertNotNil(appState.precipitateClassification.result)

        // The same coupling `AppState+Open.swift`'s dataset-activation path
        // exercises: `phaseMapping.clear()` and `precipitateClassification
        // .clear()` are adjacent calls there, both reached on every dataset
        // change.
        appState.phaseMapping.clear()
        appState.precipitateClassification.clear()
        XCTAssertNil(appState.phaseMapping.map)
        XCTAssertNil(appState.precipitateClassification.result)
    }
}
