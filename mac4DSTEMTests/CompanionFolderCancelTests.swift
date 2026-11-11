//
//  CompanionFolderCancelTests.swift
//  The user's own Cancel at the folder prompt (mac4DSTEM#120 drive, 2026-11-11) showed "Something went wrong". A Cancel is
//  not a failure: it is said in the status line and raises no alert; a real refusal still does.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class CompanionFolderCancelTests: XCTestCase {

    /// Mutation: drop the `Declined` branch in `AppState.present` - red (the alert's message is set).
    func testCancelAtTheFolderPromptRaisesNoAlert() {
        let state = AppState()
        state.present(CompanionFolderAccess.Declined(message: "Not opened: default17.mib is one of 65 files of a Merlin acquisition."))
        XCTAssertNil(state.errorMessage, "a Cancel is not an error")
        XCTAssertEqual(state.statusText, "Not opened: default17.mib is one of 65 files of a Merlin acquisition.")
        state.present(SimpleError("The folder chosen is not the one that holds default17.mib."))
        XCTAssertNotNil(state.errorMessage, "a real refusal still reaches the alert")
    }
}
