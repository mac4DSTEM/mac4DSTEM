import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Seam 1 (`Session/PhaseContrastProduct.swift`, docs/appstate-seams-plan.md):
/// the one owner of the Parallax and single-slice ptychography products and
/// their run controls. These pin the seam's contracts — the pre-seam default
/// values, a direct run-control mutation (there are no `publish`/`clear`
/// methods on this owner; see the type's header for why it stays plain
/// `package var` rather than following `StrainProduct`'s
/// `private(set)`-plus-method shape), and the two `didSet` cascades that
/// invalidate later stages when an earlier one reruns.
@MainActor
final class PhaseContrastProductTests: XCTestCase {

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

    private func syntheticAlignment(completedBins: [Int] = [4, 2, 1]) -> ParallaxAlignmentResult {
        ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [4, 2, 1],
            completedBins: completedBins, upsampleFactor: 8,
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

    func testConstructionDefaults() {
        let product = PhaseContrastProduct()

        XCTAssertNil(product.parallaxPreprocess)
        XCTAssertNil(product.parallaxAberrationFit)
        XCTAssertNil(product.parallaxCorrection)
        XCTAssertNil(product.parallaxSubpixel)
        XCTAssertNil(product.parallaxDepth)
        XCTAssertNil(product.singleslicePtychography)
        XCTAssertNil(product.parallaxHigherOrderFit)
        XCTAssertNil(product.parallaxAlignment)

        XCTAssertEqual(product.parallaxKDEUpsampleFactor, 0)
        XCTAssertEqual(product.parallaxKDESigmaPixels, 0.125)
        XCTAssertFalse(product.parallaxKDELowpass)
        XCTAssertEqual(product.parallaxKDELanczosOrder, 0)
        XCTAssertEqual(product.parallaxPositionCorrectionIterations, 0)
        XCTAssertFalse(product.parallaxPositionCorrectionCheckerboard)
        XCTAssertEqual(product.parallaxDepthStartAngstrom, -256)
        XCTAssertEqual(product.parallaxDepthEndAngstrom, 256)
        XCTAssertEqual(product.parallaxDepthPlaneCount, 33)
        XCTAssertTrue(product.parallaxDepthUseFullFit)
        XCTAssertEqual(product.parallaxDepthInformationLimit, 0)
        XCTAssertEqual(product.parallaxDepthInformationPower, 1)
        XCTAssertEqual(product.parallaxDepthSelectedIndex, 0)
        XCTAssertEqual(product.parallaxResultProduct, .preprocess)
        XCTAssertEqual(product.parallaxQLowpassInvAngstrom, 0)
        XCTAssertEqual(product.parallaxQHighpassInvAngstrom, 0)
    }

    /// Run controls are plain `package var`, mutated directly by every
    /// orchestration call site — this is that same shape, pinned once.
    func testDirectMutationSetsTheRunControl() {
        let product = PhaseContrastProduct()

        product.parallaxDepthPlaneCount = 5
        product.parallaxResultProduct = .depth

        XCTAssertEqual(product.parallaxDepthPlaneCount, 5)
        XCTAssertEqual(product.parallaxResultProduct, .depth)
    }

    /// A new (or reset) alignment invalidates every later stage — the
    /// cascade `alignParallaxNextLevel`/`resetParallaxAlignment` depend on to
    /// keep a stale fit/subpixel/depth product from surviving a rerun.
    func testAssigningAlignmentInvalidatesLaterStages() {
        let product = PhaseContrastProduct()
        product.parallaxAberrationFit = syntheticLowOrderFit()
        product.parallaxHigherOrderFit = syntheticHigherOrderFit()
        product.parallaxSubpixel = syntheticSubpixel()
        product.parallaxDepth = syntheticDepth()

        product.parallaxAlignment = syntheticAlignment()

        XCTAssertNil(product.parallaxAberrationFit,
                     "a new alignment must invalidate the aberration fit computed from the old one")
        XCTAssertNil(product.parallaxHigherOrderFit,
                     "a new alignment must invalidate the higher-order fit computed from the old one")
        XCTAssertNil(product.parallaxSubpixel,
                     "a new alignment must invalidate the KDE subpixel reconstruction")
        XCTAssertNil(product.parallaxDepth,
                     "a new alignment must invalidate depth sections computed from the old fit")
    }

    /// A higher-order re-fit invalidates the phase correction and depth
    /// sections computed from the PRIOR fit — a narrower cascade than
    /// alignment's, so it must not also clear the aberration fit or subpixel
    /// reconstruction (those survive a re-fit).
    func testAssigningHigherOrderFitInvalidatesCorrectionAndDepthOnly() {
        let product = PhaseContrastProduct()
        product.parallaxAberrationFit = syntheticLowOrderFit()
        product.parallaxSubpixel = syntheticSubpixel()
        product.parallaxCorrection = syntheticCorrection()
        product.parallaxDepth = syntheticDepth()

        product.parallaxHigherOrderFit = syntheticHigherOrderFit()

        XCTAssertNil(product.parallaxCorrection,
                     "a new higher-order fit must invalidate the phase correction computed from the old one")
        XCTAssertNil(product.parallaxDepth,
                     "a new higher-order fit must invalidate depth sections computed from the old one")
        XCTAssertNotNil(product.parallaxAberrationFit,
                        "the low-order fit is not touched by the higher-order didSet")
        XCTAssertNotNil(product.parallaxSubpixel,
                        "the subpixel reconstruction does not depend on the higher-order fit")
    }

    /// Seam rule (docs/appstate-seams-plan.md, "What a seam is"): AppState
    /// holds the owner with no forwarding properties. Mirrors
    /// `StrainProductTests.testAppStateHoldsTheSeamWithoutForwardingProperties`.
    func testAppStateHoldsTheSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("phaseContrast"), "the facade holds the seam")
        let forwarded = names.filter { $0.hasPrefix("phaseContrast") && $0 != "phaseContrast" }
        XCTAssertTrue(
            forwarded.isEmpty,
            "no phaseContrast* stored property may shadow the seam: \(forwarded)"
        )
        // Also: no stray `parallax*`/`singleslicePtychography` stored
        // property may remain directly on AppState after the move.
        let stray = names.filter {
            ($0.hasPrefix("parallax") || $0 == "singleslicePtychography")
        }
        XCTAssertTrue(stray.isEmpty, "parallax state must live on phaseContrast, not AppState: \(stray)")
    }
}
