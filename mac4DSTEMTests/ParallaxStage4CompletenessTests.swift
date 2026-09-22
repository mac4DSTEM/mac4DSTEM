import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// `UI/PhaseSettings.swift`'s `ParallaxStageSections.stageIsComplete(4)` used
/// to read `phaseContrast.singleslicePtychography != nil` as an alternate
/// completion signal — a copy-paste survivor from the 2026-09-04 SwiftUI
/// rewrite (`345c7c7`) with nothing to do with parallax: single-slice
/// ptychography is a wholly independent task of `WorkspaceArea.reconstruct`.
/// Running it alone, with zero parallax stages run, marked the parallax
/// pipeline's last stage "Complete" (Gate D, 2026-09-22). Pinned here
/// directly on the extracted pure function (`parallaxStage4IsComplete`)
/// rather than through the view.
@MainActor
final class ParallaxStage4CompletenessTests: XCTestCase {

    private func syntheticSubpixel() -> ParallaxSubpixelResult {
        ParallaxSubpixelResult(
            upsampleFactor: 1, brightFieldUpsampleLimit: 1, darkFieldUpsampleLimit: 1,
            kdeSigmaPixels: 0.125, lowpassFilter: false, lanczosOrder: nil,
            paddedHeight: 1, paddedWidth: 1, paddedBF: [0],
            croppedBF: FloatImage(width: 1, height: 1, pixels: [0]),
            outputSamplingAngstrom: 1, probeShiftRows: [], probeShiftColumns: [],
            positionCorrectionScores: []
        )
    }

    private func syntheticDepth() -> ParallaxDepthResult {
        ParallaxDepthResult(
            depthsAngstrom: [0], paddedStack: [0], paddedHeight: 1, paddedWidth: 1,
            scanHeight: 1, scanWidth: 1, samplingAngstrom: 1, usedFullFit: true,
            informationLimitInvAngstrom: nil, informationPower: 1
        )
    }

    private func syntheticSingleslicePtychography() -> SingleslicePtychographyResult {
        let array = PtychographyComplexArray(width: 1, height: 1, real: [0], imaginary: [0])
        return SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0],
            objectSamplingRowAngstrom: 1, objectSamplingColumnAngstrom: 1,
            options: SingleslicePtychographyOptions()
        )
    }

    private func syntheticLowOrderFit() -> ParallaxAberrationFitResult {
        ParallaxAberrationFitResult(
            measuredShifts: [], fittedShifts: [], rotationRad: 0,
            c1Angstrom: 0, c12aAngstrom: 0, c12bAngstrom: 0,
            rmsResidualAngstrom: 0, forceTranspose: false,
            forcedRotationAngleDegrees: nil
        )
    }

    private func syntheticHigherOrderFit() -> ParallaxHigherOrderAberrationFitResult {
        ParallaxHigherOrderAberrationFitResult(
            lowOrder: syntheticLowOrderFit(), terms: [], coefficientsAngstrom: [],
            fittedShifts: [], rmsResidualAngstrom: 0, fitMethod: .recursive
        )
    }

    private func syntheticAlignment() -> ParallaxAlignmentResult {
        ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [4, 2, 1],
            completedBins: [4, 2, 1], upsampleFactor: 8,
            groups: [], groupShifts: [], totalShifts: [],
            shiftedStack: [], shiftedMasks: [], reconstructionMask: [],
            alignedBF: [], errorHistory: [0],
            scanHeight: 1, scanWidth: 1, stackHeight: 1, stackWidth: 1
        )
    }

    private func syntheticCorrection() -> ParallaxAberrationCorrectionResult {
        ParallaxAberrationCorrectionResult(
            paddedPhase: [], correctedPhase: FloatImage(width: 1, height: 1, pixels: [0]),
            chiEven: [], chiOdd: [], transferReal: [], transferImaginary: [],
            samplingAngstrom: 1, usedFullFit: true,
            qLowpassInvAngstrom: nil, qHighpassInvAngstrom: nil, butterworthOrder: 2
        )
    }

    func testFreshProductIsNotComplete() {
        XCTAssertFalse(parallaxStage4IsComplete(PhaseContrastProduct()))
    }

    func testSingleslicePtychographyAloneDoesNotCompleteTheParallaxStage() {
        let product = PhaseContrastProduct()
        product.singleslicePtychography = syntheticSingleslicePtychography()
        XCTAssertFalse(
            parallaxStage4IsComplete(product),
            "single-slice ptychography is an independent task; it must not mark the parallax pipeline's last stage complete"
        )
    }

    func testUpsampledSubpixelResultCompletesTheStage() {
        let product = PhaseContrastProduct()
        product.parallaxSubpixel = syntheticSubpixel()
        XCTAssertTrue(parallaxStage4IsComplete(product))
    }

    func testDepthSectioningResultCompletesTheStage() {
        let product = PhaseContrastProduct()
        product.parallaxDepth = syntheticDepth()
        XCTAssertTrue(parallaxStage4IsComplete(product))
    }

    // MARK: - Negative controls: an earlier stage's own product must not leak in
    //
    // Gate B (2026-09-22): the suite above pinned that `singleslicePtychography`
    // no longer completes stage 4, but had no control for the equally-easy
    // mistake of an accidental extra clause on an EARLIER parallax stage's own
    // product — e.g. `parallaxCorrection != nil || parallaxSubpixel != nil` (a
    // one-token typo away from the real fix) passed every test above
    // undetected. `parallaxAlignment`, `parallaxHigherOrderFit` and
    // `parallaxCorrection` are covered directly (their fixtures already exist,
    // shared with `PhaseContrastProductTests`); `parallaxPreprocess` is not —
    // its result type nests a `ParallaxPhysicalCalibration` with no existing
    // test fixture anywhere in this suite, and it is the switch's most
    // structurally distant case, not a neighbor `stageIsComplete`'s `default`
    // clause could plausibly absorb by a one-token slip the way the other
    // three could.

    func testAlignmentAloneDoesNotCompleteTheStage() {
        let product = PhaseContrastProduct()
        product.parallaxAlignment = syntheticAlignment()
        XCTAssertFalse(parallaxStage4IsComplete(product))
    }

    func testHigherOrderFitAloneDoesNotCompleteTheStage() {
        let product = PhaseContrastProduct()
        product.parallaxHigherOrderFit = syntheticHigherOrderFit()
        XCTAssertFalse(parallaxStage4IsComplete(product))
    }

    func testCorrectionAloneDoesNotCompleteTheStage() {
        let product = PhaseContrastProduct()
        product.parallaxCorrection = syntheticCorrection()
        XCTAssertFalse(parallaxStage4IsComplete(product))
    }
}
