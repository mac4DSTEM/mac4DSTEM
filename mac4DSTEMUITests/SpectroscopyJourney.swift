// SpectroscopyJourney: the demo EDX spectrum image, Auto ID, Quantify (process/ui-testing-2026-10-21.md §3).

import XCTest

final class SpectroscopyJourney: Journey {
    func testAutoIDAndQuantifyOnTheDemoSpectrumImage() {
        step("launch with the demo spectrum image") { launch(arguments: ["--demo-spectrum-fixture"]) }
        step("the Spectroscopy room is open") {
            waitForLoadingToEnd()
            wait(for: "spectroscopy.room", timeout: 30)
        }
        step("Auto ID") {
            // the one read of a label: the button's identifier is not exposed to XCUITest through InspectorAdaptiveButton
            app.buttons["Auto ID"].firstMatch.click()
            waitGone("spectroscopy.autoID.cancel", timeout: 90)
        }
        step("Quantify") {
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
        step("the results name Mg and Si") {
            // The results table is one accessibility element per row; read the rows' labels (no identifier on them yet).
            for symbol in ["Mg", "Si"] {
                let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", symbol, symbol)).firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 30), "no \(symbol) in the results")
            }
        }
    }
}
