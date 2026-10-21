// LaunchJourney: the app launches and the demo opens (process/ui-testing-2026-10-21.md §3).

import XCTest

final class LaunchJourney: Journey {
    func testTheDemoOpensInPrepare() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("demo ready") {
            wait(for: "workspace.prepare")
            waitForLoadingToEnd()
            let status = wait(for: "toolbar.display.idle")
            let text = (status.value as? String) ?? status.label
            XCTAssertTrue(text.contains("Demo.h5") && text.contains("Prepare"), "status line: \(text)")
        }
    }
}
