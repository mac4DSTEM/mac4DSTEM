//
//  ApertureEntryTests.swift
//  Tier 2 (behaviour without a new number): the aperture typed into the Imaging inspector takes the drag's own path
//  (`Aperture.snappedEdit`, then `updateAperture` and `commitApertureChange`). UI audit 2026-10-14, "Aperture is drag-only".
//

import ShellControls
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ApertureEntryTests: XCTestCase {
    private let fitted = Aperture(centerX: 69.3133, centerY: 54.5009, inner: 5, outer: 20)

    private func edit(_ field: ApertureEntry.Field, _ typed: Double, from start: Aperture? = nil) -> Aperture? {
        ApertureEntry.edited(start ?? fitted, field: field, to: typed, patternWidth: 128, patternHeight: 96)
    }

    func testATypedCentreSnapsToWholePixelsAndClampsAfterRoundingLikeTheDrag() throws {
        XCTAssertEqual(try XCTUnwrap(edit(.centerX, 70.4)).centerX, 70)
        XCTAssertEqual(try XCTUnwrap(edit(.centerY, 55.6)).centerY, 56)
        XCTAssertEqual(try XCTUnwrap(edit(.centerX, 500)).centerX, 127, "past the last column: clamped to 127, not 128")
        XCTAssertEqual(try XCTUnwrap(edit(.centerY, 500)).centerY, 95, "the detector is 96 rows")
        XCTAssertEqual(try XCTUnwrap(edit(.centerX, -3)).centerX, 0)
        // Exactly the drag's result for the same raw edit.
        var raw = fitted
        raw.centerX = 70.4
        XCTAssertEqual(edit(.centerX, 70.4), raw.snappedEdit(from: fitted, patternWidth: 128, patternHeight: 96))
    }

    func testATypedRadiusLeavesAFractionalFittedCentreBitForBit() throws {
        let outer = try XCTUnwrap(edit(.outer, 29.6))
        XCTAssertEqual(outer.outer, 30)
        XCTAssertEqual(outer.centerX, fitted.centerX)
        XCTAssertEqual(outer.centerY, fitted.centerY)
        let inner = try XCTUnwrap(edit(.inner, 7.4))
        XCTAssertEqual(inner.inner, 7)
        XCTAssertEqual(inner.centerX, fitted.centerX)
        XCTAssertEqual(inner.centerY, fitted.centerY)
    }

    func testRadiiKeepTheDragsOrderAndBounds() throws {
        XCTAssertEqual(try XCTUnwrap(edit(.inner, 99)).inner, 20, "inner stops at the outer radius")
        XCTAssertEqual(try XCTUnwrap(edit(.inner, -4)).inner, 0)
        XCTAssertEqual(try XCTUnwrap(edit(.outer, 2)).outer, 5, "outer stops at the inner radius")
        XCTAssertEqual(try XCTUnwrap(edit(.outer, 0, from: Aperture(centerX: 10, centerY: 10, inner: 0, outer: 20))).outer,
                       1, "a circle of radius 0 is nothing: at least 1")
        XCTAssertEqual(try XCTUnwrap(edit(.outer, 9999)).outer, 128, "the accessible slider's bound: the larger detector side")
    }

    func testNothingChangesForTheSameValueOrANonNumber() {
        XCTAssertNil(edit(.outer, 20))
        XCTAssertNil(edit(.centerX, 69.3133), "the fractional centre typed back is the centre it already is")
        XCTAssertNil(edit(.centerX, .nan))
        XCTAssertNil(edit(.outer, .infinity))
        XCTAssertNil(ApertureEntry.edited(fitted, field: .outer, to: 25, patternWidth: 0, patternHeight: 96))
    }

    func testEachShapeOffersOnlyItsOwnFieldsAndNamesThem() {
        XCTAssertEqual(ApertureEntry.fields(for: .point), [.centerX, .centerY])
        XCTAssertEqual(ApertureEntry.fields(for: .circle), [.centerX, .centerY, .outer])
        XCTAssertEqual(ApertureEntry.fields(for: .rectangle), [.centerX, .centerY, .outer])
        XCTAssertEqual(ApertureEntry.fields(for: .annulus), [.centerX, .centerY, .inner, .outer])
        XCTAssertEqual(ApertureEntry.label(for: .outer, shape: .circle), "Radius")
        XCTAssertEqual(ApertureEntry.label(for: .outer, shape: .rectangle), "Half-width")
        XCTAssertEqual(ApertureEntry.label(for: .outer, shape: .annulus), "Outer radius")
        // The unit is in the spoken name, so the field says it once (NumericFieldSpeech).
        for field in [ApertureEntry.Field.centerX, .centerY, .inner, .outer] {
            let name = ApertureEntry.spokenName(for: field, shape: .annulus)
            XCTAssertEqual(NumericFieldSpeech.label(name, unit: "px"), name, name)
        }
    }

    func testTheStepperRangesAreTheDetectorAndTheDragsOrder() {
        func range(_ f: ApertureEntry.Field) -> ClosedRange<Double> {
            ApertureEntry.range(of: f, in: fitted, patternWidth: 128, patternHeight: 96)
        }
        XCTAssertEqual(range(.centerX), 0...127)
        XCTAssertEqual(range(.centerY), 0...95)
        XCTAssertEqual(range(.inner), 0...20, "inner up to the outer radius")
        XCTAssertEqual(range(.outer), 5...128, "outer from the inner radius to the larger detector side")
        XCTAssertEqual(ApertureEntry.range(of: .outer, in: Aperture(centerX: 1, centerY: 1, inner: 0, outer: 3),
                                           patternWidth: 128, patternHeight: 96), 1...128, "never below one pixel")
        // A stepper click is a typed value one pixel away, through the same rules: it lands on the neighbour whole pixel.
        XCTAssertEqual(ApertureEntry.edited(fitted, field: .centerX, to: ApertureEntry.value(of: .centerX, in: fitted) + 1,
                                            patternWidth: 128, patternHeight: 96)?.centerX, 70)
    }

    /// The row's format reads a typed period and a typed comma as the decimal point in a decimal-comma region (the S3 trap):
    /// 70.4 is never 704.
    func testTheRowsFormatReadsEitherSeparatorAsTheDecimalPoint() throws {
        let german = Locale(identifier: "en_US@rg=dezzzz")
        let entry = DecimalEntryFormat(
            FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(german), locale: german)
        XCTAssertEqual(try entry.parseStrategy.parse("70.4"), 70.4, accuracy: 1e-9)
        XCTAssertEqual(try entry.parseStrategy.parse("70,4"), 70.4, accuracy: 1e-9)
        XCTAssertEqual(entry.format(1234.5), "1234,5", "shown without grouping")
    }

    // MARK: The wiring: AppState sees what a drag would have shown it

    private func stateWithFittedOrigin() -> AppState {
        let state = AppState()
        state.calibrationSession.calibration.origin = OriginMaps(
            width: 2, height: 2,
            measuredX: [Float](repeating: 54.5009, count: 4), measuredY: [Float](repeating: 69.3133, count: 4),
            fittedX: [Float](repeating: 54.5009, count: 4), fittedY: [Float](repeating: 69.3133, count: 4))
        state.calibrationSession.calibration.originProvenance = .fitted
        state.aperture = fitted
        return state
    }

    func testATypedRadiusKeepsTheFittedOriginAndATypedCentreSetsItAsideRecoverably() {
        let radius = stateWithFittedOrigin()
        XCTAssertTrue(ApertureEntry.apply(31.2, to: .outer, in: radius, patternWidth: 128, patternHeight: 96))
        XCTAssertEqual(radius.aperture.outer, 31)
        XCTAssertEqual(radius.aperture.centerX, 69.3133)
        XCTAssertNotNil(radius.calibrationSession.calibration.origin, "a typed radius must not discard the fitted origin")
        XCTAssertFalse(radius.canRestoreFittedOrigin)

        let centre = stateWithFittedOrigin()
        XCTAssertTrue(ApertureEntry.apply(70.4, to: .centerX, in: centre, patternWidth: 128, patternHeight: 96))
        XCTAssertEqual(centre.aperture.centerX, 70)
        XCTAssertNil(centre.calibrationSession.calibration.origin)
        XCTAssertEqual(centre.calibrationSession.calibration.originProvenance, .manual)
        XCTAssertTrue(centre.canRestoreFittedOrigin, "the same recoverable set-aside a centre drag makes")
    }

    func testATypedValueThatChangesNothingTouchesNothing() {
        let state = stateWithFittedOrigin()
        XCTAssertFalse(ApertureEntry.apply(20, to: .outer, in: state, patternWidth: 128, patternHeight: 96))
        XCTAssertEqual(state.aperture, fitted)
        XCTAssertNotNil(state.calibrationSession.calibration.origin)
    }
}
