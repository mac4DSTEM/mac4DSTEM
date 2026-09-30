//
//  PrepareCalibrationPolishTests.swift
//  Polish 2026-09-30 (drives 1, 2A, 2B): wording and visibility decisions of the
//  Prepare › Calibration rows and the Session sidebar, as pure functions.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PrepareCalibrationPolishTests: XCTestCase {

    // MARK: item 1 — a visible re-measure

    /// Mutation it catches: the title ignoring readiness (always "Measure").
    func testTheOriginActionReadsReMeasureOnceAnOriginExists() {
        XCTAssertEqual(CalibrationReadinessRow.originActionTitle(status: .missing), "Measure Origin & Probe")
        XCTAssertEqual(CalibrationReadinessRow.originActionTitle(status: .unusable), "Measure Origin & Probe")
        XCTAssertEqual(CalibrationReadinessRow.originActionTitle(status: .ready(.measuredInApp)), "Re-measure Origin & Probe")
        XCTAssertEqual(CalibrationReadinessRow.originActionTitle(status: .ready(.importedFile)), "Re-measure Origin & Probe")
    }

    /// Mutations it catches: no re-measure on a ready origin in Prepare; the
    /// re-measure offered beside Restore Fitted Origin; offered in the export
    /// sheet; a missing origin losing its action.
    func testTheReMeasureIsOfferedInPrepareUnlessRestoreIsTheAction() {
        let ready = CalibrationReadinessStatus.ready(.measuredInApp)
        XCTAssertTrue(CalibrationReadinessRow.showsAction(
            kind: .originProbe, status: ready, canRestoreFittedOrigin: false, offersRemeasure: true))
        XCTAssertFalse(CalibrationReadinessRow.showsAction(
            kind: .originProbe, status: ready, canRestoreFittedOrigin: true, offersRemeasure: true),
            "Restore Fitted Origin is the row's action while a fit is set aside")
        XCTAssertFalse(CalibrationReadinessRow.showsAction(
            kind: .originProbe, status: ready, canRestoreFittedOrigin: false, offersRemeasure: false),
            "the export sheet keeps its old rows")
        XCTAssertTrue(CalibrationReadinessRow.showsAction(
            kind: .originProbe, status: .missing, canRestoreFittedOrigin: false, offersRemeasure: false))
        // The other rows are unchanged: no action on a ready ellipse or rotation.
        XCTAssertFalse(CalibrationReadinessRow.showsAction(
            kind: .ellipse, status: ready, canRestoreFittedOrigin: false, offersRemeasure: true))
        XCTAssertFalse(CalibrationReadinessRow.showsAction(
            kind: .rotation, status: ready, canRestoreFittedOrigin: false, offersRemeasure: true))
        XCTAssertTrue(CalibrationReadinessRow.showsAction(
            kind: .rScale, status: ready, canRestoreFittedOrigin: false, offersRemeasure: false),
            "the manual scale editor stays")
    }

    // MARK: item 2 — the file clause only for a file's origin

    /// Mutations it catches: the file clause on a measured fit; the clause lost
    /// for a file's maps.
    func testTheFileClauseIsSaidOnlyForAnOriginThatCameFromAFile() {
        let file = "Aperture center replaced the fitted origin; the file's recorded mean, if any, was discarded."
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: .fileMaps), file)
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: .fileMean), file)
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: .fitted),
                       "Aperture center replaced the fitted origin.")
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: .sessionMaps),
                       "Aperture center replaced the fitted origin.")
        XCTAssertEqual(CalibrationReadinessRow.originReplacedDetail(displaced: nil),
                       "Aperture center replaced the fitted origin.")
    }

    // MARK: item 3 — Prepare says what was not carried

    private let originRefusal = CalibrationInvalidation(
        field: .origin, reason: "The saved fitted-origin maps cover 44 × 40 scan positions.")
    private let sessionRefusal = CalibrationInvalidation(
        field: .sessionCalibration, reason: "The saved session did not record which view of the file it was measured on.")
    private let ellipseLoss = CalibrationInvalidation(field: .ellipse, reason: "x")

    /// Mutations it catches: no note for a refused origin; a note on another
    /// row; the origin note repeated under a section note.
    func testTheOriginRowNamesADroppedOrigin() {
        XCTAssertNotNil(CalibrationCarryNotes.rowNote(kind: .originProbe, invalidated: [originRefusal]))
        XCTAssertTrue(CalibrationCarryNotes.rowNote(kind: .originProbe, invalidated: [originRefusal])!
            .contains("Info › Not carried into this view"))
        XCTAssertNil(CalibrationCarryNotes.rowNote(kind: .qScale, invalidated: [originRefusal]))
        XCTAssertNil(CalibrationCarryNotes.rowNote(kind: .originProbe, invalidated: []))
        XCTAssertNil(CalibrationCarryNotes.rowNote(kind: .originProbe, invalidated: [ellipseLoss]))
        XCTAssertNil(CalibrationCarryNotes.rowNote(kind: .originProbe, invalidated: [originRefusal, sessionRefusal]),
                     "a refused session is said once, for the section")
    }

    /// Mutations it catches: no section note for a refused session; a section
    /// note for an origin-only loss.
    func testTheSectionNamesARefusedSessionCalibration() {
        XCTAssertEqual(CalibrationCarryNotes.sectionNote(invalidated: [sessionRefusal]),
                       "Saved calibration not applied to this view — see Info › Not carried into this view")
        XCTAssertNil(CalibrationCarryNotes.sectionNote(invalidated: [originRefusal]))
        XCTAssertNil(CalibrationCarryNotes.sectionNote(invalidated: []))
        XCTAssertTrue(CalibrationCarryNotes.sessionCalibrationRefused([originRefusal, sessionRefusal]))
        XCTAssertFalse(CalibrationCarryNotes.sessionCalibrationRefused([originRefusal]))
    }

    // MARK: item 4 — the Session sidebar

    /// Mutation it catches: the wording ignoring the flag either way.
    func testTheSessionExplainerSaysSavedOnceThisSessionWroteTheSidecar() {
        let loaded = SessionSidebarWording.explainer(savedThisSession: false)
        XCTAssertEqual(loaded.text, "Loaded with the dataset — from earlier analysis")
        XCTAssertTrue(loaded.help.contains("nothing here was computed in this session"))
        let saved = SessionSidebarWording.explainer(savedThisSession: true)
        XCTAssertEqual(saved.text, "Saved with the dataset")
        XCTAssertFalse(saved.help.contains("nothing here was computed"),
                       "a sidecar written now does hold this session's work")
        XCTAssertTrue(saved.help.contains("earlier analysis"), "and may still hold the earlier work")
    }

    /// The reported flow: reopen a dataset whose sidecar recorded its view
    /// (`sessionLoadSpecification` non-nil), continue, save — the flag, not the
    /// recorded view, decides. Mutations it catches: `noteWritten` not setting
    /// the flag; `release` not clearing it (the next dataset would read Saved).
    @MainActor
    func testTheWriteFlagBeatsARecordedViewAndIsClearedWhenTheDatasetChanges() {
        let state = AppState()
        state.sessionLoadSpecification = .fullExtent
        XCTAssertFalse(state.sessionSidecar.wroteThisSession)
        XCTAssertEqual(SessionSidebarWording.explainer(
            savedThisSession: state.sessionSidecar.wroteThisSession).text,
            "Loaded with the dataset — from earlier analysis")
        state.sessionSidecar.noteWritten()
        XCTAssertTrue(state.sessionSidecar.wroteThisSession)
        XCTAssertEqual(SessionSidebarWording.explainer(
            savedThisSession: state.sessionSidecar.wroteThisSession).text,
            "Saved with the dataset", "a save after a reopen is still a save")
        state.sessionSidecar.release()
        XCTAssertFalse(state.sessionSidecar.wroteThisSession, "a new dataset starts unwritten")
    }

    /// Mutation it catches: the refused row still reading "Calibration".
    func testARefusedCalibrationRowIsNotReadAsLoaded() {
        XCTAssertEqual(SessionSidebarWording.calibrationRowTitle(refusedForThisView: false), "Calibration")
        XCTAssertEqual(SessionSidebarWording.calibrationRowTitle(refusedForThisView: true),
                       "Calibration — not used in this view")
    }
}
