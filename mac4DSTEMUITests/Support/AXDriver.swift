import XCTest

/// QC-playthrough-only error. Thrown for any step that fails or times out;
/// the caller catches these per-datacube and moves on to the next file.
struct QCError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Thin wrapper over XCUITest that drives mac4DSTEM through its existing
/// accessibility identifiers (see UI/*.swift `.accessibilityIdentifier(...)`
/// call sites). Mirrors the interaction patterns already proven in
/// tools/ui-smoke-test/*.applescript (Cmd+O / Cmd+Shift+G file panel
/// navigation, poll-for-identifier waits) so this test rides the same
/// well-understood accessibility surface rather than inventing a new one.
///
/// No method here changes app state beyond what a person clicking the same
/// controls would do.
struct AXDriver {
    let app: XCUIApplication

    /// Pause between actions purely so a human watching the screen can
    /// follow each step instead of seeing a blur of clicks.
    static let stepPause: TimeInterval = 0.7

    func pause(_ seconds: TimeInterval = AXDriver.stepPause) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Best-effort text for a control's current value (e.g. a Picker's
    /// selected option), for logging only — never used to drive a decision.
    func readValueText(_ identifier: String) -> String {
        let el = element(identifier)
        guard el.exists else { return "(not present)" }
        return Self.bestText(el)
    }

    /// macOS static-text elements commonly carry their content in AXValue
    /// rather than AXTitle — `.label` alone reads empty for many SwiftUI
    /// `Text` views here, so value is tried first everywhere text is read.
    static func bestText(_ el: XCUIElement) -> String {
        if let value = el.value as? String, !value.isEmpty { return value }
        if !el.label.isEmpty { return el.label }
        return ""
    }

    @discardableResult
    func waitForExistence(
        _ identifier: String, timeout: TimeInterval, describing description: String? = nil
    ) throws -> XCUIElement {
        let el = element(identifier)
        guard el.waitForExistence(timeout: timeout) else {
            throw QCError("Timed out after \(Int(timeout))s waiting for \(description ?? identifier)")
        }
        return el
    }

