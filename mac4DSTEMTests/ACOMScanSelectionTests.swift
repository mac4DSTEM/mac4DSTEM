import XCTest
import DSTEMCore
import simd
@testable import mac4DSTEM

final class ACOMScanSelectionTests: XCTestCase {
    func testPreviewBoundsWorkAndExpandsCoarseBlocks() {
        let selection = ACOMScanSelection.preview(maxDimension: 4)
        XCTAssertEqual(
            selection.sourceIndices(width: 10, height: 6),
            [0, 3, 6, 9, 30, 33, 36, 39]
        )

        var map = OrientationMap(width: 10, height: 6)
        for source in selection.sourceIndices(width: 10, height: 6) {
            map.results[source] = OrientationResult(
                templateIndex: source,
                euler: .zero,
                score: Float(source + 1),
                secondScore: 0,
                phaseID: 0
            )
        }
        let expanded = selection.expandedPreview(map)
        XCTAssertEqual(expanded[2, 2].templateIndex, 0)
        XCTAssertEqual(expanded[5, 1].templateIndex, 3)
        XCTAssertEqual(expanded[9, 5].templateIndex, 39)
    }

    func testSelectedRegionClipsAtDatasetEdges() {
        let selection = ACOMScanSelection.square(centerX: 0, centerY: 1, radius: 2)
        XCTAssertEqual(
            selection.sourceIndices(width: 5, height: 4),
            [0, 1, 2, 5, 6, 7, 10, 11, 12, 15, 16, 17]
        )
        XCTAssertEqual(selection.positionCount(width: 5, height: 4), 12)
    }

    func testQualityPresetsExposeIncreasingTemplateBudgets() {
        XCTAssertEqual(ACOMQualityPreset.fast.templateCount, 96)
        XCTAssertEqual(ACOMQualityPreset.balanced.templateCount, 200)
        XCTAssertEqual(ACOMQualityPreset.best.templateCount, 400)
    }

    // MARK: Reliability runner-up selection

    /// Four zone axes: the winner, a near-duplicate 2° away that scores almost
    /// as well *because* it is a near-duplicate, and two genuinely different
    /// orientations. Reliability must be measured against a real alternative,
    /// not against the winner's own neighbour.
    private func reliabilityFixture() -> (axes: [SIMD3<Double>], scores: [Float]) {
        let twoDegrees = 2.0 * .pi / 180
        return (
            axes: [
                SIMD3(0, 0, 1),
                simd_normalize(SIMD3(sin(twoDegrees), 0, cos(twoDegrees))),
                simd_normalize(SIMD3(1, 0, 1)),
                simd_normalize(SIMD3(1, 1, 1)),
            ],
            scores: [0.90, 0.89, 0.40, 0.20]
        )
    }

    func testRunnerUpSkipsTemplatesTooCloseToBeADifferentOrientation() {
        let fixture = reliabilityFixture()
        let selected = selectOrientation(
            zoneAxes: fixture.axes, scores: fixture.scores,
            bins: [0, 0, 0, 0], distinctOrientationRad: 10 * .pi / 180
        )
        XCTAssertEqual(selected.template, 0)
        XCTAssertEqual(selected.score, 0.90, accuracy: 1e-6)
        // 0.89 belongs to the 2° neighbour and must be skipped; the best
        // genuinely different orientation scores 0.40.
        XCTAssertEqual(selected.secondScore, 0.40, accuracy: 1e-6)
        let reliability = 1 - selected.secondScore / selected.score
        XCTAssertGreaterThan(reliability, 0.5,
                             "a clear winner must report high confidence")
    }

    func testZeroSeparationReproducesTheOldUnusableRunnerUp() {
        let fixture = reliabilityFixture()
        let selected = selectOrientation(
            zoneAxes: fixture.axes, scores: fixture.scores,
            bins: [0, 0, 0, 0], distinctOrientationRad: 0
        )
        XCTAssertEqual(selected.secondScore, 0.89, accuracy: 1e-6)
        // This is the failure being fixed: an unambiguous match reporting
        // near-zero confidence because its own neighbour was the runner-up.
        XCTAssertLessThan(1 - selected.secondScore / selected.score, 0.02)
    }

    func testGenuinelyAmbiguousMatchStillReportsLowConfidence() {
        var fixture = reliabilityFixture()
        fixture.scores[2] = 0.88          // a far-away orientation nearly ties
        let selected = selectOrientation(
            zoneAxes: fixture.axes, scores: fixture.scores,
            bins: [0, 0, 0, 0], distinctOrientationRad: 10 * .pi / 180
        )
        XCTAssertEqual(selected.secondScore, 0.88, accuracy: 1e-6)
        XCTAssertLessThan(1 - selected.secondScore / selected.score, 0.05,
                          "a real tie must still read as low confidence")
    }

    // MARK: Radial deposition

    /// A peak whose radius is off by a fraction of a radial bin must still
    /// match its own template. With nearest-bin deposition it does not: the
    /// peak lands in a shell the template never occupies and contributes
    /// nothing, which is why a 0.5% Q-calibration error was enough to take the
    /// measured orientation error from 3° to 32° on synthetic patterns.
    func testPeaksSurviveRadialErrorSmallerThanABin() throws {
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: .gold, kMax: 1.2, zoneAxisCount: 96
        ))
        let matcher = try XCTUnwrap(OrientationMatcher(plan: plan))
        let templateIndex = 23
        let invAngstromPerPixel = 0.01
        let origin: Float = 128

        func match(radialScaleError: Double) -> OrientationResult {
            let peaks = plan.templateSpots[templateIndex].map { spot -> BraggPeak in
                let radius = Double(spot.r) / invAngstromPerPixel
                    * (1 + radialScaleError)
                let intensity = pow(Double(spot.weight), 1 / plan.intensityPower)
                return BraggPeak(
                    x: origin + Float(radius * cos(Double(spot.azim))),
                    y: origin + Float(radius * sin(Double(spot.azim))),
                    intensity: Float(intensity)
                )
            }
            return matcher.match(peaks: peaks, originX: origin, originY: origin,
                                 invAngstromPerPixel: invAngstromPerPixel)
        }

        let exact = match(radialScaleError: 0)
        XCTAssertEqual(exact.templateIndex, templateIndex)

        // 1% of a 1 Å⁻¹ radius is ~0.27 of a radial bin — well inside one bin,
        // and squarely in the range a first-ring Q calibration can be off by.
        let perturbed = match(radialScaleError: 0.01)
        XCTAssertEqual(perturbed.templateIndex, templateIndex,
                       "sub-bin radial error must not change the match")
        XCTAssertGreaterThan(
            perturbed.score, exact.score * 0.8,
            "sub-bin radial error must not collapse the correlation"
        )
    }

    func testBankWithNoDistinctAlternativeCannotClaimDoubt() {
        let twoDegrees = 2.0 * .pi / 180
        let selected = selectOrientation(
            zoneAxes: [SIMD3(0, 0, 1),
                       simd_normalize(SIMD3(sin(twoDegrees), 0, cos(twoDegrees)))],
            scores: [0.9, 0.89], bins: [0, 0],
            distinctOrientationRad: 10 * .pi / 180
        )
        XCTAssertEqual(selected.secondScore, 0)
    }
}
