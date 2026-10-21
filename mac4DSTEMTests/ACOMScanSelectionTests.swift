import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import simd
@testable import mac4DSTEM

final class ACOMScanSelectionTests: XCTestCase {
    func testPreviewBoundsWorkAndExpandsCoarseBlocks() {
        let selection = ACOMScanSelection.preview(maxDimension: 4)
        XCTAssertEqual(
            selection.sourceIndices(width: 10, height: 6),
            [0, 3, 6, 9, 30, 33, 36, 39]
        )

        var map = ACOMScanResults(width: 10, height: 6, templateCount: 0)
        for source in selection.sourceIndices(width: 10, height: 6) {
            map.results[source] = OrientationResult(
                templateIndex: source,
                euler: .zero,
                score: Float(source + 1),
                secondScore: 0,
                phaseID: 0
            )
        }
        let expanded = map.expandedPreview(selection: selection)
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

    // MARK: Reliability runner-up selection (the kit's `ACOMMatcher.result(scores:bins:mirrored:)`, DiffractoKit 0.7.0)

    /// A real gold library of 40 beam directions and a matcher over it. `distinctDegrees` is the angle within which a template
    /// is the winner's neighbour and not a different orientation.
    private func reliabilityFixture(distinctDegrees: Double) throws -> (library: ACOMTemplateLibrary, matcher: ACOMMatcher) {
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: Crystal.gold, kMax: 1.2, nRadial: 8, nAzimuthal: 32, zoneAxisCount: 40,
            distinctOrientationDeg: distinctDegrees))
        return (plan.library, try XCTUnwrap(ACOMMatcher(library: plan.library)))
    }

    /// Scores: template 0 wins with 0.90; every other template within the limit of it (its neighbours) scores 0.89 *because*
    /// it is a near-duplicate; the one template farthest from it scores `farthest`; the rest 0.1. Returns the scores and
    /// whether the library has a neighbour and a different orientation at all.
    private func scores(_ library: ACOMTemplateLibrary, distinctDegrees: Double, farthest: Float)
        -> (scores: [Float], neighbours: Int) {
        let winner = library.zoneAxes[0]
        let limit = cos(distinctDegrees * .pi / 180)
        var scores = [Float](repeating: 0.1, count: library.count)
        scores[0] = 0.90
        var neighbours = 0, far = 0, farDot = 2.0
        for t in 1..<library.count {
            let d = simd_dot(library.zoneAxes[t], winner)
            if d > limit { scores[t] = 0.89; neighbours += 1 }
            if d < farDot { farDot = d; far = t }
        }
        scores[far] = farthest
        return (scores, neighbours)
    }

    func testRunnerUpSkipsTemplatesTooCloseToBeADifferentOrientation() throws {
        let (library, matcher) = try reliabilityFixture(distinctDegrees: 25)
        let (s, neighbours) = scores(library, distinctDegrees: 25, farthest: 0.40)
        XCTAssertGreaterThan(neighbours, 0, "the fixture needs near-duplicates of the winner")
        let result = matcher.result(scores: s, bins: [UInt32](repeating: 0, count: s.count),
                                    mirrored: [Bool](repeating: false, count: s.count))
        XCTAssertEqual(result.templateIndex, 0)
        XCTAssertEqual(result.score, 0.90, accuracy: 1e-6)
        // 0.89 belongs to the neighbours and must be skipped; the best genuinely different orientation scores 0.40.
        XCTAssertEqual(result.secondScore, 0.40, accuracy: 1e-6)
        XCTAssertGreaterThan(result.reliability, 0.5, "a clear winner must report high confidence")
    }

    func testZeroSeparationReproducesTheOldUnusableRunnerUp() throws {
        let (library, matcher) = try reliabilityFixture(distinctDegrees: 0)
        let (s, neighbours) = scores(library, distinctDegrees: 25, farthest: 0.40)
        XCTAssertGreaterThan(neighbours, 0)
        let result = matcher.result(scores: s, bins: [UInt32](repeating: 0, count: s.count),
                                    mirrored: [Bool](repeating: false, count: s.count))
        XCTAssertEqual(result.secondScore, 0.89, accuracy: 1e-6)
        // This is the failure being fixed: an unambiguous match reporting near-zero confidence because its own
        // neighbour was the runner-up.
        XCTAssertLessThan(result.reliability, 0.02)
    }

    func testGenuinelyAmbiguousMatchStillReportsLowConfidence() throws {
        let (library, matcher) = try reliabilityFixture(distinctDegrees: 25)
        let (s, _) = scores(library, distinctDegrees: 25, farthest: 0.88)    // a far-away orientation nearly ties
        let result = matcher.result(scores: s, bins: [UInt32](repeating: 0, count: s.count),
                                    mirrored: [Bool](repeating: false, count: s.count))
        XCTAssertEqual(result.secondScore, 0.88, accuracy: 1e-6)
        XCTAssertLessThan(result.reliability, 0.05, "a real tie must still read as low confidence")
    }

    // MARK: Radial deposition

    /// A peak whose radius is off by a fraction of a radial bin must still
    /// match its own template. With nearest-bin deposition it does not: the
    /// peak lands in a shell the template never occupies and contributes
    /// nothing, which is why a 0.5% Q-calibration error was enough to take the
    /// measured orientation error from 3° to 32° on synthetic patterns.
    func testPeaksSurviveRadialErrorSmallerThanABin() throws {
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: Crystal.gold, kMax: 1.2, zoneAxisCount: 96
        ))
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        let templateIndex = 23
        let invAngstromPerPixel = 0.01
        let origin: Float = 128

        func match(radialScaleError: Double) -> OrientationResult {
            let peaks = plan.templateSpots[templateIndex].map { spot -> BraggPeak in
                let radius = Double(spot.radius) / invAngstromPerPixel
                    * (1 + radialScaleError)
                let intensity = pow(Double(spot.weight), 1 / plan.intensityPower)
                return BraggPeak(
                    x: origin + Float(radius * cos(Double(spot.azimuth))),
                    y: origin + Float(radius * sin(Double(spot.azimuth))),
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

    func testBankWithNoDistinctAlternativeCannotClaimDoubt() throws {
        let (library, matcher) = try reliabilityFixture(distinctDegrees: 179)   // every template is the winner's neighbour
        var s = [Float](repeating: 0.89, count: library.count)
        s[0] = 0.9
        let result = matcher.result(scores: s, bins: [UInt32](repeating: 0, count: s.count),
                                    mirrored: [Bool](repeating: false, count: s.count))
        XCTAssertEqual(result.templateIndex, 0)
        XCTAssertEqual(result.secondScore, 0)
    }
}
