// StaleTaskJourney: a real .h5 file opened at launch (`--open`), DPC run on it, then the origin calibrated in Prepare: the DPC task row
// shows its stale glyph, found by its own identifier (`task.DPC.stale`). The fixture is opened in place; the Debug app reads it
// through its read-only exception, so nothing it could write lands in the repository. Fixture: Fixtures/disk-scan.h5 (make_disk_scan.py).

import XCTest

final class StaleTaskJourney: Journey {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/disk-scan.h5")

    /// The fixture itself, opened in place (#356). The runner is sandboxed: a copy in its temporary folder sits in its own container,
    /// which the app may not read ("can't be read: Operation not permitted"). The Debug app reads the repository through its read-only
    /// exception for "/", so it can't write anything beside the fixture either.
    private func fixturePath() -> String { Self.fixture.path }

    func testDPCReadsStaleAfterTheOriginIsCalibrated() throws {
        let path = fixturePath()
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
