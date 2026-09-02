//
//  SidecarRecognitionTests.swift
//  Pins v2 S4's open-path answer when the file is one of this app's own
//  session sidecars: one sentence naming what the file is, instead of a
//  30-line wall of tried paths. The release owner — who designed the format —
//  picked the sidecar over the cube twice in one afternoon (2026-08-19); the
//  open panel offers both and they sort adjacently, so this failure mode is
//  expected, not exotic.
//
//  The fixture is written by the PRODUCTION writer, calibration-only on
//  purpose: that is exactly the 8.9 kB file both incidents opened, and until
//  S4 the writer only stamped the schema attribute when result nodes existed —
//  so a calibration-only sidecar was unrecognisable by construction. This test
//  pins both halves at once: the writer stamps every sidecar, and the reader
//  answers with the sentence.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SidecarRecognitionTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarRecognitionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    func testOpeningACalibrationOnlySidecarNamesWhatItIsAndTheSibling() async throws {
        let url = workDirectory.appendingPathComponent("fixture.mac4dstem.h5")
        let calibration = PixelCalibration(
            rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url
        )

        let reader = try H5Reader(path: url.path)
        do {
            _ = try await reader.discoverPrimaryDataset()
            XCTFail("A sidecar contains no datacube by design — discovery succeeding means the fixture is wrong")
        } catch let error as H5Error {
            guard case .sessionSidecarOpened(let sidecar, let suggestedSource) = error else {
                return XCTFail("Expected sessionSidecarOpened, got: \(error.localizedDescription)")
            }
            XCTAssertEqual(sidecar, "fixture.mac4dstem.h5")
            // The suggestion is the source's STEM, never a filename: the
            // naming rule strips ANY extension (`<stem>.mac4dstem.h5` beside
            // `<stem>.<ext>`), so a sidecar saved beside `Scan.dm4` must not
            // send the user hunting for a `Scan.h5` that never existed.
            XCTAssertEqual(suggestedSource, "fixture")
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("session sidecar"), message)
            XCTAssertTrue(message.contains("“fixture”"), message)
            XCTAssertFalse(message.contains("fixture.h5"),
                           "The message must not assert an extension the source may not have")
            XCTAssertFalse(message.contains("Tried paths"),
                           "The recognition sentence must replace the path wall, not join it")
        }
    }

    func testARenamedSidecarIsStillRecognisedWithoutInventingASibling() async throws {
        // A sidecar renamed away from the convention (the F1.3i scenario, now
        // reachable again via Save As) cannot name its cube — the message must
        // not guess one.
        let url = workDirectory.appendingPathComponent("crop-test.h5")
        let calibration = PixelCalibration(
            rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url
        )

        let reader = try H5Reader(path: url.path)
        do {
            _ = try await reader.discoverPrimaryDataset()
            XCTFail("Discovery must not succeed on a sidecar")
        } catch let error as H5Error {
            guard case .sessionSidecarOpened(let sidecar, let suggestedSource) = error else {
                return XCTFail("Expected sessionSidecarOpened, got: \(error.localizedDescription)")
            }
            XCTAssertEqual(sidecar, "crop-test.h5")
            XCTAssertNil(suggestedSource,
                         "A non-convention name gives no honest sibling to suggest")
        }
    }

    func testTheNoDatasetPathWallIsCappedForOrdinaryFiles() {
        // The recognition sentence handles sidecars; every OTHER file of this
        // error shape keeps a list, but a capped one.
        let paths = (0..<30).map { "/probe/path\($0)" }
        let message = H5Error.noDatasetFound(paths).localizedDescription
        XCTAssertTrue(message.contains("/probe/path7"), message)
        XCTAssertFalse(message.contains("/probe/path8\n"), message)
        XCTAssertTrue(message.contains("and 22 more paths"), message)
    }

    func testAShortPathListIsNotDecoratedWithARemainder() {
        let message = H5Error.noDatasetFound(["/a", "/b"]).localizedDescription
        XCTAssertTrue(message.contains("/a"), message)
        XCTAssertFalse(message.contains("more paths"), message)
    }
}
