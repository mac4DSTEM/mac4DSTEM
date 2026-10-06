//
//  SpectroscopyRoomR10Tests.swift
//  Lane R10 (Velox-league polish): Auto ID's proposed elements are labelled on the first spectrum in a muted style, and the
//  empty quant panel says to accept them. (The ColorMix-tick change is tested in SpectrumImageOpeningTests.)
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class SpectroscopyRoomR10Tests: XCTestCase {
    private let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1000)

    /// A proposal gets exactly one muted marker, its window's own line, named like a picked one and with no "?".
    /// Mutation: `kind: .proposed` changed to `.line` in `proposedMarkers` - red.
    func testProposalsGetOneMutedMarkerEach() throws {
        let windows = ElementWindows.build(elements: [("Al", nil), ("Cu", nil)], axis: axis, beamEnergyKeV: 200)
        let marks = SpectroscopyRoomController.proposedMarkers(for: windows, axis: axis, beam: 200)
        XCTAssertEqual(Set(marks.map(\.label)), ["Al K\u{03B1}", "Cu K\u{03B1}"])
        XCTAssertEqual(marks.count, windows.count, "one marker per proposed element")
        XCTAssertTrue(marks.allSatisfy { $0.kind == .proposed }, "muted, not the element's colour")
        XCTAssertTrue(marks.allSatisfy { !$0.label.hasSuffix("?") }, "no question mark: that is a suspect's")
        XCTAssertEqual(marks.first?.elementZ, 13)
    }

    /// A picked element's markers are coloured lines and its family satellites stay; the proposal seam never returns them.
    /// Mutation: `l.id == w.id` dropped in `proposedMarkers` (every line of the family) - red.
    func testProposalsDrawTheMainLineOnly() throws {
        let windows = ElementWindows.build(elements: [("Al", nil)], axis: axis, beamEnergyKeV: 200)
        let picked = SpectroscopyRoomController.markers(for: windows, axis: axis, beam: 200, quantified: ["Al"])
        XCTAssertTrue(picked.allSatisfy { $0.kind == .line })
        let proposed = SpectroscopyRoomController.proposedMarkers(for: windows, axis: axis, beam: 200)
        XCTAssertEqual(proposed.count, 1)
        XCTAssertEqual(proposed.first?.label, "Al K\u{03B1}")
        // a chosen L family: the marker is the window's own line, not the element's first listed one
        let cuL = ElementWindows.build(elements: [("Cu", .L)], axis: axis, beamEnergyKeV: 200)
        XCTAssertEqual(SpectroscopyRoomController.proposedMarkers(for: cuL, axis: axis, beam: 200).map(\.label), ["Cu L\u{03B1}"])
    }

    /// The quant panel's empty sentence: proposals present means "accept", else the plain pick sentence.
    /// Mutation: the `hasProposals` branch inverted - red.
    func testEmptyQuantWording() {
        XCTAssertEqual(QuantifyPresentation.emptyText(isLive: true, hasProposals: true),
                       "Accept the proposed elements or pick in the periodic table to see their net counts.")
        XCTAssertEqual(QuantifyPresentation.emptyText(isLive: true, hasProposals: false),
                       "Pick elements in the periodic table to see their window net counts here.")
        XCTAssertEqual(QuantifyPresentation.emptyText(isLive: false, hasProposals: true), "No results yet.")
    }
}
