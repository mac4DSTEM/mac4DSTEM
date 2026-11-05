//
//  PhaseMappingDetectorResolutionTests.swift
//  Issue #100: the detector-resolution row is shown under Known variants too (the Al–Mg–Si preset's classifier), and it lists
//  the tolerances that classifier uses. Paul's bin-4 Al–Mg–Si cube: 0.0457 Å⁻¹ per pixel, shipped 0.020 / 0.020 / 0.015 Å⁻¹.
//

import XCTest
import DiffractoOrientation
@testable import mac4DSTEM

final class PhaseMappingDetectorResolutionTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    private var resolution: PhaseVectorResolution {
        var s = PhaseVectorSettings()
        s.pairRadiusInvAngstrom = 0.020
        s.matrixToleranceInvAngstrom = 0.020
        s.notIndexedAboveInvAngstrom = 0.015
        return PhaseVectorResolution(settings: s, invAngstromPerPixel: 0.0457415)
    }

    func testKnownVariantsShowsPairRadiusAndMatrixRemovalOnly() {
        XCTAssertEqual(PhaseMappingSections.detectorResolutionText(resolution, rule: .knownVariants, locale: posix), "0.44 · 0.44 px")
    }

    func testSearchShowsAllThree() {
        XCTAssertEqual(PhaseMappingSections.detectorResolutionText(resolution, rule: .search, locale: posix), "0.44 · 0.44 · 0.33 px")
    }

    func testTheAdviceThatOffersScalingExistsOnThisDetector() {
        XCTAssertNotNil(resolution.advice)
    }
}
