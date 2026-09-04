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

    /// The results-rich sidecar, which the calibration-only test above does
    /// not reach. Found by `run-tests.sh all` on 2026-09-04: the aggregate
    /// gate exited 1 in `real-data-acceptance` on a real sidecar the owner's
    /// own driving had written beside a training cube.
    ///
    /// MECHANISM: `describe(path:)` accepts rank 3 and promotes it to
    /// `[1, d0, d1, d2]` — correct for a genuine single-row datacube. An RGBA
    /// result map is stored `{height, width, 4}`, which is also rank 3, so the
    /// link-visit search "finds a 4D datacube" in a saved IPF map and
    /// discovery SUCCEEDS. The sidecar check never runs, because it is
    /// deliberately placed after the search. The caller gets a descriptor
    /// whose detector is `width × 4` instead of the sentence naming the file.
    func testAResultsRichSidecarIsStillRecognisedAndNotReadAsADatacube() async throws {
        let url = workDirectory.appendingPathComponent("results.mac4dstem.h5")
        let calibration = PixelCalibration(
            rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false
        )
        // Shaped like the file that broke the gate: an RGBA orientation map,
        // stored as {height, width, 4} — rank 3, and the trap.
        let width = 200, height = 50
        let map = RGBAResultMap(
            width: width, height: height,
            rgba: [UInt8](repeating: 128, count: width * height * 4),
            kind: "acom_full_ipf_z",
            displayName: "ACOM full scan · IPF · Z",
            valueUnits: "dimensionless"
        )
        try BraggVectorEMDWriter.mergeRGBAResultMap(
            map, vectors: nil, qWidth: 128, qHeight: 128,
            calibration: calibration, to: url
        )

        let reader = try H5Reader(path: url.path)

        // PIN THE TRAP ITSELF, not just the refusal. Without this the test
        // cannot tell "the rank-3 trap was written and skipped" from "no trap
        // was ever written": both end at the same `throw`, so if the writer
        // ever changed rank or stopped emitting the map, this would silently
        // become a duplicate of the calibration-only test above and stay
        // green. Raised by the Gate B refuters, 2026-09-04 — the wrong-reason
        // pass this repo has been bitten by three times.
        let trapPath = "/" + SessionSidecarFormat.rootGroupName + "/"
            + BraggVectorEMDWriter.resultNodeName(forKind: "acom_full_ipf_z") + "/data"
        let trap = try reader.describe(path: trapPath)
        XCTAssertEqual(
            trap.shape, [1, height, width, 4],
            "The fixture must contain the rank-3 array that `describe` promotes; "
            + "without it this test proves nothing about the defect."
        )
        XCTAssertTrue(trap.is4D, "`is4D` is a tautology after padding — that IS the trap.")

        do {
            let descriptor = try await reader.discoverPrimaryDataset()
            XCTFail(
                "A sidecar holds no datacube by design. Discovery returned "
                + "shape \(descriptor.shape) from \(descriptor.datasetPath) — "
                + "a saved RGBA result read as a cube."
            )
        } catch let error as H5Error {
            guard case .sessionSidecarOpened(let sidecar, let suggestedSource) = error else {
                return XCTFail("Expected sessionSidecarOpened, got: \(error.localizedDescription)")
            }
            XCTAssertEqual(sidecar, "results.mac4dstem.h5")
            XCTAssertEqual(suggestedSource, "results")
        }
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
