import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ResultPresentationTests: XCTestCase {
    func testLinearAndLogarithmicGeometry() {
        let linear = ScientificSeriesGeometry.make(values: [3, 5, 7], scale: .linear)
        XCTAssertEqual(linear.points.map(\.x), [0, 0.5, 1])
        XCTAssertEqual(linear.points.map(\.y), [0, 0.5, 1])
        XCTAssertEqual(linear.nearestIndex(toUnitX: 0.76), 2)

        let log = ScientificSeriesGeometry.make(
            values: [1, .nan, 10, .infinity, -1, 100], scale: .logarithmic
        )
        XCTAssertEqual(log.segments.count, 3)
        XCTAssertEqual(log.points.map(\.index), [0, 2, 5])
        XCTAssertEqual(log.points.map(\.y), [0, 0.5, 1])
    }

    func testEmptyAndSingleGeometry() {
        XCTAssertTrue(ScientificSeriesGeometry.make(values: [], scale: .linear).points.isEmpty)
        XCTAssertEqual(
            ScientificSeriesGeometry.make(values: [7], scale: .linear).points.first,
            ScientificSeriesPoint(index: 0, x: 0.5, y: 0.5, value: 7)
        )
    }

    func testControlRehydrationRejectsMalformedProvenance() {
        let valid = SessionControlRehydration.parse(
            kind: "ptychography_object_phase",
            provenance: [
                "engine": "singleslice", "method": "gradient-descent",
                "iterations": "12", "step_size": "0.25",
                "normalization_minimum": "0.75", "fix_probe": "true",
                "constrain_object_amplitude": "true", "pure_phase_object": "false",
                "fix_probe_com": "true", "constrain_probe_amplitude": "true",
                "probe_amplitude_radius": "0.42", "probe_amplitude_width": "0.09",
            ]
        )
        XCTAssertEqual(valid.ptychographyIterations, 12)
        XCTAssertEqual(valid.ptychographyStepSize, 0.25)
        XCTAssertEqual(valid.ptychographyNormalizationMinimum, 0.75)
        XCTAssertEqual(valid.ptychographyFixProbe, true)
        XCTAssertEqual(valid.ptychographyConstrainObjectAmplitude, true)
        XCTAssertEqual(valid.ptychographyPurePhaseObject, false)
        XCTAssertEqual(valid.ptychographyFixProbeCenterOfMass, true)
        XCTAssertEqual(valid.ptychographyConstrainProbeAmplitude, true)
        XCTAssertEqual(valid.ptychographyProbeAmplitudeRadius, 0.42)
        XCTAssertEqual(valid.ptychographyProbeAmplitudeWidth, 0.09)

        let projection = SessionControlRehydration.parse(
            kind: "ptychography_probe_phase",
            provenance: [
                "engine": "singleslice",
                "method": "difference-map_alternating-projections",
                "projection_parameter": "0.8", "iterations": "5",
            ]
        )
        XCTAssertEqual(
            projection.ptychographyMethod,
            "difference-map_alternating-projections"
        )
        XCTAssertEqual(projection.ptychographyProjectionParameter, 0.8)

        let malformed = SessionControlRehydration.parse(
            kind: "parallax_subpixel_bf",
            provenance: [
                "upsample_factor": "0.5", "kde_sigma_px": "nan",
                "interpolation": "lanczos_99", "position_iterations": "-1",
            ]
        )
        XCTAssertTrue(malformed.isEmpty)
    }
}

/// Backlog #28. Strain and orientation are retained simultaneously; only the
/// displayed product was ever single-valued. These pin the explicit switch and
/// the export that used to drop whichever family was not in front.
@MainActor
final class ComputedProductSwitchTests: XCTestCase {

    func testNothingIsOfferedBeforeAnythingIsComputed() {
        let state = AppState()
        XCTAssertTrue(state.availableComputedProducts.isEmpty)
        // Must be inert rather than crash or publish an empty product.
        state.showComputedProduct(.strain)
        state.showComputedProduct(.orientation)
        XCTAssertNil(state.resultImage)
        XCTAssertNil(state.resultRGBA)
    }

    func testAnEmptyBundleIsNilRatherThanAnEmptyArray() {
        let state = AppState()
        XCTAssertNil(
            state.scientificBundleMaps(),
            "an empty bundle must stay nil so export reports 'compute something first'"
        )
        XCTAssertTrue(state.scientificBundleOmissions(in: []).isEmpty)
    }

    func testProductDisplayNamesAreStableForTheInspectorRows() {
        XCTAssertEqual(AppState.ComputedProduct.strain.displayName, "Strain map")
        XCTAssertEqual(AppState.ComputedProduct.orientation.displayName, "Orientation map")
        XCTAssertEqual(AppState.ComputedProduct.allCases.count, 2)
    }
}
