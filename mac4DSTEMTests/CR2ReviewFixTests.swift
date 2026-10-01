//
//  CR2ReviewFixTests.swift
//  Lane CR2 (code review round 2, 2026-10-01): the label-import read error (D) and the same-unit guard (A).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class CR2ReviewFixTests: XCTestCase {
    /// D. A file that cannot be read reports the read error, not a JSON one.
    /// Mutation: pass `Data()` to `importLabels` on a read failure -> red.
    func testUnreadableFileReportsTheReadError() throws {
        let state = AppState()
        let descriptor = DatasetDescriptor(filePath: "/a/cube.h5", datasetPath: "/data", shape: [2, 2, 4, 4],
                                           dtypeDescription: "float32", chunkShape: nil)
        state.descriptor = descriptor
        state.diskCentreLabels.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        let missing = URL(fileURLWithPath: "/nonexistent-cr2/labels.json")
        state.importDiskCentreLabels(from: missing, descriptor: descriptor)
        let line = try XCTUnwrap(state.diskCentreLabels.importRefusal)
        XCTAssertTrue(line.contains("labels.json"), line)
        XCTAssertFalse(line.lowercased().contains("labels could not be read"), line)   // the JSON wording
        XCTAssertTrue(line.lowercased().contains("couldn") || line.lowercased().contains("no such") || line.lowercased().contains("doesn"), line)
    }

    /// A. A file's raw "A^-1" re-picked as the canonical "Å⁻¹" is the same unit: no lineage node, provenance unchanged.
    /// Mutation: compare the raw stored string with the canonical one (the CR1 guard) -> red.
    func testRawStoredUnitRepickedAsCanonicalChangesNothing() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.calibrationSession.calibration.qPixelSize = 0.12
        state.calibrationSession.calibration.qPixelUnits = "A^-1"      // py4DSTEM's spelling
        state.calibrationSession.provenance.qScale = .importedFile
        let before = state.replay.lineage.activeNodes().count
        state.setManualQPixelUnits("Å⁻¹")
        XCTAssertEqual(state.replay.lineage.activeNodes().count, before, "no new lineage node")
        XCTAssertNil(state.replay.lineage.activeNodes().first { $0.kind == "calibration_q" })
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .importedFile, "provenance stays the file's")
        XCTAssertEqual(state.calibrationSession.calibration.qPixelUnits, "A^-1")
        state.setManualQPixelUnits("nm⁻¹")   // a real change still lands
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .manual)
    }
}
