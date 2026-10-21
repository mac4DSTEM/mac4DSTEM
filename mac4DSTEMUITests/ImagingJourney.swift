// ImagingJourney: Imaging, the ADF preset, the virtual image shown (process/ui-testing-2026-10-21.md §3).

import XCTest

final class ImagingJourney: Journey {
    func testADFPresetShowsAFreshVirtualImage() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Imaging") {
            waitForLoadingToEnd()
            wait(for: "workspace.image").click()
            wait(for: "result.viewer", timeout: 30)
        }
        step("apply the ADF preset") {
            wait(for: "detector.preset.adf").click()
            waitGone("toolbar.display.busy", timeout: 60)
            wait(for: "result.viewer")
            XCTAssertFalse(element("result.staleBadge").exists, "the virtual image is stale after applying a preset")
        }
    }
}
