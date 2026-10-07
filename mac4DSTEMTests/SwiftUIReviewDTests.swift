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

    // MARK: D2 - drawing cost

    /// D2: a one-channel spike (and a one-channel dip) in a spectrum far wider than the plot survives the decimation.
    /// Mutation: only the first channel of each column kept - red.
    func testDecimationKeepsASingleChannelSpikeAndDip() {
        var ys = [Double](repeating: 100, count: 10_000)
        ys[4_321] = 5_000; ys[7_777] = -3
        let kept = SpectrumDecimation.channels(ys, range: 0...9_999, frame: 0...9_999, columns: 100)
        XCTAssertTrue(kept.contains(4_321), "the spike")
        XCTAssertTrue(kept.contains(7_777), "the dip")
        XCTAssertTrue(kept.contains(0) && kept.contains(9_999), "both ends")
        XCTAssertEqual(kept, kept.sorted(), "channel order")
        XCTAssertEqual(Set(kept).count, kept.count, "no channel twice")
        XCTAssertLessThanOrEqual(kept.count, 4 * 100, "at most four per column")
    }

    /// D2: channels are dropped only where there are many more than columns; a spectrum of at most twice the columns is stroked whole.
    /// Mutation: the decimation never drops anything - red.
    func testDecimationDropsChannelsOnlyWhereThereAreFarMoreThanColumns() {
        let ys = (0..<1_000).map(Double.init)
        XCTAssertEqual(SpectrumDecimation.channels(ys, range: 0...999, frame: 0...999, columns: 600), Array(0...999))
        // a ramp: per column only the first and the last are its extremes, so a column of ten keeps two
        let ramp = (0..<10_000).map(Double.init)
        let kept = SpectrumDecimation.channels(ramp, range: 0...9_999, frame: 0...9_999, columns: 100)
        XCTAssertEqual(kept.count, 200)
        XCTAssertEqual(Array(kept.prefix(4)), [0, 99, 100, 199])
    }

    /// D2: a curve that covers only part of the frame (the model, where the fit ran) keeps the frame's columns.
    /// Mutation: the columns counted from `range` instead of `frame` - red.
    func testDecimationColumnsComeFromTheFrameNotTheCurve() {
        var ys = [Double](repeating: 1, count: 10_000)
        ys[5_120] = 9
        // 100 channels per column; the curve starts mid-column (5050) and its first column is 5050...5099
        let kept = SpectrumDecimation.channels(ys, range: 5_050...9_999, frame: 0...9_999, columns: 100)
        XCTAssertEqual(kept.filter { $0 < 5_200 }, [5_050, 5_099, 5_100, 5_120, 5_199])
    }

    /// D2: the memo serves an unchanged array and recomputes for a changed array, a changed number, or another key.
    /// Mutation: the memo always recomputes - red.
    func testMemoServesTheSameArrayAndRecomputesOnChange() {
        var memo = SpectrumDrawMemo()
        let a = [1.0, 2, 3]
        var calls = 0
        func make(_ x: [Double], _ f: Double) -> () -> [Double] { { calls += 1; return x.map { $0 / f } } }
        let r1 = memo.scaled(.data, a, a: 2, compute: make(a, 2))
        let r2 = memo.scaled(.data, a, a: 2, compute: make(a, 2))
        XCTAssertEqual(r1, [0.5, 1, 1.5]); XCTAssertEqual(r2, r1)
        XCTAssertEqual(calls, 1, "the second frame is served")
        _ = memo.scaled(.data, a, a: 4, compute: make(a, 4))
        XCTAssertEqual(calls, 2, "a new divisor")
        let b = [1.0, 2, 4]
        let r3 = memo.scaled(.data, b, a: 4, compute: make(b, 4))
        XCTAssertEqual(calls, 3, "a new array"); XCTAssertEqual(r3, [0.25, 0.5, 1])
        _ = memo.scaled(.model, b, a: 4, compute: make(b, 4))
        XCTAssertEqual(calls, 4, "another key has its own entry")
        XCTAssertEqual(memo.sum(.total, b), 7); XCTAssertEqual(memo.sum(.total, b), 7)
        XCTAssertEqual(memo.computed, 5, "one sum, computed once")
        XCTAssertEqual(memo.sum(.total, a), 6, "a changed array has a new sum")
    }

    /// D2: the residual is kept per (data, model): a changed model recomputes it.
    /// Mutation: the model left out of the key - red.
    func testMemoResidualFollowsTheModel() {
        var memo = SpectrumDrawMemo()
        var calls = 0
        let data = [10.0, 20, 30], m1 = [10.0, 20, 30], m2 = [12.0, 20, 30]
        _ = memo.residual(data: data, model: m1) { calls += 1; return [] }
        _ = memo.residual(data: data, model: m1) { calls += 1; return [] }
        XCTAssertEqual(calls, 1)
        _ = memo.residual(data: data, model: m2) { calls += 1; return [] }
        XCTAssertEqual(calls, 2)
    }

    /// D2: the marker names' layout is a pure value of the viewport and the frame; names that crowd out are reported in it.
    /// Mutation: the in-view filter dropped - red.
    func testMarkerLayoutIsAValueOfTheViewport() {
        var vp = SpectrumViewport(domain: 0...20, minimumSpan: 0.02)
        vp.lo = 1; vp.hi = 3
        let inside = LineMarker(label: "Al K\u{03B1}", energy: 1.487, elementZ: 13, priority: 2)
        let outside = LineMarker(label: "Cu K\u{03B1}", energy: 8.04, elementZ: 29)
        let edge = LineMarker(label: "Al K edge", energy: 1.56, elementZ: nil, kind: .edge)
        let r = SpectrumStripLogic.markerLayout(markers: [inside, outside, edge], viewport: vp, plotLeft: 46, plotWidth: 500)
        XCTAssertEqual(r.placed.map(\.label), ["Al K\u{03B1}"], "in view, not an edge")
        XCTAssertTrue(r.left.isEmpty)
        // five names at one energy: three rows hold three, two are left out and reported
        let crowd = (0..<5).map { LineMarker(label: "Xx\($0) K\u{03B1}", energy: 2.0, elementZ: 30 + $0, priority: 5 - $0) }
        let c = SpectrumStripLogic.markerLayout(markers: crowd, viewport: vp, plotLeft: 46, plotWidth: 500)
        XCTAssertEqual(c.placed.count, MarkerLabelLayout.rows)
        XCTAssertEqual(Set(c.left), ["Xx3 K\u{03B1}", "Xx4 K\u{03B1}"], "the lowest priorities go")
        XCTAssertTrue(SpectrumStripLogic.markerLayout(markers: crowd, viewport: vp, plotLeft: 46, plotWidth: 10).placed.isEmpty, "a collapsed frame places nothing")
    }

    /// D2: the plot's frames (shared by the curves and the hover overlay): none under the floor; the residual strip takes its height.
    /// Mutation: the floor test removed - red.
    func testPlotFramesAreSharedAndHaveAFloor() {
        XCTAssertNil(SpectrumStripView.frames(CGSize(width: 600, height: SpectrumPlotFit.minimumHeight - 1), residual: false))
        guard let withRes = SpectrumStripView.frames(CGSize(width: 600, height: 300), residual: true),
              let noRes = SpectrumStripView.frames(CGSize(width: 600, height: 300), residual: false) else { return XCTFail("frames") }
        XCTAssertLessThan(withRes.main.height, noRes.main.height)
        XCTAssertEqual(withRes.main.minX, noRes.main.minX)
        XCTAssertEqual(noRes.resH, 0)
        XCTAssertNil(SpectrumStripView.frames(CGSize(width: 60, height: 300), residual: false), "a frame under 20 pt wide")
    }

    /// D2: the visible channel range, and none when under two channels are shown.
    /// Mutation: the upper bound rounded down instead of up - red.
    func testVisibleChannels() {
        let s = SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [Double](repeating: 1, count: 1_000), background: [], model: [])
        var vp = SpectrumViewport(domain: s.domain, minimumSpan: 0.02)
        vp.lo = 1.004; vp.hi = 2.001
        XCTAssertEqual(SpectrumStripLogic.channels(series: s, viewport: vp), 100...201)
        vp.lo = 1.0; vp.hi = 1.0
        XCTAssertNil(SpectrumStripLogic.channels(series: s, viewport: vp))
    }
}
