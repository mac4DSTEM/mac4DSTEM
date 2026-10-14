import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// "Same scale" and "Clear" on the Results comparison. Display only: which value the colours span, never a stored value.
/// Tier 2, but the colorbar prints the window, so the tests pin that it is the window the colours really use.
@MainActor
final class ComparisonColourScaleTests: XCTestCase {

    private func scalar(_ pixels: [Float], units: String = "counts") -> DisplayedProduct {
        DisplayedProduct(
            kind: "test_scalar", displayName: "Test",
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: pixels)),
            domain: .scan,
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: units, quantitativeStatus: .relative)
    }

    private func colour() -> DisplayedProduct {
        DisplayedProduct(
            kind: "test_rgba", displayName: "Colour",
            payload: .rgba(RGBAImage(width: 2, height: 2, rgba: [UInt8](repeating: 9, count: 16))),
            domain: .scan,
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "", quantitativeStatus: .categorical)
    }

    func testTheSharedRangeSpansBothProducts() throws {
        let range = try XCTUnwrap(ComparisonColourScale.sharedRange(scalar([2, 4, 6, 8]), scalar([-1, 0, 1, 20])))
        XCTAssertEqual(range.low, -1)
        XCTAssertEqual(range.high, 20)
    }

    func testNoSharedRangeWhereItWouldMeanNothing() {
        XCTAssertNil(ComparisonColourScale.sharedRange(scalar([0, 1, 2, 3]), scalar([0, 1, 2, 3], units: "nm")),
                     "different units cannot share one colour range")
        XCTAssertNil(ComparisonColourScale.sharedRange(scalar([0, 1, 2, 3]), colour()), "a colour image has no range")
    }

    func testTheHeaderNoteIsForRangesThatDiffer() {
        XCTAssertTrue(ComparisonColourScale.rangesDiffer(scalar([0, 1, 2, 3]), scalar([0, 1, 2, 30])))
        XCTAssertFalse(ComparisonColourScale.rangesDiffer(scalar([0, 1, 2, 3]), scalar([3, 2, 1, 0])),
                       "the same minimum and maximum: nothing to warn about")
        XCTAssertFalse(ComparisonColourScale.rangesDiffer(scalar([0, 1, 2, 3]), scalar([0, 1, 2, 30], units: "nm")))
    }

    func testPanelsWindowOnTheSharedRangeAndTheColorbarPrintsIt() throws {
        let a = scalar([0, 1, 2, 4]), b = scalar([0, 5, 10, 20])
        let shared = try XCTUnwrap(ComparisonColourScale.sharedRange(a, b))
        let own = ComparisonPanel(a, label: "A", colormap: .viridis)
        let same = ComparisonPanel(a, label: "A", colormap: .viridis, sharedRange: shared)
        XCTAssertEqual(own.pixels, [0, 0.25, 0.5, 1])
        XCTAssertEqual(same.pixels, [0, 0.05, 0.1, 0.2], "A's 4 is a fifth of the way up B's 0...20")
        XCTAssertEqual(same.valueRange?.low, 0)
        XCTAssertEqual(same.valueRange?.high, 20, "the colorbar prints the window the colours span")
        XCTAssertNotEqual(own.contentVersion, same.contentVersion, "the texture must be re-uploaded when the window changes")
        // The same colour now means the same value in both panels.
        let sameB = ComparisonPanel(b, label: "B", colormap: .viridis, sharedRange: shared)
        XCTAssertEqual(sameB.pixels, [0, 0.25, 0.5, 1])
    }

    func testNoDataStaysNoDataOnASharedScale() throws {
        let a = scalar([0, .nan, 2, 4]), b = scalar([0, 1, 2, 8])
        let shared = try XCTUnwrap(ComparisonColourScale.sharedRange(a, b))
        let panel = ComparisonPanel(a, label: "A", colormap: .viridis, sharedRange: shared)
        XCTAssertEqual(panel.pixels[1], FloatImage.invalidDisplayValue)
        XCTAssertEqual(shared.high, 8, "a non-finite pixel does not blank the window")
    }

    func testClearEmptiesBothSlots() {
        let appState = AppState()
        appState.comparisonProductA = scalar([0, 1, 2, 3])
        appState.comparisonProductB = scalar([0, 1, 2, 3])
        appState.clearComparison()
        XCTAssertNil(appState.comparisonProductA)
        XCTAssertNil(appState.comparisonProductB)
    }
}
