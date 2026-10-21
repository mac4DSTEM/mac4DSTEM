// PrepareJourney: Prepare on the calibrated demo, Re-calibrate Origin, and the file's probe radius stays 4.5 px
// (process/ui-testing-2026-10-21.md §3; the 2026-10-21 probe-radius fix, seen on screen).

import XCTest

final class PrepareJourney: Journey {
    func testRecalibrateOriginKeepsTheFilesProbeRadius() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Prepare") {
            waitForLoadingToEnd()
            wait(for: "workspace.prepare").click()
            wait(for: "calibration.readiness", timeout: 30)
        }
        step("re-calibrate origin") {
            wait(for: "calibration.action.originProbe").click()
            waitGone("toolbar.display.busy", timeout: 90)
        }
        step("the probe radius is still the file's") {
            // The one read of a label: the readiness row states the radius and where it came from in one sentence.
            let probe = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label MATCHES '.*Probe: 4[.,]5.*' OR value MATCHES '.*Probe: 4[.,]5.*'")).firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 30), "the readiness row no longer says Probe: 4.5 (or 4,5)")
        }
    }
}
