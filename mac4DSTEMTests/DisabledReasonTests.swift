//
//  DisabledReasonTests.swift
//  Drive 14 (2026-10-13): Save to Session, Export Labels…, Align Next Level and Fit Aberrations dimmed with no reason.
//  Each reason is nil EXACTLY when the button's old `.disabled` condition was false, over every input combination, so
//  the buttons dim in the same states as before and only gain a reason.
//

import XCTest
@testable import mac4DSTEM

final class DisabledReasonTests: XCTestCase {
    private let bools = [false, true]

    /// Mutation: drop the loading check - red (the loading-only state would read enabled).
    func testSaveToSessionReasonMatchesTheOldCondition() {
        for loading in bools { for product in bools { for busy in bools { for refusal in [nil, "The sidecar is read-only."] {
            let old = loading || !product || busy || refusal != nil
            let reason = ResultsActionReason.saveToSession(isLoading: loading, hasDisplayedProduct: product, isBusy: busy, sidecarRefusal: refusal)
            XCTAssertEqual(reason != nil, old, "loading \(loading) product \(product) busy \(busy) refusal \(refusal ?? "nil")")
        } } } }
        XCTAssertEqual(ResultsActionReason.saveToSession(isLoading: false, hasDisplayedProduct: true, isBusy: false, sidecarRefusal: "R"), "R",
                       "the gate's own refusal text, so reason and gate agree in wording")
    }

    /// Mutation: invert isEmpty - red.
    func testExportLabelsReasonMatchesTheOldCondition() {
        XCTAssertNil(DiskCentreControlReason.exportLabels(isEmpty: false))
        XCTAssertEqual(DiskCentreControlReason.exportLabels(isEmpty: true), "There are no labelled centres to export yet.")
    }

    /// Mutation: drop the isComplete check - red.
    func testParallaxReasonsMatchTheOldConditions() {
        for busy in bools { for preview in bools { for complete in bools {
            let oldAlign = busy || !preview || complete
            XCTAssertEqual(ParallaxActionReason.alignNextLevel(isBusy: busy, hasPreview: preview, isComplete: complete) != nil, oldAlign)
            let oldFit = busy || !complete
            XCTAssertEqual(ParallaxActionReason.fitAberrations(isBusy: busy, alignmentComplete: complete) != nil, oldFit)
        } } }
    }
}
