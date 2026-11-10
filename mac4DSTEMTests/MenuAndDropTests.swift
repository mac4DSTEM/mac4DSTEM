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

    /// #163: a Finder open fills the empty window. A window with a document, or one already opening a file,
    /// declines it, and SwiftUI makes a new window for it.
    func testOnlyAnEmptyWindowTakesAFinderOpen() {
        XCTAssertEqual(ExternalOpen.patterns(holdsDocument: false, isOpening: false), ["*"])
        XCTAssertEqual(ExternalOpen.patterns(holdsDocument: true, isOpening: false), [])
        XCTAssertEqual(ExternalOpen.patterns(holdsDocument: false, isOpening: true), [])
        let empty = AppState()
        XCTAssertFalse(empty.hasDocument, "a new window holds nothing, so it is the one that takes the open")
    }

    /// Drive 2026-11-11, check 3: the file a window holds, opened again from Finder, goes to that window (which
    /// comes forward) and not to a new window that refuses it. Any other file is still declined.
    func testTheWindowHoldingAFileTakesThatFileAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let held = folder.appendingPathComponent("scan a.h5")
        let other = folder.appendingPathComponent("other.h5")
        try Data([0]).write(to: held)
        try Data([0]).write(to: other)

        let patterns = ExternalOpen.patterns(holdsDocument: true, isOpening: false, heldPath: held.path)
        XCTAssertTrue(patterns.contains(held.absoluteString), "the URL Finder sends for the held file, spaces escaped")
        XCTAssertFalse(patterns.contains("*"), "a window with a dataset takes no other file")
        XCTAssertFalse(patterns.contains { other.absoluteString.contains($0) }, "the other file matches none of them")
        XCTAssertEqual(ExternalOpen.patterns(holdsDocument: true, isOpening: true, heldPath: held.path), [],
                       "nothing while an open is running")

        XCTAssertTrue(ExternalOpen.isHeld(held, heldPath: held.path))
        XCTAssertFalse(ExternalOpen.isHeld(other, heldPath: held.path))
        XCTAssertFalse(ExternalOpen.isHeld(held, heldPath: nil))
    }
}
