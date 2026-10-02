//
//  PolishATests.swift
//  Lane A (Slot 4½ polish, 2026-10-02): the reconstruction display and the text of its numbers.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishATests: XCTestCase {
    private func result() -> SingleslicePtychographyResult {
        let array = PtychographyComplexArray(width: 2, height: 2, real: [1, 1, 1, 1], imaginary: [0, 0, 0, 0])
        return SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0.5],
            objectSamplingRowAngstrom: 0.25, objectSamplingColumnAngstrom: 0.25,
            options: SingleslicePtychographyOptions(), probeAberrations: PtychographyProbeAberrations())
    }

    /// A signed phase product leaves the diverging map on screen; the next brightness product must not inherit it.
    /// Mutation: drop the colormap assignment in `showParallaxProduct` -> the amplitude stays .rdbu (solid red).
    func testABrightnessProductDoesNotInheritADivergingColormap() {
        let state = AppState()
        state.changeMode(.singleslicePtychography)
        state.phaseContrast.singleslicePtychography = result()
        state.showParallaxProduct(.iterativePhase)
        XCTAssertEqual(state.resultPresentation.resultColormap, .rdbu)
        state.showParallaxProduct(.iterativeAmplitude)
        XCTAssertEqual(state.resultPresentation.resultColormap, .viridis)
        XCTAssertFalse(state.resultPresentation.resultColormap.isDiverging)
    }

    /// The per-product choice itself. Mutation: swap the two groups -> red.
    func testOnlySignedPhaseProductsAreDiverging() {
        for product in ParallaxResultProduct.allCases {
            let signed: Set<ParallaxResultProduct> = [.correctedPhase, .depth, .iterativePhase, .iterativeProbePhase]
            XCTAssertEqual(product.displayColormap.isDiverging, signed.contains(product), "\(product)")
        }
    }

    /// A tiny negative angle prints "0.00°", never "-0.00°". Mutation: a raw "%.2f°" -> "-0.00°".
    func testATinyNegativeRotationPrintsWithoutASign() {
        let tiny = -0.00001 * 180 / Double.pi   // -1e-5 rad = -0.00057 deg in degrees
        XCTAssertEqual(RQRotationConvention.degreesText(tiny, decimals: 2), "0.00°")
        XCTAssertEqual(String(format: "%.2f°", tiny), "-0.00°", "the raw format this replaced")
    }

    /// Mutation: the raw stored unit "A" -> "A/px".
    func testThePublicationCaptionNamesAngstromWithItsSymbol() {
        let state = AppState()
        state.publishProduct(kind: "t", displayName: "t", valueUnits: "rad", payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3])),
                             sampling: ProductSampling(row: 0.5, column: 0.5, units: "A"))
        XCTAssertTrue(state.publicationCaption.contains("0.5 Å/px"), state.publicationCaption)
    }

    /// Mutation: always print both steps -> "5 × 5"; or always one -> "5" for 5 × 6.
    func testSquareSamplingCollapsesAndUnequalKeepsBoth() {
        XCTAssertEqual(SessionResultPresentation.sampling(row: 5, column: 5, units: "A"), "sampling 5 Å/px")
        XCTAssertEqual(SessionResultPresentation.sampling(row: 5, column: 6, units: "A"), "sampling 5 × 6 Å/px")
    }
}
