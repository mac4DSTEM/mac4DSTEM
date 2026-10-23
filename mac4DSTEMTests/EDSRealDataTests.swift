//
//  EDSRealDataTests.swift
//  The EDS room on the owner's Velox STEM-EDX files (data/stem-edx, read-only, never copied): Auto ID's picks as macTEM 1.0's room
//  makes them on the same files (1339 and 1840: Mg, Al, Si; 1456: Si, Ni, Ge, Pt), and Quantify fits. Heavy, opt-in:
//      ../tools/memcap.sh --gb 12 -- env TEST_RUNNER_MAC4DSTEM_EDS_REAL=1 MAC4DSTEM_UNIT_ONLY=EDSRealDataTests tools/run-tests.sh unit
//  `MACEM_DATA` names the data folder (default ../data).
//

@testable import DSTEMSession
import XCTest
@testable import mac4DSTEM

@MainActor
final class EDSRealDataTests: XCTestCase {
    private var keep: [AppState] = []
    private static let data = ProcessInfo.processInfo.environment["MACEM_DATA"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data")

    private func waitFor(_ what: String, timeout: TimeInterval = 300, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testTheThreeVeloxFilesPickWhatMacTEMPicksAndQuantify() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAC4DSTEM_EDS_REAL"] == "1", "heavy real-data run: set MAC4DSTEM_EDS_REAL=1 (command in this file's header)")
        let files = [("SI HAADF 1339 65000 x 20260508.emd", ["Mg", "Al", "Si"]), ("SI HAADF 1840 23000 x 20260506.emd", ["Mg", "Al", "Si"]),
                     ("SI HAADF 1456 77000 x 20260420.emd", ["Si", "Ni", "Ge", "Pt"])]
        for (name, expected) in files {
            let url = Self.data.appendingPathComponent("stem-edx/\(name)")
            guard FileManager.default.fileExists(atPath: url.path) else { XCTFail("\(name) not found under \(Self.data.path)"); continue }
            let state = AppState(); keep.append(state)
            await state.openFileAsync(url: url)
            try await waitFor("\(name): Auto ID on open") { state.edx.hasImage && !state.edx.isBusy && state.edx.autoID != .idle && state.edx.autoID != .running }
            let picks = state.edx.picks.map(\.symbol)
            print("EDS-REAL \(name): picks \(picks.joined(separator: " "))")
            XCTAssertTrue(Set(expected).isSubset(of: Set(picks)), "\(name): picks \(picks), expected at least \(expected)")
            state.navigation.workspaceArea = .spectroscopy
            await state.runPrimaryWorkspaceTask()
            XCTAssertNotNil(state.edx.fit, "\(name): \(state.edx.fitFailure ?? "no fit")")
            state.windowClosed()
        }
    }
}
