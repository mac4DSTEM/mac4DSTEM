//
//  ApertureDragOriginTests.swift
//  Register item "Radius-only aperture drag destroys the fitted origin" (Gate D
//  2026-09-30). `ApertureOverlay.emit` rounded the CENTRE on every handle drag;
//  after an origin fit the live centre is fractional, so a drag of only a
//  radius handle published a "moved" centre and `updateAperture` discarded the
//  fitted origin on rounding alone. The decision is now `Aperture.snappedEdit`.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class ApertureSnappedEditTests: XCTestCase {
    private let fitted = Aperture(centerX: 69.3133, centerY: 54.5009, inner: 0, outer: 20)

    func testARadiusOnlyEditKeepsTheFractionalCentreBitForBit() {
        var raw = fitted
        raw.outer = 29.6
        let out = raw.snappedEdit(from: fitted, patternWidth: 128, patternHeight: 128)
        XCTAssertEqual(out.centerX, fitted.centerX, "an unchanged centre must not be re-rounded")
        XCTAssertEqual(out.centerY, fitted.centerY)
        XCTAssertEqual(out.outer, 30, "radii still snap to whole pixels")
        XCTAssertEqual(out.inner, 0)
    }

    func testAnInnerRadiusEditKeepsTheCentreToo() {
        var raw = Aperture(centerX: 69.3133, centerY: 54.5009, inner: 5, outer: 20)
        let previous = raw
        raw.inner = 7.4
        let out = raw.snappedEdit(from: previous, patternWidth: 128, patternHeight: 128)
        XCTAssertEqual(out.centerX, previous.centerX)
        XCTAssertEqual(out.centerY, previous.centerY)
        XCTAssertEqual(out.inner, 7)
    }

    func testACentreDragStillSnapsToWholePixelsAndClampsAfterRounding() {
        var raw = fitted
        raw.centerX = 70.4; raw.centerY = 128.4
        let out = raw.snappedEdit(from: fitted, patternWidth: 128, patternHeight: 128)
        XCTAssertEqual(out.centerX, 70)
        XCTAssertEqual(out.centerY, 127, "clamp after rounding (ui-08): 128 would be one past the last pixel")
        raw.centerX = -3
        XCTAssertEqual(raw.snappedEdit(from: fitted, patternWidth: 128, patternHeight: 128).centerX, 0)
    }

    func testAnIntegerCentreIsUnchangedByEitherPolicy() {
        let start = Aperture(centerX: 64, centerY: 64, inner: 0, outer: 20)
        var raw = start
        raw.outer = 33.2
        let out = raw.snappedEdit(from: start, patternWidth: 128, patternHeight: 128)
        XCTAssertEqual(out, Aperture(centerX: 64, centerY: 64, inner: 0, outer: 33))
    }
}

/// The wiring: the value the overlay publishes must not trip `updateAperture`'s
/// centre-change branch (which parks the fitted maps and sets provenance manual).
@MainActor
final class ApertureRadiusDragKeepsFittedOriginTests: XCTestCase {
    private func stateWithFittedOrigin() -> AppState {
        let state = AppState()
        let count = 4
        state.calibrationSession.calibration.origin = OriginMaps(
            width: 2, height: 2,
            measuredX: [Float](repeating: 54.5009, count: count),
            measuredY: [Float](repeating: 69.3133, count: count),
            fittedX: [Float](repeating: 54.5009, count: count),
            fittedY: [Float](repeating: 69.3133, count: count))
        state.calibrationSession.calibration.originProvenance = .fitted
        state.aperture = Aperture(centerX: 69.3133, centerY: 54.5009, inner: 0, outer: 20)
        return state
    }

    func testARadiusOnlyDragLeavesTheFittedOriginAlone() {
        let state = stateWithFittedOrigin()
        var raw = state.aperture
        raw.outer = 30.4
        state.updateAperture(raw.snappedEdit(from: state.aperture, patternWidth: 128, patternHeight: 128))
        XCTAssertNotNil(state.calibrationSession.calibration.origin, "a radius drag must not discard the fitted origin")
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .fitted)
        XCTAssertFalse(state.canRestoreFittedOrigin)
        XCTAssertNil(state.supersededFittedOrigin?.maps)
        XCTAssertEqual(state.aperture.outer, 30)
        XCTAssertEqual(state.aperture.centerX, 69.3133)
    }

    /// Control: the branch the drag is MEANT to reach stays reachable.
    func testACentreDragStillSetsTheOriginAsideRecoverably() {
        let state = stateWithFittedOrigin()
        var raw = state.aperture
        raw.centerX = 70.4; raw.centerY = 55.2
        state.updateAperture(raw.snappedEdit(from: state.aperture, patternWidth: 128, patternHeight: 128))
        XCTAssertNil(state.calibrationSession.calibration.origin)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)
        XCTAssertTrue(state.canRestoreFittedOrigin)
        XCTAssertEqual(state.aperture.centerX, 70)
        XCTAssertEqual(state.aperture.centerY, 55)
    }
}
