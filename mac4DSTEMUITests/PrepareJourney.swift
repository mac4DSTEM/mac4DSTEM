// PrepareJourney: Prepare, calibrate the origin and read the probe radius (process/ui-testing-2026-10-21.md §3).

import XCTest

final class PrepareJourney: Journey {
    func testCalibrateOriginKeepsTheProbeRadiusANumber() {
        step("launch with the uncalibrated demo") { launch(arguments: ["--demo-fixture", "--demo-uncalibrated"]) }
        step("open Prepare") {
            waitForLoadingToEnd()
            wait(for: "workspace.prepare").click()
            wait(for: "calibration.readiness")
        }
        step("calibrate origin") {
            wait(for: "calibration.calibrateOrigin").click()
            waitGone("toolbar.display.busy", timeout: 90)
        }
        step("probe radius is a number") {
            wait(for: "calibration.probeRadius", timeout: 30)
            waitValue(of: "calibration.probeRadius", timeout: 10) { Double($0) != nil }
        }
    }
}
