//
//  ExportRecipeFrameTests.swift
//  A datacube export that thins the scan or crops the detector carries the
//  session's recipe, re-expressed in the exported file's own detector frame
//  (crop, then bin — the writer's order). Before, both left the recipe out.
//

import XCTest
import FormatoHDF5
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ExportRecipeFrameTests: XCTestCase {

    private func step(_ kind: String, _ parameters: [String: String]) -> SessionReplayRecord {
        var record = SessionReplayRecord()
        record.record(kind: kind, parameters: parameters, at: Date(timeIntervalSince1970: 0))
        return record
    }

    /// Positions lose the crop offset, then bin about the pixel grid; lengths
    /// only bin. Column offset 8, row offset 4, bin 2: (31.5 - 8 + 0.5) / 2 - 0.5
    /// = 11.5 and (30 - 4 + 0.5) / 2 - 0.5 = 12.75.
    func testACroppedAndBinnedExportReExpressesPositionsInTheFilesFrame() throws {
        let record = step("virtual_detector", ["shape": "Annulus", "center_x": "31.5", "center_y": "30.0",
                                               "inner": "3.0", "outer": "9.0"])
        let (carried, omission) = ReplayRecordFrameMap.exportableRecipe(
            record: record, recordedFrame: .detectorIdentity, currentSpecification: LoadSpecification(),
            exportBin: 2, cropXOffset: 8, cropYOffset: 4)
        XCTAssertNil(omission)
        let p = try XCTUnwrap(carried?.steps.first?.parameters)
        XCTAssertEqual(p["center_x"], String(Float(11.5)))
        XCTAssertEqual(p["center_y"], String(Float(12.75)))
        XCTAssertEqual(p["inner"], String(Float(1.5)), "a length ignores the crop")
        XCTAssertEqual(p["outer"], String(Float(4.5)))
    }

    /// A crop alone (bin 1) still moves positions: it is not the identity.
    func testACropAtBinOneShiftsPositionsOnly() throws {
        let record = step("virtual_detector", ["shape": "Circle", "center_x": "31.5", "center_y": "30.0",
                                               "inner": "0.0", "outer": "9.0"])
        let mapped = try ReplayRecordFrameMap.mapForExport(record, exportBin: 1, cropXOffset: 8, cropYOffset: 4).get()
        XCTAssertEqual(mapped.steps[0].parameters["center_x"], String(Float(23.5)))
        XCTAssertEqual(mapped.steps[0].parameters["center_y"], String(Float(26.0)))
        XCTAssertEqual(mapped.steps[0].parameters["outer"], String(Float(9.0)))
    }

    /// A crop that leaves the aperture centre off the exported detector drops
    /// the recipe by name instead of stamping a centre at -7 px.
    func testACropThatLeavesAPositionOffTheDetectorOmitsTheRecipeByName() {
        let record = step("virtual_detector", ["shape": "Circle", "center_x": "3.0", "center_y": "20.0",
                                               "inner": "0.0", "outer": "2.0"])
        let (carried, omission) = ReplayRecordFrameMap.exportableRecipe(
            record: record, recordedFrame: .detectorIdentity, currentSpecification: LoadSpecification(),
            exportBin: 1, cropXOffset: 10, cropYOffset: 0, exportedWidth: 40, exportedHeight: 40)
        XCTAssertNil(carried)
        XCTAssertTrue(omission?.contains("center_x") == true, omission ?? "nil")
    }

    /// Through the export door: a thinned scan and a cropped, binned detector
    /// write the recipe into the file's root, in the file's frame. Mutation it
    /// catches: the old gate that left the recipe out of any thinned or cropped
    /// export (the attribute was absent).
    func testAThinnedCroppedExportWritesTheRecipeInTheFilesFrame() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-recipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let state = AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
        let descriptor = VoltageFixtureSource.descriptor   // scan 2 × 3, detector 4 × 6
        let load = state.beginDatasetLoading("Opening…")
        await state.activate(descriptor: descriptor, reader: VoltageFixtureSource(voltage: nil), runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)

        state.recordReplayStep(kind: "virtual_detector",
                               parameters: ["shape": "Circle", "center_x": "3.5", "center_y": "1.5",
                                            "inner": "0.0", "outer": "2.0"],
                               replaying: false)
        let options = CalibratedDataCubeExportOptions(scanY: 0..<2, scanX: 0..<3, qBin: 2, scanStride: 2,
                                                      qCropY: 0..<4, qCropX: 2..<6)
        let url = directory.appendingPathComponent("thinned-cropped.h5")
        let outcome: DataCubeWriteOutcome = await withCheckedContinuation { continuation in
            state.exportCalibratedDataCube(options: options, to: url, progress: { _ in },
                                           finish: { continuation.resume(returning: $0) })
        }
        guard case .wrote = outcome else { return XCTFail("the export did not write: \(outcome)") }

        let attribute = try HDF5Reader(url: url).attribute(SessionSidecarFormat.replayRecordAttribute,
                                                           of: "/datacube_root")
        let json: String
        switch attribute {
        case .text(let text): json = text
        case .texts(let texts) where texts.count == 1: json = texts[0]
        default: return XCTFail("the recipe attribute is not one string: \(attribute)")
        }
        let record = try XCTUnwrap(SessionReplayRecord.parse(json))
        let p = try XCTUnwrap(record.steps.first?.parameters)
        // x: (3.5 - 2 + 0.5) / 2 - 0.5 = 0.5; y: (1.5 - 0 + 0.5) / 2 - 0.5 = 0.5; outer 2 / 2 = 1.
        XCTAssertEqual(p["center_x"], String(Float(0.5)))
        XCTAssertEqual(p["center_y"], String(Float(0.5)))
        XCTAssertEqual(p["outer"], String(Float(1.0)))
    }
}
