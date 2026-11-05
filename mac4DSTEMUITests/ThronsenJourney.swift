// ThronsenJourney: Thronsen et al. (Ultramicroscopy 255, 2024) dataset A at stride 3, driven through the app the way
// ThronsenParityTests sets it up (docs/parity.md, "Precipitation workflow: Thronsen et al."): the R scale at the paper's 13.8 nm,
// the disks, Al / θ′ edge-on / θ′ face-on / T1 from the three Thronsen CIFs with the test's zones, relationships and slabs, the
// Known variants classifier and the test's library and matching values, then the Precipitates section at minimum size 1 and 2,
// N_V without and with a thickness, the object table, the variant map with the θ′ and T1 presets, the CSV, and objects on panes.
// Every step keeps a screenshot, the window's accessibility tree and a full readout of its texts (the record the parity table is
// read against), the session sidecar after Save to Session (the phase map per position, RGBA in PhaseMapPresentation's colours),
// and the two CSVs. The probe radius is typed only where the field exists (mac4DSTEM#114); without it the kernel is the session's
// measured 2.84 px and the map scores 97.25 % against the truth instead of 98.69 % (first drive, 2026-11-05).
// Every click goes to the app only while it is frontmost with its window on screen (`front`); otherwise the step stops.
//
// Heavy (a full phase map of 29 241 positions), real data outside the repo (CC BY 4.0): one pass on a quiet Mac, never per session.
//     env TEST_RUNNER_MACEM_ORG=<org folder> tools/run-tests.sh ui ThronsenJourney
// Without TEST_RUNNER_MACEM_ORG it skips (check the xcresult for Skipped). The cube and its session are copied into the runner's
// temporary folder and the copy is opened, so nothing the app saves lands in References.

import XCTest

final class ThronsenJourney: Journey {
    private static var organization: String? { ProcessInfo.processInfo.environment["MACEM_ORG"] }
    private var folder: URL!

    // MARK: helpers

