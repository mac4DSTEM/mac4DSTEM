//
//  FinalPolishSTests.swift
//  Slot 4⅞ lane S (session safety, 2026-10-04). Each test names the mutation it was broken on.
//  P3b (Gate D): removing a saved result replaced the product on screen whether or not the removed result was
//  the one shown, so a live, never-saved image vanished when an unrelated saved result was removed.
//  P5c: the unreadable-sidecar warning had two writers and the raw HDF5 text won (second class below).
//  No test here completes `openFileAsync` (it writes the host's real Recents); `hold` is ReviewOwnerCardsTests's.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishSTests: XCTestCase {

    private var directory: URL!
    private var owners: [AnyObject] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("polish-lane-s-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for owner in owners { OpenDatasetRegistry.withdraw(owner) }
        owners = []
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private func isolatedAppState() throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults),
                             recents: RecentDatasets(entries: [], persist: { _ in }))
        state.recoveryRecord = nil   // never restamp the host's real recovery record
        owners.append(state)
        return state
    }

    /// A real 4 × 4-position cube of the demo's 64 × 64 patterns, written as py4DSTEM EMD.
    private func writeCube(_ name: String) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor), calibration: PixelCalibration(),
            options: CalibratedDataCubeExportOptions(scanY: 0..<4, scanX: 0..<4), to: url)
        return url
    }

    /// The window holds `url` the way an open leaves it (activate through the file's own reader).
    private func hold(_ url: URL, in state: AppState) async throws {
        let reader = try H5Reader(path: url.path)
        let descriptor = try await reader.discoverPrimaryDataset()
        state.datasetSession.prepare(reader: reader, datasets: [descriptor])
        await state.activate(descriptor: descriptor, reader: reader, specification: .fullExtent,
                             runInitialAnalysis: false)
        XCTAssertEqual(state.descriptor?.filePath, url.path, "precondition: the window holds \(url.lastPathComponent)")
    }

    /// The sidecar beside `cube`: one 4 × 4 map per kind, saved in order on the whole file, so the LAST kind is the
    /// file's current result and the open restores it onto the screen.
    private func writeSidecar(beside cube: URL, kinds: [String]) throws {
        let url = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: cube.path)
        for kind in kinds {
            try BraggVectorEMDWriter.mergeResultMap(
                ScalarResultMap(width: 4, height: 4, pixels: (0..<16).map { Float($0) }, kind: kind,
                                displayName: "Map \(kind)", valueUnits: "a.u."),
                vectors: nil, qWidth: 64, qHeight: 64, calibration: PixelCalibration(), to: url,
                loadSpecification: .fullExtent)
        }
    }

    /// A live, never-saved product on screen, like a Virtual detector run.
    private func publishComputed(_ state: AppState, name: String) {
        state.publishProduct(
            kind: "virtual_detector", displayName: name, valueUnits: "a.u.",
            payload: .scalar(FloatImage(width: 4, height: 4, pixels: (0..<16).map { Float($0) * 2 })))
    }

    private func saved(_ state: AppState, kind: String) throws -> SessionResultDescriptor {
        try XCTUnwrap(state.sessionInventory.results.first { $0.kind == kind }, "saved result \(kind)")
    }

    // MARK: - P3b: removing a saved result changes the display only when it was the one shown

    /// Mutation: the tail of `removeSavedSessionResult` replaces the product unconditionally (HEAD) -> red.
    /// The last saved result is removed, so HEAD's tail clears the screen.
    func testAComputedImageSurvivesRemovingTheLastSavedResult() async throws {
        let cube = try await writeCube("a.h5")
        try writeSidecar(beside: cube, kinds: ["saved_map"])
        let a = try isolatedAppState()
        try await hold(cube, in: a)
        XCTAssertEqual(a.resultPresentation.product?.origin, .restoredFromSidecar, "precondition: the open shows the saved result")
        let target = try saved(a, kind: "saved_map")
        publishComputed(a, name: "Live virtual image")
        XCTAssertEqual(a.resultPresentation.product?.origin, .computed, "precondition: a live image replaced it")

        await a.removeSavedSessionResult(target)

        XCTAssertNil(a.errorMessage)
        XCTAssertTrue(a.sessionInventory.results.isEmpty, "the result is removed from the file's inventory")
        XCTAssertEqual(a.resultPresentation.product?.origin, .computed, "the live image is still the displayed product")
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Live virtual image")
    }

    /// Mutation: as above, with two saved results left — HEAD swaps the live image for the file's current result -> red.
    /// Also pins that the result version (a display change) is left alone.
    func testAComputedImageIsNotSwappedForTheSavedCurrentWhenAnotherIsRemoved() async throws {
        let cube = try await writeCube("b.h5")
        try writeSidecar(beside: cube, kinds: ["first_map", "second_map"])
        let a = try isolatedAppState()
        try await hold(cube, in: a)
        publishComputed(a, name: "Live virtual image")
        let versionBefore = a.resultPresentation.resultVersion

        await a.removeSavedSessionResult(try saved(a, kind: "first_map"))

        XCTAssertNil(a.errorMessage)
        XCTAssertEqual(a.sessionInventory.results.map(\.kind), ["second_map"], "one result left in the file")
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Live virtual image")
        XCTAssertEqual(a.resultPresentation.product?.origin, .computed)
        XCTAssertEqual(a.resultPresentation.resultVersion, versionBefore, "nothing on screen changed, so nothing was invalidated")
    }

    /// Mutation 1: the predicate is always false (the tail never runs) -> red. Mutation 2: the clear branch drops
    /// `resultPresentation.bumpResultVersion()` -> the version assertion goes red (the cleared screen is not
    /// invalidated, so a version-gated cache keeps drawing the removed result). Removing the saved result that IS
    /// the one on screen clears the screen when none is left, as before.
    func testRemovingTheShownSavedResultStillClearsTheScreen() async throws {
        let cube = try await writeCube("c.h5")
        try writeSidecar(beside: cube, kinds: ["saved_map"])
        let a = try isolatedAppState()
        try await hold(cube, in: a)
        XCTAssertEqual(a.resultPresentation.product?.origin, .restoredFromSidecar, "precondition")
        let versionBefore = a.resultPresentation.resultVersion

        await a.removeSavedSessionResult(try saved(a, kind: "saved_map"))

        XCTAssertNil(a.errorMessage)
        XCTAssertNil(a.resultPresentation.product, "the shown result is gone from the file and from the screen")
        XCTAssertNotEqual(a.resultPresentation.resultVersion, versionBefore, "the cleared screen was invalidated")
    }

    /// Mutation: as above — removing the shown result shows the file's remaining current one, as before.
    func testRemovingTheShownSavedResultShowsTheFilesCurrentOne() async throws {
        let cube = try await writeCube("d.h5")
        try writeSidecar(beside: cube, kinds: ["first_map", "second_map"])
        let a = try isolatedAppState()
        try await hold(cube, in: a)
        let second = try saved(a, kind: "second_map")
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Map second_map", "precondition: the open shows the current result")
        XCTAssertEqual(a.sessionInventory.currentResultID, second.id, "precondition")

        await a.removeSavedSessionResult(second)

        XCTAssertNil(a.errorMessage)
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Map first_map", "the remaining saved result is shown")
        XCTAssertEqual(a.resultPresentation.product?.origin, .restoredFromSidecar)
        XCTAssertEqual(a.sessionInventory.currentResultID, try saved(a, kind: "first_map").id)
    }

    /// Mutation: the tail runs unconditionally (HEAD) -> red (it swaps the viewed saved result for the file's current
    /// one). Viewing a saved result and removing ANOTHER leaves the viewed one on screen AND marked as the current one.
    /// Mutation 2: the in-session selection is not kept after the inventory reread -> the mark assertion goes red.
    func testViewingOneSavedResultSurvivesRemovingAnother() async throws {
        let cube = try await writeCube("e.h5")
        try writeSidecar(beside: cube, kinds: ["first_map", "second_map", "third_map"])
        let a = try isolatedAppState()
        try await hold(cube, in: a)
        let first = try saved(a, kind: "first_map")
        await a.selectSavedSessionResult(first)
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Map first_map", "precondition: the first is viewed")
        XCTAssertEqual(a.sessionInventory.currentResultID, first.id, "precondition")

        await a.removeSavedSessionResult(try saved(a, kind: "second_map"))

        XCTAssertNil(a.errorMessage)
        XCTAssertEqual(a.sessionInventory.results.map(\.kind), ["first_map", "third_map"])
        XCTAssertEqual(a.resultPresentation.product?.displayName, "Map first_map", "the viewed result stays on screen")
        XCTAssertEqual(a.sessionInventory.currentResultID, first.id, "and stays marked as the one in view")
    }

    /// Mutation A: `displayedOrigin` is ignored (`currentID == removedID` alone) -> the `.computed` and `nil` rows go red.
    /// Mutation B: `currentID` is ignored (`displayedOrigin == .restoredFromSidecar` alone) -> the "another saved
    /// result in view" and `nil` current rows go red. Mutation C: always false -> the first row goes red.
    func testRemovalDisplacesTheDisplayOnlyForTheSavedResultOnScreen() {
        typealias Gates = SessionGates
        XCTAssertTrue(Gates.removalDisplacesDisplay(displayedOrigin: .restoredFromSidecar, currentID: "r1", removedID: "r1"),
                      "the saved result on screen is the one removed")
        XCTAssertFalse(Gates.removalDisplacesDisplay(displayedOrigin: .computed, currentID: "r1", removedID: "r1"),
                       "a live product is not the saved result, even when that result was just saved from it")
        XCTAssertFalse(Gates.removalDisplacesDisplay(displayedOrigin: .restoredFromSidecar, currentID: "r2", removedID: "r1"),
                       "another saved result is in view")
        XCTAssertFalse(Gates.removalDisplacesDisplay(displayedOrigin: .restoredFromSidecar, currentID: nil, removedID: "r1"),
                       "no saved result is selected")
        XCTAssertFalse(Gates.removalDisplacesDisplay(displayedOrigin: nil, currentID: "r1", removedID: "r1"),
                       "nothing is displayed, so nothing is displaced")
    }

    /// Mutation A: the helper always returns the reread inventory -> the first row goes red.
    /// Mutation B: it marks `inView` whether or not the reread holds it -> the removed and vanished rows go red
    /// (a mark naming a result the file no longer has).
    func testTheResultInViewStaysMarkedOnlyWhileTheRereadHoldsIt() {
        func result(_ id: String) -> SessionResultDescriptor {
            SessionResultDescriptor(id: id, kind: id, displayName: id, valueUnits: "a.u.", width: 4, height: 4,
                                    storage: .scalarFloat32, pixelSizeRow: nil, pixelSizeColumn: nil, pixelUnits: nil, provenance: [:])
        }
        // r2 was removed: the reread holds r1 and r3, and the file's own current is r3.
        let reread = SessionSidecarInventory(hasSidecar: true, hasBraggVectors: false, hasCalibration: true,
                                             results: [result("r1"), result("r3")], currentResultID: "r3")
        typealias Gates = SessionGates
        let kept = Gates.inventory(reread, keepingInView: "r1")
        XCTAssertEqual(kept.currentResultID, "r1", "r1 is on screen and survives the removal of r2")
        XCTAssertEqual(kept.results, reread.results, "the file's own list is untouched")
        XCTAssertTrue(kept.hasSidecar && !kept.hasBraggVectors && kept.hasCalibration, "and so are its flags")
        XCTAssertEqual(Gates.inventory(reread, keepingInView: "r2").currentResultID, "r3",
                       "the removed result was the one in view: the file's own current stands")
        XCTAssertEqual(Gates.inventory(reread, keepingInView: nil).currentResultID, "r3", "nothing was in view")
    }

    // MARK: - P5c: one sentence for an unreadable sidecar, naming the remedy that exists

    /// The error the sandbox raised on 2026-08-19 (errno 1), as `SessionSidecarLocatorTests` carries it.
    private static let sandboxDenial = """
        HDF5 failed while opening the session sidecar — HDF5 reported: unable to open file: \
        name = '/Users/someone/data/sim_Au.mac4dstem.h5', errno = 1, \
        error message = 'Operation not permitted', flags = 0, o_flags = 0
        """

    /// Mutation: `reason` returns the raw detail for both classes (the HEAD behaviour of the later writer) -> red.
    func testASandboxRefusalIsWordedAsTheRemedyAndNotTheMechanism() {
        let reason = SessionSidecarReadFailure.reason(sidecar: "sim_Au.mac4dstem.h5", error: SimpleError(Self.sandboxDenial))
        XCTAssertTrue(reason.contains("sim_Au.mac4dstem.h5"), reason)
        XCTAssertTrue(reason.contains("not been granted access"), "the cause, in the user's terms: \(reason)")
        XCTAssertTrue(reason.contains("Allow Access…"), "the control that exists: \(reason)")
        XCTAssertTrue(reason.contains("sidebar") && reason.contains("Dataset menu"), "and where it is: \(reason)")
        for mechanism in ["HDF5", "errno", "Operation not permitted", "o_flags"] {
            XCTAssertFalse(reason.contains(mechanism), "the mechanism \(mechanism) belongs in the log: \(reason)")
        }
        for stale in ["Save Calibration", "File ▸", "Save the session"] {
            XCTAssertFalse(reason.contains(stale), "the remedy that cannot work (every save is refused): \(reason)")
        }
    }

    /// Mutation: the `.unreadable` class is worded like the sandbox class (no raw detail) -> red.
    func testAnyOtherReadFailureKeepsItsRawDetail() {
        let posix = "unable to open file: name = '/tmp/x.mac4dstem.h5', errno = 13, "
            + "error message = 'Permission denied', flags = 0, o_flags = 0"
        let reason = SessionSidecarReadFailure.reason(sidecar: "x.mac4dstem.h5", error: SimpleError(posix))
        XCTAssertTrue(reason.hasPrefix("Could not restore x.mac4dstem.h5: "), reason)
        XCTAssertTrue(reason.contains("errno = 13"), "the raw detail is the only clue for a failure that is not the sandbox: \(reason)")
        XCTAssertFalse(reason.contains("Allow Access"), "re-granting access cannot fix a file that is merely unreadable: \(reason)")
    }

    /// Mutation: `reason` words the sandbox class with the raw detail -> red on the HDF5/errno assertion.
    /// This is the open-time writer for the sandbox class: the same sentence, then what the app did about it.
    func testTheOpenTimeWriterUsesTheSameReason() {
        let outcome = SessionSidecarLocator.recordedOutcome(
            from: .failure(SimpleError(Self.sandboxDenial)), sidecar: "sim_Au.mac4dstem.h5")
        guard case .unreadable(let message) = outcome else { return XCTFail("expected .unreadable, got \(outcome)") }
        let reason = SessionSidecarReadFailure.reason(sidecar: "sim_Au.mac4dstem.h5", error: SimpleError(Self.sandboxDenial))
        XCTAssertEqual(message, reason + " Loading the whole dataset.")
        XCTAssertFalse(message.contains("HDF5") || message.contains("errno"), message)
    }

    /// The two writers on a REAL unreadable sidecar (a file that is not HDF5; EPERM itself needs the sandbox):
    /// the specification read at open, then `activate`'s own read. They must say one thing — the second used to
    /// replace the first with the raw error stack — and the raw error goes to the activity log.
    /// Mutations: `recordedOutcome` composes `explanation(...)` again (the HEAD text) -> the equality goes red;
    /// `reason` loses the unreadable class's raw detail -> the prefix goes red; the catch stops logging the raw
    /// error -> the log assertion goes red. Not reachable here: the SANDBOX class through `loadSessionSnapshot`'s
    /// catch (EPERM needs the sandbox); that call is the same `reason` and the same log line as this one.
    func testBothWritersOfTheUnreadableWarningSayTheSameThing() async throws {
        let cube = try await writeCube("u.h5")
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: cube.path)
        try Data("not an HDF5 file at all".utf8).write(to: sidecar)
        let a = try isolatedAppState()
        let reader = try H5Reader(path: cube.path)
        let descriptor = try await reader.discoverPrimaryDataset()

        _ = await a.recordedLoadSpecification(forSourcePath: cube.path, source: descriptor)
        let atOpen = try XCTUnwrap(a.sessionSidecar.unreadableReason, "the open-time writer reported")
        try await hold(cube, in: a)
        let afterActivate = try XCTUnwrap(a.sessionSidecar.unreadableReason, "the sidecar is still reported unreadable")

        let name = sidecar.lastPathComponent
        XCTAssertTrue(afterActivate.hasPrefix("Could not restore \(name): "), afterActivate)
        XCTAssertEqual(atOpen, afterActivate + " Loading the whole dataset.",
                       "one sentence from one classifier; the open-time one adds what the app then did")
        XCTAssertTrue(a.activityLog.messages.contains { $0.contains("\(name) could not be read: ") },
                      "the raw error is kept in the log: \(a.activityLog.messages.suffix(5))")
    }
}
