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

    private func openAndQuantify() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.fourDEDS), "\(Self.fourDEDS) is not on this machine")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.betaCIF), "\(Self.betaCIF) is not on this machine")
        step("open AlMgSi_4D_EDX.dm4") {
            launch(arguments: ["--open", Self.fourDEDS, "--export-dir", "precipitate-joins-journey"])
            waitForLoadingToEnd(timeout: 180)
            wait(for: "edx.spectrum", timeout: 180)
            waitIdle("Auto ID on open")
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
}
