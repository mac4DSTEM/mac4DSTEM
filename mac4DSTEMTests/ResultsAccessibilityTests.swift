//
//  ResultsAccessibilityTests.swift
//  Results accessibility routes of the 2026-10-12 SwiftUI review residuals (G1, G2).
//

import XCTest
@testable import mac4DSTEM

final class ResultsAccessibilityTests: XCTestCase {

    /// G1: a comparison panel's VoiceOver sample cursor starts at the centre of the image.
    func testSampleCursorStartsAtTheCentre() {
        XCTAssertEqual(ComparisonSampleCursor.centre(width: 10, height: 6),
                       ComparisonSamplePoint(x: 5, y: 3))
        XCTAssertEqual(ComparisonSampleCursor.centre(width: 1, height: 1),
                       ComparisonSamplePoint(x: 0, y: 0))
    }

    /// G1: one step is a twentieth of the image in each axis, and never less than one pixel.
    func testSampleCursorStepsOneTwentiethOfTheImage() {
        let start = ComparisonSamplePoint(x: 100, y: 50)
        XCTAssertEqual(ComparisonSampleCursor.stepped(start, .right, width: 200, height: 100),
                       ComparisonSamplePoint(x: 110, y: 50))
        XCTAssertEqual(ComparisonSampleCursor.stepped(start, .left, width: 200, height: 100),
                       ComparisonSamplePoint(x: 90, y: 50))
        XCTAssertEqual(ComparisonSampleCursor.stepped(start, .down, width: 200, height: 100),
                       ComparisonSamplePoint(x: 100, y: 55))
        XCTAssertEqual(ComparisonSampleCursor.stepped(start, .up, width: 200, height: 100),
                       ComparisonSamplePoint(x: 100, y: 45))
        // A 10-pixel image: a twentieth is under a pixel, so the step is one pixel.
        XCTAssertEqual(ComparisonSampleCursor.stepped(ComparisonSamplePoint(x: 5, y: 5),
                                                      .right, width: 10, height: 10),
                       ComparisonSamplePoint(x: 6, y: 5))
    }

    /// G1: the cursor never leaves the image, in any direction.
    func testSampleCursorIsClampedInsideTheImage() {
        XCTAssertEqual(ComparisonSampleCursor.stepped(ComparisonSamplePoint(x: 3, y: 0),
                                                      .left, width: 200, height: 100),
                       ComparisonSamplePoint(x: 0, y: 0))
        XCTAssertEqual(ComparisonSampleCursor.stepped(ComparisonSamplePoint(x: 0, y: 0),
                                                      .up, width: 200, height: 100),
                       ComparisonSamplePoint(x: 0, y: 0))
        XCTAssertEqual(ComparisonSampleCursor.stepped(ComparisonSamplePoint(x: 198, y: 99),
                                                      .right, width: 200, height: 100),
                       ComparisonSamplePoint(x: 199, y: 99))
        XCTAssertEqual(ComparisonSampleCursor.stepped(ComparisonSamplePoint(x: 199, y: 97),
                                                      .down, width: 200, height: 100),
                       ComparisonSamplePoint(x: 199, y: 99))
    }

    /// G2: Export Data is enabled exactly when nothing runs and a result image exists.
    func testExportDataReasonIsNilOnlyWhenEnabled() {
        XCTAssertNil(ResultsActionReason.exportData(isBusy: false, hasResultImage: true))
        XCTAssertEqual(ResultsActionReason.exportData(isBusy: true, hasResultImage: true),
                       ResultsActionReason.busy)
        XCTAssertEqual(ResultsActionReason.exportData(isBusy: false, hasResultImage: false),
                       "No result to export yet.")
        XCTAssertEqual(ResultsActionReason.exportData(isBusy: true, hasResultImage: false),
                       ResultsActionReason.busy, "a busy app is named first")
    }

    /// G2: Save to Results is enabled exactly when nothing runs and the gate gives no refusal;
    /// a refusal is spoken as the gate's own text, and busy is named first.
    func testSaveToResultsReasonIsNilOnlyWhenEnabled() {
        XCTAssertNil(ResultsActionReason.saveToResults(isBusy: false, sidecarRefusal: nil))
        XCTAssertEqual(ResultsActionReason.saveToResults(isBusy: true, sidecarRefusal: nil),
                       ResultsActionReason.busy)
        XCTAssertEqual(ResultsActionReason.saveToResults(isBusy: true, sidecarRefusal: "refused"),
                       ResultsActionReason.busy, "a busy app is named first")
        XCTAssertEqual(ResultsActionReason.saveToResults(isBusy: false, sidecarRefusal: "refused"),
                       "refused", "the gate's own refusal text, unchanged")
    }
}
