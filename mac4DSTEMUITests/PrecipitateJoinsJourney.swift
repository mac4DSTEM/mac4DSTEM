// PrecipitateJoinsJourney: composition and strain per precipitate object (suite task 42) on mac4DSTEM's own 4D-STEM + EDS file,
// through the app's real open path (`--open`) and the Add Phase ▸ From CIF file open panel (aluminium, then β″). One pass before Paul's drive,
// never per session. Run as
//     tools/run-tests.sh ui PrecipitateJoinsJourney
// The file is References/demo-edx-v3/AlMgSi_4D_EDX.dm4 (simulated, beside the repo); the β″ CIF is
// References/crystal-structures/beta_double_prime_Mg5Si6_needle.cif. From a worktree, `References` must be a link to the org's
// References/mac4DSTEM, or the journey skips (check the xcresult for Skipped).

import XCTest

final class PrecipitateJoinsJourney: Journey {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fourDEDS = repo.appendingPathComponent("References/demo-edx-v3/AlMgSi_4D_EDX.dm4").path
    private static let betaCIF = repo.appendingPathComponent("References/crystal-structures/beta_double_prime_Mg5Si6_needle.cif").path
    private static let aluminiumCIF = repo.appendingPathComponent("References/crystal-structures/Al_thronsen2024.cif").path

