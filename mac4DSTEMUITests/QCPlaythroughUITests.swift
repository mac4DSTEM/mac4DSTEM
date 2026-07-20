import XCTest

/// Visible, on-screen QC playthrough of the real app across every datacube
/// in References/training_dataset. This is evaluation tooling only: it
/// drives mac4DSTEM through its existing UI (accessibility identifiers
/// already used by tools/ui-smoke-test) and records what happened — it does
/// not modify app logic.
///
/// Per datacube: load → calibrate (standard Prepare-stage actions only) →
/// orientation map (ACOM, preview scope) → virtual DF, screenshotting each
/// step, exporting the orientation map and virtual DF images, and writing a
/// markdown log to References/training_runs/run_<timestamp>/<datacube>/.
///
/// A failure loading a datacube or running one of its steps is logged and
/// that datacube is abandoned in favor of the next one — one bad file never
/// aborts the whole run.
final class QCPlaythroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testQCPlaythroughAllDatacubes() throws {
        let datacubes = try OutputLayout.discoverDatacubes()
        guard !datacubes.isEmpty else {
            XCTFail("No .h5 files found in \(OutputLayout.datasetDirectory.path)")
            return
        }

        let runDirectory = try OutputLayout.makeRunDirectory(timestamp: Self.runTimestamp())
        print("QC playthrough run directory: \(runDirectory.path)")

        var currentApp: XCUIApplication?
        var failedDatacubes: [String] = []

        for datacubeURL in datacubes {
            let baseName = datacubeURL.deletingPathExtension().lastPathComponent
            print("QC playthrough — starting \(datacubeURL.lastPathComponent)")

            let outputDirectory: URL
            do {
                outputDirectory = try OutputLayout.makeDatacubeDirectory(
                    in: runDirectory, datacubeBaseName: baseName
                )
            } catch {
                XCTFail("Could not create output directory for \(baseName): \(error)")
                failedDatacubes.append(baseName)
                continue
            }

            let log = RunLog(datacubeFileName: datacubeURL.lastPathComponent, sourceURL: datacubeURL)

            currentApp?.terminate()
            let app = XCUIApplication()
            currentApp = app
            app.launch()

            do {
                let workflow = QCWorkflow(
                    app: app, testCase: self, outputDirectory: outputDirectory, log: log
                )
                try workflow.run(datacubeURL: datacubeURL)
            } catch {
                let message = "\(error)"
                log.recordError(message)
                if app.state == .runningForeground {
                    let attachment = AXDriver(app: app).screenshot(
                        name: "ERROR_state", outputDirectory: outputDirectory
                    )
                    self.add(attachment)
                    log.recordScreenshot(step: "on failure", fileName: "ERROR_state.png")
                }
                XCTFail("Datacube \(baseName) failed: \(message)")
                failedDatacubes.append(baseName)
            }

            log.write(to: outputDirectory.appendingPathComponent("log.md"))
            print("QC playthrough — finished \(datacubeURL.lastPathComponent), log at "
                + outputDirectory.appendingPathComponent("log.md").path)
        }

        currentApp?.terminate()

        if !failedDatacubes.isEmpty {
            XCTFail(
                "\(failedDatacubes.count) of \(datacubes.count) datacube(s) failed: "
                    + failedDatacubes.joined(separator: ", ")
                    + " — see per-datacube log.md under \(runDirectory.path)"
            )
        }
    }

    private static func runTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

/// Drives one datacube through the standard workflow. Stateless aside from
/// its constructor arguments — a fresh instance per datacube keeps failures
/// from one file from leaking state into the next.
private struct QCWorkflow {
    let app: XCUIApplication
    let testCase: XCTestCase
    let outputDirectory: URL
    let log: RunLog

    private var driver: AXDriver { AXDriver(app: app) }

