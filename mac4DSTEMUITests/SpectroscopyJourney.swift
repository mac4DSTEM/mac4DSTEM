// SpectroscopyJourney: the demo EDX spectrum image, Auto ID, Quantify (process/ui-testing-2026-10-21.md §3).

import XCTest

final class SpectroscopyJourney: Journey {
    func testAutoIDAndQuantifyOnTheDemoSpectrumImage() {
        step("launch with the demo spectrum image") { launch(arguments: ["--demo-spectrum-fixture", "--demo-spectrum-regions"]) }
        step("the Spectroscopy room is open") {
            waitForLoadingToEnd()
            wait(for: "spectroscopy.room", timeout: 30)
        }
        step("the header row holds the region tool and the map mode") {
            wait(for: "spectroscopy.header")
            wait(for: "spectroscopy.regionTool")
            wait(for: "spectroscopy.mapMode")
            wait(for: "spectroscopy.results")
        }
        step("the Tile size menu starts on Medium and Large reflows the tiles") {
            // by label: the picker's own identifier is replaced by the inspector's (macOS 27)
            let menu = app.popUpButtons["Tile size"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "no Tile size menu")
            XCTAssertEqual(menu.value as? String, "Medium", "the default tile size is Medium")
            menu.click()
            app.menuItems["Large"].firstMatch.click()   // a menu item has no identifier
            XCTAssertEqual(menu.value as? String, "Large", "Large did not take")
        }
        step("two regions are listed and each keeps its pixel count") {
            // Launched with two drawn regions of known size (8 x 8 and 4 x 4): XCUITest's synthetic drag does not reach the drawing tool.
            // the row's own identifier is replaced by its children's on macOS 27: the name fields stand for the rows
            wait(for: "regions.name.Region 1")
            wait(for: "regions.name.Region 2")
            func shows(_ text: String) -> Bool {
                app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 30)
            }
            XCTAssertTrue(shows("16 px"), "Region 2 (the newest, selected) is not 16 px")
            // a click just right of Region 1's name field lands on its row (the kind word is not exposed): the row selects it
            element("regions.name.Region 1").coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 0.5)).click()
            XCTAssertTrue(shows("64 px"), "Region 1 is not 64 px")
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
