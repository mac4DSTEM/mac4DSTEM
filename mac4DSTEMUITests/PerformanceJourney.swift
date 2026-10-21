// PerformanceJourney: wall clock, memory and CPU of the demo's main actions, measured by XCTest (five iterations each). Not part of
// the per-landing run: `tools/run-tests.sh ui Performance` runs it, `ui all` includes it. The numbers go to docs/performance.md.

import XCTest

final class PerformanceJourney: Journey {
    private let options: XCTMeasureOptions = {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }()

    private func metrics() -> [any XCTMetric] {
        [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
    }

    /// Launches once and waits for the demo to be ready; the measured block repeats one action.
    private func openDemo(extra: [String] = ["--demo-fixture"]) {
        launch(arguments: extra)
        waitForLoadingToEnd()
    }

    private func runPrimary(area: String, task: String? = nil, timeout: TimeInterval = 120) {
        wait(for: area).click()
        if let task { wait(for: task).click() }
        wait(for: "workspace.primaryAction").click()
        waitGone("toolbar.display.busy", timeout: timeout)
    }

    func testOpenDemo() {
        measure(metrics: [XCTClockMetric()], options: options) {
            openDemo()
            app.terminate()
        }
    }

    func testPrepareOriginAndProbe() {
        openDemo()
        wait(for: "workspace.prepare").click()
        wait(for: "calibration.action.originProbe")
        measure(metrics: metrics(), options: options) {
            wait(for: "calibration.action.originProbe").click()
            waitGone("toolbar.display.busy", timeout: 90)
        }
    }

    func testADFVirtualImage() {
        openDemo()
        measure(metrics: metrics(), options: options) { runPrimary(area: "workspace.image") }
    }

    func testBraggDisksAllPositions() {
        openDemo()
        measure(metrics: metrics(), options: options) { runPrimary(area: "workspace.braggDisks") }
    }

    func testStrainFromTheDisks() {
        openDemo()
        runPrimary(area: "workspace.braggDisks")
        measure(metrics: metrics(), options: options) { runPrimary(area: "workspace.map", task: "task.Strain") }
    }

    func testAutoIDAndQuantify() {
        openDemo(extra: ["--demo-spectrum-fixture"])
        measure(metrics: metrics(), options: options) {
            // the one read of a label: the button's identifier is not exposed to XCUITest through InspectorAdaptiveButton
            app.buttons["Auto ID"].firstMatch.click()
            waitGone("spectroscopy.autoID.cancel", timeout: 90)
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
    }
}
