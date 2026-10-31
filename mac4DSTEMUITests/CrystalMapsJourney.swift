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

    /// A strain map computed, Orientation visited, Strain again: the map is still on screen, not "No Result Yet".
    func testStrainSurvivesAnOrientationVisit() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("detect all disks") {
            waitForLoadingToEnd()
            wait(for: "workspace.braggDisks").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
        step("compute strain") {
            wait(for: "workspace.map").click()
            wait(for: "task.Strain").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
            wait(for: "result.viewer", timeout: 30)
        }
        step("visit Orientation") {
            wait(for: "task.ACOM").click()
        }
        step("back to Strain: the map is still shown") {
            wait(for: "task.Strain").click()
            wait(for: "result.viewer", timeout: 10)
            XCTAssertFalse(app.staticTexts["No Result Yet"].exists, "Strain lost its map after an Orientation visit")
        }
    }
}
