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
        step("the Profile tab plots the launch line, 28 nm long") {
            // the segmented tab row is found by its segment labels (its identifier is replaced on macOS 27)
            let tab = app.radioButtons["Profile"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "no Profile tab although a line is drawn")
            tab.click()
            // the header names the line and its length (the kit's last sample distance): 28 px at 1 nm
            let header = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "Profile \u{00B7} Line 1 \u{00B7} 28 nm")).firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 30), "the Profile header does not say Line 1, 28 nm")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Profile along the line")).firstMatch.exists, "no chart")
        }
        step("the Table tab lists the whole map and both regions with their pixel counts") {
            let tab = app.radioButtons["Table"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "no Table tab although maps exist")
            tab.click()
            let table = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Region table")).firstMatch
            XCTAssertTrue(table.waitForExistence(timeout: 30), "the Table tab shows no table")
            for count in ["1\u{202F}024", "64", "16"] {   // the whole map is 32 x 32; the regions are the launch's 8 x 8 and 4 x 4
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", count, count)).firstMatch.waitForExistence(timeout: 30), "no \(count) px row")
            }
        }
        step("back on the Spectrum tab") {
            app.radioButtons["Spectrum"].firstMatch.click()
            wait(for: "spectroscopy.spectrum")
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
        step("the Table tab holds the fitted composition of the whole map and both regions") {
            app.radioButtons["Table"].firstMatch.click()
            let fitted = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Fitted composition")).firstMatch
            XCTAssertTrue(fitted.waitForExistence(timeout: 60), "no fitted composition after Quantify")
            for name in ["Whole map", "Region 1", "Region 2"] {
                XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 60), "no \(name) row in the fitted composition")
            }
        }
    }
}
