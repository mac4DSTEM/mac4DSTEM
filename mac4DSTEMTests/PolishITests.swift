//
//  PolishITests.swift
//  Lane I (owner card S8 b, 2026-10-02): "Export Data…" writes the product's float array as computed,
//  with pixel size, units, kind and provenance, through the existing one-field EMD bundle writer.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishITests: XCTestCase {
    func testExportDataWritesTheFloatArrayAsComputedWithSamplingAndProvenance() throws {
        let state = AppState()
        // Values a display mapping would destroy: negative, tiny, huge, NaN.
        let pixels: [Float] = [-1.25e-7, 3.5, 1e30, .nan, 0.1, -0.0]
        state.publishRestoredProduct(
            kind: "virtual_image", displayName: "Virtual image", valueUnits: "counts",
            payload: .scalar(FloatImage(width: 3, height: 2, pixels: pixels)),
            pixelSizeRow: 0.25, pixelSizeColumn: 0.5, pixelUnits: "nm",
            provenance: ["detector": "annular", "inner_px": "12"])
        let map = try XCTUnwrap(state.productDataExportMap())
        XCTAssertFalse(state.productIsColourImageOnly)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polishI-\(UUID().uuidString).h5")
        defer { try? FileManager.default.removeItem(at: url) }
        try BraggVectorEMDWriter.writeScientificBundle(
            maps: [map], calibration: PixelCalibration(), to: url)
        let back = try XCTUnwrap(BraggVectorEMDWriter.loadScientificBundleField(kind: "virtual_image", from: url))

        XCTAssertEqual(back.pixels.map(\.bitPattern), pixels.map(\.bitPattern))
        XCTAssertEqual(back.width, 3)
        XCTAssertEqual(back.height, 2)
        XCTAssertEqual(back.pixelSizeRow, 0.25)
        XCTAssertEqual(back.pixelSizeColumn, 0.5)
        XCTAssertEqual(back.pixelUnits, "nm")
        XCTAssertEqual(back.valueUnits, "counts")
        XCTAssertEqual(back.kind, "virtual_image")
        XCTAssertEqual(back.displayName, "Virtual image")
        XCTAssertEqual(back.provenance["detector"], "annular")
        XCTAssertEqual(back.provenance["inner_px"], "12")
        XCTAssertNotNil(back.provenance["display_domain"])
        XCTAssertNotNil(back.provenance["quantitative_status"])
    }

    func testColourImageOnlyProductHasNoDataExport() {
        let state = AppState()
        state.publishRestoredProduct(
            kind: "dpc_colour", displayName: "DPC colour", valueUnits: "rgb",
            payload: .rgba(RGBAImage(width: 1, height: 1, rgba: [1, 2, 3, 255])),
            pixelSizeRow: nil, pixelSizeColumn: nil, pixelUnits: nil, provenance: [:])
        XCTAssertNil(state.productDataExportMap())
        XCTAssertTrue(state.productIsColourImageOnly)
    }
}
