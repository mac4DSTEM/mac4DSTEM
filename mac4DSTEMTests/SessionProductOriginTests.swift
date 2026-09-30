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

    /// A6 (owner, ADR 050): the row's circle is empty only when NO origin is in memory. A
    /// session that restored only a mean origin (no maps) read as absent beside Prepare's
    /// "From session". Mutations: `hasOrigin` reading `origin != nil` again (the mean-only
    /// cases go red); always true (the default case goes red); the word and the circle
    /// disagreeing for any provenance.
    func testTheOriginRowIsPresentForAnyOriginAndEmptyOnlyForNone() {
        func calibration(_ provenance: OriginProvenance, maps: Bool = false) -> Calibration {
            var value = Calibration()
            value.originProvenance = provenance
            if maps {
                value.origin = OriginMaps(width: 1, height: 1, measuredX: nil, measuredY: nil,
                                          fittedX: [3], fittedY: [4])
            }
            return value
        }
        XCTAssertFalse(SessionProductOrigin.hasOrigin(Calibration()), "a fresh calibration has none")
        XCTAssertFalse(SessionProductOrigin.hasOrigin(calibration(.geometricDefault)))
        XCTAssertTrue(SessionProductOrigin.hasOrigin(calibration(.sessionMean)), "mean only: was an empty circle")
        XCTAssertTrue(SessionProductOrigin.hasOrigin(calibration(.fileMean)))
        XCTAssertTrue(SessionProductOrigin.hasOrigin(calibration(.manual)), "a hand-set centre is an origin")
        XCTAssertTrue(SessionProductOrigin.hasOrigin(calibration(.fitted, maps: true)))
        XCTAssertTrue(SessionProductOrigin.hasOrigin(calibration(.sessionMaps, maps: true)))
        // The circle and the word agree for every provenance.
        for provenance in [OriginProvenance.geometricDefault, .fileMean, .fileMaps, .sessionMean,
                           .sessionMaps, .fitted, .manual] {
            XCTAssertEqual(SessionProductOrigin.hasOrigin(calibration(provenance)),
                           SessionProductOrigin.originCalibration(provenance) != nil, "\(provenance)")
        }
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
