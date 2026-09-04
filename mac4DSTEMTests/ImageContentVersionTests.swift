//
//  ImageContentVersionTests.swift
//  Pins UI2MetalImage.contentVersion(of:width:height:) — the value- and
//  dimension-dependent version behind `PendingLoad.DisplayImage` (v2 S4).
//
//  The defect class this guards: a dims-only version means swapping to a
//  DIFFERENT image of the SAME shape never re-uploads the texture, so a
//  picker that changes the image appears to do nothing. The dimensions are
//  in the hash too, because the Coordinator short-circuits on the version
//  BEFORE it looks at width/height — identical pixels at transposed
//  dimensions must still re-upload.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ImageContentVersionTests: XCTestCase {

    func testTwoSameShapeImagesWithDifferentValuesGetDifferentVersions() {
        // The literal defect: same count, same dimensions, different pixels.
        let a: [Float] = [0, 1, 2, 3]
        let b: [Float] = [0, 1, 2, 4]
        XCTAssertNotEqual(
            UI2MetalImage.contentVersion(of: a, width: 2, height: 2),
            UI2MetalImage.contentVersion(of: b, width: 2, height: 2),
            "Same-shape images with different values must version differently — a dims-only hash cannot see this change and the texture would stay stale"
        )
    }

    func testTheVersionDependsOnPixelOrderNotJustTheValueSet() {
        // A sum or an order-free hash would pass the test above and still
        // miss a flipped image.
        let a: [Float] = [0, 1]
        let b: [Float] = [1, 0]
        XCTAssertNotEqual(
            UI2MetalImage.contentVersion(of: a, width: 2, height: 1),
            UI2MetalImage.contentVersion(of: b, width: 2, height: 1)
        )
    }

    func testIdenticalPixelsAtTransposedDimensionsGetDifferentVersions() {
        // The inverse defect of the dims-only hash: the Coordinator
        // short-circuits on the version before reading width/height, so a
        // values-only hash would keep a 64×32 texture for a 32×64 image.
        let pixels = [Float](repeating: 0, count: 8)
        XCTAssertNotEqual(
            UI2MetalImage.contentVersion(of: pixels, width: 4, height: 2),
            UI2MetalImage.contentVersion(of: pixels, width: 2, height: 4)
        )
    }

    func testEqualPixelsGetEqualVersions() {
        // Stability is the other half of the contract: an unstable version
        // would re-upload the texture on every redraw.
        let pixels: [Float] = (0..<64).map { Float($0) / 63 }
        XCTAssertEqual(
            UI2MetalImage.contentVersion(of: pixels, width: 8, height: 8),
            UI2MetalImage.contentVersion(of: Array(pixels), width: 8, height: 8)
        )
    }

    func testAnEmptyImageHasAVersion() {
        // Must not trap; the exact value is irrelevant.
        _ = UI2MetalImage.contentVersion(of: [], width: 0, height: 0)
    }
}
