import XCTest
@testable import mac4DSTEM

/// SwiftUI-review residual A2 (drive 7, VoiceOver): a NumericField's drawn unit
/// is hidden from accessibility and folded into the field's spoken label, so
/// the unit is not lost where the title does not carry it.
final class NumericFieldSpokenLabelTests: XCTestCase {

    private typealias Field = NumericField<Double, FloatingPointFormatStyle<Double>>

    func testUnitIsFoldedIntoTheSpokenLabel() {
        XCTAssertEqual(Field.spokenLabel("KDE σ", unit: "px"), "KDE σ, px")
        XCTAssertEqual(Field.spokenLabel("Minimum size", unit: "px"), "Minimum size, px")
        XCTAssertEqual(Field.spokenLabel("σ_k", unit: "%"), "σ_k, %")
    }

    func testNoUnitLeavesTheTitleAlone() {
        XCTAssertEqual(Field.spokenLabel("Inner fit radius in pixels", unit: nil),
                       "Inner fit radius in pixels")
    }
}
