//
//  PolishFTests.swift
//  Lane F (Slot 4½ polish, 2026-10-02): BF/ADF presets follow the measured beam (S3); entering Phase mapping or
//  Diffraction groups no longer shows the previous mode's product (S5 item 2).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishFTests: XCTestCase {
    private func strainProduct() -> DisplayedProduct {
        DisplayedProduct(
            kind: "strain_exx", displayName: "Strain · exx",
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 0, 0, 0])), domain: .scan,
            validityMask: nil, qualityFields: [],
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "strain", quantitativeStatus: .relative, provenance: [:], overlays: [])
    }

    /// r = 25.3 on a 64-px detector: BF is the beam, 3r = 75.9 >= 64 leaves no room, so ADF keeps the fractions.
    /// Mutation: drop the `3 * r < maxRadius` guard -> ADF becomes (75.9, 64) -> red.
    func testPresetsWithABeamTooWideForAnAnnulusFallBackForADF() {
        let bf = DetectorPreset.brightField.radii(maxRadius: 64, probeRadius: 25.3)!
        XCTAssertEqual(bf.inner, 0); XCTAssertEqual(bf.outer, 25.3, accuracy: 1e-5)
        let adf = DetectorPreset.adf.radii(maxRadius: 64, probeRadius: 25.3)!
        XCTAssertEqual(adf.inner, 0.25 * 64, accuracy: 1e-5)
        XCTAssertEqual(adf.outer, 0.55 * 64, accuracy: 1e-5)
        XCTAssertFalse(DetectorPreset.adf.followsBeam(maxRadius: 64, probeRadius: 25.3))
    }

    /// r = 8: ADF is 3r...6r = 24...48 (py4DSTEM tutorial). Mutation: 6r -> 5r -> red.
    func testADFIsThreeToSixProbeRadii() {
        let adf = DetectorPreset.adf.radii(maxRadius: 64, probeRadius: 8)!
        XCTAssertEqual(adf.inner, 24, accuracy: 1e-5); XCTAssertEqual(adf.outer, 48, accuracy: 1e-5)
        XCTAssertTrue(DetectorPreset.adf.followsBeam(maxRadius: 64, probeRadius: 8))
        // 6r past the edge clips to the edge.
        XCTAssertEqual(DetectorPreset.adf.radii(maxRadius: 64, probeRadius: 12)!.outer, 64)
        // HAADF is unchanged by the beam.
        let h = DetectorPreset.haadf.radii(maxRadius: 64, probeRadius: 8)!
        XCTAssertEqual(h.inner, 0.55 * 64, accuracy: 1e-5)
    }

    /// No usable beam: today's fractions. Mutation: accept probeRadius 0 / NaN -> red.
    func testNoBeamKeepsFractions() {
        for probe: Float? in [nil, 0, -3, .nan] {
            let bf = DetectorPreset.brightField.radii(maxRadius: 64, probeRadius: probe)!
            XCTAssertEqual(bf.outer, 0.20 * 64, accuracy: 1e-5)
            XCTAssertFalse(DetectorPreset.brightField.followsBeam(maxRadius: 64, probeRadius: probe))
        }
    }

    func testPresetProbeRadiusOnlyForAUsableCalibrationValue() {
        let state = AppState()
        XCTAssertNil(state.presetProbeRadius)
        state.calibrationSession.calibration.probeRadius = .nan
        XCTAssertNil(state.presetProbeRadius)
        state.calibrationSession.calibration.probeRadius = 7
        XCTAssertEqual(state.presetProbeRadius, 7)
    }

    /// Strain on screen, then Phase mapping with no phase map: nothing shown.
    /// Mutation: make the `.phaseMapping` branch a no-op -> the strain product stays -> red.
    func testEnteringPhaseMappingDropsTheStaleStrainMap() {
        let state = AppState()
        state.resultPresentation.publish(strainProduct())
        XCTAssertEqual(state.resultPresentation.product?.kind, "strain_exx")
        state.presentProductForEnteredMode(.phaseMapping)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// The wiring: the mode switch itself presents the entered mode's product.
    /// Mutation: drop the call from `changeMode` -> red.
    func testChangingModeToPhaseMappingDropsTheStaleStrainMap() {
        let state = AppState()
        state.resultPresentation.publish(strainProduct())
        state.changeMode(.phaseMapping)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Mutation: no-op the `.diffractionGroups` branch -> red.
    func testEnteringDiffractionGroupsWithoutAResultDropsTheStaleProduct() {
        let state = AppState()
        state.resultPresentation.publish(strainProduct())
        state.presentProductForEnteredMode(.diffractionGroups)
        XCTAssertNil(state.resultPresentation.product)
    }

    /// Other modes are untouched.
    func testEnteringStrainLeavesTheProduct() {
        let state = AppState()
        state.resultPresentation.publish(strainProduct())
        state.presentProductForEnteredMode(.strain)
        XCTAssertNotNil(state.resultPresentation.product)
    }
}
