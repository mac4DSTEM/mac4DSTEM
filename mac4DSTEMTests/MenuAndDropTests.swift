//
//  MenuAndDropTests.swift
//  UI audit 2026-10-14, F: File > Open with Options… and Open Recent reach a window that does not exist yet through
//  the relay, and a file dropped on a window asks for its first file URL. The menu items themselves are SwiftUI
//  `Commands` (checked on screen in the drive); what is held here is the logic behind them.
//
//  Mutations these were broken against (each must turn a test red):
//   1. `run(.openWithOptions)` routes to `requestOpenDataset` (plain open)        -> testOpenWithOptionsIsTheWindowsOptionsRequest
//   2. `run(.openRecent)` does nothing                                             -> testOpenRecentOpensThatRecent
//   3. `DropToOpen.dataset(in:)` returns the last URL, or a non-file URL           -> testADropAsksForItsFirstFile
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class MenuAndDropTests: XCTestCase {

    func testOpenWithOptionsIsTheWindowsOptionsRequest() {
        let state = AppState()
        XCTAssertFalse(state.configureOnOpen)
        let before = state.openDatasetRequest
        MenuActionRelay.run(.openWithOptions, in: state)
        XCTAssertEqual(state.openDatasetRequest, before &+ 1, "the open-panel request ContentView observes")
        XCTAssertTrue(state.configureOnOpen, "and this one stops at the configurator")
    }

    func testTheRelayCarriesTheNewActionsToTheWindowThatOpens() {
        let relay = MenuActionRelay()
        relay.request(.openWithOptions)
        XCTAssertEqual(relay.take(), .openWithOptions)
        let recent = RecentDataset(id: "/data/a.h5", displayName: "a.h5", bookmark: Data(), lastOpened: Date(timeIntervalSince1970: 0))
        relay.request(.openRecent(recent))
        XCTAssertEqual(relay.take(), .openRecent(recent))
        XCTAssertNil(relay.take())
    }

    /// An entry whose bookmark cannot be resolved takes the same road as a click on the Welcome list: said once, and
    /// dropped from Recents. (A bookmark that does resolve opens the file; that path is `openFile`'s own.)
    func testOpenRecentOpensThatRecent() throws {
        let recent = RecentDataset(id: "/gone/a.h5", displayName: "a.h5", bookmark: Data([1, 2, 3]),
                                   lastOpened: Date(timeIntervalSince1970: 0))
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults),
                             recents: RecentDatasets(entries: [recent], persist: { _ in }))
        state.recoveryRecord = nil   // never touch the host's real recovery record
        MenuActionRelay.run(.openRecent(recent), in: state)
        XCTAssertTrue(state.errorMessage?.contains("a.h5") == true,
                      "the entry was asked for: \(state.errorMessage ?? "nil")")
        XCTAssertTrue(state.recents.entries.isEmpty, "a dead entry leaves the list, as from the Welcome screen")
    }

    func testADropAsksForItsFirstFile() {
        let a = URL(fileURLWithPath: "/data/a.h5"), b = URL(fileURLWithPath: "/data/b.h5")
        XCTAssertEqual(DropToOpen.dataset(in: [a, b]), a, "one dataset per window: the first")
        XCTAssertEqual(DropToOpen.dataset(in: [URL(string: "https://example.com/a.h5")!, b]), b,
                       "a web link is not a dataset")
        XCTAssertNil(DropToOpen.dataset(in: [URL(string: "https://example.com/a.h5")!]))
        XCTAssertNil(DropToOpen.dataset(in: []))
    }
}
