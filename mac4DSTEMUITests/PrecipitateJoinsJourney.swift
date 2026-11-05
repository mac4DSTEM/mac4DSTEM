// PrecipitateJoinsJourney: composition and strain per precipitate object (suite task 42) on mac4DSTEM's own 4D-STEM + EDS file,
// through the app's real open path (`--open`) and the Add Phase ▸ Presets ▸ Al–Mg–Si open panel. One pass before Paul's drive,
// never per session. Run as
//     tools/run-tests.sh ui PrecipitateJoinsJourney
// The file is References/demo-edx/AlMgSi_4D_EDX.dm4 (simulated, beside the repo); the β″ CIF is
// References/crystal-structures/beta_double_prime_Mg5Si6_needle.cif. From a worktree, `References` must be a link to the org's
// References/mac4DSTEM, or the journey skips (check the xcresult for Skipped).

import XCTest

final class PrecipitateJoinsJourney: Journey {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fourDEDS = repo.appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4").path
    private static let betaCIF = repo.appendingPathComponent("References/crystal-structures/beta_double_prime_Mg5Si6_needle.cif").path

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

    /// Spectroscopy ▸ Maps ▸ at%: the per-pixel composition maps the object join reads are made only while wt% or at% is shown.
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
        step("open AlMgSi_4D_EDX.dm4") {
            launch(arguments: ["--open", Self.fourDEDS, "--export-dir", "precipitate-joins-journey"])
            waitForLoadingToEnd(timeout: 180)
            wait(for: "edx.spectrum", timeout: 180)
            waitIdle("Auto ID on open")
        }
        for symbol in extra {
            step("add \(symbol) in the Elements table") {
                let cell = wait(for: "periodicTable.\(symbol)", timeout: 30)
                cell.click()
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

    /// Disks, the Al–Mg–Si phase map with its objects, strain, and the object table open.
    private func objectsStrainAndTable() {
        step("detect Bragg disks") {
            wait(for: "workspace.braggDisks").click()
            clickPrimary("Detect")
        }
        step("Crystal Maps, Phase mapping, Al–Mg–Si preset") {
            wait(for: "workspace.map").click()
            wait(for: "task.Phase mapping").click()
            wait(for: "phaseMapping.addPhase", timeout: 20).click()
            let preset = app.menuItems["Al–Mg–Si (β″ needles)…"]
            XCTAssertTrue(preset.waitForExistence(timeout: 10), "Add Phase has no Al–Mg–Si preset")
            preset.click()
            choose(Self.betaCIF)
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
    }

    /// Quantify with Maps left at net counts (#99): the composition note names the missing step, not Quantify.
    func test2_QuantifiedWithoutCompositionMapsSaysWhatToShow() throws {
        try openAndQuantify()
        objectsStrainAndTable()
        step("the composition note says to show wt% or at%") {
            let notes = table.descendants(matching: .any).matching(identifier: "precipitates.objects.joinNotes").firstMatch
            XCTAssertTrue(notes.waitForExistence(timeout: 10), "no join note")
            let text = (notes.value as? String) ?? notes.label
            XCTAssertTrue(text.contains("wt% or at%"), "the note reads: \(text)")
            XCTAssertFalse(text.contains("Strain:"), "strain is computed but the note says it is not: \(text)")
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
    /// and the exported CSV carries the variant columns. It does not assert assignments: the demo plants beta'' at the matrix's in-plane
    /// angle + 0 or 90 degrees, not in the Andersen relationship, so every object is honestly unassigned here (#115).
    func test4_VariantMapLegendAndCSV() throws {
        try openAndQuantify()
        objectsStrainAndTable()
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