    func run(datacubeURL: URL) throws {
        let fileName = datacubeURL.lastPathComponent
        let hints = DatacubeFilenameCalibration.parse(fileName: fileName)

        log.section("Calibration")
        log.bullet("Accelerating voltage assumption: \(hints.acceleratingVoltageKV) kV — source: \(hints.voltageSource)")
        log.note(
            "  (Not entered into the UI: the app's own accelerating-voltage field only "
            + "appears under Reconstruct → Ptychography, outside this workflow's scope. "
            + "Recorded here for reference; the app separately auto-imports "
            + "`accelerating_voltage` from file metadata into the same field when present.)"
        )
        if let scanStep = hints.scanStepNM {
            log.bullet("Filename scan-step token: \(scanStep) nm (candidate r-space pixel size)")
        }
        if let cameraLength = hints.cameraLengthMM {
            log.bullet(
                "Filename camera-length token: \(cameraLength) mm — constrains q-space pixel size "
                + "together with kV, but not enough on its own (no detector-pixel-pitch constant "
                + "available here); not injected."
            )
        }

        let phaseModel = Self.phaseModel(for: fileName)
        if let phaseModel {
            log.bullet("Crystal phase model for this dataset: \"\(phaseModel)\" "
                + "(matches the py4DSTEM tutorial standard for this sample)")
        } else {
            log.bullet("No known library phase model for this dataset — ACOM will be skipped.")
        }

        // Canonical crystalline (Bragg) pipeline, in the app's own Prepare→Map
        // order (see docs/py4dstem-pipelines.md §3). The app measures origin &
        // rotation independently, so those run first in Prepare; disk
        // detection and phase-model selection then unlock the Q-from-crystal
        // pixel-size calibration and ACOM.
        try loadDataset(at: datacubeURL)
        attachScreenshot(step: "01_loaded")

        try calibrateOriginRotation(hints: hints)
        attachScreenshot(step: "02_calibrated_origin_rotation")

        try runVirtualDF()
        attachScreenshot(step: "03_virtual_df")
        try exportCurrentResult(filename: "virtual_df.png")

        try runDiskDetection()
        attachScreenshot(step: "04_disks")
        try exportCurrentResult(filename: "bragg_vector_map.png")

        if let phaseModel {
            try selectPhaseModel(phaseModel)
            try calibrateQFromCrystal()
            attachScreenshot(step: "05_calibrated_q")

            try runOrientationMap()
            attachScreenshot(step: "06_orientation_map")
            try exportCurrentResult(filename: "orientation_map.png")
        }

        attachScreenshot(step: "07_results")
    }

    /// Library phase model (matching the app's ACOM material picker labels)
    /// for datasets whose structure is known from the py4DSTEM tutorials.
    private static func phaseModel(for fileName: String) -> String? {
        let lower = fileName.lowercased()
        if lower.contains("sim_au") || lower.contains("_au_") { return "Gold (FCC)" }
        if lower.contains("si_sige") || lower.contains("sige") { return "Silicon (diamond)" }
        return nil
    }

    // MARK: - Steps

    private func loadDataset(at url: URL) throws {
        log.section("Steps")
        log.subsection("1. Load datacube")
        do {
            try driver.openDataset(at: url.path)
        } catch {
            log.recordError("Failed to load \(url.lastPathComponent): \(error)")
            throw error
        }
        log.bullet("Status: \(driver.currentStatusText())")
    }

    private func calibrateOriginRotation(hints: DatacubeFilenameCalibration.Hints) throws {
        log.subsection("2. Calibrate origin & rotation (Prepare)")

        try driver.click("workspace.prepare")
        _ = try driver.waitForExistence("calibration.readiness", timeout: 20)

        log.bullet("As imported (before any calibration action) — calibration panel text:")
        for line in driver.calibrationPanelText() { log.bullet("  \(line)") }

        // Drive the single "Calibrate Origin" -> "Calibrate Rotation" ->
        // (nothing left) sequence through workspace.primaryAction itself,
        // the same button a person would click, reading its label each time
        // for the log. Real datasets can take well over a minute per step.
        let primaryAction = driver.element("workspace.primaryAction")
        var guardCount = 0
        while primaryAction.waitForExistence(timeout: 5), guardCount < 4 {
            guardCount += 1
            let label = AXDriver.bestText(primaryAction)
            guard label == "Calibrate Origin" || label == "Calibrate Rotation" else { break }
            try driver.click("workspace.primaryAction", timeout: 15)
            log.bullet("Ran \"\(label)\"")
            try driver.waitForPrimaryActionChange(
                from: label, timeout: 300, describing: "\"\(label)\" to finish"
            )
        }

        // R-space is the one filename-derived value the spec explicitly
        // authorizes typing in ("ss30nm" names a scan step directly). The
        // manual field only renders while R pixel scale is not yet ready, so
        // its mere presence is enough to decide whether to fill it in.
        if let scanStep = hints.scanStepNM,
           driver.element("calibration.action.rManual").waitForExistence(timeout: 5) {
            try driver.typeAndCommit("calibration.action.rManual", text: String(scanStep))
            log.bullet(
                "Entered manual R pixel scale \(scanStep) nm/px — source: filename scan-step token "
                + "(\"ss\(Int(scanStep))nm\" or equivalent)"
            )
        }

        log.bullet("After origin/rotation calibration — calibration panel text:")
        for line in driver.calibrationPanelText() { log.bullet("  \(line)") }
    }

