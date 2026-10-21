// ReconstructionJourney: DPC on the demo (process/ui-testing-2026-10-21.md §3).

import XCTest

final class ReconstructionJourney: Journey {
    func testDPCOnTheDemoShowsAResultWithItsBadge() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Reconstruction, DPC") {
            waitForLoadingToEnd()
            wait(for: "workspace.reconstruct").click()
            wait(for: "task.DPC").click()
        }
        step("run DPC") {
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
            wait(for: "result.viewer", timeout: 30)
            wait(for: "result.statusBadge", timeout: 30)
        }
    }
}