    /// Waits until `identifier`'s label differs from `previousLabel` (a new
    /// step became available) or the element disappears (nothing left to
    /// do). Used to drive `workspace.primaryAction` through Prepare's
    /// "Calibrate Origin" → "Calibrate Rotation" → (gone) sequence without
    /// racing a freshly-clicked button's own identifier re-attaching.
    func waitForPrimaryActionChange(
        from previousLabel: String, timeout: TimeInterval, describing description: String
    ) throws {
        let el = element("workspace.primaryAction")
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !el.exists { return }
            if Self.bestText(el) != previousLabel { return }
            if Date() > deadline {
                throw QCError("Timed out after \(Int(timeout))s waiting for \(description)")
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    /// Waits out one click's busy cycle on `workspace.primaryAction` without
    /// caring whether its label changes — some stages (parallax "Align Next
    /// Level" advances one bin level per click, so the SAME label can
    /// legitimately reappear several times before the label finally
    /// advances). First tolerates the button vanishing while the op runs
    /// (best-effort; a very fast op may never be observed missing), then
    /// waits for it to come back, which is when the app is idle again.
    func waitForPrimaryActionBusyCycle(timeout: TimeInterval, describing description: String) throws {
        let el = element("workspace.primaryAction")
        let disappearDeadline = Date().addingTimeInterval(3)
        while el.exists, Date() < disappearDeadline {
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard el.waitForExistence(timeout: timeout) else {
            throw QCError("Timed out after \(Int(timeout))s waiting for \(description)")
        }
    }

    /// Dismisses the app's "Something went wrong" error alert if one is on
    /// screen. `AppState.present(error:)` blocks the rest of the UI behind a
    /// modal until acknowledged, so any step that can genuinely fail at
    /// runtime (not just time out waiting for a result) needs to clear this
    /// before the workflow can click anything else — confirmed by a real
    /// failure where a strain-computation error left this alert up and the
    /// next click (switching workspaces) was silently swallowed by it.
    func dismissErrorAlertIfPresent(timeout: TimeInterval = 3) {
        let okButton = app.buttons["OK"]
        guard okButton.waitForExistence(timeout: timeout) else { return }
        okButton.click()
        pause()
    }

    func waitForDisappearance(
        _ identifier: String, timeout: TimeInterval, describing description: String? = nil
    ) throws {
        let el = element(identifier)
        let deadline = Date().addingTimeInterval(timeout)
        while el.exists {
            if Date() > deadline {
                throw QCError(
                    "Timed out after \(Int(timeout))s waiting for \(description ?? identifier) to finish"
                )
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    @discardableResult
    func click(_ identifier: String, timeout: TimeInterval = 15) throws -> XCUIElement {
        app.activate()
        let el = try waitForExistence(identifier, timeout: timeout)
        guard el.isHittable else {
            throw QCError("Element \(identifier) exists but is not hittable")
        }
        el.click()
        pause()
        return el
    }

    /// Selects all existing text in a field and replaces it, committing with
    /// Tab so SwiftUI's `.number` formatter parses the value immediately.
    func typeAndCommit(_ identifier: String, text: String, timeout: TimeInterval = 10) throws {
        let el = try click(identifier, timeout: timeout)
        el.typeKey("a", modifierFlags: .command)
        el.typeText(text)
        el.typeKey(.tab, modifierFlags: [])
        pause()
    }

    /// Selects an option from a SwiftUI menu-style `Picker` (rendered as an
    /// AXPopUpButton on macOS): click the picker, then click the menu item
    /// whose title matches `optionLabel`.
    func selectMenuOption(picker identifier: String, optionLabel: String, timeout: TimeInterval = 10) throws {
        try click(identifier, timeout: timeout)
        pause(0.5)
        let item = app.menuItems[optionLabel]
        guard item.waitForExistence(timeout: 5) else {
            // Dismiss the open menu before surfacing the failure.
            app.typeKey(.escape, modifierFlags: [])
            throw QCError("Menu option \"\(optionLabel)\" not found in picker \(identifier)")
        }
        item.click()
        pause()
    }

    // MARK: - File → Open… (NSOpenPanel via fileImporter)

    /// Cmd+O, then Cmd+Shift+G "Go to the folder" navigation typed with the
    /// full absolute file path (not just a directory) — NSOpenPanel resolves
    /// a file path there directly to that file, pre-selected. Matches
    /// tools/ui-smoke-test/import-real.applescript's proven sequence.
    func openDataset(at path: String, datasetCardTimeout: TimeInterval = 240) throws {
        guard app.windows.firstMatch.waitForExistence(timeout: 30) else {
            throw QCError("App window never appeared after launch")
        }
        app.activate()
        pause(0.5)
        app.typeKey("o", modifierFlags: .command)
        pause(1.5)
        app.typeKey("g", modifierFlags: [.command, .shift])
        pause(1.0)
        app.typeText(path)
        app.typeKey(.enter, modifierFlags: [])
        pause(2.0)
        app.typeKey(.enter, modifierFlags: [])
        try waitForExistence("dataset.card", timeout: datasetCardTimeout, describing: "dataset.card after opening \(path)")
    }

    // MARK: - Export PNG (NSSavePanel)

    /// Clicks `result.exportPNG` (caller must already be on the Results
    /// workspace with a computed result showing) and drives the resulting
    /// NSSavePanel: rename to `filename`, navigate to `directory` via
    /// Cmd+Shift+G, confirm. Mirrors
    /// tools/ui-smoke-test/session-save.applescript's save-panel sequence.
    func exportCurrentResultPNG(filename: String, directory: URL) throws {
        try click("result.exportPNG", timeout: 20)
        pause(1.0)
        app.typeKey("a", modifierFlags: .command)
        app.typeText(filename)
        pause(0.3)
        app.typeKey("g", modifierFlags: [.command, .shift])
        pause(1.0)
        app.typeText(directory.path)
        app.typeKey(.enter, modifierFlags: [])
        pause(1.5)
        app.typeKey(.enter, modifierFlags: [])
        pause(1.5)

        let expected = directory.appendingPathComponent(filename)
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: expected.path) {
            if Date() > deadline {
                throw QCError("PNG export did not appear at \(expected.path) within 20s")
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - Result readiness

    /// Polls `result.title` for `substring`, falling back to reading the
    /// status bar for a diagnostic message on timeout — same strategy as
    /// tools/ui-smoke-test/smoke.applescript's waitForResultContaining.
    func waitForResultTitleContaining(_ substring: String, timeout: TimeInterval) throws {
        let titleElement = element("result.title")
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            // macOS static text carries its content in AXValue, not AXTitle,
            // so read value-first (bestText) rather than .label, which is
            // empty here.
            if titleElement.exists,
               Self.bestText(titleElement).localizedCaseInsensitiveContains(substring) {
                return
            }
            if Date() > deadline {
                throw QCError(
                    "Timed out after \(Int(timeout))s waiting for result title containing "
                        + "\"\(substring)\" — last status: \(currentStatusText())"
                )
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    func currentStatusText() -> String {
        let status = element("status.bar")
        return status.exists ? Self.bestText(status) : "(status bar not found)"
    }

    // MARK: - Calibration readiness reading

    /// The five readiness rows (`calibration.item.*`) are each their own
    /// `.accessibilityElement(children: .contain)` nested inside the panel's
    /// own `.contain` container — that nesting does not surface as an
    /// independently queryable element in this app's macOS accessibility
    /// tree (confirmed: `waitForExistence` on `calibration.item.*` times out
    /// even though the row is plainly visible on screen and its action
    /// buttons/fields — plain leaf controls — work fine). Rather than lean on
    /// identifiers that don't resolve, this reads every static text under the
    /// whole `calibration.readiness` panel in on-screen order: it's the same
    /// values a person reads off the panel, just captured as log lines too.
    func calibrationPanelText() -> [String] {
        let panel = element("calibration.readiness")
        guard panel.waitForExistence(timeout: 10) else {
            return ["(calibration.readiness panel not found)"]
        }
        let texts = panel.descendants(matching: .staticText).allElementsBoundByIndex
            .map(Self.bestText)
            .filter { !$0.isEmpty }
        return texts.isEmpty ? ["(no readable text under calibration.readiness)"] : texts
    }

    // MARK: - Screenshots

    /// Captures the app's front window, writes it as a loose PNG into
    /// `outputDirectory`, and returns an XCTAttachment for the test's own
    /// result bundle — the two forms of evidence the QC run asks for.
    func screenshot(name: String, outputDirectory: URL) -> XCTAttachment {
        let capture = app.windows.firstMatch.screenshot()
        let pngURL = outputDirectory.appendingPathComponent("\(name).png")
        try? capture.pngRepresentation.write(to: pngURL)
        let attachment = XCTAttachment(screenshot: capture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