    private func runVirtualDF() throws {
        log.subsection("3. Virtual DF (Image)")
        try driver.click("workspace.image")
        try driver.click("task.Virtual Det")
        try driver.click("workspace.primaryAction", timeout: 15)
        try driver.waitForResultTitleContaining("Virtual detector", timeout: 240)
        log.bullet("Result: \(driver.currentStatusText())")
    }

    private func runDiskDetection() throws {
        log.subsection("4. Bragg disk detection (Map)")
        try driver.click("workspace.map")
        try driver.click("task.Disks")
        try driver.click("workspace.primaryAction", timeout: 15)
        try driver.waitForResultTitleContaining("Bragg vector map", timeout: 400)
        log.bullet("Detected disks — result: \(driver.currentStatusText())")
    }

    private func selectPhaseModel(_ phaseModel: String) throws {
        log.subsection("5. Select crystal phase model (ACOM)")
        // The prior export step left us on the Results workspace, which has
        // no task buttons; ACOM's controls live under Map.
        try driver.click("workspace.map")
        try driver.click("task.ACOM")
        _ = try driver.waitForExistence("acom.material", timeout: 20)
        try driver.selectMenuOption(picker: "acom.material", optionLabel: phaseModel)
        log.bullet("Selected phase model: \(driver.readValueText("acom.material"))")
    }

    /// Pixel-size (Q) calibration by matching detected Bragg peaks to the
    /// selected crystal's structure factors — the canonical py4DSTEM method
    /// (docs/py4dstem-pipelines.md §2.8). Requires disks + a phase model, so
    /// the app only renders `calibration.action.qCrystal` once both exist.
    private func calibrateQFromCrystal() throws {
        log.subsection("5b. Calibrate Q pixel size from crystal (Prepare)")
        try driver.click("workspace.prepare")
        _ = try driver.waitForExistence("calibration.readiness", timeout: 20)

        guard driver.element("calibration.action.qCrystal").waitForExistence(timeout: 8) else {
            log.recordError(
                "\"Calibrate Q from Selected Material\" action did not appear even after "
                + "disk detection + phase-model selection — Q pixel size left uncalibrated."
            )
            log.note(
                "\n**UNCALIBRATED Q** — orientation results ran in the app's exploratory "
                + "pixel-scale mode. Virtual DF is unaffected.\n"
            )
            return
        }
        try driver.click("calibration.action.qCrystal", timeout: 10)
        log.bullet("Ran \"Calibrate Q from Selected Material\"")
        // Q row's action controls un-render once the scale is established.
        try driver.waitForDisappearance(
            "calibration.action.qManual", timeout: 120, describing: "Q pixel-size calibration"
        )
        log.bullet("After Q calibration — calibration panel text:")
        for line in driver.calibrationPanelText() { log.bullet("  \(line)") }
    }

    private func runOrientationMap() throws {
        log.subsection("6. Orientation map (ACOM)")
        try driver.click("workspace.map")
        try driver.click("task.ACOM")
        _ = try driver.waitForExistence("acom.scope", timeout: 20)

        log.bullet("Phase model: \(driver.readValueText("acom.material"))")
        log.bullet("Scope: Preview (app default; not changed by this test)")

        try driver.click("workspace.primaryAction", timeout: 15)
        try driver.waitForResultTitleContaining("ACOM", timeout: 600)
        log.bullet("Result: \(driver.currentStatusText())")
    }

    private func exportCurrentResult(filename: String) throws {
        try driver.click("workspace.results")
        _ = try driver.waitForExistence("result.exportPNG", timeout: 20)
        do {
            try driver.exportCurrentResultPNG(filename: filename, directory: outputDirectory)
            log.recordExport(fileName: filename)
        } catch {
            log.recordError("Export of \(filename) failed: \(error)")
            throw error
        }
    }

    // MARK: - Helpers

    private func attachScreenshot(step: String) {
        let attachment = driver.screenshot(name: step, outputDirectory: outputDirectory)
        testCase.add(attachment)
        log.recordScreenshot(step: step, fileName: "\(step).png")
    }
}
