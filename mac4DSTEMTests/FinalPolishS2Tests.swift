//
//  FinalPolishS2Tests.swift
//  Slot 4⅞ lane S2 (session safety, owner cards, 2026-10-04). Each test names the mutation it was broken on.
//  P3a (card Q2 a): "Ignore Session Sidecar…" / "Reopen Without This Session" ask before they replace the
//  dataset — the request raises a per-window flag, the dialog's Reopen is the confirmed reopen.
//  P5a + P7a (card Q4 d): the sidebar's session warnings show one remedy-first line, the whole text is on
//  hover without the false pointer to the Info tab, and the headline is not capped.
//  Nothing here completes `openFileAsync` (it writes the host's real Recents and recovery record): the
//  confirmed reopen is observed with the load session already busy, where `openFile` refuses at once.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishS2Tests: XCTestCase {

    private var directory: URL!
    private var owners: [AnyObject] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("polish-lane-s2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for owner in owners { OpenDatasetRegistry.withdraw(owner) }
        owners = []
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private func isolatedAppState(recents: [RecentDataset] = []) throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults),
                             recents: RecentDatasets(entries: recents, persist: { _ in }))
        state.recoveryRecord = nil   // never restamp the host's real recovery record
        owners.append(state)
        return state
    }

    /// A window that could reopen `file`: a Recents entry with a real bookmark, and the recovery record naming it.
    /// A real bookmark on purpose: a dead one sends `openRecent` down the removal path, which clears the HOST's
    /// stored recovery record (`WorkspaceRecoveryStore.clearRecovery` is `UserDefaults.standard`).
    private func reopenable() throws -> (state: AppState, recent: RecentDataset) {
        let file = directory.appendingPathComponent("not-a-cube.h5")
        try Data("not hdf5".utf8).write(to: file)
        let bookmark = try WorkspaceRecoveryStore.bookmark(for: file)
        let recent = RecentDataset(id: file.standardizedFileURL.path, displayName: file.lastPathComponent,
                                   bookmark: bookmark, lastOpened: Date())
        let state = try isolatedAppState(recents: [recent])
        state.recoveryRecord = DatasetRecoveryRecord(
            datasetID: recent.id, bookmark: bookmark, selectedX: 0, selectedY: 0,
            analysisMode: "virtualDetector", updated: Date(timeIntervalSince1970: 0))
        return (state, recent)
    }

    private func writeCube(_ name: String) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor), calibration: PixelCalibration(),
            options: CalibratedDataCubeExportOptions(scanY: 0..<4, scanX: 0..<4), to: url)
        return url
    }

    private func hold(_ url: URL, in state: AppState) async throws {
        let reader = try H5Reader(path: url.path)
        let descriptor = try await reader.discoverPrimaryDataset()
        state.datasetSession.prepare(reader: reader, datasets: [descriptor])
        await state.activate(descriptor: descriptor, reader: reader, specification: .fullExtent,
                             runInitialAnalysis: false)
        XCTAssertEqual(state.descriptor?.filePath, url.path, "precondition: the window holds \(url.lastPathComponent)")
    }

    // MARK: - P3a: the reopen asks first

    /// Mutation: the request calls `confirmReopenIgnoringSessionSidecar()` (the brief's mutation) -> the id is
    /// stamped and the flag is never raised -> red on the first two assertions. The `isLoading` line is only a
    /// belt-and-braces guard: the open is a `Task` that has not run when this synchronous test reads it, so it
    /// stays green under that mutation (recorded in the report, run R1).
    func testAskingToReopenWithoutTheSessionOnlyRaisesTheQuestion() throws {
        let (state, _) = try reopenable()
        XCTAssertFalse(state.sessionSidecar.confirmsIgnore, "precondition: no question is pending")

        state.reopenIgnoringSessionSidecar()

        XCTAssertTrue(state.sessionSidecar.confirmsIgnore, "the window is now waiting for the answer")
        XCTAssertNil(state.ignoreSessionForDatasetID, "nothing is set aside until the user says Reopen")
        XCTAssertFalse(state.datasetSession.isLoading, "and no open has begun")
        XCTAssertNil(state.errorMessage)
    }

    /// Mutation A: the confirm does not stamp `ignoreSessionForDatasetID` -> red. Mutation B: it does not lower
    /// the flag -> red. Mutation C: it does not call `openRecent` -> the status line assertion goes red.
    func testConfirmingReopensWithTheSavedSessionSetAside() throws {
        let (state, recent) = try reopenable()
        state.reopenIgnoringSessionSidecar()
        XCTAssertTrue(state.sessionSidecar.confirmsIgnore, "precondition: asked")
        // The load session is busy, so `openFile` (reached through `openRecent`) refuses at once and starts nothing.
        let load = state.beginDatasetLoading("A load already running")
        defer { state.finishDatasetLoading(owner: load) }

        state.confirmReopenIgnoringSessionSidecar()

        XCTAssertEqual(state.ignoreSessionForDatasetID, recent.id, "this one open skips the saved session")
        XCTAssertFalse(state.sessionSidecar.confirmsIgnore, "the question is answered")
        XCTAssertTrue(state.statusText.hasPrefix("Already opening a dataset"),
                      "the confirmed reopen went on to open the dataset (got: \(state.statusText))")
    }

    /// Mutation: the request raises the flag before looking for the reopen path -> red. A dataset with no recorded
    /// reopen path is told so at once; asking a question whose Reopen can only answer "no path" is wrong.
    func testNoQuestionIsAskedWhenThereIsNoPathToReopenFrom() throws {
        let state = try isolatedAppState()
        XCTAssertNil(state.recoveryRecord, "precondition")

        state.reopenIgnoringSessionSidecar()

        XCTAssertFalse(state.sessionSidecar.confirmsIgnore)
        XCTAssertTrue(state.errorMessage?.contains("no recorded reopen path") == true,
                      "told at once, before any question (got: \(state.errorMessage ?? "nil"))")
    }

    /// Mutation: `release()` leaves the flag up -> red. A dataset change (release is called by every open) makes
    /// the pending question moot, so it cannot be answered for a dataset it was not asked about.
    func testADatasetChangeWithdrawsThePendingQuestion() throws {
        let locator = SessionSidecarLocator(defaults: try XCTUnwrap(UserDefaults(suiteName: "mac4dstem.tests.\(UUID().uuidString)")))
        locator.confirmsIgnore = true

        locator.release()

        XCTAssertFalse(locator.confirmsIgnore)
    }

    /// Mutation: `existingSessionSidecarName` returns the derived name whether or not the file exists -> the
    /// "no sidecar" half goes red. The question may only say a file "stays on disk" when it is there.
    func testTheQuestionNamesTheSidecarOnlyWhenItIsThere() async throws {
        let cube = try await writeCube("named.h5")
        let state = try isolatedAppState()
        try await hold(cube, in: state)
        XCTAssertNil(state.existingSessionSidecarName, "no sidecar beside the cube yet")

        try BraggVectorEMDWriter.mergeResultMap(
            ScalarResultMap(width: 4, height: 4, pixels: (0..<16).map { Float($0) }, kind: "saved_map",
                            displayName: "Map", valueUnits: "a.u."),
            vectors: nil, qWidth: 64, qHeight: 64, calibration: PixelCalibration(),
            to: BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: cube.path), loadSpecification: .fullExtent)

        XCTAssertEqual(state.existingSessionSidecarName,
                       BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: cube.path).lastPathComponent)

        // A sidecar adopted under ANOTHER name (Allow Access… / Save As…) is the one in use; the derived sibling
        // above still exists, so a name taken from the derived path (mutation X5, the refuter's) names the wrong file.
        let renamed = directory.appendingPathComponent("renamed-session.h5")
        try Data("adopted".utf8).write(to: renamed)
        state.sessionSidecar.adopt(renamed, for: try XCTUnwrap(state.descriptor))
        XCTAssertEqual(state.existingSessionSidecarName, "renamed-session.h5",
                       "the granted sidecar is named, not the derived sibling")
    }

    /// Mutation A: the "none" wording still says "stays on disk" -> red. Mutation B: the named wording drops "not
    /// saved" (the sense of the owner's card: unsaved work is what is lost) -> red. Mutation X3 (the refuter's): the
    /// Reopen button loses `role: .destructive` -> red: it replaces the dataset and discards unsaved work, and the
    /// card must say so; the role is view wiring the pure wording cannot see, so the dialog's source is read.
    func testTheQuestionsWordsAreTheOwnersAndNameWhatIsLost() throws {
        XCTAssertEqual(ReopenWithoutSessionWording.title, "Reopen Without the Saved Session?")
        XCTAssertEqual(ReopenWithoutSessionWording.confirmButton, "Reopen")
        XCTAssertEqual(
            ReopenWithoutSessionWording.message(sidecarName: "cube.mac4dstem.h5"),
            "cube.mac4dstem.h5 stays on disk. Anything computed in this window and not saved to it is lost.")
        let none = ReopenWithoutSessionWording.message(sidecarName: nil)
        XCTAssertFalse(none.contains("stays on disk"), "no file is named when none exists")
        XCTAssertTrue(none.contains("not saved") && none.hasSuffix("is lost."), "still says what is lost: \(none)")
        let dialog = try source("mac4DSTEM/App/ReopenWithoutSessionDialog.swift")
        XCTAssertTrue(dialog.contains("Button(ReopenWithoutSessionWording.confirmButton, role: .destructive)"),
                      "Reopen is the destructive action of the card")
    }

    /// Mutation: the Dataset menu item (or any caller other than the dialog) calls the confirmed reopen directly
    /// -> red. Every route to the reopen must pass the question; this finds a route that does not.
    func testOnlyTheDialogCallsTheConfirmedReopen() throws {
        let callers = try swiftFiles(under: "mac4DSTEM").filter { file in
            (try? String(contentsOf: file, encoding: .utf8))?.contains("confirmReopenIgnoringSessionSidecar()") == true
        }.map(\.lastPathComponent).sorted()
        XCTAssertEqual(callers, ["AppState+Open.swift", "ReopenWithoutSessionDialog.swift"],
                       "the definition and the dialog's Reopen button, nothing else")
        let window = try source("mac4DSTEM/App/mac4DSTEMApp.swift")
        XCTAssertTrue(window.contains(".reopenWithoutSessionDialog(appState)"), "the dataset window hosts the dialog")
        XCTAssertTrue(window.contains("appState?.reopenIgnoringSessionSidecar()"), "the menu item asks")
    }

    // MARK: - P5a + P7a: the sidebar's session warnings

    private func crop() -> LoadSpecification {
        LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 2), detectorCrop: nil, detectorBin: 1)
    }

    private func carriedViewRefusal() throws -> String {
        let view = SessionGates.SessionView(
            recorded: crop(), loaded: .fullExtent,
            savedResults: [.init(kind: "strain", name: "Strain map")])
        return try XCTUnwrap(SessionGates.carriedViewRefusal(view), "precondition: a crop saved, the whole file loaded")
    }

    /// Mutation: `differentViewDetail` shows the raw refusal -> the length assertion goes red. Mutation 2: the line
    /// loses "remove" (or "Reopen") -> red. The refusal's remedy is at its END; at three caption lines it was cut.
    func testARefusedSaveShowsOneRemedyFirstLineAndTheWholeRefusalOnHover() throws {
        let refusal = try carriedViewRefusal()
        XCTAssertGreaterThan(refusal.count, 250, "precondition: the refusal is the long one the sidebar cut off")

        let text = SessionSidebarWording.differentViewDetail(
            refusal: refusal, saved: "scan 0–2 × 0–2", loaded: "whole file")

        XCTAssertLessThan(text.shown.count, 120)
        XCTAssertTrue(text.shown.contains("Reopen") && text.shown.contains("remove"), text.shown)
        XCTAssertEqual(text.shown, "Saving is off here. Reopen the dataset, or remove the saved result in Results.")
        XCTAssertEqual(text.full, refusal, "the hover carries every word of the refusal")
    }

    // The three tests below pin where the SIDEBAR CALLS the wording (the pure functions above cannot see the view):
    // the refuter's survivors X1, X2 and X6 left every test green because each defect sat at the call site.
    // Whitespace is collapsed so a re-wrapped call still reads; the pinned text is the call itself.

    private func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Mutation X1: `warning()`'s `.help` gets `detail` (the short line) instead of `fullDetail` -> red. The hover is
    /// where the whole refusal lives (owner card Q4 d); with the short line there it is shown nowhere.
    func testTheWarningHoverIsGivenTheFullDetail() throws {
        let sidebar = collapsingWhitespace(try source("mac4DSTEM/UI/WorkspaceSidebar.swift"))
        XCTAssertTrue(
            sidebar.contains(".help(SessionSidebarWording.warningHelp(headline: headline, detail: fullDetail))"),
            "the hover is the headline and the FULL detail")
    }

    /// Mutation X2: the different-view branch passes `refusal: nil` -> red. The remedy line would never show, and the
    /// two-views line would show while saving is refused.
    func testTheDifferentViewWarningAsksTheGatesForTheRefusal() throws {
        let sidebar = collapsingWhitespace(try source("mac4DSTEM/UI/WorkspaceSidebar.swift"))
        XCTAssertTrue(sidebar.contains("refusal: appState.gates.sidecarRewriteRefusal(),"),
                      "the refusal comes from the gates, not nil")
    }

    /// Mutation X6: the different-view branch shows `text.full` as the detail -> red. The raw 310-character refusal
    /// would be back under the headline, cut at three lines — the P5a defect itself.
    func testTheDifferentViewWarningShowsTheShortLineAndHoversTheWholeText() throws {
        let sidebar = collapsingWhitespace(try source("mac4DSTEM/UI/WorkspaceSidebar.swift"))
        XCTAssertTrue(
            sidebar.contains("warning(SessionSidebarWording.differentViewHeadline, "
                             + "detail: text.shown, fullDetail: text.full, "
                             + "identifier: \"sidebar.session.provenanceMismatch\")"),
            "the line shown is the short one; the whole text goes to the hover")
    }

    /// Mutation: the no-refusal branch shows the short remedy line too -> red (saving is not off there).
    func testWithoutARefusalTheSidebarNamesTheTwoViews() {
        let text = SessionSidebarWording.differentViewDetail(refusal: nil, saved: "scan 0–2 × 0–2", loaded: "whole file")
        XCTAssertEqual(text.shown, "Session: scan 0–2 × 0–2 · loaded: whole file")
        XCTAssertEqual(text.full, text.shown)
    }

    /// Mutation A: `unreadableDetail` always shows the whole reason -> the sandbox half goes red. Mutation B: it
    /// always shows the short line -> the other-failure half goes red (the raw detail is the only clue there).
    /// The sandbox sentence below is lane S's (`SessionSidecarReadFailure.notPermitted`), copied as a fixture so
    /// this lane stands alone; `FinalPolishSTests` and `SessionSidecarLocatorTests` pin that the real one names
    /// "Allow Access…", which is what `unreadableDetail` keys on.
    func testAnAccessRefusalShowsTheRemedyAndAnyOtherFailureKeepsItsText() {
        let access = "cube.mac4dstem.h5 sits beside this dataset but mac4DSTEM has not been granted access to it by "
            + "macOS. Choose Allow Access… (sidebar or Dataset menu) and pick that file; the dataset then reopens "
            + "with its session."
        let shortAccess = SessionSidebarWording.unreadableDetail(reason: access)
        XCTAssertLessThan(shortAccess.shown.count, access.count)
        XCTAssertLessThan(shortAccess.shown.count, 120)
        XCTAssertTrue(shortAccess.shown.contains(SessionSidebarWording.allowAccessTitle), shortAccess.shown)
        XCTAssertEqual(SessionSidebarWording.allowAccessTitle, "Allow Access…", "the sidebar button's own title")
        XCTAssertEqual(shortAccess.full, access, "the whole sentence is on hover")

        let other = "Could not restore cube.mac4dstem.h5: bad object header (underlying: HDF5 1)"
        let kept = SessionSidebarWording.unreadableDetail(reason: other)
        XCTAssertEqual(kept.shown, other)
        XCTAssertEqual(kept.full, other)
    }

    /// Mutation: `warningHelp` appends "The Info tab carries the full explanation." (HEAD) -> red.
    func testTheHoverIsTheHeadlineAndTheWholeTextAndNothingFalse() {
        let help = SessionSidebarWording.warningHelp(headline: "Headline", detail: "Whole detail text.")
        XCTAssertEqual(help, "Headline\n\nWhole detail text.")
        XCTAssertFalse(help.contains("Info tab"))
    }

    /// Mutation: the sentence is back in the sidebar source -> red. Info's "Session provenance" holds the two views
    /// and a note, never the refusal or its remedy, so the pointer was false for all three warnings.
    func testNoViewPointsAtTheInfoTabForAnExplanationItDoesNotHold() throws {
        for file in try swiftFiles(under: "mac4DSTEM/UI") {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("The Info tab carries the full explanation"), file.lastPathComponent)
        }
    }

    /// Mutation A: a headline grows past 64 characters -> red. Mutation B: the headline's `Label` gets
    /// `.lineLimit(3)` back (HEAD) -> the source assertion goes red. At the narrowest sidebar a 64-character
    /// headline needs four lines: the old cap cut it at "different view of thi…".
    func testTheWarningHeadlinesWrapUncapped() throws {
        for headline in [SessionSidebarWording.unreadableHeadline, SessionSidebarWording.doesNotFitHeadline,
                         SessionSidebarWording.differentViewHeadline] {
            XCTAssertLessThanOrEqual(headline.count, 64, headline)
        }
        let sidebar = try source("mac4DSTEM/UI/WorkspaceSidebar.swift")
        let start = try XCTUnwrap(sidebar.range(of: "private func warning("), "the warning helper")
        let tail = sidebar[start.lowerBound...]
        let label = try XCTUnwrap(tail.range(of: "Label(headline"), "the headline")
        let detail = try XCTUnwrap(tail.range(of: "Text(detail)"), "the detail")
        let headlineCode = String(tail[label.lowerBound..<detail.lowerBound])
        XCTAssertTrue(headlineCode.contains(".lineLimit(nil)"), "the headline is uncapped: \(headlineCode)")
        XCTAssertFalse(headlineCode.contains(".lineLimit(3)"), headlineCode)
        // The detail keeps its three lines (the row cannot grow past them).
        let detailCode = String(tail[detail.lowerBound...].prefix(200))
        XCTAssertTrue(detailCode.contains(".lineLimit(3)"), detailCode)
    }

    // MARK: - Reading the sources (contract checks)

    /// The repository root, from this file's own path (`mac4DSTEMTests/…`).
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftFiles(under relativeDirectory: String) throws -> [URL] {
        let root = repositoryRoot().appendingPathComponent(relativeDirectory)
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
