//
//  PolishGTests.swift
//  Lane G (Slot 4½, owner cards S4 a and S5 items 1 and 4, 2026-10-02): the label export writes where it is told, an instant step
//  names itself as the last run, and the Add Phase menu says why a listed model is offered again.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishGTests: XCTestCase {
    private func model() -> CrystalModel {
        CrystalModel(id: "al", displayName: "Al", crystal: Crystal.cubic(.fcc, a: 4.05, z: 13),
                     symmetry: .cubic, source: .imported)
    }

    /// S4. The chosen URL receives the same bytes `exportForFineTuning` writes, and the status names the file.
    /// Mutation: write to the Documents folder (ignore `url`) -> the file at `url` is missing -> red.
    func testLabelExportWritesTheChosenURLWithTheSameBytes() throws {
        let state = AppState()
        state.diskCentreLabels.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        state.diskCentreLabels.add(.init(row: 1.5, col: 2.5), ry: 0, rx: 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("polishG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("chosen-name.json")
        XCTAssertEqual(state.exportDiskCentreLabels(to: url, frame: "native"), .published)
        let reference = try state.diskCentreLabels.exportForFineTuning(to: dir.appendingPathComponent("ref"), datasetName: "cube")
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: reference))
        XCTAssertEqual(state.statusText, "Exported disk-centre labels → chosen-name.json")
    }

    /// S5(1). An instant step is the last run; the next `begin` clears it.
    /// Mutation: make `recordInstant` a no-op -> `lastFinished` stays nil / the earlier run -> red.
    func testInstantStepNamesItselfAsTheLastRun() {
        let center = OperationCenter()
        let token = center.begin(name: "Origin calibration", totalUnits: nil)
        center.finish(token)
        XCTAssertEqual(center.lastFinished?.name, "Origin calibration")
        center.recordInstant(name: "Probe kernel", elapsed: 0.25)
        XCTAssertEqual(center.lastFinished?.name, "Probe kernel")
        XCTAssertEqual(center.lastFinished?.elapsed, 0.25)
        XCTAssertEqual(center.lastFinished?.outcome, .completed)
        XCTAssertFalse(center.isBusy)
        _ = center.begin(name: "Detection", totalUnits: nil)
        XCTAssertNil(center.lastFinished)
        // While an operation runs the instant step does not claim the line.
        center.recordInstant(name: "Aberration fit", elapsed: 0.1)
        XCTAssertNil(center.lastFinished)
    }

    /// S5(4). Mutation: ignore `alreadyAdded` -> the second string is unmarked -> red.
    func testAddPhaseMenuLabelMarksAnAlreadyAddedModel() {
        let m = model()
        XCTAssertEqual(addPhaseMenuLabel(m, alreadyAdded: false), "Imported: Al")
        XCTAssertEqual(addPhaseMenuLabel(m, alreadyAdded: true), "Imported: Al (another zone axis)")
    }
}
