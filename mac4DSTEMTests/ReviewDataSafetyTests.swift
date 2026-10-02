//
//  ReviewDataSafetyTests.swift
//  Slot 4¾ lane A (pre-release review, 2026-10-02): the source dataset and the session sidecar are never a write
//  destination they should not be (a1/b5/e1), an unopenable sidecar is never replaced (a4), labels a view did not
//  restore are never overwritten by a save (a3), the rewrite refusal names controls that exist (e5), a superseded
//  sidecar save is logged and the open commands know one is running (c4), and the sidebar never says "Nothing saved
//  yet" beside a session it could not read (e10). Each test names the mutation it was broken on.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewDataSafetyTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-lane-a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for name in names {   // a chmod-0 fixture must not survive the run
                try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: directory.appendingPathComponent(name).path)
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func isolatedAppState() throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
    }

    private func waitUntil(_ what: String, timeoutSeconds: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out waiting for \(what)"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func oneFieldMap() -> ScalarResultMap {
        ScalarResultMap(width: 2, height: 2, pixels: [1, 2, 3, 4], kind: "virtual_image",
                        displayName: "Virtual image", valueUnits: "counts")
    }

    // MARK: a1 — the sidecar panels never adopt the dataset

    /// The dataset and a link to it refuse; the sidecar's own default path (which `exportDestinationRefusal`
    /// would wrongly refuse) and another name do not. Mutation: `sidecarDestinationRefusal` returns nil -> red.
    func testTheSidecarPanelRefusesTheDatasetButNotItsOwnSidecar() throws {
        let source = directory.appendingPathComponent("scan.h5")
        try Data("raw cube".utf8).write(to: source)
        let link = directory.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: source.path)
        XCTAssertNotNil(SessionSidecarLocator.sidecarDestinationRefusal(source, sourcePath: source.path))
        XCTAssertNotNil(SessionSidecarLocator.sidecarDestinationRefusal(link, sourcePath: source.path))
        XCTAssertNil(SessionSidecarLocator.sidecarDestinationRefusal(sidecar, sourcePath: source.path),
                     "the sidecar's default path is the panel's correct answer")
        XCTAssertNil(SessionSidecarLocator.sidecarDestinationRefusal(
            directory.appendingPathComponent("elsewhere.mac4dstem.h5"), sourcePath: source.path))
    }

    /// Change Session Sidecar… with an unreadable current sidecar: the copy fails and the file already at the chosen
    /// destination is untouched. Mutation: restore remove-before-copy -> red (the destination is gone).
    func testAFailedSidecarCopyNeverRemovesTheDestination() throws {
        let current = directory.appendingPathComponent("old.mac4dstem.h5")
        try Data("session".utf8).write(to: current)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: current.path)
        let destination = directory.appendingPathComponent("scan.h5")
        let raw = Data("the only raw cube".utf8)
        try raw.write(to: destination)
        guard case .failed(let line) = SessionSidecarLocator.copySidecarFile(from: current, to: destination) else {
            return XCTFail("an unreadable current sidecar must fail the copy")
        }
        XCTAssertEqual(try Data(contentsOf: destination), raw, "the destination must survive a failed copy: \(line)")
        XCTAssertFalse(line.contains("removed"), line)
        // A readable source still replaces the destination the user chose.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: current.path)
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: current, to: destination), .copied)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "session")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [], "no scratch file is left beside the destination")
    }

    // MARK: b5 / e1 — the scientific bundle never replaces the source or its sidecar

    /// Mutation: drop the `sourcePath` refusal in `writeScientificBundle` -> red (the file is replaced).
    func testTheScientificBundleRefusesTheSourceAndItsSidecar() throws {
        let source = directory.appendingPathComponent("scan.h5")
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: source.path)
        for target in [source, sidecar] {
            let bytes = Data("must survive \(target.lastPathComponent)".utf8)
            try bytes.write(to: target)
            XCTAssertThrowsError(try BraggVectorEMDWriter.writeScientificBundle(
                maps: [oneFieldMap()], calibration: PixelCalibration(), to: target, sourcePath: source.path)) { error in
                guard case BraggVectorEMDWriter.WriterError.publishFailed = error else {
                    return XCTFail("expected publishFailed, got \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: target), bytes, "\(target.lastPathComponent) must be unchanged")
        }
        // A sibling name still writes.
        let sibling = directory.appendingPathComponent("scan_scientific_bundle.h5")
        try BraggVectorEMDWriter.writeScientificBundle(
            maps: [oneFieldMap()], calibration: PixelCalibration(), to: sibling, sourcePath: source.path)
        XCTAssertNotNil(try BraggVectorEMDWriter.loadScientificBundleField(kind: "virtual_image", from: sibling))
    }

    // MARK: a4 — an existing sidecar that cannot be opened is an error, never replaced

    private func sidecarWithLabels() throws -> (url: URL, bytes: Data) {
        let url = directory.appendingPathComponent("scan.mac4dstem.h5")
        let labels = DiskCentreLabelStore()
        labels.reset(filePath: directory.appendingPathComponent("scan.h5").path, datasetPath: "/data")
        labels.add(.init(row: 3, col: 4), ry: 0, rx: 0)
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 8, qHeight: 8, to: url,
            diskCentreLabelsJSON: String(decoding: try labels.encodedJSON(frame: "native"), as: UTF8.self))
        return (url, try Data(contentsOf: url))
    }

    /// Unreadable (permissions) sidecar in a writable folder. Mutation: restore `id >= 0 ? id : nil` -> red (the save
    /// succeeds and renames a fresh file over the sidecar).
    func testASaveOverAnUnopenableSidecarThrowsAndKeepsIt() throws {
        let (url, bytes) = try sidecarWithLabels()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        XCTAssertThrowsError(try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 8, qHeight: 8, to: url)) { error in
            XCTAssertTrue("\(error)".contains("opening the existing session sidecar"), "\(error)")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "the sidecar must be byte-identical after the refused save")
    }

    /// The reviewer's own trigger: another reader holds the file's lock (HDFView, h5py "r+"), so HDF5's read-only
    /// open fails with "unable to lock file". Same mutation -> red.
    func testASaveOverALockedSidecarThrowsAndKeepsIt() throws {
        let (url, bytes) = try sidecarWithLabels()
        let fd = open(url.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0, "the fixture must hold the exclusive lock")
        XCTAssertThrowsError(try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 8, qHeight: 8, to: url)) { error in
            XCTAssertTrue("\(error)".contains("opening the existing session sidecar"), "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    // MARK: a3 — labels a view did not restore are never overwritten

    /// Mutation: drop the flag assignment at the top of `restore` -> red.
    func testARefusedRestoreFlagsTheStoreAndResetClearsIt() throws {
        let source = DiskCentreLabelStore()
        source.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        source.add(.init(row: 1, col: 1), ry: 0, rx: 0)
        let native = try source.encodedJSON(frame: "native")

        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertFalse(try target.restore(from: native, expecting: "/a/cube.h5", frame: "bin2",
                                          scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        XCTAssertTrue(target.sidecarHoldsUnrestoredLabels, "a frame refusal leaves the sidecar's labels unrestored")
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertFalse(target.sidecarHoldsUnrestoredLabels)

        XCTAssertThrowsError(try target.restore(from: native, expecting: "/b/other.h5", frame: "native",
                                                scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        XCTAssertTrue(target.sidecarHoldsUnrestoredLabels, "a cube-path refusal too")

        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertTrue(try target.restore(from: native, expecting: "/a/cube.h5", frame: "native",
                                         scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        XCTAssertFalse(target.sidecarHoldsUnrestoredLabels, "an applied restore owes the sidecar nothing")
    }

    /// The app's own save path: with the store flagged and a new label clicked, Save Calibration keeps the sidecar's
    /// labels byte-identical and says so. Mutation: drop `|| labelsWithheld` in `saveCalibrationToSessionSidecar` -> red.
    func testASaveKeepsLabelsTheViewDidNotRestore() async throws {
        let state = try isolatedAppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        let old = DiskCentreLabelStore()
        old.reset(filePath: descriptor.filePath, datasetPath: descriptor.datasetPath)
        for ry in 0..<3 { old.add(.init(row: 5, col: 6), ry: ry, rx: 1) }
        let oldJSON = String(decoding: try old.encodedJSON(frame: "bin2"), as: UTF8.self)
        try BraggVectorEMDWriter.mergeCalibration(PixelCalibration(), qWidth: descriptor.qx, qHeight: descriptor.qy,
                                                  to: sidecar, diskCentreLabelsJSON: oldJSON)
        state.sessionSidecar.adopt(sidecar, for: descriptor)
        state.diskCentreLabels.noteSidecarLabelsNotRestored()   // what the refused restore at open leaves behind
        state.diskCentreLabels.add(.init(row: 2, col: 2), ry: 0, rx: 0)

        state.saveCalibrationToSessionSidecar()
        try await waitUntil("the calibration save publishes") { state.statusText.contains("Saved calibration") }
        XCTAssertTrue(state.statusText.contains(DiskCentreLabelStore.withheldLabelsLine), state.statusText)
        XCTAssertEqual(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: sidecar), oldJSON,
                       "the sidecar's unrestored labels must survive the save")
    }

    // MARK: e5 — the rewrite refusal names controls that exist

    /// Mutation: restore the "Change… in the dataset inspector" wording -> red.
    func testTheRewriteRefusalNamesRealControls() {
        let gates = SessionGates()
        gates.noteSidecarRestoreFailed(.unreadable, message: "EPERM.")
        let unreadable = gates.sidecarRewriteRefusal() ?? ""
        XCTAssertTrue(unreadable.contains("Allow Access…"), unreadable)
        XCTAssertTrue(unreadable.contains("Change Session Sidecar…"), unreadable)
        XCTAssertFalse(unreadable.contains("dataset inspector"), unreadable)
        gates.noteSidecarRestoreFailed(.doesNotFit, message: "Wrong file.")
        let doesNotFit = gates.sidecarRewriteRefusal() ?? ""
        XCTAssertTrue(doesNotFit.contains("Dataset › Change Session Sidecar…"), doesNotFit)
        XCTAssertFalse(doesNotFit.contains("dataset inspector"), doesNotFit)
    }

    // MARK: c4 — a superseded sidecar save is logged, and the open commands can see one running

    /// Mutation A: `isSaveInFlight` returns false -> red. Mutation B: drop the `activityLog.record` in the
    /// calibration save's cancel catch -> red.
    func testASupersededCalibrationSaveIsLoggedAndWasVisibleAsInFlight() async throws {
        XCTAssertFalse(SessionSidecarLocator.isSaveInFlight(nil))
        XCTAssertFalse(SessionSidecarLocator.isSaveInFlight("Scientific bundle"))
        let state = try isolatedAppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        state.sessionSidecar.adopt(sidecar, for: descriptor)
        state.diskCentreLabels.add(.init(row: 2, col: 2), ry: 0, rx: 0)

        state.saveCalibrationToSessionSidecar()
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(SessionSidecarLocator.isSaveInFlight(state.activeOperation),
                      "the open commands must see the save's own operation name: \(state.activeOperation ?? "nil")")
        state.operationCenter.reset()   // what `activate` does when another dataset opens
        try await waitUntil("the superseded save is logged") {
            state.activityLog.messages.contains { $0.contains("cancelled before it was written") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path), "nothing was written")
    }

    /// Every open path (toolbar, welcome, sidebar, Recents, Finder) funnels through `openFile`; while a sidecar save
    /// runs it refuses by name and the save completes. Mutation: drop the `isSaveInFlight` guard in `openFile` -> red.
    func testOpeningAnotherDatasetDuringASidecarSaveIsRefusedAndTheSaveCompletes() async throws {
        let state = try isolatedAppState()
        await state.openDemoFixture(calibrated: true)
        let descriptor = try XCTUnwrap(state.descriptor)
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        state.sessionSidecar.adopt(sidecar, for: descriptor)
        state.diskCentreLabels.add(.init(row: 2, col: 2), ry: 0, rx: 0)

        state.saveCalibrationToSessionSidecar()
        XCTAssertTrue(state.isBusy)
        state.openFile(url: directory.appendingPathComponent("other.h5"))
        XCTAssertTrue(state.statusText.contains("Still saving the session sidecar"),
                      "the open must be refused by name: \(state.statusText)")
        XCTAssertTrue(state.statusText.contains("other.h5"))
        try await waitUntil("the save finishes", timeoutSeconds: 30) { !state.isBusy }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path), "the save was not cancelled")
        XCTAssertFalse(state.activityLog.messages.contains { $0.contains("cancelled before it was written") })
    }

    // MARK: e10 — no "Nothing saved yet" beside an unreadable session

    /// Mutation: drop `&& unreadableReason == nil` -> red.
    func testTheSidebarNeverSaysNothingSavedBesideAnUnreadableSession() throws {
        let locator = try XCTUnwrap(isolatedAppState().sessionSidecar)
        XCTAssertTrue(locator.mayClaimNothingSaved(hasSidecar: false))
        XCTAssertFalse(locator.mayClaimNothingSaved(hasSidecar: true))
        locator.noteUnreadable("Operation not permitted.")
        XCTAssertFalse(locator.mayClaimNothingSaved(hasSidecar: false),
                       "a session IS saved beside the dataset; it could not be read")
    }
}
