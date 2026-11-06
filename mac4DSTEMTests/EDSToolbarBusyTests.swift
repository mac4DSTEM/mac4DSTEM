//
//  EDSToolbarBusyTests.swift
//  The toolbar's centre says busy while the EDS room works. The fit, its unlisted-line check, Auto ID and the composition maps run in
//  `EDXSession`, not `OperationCenter`; before 2026-11-05 the toolbar read only `OperationCenter` and said idle mid-Quantify, so
//  EDSJourney's "back to idle" wait passed while Results CSV was still disabled (the Velox 1024 x 1024 file's check takes seconds).
//

import XCTest
import ShellLayout
@testable import mac4DSTEM

@MainActor
final class EDSToolbarBusyTests: XCTestCase {
    private var keep: [AppState] = []

    private func isBusy(_ state: ToolbarDisplayState?) -> String? {
        if case let .busy(operation, _, _) = state { return operation }
        return nil
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 60, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// A spectrum-only window in the EDS room: busy from the moment Quantify starts until the fit and its check have landed, idle
    /// after. Mutation: `toolbarDisplay` ignoring `edsBusyOperation` (the old code) - red on the first busy assertion.
    func testQuantifyKeepsTheToolbarBusyUntilTheCheckLands() async throws {
        let loaded = try SpectroQuantFixtures.image()
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(loaded)
        state.navigation.workspaceArea = .spectroscopy
        try await waitFor("the open's Auto ID") { !state.edx.isBusy && state.edx.autoID != .idle }
        for s in ["Al", "Mg", "Si", "Cu"] where !state.edx.picks.contains(where: { $0.symbol == s }) { state.edx.toggle(s) }
        for s in ["Al", "Mg", "Si", "Cu"] { state.edx.setRole(.quantify, of: s) }
        if loaded.metadata.beamEnergyKeV == nil { state.edx.changeMethod { $0.beamEnergyKeV = 200 } }
        await state.edx.settled()
        XCTAssertNil(isBusy(state.toolbarDisplay), "at rest before Quantify")
        XCTAssertFalse(state.isBusy, "the operation center runs nothing: only the room is busy")

        let task = try XCTUnwrap(state.edx.quantify())
        XCTAssertEqual(isBusy(state.toolbarDisplay), "Quantifying…", "the fit is running")
        await task.value
        if state.edx.isChecking {
            XCTAssertEqual(isBusy(state.toolbarDisplay), "Checking for unlisted lines…", "the check holds Results CSV")
        }
        await state.edx.settled()
        XCTAssertNotNil(state.edx.fit)
        XCTAssertNil(isBusy(state.toolbarDisplay), "idle once the fit and its check have landed")
    }

    /// The names follow the order a Quantify sets the flags; nil at rest.
    func testTheBusyNameIsTheFirstFlagSet() {
        XCTAssertNil(AppState.edsBusyOperation(opening: false, fitting: false, checking: false, identifying: false, mapping: false, refreshing: false))
        XCTAssertEqual(AppState.edsBusyOperation(opening: false, fitting: true, checking: false, identifying: false, mapping: true, refreshing: true),
                       "Quantifying…")
        XCTAssertEqual(AppState.edsBusyOperation(opening: false, fitting: false, checking: true, identifying: false, mapping: false, refreshing: false),
                       "Checking for unlisted lines…")
    }
}
