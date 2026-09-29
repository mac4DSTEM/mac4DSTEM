import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Gate D (2026-09-29): `currentScalarPersistenceMetadata` guarded its
/// ptychography branch on `.ptychography` only, but single-slice ptychography
/// runs in its own mode, so its published product took the SCAN's R pixel size
/// (and no engine provenance) instead of the object sampling in Å. Pinned here
/// through `showParallaxProduct`, the site that publishes it.
@MainActor
final class SingleslicePtychographyExportTests: XCTestCase {

    private func result() -> SingleslicePtychographyResult {
        let array = PtychographyComplexArray(width: 2, height: 2, real: [1, 1, 1, 1], imaginary: [0, 0, 0, 0])
        return SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0.5, 0.25],
            objectSamplingRowAngstrom: 0.25, objectSamplingColumnAngstrom: 0.30,
            options: SingleslicePtychographyOptions())
    }

    private func published(in mode: AnalysisMode) -> DisplayedProduct? {
        let state = AppState()
        state.changeMode(mode)
        state.calibrationSession.calibration.rPixelSize = 5
        state.calibrationSession.calibration.rPixelUnits = "nm"
        state.phaseContrast.singleslicePtychography = result()
        state.showParallaxProduct(.iterativePhase)
        return state.resultPresentation.product
    }

    /// Mutation: restore `guard navigation.analysisMode == .ptychography`
    /// (drop `|| .singleslicePtychography`) -> the single-slice test goes red
    /// with sampling (5, 5, "nm"); the `.ptychography` control stays green.
    func testSingleslicePublishesObjectSamplingInAngstromAndItsEngine() throws {
        let product = try XCTUnwrap(published(in: .singleslicePtychography))
        XCTAssertEqual(product.kind, "ptychography_object_phase")
        XCTAssertEqual(product.sampling.row, 0.25)
        XCTAssertEqual(product.sampling.column, 0.30)
        XCTAssertEqual(product.sampling.units, "A")
        XCTAssertEqual(product.provenance["engine"], "singleslice")
        XCTAssertEqual(product.provenance["source_product"], "ptychography_object_phase")
        XCTAssertEqual(product.provenance["iterations"], "2")
    }

    /// The control: the branch was always reachable from the parallax mode.
    func testControlPtychographyModeReachesTheSameBranch() throws {
        let product = try XCTUnwrap(published(in: .ptychography))
        XCTAssertEqual(product.sampling.row, 0.25)
        XCTAssertEqual(product.provenance["engine"], "singleslice")
    }
}
