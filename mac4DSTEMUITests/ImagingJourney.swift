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

    /// The circular region: the positions inside the drawn ring summed into the diffraction pane.
    func testCircleRegionShowsTheSummedPattern() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Imaging") {
            waitForLoadingToEnd()
            wait(for: "workspace.image").click()
            wait(for: "result.viewer", timeout: 30)
        }
        step("switch the direction to Region and pick a circle") {
            labelled("Region").click()
            labelled("Circle").click()
        }
        step("the diffraction pane shows the circle region sum") {
            wait(for: "pattern.roiSumBadge", timeout: 30)
        }
    }

    /// Another room's map, then Imaging: the virtual image is back, not the map under the Imaging room.
    /// Strain stands in for an ACOM preview (the demo has no crystal to match); both left their map on screen.
    func testImagingAfterAStrainMapShowsTheVirtualImage() {
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
        step("open Imaging: the virtual image is shown") {
            wait(for: "workspace.image").click()
            waitGone("toolbar.display.busy", timeout: 60)
            let title = wait(for: "result.title", timeout: 10)
            let text = "\(title.label) \(title.value as? String ?? "")"
            XCTAssertTrue(text.contains("Virtual detector"), "Imaging shows \(text)")
            XCTAssertFalse(text.contains("Strain"), "Imaging kept the strain map: \(text)")
        }
    }

    private func labelled(_ label: String) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR title == %@", label, label)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 10), "no control labelled \(label)")
        return match
    }
}
