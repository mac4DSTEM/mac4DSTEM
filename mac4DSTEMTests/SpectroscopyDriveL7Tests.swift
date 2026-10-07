//
//  SpectroscopyDriveL7Tests.swift
//  Lane L7 (the owner's drive findings, 2026-10-07): the spectrum's weight and colour, and zoom that feels natural. Every test
//  names the mutation it catches; each was broken once and seen red (the lane report lists them).
//

import XCTest
import SwiftUI
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class SpectroscopyDriveL7Tests: XCTestCase {
    private let de = Locale(identifier: "de_DE")
    private let domain = 0.0...20.0

    // MARK: zoom factor in the x-axis gutter

    /// Right is in, left is out, none is none; the two directions are inverses. Mutation: the sign flipped (left = in), or the
    /// exponent made linear, red.
    func testZoomFactorRightIsInLeftIsOut() {
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: 0), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(SpectrumInteraction.zoomFactor(dx: 40), 1)
        XCTAssertLessThan(SpectrumInteraction.zoomFactor(dx: -40), 1)
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: SpectrumInteraction.pointsPerDoubling), 2, accuracy: 1e-12, "one doubling's drag doubles")
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: 37) * SpectrumInteraction.zoomFactor(dx: -37), 1, accuracy: 1e-12)
    }

    /// A huge drag stays inside the factor range both ways; a non-finite one is no drag. Mutation: the clamp removed (inf, 2^25), red.
    func testZoomFactorClamps() {
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: 100_000), SpectrumInteraction.factorRange.upperBound)
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: -100_000), SpectrumInteraction.factorRange.lowerBound)
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: .nan), 1)
        XCTAssertEqual(SpectrumInteraction.zoomFactor(dx: .infinity), 1)
    }

    /// The factor applied to the viewport keeps the energy under the start and stays inside the domain (zoom out from the full
    /// range changes nothing). Mutation: the factor inverted at the call (out zooms in) - the second assertion goes red.
    func testGutterZoomAboutTheStartEnergy() {
        var vp = SpectrumViewport(domain: domain, minimumSpan: 0.04)
        vp.lo = 4; vp.hi = 8
        let start = vp
        let anchor = 0.25, e0 = start.energy(atFraction: anchor)
        vp.zoom(factor: SpectrumInteraction.zoomFactor(dx: 80), anchor: anchor)       // right: in
        XCTAssertEqual(vp.span, 2, accuracy: 1e-9)
        XCTAssertEqual(vp.energy(atFraction: anchor), e0, accuracy: 1e-9)
        var out = start
        out.zoom(factor: SpectrumInteraction.zoomFactor(dx: -80), anchor: anchor)      // left: out
        XCTAssertEqual(out.span, 8, accuracy: 1e-9)
        var full = SpectrumViewport(domain: domain, minimumSpan: 0.04)
        full.zoom(factor: SpectrumInteraction.zoomFactor(dx: -300), anchor: 0.5)
        XCTAssertEqual(full.lo, 0); XCTAssertEqual(full.hi, 20, "out of the full range stays the full range")
    }

    // MARK: what a drag does

    /// Mode by where the drag began. Mutations: the gutter test dropped (a gutter drag pans), ⌘ and ⌥ swapped, or the counts
    /// gutter losing to the x row at the corner, red.
    func testDragModeByStartAndModifier() {
        func mode(_ opt: Bool = false, _ cmd: Bool = false, x: CGFloat = 200, y: CGFloat = 100) -> SpectrumDragMode {
            SpectrumInteraction.dragMode(optionHeld: opt, commandHeld: cmd, startX: x, startY: y, plotLeft: 46, gutterTop: 280)
        }
        XCTAssertEqual(mode(), .pan)
        XCTAssertEqual(mode(true), .range)
        XCTAssertEqual(mode(false, true), .band)
        XCTAssertEqual(mode(true, true), .band, "both held: the zoom box")
        XCTAssertEqual(mode(y: 285), .zoomX, "the keV row")
        XCTAssertEqual(mode(true, y: 285), .zoomX)
        XCTAssertEqual(mode(false, true, y: 285), .zoomX)
        XCTAssertEqual(mode(y: 279.9), .pan, "just above the row is the plot")
        XCTAssertEqual(mode(x: 10), .stretchY)
        XCTAssertEqual(mode(false, true, x: 10, y: 285), .stretchY, "the counts gutter wins at the corner, as before")
    }

    // MARK: rubber band and "Zoom to range"

    /// A box's span becomes the window; either direction of drag is the same; the centre is kept. Mutation: from/to not ordered
    /// (a right-to-left box gives a negative span), red.
    func testBandWindowIsTheBoxSpan() throws {
        let a = try XCTUnwrap(SpectrumInteraction.bandWindow(from: 4, to: 6, domain: domain, channel: 0.01))
        XCTAssertEqual(a.lowerBound, 4, accuracy: 1e-12); XCTAssertEqual(a.upperBound, 6, accuracy: 1e-12)
        let b = try XCTUnwrap(SpectrumInteraction.bandWindow(from: 6, to: 4, domain: domain, channel: 0.01))
        XCTAssertEqual(b, a)
    }

    /// A box narrower than 10 channels is widened to 10 about its centre; at the domain's edge it shifts inside; a box wider than
    /// the domain is the domain. Mutation: the minimum 2 channels (the viewport's own) or the shift dropped, red.
    func testBandWindowMinimumTenChannelsAndTheDomain() throws {
        let w = try XCTUnwrap(SpectrumInteraction.bandWindow(from: 5.00, to: 5.02, domain: domain, channel: 0.02))
        XCTAssertEqual(w.upperBound - w.lowerBound, 0.2, accuracy: 1e-12, "10 channels of 20 eV")
        XCTAssertEqual((w.lowerBound + w.upperBound) / 2, 5.01, accuracy: 1e-12)
        let edge = try XCTUnwrap(SpectrumInteraction.bandWindow(from: 0.0, to: 0.02, domain: domain, channel: 0.02))
        XCTAssertEqual(edge.lowerBound, 0, accuracy: 1e-12); XCTAssertEqual(edge.upperBound - edge.lowerBound, 0.2, accuracy: 1e-12)
        let top = try XCTUnwrap(SpectrumInteraction.bandWindow(from: 19.99, to: 20.0, domain: domain, channel: 0.02))
        XCTAssertEqual(top.upperBound, 20, accuracy: 1e-12); XCTAssertEqual(top.upperBound - top.lowerBound, 0.2, accuracy: 1e-12)
        let all = try XCTUnwrap(SpectrumInteraction.bandWindow(from: -5, to: 30, domain: domain, channel: 0.02))
        XCTAssertEqual(all, domain)
    }

    /// Nothing drawn (equal energies) or a broken input is no zoom. Mutation: the guard dropped (a click zooms), red.
    func testBandWindowNilWhenNothingWasDrawn() {
        XCTAssertNil(SpectrumInteraction.bandWindow(from: 5, to: 5, domain: domain, channel: 0.02))
        XCTAssertNil(SpectrumInteraction.bandWindow(from: .nan, to: 5, domain: domain, channel: 0.02))
        XCTAssertNil(SpectrumInteraction.bandWindow(from: 4, to: 5, domain: domain, channel: 0))
    }

    /// The menu's first row names the range with the readout's two decimals, German commas, low to high whatever the drag's
    /// direction. Mutation: from/to unordered, or three decimals, red.
    func testZoomToRangeTitle() {
        XCTAssertEqual(SpectrumInteraction.zoomToRangeTitle(from: 1.2, to: 1.86, locale: de), "Zoom to 1,20\u{2013}1,86 keV")
        XCTAssertEqual(SpectrumInteraction.zoomToRangeTitle(from: 1.86, to: 1.2, locale: de), "Zoom to 1,20\u{2013}1,86 keV")
        XCTAssertEqual(SpectrumInteraction.zoomToRangeTitle(from: 1.2, to: 1.86, locale: Locale(identifier: "en_US")), "Zoom to 1.20\u{2013}1.86 keV")
    }

    // MARK: colour and weight

    /// A region is shown only on a live image with a region other than the whole map (id 0) selected. Mutations: `isLive` ignored
    /// (the fixture's region 2 shows as a region), id 0 treated as a region, a nil selection as a region, red.
    func testCurveRoleRegionVersusWholeMap() {
        XCTAssertEqual(SpectrumInteraction.curveRole(isLive: true, selectedRegion: 2), .region)
        XCTAssertEqual(SpectrumInteraction.curveRole(isLive: true, selectedRegion: 0), .wholeMap)
        XCTAssertEqual(SpectrumInteraction.curveRole(isLive: true, selectedRegion: nil), .wholeMap)
        XCTAssertEqual(SpectrumInteraction.curveRole(isLive: false, selectedRegion: 2), .wholeMap)
        XCTAssertEqual(SpectroscopyRoomModel.fixture.selectedRegion, 2)
        XCTAssertFalse(SpectroscopyRoomModel.fixture.isLive)
    }

    /// The region's curve is the seam's live-region colour (the map outline's), the whole map's is not; a pin keeps its own tint
    /// (the strip draws it from `PinnedRegion.tint`, never from this helper). Mutation: the roles' colours swapped, red.
    func testCurveColourRegionIsTheLiveRegionColour() {
        XCTAssertEqual(SpectrumInteraction.curveColor(.region), SpectroscopyRoomModel.liveRegionColor)
        XCTAssertNotEqual(SpectrumInteraction.curveColor(.wholeMap), SpectroscopyRoomModel.liveRegionColor)
        XCTAssertEqual(SpectrumInteraction.curveColor(.wholeMap), Color.primary.opacity(0.85))
    }

    /// The owner's weights: the spectrum and the model 1,6 pt, pins and the background 1,4, a marker 1,2 (2,2 highlighted), names
    /// 11 pt. Mutation: any constant reverted to the old thin value (0,9 / 1 / 0,8 / 1,8), red.
    func testWeights() {
        typealias W = SpectrumInteraction.Width
        XCTAssertEqual(W.spectrum, 1.6); XCTAssertEqual(W.model, 1.6)
        XCTAssertEqual(W.pin, 1.4); XCTAssertEqual(W.background, 1.4)
        XCTAssertEqual(W.marker, 1.2); XCTAssertEqual(W.markerHighlighted, 2.2)
        XCTAssertEqual(W.markerLabel, 11)
        let cu = LineMarker(label: "Cu Kα", energy: 8.05, elementZ: 29)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(cu, highlightedZ: 29), W.markerHighlighted)
        XCTAssertEqual(SpectrumStripLogic.lineWidth(cu, highlightedZ: nil), W.marker)
    }

    /// The hover readout's energy follows the region's colour only when a region is shown. Mutation: always the label colour, or
    /// always the region's, red.
    func testReadoutEnergyColourFollowsTheRole() {
        XCTAssertEqual(SpectrumInteraction.readoutEnergyColor(.region), SpectroscopyRoomModel.liveRegionColor)
        XCTAssertEqual(SpectrumInteraction.readoutEnergyColor(.wholeMap), Color.primary)
    }
}
