//
//  SidecarSourceStampTests.swift
//  One sidecar name per stem: `scan.h5` and `scan.dm4` in one folder share `scan.mac4dstem.h5`, and opening one adopted
//  the other's calibration (the 2x binned conversion opened with Q off by 2). The writer now stamps the source
//  (`mac4dstem_source`: name, bytes, shape), and a restore checks it before anything is read.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

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
    }

    func testTheStampRoundTripsAsJSONAndGarbageIsAbsent() {
        let stamp = SessionSourceStamp(name: "scan.h5", bytes: 123, shape: [4, 5, 8, 8])
        XCTAssertEqual(stamp.jsonString.flatMap(SessionSourceStamp.decoded(from:)), stamp)
        XCTAssertNil(SessionSourceStamp.decoded(from: "not json"))
    }
}
