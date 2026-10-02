//
//  ReviewOwnerCardsTests.swift
//  Slot 4¾ lane I (pre-release review, 2026-10-02) — the owner's answers on two cards:
//  D2 (a): a dataset another window holds is refused, by file identity, before the opening window changes; the
//  same window keeps reopening its own dataset (Open with Options…, Promote); a window that lets go stops blocking.
//  D3 (a): while the session sidecar holds results computed on another view than the loaded one, a save is
//  refused with the remedy named; removing the last such result stays possible (it is the remedy), removing one of
//  several is refused (it would relabel the rest), and a rewrite leaves the in-app record of the file's view true.
//  Each test names the mutation it was broken on. No test here completes `openFileAsync`: that path remembers the
//  file in the host's real Recents and recovery record (`UserDefaults.standard` is the app's own domain here).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewOwnerCardsTests: XCTestCase {

    private var directory: URL!
    private var owners: [AnyObject] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-lane-i-\(UUID().uuidString)", isDirectory: true)
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

    /// The window holds `url` the way an open leaves it (activate through the file's own reader), without the
    /// Recents/recovery writes that close `openFileAsync`.
    private func hold(_ url: URL, in state: AppState, specification: LoadSpecification = .fullExtent) async throws {
        let reader = try H5Reader(path: url.path)
        let descriptor = try await reader.discoverPrimaryDataset()
        state.datasetSession.prepare(reader: reader, datasets: [descriptor])
        await state.activate(descriptor: descriptor, reader: reader, specification: specification,
                             runInitialAnalysis: false)
        XCTAssertEqual(state.descriptor?.filePath, url.path, "precondition: the window holds \(url.lastPathComponent)")
    }

    private func waitUntil(_ condition: () -> Bool, seconds: Double = 15) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    private var scanCrop: LoadSpecification {
        LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 2))
    }

    private func line(_ name: String) -> String {
        "\(name) is already open in another window — use that window, or close it first."
    }

    // MARK: - D2: one dataset, one window

    /// Mutation: `sameFile` stops at the path comparison (no resource identifier) -> red (the hard link and the
    /// case-different spelling read as different files).
    func testSameFileIsDecidedByIdentityNotSpelling() throws {
        let file = directory.appendingPathComponent("scan.h5")
        try Data("x".utf8).write(to: file)
        let other = directory.appendingPathComponent("other.h5")
        try Data("y".utf8).write(to: other)
        let link = directory.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let hard = directory.appendingPathComponent("hard.h5")
        try FileManager.default.linkItem(at: file, to: hard)
        let upper = directory.appendingPathComponent("SCAN.H5")

        XCTAssertTrue(OpenDatasetRegistry.sameFile(file, file))
        XCTAssertTrue(OpenDatasetRegistry.sameFile(link, file), "a symlink is its target")
        XCTAssertTrue(OpenDatasetRegistry.sameFile(hard, file), "a hard link is the same file")
        XCTAssertTrue(OpenDatasetRegistry.sameFile(upper, file), "a case-different spelling on APFS is the same file")
        XCTAssertFalse(OpenDatasetRegistry.sameFile(other, file), "another file is another dataset")
        let missing = directory.appendingPathComponent("missing.h5")
        XCTAssertTrue(OpenDatasetRegistry.sameFile(missing, directory.appendingPathComponent("./missing.h5")),
                      "with no file to ask, the standardized path decides")
    }

    /// Mutation: delete the entry check in `openFileAsync` (the post-discovery check stays) -> red: the refused
    /// open first put "Opening x.h5…" in this window's log, i.e. touched it before refusing.
    func testAnotherWindowsDatasetIsRefusedBeforeThisWindowChanges() async throws {
        let x = try await writeCube("x.h5")
        let y = try await writeCube("y.h5")
        let a = try isolatedAppState()
        let b = try isolatedAppState()
        try await hold(x, in: a)
        try await hold(y, in: b)

        await b.openFileAsync(url: x)
        XCTAssertEqual(b.errorMessage, line("x.h5"))
        XCTAssertEqual(b.descriptor?.filePath, y.path, "this window keeps its own dataset")
        XCTAssertFalse(b.datasetSession.isLoading)
        XCTAssertFalse(b.activityLog.messages.contains { $0.contains("Opening x.h5") },
                       "refused before the window started loading anything")

        let link = directory.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: x)
        b.errorMessage = nil
        await b.openFileAsync(url: link)
        XCTAssertEqual(b.errorMessage,
                       "link.h5 is the same file as x.h5, which is already open in another window — use that window, or close it first.")
        XCTAssertEqual(b.descriptor?.filePath, y.path)

        b.errorMessage = nil
        b.openFileForConfiguration(url: x)   // Open with Options…
        XCTAssertEqual(b.errorMessage, line("x.h5"))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(b.promotionRun.pendingLoad, "no configurator opened on the other window's dataset")
        XCTAssertFalse(b.datasetSession.isLoading)
    }

    /// Mutation: `otherHolder` also asks the asking window's own claims -> red (its own Open with Options… is
    /// refused against itself).
    func testTheSameWindowKeepsReopeningItsOwnDataset() async throws {
        let x = try await writeCube("x.h5")
        let a = try isolatedAppState()
        let b = try isolatedAppState()
        try await hold(x, in: a)
        XCTAssertNil(OpenDatasetRegistry.refusal(opening: x, by: a), "a window's own dataset is never refused")

        a.openFileForConfiguration(url: x)   // Open with Options… on the dataset this window holds
        try await waitUntil { a.promotionRun.pendingLoad != nil || a.errorMessage != nil }
        XCTAssertNil(a.errorMessage)
        XCTAssertEqual(a.promotionRun.pendingLoad?.url.path, x.path)
        a.discardPendingLoad()

        try await hold(x, in: a, specification: scanCrop)   // a rehearsal view…
        await a.promoteToFullExtent(runReestablishingAnalysis: false)   // …promoted in the same window
        XCTAssertNil(a.errorMessage)
        XCTAssertTrue(a.loadedView.isFullExtent)
        XCTAssertEqual(a.descriptor?.filePath, x.path)
        XCTAssertEqual(OpenDatasetRegistry.refusal(opening: x, by: b), line("x.h5"), "still held after the promote")
    }

    /// Mutation: `withdraw` removes nothing -> red (a closed window would keep its file locked).
    func testAWindowThatLetsGoNoLongerBlocks() async throws {
        let x = try await writeCube("x.h5")
        let a = try isolatedAppState()
        let b = try isolatedAppState()
        try await hold(x, in: a)
        XCTAssertNotNil(OpenDatasetRegistry.refusal(opening: x, by: b))

        await a.discardPartialLoad()   // the window's dataset goes
        XCTAssertNil(OpenDatasetRegistry.refusal(opening: x, by: b), "a window holds only what it has open")

        try await hold(x, in: a)
        OpenDatasetRegistry.withdraw(a)   // its window closed
        XCTAssertNil(OpenDatasetRegistry.refusal(opening: x, by: b), "a closed window lets go at once")
        a.enrollInOpenDatasetRegistry()   // its window appeared again
        XCTAssertNotNil(OpenDatasetRegistry.refusal(opening: x, by: b))

        var released: NSObject? = NSObject()
        let path = directory.appendingPathComponent("held-by-released.h5").path
        if let object = released {
            OpenDatasetRegistry.enroll(object) { () -> [String] in [path] }
        }
        XCTAssertNotNil(OpenDatasetRegistry.otherHolder(of: URL(fileURLWithPath: path), excluding: b))
        released = nil
        XCTAssertNil(OpenDatasetRegistry.otherHolder(of: URL(fileURLWithPath: path), excluding: b),
                     "held weakly: a state graph that is gone holds nothing")
    }

    /// Mutation: `otherHolder` ignores the opens in flight -> red (an open still reading the file structure claims
    /// nothing, so a second window could open the same file at the same time).
    func testAnOpenInFlightAndAConfiguredOpenHoldTheirFile() async throws {
        let x = try await writeCube("x.h5")
        let a = try isolatedAppState()
        let b = try isolatedAppState()

        OpenDatasetRegistry.beginOpening(x, by: a)
        XCTAssertEqual(OpenDatasetRegistry.refusal(opening: x, by: b), line("x.h5"), "an open in flight claims its file")
        OpenDatasetRegistry.endOpening(x, by: a)
        XCTAssertNil(OpenDatasetRegistry.refusal(opening: x, by: b))

        a.openFileForConfiguration(url: x)   // the configurator waits with the file open
        try await waitUntil { a.promotionRun.pendingLoad != nil || a.errorMessage != nil }
        XCTAssertNotNil(a.promotionRun.pendingLoad, "precondition: the configurator holds x.h5")
        await b.openFileAsync(url: x)
        XCTAssertEqual(b.errorMessage, line("x.h5"))
        XCTAssertNil(b.descriptor)
        a.discardPendingLoad()
        XCTAssertNil(OpenDatasetRegistry.refusal(opening: x, by: b), "a dismissed configurator holds nothing")
    }

    /// Mutation: a Preprocess pending open counts as held (`heldDatasetFilePaths` drops its preprocess test) -> red.
    func testPreprocessIsNeitherRefusedNorHolding() async throws {
        let x = try await writeCube("x.h5")
        let a = try isolatedAppState()
        let b = try isolatedAppState()
        try await hold(x, in: a)

        b.openFileForConfiguration(url: x, preprocess: true)   // Preprocess Raw Data… only reads its source
        try await waitUntil { b.promotionRun.pendingLoad != nil || b.errorMessage != nil }
        XCTAssertNil(b.errorMessage)
        XCTAssertNotNil(b.promotionRun.pendingLoad?.preprocess)
        XCTAssertNil(OpenDatasetRegistry.otherHolder(of: x, excluding: a), "a preprocess source is not a held dataset")
        b.discardPendingLoad()
    }

    // MARK: - D3: results saved on another view

    private func view(recorded: LoadSpecification?, loaded: LoadSpecification, kinds: [String]) -> SessionGates.SessionView {
        SessionGates.SessionView(recorded: recorded, loaded: loaded,
                                 savedResults: kinds.map { .init(kind: $0, name: "Map \($0)") })
    }

    /// Mutation: the rule only knows the rehearse-then-promote direction (`!recorded.isFullExtent` instead of
    /// `recorded != loaded`) -> red (a crop rehearsal of a dataset holding full-extent results saves over them).
    func testTheCarriedViewRuleRefusesBothDirectionsAndAllowsTheLastRemoval() {
        let crop = scanCrop
        XCTAssertNil(SessionGates.carriedViewRefusal(view(recorded: nil, loaded: crop, kinds: ["a"])),
                     "no recorded view, nothing known to differ")
        XCTAssertNil(SessionGates.carriedViewRefusal(view(recorded: crop, loaded: crop, kinds: ["a"])))
        XCTAssertNil(SessionGates.carriedViewRefusal(view(recorded: crop, loaded: .fullExtent, kinds: [])),
                     "nothing saved, nothing to relabel")

        let promoted = SessionGates.carriedViewRefusal(view(recorded: crop, loaded: .fullExtent, kinds: ["a"]))
        XCTAssertEqual(promoted,
                       "The session sidecar holds “Map a”, computed on another view of this file "
                       + "(saved: scan 2 × 2 at (x 0, y 0) · loaded: whole file). Saving now would relabel it as "
                       + "computed on the loaded view. Reopen the dataset — a plain open restores the saved view — "
                       + "and save there, or remove “Map a” in Results first.")
        XCTAssertNotNil(SessionGates.carriedViewRefusal(view(recorded: .fullExtent, loaded: crop, kinds: ["a"])),
                        "both directions: a rehearsal view of a dataset holding full-extent results refuses too")
        XCTAssertEqual(SessionGates.carriedViewRefusal(view(recorded: crop, loaded: .fullExtent, kinds: ["a", "b"])),
                       "The session sidecar holds 2 results computed on another view of this file "
                       + "(saved: scan 2 × 2 at (x 0, y 0) · loaded: whole file). Saving now would relabel them as "
                       + "computed on the loaded view. Reopen the dataset — a plain open restores the saved view — "
                       + "and save or remove them there.")

        XCTAssertNil(SessionGates.carriedViewRefusal(view(recorded: crop, loaded: .fullExtent, kinds: ["a"]),
                                                     removingKind: "a"),
                     "removing the last one is the remedy")
        XCTAssertEqual(SessionGates.carriedViewRefusal(view(recorded: crop, loaded: .fullExtent, kinds: ["a", "b"]),
                                                       removingKind: "a"),
                       "Removing “Map a” rewrites the session sidecar as the loaded view, which would relabel the "
                       + "other result computed on another view of this file (saved: scan 2 × 2 at (x 0, y 0) · "
                       + "loaded: whole file). Reopen the dataset — a plain open restores the saved view — and "
                       + "remove them there.")
    }

    /// The sidecar beside `cube`, holding one 2 × 2 result per kind, saved on `specification`.
    private func writeSidecar(beside cube: URL, kinds: [String], specification: LoadSpecification) throws -> URL {
        let url = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: cube.path)
        for kind in kinds {
            try BraggVectorEMDWriter.mergeResultMap(
                ScalarResultMap(width: 2, height: 2, pixels: [1, 2, 3, 4], kind: kind,
                                displayName: "Map \(kind)", valueUnits: "a.u."),
                vectors: nil, qWidth: 64, qHeight: 64, calibration: PixelCalibration(), to: url,
                loadSpecification: specification)
        }
        return url
    }

    /// Mutations: (1) `AppState.init` installs no `gates.sessionView` -> red (the promoted session saves);
    /// (2) the removal path does not record that the file now states the loaded view -> red (the next save after
    /// the remedy would be refused, and the sidebar would keep warning about a view the file no longer holds).
    func testAPromotedSessionRefusesSavesAndKeepsTheRemedy() async throws {
        let x = try await writeCube("x.h5")
        let sidecar = try writeSidecar(beside: x, kinds: ["rehearsal_map"], specification: scanCrop)
        let a = try isolatedAppState()
        try await hold(x, in: a)   // the whole file, while the sidecar records the 2 × 2 rehearsal
        XCTAssertEqual(a.sessionLoadSpecification, scanCrop, "precondition: the sidecar's view was read")
        XCTAssertEqual(a.sessionInventory.results.map(\.kind), ["rehearsal_map"], "precondition")

        XCTAssertFalse(a.gates.mayWriteSidecar, "every save control is closed")
        guard !a.gates.mayWriteSidecar else { return }   // a save would otherwise ask for a panel
        let refusal = try XCTUnwrap(a.gates.sidecarRewriteRefusal())
        XCTAssertTrue(refusal.contains("remove “Map rehearsal_map” in Results first"), refusal)
        a.sessionSidecar.adopt(sidecar, for: try XCTUnwrap(a.descriptor))   // a grant: no panel, ever
        a.saveCalibrationToSessionSidecar()   // the Dataset menu's / labels' save
        XCTAssertEqual(a.errorMessage, refusal, "the save entry refuses with the remedy named")
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: sidecar).loadSpecification, scanCrop,
                       "nothing was written")

        XCTAssertTrue(a.gates.mayRemoveFromSidecar(kind: "rehearsal_map"), "the remedy stays open")
        a.errorMessage = nil
        await a.removeSavedSessionResult(try XCTUnwrap(a.sessionInventory.results.first))
        XCTAssertNil(a.errorMessage)
        XCTAssertTrue(a.sessionInventory.results.isEmpty)
        XCTAssertEqual(a.sessionLoadSpecification, .fullExtent, "the file now records the loaded view")
        XCTAssertTrue(a.gates.mayWriteSidecar, "saving is open again")
        let reread = try BraggVectorEMDWriter.loadSession(from: sidecar)
        XCTAssertNil(reread.loadSpecification, "rewritten as the whole file")
        XCTAssertTrue(reread.inventory.results.isEmpty)
    }

    /// Mutation: the removal path asks only the restore failure (`gates.sidecarRestoreFailure`), not the rewrite
    /// gate for this removal -> red (removing one of two relabels the other in the file).
    func testRemovingOneOfSeveralCarriedResultsIsRefused() async throws {
        let x = try await writeCube("x.h5")
        let sidecar = try writeSidecar(beside: x, kinds: ["first_map", "second_map"], specification: scanCrop)
        let a = try isolatedAppState()
        try await hold(x, in: a)
        XCTAssertEqual(a.sessionInventory.results.count, 2, "precondition")

        XCTAssertFalse(a.gates.mayRemoveFromSidecar(kind: "first_map"))
        let first = try XCTUnwrap(a.sessionInventory.results.first { $0.kind == "first_map" })
        await a.removeSavedSessionResult(first)
        XCTAssertTrue(a.errorMessage?.contains("would relabel the other result") == true, a.errorMessage ?? "nil")
        let reread = try BraggVectorEMDWriter.loadSession(from: sidecar)
        XCTAssertEqual(reread.inventory.results.count, 2, "the file is untouched")
        XCTAssertEqual(reread.loadSpecification, scanCrop)
    }
}