    /// Synthetic events only into the app itself: it must be frontmost and its window on screen (a full-screen app in another
    /// Space keeps the window off screen, and a click would land in that app instead).
    private func front(_ name: String, _ body: () throws -> Void) rethrows {
        try step(name) {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "mac4DSTEM is not frontmost: stopping before \(name)")
            XCTAssertTrue(app.windows.firstMatch.isHittable, "mac4DSTEM's window is not on screen: stopping before \(name)")
            try body()
        }
    }

    /// The window's accessibility tree as a text attachment: the numbers on screen, as the app shows them.
    private func record(_ name: String, _ element: XCUIElement? = nil) {
        let root = element ?? app.windows.firstMatch
        let text = XCTAttachment(string: root.debugDescription)
        text.name = "tree " + name
        text.lifetime = .keepAlways
        add(text)
        // The tree cuts long values ("Phase map: thetapr..."): every element's identifier, label and value in full, one per line,
        // from one snapshot (no per-element queries that can race a redraw).
        var lines: [String] = []
        func walk(_ e: XCUIElementSnapshot, _ depth: Int) {
            let value = (e.value as? String) ?? (e.value.map { "\($0)" } ?? "")
            let parts = [e.identifier, e.label, e.title, value].filter { !$0.isEmpty }
            if !parts.isEmpty { lines.append(String(repeating: " ", count: depth) + parts.joined(separator: " | ")) }
            for c in e.children { walk(c, depth + 1) }
        }
        if let snapshot = try? root.snapshot() { walk(snapshot, 0) }
        let readout = XCTAttachment(string: lines.joined(separator: "\n"))
        readout.name = "readout " + name
        readout.lifetime = .keepAlways
        add(readout)
    }

    private func waitIdle(_ what: String, timeout: TimeInterval = 600) {
        waitGone("toolbar.display.busy", timeout: timeout)
        XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: timeout), "the room never came back to idle after \(what)")
    }

    /// Scrolls the inspector until the element is fully inside the window (macOS UI tests do not scroll a click target into view;
    /// a button half under the window's bottom edge takes no click).
    @discardableResult
    private func reveal(_ e: XCUIElement) -> XCUIElement {
        guard e.waitForExistence(timeout: 20) else { return e }
        let window = app.windows.firstMatch.frame
        for _ in 0..<15 {
            let f = e.frame
            if f.minY >= window.minY + 60 && f.maxY <= window.maxY - 40 { break }
            let down = f.maxY > window.maxY - 40
            let scroller = app.scrollViews.containing(NSPredicate(format: "identifier == %@ AND label == %@", e.identifier, e.label)).firstMatch
            let target = scroller.exists ? scroller : e
            target.scroll(byDeltaX: 0, deltaY: down ? -120 : 120)
        }
        return e
    }

    /// Replaces a field's text and commits it with Return.
    private func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no field for \(text)", file: file, line: line)
        reveal(field).click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text + "\r")
    }

    /// Opens a disclosure triangle: SwiftUI toggles it only on its chevron, which sits inside the element's frame at a
    /// distance the frame does not say, so the chevron's likely places are tried until the triangle reads open.
    private func expand(_ disclosure: XCUIElement) {
        func isOpen() -> Bool { (disclosure.value as? NSNumber)?.intValue == 1 }
        for dx in [25.0, 12, 6, 32, 18] where !isOpen() {
            disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: dx, dy: 0)).click()
            let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in isOpen() }, object: nil)
            _ = XCTWaiter().wait(for: [opened], timeout: 2)
        }
        XCTAssertTrue(isOpen(), "\(disclosure.label) did not open")
    }

    private func field(_ label: String, _ index: Int = 0) -> XCUIElement {
        // A numeric field speaks its unit with its title ("Max |q|, Å⁻¹", NumericFieldSpeech).
        app.textFields.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ",")).element(boundBy: index)
    }

    /// Picks a menu item of a pop-up button whose title contains `text`.
    private func pick(_ text: String, in popup: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(popup.waitForExistence(timeout: 20), "no pop-up for \(text)", file: file, line: line)
        reveal(popup).click()
        let item = app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", text)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the pop-up has no item containing \(text)", file: file, line: line)
        item.click()
    }

    /// The open panel the CIF importer shows: Go to Folder with the path, then Open.
    private func choose(_ path: String) {
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "the open panel did not appear")
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

    /// The save panel of Export CSV…: the name, Go to Folder with the folder, then Export. Returns the file's text.
    private func exportCSV(named name: String) -> String? {
        reveal(wait(for: "precipitates.exportCSV", timeout: 30)).click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "the save panel did not appear")
        app.typeKey("a", modifierFlags: .command)
        app.typeText(name)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path)
        app.typeKey(.return, modifierFlags: [])
        let save = panel.buttons["OKButton"]   // titled Export in a file exporter, Save elsewhere
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the save panel has no default button")
        save.click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "the save panel did not close")
        let url = folder.appendingPathComponent(name)
        let written = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, object: nil)
        _ = XCTWaiter().wait(for: [written], timeout: 20)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { XCTFail("no CSV at \(url.path)"); return nil }
        let attachment = XCTAttachment(string: text)
        attachment.name = "csv " + name
        attachment.lifetime = .keepAlways
        add(attachment)
        return text
    }

    private var objectTable: XCUIElement { app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Precipitate Objects'")).firstMatch }

    // MARK: the journey

    func testDatasetAThroughTheApp() throws {
        guard let org = Self.organization, !org.isEmpty else { throw XCTSkip("set TEST_RUNNER_MACEM_ORG to the org folder") }
        let source = org + "/References/mac4DSTEM/thronsen-datasetA"
        let cifs = org + "/References/mac4DSTEM/crystal-structures"
        for f in ["datasetA_stride3.h5", "datasetA_stride3.mac4dstem.h5"] {
            try XCTSkipUnless(FileManager.default.fileExists(atPath: source + "/" + f), "\(source)/\(f) is not on this machine")
        }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ThronsenJourney-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { [folder] in try? FileManager.default.removeItem(at: folder!) }
        for f in ["datasetA_stride3.h5", "datasetA_stride3.mac4dstem.h5"] {
            try FileManager.default.copyItem(atPath: source + "/" + f, toPath: folder.appendingPathComponent(f).path)
        }

        step("open datasetA_stride3.h5 with its session") {
            launch(arguments: ["--open", folder.appendingPathComponent("datasetA_stride3.h5").path])
            waitForLoadingToEnd(timeout: 300)
        }
        front("Prepare: R pixel size 13.8 nm (the paper's 4.6 nm at stride 3)") {
            wait(for: "workspace.prepare").click()
            wait(for: "calibration.readiness", timeout: 30)
            let override = element("calibration.action.rManual" + ".override")   // the editor's identifier + ".override"
            if override.waitForExistence(timeout: 5), (override.value as? NSNumber)?.intValue != 1 { expand(override) }
            record("prepare override")
            let r = app.textFields.matching(NSPredicate(format: "identifier == 'calibration.action.rManual' OR label == 'R pixel size'")).firstMatch
            type("13.8", into: r)
            record("prepare")
        }
        front("Bragg Disks: kernel and Detect All Disks") {
            wait(for: "workspace.braggDisks").click()
            // The test's kernel is 2 px; the field exists from mac4DSTEM#114 on. Without it the kernel is the session's measured radius.
            let radius = field("Probe radius")
            if radius.waitForExistence(timeout: 5) { type("2", into: radius) }
            wait(for: "disk.generateSyntheticKernel", timeout: 30).click()
            waitIdle("the kernel")
            let advanced = wait(for: "disk.advancedDisclosure")
            if (advanced.value as? String) == "Collapsed" { advanced.click() }   // a Button, not a triangle
            record("bragg settings")
            let verb = wait(for: "workspace.primaryAction")
            verb.click()
            waitIdle("Detect All Disks", timeout: 900)
            record("bragg detected")
        }
        front("Phase mapping: Al, θ′, T1 from the Thronsen CIFs, θ′ again") {
            wait(for: "workspace.map").click()
            wait(for: "task.Phase mapping").click()
            for cif in ["Al_thronsen2024.cif", "thetaprime_thronsen2024.cif", "T1_thronsen2024.cif"] {
                wait(for: "phaseMapping.addPhase", timeout: 20).click()
                let item = app.menuItems["From CIF file…"]
                XCTAssertTrue(item.waitForExistence(timeout: 10), "Add Phase has no From CIF file…")
                item.click()
                choose(cifs + "/" + cif)
            }
            wait(for: "phaseMapping.addPhase", timeout: 20).click()
            let again = app.menuItems.matching(NSPredicate(format: "title CONTAINS 'thetaprime' AND title CONTAINS 'another zone axis'")).firstMatch
            XCTAssertTrue(again.waitForExistence(timeout: 10), "Add Phase does not offer θ′ for another zone axis")
            again.click()
            record("four phases")
        }
        front("zones, relationships, slabs (ThronsenReference.phases)") {
            // Phase order: Al (matrix), θ′ (edge-on), T1, θ′ (face-on).
            for (i, zone) in ["0 0 1", "1 0 0", "0 -4 1", "0 0 1"].enumerated() { type(zone, into: field("Zone axis", i)) }
            for (i, or) in ["(002) ∥ (200), (002) ∥ (020)", "[210] ∥ [1-10], [210] ∥ [110]", "(200) ∥ (200), (200) ∥ (020)"].enumerated() {
                type(or, into: field("Parallel to matrix", i))
            }
            // Excitation slab rows: θ′ edge-on, T1 (left empty), θ′ face-on.
            type("0.3", into: field("Excitation slab", 0))
            type("0.3", into: field("Excitation slab", 2))
            record("phases set")
        }
        front("library and matching: Known variants, Max |q| 0.70, step 2, min. intensity 0, ignore beyond 0.68") {
            pick("Known variants", in: wait(for: "phaseMapping.classifierPicker"))
            type("0.7", into: field("Max |q|"))
            type("2", into: field("In-plane step"))
            type("0.68", into: field("Ignore peaks beyond"))
            let advanced = app.disclosureTriangles["Advanced"].exists ? app.disclosureTriangles["Advanced"] : app.buttons["Advanced"]
            if advanced.exists { expand(reveal(advanced)) }
            type("0", into: field("Min. intensity"))
            record("settings set")
        }
        front("Map Phases") {
            let run = reveal(wait(for: "phaseMapping.run", timeout: 30))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: run)
            XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "Map Phases never became enabled")
            run.click()
            waitIdle("the phase map", timeout: 1200)
            wait(for: "precipitates.table", timeout: 120)
            record("phase map")
        }
        front("Save to Session: the phase map in the sidecar, for a per-position comparison") {
            let sidecar = folder.appendingPathComponent("datasetA_stride3.mac4dstem.h5")
            let before = (try? FileManager.default.attributesOfItem(atPath: sidecar.path)[.modificationDate]) as? Date
            let save = wait(for: "workspace.saveToResults", timeout: 30)
            XCTAssertTrue(save.isEnabled, "Save to Session is disabled: \((save.value as? String) ?? "")")
            save.click()
            // Opened by `--open`, the sandbox has no grant for the sidecar: the app asks once with a save panel at the sidecar's own
            // path ("Choose Session Sidecar"); Save, then Replace for the existing file.
            let panel = app.dialogs.firstMatch.exists ? app.dialogs.firstMatch : app.sheets.firstMatch
            if panel.waitForExistence(timeout: 10) {
                record("sidecar panel", panel)
                let ok = panel.buttons["OKButton"]
                if ok.waitForExistence(timeout: 5) { ok.click() }
                let replace = app.buttons["Replace"]
                if replace.waitForExistence(timeout: 5) { replace.click() }
            }
            waitIdle("Save to Session")
            let written = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                ((try? FileManager.default.attributesOfItem(atPath: sidecar.path)[.modificationDate]) as? Date) != before
            }, object: nil)
            continueAfterFailure = true
            defer { continueAfterFailure = false }
            if XCTWaiter().wait(for: [written], timeout: 60) != .completed {
                record("save to session refused")
                XCTFail("the sidecar was not rewritten; files: \((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
            }
            // The phase map is the sidecar's current result: RGBA, the legend's colours (PhaseMapPresentation), read per position.
            let file = XCTAttachment(contentsOfFile: sidecar)
            file.name = "sidecar datasetA_stride3.mac4dstem.h5"
            file.lifetime = .keepAlways
            add(file)
        }
        front("Precipitates at minimum size 1, no thickness") {
            type("1", into: field("Minimum size"))
            waitIdle("minimum size 1")
            wait(for: "precipitates.nv.empty", timeout: 20)
            record("min1")
        }
        front("Precipitates at minimum size 2") {
            type("2", into: field("Minimum size"))
            waitIdle("minimum size 2")
            record("min2")
        }
        front("N_V with a typed thickness of 50 nm") {
            type("50", into: wait(for: "precipitates.nv.thickness"))
            record("nv typed")
            // Back to none, as the dataset has no thickness. The emptied field does not clear it yet (mac4DSTEM#129), so the
            // CSVs below still carry 50 nm; not asserted here.
            type("", into: wait(for: "precipitates.nv.thickness"))
            type("1", into: field("Minimum size"))
            waitIdle("minimum size 1 again")
        }
        front("the object table at minimum size 1") {
            reveal(wait(for: "precipitates.table", timeout: 30)).click()
            XCTAssertTrue(objectTable.waitForExistence(timeout: 20), "the object table did not open")
            record("object table", objectTable)
            objectTable.typeKey("w", modifierFlags: .command)
        }
        front("variants: θ′ edge-on, θ′ {001} plate preset") {
            app.windows.firstMatch.click()
            reveal(wait(for: "precipitates.variants.section", timeout: 30)).click()
            pick("[1 0 0]", in: wait(for: "precipitates.variants.phase", timeout: 30))
            pick("θ′ in Al", in: wait(for: "precipitates.variants.orPicker"))
            waitIdle("the θ′ variants")
            let legend = app.disclosureTriangles["Variants"].exists ? app.disclosureTriangles["Variants"] : app.buttons["Variants"]
            if legend.exists { expand(reveal(legend)) }
            record("variants theta")
            _ = exportCSV(named: "thronsen-theta-edge-variants.csv")
        }
        front("variants: θ′ face-on with the same preset") {
            pick("[0 0 1]", in: wait(for: "precipitates.variants.phase", timeout: 30))
            waitIdle("the θ′ face-on variants")
            record("variants theta face")
        }
        front("variants: T1 {111} plate preset") {
            pick("T1", in: wait(for: "precipitates.variants.phase", timeout: 30))
            pick("T1 in Al", in: wait(for: "precipitates.variants.orPicker"))
            waitIdle("the T1 variants")
            record("variants T1")
            _ = exportCSV(named: "thronsen-T1-variants.csv")
        }
        front("objects on panes") {
            let onPanes = wait(for: "precipitates.overlayOnPanes", timeout: 20)
            if (onPanes.value as? NSNumber)?.intValue != 1 { reveal(onPanes).click() }
            wait(for: "precipitates.overlayCountedOnly", timeout: 10)
            record("objects on panes")
        }
    }
}
