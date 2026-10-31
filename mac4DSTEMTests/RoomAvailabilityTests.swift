//
//  RoomAvailabilityTests.swift
//  ⌘6 with a 4D cube and no spectrum image opened an empty Spectroscopy room: nothing in the room opens a spectrum image.
//  The room is unavailable then (the Go to item disabled, the sidebar row withheld), as macTEM's RoomAvailability has it.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class RoomAvailabilityTests: XCTestCase {
    func testSpectroscopyNeedsASpectrumImage() {
        XCTAssertFalse(WorkspaceArea.spectroscopy.isAvailable(hasFourDCube: true, hasSpectrumImage: false),
                       "a 4D cube alone leaves Spectroscopy empty")
        XCTAssertTrue(WorkspaceArea.spectroscopy.isAvailable(hasFourDCube: true, hasSpectrumImage: true))
        XCTAssertTrue(WorkspaceArea.spectroscopy.isAvailable(hasFourDCube: false, hasSpectrumImage: true))
        XCTAssertFalse(WorkspaceArea.spectroscopy.isAvailable(hasFourDCube: false, hasSpectrumImage: false))
    }

    func testTheOtherRoomsAreUnchanged() {
        for area in WorkspaceArea.allCases where area != .spectroscopy {
            XCTAssertTrue(area.isAvailable(hasFourDCube: true, hasSpectrumImage: false), "\(area) with a 4D cube")
            XCTAssertFalse(area.isAvailable(hasFourDCube: false, hasSpectrumImage: false), "\(area) with nothing open")
            XCTAssertEqual(area.isAvailable(hasFourDCube: false, hasSpectrumImage: true), !area.needsFourDCube,
                           "\(area) in a spectrum-only window")
        }
    }

    /// The window: the demo cube open, no spectrum image. The Go to item and the sidebar row both say no.
    func testAWindowWithACubeAndNoSpectrumImageWithholdsSpectroscopy() async {
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertTrue(state.hasDataset, "precondition: the demo cube is open")
        XCTAssertFalse(state.hasSpectrumImage, "precondition: no spectrum image")
        XCTAssertFalse(state.isWorkspaceAvailable(.spectroscopy))
        XCTAssertTrue(state.isWorkspaceWithheld(.spectroscopy))
        XCTAssertFalse(state.isWorkspaceWithheld(.image), "the 4D rooms stay open")
        XCTAssertFalse(state.isWorkspaceWithheld(.results))
    }

    /// With nothing open the sidebar's rooms stay selectable, as before.
    func testAnEmptyWindowWithholdsNothing() {
        let state = AppState()
        for area in WorkspaceArea.allCases { XCTAssertFalse(state.isWorkspaceWithheld(area), "\(area)") }
    }
}
