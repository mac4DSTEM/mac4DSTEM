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

            // Loud, at the top of every affected log: a run without screenshots
            // still proves the numbers, but it is *not* the full acceptance
            // artifact, and nothing downstream should read it as one.
            if OutputLayout.screenshotsDisabled {
                log.note(
                    "\n> **⚠️ SCREENSHOTS DISABLED FOR THIS RUN.** No visual evidence was "
                    + "captured. The numeric findings below are unaffected — they are read "
                    + "from the app's own controls — but this log must **not** be treated as "
                    + "a complete acceptance artifact, and it is not a valid baseline for a "
                    + "visual comparison. Cause: `XCUIScreenshot` runs in the ad-hoc-signed "
                    + "test-runner app, which needs its own Screen & System Audio Recording "
                    + "grant. Delete `.ui-qc-no-screenshots` and grant it to restore.\n"
                )
            }

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
                if app.state == .runningForeground,
                   let attachment = AXDriver(app: app).screenshot(
                       name: "ERROR_state", outputDirectory: outputDirectory
                   ) {
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
            "  (The app's accelerating-voltage field only appears under Reconstruct → "
            + "Ptychography and has no accessibility identifier; step 7 locates it "
            + "structurally by its \"Voltage\" row label and fills it in only if the app "
            + "did not already auto-import `accelerating_voltage` from file metadata.)"
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

        log.section("Routing")
        log.bullet("Pipeline assigned by docs/py4dstem-pipelines.md §6: \(Self.pipelineNote(for: fileName))")
        log.bullet(
            "Steps this run will attempt: virtual imaging → DPC → Bragg disks"
            + (phaseModel == nil ? "" : " → Q-from-crystal → ACOM")
            + " → strain → reconstruct."
        )
        log.note(
            "  (Routing is by *capability gate*, not a fixed per-file script: every dataset "
            + "is offered the full pipeline and each step self-gates on what the app "
            + "actually has — a phase model for ACOM, Bragg vectors for strain, the five "
            + "calibration prerequisites for reconstruct. A skipped step is therefore a "
            + "recorded finding about the app or the data, never a routing decision made "
            + "here to avoid an awkward result.)"
        )

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

        try runDPC()
        attachScreenshot(step: "03b_dpc")
        try exportCurrentResult(filename: "dpc.png")

        try runDiskDetection()
        attachScreenshot(step: "04_disks")
        try exportCurrentResult(filename: "bragg_vector_map.png")

        if let phaseModel {
            try selectPhaseModel(phaseModel)
            try calibrateQFromCrystal(fileName: fileName)
            attachScreenshot(step: "05_calibrated_q")

            try runOrientationMap()
            attachScreenshot(step: "06_orientation_map")
            try exportCurrentResult(filename: "orientation_map.png")

            // Round out ACOM (docs/py4dstem-pipelines.md §3.5): the preview
            // above is a 525-position subset shown as Reliability, whereas
            // py4DSTEM's plot_orientation_maps presents the IPF-colored
            // orientation of every position. Both extras are additive — a
            // failure in either leaves the preview result already exported.
            if try runFullScanOrientationMap() {
                attachScreenshot(step: "06c_orientation_map_full_scan")
                try exportCurrentResult(filename: "orientation_map_full_scan.png")
                log.bullet(ParityRecords.citation(
                    datacubeFileName: fileName, product: "acom"
                ))

                if try showIPFZOrientationMap() {
                    attachScreenshot(step: "06d_orientation_map_ipf_z")
                    try exportCurrentResult(filename: "orientation_map_ipf_z.png")
                }
            }
        }

        // Strain only needs Bragg vectors (docs/py4dstem-pipelines.md §4), so
        // it runs regardless of whether a phase model was available for ACOM.
        if try runStrainMapping() {
            attachScreenshot(step: "06b_strain")
            try exportCurrentResult(filename: "strain_map.png")
            log.bullet(ParityRecords.citation(
                datacubeFileName: fileName, product: "strain"
            ))
        }

        // Parallax/ptychography additionally need R+Q pixel size and the
        // accelerating voltage (§5b); on a dataset missing any of those this
        // self-gates and logs a finding rather than failing the run.
        if try runParallaxReconstruction(hints: hints) {
            attachScreenshot(step: "07_parallax")
            try exportCurrentResult(filename: "parallax_reconstruction.png")
        }

        attachScreenshot(step: "08_results")
    }

    /// The pipeline `docs/py4dstem-pipelines.md` §6 assigns to each training
    /// dataset, for the log. Descriptive only — it records what §6 *expects*
    /// so a reader can compare it against what the run actually achieved; it
    /// never gates a step.
    private static func pipelineNote(for fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("sim_au") {
            return "virtual imaging → disks → calibrate Q from gold → ACOM (200 kV)"
        }
        if lower.contains("ws2") {
            return "disks → calibrate → ACOM + strain (200 kV) — note §9.2.2: the app's "
                + "crystal library has no WS₂ model, so the ACOM half is unavailable"
        }
        if lower.contains("si_sige") || lower.contains("sige") {
            return "disks → origin+rotation → strain (200 kV)"
        }
        if lower.contains("particle_1") {
            return "virtual imaging; disks/strain if crystalline (300 kV)"
        }
        return "not listed in §6 — full pipeline attempted, every step self-gating"
    }

    /// Whether this dataset is *expected* to have its Q calibration refused
    /// because its origin fit is not quantitative (backlog #46).
    ///
    /// This is a per-dataset expectation on purpose. Accepting a refusal from
    /// any dataset would mean a regression that made the gate over-fire —
    /// refusing on `sim_Au_data_all_binned`, whose fit RMS is 0.1616 px against
    /// a 6.1 px probe — produced a green run with a line in the Errors section
    /// nobody reads. That is the repo's own "never widen a gate that fails
    /// silently" lesson turned on the acceptance test itself.
    ///
    /// `downsample_Si_SiGe_exp` fits the origin at RMS 11.66 px against a
    /// 5.03 px probe radius, which is why #46 was found there. If #29 ever
    /// fixes that fit, this entry must come out — and the run failing is the
    /// intended way to find that out.
    private static func expectsQCalibrationRefusal(for fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return lower.contains("si_sige") || lower.contains("sige")
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

    /// DPC (docs/py4dstem-pipelines.md §5a) needs no Bragg detection or
    /// crystal calibration — only energy + geometry, and even those are
    /// optional (ProductWorkflow.prerequisites for .dpc is always empty; a
    /// missing calibration just makes the result qualitative). The app's
    /// default display mode (magnitude, in detector px) needs no voltage at
    /// all, so this runs unconditionally right after Virtual DF.
    private func runDPC() throws {
        log.subsection("3b. DPC (Image)")
        try driver.click("workspace.image")
        try driver.click("task.DPC")
        try driver.click("workspace.primaryAction", timeout: 15)
        try driver.waitForResultTitleContaining("DPC", timeout: 240)
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
    private func calibrateQFromCrystal(fileName: String) throws {
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

        // Two outcomes are now legitimate, and this waits for whichever comes.
        //
        // The app refuses to measure Q from an origin whose fit residual
        // exceeds the probe radius (backlog #46): that origin re-centres every
        // pattern, and on `downsample_Si_SiGe_exp` it produced a scale 2.56×
        // too large stamped "Measured in app". A refusal is therefore the
        // *correct* result on that dataset, not a regression — but it is still
        // a fact this log must state loudly rather than pass over, so it goes
        // through `recordError` and a `note`, exactly like the missing-action
        // path above. Nothing here is an app-behaviour judgement the playthrough
        // makes on its own: it reports which of the two the app chose.
        //
        // The success side keeps its original meaning — the Q row's action
        // controls un-render once the scale is established.
        let manualField = driver.element("calibration.action.qManual")
        let deadline = Date().addingTimeInterval(120)
        var refusal: String?
        while manualField.exists {
            let status = driver.currentStatusText()
            if status.contains("Origin fit RMS") {
                refusal = status
                break
            }
            if Date() > deadline {
                throw QCError(
                    "Timed out after 120s waiting for Q pixel-size calibration to either "
                    + "establish a scale or refuse; last status: \(status)"
                )
            }
            Thread.sleep(forTimeInterval: 0.3)
        }

        let expectedRefusal = Self.expectsQCalibrationRefusal(for: fileName)
        switch (refusal, expectedRefusal) {
        case (let refusal?, true):
            log.recordError(
                "Q calibration was refused because the origin fit is not quantitative — "
                + refusal
            )
            log.note(
                "\n**UNCALIBRATED Q (refused, expected)** — the app declined to derive a Q "
                + "pixel size from an origin it had already flagged, so orientation results "
                + "ran in the exploratory pixel-scale mode instead of carrying a wrong scale "
                + "labelled \"Measured in app\" (backlog #46). Virtual DF is unaffected. The "
                + "remedy is in the refusal: try another Origin fit and re-run Calibrate "
                + "Origin, or set Q manually.\n"
            )
        case (let refusal?, false):
            // Over-firing is a worse failure than the defect: it withholds a
            // calibration that was fine. It fails the dataset rather than
            // leaving a line in a section nobody reads.
            throw QCError(
                "Q calibration was refused on a dataset whose origin fit is expected to be "
                + "usable — the #46 gate is over-firing. Status: \(refusal)"
            )
        case (nil, true):
            throw QCError(
                "Q calibration succeeded on a dataset whose origin fit is expected to be "
                + "unusable. Either the origin fit improved (update "
                + "`expectsQCalibrationRefusal`) or the #46 gate has stopped firing."
            )
        case (nil, false):
            break
        }
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

    /// Re-runs ACOM at **full-scan** scope, so every scan position is matched
    /// rather than the preview's 32×32-sampled subset
    /// (`UI/ACOMControlsView.swift:129`). `acom.scope` carries an accessibility
    /// identifier but is a `.segmented` Picker, i.e. an AXRadioGroup whose
    /// selection is not readable as text — so the option is chosen by clicking
    /// the segment carrying its visible label, and the *result* is what
    /// confirms the switch took effect.
    ///
    /// Returns whether a full-scan map published, so the caller knows whether
    /// there is something to export. A failure here is logged, not thrown: the
    /// preview map is already exported, and losing the extras must not cost the
    /// rest of the datacube's run.
    private func runFullScanOrientationMap() throws -> Bool {
        log.subsection("6c. Full-scan orientation map (ACOM)")
        try driver.click("workspace.map")
        try driver.click("task.ACOM")
        _ = try driver.waitForExistence("acom.scope", timeout: 20)

        do {
            try driver.selectSegment(in: "acom.scope", optionLabel: "Full scan")
        } catch {
            log.recordError("Could not select the ACOM full-scan scope: \(error)")
            log.note(
                "\n**Full-scan ACOM skipped** — the `acom.scope` segmented control did not "
                + "expose a clickable \"Full scan\" segment. Preview-scope ACOM is unaffected "
                + "and already exported.\n"
            )
            return false
        }
        log.bullet("Scope set to \"Full scan\" (was Preview)")
        for line in driver.acomWorkEstimateText() { log.bullet("  \(line)") }

        try driver.click("workspace.primaryAction", timeout: 15)
        do {
            // A full-scan title drops the scope qualifier ("ACOM · Reliability"
            // vs "ACOM preview · Reliability"), so the absence of "preview" is
            // the signal that the new run replaced the old result.
            try driver.waitForResultTitle(
                containing: "ACOM", notContaining: "preview", timeout: 900
            )
            log.bullet("Result: \(driver.currentStatusText())")
            return true
        } catch {
            log.recordError("Full-scan ACOM did not complete: \(error)")
            if let alert = driver.dismissErrorAlertIfPresent() {
                log.bullet("App error alert: \(alert)")
            }
            return false
        }
    }

    /// Switches the ACOM result to **IPF · Z** orientation coloring — the
    /// display py4DSTEM's `plot_orientation_maps` leads with (§3.5), as opposed
    /// to the Reliability map the earlier steps export.
    ///
    /// The display-mode picker now carries the `acom.display` identifier
    /// (added 2026-08-04, backlog #3), but this lookup deliberately stays on
    /// the current-value route: it is the fallback that found the gap, and it
    /// keeps working if the identifier regresses.
    private func showIPFZOrientationMap() throws -> Bool {
        log.subsection("6d. IPF · Z orientation coloring (ACOM)")
        // The export step above left us on Results; the picker lives under Map.
        try driver.click("workspace.map")
        try driver.click("task.ACOM")

        let modeLabels = Set(Self.acomDisplayModeLabels)
        guard let picker = driver.control(.popUpButton, showingOneOf: modeLabels, timeout: 15) else {
            log.recordError(
                "ACOM display-mode picker could not be located. It has no accessibility "
                + "identifier, and neither its current value nor its \"Display\" label "
                + "resolved to a reachable control."
            )
            log.note(
                "\n**IPF · Z skipped — finding.** The ACOM display mode is not reachable "
                + "through the UI for automation, so the orientation coloring py4DSTEM leads "
                + "with cannot be captured. Not fixed here: eval-only. "
                + "See docs/ui-workflow-backlog.md.\n"
            )
            return false
        }
        log.bullet("Display mode before: \(AXDriver.bestText(picker))")

        do {
            try driver.selectMenuOption(in: picker, optionLabel: Self.ipfZLabel)
        } catch {
            log.recordError("Could not select the \"\(Self.ipfZLabel)\" display mode: \(error)")
            return false
        }
        do {
            try driver.waitForResultTitle(containing: "IPF", notContaining: nil, timeout: 120)
            // The result title is the evidence here, not the status bar: no new
            // compute runs (switching display re-renders the existing map via
            // AppState.applyACOMDisplay), so the status bar still shows whatever
            // the previous step left there.
            log.bullet(
                "Displayed product: \(driver.readValueText("result.title")) "
                + "— RGBA orientation coloring, not a scalar map, so it carries an IPF "
                + "legend instead of a colorbar."
            )
            log.bullet("Status bar (unchanged — no recompute): \(driver.currentStatusText())")
            return true
        } catch {
            log.recordError("IPF · Z display did not appear: \(error)")
            if let alert = driver.dismissErrorAlertIfPresent() {
                log.bullet("App error alert: \(alert)")
            }
            return false
        }
    }

    /// `ACOMDisplayMode` raw values (`App/ACOMWorkflow.swift:4`). Duplicated
    /// here because the test target does not link the app's types; kept in one
    /// place so a rename shows up as one failing lookup, not several.
    private static let acomDisplayModeLabels = [
        "IPF · Z", "Reliability", "Symmetry FZ angle", "In-plane angle",
        "Euler φ₁", "Euler Φ", "Euler φ₂", "Score",
    ]
    private static let ipfZLabel = "IPF · Z"

    /// Strain (docs/py4dstem-pipelines.md §4) only needs detected Bragg
    /// vectors — origin/rotation help but aren't a hard prerequisite
    /// (ProductWorkflow.prerequisites for .strain only checks
    /// hasBraggVectors). The app defaults to whole-scan reference and
    /// automatic basis-vector selection, which is exactly what py4DSTEM's
    /// basics_04 tutorial does when no ROI is chosen, so this test leaves
    /// both pickers at their defaults rather than driving them (neither has
    /// an accessibility identifier — see docs/ui-workflow-backlog.md).
    ///
    /// Whole-scan automatic basis fitting is a genuine per-dataset scientific
    /// outcome, not just an automation risk: on messier real data it can fail
    /// to find a well-conditioned lattice (confirmed on
    /// downsample_Si_SiGe_exp — see docs/py4dstem-pipelines.md §7 finding #6,
    /// reference/basis choice). That failure is logged as a finding rather
    /// than thrown, so it doesn't abort the rest of this datacube's run
    /// (in particular, so Parallax still gets a chance to run afterward).
    /// Returns whether a strain map actually published (so the caller knows
    /// whether there is a result to export).
    private func runStrainMapping() throws -> Bool {
        log.subsection("6b. Strain mapping (Map)")
        try driver.click("workspace.map")
        try driver.click("task.Strain")
        _ = try driver.waitForExistence("workspace.primaryAction", timeout: 20)

        // Both pickers are identifier-free, so read them off the screen the way
        // a person would (see AXDriver.control(_:inRowWithLabel:)). Read, don't
        // change: the defaults (whole-scan mean + automatic basis) are exactly
        // what py4DSTEM's basics_04 does when no ROI is chosen, and picking a
        // reference ROI or hand-entering g₁/g₂ would be the test inventing a
        // scientific choice rather than evaluating the app's own default path.
        let reference = driver.control(.popUpButton, inRowWithLabel: "Reference")
        let basis = driver.control(.popUpButton, inRowWithLabel: "Basis")
        log.bullet(
            "Reference: \(driver.text(of: reference)) · Basis: \(driver.text(of: basis)) "
            + "— both left at the app defaults"
        )

        try driver.click("workspace.primaryAction", timeout: 15)
        do {
            try driver.waitForResultTitleContaining("Strain", timeout: 300)
            log.bullet("Result: \(driver.currentStatusText())")
            let component = driver.control(.popUpButton, inRowWithLabel: "Component")
            log.bullet(
                "Displayed strain component: \(driver.text(of: component)) "
                + "— this is the component exported below."
            )
            for line in driver.strainDiagnosticsText() { log.bullet("  \(line)") }
            return true
        } catch {
            log.recordError("Strain mapping did not complete: \(error)")
            // A publish failure surfaces as a blocking "Something went wrong"
            // sheet that would otherwise swallow every later click.
            let alert = driver.dismissErrorAlertIfPresent()
            if let alert { log.bullet("App error alert: \(alert)") }
            log.note(
                "\n**Strain skipped** — whole-scan automatic basis fitting did not converge "
                + "on this dataset (see error above). The app's own remedy text points at the "
                + "Bragg thresholds or the reference/basis selection; this test deliberately "
                + "does not tune either, because both are scientific choices the *user* makes "
                + "(see docs/ui-workflow-backlog.md).\n"
            )
            return false
        }
    }

    /// Parallax/ptychography (docs/py4dstem-pipelines.md §5b/§5c) is driven
    /// entirely through `workspace.primaryAction`, which advances through
    /// "Prepare Preview" -> "Align Next Level" (repeated once per
    /// coarse-to-fine bin) -> "Fit Aberrations" -> "Correct Phase" ->
    /// "Upsample BF" -> disabled "Reconstruction Ready". Unlike the Prepare
    /// origin/rotation loop, the SAME label can legitimately reappear across
    /// several clicks (one bin level per "Align Next Level" click), so this
    /// waits out each busy cycle rather than waiting for the label to change.
    ///
    /// Requires fitted origin + rotation + R and Q pixel size + accelerating
    /// voltage (ProductWorkflow.prerequisites for .ptychography). Voltage is
    /// the one this step can supply itself (see setAcceleratingVoltage); the
    /// other four come from Prepare. On a dataset missing any of them the
    /// primary action renders but stays disabled, so this dumps the
    /// calibration panel — which names the actual culprit — and treats it as a
    /// skip rather than a hard failure. Measured outcome: none of the four
    /// training datasets satisfies all five, and the missing item differs per
    /// dataset (docs/py4dstem-pipelines.md §9.2, backlog #7).
    /// Returns whether any stage actually ran (so the caller knows whether
    /// there is a result to export).
    private func runParallaxReconstruction(hints: DatacubeFilenameCalibration.Hints) throws -> Bool {
        log.subsection("7. Parallax reconstruction (Reconstruct)")
        try driver.click("workspace.reconstruct")
        try driver.click("task.Ptycho")
        _ = try driver.waitForExistence("workspace.primaryAction", timeout: 20)

        try setAcceleratingVoltage(hints: hints)

        let stageWhitelist: Set<String> = [
            "Prepare Preview", "Align Next Level", "Fit Aberrations",
            "Correct Phase", "Upsample BF",
        ]
        var ranStages: [String] = []
        var guardCount = 0
        while guardCount < 12 {
            guardCount += 1
            let primaryAction = driver.element("workspace.primaryAction")
            guard primaryAction.waitForExistence(timeout: 10) else { break }
            let label = AXDriver.bestText(primaryAction)
            guard stageWhitelist.contains(label) else { break }
            guard primaryAction.isEnabled else {
                log.bullet(
                    "Reconstruct primary action (\"\(label)\") is disabled — a required "
                    + "prerequisite (fitted origin, R–Q rotation, R or Q pixel size, or "
                    + "accelerating voltage) is missing for this dataset. Calibration panel "
                    + "state at this point:"
                )
                try driver.click("workspace.prepare")
                for line in driver.calibrationPanelText() { log.bullet("  \(line)") }
                // Back to Reconstruct so the run's closing screenshot shows the
                // dead end itself rather than the panel we detoured to read.
                try driver.click("workspace.reconstruct")
                break
            }
            try driver.click("workspace.primaryAction", timeout: 15)
            ranStages.append(label)
            log.bullet("Ran \"\(label)\"")
            try driver.waitForPrimaryActionBusyCycle(timeout: 300, describing: "\"\(label)\" to finish")
        }

        guard !ranStages.isEmpty else {
            log.note(
                "\n**Parallax reconstruction skipped** — primary action never became "
                + "available for this dataset (see prerequisite note above).\n"
            )
            return false
        }
        log.bullet("Ran stages: \(ranStages.joined(separator: " → "))")
        log.bullet("Result: \(driver.currentStatusText())")
        return true
    }

    /// Accelerating voltage is a hard prerequisite for parallax/ptychography
    /// (`ProductWorkflow.prerequisites` for `.ptychography`) and py4DSTEM
    /// passes it straight into the constructor (docs/py4dstem-pipelines.md
    /// §5a–c). In the app it is a bare `TextField` under Reconstruct →
    /// Ptychography with **no accessibility identifier**
    /// (`UI/ContentView.swift:344`) — its row label is a separate
    /// `Text("Voltage")`, so this locates it structurally by that label rather
    /// than adding an identifier to app code (which eval-only forbids).
    ///
    /// The app auto-imports `accelerating_voltage` from file metadata when the
    /// H5 carries it, so this only types a value when the field reads empty/0,
    /// and always logs which of the two supplied the number.
    private func setAcceleratingVoltage(hints: DatacubeFilenameCalibration.Hints) throws {
        guard let field = driver.control(.textField, inRowWithLabel: "Voltage") else {
            log.recordError(
                "Accelerating-voltage field could not be located under Reconstruct → "
                + "Ptychography, even structurally by its \"Voltage\" row label. Parallax/"
                + "ptychography cannot be driven without it."
            )
            log.note(
                "\n**Finding — kV is unreachable to automation.** The field has no "
                + "accessibility identifier (docs/py4dstem-pipelines.md §7.4). Not added "
                + "here: eval-only. See docs/ui-workflow-backlog.md.\n"
            )
            return
        }
        let imported = AXDriver.bestText(field)
        let importedValue = Double(imported.replacingOccurrences(of: ",", with: "."))
        if let importedValue, importedValue > 0 {
            log.bullet(
                "Accelerating voltage already set to \(imported) kV — auto-imported by the "
                + "app from the file's `accelerating_voltage` metadata. Left as-is."
            )
            return
        }
        let kV = hints.acceleratingVoltageKV
        try driver.typeAndCommit(element: field, text: String(format: "%.0f", kV))
        log.bullet(
            "Entered accelerating voltage \(String(format: "%.0f", kV)) kV — source: "
            + "\(hints.voltageSource). The field was empty, i.e. the file carried no "
            + "`accelerating_voltage` metadata. Field now reads: "
            + "\(AXDriver.bestText(field))"
        )
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
        guard let attachment = driver.screenshot(name: step, outputDirectory: outputDirectory)
        else {
            log.bullet("_(screenshot skipped at \"\(step)\" — screenshots disabled for this run)_")
            return
        }
        testCase.add(attachment)
        log.recordScreenshot(step: step, fileName: "\(step).png")
    }
}
