//
//  EDSFourDEDXFileTests.swift
//  The EDS room on mac4DSTEM's own 4D-STEM + EDS input: the simulated GMS joint file References/demo-edx/AlMgSi_4D_EDX.dm4
//  (a 64 x 48 scan, 128 x 128 diffraction patterns and an EDS spectrum image in one experiment; truth_edx.json beside it). Skipped
//  where the file is not generated (CI). Headless: no window.
//

import DSTEMCore
@testable import DSTEMSession
import SpectroCore
import SpectroEDX
import XCTest
@testable import mac4DSTEM

@MainActor
final class EDSFourDEDXFileTests: XCTestCase {
    private var keep: [AppState] = []
    private static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4")

    private func waitFor(_ what: String, timeout: TimeInterval = 120, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// The joint file opens as the 4D cube with its EDS spectrum image attached to the EDS room on the same scan (64 x 48, not
    /// swapped), with the identity registration stated; Auto ID on open picks the matrix's elements (Al and Si on the whole map: the
    /// simulated Mg and Cu sit in the precipitates and fall under the kit's bar on the sum of 105 105 counts, measured 2026-10-23);
    /// Quantify on the whole map fits and records the step. Mutations: the attach not binding the EDS session - red at once;
    /// nx and ny swapped - red; no registration - red.
    func testTheJointFileOpensTheCubeAndTheEDSRoomOnOneScan() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.file.path), "References/demo-edx not generated on this machine")
        let state = AppState(); keep.append(state)
        await state.openFileAsync(url: Self.file)
        try await waitFor("the cube and the spectrum image") { state.hasDataset && state.hasSpectrumImage && state.edx.hasImage }
        let source = try XCTUnwrap(state.edx.source)
        XCTAssertEqual(source.nx, 64); XCTAssertEqual(source.ny, 48)
        XCTAssertNotNil(state.spectroscopy.registration, "the joint attach states the identity registration")
        try await waitFor("Auto ID on open") { !state.edx.isBusy && state.edx.autoID != .idle && state.edx.autoID != .running }
        let picks = Set(state.edx.picks.map(\.symbol))
        XCTAssertTrue(["Al", "Si"].allSatisfy(picks.contains), "Auto ID picks \(picks.sorted())")
        for s in ["Mg", "Cu"] where !picks.contains(s) { state.edx.toggle(s) }   // the simulated precipitate elements, as a person adds them
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        let fit = try XCTUnwrap(state.edx.fit, state.edx.fitFailure ?? "no fit")
        XCTAssertEqual(Set(fit.rows.map(\.element)), ["Al", "Si", "Mg", "Cu"])
        XCTAssertEqual(state.replay.lineage.nodes.last { $0.kind == QuantificationStep.kind }?.parameters["region_kind"], "wholeMap")
    }
}
