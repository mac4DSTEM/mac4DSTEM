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

    /// A region of the scan summed into the diffraction pane: the kit's Metal selected-area pattern, badged "ROI sum".
    func testRegionShowsTheSummedPattern() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Imaging") {
            waitForLoadingToEnd()
            wait(for: "workspace.image").click()
            wait(for: "result.viewer", timeout: 30)
        }
        step("switch the direction to Region and pick a rectangle") {
            labelled("Region").click()
            labelled("Rectangle").click()
        }
        step("the diffraction pane shows the region sum") {
            wait(for: "pattern.roiSumBadge", timeout: 30)
        }
    }

    private func labelled(_ label: String) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR title == %@", label, label)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 10), "no control labelled \(label)")
        return match
    }
}
