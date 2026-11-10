//
//  SidecarSourceStampTests.swift
//  One sidecar name per stem: `scan.h5` and `scan.dm4` in one folder share `scan.mac4dstem.h5`, and opening one adopted
//  the other's calibration (the 2x binned conversion opened with Q off by 2). The writer now stamps the source
//  (`mac4dstem_source`: name, bytes, shape), and a restore checks it before anything is read. A save checks it too, and the
//  source that did not write the shared file keeps its session under its own name (`scan.dm4.mac4dstem.h5`).
//

import XCTest
import DSTEMCore
import DSTEMSession

final class SidecarSourceStampTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarSourceStampTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let calibration = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)

    /// A source file of `bytes` zero bytes in the test folder.
    private func source(_ name: String, bytes: Int = 16) throws -> String {
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url.path
    }

    private var sidecar: URL { folder.appendingPathComponent("scan.mac4dstem.h5") }

    // MARK: The writer stamps the source

    func testACalibrationSaveStampsTheSourceItWasSavedFor() throws {
        let h5 = try source("scan.h5", bytes: 40)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        let snapshot = try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: h5)
        XCTAssertEqual(snapshot.source, SessionSourceStamp(name: "scan.h5", bytes: 40, shape: [4, 5, 8, 8]))
        XCTAssertNotNil(snapshot.calibration, "the matching source restores")
    }

    /// A rewrite that says nothing about the source keeps the stamp the file carries, as the recipe and the labels are kept.
    func testARewriteWithoutAStampKeepsTheFilesStamp() throws {
        let h5 = try source("scan.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: sidecar)
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: sidecar).source?.name, "scan.h5")
    }

    // MARK: The restore checks it

    /// The defect: a sidecar written for `scan.h5`, then `scan.dm4` opened beside it. Before the stamp it adopted the
    /// calibration; now the restore is refused, and the sentence names both files.
    func testASidecarWrittenForScanH5IsRefusedWhenScanDM4IsOpened() throws {
        let h5 = try source("scan.h5")
        let dm4 = try source("scan.dm4")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: dm4)) { error in
            guard case BraggVectorEMDWriter.WriterError.belongsToAnotherSource = error else {
                return XCTFail("threw \(error), not belongsToAnotherSource")
            }
            let sentence = error.localizedDescription
            XCTAssertTrue(sentence.contains("scan.h5") && sentence.contains("scan.dm4"), sentence)
            // The open path's one sentence for a sidecar it could not restore carries it unchanged.
            XCTAssertTrue(SessionSidecarReadFailure.reason(sidecar: "scan.mac4dstem.h5", error: error).contains(sentence))
        }
    }

    /// A sidecar from before the stamp, with no other file of its stem: restored as before.
    func testAnUnstampedSidecarWithNoSiblingRestoresAsBefore() throws {
        let h5 = try source("scan.h5")
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: sidecar)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: h5)
        XCTAssertNil(snapshot.source)
        XCTAssertNotNil(snapshot.calibration)
    }

    /// A sidecar from before the stamp, beside two files of its stem: nothing says which wrote it, so it is not restored.
    func testAnUnstampedSidecarBesideASiblingIsRefused() throws {
        _ = try source("scan.h5")
        let dm4 = try source("scan.dm4")
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: sidecar)
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: dm4)) { error in
            let sentence = error.localizedDescription
            XCTAssertTrue(sentence.contains("scan.dm4 and scan.h5"), sentence)
        }
    }

    /// The inventory reads (no source given) are not gated: they read the file the open path already accepted.
    func testAReadWithoutASourcePathIsNotChecked() throws {
        let h5 = try source("scan.h5")
        _ = try source("scan.dm4")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadInventory(from: sidecar))
    }

    /// The unstamped refusal and the stamped one are different errors: only the stamped one says whose file it is.
    func testAnUnstampedRefusalIsNotBelongsToAnotherSource() throws {
        _ = try source("scan.h5")
        let dm4 = try source("scan.dm4")
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: sidecar)
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: dm4)) { error in
            guard case BraggVectorEMDWriter.WriterError.sourceNotRecorded = error else {
                return XCTFail("threw \(error), not sourceNotRecorded")
            }
        }
    }

    // MARK: A save never mixes two sources

    /// The other half of the defect: with `scan.h5`'s sidecar in place, a save for `scan.dm4` merged into it, carried
    /// `scan.h5`'s results and recipe along and restamped the file for `scan.dm4`. Refused, and the file is as it was.
    func testASaveForScanDM4IsNotMergedIntoScanH5sSidecar() throws {
        let h5 = try source("scan.h5", bytes: 40)
        let dm4 = try source("scan.dm4", bytes: 80)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        let before = try Data(contentsOf: sidecar)
        let other = PixelCalibration(rSize: 2.0, rUnits: "nm", qSize: 0.02, qUnits: "A^-1", qrFlip: false)
        XCTAssertThrowsError(try BraggVectorEMDWriter.mergeCalibration(
            other, qWidth: 16, qHeight: 16, to: sidecar,
            source: SessionSourceStamp(sourcePath: dm4, shape: [4, 5, 16, 16]))) { error in
            guard case BraggVectorEMDWriter.WriterError.belongsToAnotherSource = error else {
                return XCTFail("threw \(error), not belongsToAnotherSource")
            }
            let sentence = error.localizedDescription
            XCTAssertTrue(sentence.contains("scan.h5") && sentence.contains("scan.dm4"), sentence)
        }
        XCTAssertEqual(try Data(contentsOf: sidecar), before, "the other source's session is untouched")
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: h5).source?.name, "scan.h5")
    }

    /// Each source keeps its own file: `scan.dm4` saves to `scan.dm4.mac4dstem.h5`, and both restore side by side.
    func testEachSourceRestoresItsOwnSessionSideBySide() throws {
        let h5 = try source("scan.h5", bytes: 40)
        let dm4 = try source("scan.dm4", bytes: 80)
        let own = BraggVectorEMDWriter.ownSessionSidecarURL(forSourcePath: dm4)
        XCTAssertEqual(own.lastPathComponent, "scan.dm4.mac4dstem.h5")
        XCTAssertEqual(SessionSidecarFormat.savePanelSeedName(for: own), "scan.dm4.mac4dstem")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        let other = PixelCalibration(rSize: 2.0, rUnits: "nm", qSize: 0.02, qUnits: "A^-1", qrFlip: false)
        try BraggVectorEMDWriter.mergeCalibration(
            other, qWidth: 16, qHeight: 16, to: own,
            source: SessionSourceStamp(sourcePath: dm4, shape: [4, 5, 16, 16]))
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: h5).calibration?.qSize, 0.01)
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: own, forSourcePath: dm4).calibration?.qSize, 0.02)
    }

    // MARK: A renamed source keeps its session

    /// `scan.h5` renamed to `scan_v2.h5` with its sidecar renamed beside it: the stamp still says `scan.h5`, which is
    /// gone, and the byte size is the same, so the session restores and the next save restamps it.
    func testARenamedSourceRestoresAndRestamps() throws {
        let h5 = try source("scan.h5", bytes: 40)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        let renamed = folder.appendingPathComponent("scan_v2.h5")
        let renamedSidecar = folder.appendingPathComponent("scan_v2.mac4dstem.h5")
        try FileManager.default.moveItem(atPath: h5, toPath: renamed.path)
        try FileManager.default.moveItem(at: sidecar, to: renamedSidecar)
        XCTAssertNotNil(try BraggVectorEMDWriter.loadSession(from: renamedSidecar, forSourcePath: renamed.path).calibration)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: renamedSidecar,
            source: SessionSourceStamp(sourcePath: renamed.path, shape: [4, 5, 8, 8]))
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: renamedSidecar).source?.name, "scan_v2.h5")
    }

    /// The same byte size is not enough while the stamped file is still there: that is two files, not a rename.
    func testTheSameSizeBesideTheStampedFileIsStillAnotherSource() throws {
        let h5 = try source("scan.h5", bytes: 40)
        let dm4 = try source("scan.dm4", bytes: 40)
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: h5, shape: [4, 5, 8, 8]))
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar, forSourcePath: dm4))
        XCTAssertThrowsError(try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: sidecar,
            source: SessionSourceStamp(sourcePath: dm4, shape: [4, 5, 8, 8])))
    }

    // MARK: The locator keeps the two apart

    func testTheLocatorMovesASourceToItsOwnNameAndForgetsTheForeignGrant() throws {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let dm4 = try source("scan.dm4")
        try Data("stands in for scan.h5's session".utf8).write(to: sidecar)
        let locator = SessionSidecarLocator(defaults: defaults)
        try locator.remember(sidecar, forSourcePath: dm4)
        XCTAssertEqual(locator.location(forSourcePath: dm4).lastPathComponent, "scan.mac4dstem.h5")

        XCTAssertTrue(locator.keepApart(forSourcePath: dm4, from: sidecar))
        XCTAssertEqual(locator.location(forSourcePath: dm4).lastPathComponent, "scan.dm4.mac4dstem.h5")
        XCTAssertFalse(locator.hasGrant)
        XCTAssertNil(SessionSidecarLocator(defaults: defaults).grant(forSourcePath: dm4), "the grant is forgotten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path), "the other source's file is untouched")
        XCTAssertFalse(locator.keepApart(forSourcePath: dm4, from: sidecar), "once apart, there is nothing to move from")

        // After a dataset change the stem name is the default again, until the own-named file exists.
        locator.release()
        XCTAssertEqual(locator.location(forSourcePath: dm4).lastPathComponent, "scan.mac4dstem.h5")
        try Data().write(to: folder.appendingPathComponent("scan.dm4.mac4dstem.h5"))
        XCTAssertEqual(locator.location(forSourcePath: dm4).lastPathComponent, "scan.dm4.mac4dstem.h5")
    }

    // MARK: The rule, pure

    func testTheRule() {
        let stamp = SessionSourceStamp(name: "scan.h5", bytes: 1, shape: [1, 1, 2, 2])
        let side = "scan.mac4dstem.h5"
        XCTAssertEqual(SessionSourceStamp.check(stamp, sourcePath: "/d/scan.h5", sidecarName: side,
                                                siblings: ["scan.h5", "scan.dm4", side]), .matches)
        guard case .refused = SessionSourceStamp.check(stamp, sourcePath: "/d/scan.dm4", sidecarName: side,
                                                       siblings: []) else { return XCTFail("another name is refused") }
        // Unstamped: the sidecar itself and unrelated names are not siblings.
        XCTAssertEqual(SessionSourceStamp.check(nil, sourcePath: "/d/scan.h5", sidecarName: side,
                                                siblings: ["scan.h5", side, "scan2.dm4", "other.h5"]), .matches)
        guard case .refused = SessionSourceStamp.check(nil, sourcePath: "/d/scan.h5", sidecarName: side,
                                                       siblings: ["scan.h5", "scan.emd"]) else {
            return XCTFail("an unstamped sidecar beside a sibling is refused")
        }
        // One source: the same name, or the same size with the stamped file gone.
        let renamed = SessionSourceStamp(name: "scan_v2.h5", bytes: 1, shape: [1, 1, 2, 2])
        XCTAssertTrue(stamp.isSameSource(as: renamed, stampedFileExists: false))
        XCTAssertFalse(stamp.isSameSource(as: renamed, stampedFileExists: true))
        XCTAssertFalse(stamp.isSameSource(as: SessionSourceStamp(name: "scan.dm4", bytes: 2, shape: [1, 1, 2, 2]),
                                          stampedFileExists: false))
        XCTAssertFalse(SessionSourceStamp(name: "scan.h5", bytes: nil, shape: [])
            .isSameSource(as: SessionSourceStamp(name: "scan.dm4", bytes: nil, shape: []), stampedFileExists: false),
                       "an unread size proves nothing")
    }

    func testTheStampRoundTripsAsJSONAndGarbageIsAbsent() {
        let stamp = SessionSourceStamp(name: "scan.h5", bytes: 123, shape: [4, 5, 8, 8])
        XCTAssertEqual(stamp.jsonString.flatMap(SessionSourceStamp.decoded(from:)), stamp)
        XCTAssertNil(SessionSourceStamp.decoded(from: "not json"))
    }
}
