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
import DSTEMSession
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

    // MARK: - The set-aside is a lineage fact and a durable warning (owner decision 1, 2026-09-30 night)

    /// The origin fit lands as a lineage node (as `calibrateOrigin` records it),
    /// then a strain run that consumed it.
    private func recordFitAndAStrainOnIt(_ state: AppState) -> (fit: String, strain: String) {
        state.recordOriginCalibrationRun(fitFunction: .plane, method: .centreOfMass,
                                         probeRadius: 5, rmsResidual: 0.05)
        let strain = state.replay.record(kind: "strain", parameters: ["basis_mode": "consensus"],
                                         under: .detectorIdentity)
        let fit = state.replay.lineage.activeNodes().first { $0.kind == "calibration_origin" }?.id ?? ""
        return (fit, strain)
    }

    private func activeOrigin(_ state: AppState) -> SessionLineage.Node? {
        state.replay.lineage.activeNodes().first { $0.kind == "calibration_origin" }
    }

    private func dragCentre(_ state: AppState) {
        var raw = state.aperture
        raw.centerX = 70.4; raw.centerY = 55.2
        state.updateAperture(raw.snappedEdit(from: state.aperture, patternWidth: 128, patternHeight: 128))
    }

    /// A centre drag replaces the origin: the lineage says so, so a strain that
    /// stood on the fit reads "computed with different origin calibration"
    /// (D068). Mutations it catches: no node recorded at the set-aside (the
    /// strain reads current on an origin nobody applies any more); the node
    /// recorded with any method but "manual".
    func testACentreDragRecordsAManualOriginNodeAndAStrainOnTheFitReadsStale() throws {
        let state = stateWithFittedOrigin()
        let (fit, strain) = recordFitAndAStrainOnIt(state)
        XCTAssertEqual(activeOrigin(state)?.id, fit, "precondition")
        dragCentre(state)
        let manual = try XCTUnwrap(activeOrigin(state))
        XCTAssertNotEqual(manual.id, fit, "the fit has a child (the strain), so the drag is a new node")
        XCTAssertEqual(manual.kind, "calibration_origin")
        XCTAssertEqual(manual.parameters["method"], "manual")
        let uses = state.replay.lineage.calibrationUses(of: try XCTUnwrap(state.replay.lineage.node(id: strain)))
        let origin = try XCTUnwrap(uses.first { $0.kind == "calibration_origin" })
        XCTAssertEqual(origin.used, fit)
        XCTAssertEqual(origin.active, manual.id)
        XCTAssertTrue(origin.changed)
        XCTAssertEqual(uses.filter(\.changed).map(\.kind), ["calibration_origin"])
    }

    /// A centre dragged with no fit to displace records nothing: there is no
    /// fitted origin to have replaced. Mutation it catches: the record moved
    /// out of the `if let displaced` branch into the whole centre-change branch.
    func testACentreDragWithNoFitSetAsideRecordsNoNode() {
        let state = AppState()
        state.aperture = Aperture(centerX: 69.3133, centerY: 54.5009, inner: 0, outer: 20)
        var raw = state.aperture
        raw.centerX = 70.4; raw.centerY = 55.2
        state.updateAperture(raw.snappedEdit(from: state.aperture, patternWidth: 128, patternHeight: 128))
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual, "precondition")
        XCTAssertFalse(state.canRestoreFittedOrigin)
        XCTAssertTrue(state.replay.lineage.nodes.isEmpty)
    }

    /// A second drag tick adds nothing (the run would collapse in place anyway,
    /// R3; this pins the count, and the node's identity). Mutation it catches:
    /// the set-aside record removed (one node, not two).
    func testDraggingTheCentreTwiceRecordsOneManualNode() {
        let state = stateWithFittedOrigin()
        _ = recordFitAndAStrainOnIt(state)
        dragCentre(state)
        let after = state.replay.lineage.nodes.filter { $0.kind == "calibration_origin" }.count
        var raw = state.aperture
        raw.centerX = 71; raw.centerY = 56
        state.updateAperture(raw)
        XCTAssertEqual(state.replay.lineage.nodes.filter { $0.kind == "calibration_origin" }.count, after)
        XCTAssertEqual(after, 2, "the fit and the manual node")
    }

    /// Mutation it catches: recording on every `updateAperture` call.
    func testARadiusOnlyDragRecordsNoLineageNode() {
        let state = stateWithFittedOrigin()
        let (fit, strain) = recordFitAndAStrainOnIt(state)
        let before = state.replay.lineage.nodes.count
        var raw = state.aperture
        raw.outer = 30.4
        state.updateAperture(raw.snappedEdit(from: state.aperture, patternWidth: 128, patternHeight: 128))
        XCTAssertEqual(state.replay.lineage.nodes.count, before)
        XCTAssertEqual(activeOrigin(state)?.id, fit)
        XCTAssertEqual(state.replay.lineage.calibrationUses(
            of: state.replay.lineage.node(id: strain)!).filter(\.changed).count, 0)
    }

    /// Restore puts the fitted maps back, so the lineage's active origin must
    /// stop saying "manual". Rewind cannot do it (it refuses to restore an
    /// origin), so a new node is recorded from the fit's own parameters — the
    /// strain that stood on the OLD node still reads stale (conservative: the
    /// numbers are the same, the node is not). Mutation it catches: no record
    /// at restore (the active origin stays "manual" while the maps are back).
    /// With nothing computed between fit, drag and Restore, the manual record
    /// collapses into the fit's node in place (no child pins it), so the fit's
    /// parameters must be captured at the set-aside and restored from there —
    /// else the lineage keeps only "restored" (Fable supervisor, 2026-09-30
    /// night). Mutation it catches: the capture skipped.
    func testRestoreWithNothingComputedKeepsTheFitsOwnParameters() throws {
        let state = stateWithFittedOrigin()
        state.recordOriginCalibrationRun(fitFunction: .plane, method: .centreOfMass,
                                         probeRadius: 5, rmsResidual: 0.05)
        dragCentre(state)
        state.restoreFittedOrigin()
        let node = try XCTUnwrap(activeOrigin(state))
        XCTAssertEqual(node.parameters["method"], OriginMethod.centreOfMass.rawValue)
        XCTAssertEqual(node.parameters["fit_function"], OriginFitFunction.plane.rawValue)
        XCTAssertEqual(node.parameters["fit_rms_px"], String(Float(0.05)))
    }

    func testRestoreFittedOriginRecordsTheFitAgainAndNoLongerSaysManual() throws {
        let state = stateWithFittedOrigin()
        _ = recordFitAndAStrainOnIt(state)
        dragCentre(state)
        XCTAssertEqual(activeOrigin(state)?.parameters["method"], "manual", "precondition")
        state.restoreFittedOrigin()
        XCTAssertNotNil(state.calibrationSession.calibration.origin)
        let restored = try XCTUnwrap(activeOrigin(state))
        XCTAssertEqual(restored.parameters["method"], OriginMethod.centreOfMass.rawValue)
        XCTAssertEqual(restored.parameters["fit_function"], OriginFitFunction.plane.rawValue)
        XCTAssertNotNil(restored.parameters["origin_x_px"])
    }

    /// The readiness row: a centre that replaced a fit is a warning while the
    /// fit is parked; a manual centre with nothing set aside is not; Restore
    /// clears it. Mutations it catches: `isWarning` ignoring the parked fit;
    /// `isWarning` true for every manual origin.
    func testTheOriginRowIsAWarningOnlyWhileAFittedOriginIsSetAside() throws {
        let state = stateWithFittedOrigin()
        state.calibrationSession.calibration.probeRadius = 5
        state.calibrationSession.provenance.probe = .measuredInApp
        func origin() throws -> CalibrationReadinessItem {
            try XCTUnwrap(CalibrationReadinessReport.make(
                calibration: state.calibrationSession.calibration,
                provenance: state.calibrationSession.provenance).items.first { $0.kind == .originProbe })
        }
        XCTAssertFalse(CalibrationReadinessRow.isWarning(try origin(), canRestoreFittedOrigin: state.canRestoreFittedOrigin))
        dragCentre(state)
        XCTAssertTrue(state.canRestoreFittedOrigin)
        XCTAssertTrue(try origin().status.isReady, "a manual centre is ready — it is the caveat that is missing")
        XCTAssertTrue(CalibrationReadinessRow.isWarning(try origin(), canRestoreFittedOrigin: state.canRestoreFittedOrigin))
        state.restoreFittedOrigin()
        XCTAssertFalse(CalibrationReadinessRow.isWarning(try origin(), canRestoreFittedOrigin: state.canRestoreFittedOrigin))
        // A manual centre with nothing parked (the fit was never made).
        let bare = AppState()
        bare.calibrationSession.calibration.probeRadius = 5
        bare.calibrationSession.provenance.probe = .manual
        bare.calibrationSession.calibration.originProvenance = .manual
        let item = try XCTUnwrap(CalibrationReadinessReport.make(
            calibration: bare.calibrationSession.calibration,
            provenance: bare.calibrationSession.provenance).items.first { $0.kind == .originProbe })
        XCTAssertEqual(item.status, .ready(.manual))
        XCTAssertFalse(CalibrationReadinessRow.isWarning(item, canRestoreFittedOrigin: bare.canRestoreFittedOrigin),
                       "nothing was set aside, so nothing to warn about")
        // Fit anyway stays a warning (the row's existing idiom).
        XCTAssertTrue(CalibrationReadinessRow.isWarning(
            CalibrationReadinessItem(kind: .ellipse, status: .ready(.fitAnyway), detail: ""),
            canRestoreFittedOrigin: false))
    }
}
