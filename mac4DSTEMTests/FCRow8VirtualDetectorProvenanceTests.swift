//
//  FCRow8VirtualDetectorProvenanceTests.swift
//  Cloud review row 8 (Gate D): the virtual-detector product took its provenance
//  from the product ON SCREEN, so Strain -> Imaging -> BF carried the strain keys.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FCRow8VirtualDetectorProvenanceTests: XCTestCase {

    /// Mutation it catches: the virtual image's provenance merged from
    /// `currentResultPersistenceMetadata` (the displayed product's) instead of the
    /// mode's own metadata -- the strain keys below come back.
    func testVirtualImageDoesNotInheritTheDisplayedProductsProvenance() async throws {
        let state = AppState()
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: spec)
        // Strain on screen, as after a strain run.
        state.resultPresentation.replaceProduct(DisplayedProduct(
            kind: "strain_exx", displayName: "Strain exx",
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 1, 2, 3])), domain: .scan,
            sampling: ProductSampling(row: 1, column: 1, units: "nm"),
            valueUnits: "strain", quantitativeStatus: .quantitative,
            provenance: ["source_product": "strain_exx", "basis_mode": "consensus",
                         "qr_rotation_deg": "12.5", "analysis_mode": "strain"]))
        // Then Imaging (changeMode keeps the product), then BF.
        state.navigation.analysisMode = .virtualDetector
        let outcome = await state.runVirtualDetector()
        XCTAssertEqual(outcome, .published, state.statusText)

        let product = try XCTUnwrap(state.resultPresentation.product)
        XCTAssertTrue(product.kind.hasPrefix("virtual_"), product.kind)
        let provenance = product.provenance
        for key in ["source_product", "basis_mode", "qr_rotation_deg"] {
            XCTAssertNil(provenance[key], "the virtual image inherited \(key)=\(provenance[key] ?? "")")
        }
        XCTAssertEqual(provenance["analysis_mode"], AnalysisMode.virtualDetector.rawValue)
        XCTAssertEqual(provenance["display_domain"], "scan")
        XCTAssertEqual(provenance["quantitative_status"], "relative")
        XCTAssertNotNil(provenance["virtual_shape"])
        XCTAssertNil(state.currentResultPersistenceMetadata.provenance["source_product"])
    }
}
