import XCTest
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
            ]
        )
        XCTAssertEqual(valid.ptychographyIterations, 12)
        XCTAssertEqual(valid.ptychographyStepSize, 0.25)
        XCTAssertEqual(valid.ptychographyNormalizationMinimum, 0.75)
        XCTAssertEqual(valid.ptychographyFixProbe, true)

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
