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
    /// screen, returning the message it carried. `AppState.present(error:)`
    /// blocks the rest of the UI behind a modal until acknowledged, so any
    /// step that can genuinely fail at runtime (not just time out waiting for
    /// a result) needs to clear this before the workflow can click anything
    /// else — confirmed by a real failure where a strain-computation error
    /// left this alert up and the next click (switching workspaces) was
    /// silently swallowed by it.
    ///
    /// `ContentView`'s `.alert("Something went wrong")` is a SwiftUI alert,
    /// which AppKit presents as a window-modal *sheet*. A bare
    /// `app.buttons["OK"]` lookup proved unreliable against it (an earlier run
    /// left the sheet up and lost every later click — see
    /// `References/training_runs/run_2026-07-21_0153/.../ERROR_state.png`), so
    /// this searches the sheet/dialog containers explicitly, falls back to the
    /// app-wide button query and then to Escape, and — crucially — verifies
    /// the sheet actually went away instead of assuming the click landed.
    @discardableResult
    func dismissErrorAlertIfPresent(timeout: TimeInterval = 5) -> String? {
        guard let sheet = errorAlert(timeout: timeout) else { return nil }
        var lines: [String] = []
        for staticText in sheet.descendants(matching: .staticText).allElementsBoundByIndex {
            let line = Self.bestText(staticText)
            if !line.isEmpty, line != "Something went wrong" { lines.append(line) }
        }
        let message = lines.joined(separator: " ")

        // Three tries, then give up and leave it on screen rather than clicking
        // blindly: the caller still gets the message, and the next step's
        // screenshot shows the stuck sheet.
        for _ in 0..<3 {
            let ok = sheet.descendants(matching: .button)["OK"]
            if ok.exists, ok.isHittable {
                ok.click()
            } else if app.buttons["OK"].exists, app.buttons["OK"].isHittable {
                app.buttons["OK"].click()
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
            pause()
            if errorAlert(timeout: 1) == nil { break }
        }
        return message.isEmpty ? "(unreadable alert message)" : message
    }

    /// The "Something went wrong" sheet, if it is currently up. Checks both
    /// container types AppKit uses for a window-modal SwiftUI alert.
    private func errorAlert(timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for container in [app.sheets, app.dialogs] {
                let match = container.containing(
                    .staticText, identifier: "Something went wrong"
                ).firstMatch
                if match.exists { return match }
            }
            for candidate in [app.sheets.firstMatch, app.dialogs.firstMatch]
            where candidate.exists && candidate.buttons["OK"].exists {
                return candidate
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
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

    // MARK: - Structural lookup (controls with no accessibility identifier)

    /// Finds a control that has **no accessibility identifier** by the visible
    /// label sitting next to it on the same row.
    ///
    /// Several controls this workflow needs are plain `Picker`/`TextField`s
    /// with no `.accessibilityIdentifier(...)`: the accelerating-voltage field
    /// (`UI/ContentView.swift:344`, whose row label is a *separate*
    /// `Text("Voltage")`, so the field's own title is empty) and the Strain
    /// panel's Reference/Basis pickers (`UI/ContentView.swift:240,251`). The QC
    /// playthrough is evaluation-only, so it cannot add identifiers to app
    /// code — it locates them the way a person does instead, by the label
    /// they read on screen.
    ///
    /// Matching rule: among controls of `type`, keep those whose vertical
    /// centre falls inside the label's row and that start to the *right* of the
    /// label, then take the leftmost. That is exactly the `HStack {
    /// Text(label); Spacer(); control }` layout these rows use.
    ///
    /// Returns nil rather than throwing — every caller treats "not reachable
    /// via the UI" as a *finding to log*, not a test failure.
    func control(
        _ type: XCUIElement.ElementType, inRowWithLabel label: String, timeout: TimeInterval = 8
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let labels = app.descendants(matching: .staticText).allElementsBoundByIndex
                .filter { Self.bestText($0) == label && $0.exists && $0.frame.height > 0 }
            let candidates = app.descendants(matching: type).allElementsBoundByIndex
                .filter { $0.exists && $0.frame.width > 0 }
            for labelElement in labels {
                let row = labelElement.frame
                let midY = row.midY
                let onSameRow = candidates
                    .filter { $0.frame.minY <= midY && $0.frame.maxY >= midY }
                    // Strictly to the right, so a same-type lookup (reading a
                    // LabeledContent's value) never returns the label itself.
                    .filter { $0.frame.minX > row.minX }
                    .sorted { $0.frame.minX < $1.frame.minX }
                if let match = onSameRow.first { return match }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    /// Finds an identifier-free control by the option it is **currently
    /// showing**, which beats a label lookup whenever the label is ambiguous.
    ///
    /// Used for the ACOM display-mode picker: the word "Display" is also a
    /// sidebar section header, so `control(_:inRowWithLabel: "Display")`
    /// could bind to the wrong row, while the picker's *value*
    /// ("Reliability", "IPF · Z", …) is unique in the window. The picker
    /// gained an `acom.display` identifier on 2026-08-04 (backlog #3); this
    /// value route stays as the deliberate fallback.
    func control(
        _ type: XCUIElement.ElementType, showingOneOf values: Set<String>,
        timeout: TimeInterval = 8
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in app.descendants(matching: type).allElementsBoundByIndex
            where candidate.exists && values.contains(Self.bestText(candidate)) {
                return candidate
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    /// Selects one option of a `.pickerStyle(.segmented)` Picker. macOS renders
    /// it as an AXRadioGroup whose selection is not exposed as the group's own
    /// text, so the only way in is to click the child carrying `optionLabel`
    /// — which is also exactly what a person does. Used for `acom.scope`
    /// ("Preview" / "Region" / "Full scan").
    func selectSegment(in identifier: String, optionLabel: String, timeout: TimeInterval = 10) throws {
        app.activate()
        let group = try waitForExistence(identifier, timeout: timeout)
        for type in [XCUIElement.ElementType.radioButton, .button] {
            let segment = group.descendants(matching: type)[optionLabel]
            if segment.exists, segment.isHittable {
                segment.click()
                pause()
                return
            }
        }
        throw QCError(
            "Segment \"\(optionLabel)\" not found in \(identifier) (tried radio buttons and "
            + "buttons; segments present: \(segmentLabels(in: group)))"
        )
    }

    /// Every clickable child label of a segmented control, for a failure
    /// message that says what *was* there instead of just what wasn't.
    private func segmentLabels(in group: XCUIElement) -> String {
        var found: [String] = []
        for type in [XCUIElement.ElementType.radioButton, .button] {
            for child in group.descendants(matching: type).allElementsBoundByIndex {
                let text = Self.bestText(child)
                if !text.isEmpty { found.append(text) }
            }
        }
        return found.isEmpty ? "(none readable)" : found.joined(separator: ", ")
    }

    /// Reads a control that `control(_:inRowWithLabel:)` may not have found at
    /// all, so a log line distinguishes "the control says nothing" from "the
    /// control could not be reached" instead of printing an empty string for
    /// both.
    func text(of element: XCUIElement?) -> String {
        guard let element else { return "(not reachable via the UI)" }
        return Self.bestText(element)
    }

    /// Selects an option in an already-located menu-style `Picker` element
    /// (the identifier-free counterpart of `selectMenuOption(picker:…)`).
    func selectMenuOption(in element: XCUIElement, optionLabel: String) throws {
        app.activate()
        guard element.isHittable else {
            throw QCError("Picker exists but is not hittable (selecting \"\(optionLabel)\")")
        }
        element.click()
        pause(0.5)
        let item = app.menuItems[optionLabel]
        guard item.waitForExistence(timeout: 5) else {
            app.typeKey(.escape, modifierFlags: [])
            throw QCError("Menu option \"\(optionLabel)\" not found")
        }
        item.click()
        pause()
    }

    /// `typeAndCommit(_:text:)` for an element located structurally rather
    /// than by identifier.
    func typeAndCommit(element: XCUIElement, text: String) throws {
        app.activate()
        guard element.isHittable else {
            throw QCError("Field exists but is not hittable (typing \"\(text)\")")
        }
        element.click()
        pause(0.3)
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
        element.typeKey(.tab, modifierFlags: [])
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
        try waitForResultTitle(containing: substring, notContaining: nil, timeout: timeout)
    }

    /// Waits for `result.title` to contain `containing` and — when given — to
    /// *not* contain `notContaining`.
    ///
    /// The exclusion is what makes a re-run of the same analysis detectable. A
    /// full-scan ACOM result is titled "ACOM · Reliability" while a preview one
    /// is "ACOM preview · Reliability" (the qualifier is empty for full scan —
    /// `Support/ResultExport.swift:901`). Waiting for "ACOM" alone would match
    /// the preview result still on screen and return instantly, reporting
    /// success before the full-scan run had even started.
    func waitForResultTitle(
        containing substring: String, notContaining excluded: String?, timeout: TimeInterval
    ) throws {
        let titleElement = element("result.title")
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            // macOS static text carries its content in AXValue, not AXTitle,
            // so read value-first (bestText) rather than .label, which is
            // empty here.
            if titleElement.exists {
                let title = Self.bestText(titleElement)
                let matches = title.localizedCaseInsensitiveContains(substring)
                let clean = excluded.map { !title.localizedCaseInsensitiveContains($0) } ?? true
                if matches, clean { return }
            }
            if Date() > deadline {
                let exclusion = excluded.map { " and not containing \"\($0)\"" } ?? ""
                throw QCError(
                    "Timed out after \(Int(timeout))s waiting for result title containing "
                        + "\"\(substring)\"\(exclusion) — last title: "
                        + "\"\(Self.bestText(titleElement))\", last status: \(currentStatusText())"
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

    // MARK: - ACOM work estimate

    /// The ACOM panel's own "Work" and "Expected" `LabeledContent` rows
    /// (`UI/ACOMControlsView.swift:50–53`). Reading them right after a scope
    /// change is the cheapest proof the change landed — the position count
    /// jumps from the preview subset to the whole scan *before* anything runs,
    /// so the log records the intent as well as the outcome. No accessibility
    /// identifiers, hence the label-relative read.
    func acomWorkEstimateText() -> [String] {
        ["Work", "Expected"].compactMap { label in
            guard let value = control(.staticText, inRowWithLabel: label, timeout: 3) else {
                return nil
            }
            let text = Self.bestText(value)
            return text.isEmpty ? nil : "\(label): \(text)"
        }
    }

    // MARK: - Strain diagnostics

    /// The four `LabeledContent` diagnostic rows the Strain panel publishes
    /// alongside a successful strain map (`UI/ContentView.swift:295–328`).
    /// They are the app's own quality read-out — basis support, fit residual,
    /// indexed fraction, reference inliers — so they belong in the QC log as
    /// evidence next to the exported image. None of them has an accessibility
    /// identifier, hence the label-relative read.
    func strainDiagnosticsText() -> [String] {
        ["Basis consensus", "Basis support", "Basis fit", "Local fits", "Reference inliers"]
            .compactMap { label in
                guard let value = control(.staticText, inRowWithLabel: label, timeout: 2) else {
                    return nil
                }
                let text = Self.bestText(value)
                return text.isEmpty ? nil : "\(label): \(text)"
            }
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
