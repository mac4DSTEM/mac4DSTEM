//
//  SwiftUIReviewDTests.swift
//  Lane D of the 2026-10-07 SwiftUI review: the spectrum strip's keyboard / VoiceOver view actions and its drawing cost.
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class SwiftUIReviewDTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    private func zoomed() -> SpectrumViewport {
        var vp = SpectrumViewport(domain: 0...10, minimumSpan: 0.02)
        vp.lo = 2; vp.hi = 6
        return vp
    }

    /// D1: zoom in narrows the window about its centre; zoom out widens it back.
    /// Mutation: zoomIn and zoomOut swapped - red.
    func testZoomActionsNarrowAndWidenAboutTheCentre() {
        let vp = zoomed()
        let inn = SpectrumStripLogic.apply(.zoomIn, to: vp)
        XCTAssertEqual(inn.span, 4 / SpectrumStripLogic.zoomStep, accuracy: 1e-12)
        XCTAssertEqual((inn.lo + inn.hi) / 2, 4, accuracy: 1e-12, "the centre stays")
        let out = SpectrumStripLogic.apply(.zoomOut, to: vp)
        XCTAssertEqual(out.span, 4 * SpectrumStripLogic.zoomStep, accuracy: 1e-12)
        XCTAssertEqual((out.lo + out.hi) / 2, 4, accuracy: 1e-12)
        XCTAssertEqual(SpectrumStripLogic.apply(.zoomOut, to: inn).span, 4, accuracy: 1e-12)
    }

    /// D1: pan right moves towards high energy by a fraction of the visible width, left the other way; neither leaves the domain.
    /// Mutation: the sign of panLeft flipped - red.
    func testPanActionsMoveTheWindowAndStayInTheDomain() {
        let vp = zoomed()
        let r = SpectrumStripLogic.apply(.panRight, to: vp)
        XCTAssertEqual(r.lo, 2 + 4 * SpectrumStripLogic.panStep, accuracy: 1e-12)
        XCTAssertEqual(r.span, 4, accuracy: 1e-12)
        let l = SpectrumStripLogic.apply(.panLeft, to: vp)
        XCTAssertEqual(l.lo, 2 - 4 * SpectrumStripLogic.panStep, accuracy: 1e-12)
        var edge = vp; edge.lo = 0; edge.hi = 4
        XCTAssertEqual(SpectrumStripLogic.apply(.panLeft, to: edge).lo, 0, "the domain's start is a wall")
        var top = vp; top.lo = 6; top.hi = 10
        XCTAssertEqual(SpectrumStripLogic.apply(.panRight, to: top).hi, 10, "the domain's end is a wall")
    }

    /// D1: the counts axis (yScale) is not part of a pan or zoom step, as with the mouse.
    /// Mutation: the step resets yScale - red.
    func testStepsLeaveTheCountsStretchAlone() {
        var vp = zoomed(); vp.yScale = 4
        for a in [SpectrumStripLogic.ViewAction.zoomIn, .zoomOut, .panLeft, .panRight] {
            XCTAssertEqual(SpectrumStripLogic.apply(a, to: vp).yScale, 4)
        }
    }

    /// D1: the label is stable while the view moves; the energy span and the unit are the value.
    /// Mutation: the span put back into the label - red.
    func testAccessibilityLabelIsStableAndTheValueCarriesTheSpan() {
        let a = SpectrumStripLogic.accessibility(title: "Spectrum", subtitle: "whole map", lo: 0, hi: 20, perPixel: false, locale: en)
        let b = SpectrumStripLogic.accessibility(title: "Spectrum", subtitle: "whole map", lo: 1.2, hi: 8.5, perPixel: false, locale: en)
        XCTAssertEqual(a.label, b.label)
        XCTAssertFalse(a.label.contains("keV"))
        XCTAssertNotEqual(a.value, b.value)
        XCTAssertEqual(b.value, "Energy from 1.200 to 8.500 keV. Y axis in counts.")
        let c = SpectrumStripLogic.accessibility(title: "Spectrum", subtitle: "", lo: 0, hi: 20, perPixel: true, locale: en)
        XCTAssertEqual(c.label, "Spectrum")
        XCTAssertTrue(c.value.hasSuffix("counts per pixel."))
    }

    /// D1: a pin chip's spoken name says what the click does.
    /// Mutation: the word "Unpin" dropped - red.
    func testPinChipSpokenName() {
        XCTAssertEqual(SpectrumStripLogic.unpinLabel("Pin 2"), "Unpin Pin 2")
    }
}
