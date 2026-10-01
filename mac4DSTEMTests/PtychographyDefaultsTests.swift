import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane DC (2026-10-01): owner cards DM a (the difference map is removed) and CL a (the amplitude clamp |O| <= 1 is on by default,
/// as py4DSTEM applies it to every complex object).
@MainActor
final class PtychographyDefaultsTests: XCTestCase {
    /// CL a. Both defaults name the clamp ON: the engine's options (what the harness and the probe tool build) and the app's settings
    /// (what a run reads). Mutation: set either default back to false -> red.
    func testObjectTransmissionLimitIsOnByDefault() {
        XCTAssertTrue(SingleslicePtychographyOptions().constrainObjectAmplitude)
        XCTAssertTrue(PtychographySettings().constrainObjectAmplitude)
    }

    /// DM a. A file saved while the difference map existed still opens: its saved controls offer one named note, and applying them
    /// says the method is gone and changes nothing else. Mutation: drop the `ptychographyRetiredMethod` branch of
    /// `applySelectedSavedControls` (or parse the old record's other controls again) -> red.
    func testAnOldDifferenceMapRecordOpensAndSaysTheMethodIsGone() throws {
        let provenance = [
            "source_product": "ptychography_object_phase", "engine": "singleslice",
            "method": "difference-map_alternating-projections", "projection_parameter": "0.8",
            "iterations": "5", "step_size": "0.3", "constrain_object_amplitude": "false",
        ]
        let array = PtychographyComplexArray(width: 2, height: 2, real: [1, 1, 1, 1], imaginary: [0, 0, 0, 0])
        let source = AppState()
        source.changeMode(.singleslicePtychography)
        source.phaseContrast.singleslicePtychography = SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0.5, 0.25],
            objectSamplingRowAngstrom: 0.25, objectSamplingColumnAngstrom: 0.30,
            options: SingleslicePtychographyOptions())
        source.showParallaxProduct(.iterativePhase)
        let product = try XCTUnwrap(source.resultPresentation.product)
        XCTAssertEqual(product.provenance["method"], "gradient-descent")
        XCTAssertNil(product.provenance["projection_parameter"], "the difference map's key is no longer written")
        let state = AppState()
        state.changeMode(.singleslicePtychography)
        state.publishRestoredProduct(
            kind: product.kind, displayName: product.displayName, valueUnits: product.valueUnits, payload: product.payload,
            pixelSizeRow: nil, pixelSizeColumn: nil, pixelUnits: nil, provenance: provenance)
        let plan = try XCTUnwrap(state.selectedSavedControlRehydration)
        XCTAssertEqual(plan.summary, "difference map (no longer offered)")
        let before = (state.ptychography.iterations, state.ptychography.stepSize, state.ptychography.constrainObjectAmplitude)
        state.applySelectedSavedControls()
        XCTAssertTrue(state.statusText.hasPrefix("This result was made with the difference map"), state.statusText)
        XCTAssertFalse(state.statusText.contains("Applied saved controls"), "nothing may be applied from such a record")
        XCTAssertEqual(state.ptychography.iterations, before.0)
        XCTAssertEqual(state.ptychography.stepSize, before.1)
        XCTAssertEqual(state.ptychography.constrainObjectAmplitude, before.2)
    }
}