    private func waitIdle(_ what: String, timeout: TimeInterval = 300) {
        XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: timeout), "the room never came back to idle after \(what)")
    }

    private func clickPrimary(_ what: String, timeout: TimeInterval = 300) {
        let verb = wait(for: "workspace.primaryAction", timeout: 60)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: verb)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 120), .completed, "\(what) never became enabled")
        verb.click()
        waitGone("toolbar.display.busy", timeout: timeout)
        waitIdle(what, timeout: timeout)
    }

    /// The open panel the CIF importer shows: Go to Folder with the path, then Open.
    private func choose(_ path: String) {
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "the CIF open panel did not appear")
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = panel.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Go to Folder showed no path field")
        field.typeText(path)
        field.typeKey(.return, modifierFlags: [])
        let open = panel.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the open panel has no Open button")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: open)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, "Open stayed disabled for \(path)")
        open.click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "the open panel did not close")
    }

    /// The object table's window (its title carries the subtitle: "Precipitate Objects – 11 counted of 12 · …").
    private var table: XCUIElement { app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Precipitate Objects'")).firstMatch }

    /// Spectroscopy ▸ Maps ▸ at%: the composition maps. The object join no longer reads them (an object's composition is one pooled fit
    /// of its summed spectrum since 5.2.1); the step stays because the journey also looks at the maps.
    private func showAtomicPercentMaps() {
        wait(for: "workspace.spectroscopy").click()
        let picker = wait(for: "edx.mapMode", timeout: 30)
        let segment = picker.descendants(matching: .any).matching(NSPredicate(format: "label == 'at%' OR title == 'at%' OR value == 'at%'")).firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 10), "Maps has no at% segment")
        segment.click()
        waitIdle("the at% maps", timeout: 300)
    }

    private func openAndQuantify(adding extra: [String] = []) throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.fourDEDS), "\(Self.fourDEDS) is not on this machine")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.betaCIF), "\(Self.betaCIF) is not on this machine")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.aluminiumCIF), "\(Self.aluminiumCIF) is not on this machine")
        step("open AlMgSi_4D_EDX.dm4") {
            launch(arguments: ["--open", Self.fourDEDS, "--export-dir", "precipitate-joins-journey"])
            waitForLoadingToEnd(timeout: 180)
            wait(for: "edx.spectrum", timeout: 180)
            waitIdle("Auto ID on open")
        }
        for symbol in extra {
            step("add \(symbol) in the Elements table") {
                let cell = wait(for: "periodicTable.\(symbol)", timeout: 30)
                // A click toggles: an element Auto ID already mapped would be switched off by it (mac4DSTEM#201, Mg on the demo).
                if (cell.value as? String) != "mapped" { cell.click() }
                let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'mapped'"), object: cell)
                XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 20), .completed,
                               "\(symbol) is not quantified after the click: \(String(describing: cell.value))")
                waitIdle("adding \(symbol)")
            }
        }
        step("Quantify the spectrum image") {
            clickPrimary("Quantify")
            wait(for: "edx.compositionTable", timeout: 60)
        }
    }

    /// Disks, the phase map of aluminium and β″ with its objects, strain, and the object table open.
    /// `typedEndOnZone`: Typed zone axes switched on and β″ typed as [0 1 0] (the needles end-on) with the Known variants
    /// classifier, which is what Count variants reads today (mac4DSTEM#245).
    private func objectsStrainAndTable(typedEndOnZone: Bool = false) {
        step("detect Bragg disks") {
            wait(for: "workspace.braggDisks").click()
            clickPrimary("Detect")
        }
        step("Crystal Maps, Phase mapping, aluminium and β″ from their CIFs") {
            wait(for: "workspace.map").click()
            wait(for: "task.Phase mapping").click()
            for path in [Self.aluminiumCIF, Self.betaCIF] {
                wait(for: "phaseMapping.addPhase", timeout: 20).click()
                let item = app.menuItems["From CIF file…"]
                XCTAssertTrue(item.waitForExistence(timeout: 10), "Add Phase has no From CIF file")
                item.click()
                choose(path)
            }
        }
        if typedEndOnZone {
            step("Phases ▸ Advanced ▸ Typed zone axes; β″ at [0 1 0]; Known variants") {
                let typed = element("phaseMapping.typedZones")
                if !typed.waitForExistence(timeout: 3) {
                    let advanced = app.disclosureTriangles["Advanced"].firstMatch
                    XCTAssertTrue(advanced.waitForExistence(timeout: 10), "Phases has no Advanced disclosure")
                    advanced.click()
                }
                XCTAssertTrue(typed.waitForExistence(timeout: 10), "Advanced has no Typed zone axes switch")
                if (typed.value as? String) != "1", (typed.value as? Int) != 1 { typed.click() }
                let zones = app.textFields.matching(NSPredicate(format: "label == 'Zone axis'"))
                let beta = zones.element(boundBy: 1)
                XCTAssertTrue(beta.waitForExistence(timeout: 10), "the β″ row has no Zone axis field")
                beta.click(); beta.typeKey("a", modifierFlags: .command); beta.typeText("0 1 0\r")
                wait(for: "phaseMapping.classifierPicker", timeout: 10).click()
                let known = app.menuItems["Known variants"]
                XCTAssertTrue(known.waitForExistence(timeout: 5), "the classifier has no Known variants")
                known.click()
            }
        }
        step("map phases") {
            clickPrimary("Phase mapping")
            wait(for: "precipitates.table", timeout: 120)
        }
        step("compute strain") {
            wait(for: "task.Strain").click()
            clickPrimary("Strain")
            wait(for: "strain.component", timeout: 60)
        }
        step("back to Phase mapping, open the object table") {
            wait(for: "task.Phase mapping").click()
            wait(for: "precipitates.table", timeout: 30).click()
            XCTAssertTrue(table.waitForExistence(timeout: 20), "the object table did not open")
        }
    }

    /// Quantify, Maps at%, objects, strain: both columns of the object table are filled.
    func test1_CompositionAndStrainPerObject() throws {
        try openAndQuantify()
        step("Maps ▸ at%") { showAtomicPercentMaps() }
        objectsStrainAndTable()
        step("the composition and strain columns are filled") {
            let notes = table.descendants(matching: .any).matching(identifier: "precipitates.objects.joinNotes").firstMatch
            if notes.exists {
                XCTFail("the object table says a join is unavailable: \((notes.value as? String) ?? notes.label)")
            }
            let atPct = table.staticTexts.matching(NSPredicate(format: "value CONTAINS ' at%' OR label CONTAINS ' at%'")).firstMatch
            XCTAssertTrue(atPct.waitForExistence(timeout: 10), "no row shows a composition in at%")
            let strain = table.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'rr ' OR label BEGINSWITH 'rr '")).firstMatch
            XCTAssertTrue(strain.waitForExistence(timeout: 10), "no row shows a strain")
        }
        step("both join columns are on screen at the default size") {
            // #106: they sat past the shape columns, off screen until the reader scrolled.
            // The composition is one pooled fit per object since 5.2.1, and its column says so (mac4DSTEM#201).
            for header in ["Composition (pooled fit)", "Strain (mean of pixels)"] {
                let button = table.buttons[header]
                XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(header) column")
                XCTAssertLessThanOrEqual(button.frame.maxX, table.frame.maxX, "\(header) is off screen to the right")
            }
        }
    }

    /// Quantify with Maps left at net counts. Until 5.2.1 the composition per object was read from the composition maps, and a
    /// note asked for wt% or at% (#99). It is one pooled fit per object now, so the column is filled without the maps and no note
    /// says a join is unavailable (mac4DSTEM#201).
    func test2_QuantifiedWithoutCompositionMapsStillFillsTheComposition() throws {
        try openAndQuantify()
        objectsStrainAndTable()
        step("the composition is filled and no note says a join is unavailable") {
            let atPct = table.staticTexts.matching(NSPredicate(format: "value CONTAINS ' at%' OR label CONTAINS ' at%'")).firstMatch
            XCTAssertTrue(atPct.waitForExistence(timeout: 60), "no row shows a composition in at%")
            let notes = table.descendants(matching: .any).matching(identifier: "precipitates.objects.joinNotes").firstMatch
            if notes.exists {
                XCTFail("the object table says a join is unavailable: \((notes.value as? String) ?? notes.label)")
            }
        }
    }

    /// The composition cells of the table, row by row, as the window shows them (attached to the step for the PR's truth table).
    private func compositionCells() -> [String] {
        table.staticTexts.allElementsBoundByIndex.compactMap { ($0.value as? String) ?? $0.label }.filter { $0.contains(" at%") }
    }

    /// #108: Mg added by hand before Quantify; the β″ objects then carry Mg, and the coverage line names it.
    func test3_MgAddedByHandShowsInTheComposition() throws {
        try openAndQuantify(adding: ["Mg"])
        step("Maps ▸ at%") { showAtomicPercentMaps() }
        objectsStrainAndTable()
        step("the β″ objects show Mg, and the coverage line names Mg") {
            let coverage = table.descendants(matching: .any).matching(identifier: "precipitates.objects.compositionCoverage").firstMatch
            XCTAssertTrue(coverage.waitForExistence(timeout: 10), "the table does not say which elements the composition covers")
            let text = (coverage.value as? String) ?? coverage.label
            XCTAssertTrue(text.contains("Mg"), "the coverage line reads: \(text)")
            let cells = compositionCells()
            let record = XCTAttachment(string: cells.joined(separator: "\n"))
            record.name = "composition cells"; record.lifetime = .keepAlways
            add(record)
            XCTAssertFalse(cells.isEmpty, "no composition cell")
            XCTAssertTrue(cells.allSatisfy { $0.contains("Mg ") }, "an object has no Mg: \(cells)")
        }
    }

    /// The variant map on the same file (suite task 40): Count variants on, the legend counts needles per direction and per variant,
    /// and the exported CSV carries the variant columns. The file is version 3 of the demo, whose beta'' are variants of the Andersen
    /// relationship (#115; version 2 planted them at the matrix's in-plane angle + 0 or 90 degrees, so every object was unassigned). The
    /// assignments themselves are pinned without the screen by `DemoV3VariantsTests`; this journey checks the legend, the totals line and the CSV.
    func test4_VariantMapLegendAndCSV() throws {
        try openAndQuantify()
        objectsStrainAndTable(typedEndOnZone: true)
        step("close the table, Count variants") {
            table.buttons["_XCUI:CloseWindow"].click()
            let toggle = wait(for: "precipitates.variants.section", timeout: 20)
            toggle.click()
            XCTAssertTrue(element("precipitates.variants.totals").waitForExistence(timeout: 60)
                          || element("precipitates.variants.unavailable").exists, "the variant run showed neither a legend nor a reason")
            if element("precipitates.variants.unavailable").exists {
                let why = element("precipitates.variants.unavailable")
                XCTFail("variants unavailable: \((why.value as? String) ?? why.label)")
            }
            let directions = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'precipitates.variants.legend.direction.'"))
            XCTAssertGreaterThan(directions.count, 0, "the legend has no needle direction rows")
            let totals = element("precipitates.variants.totals")
            let record = XCTAttachment(string: ((totals.value as? String) ?? totals.label) + "\n"
                                       + directions.allElementsBoundByIndex.map(\.label).joined(separator: "\n"))
            record.name = "variant legend"; record.lifetime = .keepAlways
            add(record)
        }
        step("Export CSV with the variant columns") {
            let path = NSTemporaryDirectory() + "precipitate-objects-\(UUID().uuidString).csv"
            wait(for: "precipitates.exportCSV").click()
            let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 20), "the save panel did not appear")
            let name = panel.textFields["saveAsNameTextField"]
            XCTAssertTrue(name.waitForExistence(timeout: 10), "the save panel has no name field")
            name.click()
            name.typeKey("a", modifierFlags: .command)
            name.typeText((path as NSString).lastPathComponent)
            app.typeKey("g", modifierFlags: [.command, .shift])
            let go = app.textFields["PathTextField"]
            XCTAssertTrue(go.waitForExistence(timeout: 10), "Go to Folder showed no path field")
            go.typeText(NSTemporaryDirectory())
            go.typeKey(.return, modifierFlags: [])
            let goGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: go)
            XCTAssertEqual(XCTWaiter().wait(for: [goGone], timeout: 10), .completed, "Go to Folder did not close")
            panel.buttons["OKButton"].click()   // titled Export by the file exporter
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
            XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "the save panel did not close")
            let written = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path) }, object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [written], timeout: 20), .completed, "no CSV at \(path)")
            let csv = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let header = csv.split(separator: "\n").first { !$0.hasPrefix("#") && $0.contains("variant") }.map(String.init) ?? ""
            for column in ["variant", "direction", "variant_status", "variant_agreement", "variant_angle_deg"] {
                XCTAssertTrue(header.split(separator: ",").contains { $0 == column }, "the CSV has no \(column) column: \(header)")
            }
            let record = XCTAttachment(string: csv); record.name = "objects CSV"; record.lifetime = .keepAlways
            add(record)
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
