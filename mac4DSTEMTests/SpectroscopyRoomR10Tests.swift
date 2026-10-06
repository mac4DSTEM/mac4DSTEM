//
//  SpectroscopyRoomR10Tests.swift
//  Lane R10 (Velox-league polish): the empty Results section's sentence. (The ColorMix-tick change is tested in
//  SpectrumImageOpeningTests; Auto ID's muted proposal markers are gone, spec 2 / ADR 057.)
//  Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class SpectroscopyRoomR10Tests: XCTestCase {
    /// The Results section's empty sentence: the plain pick sentence once the room is live.
    /// Mutation: the `isLive` branch inverted - red.
    func testEmptyQuantWording() {
        XCTAssertEqual(QuantifyPresentation.emptyText(isLive: true), "Pick elements in the periodic table to see their window net counts here.")
        XCTAssertEqual(QuantifyPresentation.emptyText(isLive: false), "No results yet.")
    }
}
