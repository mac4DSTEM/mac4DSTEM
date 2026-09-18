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

/// AppState seams plan, seam 5: the mutable presentation around an immutable
/// `DisplayedProduct` has one owner. These pin the three owner decisions made
/// with the release owner: a wrapper rather than mutating `DisplayedProduct`,
/// caches as private derivation, and the existing manual version-bump order
/// preserved until a separately diagnosed simplification.
@MainActor
final class ResultPresentationSeamTests: XCTestCase {
    private func product(pixels: [Float] = [1]) -> DisplayedProduct {
        DisplayedProduct(
            kind: "test", displayName: "Test",
            payload: .scalar(FloatImage(width: pixels.count, height: 1, pixels: pixels)),
            domain: .scan,
            sampling: ProductSampling(row: 1, column: 1, units: "px"),
            valueUnits: "intensity", quantitativeStatus: .relative
        )
    }

    func testConstructionKeepsThePreSeamDefaults() {
        let presentation = ResultPresentation()

        XCTAssertNil(presentation.product)
        XCTAssertEqual(presentation.resultVersion, 0)
        XCTAssertEqual(presentation.resultColormap, .viridis)
        XCTAssertEqual(presentation.displayRangeLo, 0)
        XCTAssertEqual(presentation.displayRangeHi, 1)
        XCTAssertEqual(presentation.resultGamma, 1)
        XCTAssertFalse(presentation.inspectQualityField)
        XCTAssertEqual(presentation.virtualShape, .annulus)
        XCTAssertNil(presentation.braggVectors)
        XCTAssertNil(presentation.virtualDiffractionPattern)
    }

    func testNormalPublicationStoresTheProductAndBumpsExactlyOnce() {
        let presentation = ResultPresentation()

        presentation.publish(product())

        XCTAssertEqual(presentation.product?.kind, "test")
        XCTAssertEqual(presentation.resultVersion, 1)
    }

    func testColormapAssignmentBumpsExactlyOnceIncludingSameValueWrites() {
        let presentation = ResultPresentation()

        presentation.resultColormap = .rdbu
        XCTAssertEqual(presentation.resultVersion, 1)

        presentation.resultColormap = .rdbu
        XCTAssertEqual(presentation.resultVersion, 2)
    }

    func testReplacementAndExplicitInvalidationPreserveLegacyOrdering() {
        let presentation = ResultPresentation()

        presentation.replaceProduct(product())
        XCTAssertEqual(presentation.resultVersion, 0,
                       "legacy restore/virtual-detector call sites own the bump order")

        presentation.bumpResultVersion()
        XCTAssertEqual(presentation.resultVersion, 1)
    }

    func testDerivedNormalizationCacheKeysOnThePresentationVersion() {
        let presentation = ResultPresentation()
        let first = product(pixels: [0, 1, 2])
        presentation.publish(first)
        let firstPixels = presentation.normalizedResultPixels(
            image: presentation.resultImage, version: presentation.resultVersion,
            regionReference: false, colormap: presentation.resultColormap
        )

        presentation.replaceProduct(product(pixels: [0, 1, 4]))
        presentation.bumpResultVersion()
        let secondPixels = presentation.normalizedResultPixels(
            image: presentation.resultImage, version: presentation.resultVersion,
            regionReference: false, colormap: presentation.resultColormap
        )

        XCTAssertEqual(firstPixels, [0, 0.5, 1])
        XCTAssertEqual(secondPixels, [0, 0.25, 1])
        XCTAssertEqual(presentation.resultVersion, 2)
    }

    func testAppStateHoldsTheOwnerWithoutStoredPresentationShadows() {
        let state = AppState()
        let names = Mirror(reflecting: state).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("resultPresentation"))
        let moved = Set([
            "publishedProduct", "resultVersion", "resultColormap",
            "displayRangeLo", "displayRangeHi", "resultGamma",
            "inspectQualityField", "braggVectors", "braggPeakCount",
            "virtualShape", "virtualDiffractionPattern",
        ])
        XCTAssertTrue(moved.isDisjoint(with: names),
                      "AppState still stores presentation shadows: \(moved.intersection(names))")
    }

    func testAppStatePublicationUsesTheOwnerAndKeepsTheVersionContract() {
        let state = AppState()

        state.publishProduct(
            kind: "test", displayName: "Test", valueUnits: "intensity",
            payload: .scalar(FloatImage(width: 1, height: 1, pixels: [1]))
        )

        XCTAssertEqual(state.resultPresentation.product?.kind, "test")
        XCTAssertEqual(state.resultPresentation.resultVersion, 1)
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
        XCTAssertNil(state.resultPresentation.resultImage)
        XCTAssertNil(state.resultPresentation.resultRGBA)
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
