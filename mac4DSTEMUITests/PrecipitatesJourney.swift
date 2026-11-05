// PrecipitatesJourney: the precipitation workflow on Paul's Al–Mg–Si cube ($MACEM_DATA/4dstem/training_dataset, default ../data):
// origin, ellipse and R–Q rotation where the file lacks them, disks, the Al CIF and Q from the material (or PRECIP_Q typed by hand),
// the Al–Mg–Si preset, Map Phases, the Precipitates section (objects, N_V, variants), objects on panes, the object table.
// Opt-in: TEST_RUNNER_PRECIP=1 TEST_RUNNER_MACEM_DATA=<data folder> [TEST_RUNNER_PRECIP_CUBE=<file>] [TEST_RUNNER_PRECIP_Q=<Å⁻¹/px>].

import XCTest

final class PrecipitatesJourney: Journey {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let data = ProcessInfo.processInfo.environment["MACEM_DATA"]
        ?? repo.deletingLastPathComponent().appendingPathComponent("data").path
    private static let betaCIF = URL(fileURLWithPath: data).deletingLastPathComponent()
        .appendingPathComponent("References/mac4DSTEM/crystal-structures/beta_double_prime_Mg5Si6_needle.cif").path
    private static let alCIF = URL(fileURLWithPath: data).deletingLastPathComponent()
        .appendingPathComponent("References/mac4DSTEM/crystal-structures/Al_thronsen2024.cif").path
    /// PRECIP_CUBE (TEST_RUNNER_PRECIP_CUBE from xcodebuild) picks another cube under $MACEM_DATA, e.g. the ellipse-corrected one.
    private static let cube = data + "/4dstem/training_dataset/" + (ProcessInfo.processInfo.environment["PRECIP_CUBE"]
        ?? "Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5")

    func testPrecipitationWorkflowOnTheAlMgSiCube() throws {
        // Opt-in (TEST_RUNNER_PRECIP=1): a 1.8 GB real cube, minutes per run; never part of the per-landing set.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRECIP"] == "1", "opt-in: TEST_RUNNER_PRECIP=1")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.cube), "the Al–Mg–Si cube is not on this Mac")
        step("open the Al–Mg–Si cube with its session") {
            launch(arguments: ["--open", Self.cube])
            waitForLoadingToEnd(timeout: 300)
        }
        step("Prepare ▸ origin and probe, if the file has none") {
            let origin = element("calibration.action.originProbe")
            if origin.waitForExistence(timeout: 10), origin.label.hasPrefix("Calibrate") {
                origin.click()
                waitGone("toolbar.display.busy", timeout: 900)
            }
        }
        step("Prepare ▸ Fit Detector Ellipse, unless the file carries one") {
            let ellipse = element("calibration.action.ellipse")
            if ellipse.waitForExistence(timeout: 5) {
                ellipse.click()
                waitGone("toolbar.display.busy", timeout: 600)
            }
        }
        step("Prepare ▸ Measure R–Q Rotation, if not set") {
            let rotation = element("calibration.action.rotation")
            if rotation.waitForExistence(timeout: 5) {
                rotation.click()
                waitGone("toolbar.display.busy", timeout: 900)
            }
        }
        step("Bragg Disks ▸ detect all disks again (the ellipse changes the patterns)") {
            wait(for: "workspace.braggDisks").click()
            wait(for: "workspace.primaryAction", timeout: 20).click()
            waitGone("toolbar.display.busy", timeout: 1200)
        }
        step("Crystal Maps ▸ Orientation: import the Al CIF as the phase model") {
            wait(for: "workspace.map", timeout: 60).click()
            wait(for: "task.ACOM", timeout: 30).click()
            wait(for: "acom.importCIF", timeout: 20).click()
            choose(file: Self.alCIF)
            wait(for: "acom.phaseModelName", timeout: 20)
        }
        step("Prepare ▸ Q pixel scale ▸ Calibrate from Selected Material") {
            wait(for: "workspace.prepare").click()
            let q = wait(for: "calibration.action.qCrystal", timeout: 20)
            q.click()
            waitGone("toolbar.display.busy", timeout: 300)
        }
        if let q = ProcessInfo.processInfo.environment["PRECIP_Q"] {
            step("Prepare ▸ Q pixel scale ▸ type \(q) by hand") {
                let disclosure = element("calibration.action.qManual.override")
                if disclosure.waitForExistence(timeout: 5) { disclosure.click() }
                let field = wait(for: "calibration.action.qManual", timeout: 10)
                field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(q + "\r")
                _ = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", q)).firstMatch.waitForExistence(timeout: 10)
            }
        }
        step("Crystal Maps ▸ Phase mapping") {
            wait(for: "workspace.map", timeout: 60).click()
            wait(for: "task.Phase mapping", timeout: 30).click()
        }
        step("the phase mapping settings") {
            wait(for: "phaseMapping.run", timeout: 30)
        }
        step("Add Phase ▸ Presets ▸ Al–Mg–Si with the β″ needle CIF") {
            wait(for: "phaseMapping.addPhase").click()
            let preset = app.menuItems["Al–Mg–Si (β″ needles)…"]
            XCTAssertTrue(preset.waitForExistence(timeout: 10), "the Al–Mg–Si preset is not in the Add Phase menu")
            preset.click()
            choose(file: Self.betaCIF)
            wait(for: "phaseMapping.classifierPicker", timeout: 20)
        }
        step("scale the tolerances to this detector (offered under Search only)") {
            pickClassifier("Search")
            wait(for: "phaseMapping.scaleToDetector", timeout: 10).click()
            pickClassifier("Known variants")
        }
        step("Map Phases") {
            let run = wait(for: "phaseMapping.run")
            XCTAssertTrue(run.isEnabled, "Map Phases is disabled after the preset")
            run.click()
            waitGone("toolbar.display.busy", timeout: 900)
        }
        step("the Precipitates section counts objects") {
            wait(for: "precipitates.showObjects", timeout: 120)
            wait(for: "precipitates.variants.section", timeout: 10)
        }
        step("N_V from a thickness") {
            let t = wait(for: "precipitates.nv.thickness")
            t.click(); t.typeKey("a", modifierFlags: .command); t.typeText("50\r")
            sleepless()
        }
        step("Count variants: the legend") {
            wait(for: "precipitates.variants.section").click()
            let legend = element("precipitates.variants.legend"), why = element("precipitates.variants.unavailable")
            XCTAssertTrue(legend.waitForExistence(timeout: 30) || why.exists, "neither a variant legend nor a reason")
        }
        step("objects on the panes") {
            wait(for: "precipitates.overlayOnPanes").click()
        }
        step("the object table") {
            wait(for: "precipitates.table").click()
            XCTAssertTrue(app.windows.count >= 2 || app.tables.firstMatch.waitForExistence(timeout: 20), "no object table")
        }
    }

    /// The open panel: Go to Folder with the absolute path, then Open.
    private func choose(file path: String) {
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 15), "no open panel")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path + "\r")
        app.typeKey(.return, modifierFlags: [])
    }

    private func pickClassifier(_ label: String) {
        wait(for: "phaseMapping.classifierPicker").click()
        let item = app.menuItems[label]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no classifier \(label)")
        item.click()
    }

    /// Lets a typed field commit before the next screenshot (an existence wait on the N_V row, never a delay).
    private func sleepless() {
        _ = element("precipitates.nv.assumption").waitForExistence(timeout: 10)
    }
}
