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
        XCTAssertTrue(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", scanY: 3, scanX: 3))
        XCTAssertEqual(target.positions, source().positions)
        XCTAssertNil(target.importRefusal)
    }

    func testImportRefusesAMismatchedCubePathWithOneLine() throws {
        let data = try source().encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/b/other.h5", datasetPath: "/data")
        target.add(.init(row: 9, col: 9), ry: 0, rx: 0)
        XCTAssertFalse(target.importLabels(from: data, fileName: "x.json", expecting: "/b/other.h5", scanY: 3, scanX: 3))
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
        XCTAssertFalse(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", scanY: 2, scanX: 2))
        XCTAssertNotNil(target.importRefusal)
        XCTAssertEqual(target.positions, [.init(ry: 0, rx: 0, centres: [.init(row: 9, col: 9)])])
    }

    func testImportReplacesExistingLabelsAndClearsAnEarlierRefusal() throws {
        let data = try source().encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        target.add(.init(row: 9, col: 9), ry: 1, rx: 1)
        target.importLabels(from: Data("nope".utf8), fileName: "bad.json", expecting: "/a/cube.h5", scanY: 3, scanX: 3)
        XCTAssertNotNil(target.importRefusal)
        XCTAssertTrue(target.importLabels(from: data, fileName: "x.json", expecting: "/a/cube.h5", scanY: 3, scanX: 3))
        XCTAssertTrue(target.centres(ry: 1, rx: 1).isEmpty)   // the old label is gone
        XCTAssertEqual(target.centreCount, 2)
        XCTAssertNil(target.importRefusal)
    }
}
