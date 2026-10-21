// LaunchJourney: the app launches and the demo opens (process/ui-testing-2026-10-21.md §3).

import XCTest

final class LaunchJourney: Journey {
    func testTheDemoOpensInPrepare() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("demo ready") {
            wait(for: "workspace.prepare")
            waitForLoadingToEnd()
            wait(for: "calibration.readiness", timeout: 30)
        }
    }

    /// The same launch in light mode: contrast of the status badges, colorbars and sidebar on a light background (the design
    /// review had only dark shots). The app owns its appearance preference (`prefs.appearance`, System / Light / Dark), so the
    /// launch argument sets that key for this run only (the argument domain; nothing is written to the person's defaults).
    func testTheDemoOpensInPrepareInLightMode() {
        step("launch with the demo in light mode") { launch(arguments: ["--demo-fixture", "-prefs.appearance", "light"]) }
        step("demo ready in light mode") {
            wait(for: "workspace.prepare")
            waitForLoadingToEnd()
            wait(for: "calibration.readiness", timeout: 30)
        }
    }

    /// The same launch at 1280 points wide: where wrap and truncation show first (the status bar message, inspector rows).
    func testTheDemoOpensInPrepareAt1280() {
        step("launch with the demo at 1280 wide") { launch(arguments: ["--demo-fixture", "--ui-window-width", "1280"]) }
        step("demo ready at 1280") {
            wait(for: "workspace.prepare")
            waitForLoadingToEnd()
            wait(for: "calibration.readiness", timeout: 30)
            let width = app.windows.firstMatch.frame.width
            XCTAssertEqual(width, 1280, accuracy: 10, "the window did not open at 1280 (it is \(width) points wide)")
        }
    }
}
