// PerformanceJourney: how long the demo's main actions take. XCTest metrics (clock, memory, CPU) over five iterations; every iteration
// is a fresh launch and the way to the room (not measured, except "open"), then the measured action runs from the click to the busy
// state ending. The clock includes XCUITest's own click latency (1 to 3 s per click-and-wait here), so it is an upper bound; the app's
// own time is the signpost interval around its compute (`Signposts`, read by `XCTOSSignpostMetric`), reported beside it. Not part of
// the per-landing run: `tools/run-tests.sh ui Performance` runs it. The numbers go to docs/performance.md.

import XCTest

final class PerformanceJourney: Journey {
    private let subsystem = "com.mac4dstem.mac4DSTEM"

    private func metrics(_ app: XCUIApplication, signposts: [String]) -> [any XCTMetric] {
        [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
            + signposts.map { XCTOSSignpostMetric(subsystem: subsystem, category: "performance", name: $0) }
    }

    private func relaunch(_ arguments: [String]) -> XCUIApplication {
        let a = XCUIApplication()
        a.terminate()
        a.launchArguments = ["--ui-testing"] + arguments
        a.launch()
        a.activate()
        _ = a.windows.firstMatch.waitForExistence(timeout: 20)
        app = a
        return a
    }

    /// Five iterations; each: `prepare` (a fresh launch and the way to the room, unmeasured), then `action` measured.
    private func measureAction(_ arguments: [String], signposts: [String], prepare: () -> Void = {}, action: () -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart]
        let probe = XCUIApplication()
        measure(metrics: metrics(probe, signposts: signposts), options: options) {
            _ = relaunch(arguments)
            waitForLoadingToEnd()
            prepare()
            startMeasuring()
            action()
        }
        probe.terminate()
    }

    private func primaryAndWait(timeout: TimeInterval = 120) {
        wait(for: "workspace.primaryAction").click()
        waitGone("toolbar.display.busy", timeout: timeout)
    }

    func testOpenTheDemo() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart]
        let probe = XCUIApplication()
        measure(metrics: [XCTClockMetric(), XCTOSSignpostMetric(subsystem: subsystem, category: "performance", name: "open.demo")], options: options) {
            probe.terminate()
            probe.launchArguments = ["--ui-testing", "--demo-fixture"]
            startMeasuring()
            probe.launch()
            app = probe
            waitForLoadingToEnd()
        }
        probe.terminate()
    }

    func testPrepareOriginAndProbe() {
        measureAction(["--demo-fixture"], signposts: ["prepare.origin"], prepare: {
            wait(for: "workspace.prepare").click()
            wait(for: "calibration.action.originProbe")
        }, action: {
            wait(for: "calibration.action.originProbe").click()
            waitGone("toolbar.display.busy", timeout: 90)
        })
    }

    func testADFVirtualImage() {
        measureAction(["--demo-fixture"], signposts: ["virtual.image"], prepare: { wait(for: "workspace.image").click() },
                      action: { primaryAndWait() })
    }

    func testBraggDisksAllPositions() {
        measureAction(["--demo-fixture"], signposts: ["disks.all"], prepare: { wait(for: "workspace.braggDisks").click() },
                      action: { primaryAndWait() })
    }

    func testStrainFromTheDisks() {
        measureAction(["--demo-fixture"], signposts: ["strain.map"], prepare: {
            wait(for: "workspace.braggDisks").click(); primaryAndWait()
            wait(for: "workspace.map").click()
            wait(for: "task.Strain").click()
        }, action: { primaryAndWait() })
    }

    func testAutoIDAndQuantify() {
        // The EDS room (macTEM's): its refresh is the session's one signposted pass (Auto ID and Quantify both run through it).
        measureAction(["--demo-spectrum-fixture"], signposts: ["edx.refresh"], prepare: {
            wait(for: "edx.room", timeout: 30)
            XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: 90), "Auto ID on open did not finish")
        }, action: {
            wait(for: "edx.autoID").click()
            XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: 90), "Auto ID did not finish")
            primaryAndWait()
        })
    }
}
