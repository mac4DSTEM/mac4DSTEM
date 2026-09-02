//
//  SessionReplayAppStateTests.swift
//  Pins the CALL SITES of v2 S5 — the half the file-level tests cannot see.
//  Gate B-lite F8 measured that every S5 wiring line could be deleted with
//  the suite staying green, the exact gap S1's locator tests once had; these
//  tests reach the wiring through a real AppState on the demo fixture.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class SessionReplayAppStateTests: XCTestCase {

    func testTheAutomaticPassOnOpenRecordsNothing() async {
        // Opening runs the initial virtual-detector pass with DEFAULT
        // parameters. Recording it would let merely opening a colleague's
        // file overwrite their recorded aperture with defaults on the next
        // save (Gate B-lite F1) — the load-in-flight guard suppresses it.
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertNotNil(state.resultImage,
                        "The initial analysis must have run for this test to mean anything")
        XCTAssertTrue(state.replay.record.isEmpty,
                      "Merely opening a file must never mutate its recipe")
    }

    func testAnExplicitRunRecordsTheSessionsOwnParameters() async {
        let state = AppState()
        await state.openDemoFixture()
        state.aperture.inner = 3
        state.aperture.outer = 9
        await state.runVirtualDetector()
        XCTAssertEqual(state.replay.record.steps.map(\.kind), ["virtual_detector"])
        let step = state.replay.record.steps.first
        XCTAssertEqual(step?.parameters["inner"], "3.0",
                       "The step must carry the aperture the run actually used")
        XCTAssertEqual(step?.parameters["outer"], "9.0")
    }

    func testACalibrationSaveCarriesTheRecipeIntoTheSidecar() async throws {
        // End-to-end through the app's own save path: the wiring line in
        // ResultExport that threads `replay.recordForSaving` is exactly the
        // kind of defaulted argument whose deletion no writer-level test can
        // see (F8).
        //
        // A suite-private bookmark store (v2 S7): this save persists a grant
        // keyed by the demo's constant path, and through the shared
        // `UserDefaults` it leaked the sidecar — recipe and all — into every
        // concurrently running demo-opening test (`AppState.init`'s note).
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        await state.openDemoFixture()
        await state.runVirtualDetector()
        XCTAssertFalse(state.replay.record.isEmpty)

        let descriptor = try XCTUnwrap(state.descriptor)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReplayAppStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let url = workDirectory.appendingPathComponent("demo.mac4dstem.h5")
        // Pre-adopting the grant is what keeps the save panel out of a test.
        state.sessionSidecar.adopt(url, for: descriptor)

        state.saveCalibrationToSessionSidecar()
        // Wait for the app's OWN follow-up inventory read to publish, not
        // merely for the file to exist: the bundled HDF5 is Threadsafety: OFF
        // (the standing concurrent-use crash in docs/open-items.md), so this
        // test reading the file while the app's detached inventory task still
        // has it open is exactly that crash — it fired here once, in the full
        // suite's timing. `sessionInventory.hasCalibration` flips only after
        // the app's reader is done with the file.
        for _ in 0..<100 where !state.sessionInventory.hasCalibration {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(state.sessionInventory.hasCalibration,
                      "The calibration save never completed")

        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        XCTAssertEqual(snapshot.replayRecord?.steps.map(\.kind), ["virtual_detector"],
                       "The session's recipe must travel with the calibration save")
    }
}
