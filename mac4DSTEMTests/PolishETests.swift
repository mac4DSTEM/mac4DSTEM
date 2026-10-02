//
//  PolishETests.swift
//  Lane E (Slot 4½ polish, owner cards S1 b and S5 a, 2026-10-02): the strain frame line, and a typed R pixel size
//  reaching the real-space product already on screen.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishETests: XCTestCase {
    private func product(kind: String, domain: ProductDomain, sampling: ProductSampling,
                         origin: ProductOrigin = .computed) -> DisplayedProduct {
        DisplayedProduct(
            origin: origin, kind: kind, displayName: kind,
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3])), domain: domain,
            sampling: sampling, valueUnits: "intensity", quantitativeStatus: .relative)
    }

    private func sampling(of state: AppState) -> ProductSampling? { state.resultPresentation.product?.sampling }

    func testTheDetectorFrameLineSaysWhatTheAxesAre() {
        let text = StrainPresentationFrame.detector.displayLabel
        XCTAssertTrue(text.contains("detector x/y"))
        XCTAssertTrue(text.contains("R–Q rotation not calibrated"))
    }

    /// Mutation: drop the `resampleDisplayedProductForRChange` call in `setManualRPixelSize` -> red.
    func testTypingRMakesTheScanProductOnScreenCarryIt() {
        let state = AppState()
        state.calibrationSession.calibration.rPixelSize = nil
        state.calibrationSession.calibration.rPixelUnits = "[pix]"
        state.resultPresentation.publish(product(
            kind: "virtual_circle", domain: .scan, sampling: ProductSampling(row: nil, column: nil, units: "[pix]")))
        let version = state.resultPresentation.resultVersion
        state.setManualRPixelSize(0.25)
        XCTAssertEqual(sampling(of: state), ProductSampling(row: 0.25, column: 0.25, units: "nm"))
        XCTAssertEqual(state.currentResultPersistenceMetadata.units, "nm")
        XCTAssertEqual(state.currentResultPersistenceMetadata.row, 0.25)
        XCTAssertEqual(state.resultPresentation.resultVersion, version, "pixels are unchanged: no repaint of the image")
        // A second edit follows the first; a unit change follows too.
        state.setManualRPixelSize(0.5)
        XCTAssertEqual(sampling(of: state), ProductSampling(row: 0.5, column: 0.5, units: "nm"))
        state.setManualRPixelUnits("Å")
        XCTAssertEqual(sampling(of: state), ProductSampling(row: 0.5, column: 0.5, units: "Å"))
        state.setManualRPixelSize(0)   // cleared
        XCTAssertNil(sampling(of: state)?.row)
    }

    /// Mutation: drop the domain test in `resampleDisplayedProductForRChange` -> the detector case goes red.
    func testProductsThatDoNotTakeRKeepTheirSampling() {
        let own = ProductSampling(row: 0.01, column: 0.01, units: "nm⁻¹")
        for (domain, origin, sampling) in [
            (ProductDomain.detector, ProductOrigin.computed, own),
            (.reconstruction, .computed, ProductSampling(row: 0.3, column: 0.3, units: "A")),
            (.scan, .restoredFromSidecar, ProductSampling(row: 7, column: 7, units: "nm")),
            // A scan-domain product with its own sampling (not R as it stood) is left alone.
            (.scan, .computed, ProductSampling(row: 0.3, column: 0.3, units: "A")),
        ] {
            let state = AppState()
            state.calibrationSession.calibration.rPixelSize = nil
            state.calibrationSession.calibration.rPixelUnits = "[pix]"
            state.resultPresentation.publish(product(kind: "k", domain: domain, sampling: sampling, origin: origin))
            state.setManualRPixelSize(0.25)
            XCTAssertEqual(self.sampling(of: state), sampling, "\(domain) \(origin)")
        }
        // The detector case again with the sampling shaped like the old R: only the domain protects it.
        let state = AppState()
        state.calibrationSession.calibration.rPixelSize = nil
        state.calibrationSession.calibration.rPixelUnits = "[pix]"
        let same = ProductSampling(row: nil, column: nil, units: "[pix]")
        state.resultPresentation.publish(product(kind: "bragg", domain: .detector, sampling: same))
        state.setManualRPixelSize(0.25)
        XCTAssertEqual(sampling(of: state), same)
    }
}
