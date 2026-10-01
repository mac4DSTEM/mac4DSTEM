//
//  DiskCentreLabelImportTests.swift
//  T3: "Import Labels…" — `DiskCentreLabelStore.importLabels` round-trips an export, refuses another
//  dataset's file and out-of-scan positions with one line and no change, and replaces existing labels.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class DiskCentreLabelImportTests: XCTestCase {
    private func source() -> DiskCentreLabelStore {
        let s = DiskCentreLabelStore()
        s.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        s.add(.init(row: 1.5, col: 2.5), ry: 0, rx: 1)
        s.add(.init(row: 3, col: 4), ry: 2, rx: 2)
        return s
    }

    func testImportRoundTripsAnExport() throws {
        let data = try source().encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertTrue(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", datasetPath: "/data", frame: "native", scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        XCTAssertEqual(target.positions, source().positions)
        XCTAssertNil(target.importRefusal)
    }

    func testImportRefusesAMismatchedCubePathWithOneLine() throws {
        let data = try source().encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/b/other.h5", datasetPath: "/data")
        target.add(.init(row: 9, col: 9), ry: 0, rx: 0)
        XCTAssertFalse(target.importLabels(from: data, fileName: "x.json", expecting: "/b/other.h5", datasetPath: "/data", frame: "native", scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        let line = try XCTUnwrap(target.importRefusal)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("cube.h5"))
        XCTAssertEqual(target.centreCount, 1)   // nothing changed
    }

    func testImportRefusesAPositionOutsideTheScan() throws {
        let data = try source().encodedJSON()   // has (2, 2)
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        target.add(.init(row: 9, col: 9), ry: 0, rx: 0)
        XCTAssertFalse(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", datasetPath: "/data", frame: "native", scanY: 2, scanX: 2, detectorY: 8, detectorX: 8))
        XCTAssertNotNil(target.importRefusal)
        XCTAssertEqual(target.positions, [.init(ry: 0, rx: 0, centres: [.init(row: 9, col: 9)])])
    }

    func testImportReplacesExistingLabelsAndClearsAnEarlierRefusal() throws {
        let data = try source().encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        target.add(.init(row: 9, col: 9), ry: 1, rx: 1)
        target.importLabels(from: Data("nope".utf8), fileName: "bad.json", expecting: "/a/cube.h5", datasetPath: "/data", frame: "native", scanY: 3, scanX: 3, detectorY: 8, detectorX: 8)
        XCTAssertNotNil(target.importRefusal)
        XCTAssertTrue(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", datasetPath: "/data", frame: "native", scanY: 3, scanX: 3, detectorY: 8, detectorX: 8))
        XCTAssertTrue(target.centres(ry: 1, rx: 1).isEmpty)   // the old label is gone
        XCTAssertEqual(target.centreCount, 2)
        XCTAssertNil(target.importRefusal)
    }

    private func importing(_ data: Data, into target: DiskCentreLabelStore, path: String = "/a/cube.h5",
                           dataset: String = "/data", frame: String = "native", detector: Int = 8) -> Bool {
        target.importLabels(from: data, fileName: "x.json", expecting: path, datasetPath: dataset, frame: frame,
                            scanY: 3, scanX: 3, detectorY: detector, detectorX: detector)
    }

    private func fresh() -> DiskCentreLabelStore {
        let t = DiskCentreLabelStore()
        t.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        t.add(.init(row: 9, col: 9), ry: 0, rx: 0)
        return t
    }

    /// CR2 B. A centre beyond the detector refuses with one line and changes nothing.
    /// Mutation: drop the detector-bounds check -> red.
    func testImportRefusesACentreOutsideTheDetector() throws {
        let data = try source().encodedJSON()   // centres (1.5, 2.5) and (3, 4)
        let target = fresh()
        XCTAssertFalse(importing(data, into: target, detector: 4))   // col 4 is outside a 4-wide detector
        let line = try XCTUnwrap(target.importRefusal)
        XCTAssertTrue(line.contains("detector"), line)
        XCTAssertEqual(target.centreCount, 1)
        XCTAssertTrue(importing(data, into: target, detector: 5))
    }

    /// CR2 B. A positive frame mismatch refuses (a crop's file in the full view, and a different crop); an ABSENT frame
    /// is checked by bounds only. Mutation: ignore `frame` -> red.
    func testImportRefusesAFrameMismatchButAcceptsAnAbsentFrame() throws {
        let cropped = LoadSpecification(scanCrop: AxisCrop(yOffset: 2, xOffset: 0, height: 3, width: 3),
                                        detectorCrop: nil, detectorBin: 2)
        let tag = DiskCentreLabelStore.frameTag(cropped)
        XCTAssertNotEqual(tag, "native")
        XCTAssertNotEqual(tag, DiskCentreLabelStore.frameTag(LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 3, width: 3), detectorCrop: nil, detectorBin: 2)))
        let croppedFile = try source().encodedJSON(frame: tag)
        var target = fresh()
        XCTAssertFalse(importing(croppedFile, into: target))   // this view is native
        XCTAssertTrue(try XCTUnwrap(target.importRefusal).contains("frame"))
        XCTAssertEqual(target.centreCount, 1)
        XCTAssertTrue(importing(croppedFile, into: target, frame: tag))
        // The native file into the cropped view: refused as well.
        target = fresh()
        XCTAssertFalse(importing(try source().encodedJSON(), into: target, frame: tag))
        // Absent frame: strip the key; bounds still apply.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try source().encodedJSON()) as? [String: Any])
        object.removeValue(forKey: "frame")
        let bare = try JSONSerialization.data(withJSONObject: object)
        target = fresh()
        XCTAssertTrue(importing(bare, into: target, frame: tag))
        target = fresh()
        XCTAssertFalse(importing(bare, into: target, detector: 4))
    }

    /// CR2 C. A different HDF5 dataset refuses and the store's datasetPath is not overwritten.
    /// Mutation: drop the dataset guard, or restore `datasetPath = decoded.datasetPath` -> red.
    func testImportRefusesAnotherHDF5DatasetAndKeepsTheStorePath() throws {
        let data = try source().encodedJSON()   // dataset "/data"
        let target = fresh()
        XCTAssertFalse(importing(data, into: target, dataset: "/other"))
        XCTAssertTrue(try XCTUnwrap(target.importRefusal).contains("/data"))
        XCTAssertEqual(target.datasetPath, "/data")
        XCTAssertEqual(target.centreCount, 1)
    }

    /// CR2 D. The mismatch line tells two same-named cubes apart (parent folder + name).
    /// Mutation: use lastPathComponent only -> red.
    func testMismatchLineNamesTheParentFolder() throws {
        let data = try source().encodedJSON()   // /a/cube.h5
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/b/cube.h5", datasetPath: "/data")
        XCTAssertFalse(importing(data, into: target, path: "/b/cube.h5"))
        let line = try XCTUnwrap(target.importRefusal)
        XCTAssertTrue(line.contains("a/cube.h5") && line.contains("b/cube.h5"), line)
    }
}
