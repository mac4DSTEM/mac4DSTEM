//
//  SessionProductOriginTests.swift
//  S12: the Info tab's in-memory list (WorkspaceInspector's
//  `SessionProductsSections`) said "Computed this session" over rows that were
//  bare "exists" predicates, so an origin fit, a rotation or a set of Bragg
//  disks restored from a session read as computed here. The wording now says
//  where each value came from.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SessionProductOriginTests: XCTestCase {

    /// Mutations: `originCalibration` returning nil for every case -> red;
    /// `.fitted` and `.sessionMaps` returning the same word -> the
    /// restored/fitted distinction goes red.
    func testOriginCalibrationSaysFittedHereOrRestoredOrFromFile() {
        XCTAssertEqual(SessionProductOrigin.originCalibration(.fitted), "fitted here")
        XCTAssertEqual(SessionProductOrigin.originCalibration(.sessionMean), "restored from session")
        XCTAssertEqual(SessionProductOrigin.originCalibration(.sessionMaps), "restored from session")
        XCTAssertEqual(SessionProductOrigin.originCalibration(.fileMean), "from file")
        XCTAssertEqual(SessionProductOrigin.originCalibration(.fileMaps), "from file")
        XCTAssertEqual(SessionProductOrigin.originCalibration(.manual), "set by hand")
        XCTAssertNil(SessionProductOrigin.originCalibration(.geometricDefault), "an unfitted default names nothing")
    }

    func testRotationSaysMeasuredHereOrRestoredOrFromFile() {
        XCTAssertEqual(SessionProductOrigin.rotation(.measuredInApp), "measured here")
        XCTAssertEqual(SessionProductOrigin.rotation(.sessionSidecar), "restored from session")
        XCTAssertEqual(SessionProductOrigin.rotation(.importedFile), "from file")
        XCTAssertEqual(SessionProductOrigin.rotation(.manual), "set by hand")
        XCTAssertNil(SessionProductOrigin.rotation(nil))
    }

    /// Mutation: ignoring `computedThisSession` -> the restored case goes red.
    func testBraggDisksSayRestoredWhenTheyWereNotDetectedThisSession() {
        XCTAssertEqual(SessionProductOrigin.braggDisks(peakCount: 120, computedThisSession: true), "120 peaks")
        XCTAssertEqual(SessionProductOrigin.braggDisks(peakCount: 93_209, computedThisSession: true), "93,209 peaks")
        XCTAssertEqual(SessionProductOrigin.braggDisks(peakCount: 120, computedThisSession: false),
                       "120 peaks · restored")
        XCTAssertNil(SessionProductOrigin.braggDisks(peakCount: nil, computedThisSession: false))
    }

    /// The predicate the row uses: `completedDiskSummary` is written by a
    /// detection run and only there (a session restore sets the peaks and the
    /// count, not the summary). Mutation: a restore that also sets the summary
    /// -> red (nothing to test but the state below).
    func testARestoredPeakSetHasNoDetectionSummaryAndADetectedOneDoes() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: {
            var spec = LoadSpecification()
            spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
            return spec
        }())
        XCTAssertNil(state.completedDiskSummary, "nothing detected yet")
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        let vectors = try XCTUnwrap(state.resultPresentation.braggVectors, state.statusText)
        XCTAssertNotNil(state.completedDiskSummary, "a detection run writes the summary")

        // What a session restore does (AppState+Open): sets the peaks, not the summary.
        let restored = AppState()
        restored.resultPresentation.setBraggVectors(vectors)
        restored.resultPresentation.setBraggPeakCount(vectors.totalPeakCount)
        XCTAssertNil(restored.completedDiskSummary)
    }
}
