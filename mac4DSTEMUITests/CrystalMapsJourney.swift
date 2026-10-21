// CrystalMapsJourney: Bragg Disks on the demo, then strain from the disks in Crystal Maps (process/ui-testing-2026-10-21.md §3).

import XCTest

final class CrystalMapsJourney: Journey {
    func testStrainFromTheDisks() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("detect all disks") {
            waitForLoadingToEnd()
            wait(for: "workspace.braggDisks").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
        step("open Crystal Maps, strain") {
            wait(for: "workspace.map").click()
            wait(for: "task.Strain").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
        step("the strain component is chosen") {
            wait(for: "strain.component", timeout: 30)
        }
    }
}
