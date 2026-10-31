//
//  SessionControlRehydrationTests.swift
//  The series geometry edge cases, the session result labels, and how saved provenance parses back into controls
//  (valid, malformed, legacy and unsupported records). Moved from the result-presentation-test harness into the unit suite.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SessionControlRehydrationTests: XCTestCase {
    func testSeriesGeometryEmptySelectionAndGaps() {
        let empty = ScientificSeriesGeometry.make(values: [], scale: .linear)
        XCTAssertTrue(empty.points.isEmpty)
        XCTAssertNil(empty.minimum)

        let linear = ScientificSeriesGeometry.make(values: [3, 5, 7], scale: .linear)
        XCTAssertEqual(linear.nearestIndex(toUnitX: 0.74), 1, "nearest lower selection")
        XCTAssertEqual(linear.nearestIndex(toUnitX: 0.76), 2, "nearest upper selection")

        let gaps = ScientificSeriesGeometry.make(values: [1, .nan, 10, .infinity, -1, 100], scale: .logarithmic)
        XCTAssertEqual(gaps.nearestIndex(toUnitX: 0.5), 2, "selection skips gaps")
    }

    func testSamplingAndProvenanceLabels() {
        XCTAssertEqual(SessionResultPresentation.sampling(row: 0.25, column: 0.5, units: "A", locale: Locale(identifier: "en_US")),
                       "sampling 0.25 × 0.5 Å/px", "a stored A displays as Å")
        XCTAssertNil(SessionResultPresentation.sampling(row: nil, column: 1, units: "A"), "partial sampling omitted")
        let provenance = SessionResultPresentation.provenance([
            "source_product": "ptychography_object_phase", "iterations": "8",
            "final_error": "0.00001234", "step_size": "0.5", "fix_probe": "true",
        ], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(provenance, "iters 8 · error 1.23e-05 · step 0.5")
    }

    func testParallaxControlsParse() {
        let kde = SessionControlRehydration.parse(kind: "parallax_subpixel_bf", provenance: [
            "upsample_factor": "2.5", "kde_sigma_px": "0.125",
            "interpolation": "lanczos_2", "position_iterations": "4", "sinc_lowpass": "true",
        ])
        XCTAssertEqual(kde.kdeUpsampleFactor, 2.5)
        XCTAssertEqual(kde.kdeSigmaPixels, 0.125)
        XCTAssertEqual(kde.kdeLanczosOrder, 2)
        XCTAssertEqual(kde.positionIterations, 4)
        XCTAssertEqual(kde.kdeLowpass, true)

        let correction = SessionControlRehydration.parse(kind: "ignored", provenance: [
            "source_product": "parallax_corrected_phase", "q_lowpass_inv_a": "off", "q_highpass_inv_a": "0.02",
        ])
        XCTAssertEqual(correction.qLowpassInvAngstrom, 0)
        XCTAssertEqual(correction.qHighpassInvAngstrom, 0.02)

        let depth = SessionControlRehydration.parse(kind: "parallax_depth", provenance: [
            "depth_angstrom": "-64.5", "full_fit": "false",
            "information_limit_inv_a": "0.12", "information_power": "1.5",
        ])
        XCTAssertEqual(depth.depthAngstrom, -64.5)
        XCTAssertEqual(depth.depthUseFullFit, false)
        XCTAssertEqual(depth.depthInformationLimit, 0.12)
        XCTAssertEqual(depth.depthInformationPower, 1.5)
    }

    func testPtychographyControlsParse() {
        let ptycho = SessionControlRehydration.parse(kind: "ptychography_object_amplitude", provenance: [
            "engine": "singleslice", "method": "gradient-descent", "iterations": "12",
            "step_size": "0.25", "normalization_minimum": "0.75", "fix_probe": "yes",
            "constrain_object_amplitude": "true", "pure_phase_object": "false",
            "fix_probe_com": "true", "constrain_probe_amplitude": "true",
            "probe_amplitude_radius": "0.42", "probe_amplitude_width": "0.09",
        ])
        XCTAssertEqual(ptycho.ptychographyIterations, 12)
        XCTAssertEqual(ptycho.ptychographyStepSize, 0.25)
        XCTAssertEqual(ptycho.ptychographyNormalizationMinimum, 0.75)
        XCTAssertEqual(ptycho.ptychographyFixProbe, true)
        XCTAssertEqual(ptycho.ptychographyConstrainObjectAmplitude, true)
        XCTAssertEqual(ptycho.ptychographyPurePhaseObject, false)
        XCTAssertEqual(ptycho.ptychographyFixProbeCenterOfMass, true)
        XCTAssertEqual(ptycho.ptychographyConstrainProbeAmplitude, true)
        XCTAssertEqual(ptycho.ptychographyProbeAmplitudeRadius, 0.42)
        XCTAssertEqual(ptycho.ptychographyProbeAmplitudeWidth, 0.09)

        let projection = SessionControlRehydration.parse(kind: "ptychography_probe_phase", provenance: [
            "engine": "singleslice", "method": "difference-map_alternating-projections",
            "projection_parameter": "0.8", "iterations": "5",
        ])
        XCTAssertEqual(projection.ptychographyRetiredMethod, "difference-map_alternating-projections")
        XCTAssertNil(projection.ptychographyIterations, "an old DM/AP record parses to the retired-method marker alone")
        XCTAssertFalse(projection.isEmpty)
    }

    func testMalformedLegacyAndUnsupportedRecordsParseToNothing() {
        let malformed = SessionControlRehydration.parse(kind: "parallax_subpixel_bf", provenance: [
            "upsample_factor": "0.5", "kde_sigma_px": "nan", "interpolation": "lanczos_99",
            "position_iterations": "-1", "sinc_lowpass": "maybe",
        ])
        XCTAssertTrue(malformed.isEmpty, "malformed or out-of-range provenance is rejected")
        XCTAssertTrue(SessionControlRehydration.parse(kind: "legacy_virtual", provenance: [:]).isEmpty)
        XCTAssertTrue(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: [
            "engine": "unsupported", "iterations": "8",
        ]).isEmpty, "unsupported engine rejected")
    }
}
