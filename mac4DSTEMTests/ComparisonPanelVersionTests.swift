//
//  ComparisonPanelVersionTests.swift
//  Pins `ComparisonPanel`'s content version — the value the comparison pane
//  hands `MetalImageView` so a swapped product actually redraws (v2 S18).
//
//  The defect class, twice over. `MetalImageView`'s Coordinator re-uploads its
//  texture only when the version CHANGES, so any call site that passes a
//  constant uploads exactly once and then shows that first image forever. The
//  comparison pane passed the literal `0`: putting a different saved product in
//  slot A left the previous product's pixels on screen under the new product's
//  name. Reading a number off the wrong image is the failure this repo exists to
//  prevent, and it is silent.
//
//  The RGBA case is the same defect one payload deeper. An RGBA product renders
//  through its packed bytes and carries an all-zero `pixels` array, so a version
//  derived from `pixels` alone is identical for every same-sized RGBA product —
//  a hexagonal IPF map and a DPC colour wheel of equal dimensions would version
//  the same. `ComparisonPanel.version` folds the bytes in for exactly that.
//

import XCTest
@testable import mac4DSTEM

final class ComparisonPanelVersionTests: XCTestCase {

    private func scalarProduct(_ pixels: [Float], width: Int, height: Int) -> DisplayedProduct {
        DisplayedProduct(
            kind: "test_scalar", displayName: "Test",
            payload: .scalar(FloatImage(width: width, height: height, pixels: pixels)),
            domain: .scan,
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "counts", quantitativeStatus: .relative
        )
    }

    private func rgbaProduct(_ bytes: [UInt8], width: Int, height: Int) -> DisplayedProduct {
        DisplayedProduct(
            kind: "test_rgba", displayName: "Test",
            payload: .rgba(RGBAImage(width: width, height: height, rgba: bytes)),
            domain: .scan,
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "", quantitativeStatus: .categorical
        )
    }

    // MARK: - Scalar payloads

    func testTwoScalarProductsOfTheSameShapeVersionDifferently() {
        let a = ComparisonPanel(
            scalarProduct([0, 1, 2, 3], width: 2, height: 2),
            label: "A", colormap: .viridis
        )
        let b = ComparisonPanel(
            scalarProduct([0, 1, 2, 9], width: 2, height: 2),
            label: "A", colormap: .viridis
        )
        XCTAssertNotEqual(
            a.contentVersion, b.contentVersion,
            "Swapping the product in a comparison slot must change the version, or the pane keeps the old texture"
        )
    }

    func testTheSameScalarProductVersionsTheSameTwice() {
        // The other half of the contract: a version that changed every time
        // would re-upload the texture on every body evaluation, which is the
        // cost the version exists to avoid.
        let pixels: [Float] = [4, 5, 6, 7]
        let first = ComparisonPanel(
            scalarProduct(pixels, width: 2, height: 2), label: "A", colormap: .viridis
        )
        let second = ComparisonPanel(
            scalarProduct(pixels, width: 2, height: 2), label: "A", colormap: .viridis
        )
        XCTAssertEqual(first.contentVersion, second.contentVersion)
    }

    func testTheVersionIsNotTheConstantItReplaced() {
        // The literal defect: `contentVersion: 0`. The Coordinator starts at
        // Int.min, so a constant zero uploads once and never again.
        let panel = ComparisonPanel(
            scalarProduct([1, 2, 3, 4], width: 2, height: 2), label: "A", colormap: .viridis
        )
        XCTAssertNotEqual(panel.contentVersion, 0)
    }

    // MARK: - RGBA payloads

    func testTwoRGBAProductsOfTheSameSizeVersionDifferently() {
        // Both carry an all-zero `pixels` array of equal length at equal
        // dimensions, so everything except the packed bytes is identical.
        let a = ComparisonPanel(
            rgbaProduct([UInt8](repeating: 10, count: 2 * 2 * 4), width: 2, height: 2),
            label: "A", colormap: .viridis
        )
        let b = ComparisonPanel(
            rgbaProduct([UInt8](repeating: 200, count: 2 * 2 * 4), width: 2, height: 2),
            label: "A", colormap: .viridis
        )
        XCTAssertNotEqual(
            a.contentVersion, b.contentVersion,
            "An RGBA product's identity is its bytes — its `pixels` array is zeros by construction"
        )
    }

    func testAnRGBAProductDoesNotCollideWithTheScalarProductBehindIt() {
        // The zero-filled `pixels` an RGBA panel carries is a real scalar image
        // in its own right; the two must not share a version.
        let rgba = ComparisonPanel(
            rgbaProduct([UInt8](repeating: 0, count: 2 * 2 * 4), width: 2, height: 2),
            label: "A", colormap: .viridis
        )
        let zeros = ComparisonPanel(
            scalarProduct([0, 0, 0, 0], width: 2, height: 2), label: "A", colormap: .viridis
        )
        XCTAssertNotEqual(rgba.contentVersion, zeros.contentVersion)
    }

    func testTheRGBAVersionDependsOnByteOrderNotJustTheByteSet() {
        // A sum or an order-free fold would pass the test above and still miss
        // a flipped or rotated colour map.
        let a = ComparisonPanel(
            rgbaProduct([1, 2, 3, 4, 5, 6, 7, 8], width: 2, height: 1),
            label: "A", colormap: .viridis
        )
        let b = ComparisonPanel(
            rgbaProduct([5, 6, 7, 8, 1, 2, 3, 4], width: 2, height: 1),
            label: "A", colormap: .viridis
        )
        XCTAssertNotEqual(a.contentVersion, b.contentVersion)
    }

    // MARK: - Payload, not label

    func testTheLabelDoesNotEnterTheVersion() {
        // Slot A and slot B showing the same product must upload the same
        // texture; a label-dependent version would make the comparison pane
        // re-upload for no reason, and would also mask a real payload change
        // whenever the label happened to change with it.
        let pixels: [Float] = [1, 2, 3, 4]
        let a = ComparisonPanel(
            scalarProduct(pixels, width: 2, height: 2), label: "A", colormap: .viridis
        )
        let b = ComparisonPanel(
            scalarProduct(pixels, width: 2, height: 2), label: "B", colormap: .viridis
        )
        XCTAssertEqual(a.contentVersion, b.contentVersion)
    }
}
