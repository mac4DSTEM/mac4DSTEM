// StaleTaskJourney: a real .h5 file opened at launch (`--open`), DPC run on it, then the origin calibrated in Prepare: the DPC task row
// shows its stale glyph, found by its own identifier (`task.DPC.stale`). The file is a copy in the temporary folder, never the fixture
// itself, so nothing the app writes beside it lands in the repository. Fixture: Fixtures/disk-scan.h5 (Fixtures/make_disk_scan.py).

import XCTest

final class StaleTaskJourney: Journey {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/disk-scan.h5")

    /// A fresh copy of the fixture in its own temporary folder.
    private func copyOfFixture() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stale-task-journey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("disk-scan.h5")
        try FileManager.default.copyItem(at: Self.fixture, to: copy)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return copy.path
    }

    func testDPCReadsStaleAfterTheOriginIsCalibrated() throws {
        let path = try copyOfFixture()
        step("open disk-scan.h5 at launch") {
            launch(arguments: ["--open", path])
            waitForLoadingToEnd()
            wait(for: "workspace.reconstruct", timeout: 30)
        }
        step("run DPC") {
            wait(for: "workspace.reconstruct").click()
            wait(for: "task.DPC").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
            wait(for: "result.viewer", timeout: 30)
            XCTAssertFalse(element("task.DPC.stale").exists, "DPC reads stale right after it ran")
        }
        step("calibrate the origin in Prepare") {
            wait(for: "workspace.prepare").click()
            wait(for: "calibration.action.originProbe", timeout: 30).click()
            waitGone("toolbar.display.busy", timeout: 90)
        }
        step("the DPC row shows its stale glyph") {
            wait(for: "workspace.reconstruct").click()
            wait(for: "task.DPC.stale", timeout: 30)
        }
    }
}
