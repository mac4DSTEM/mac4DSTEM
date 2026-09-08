//
//  DiskCentreLabelTests.swift
//  C7 session 4: `DiskCentreLabelStore` (`Session/DiskCentreLabels.swift`) —
//  the hand-clicked disk-centre label store, its wire schema (the same JSON
//  `tools/disk-detector/label_centres.py` writes), the sidecar round trip
//  (`BraggVectorEMDWriter`'s `mac4dstem_disk_centre_labels` attribute), and
//  `AppState.toggleDiskCentre`'s refusal order.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

// MARK: - Store

@MainActor
final class DiskCentreLabelStoreTests: XCTestCase {

    func testAddCreatesAPositionAndAccumulatesCentres() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertTrue(store.isEmpty)
        store.add(.init(row: 1, col: 2), ry: 0, rx: 0)
        store.add(.init(row: 3, col: 4), ry: 0, rx: 0)
        XCTAssertEqual(store.centres(ry: 0, rx: 0).count, 2)
        XCTAssertEqual(store.labelledPositionCount, 1)
        XCTAssertEqual(store.centreCount, 2)
        XCTAssertFalse(store.isEmpty)
    }

    func testRemoveNearestRemovesOnlyTheClosestCentreWithinRadius() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 10, col: 10), ry: 1, rx: 1)
        store.add(.init(row: 10.5, col: 10.5), ry: 1, rx: 1)
        // Closer to the second centre than the first.
        let removed = store.removeNearest(to: .init(row: 10.4, col: 10.4), within: 3, ry: 1, rx: 1)
        XCTAssertTrue(removed)
        XCTAssertEqual(store.centres(ry: 1, rx: 1), [.init(row: 10, col: 10)])
    }

    /// Gate B 2026-09-08: the earlier test's nearer centre was also the LAST
    /// added, so "take the last within the radius" passed it. Here the nearer
    /// one was added first.
    func testRemoveNearestTakesTheNearerEvenWhenItWasAddedFirst() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 10, col: 10), ry: 0, rx: 0)
        store.add(.init(row: 12, col: 12), ry: 0, rx: 0)
        XCTAssertTrue(store.removeNearest(to: .init(row: 10.1, col: 10.1), within: 4, ry: 0, rx: 0))
        XCTAssertEqual(store.centres(ry: 0, rx: 0), [.init(row: 12, col: 12)])
    }

    /// Gate B 2026-09-08: `ingredient` and `seed` survive a tool-file round trip
    /// (a lossless re-save of `label_centres.py`'s output), and a fresh store
    /// writes "app" / 0.
    func testIngredientAndSeedSurviveALoadAndSave() throws {
        let store = DiskCentreLabelStore()
        let toolFile = Data("""
        {"cube": "/a/cube.h5", "dataset": "/data", "ingredient": "bullseye", "frame": "native", "seed": 1,
         "positions": [{"ry": 2, "rx": 3, "centres": [[10.0, 20.0]]}], "sha256": "x"}
        """.utf8)
        try store.load(from: toolFile, expecting: "/a/cube.h5")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try store.encodedJSON()) as? [String: Any])
        XCTAssertEqual(object["ingredient"] as? String, "bullseye")
        XCTAssertEqual(object["seed"] as? Int, 1)
        store.reset(filePath: "/b/cube.h5", datasetPath: "/data")
        let fresh = try XCTUnwrap(JSONSerialization.jsonObject(with: try store.encodedJSON()) as? [String: Any])
        XCTAssertEqual(fresh["ingredient"] as? String, "app")
        XCTAssertEqual(fresh["seed"] as? Int, 0)
    }

    /// Gate B 2026-09-08: nothing covered where the export lands or what it holds.
    func testExportWritesADecodableFileIntoTheGivenFolder() throws {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1.5, col: 2.5), ry: 0, rx: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("labels-\(UUID().uuidString)", isDirectory: true)
        let url = try store.exportForFineTuning(to: folder, datasetName: "cube")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("cube-centres-"), url.lastPathComponent)
        XCTAssertEqual(url.pathExtension, "json")
        let decoded = try DiskCentreLabelStore.decode(try Data(contentsOf: url))
        XCTAssertEqual(decoded.positions, [.init(ry: 0, rx: 1, centres: [.init(row: 1.5, col: 2.5)])])
    }

    func testRemoveNearestRefusesOutsideTheRadius() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 0, col: 0), ry: 2, rx: 2)
        let removed = store.removeNearest(to: .init(row: 50, col: 50), within: 3, ry: 2, rx: 2)
        XCTAssertFalse(removed, "50 px away is outside a 3 px radius — nothing should be removed")
        XCTAssertEqual(store.centres(ry: 2, rx: 2).count, 1)
    }

    func testClearEmptiesOnePositionAndLeavesOthersAlone() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1, col: 1), ry: 0, rx: 0)
        store.add(.init(row: 2, col: 2), ry: 1, rx: 1)
        store.clear(ry: 0, rx: 0)
        XCTAssertEqual(store.centres(ry: 0, rx: 0).count, 0)
        XCTAssertEqual(store.centres(ry: 1, rx: 1).count, 1)
        XCTAssertEqual(store.labelledPositionCount, 1, "position (0,0) still exists, just empty")
    }

    func testResetDropsEverythingAndBindsToTheNewDataset() {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1, col: 1), ry: 0, rx: 0)
        store.reset(filePath: "/b/cube.h5", datasetPath: "/other")
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.filePath, "/b/cube.h5")
        XCTAssertEqual(store.datasetPath, "/other")
    }

    // MARK: Wire schema

    func testEncodedJSONCarriesTheLabelCentresPySchema() throws {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/grp/data")
        store.add(.init(row: 12.5, col: 3), ry: 5, rx: 7)
        let data = try store.encodedJSON()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["cube"] as? String, "/a/cube.h5")
        XCTAssertEqual(object["dataset"] as? String, "/grp/data")
        XCTAssertEqual(object["ingredient"] as? String, "app")
        XCTAssertEqual(object["frame"] as? String, "native")
        XCTAssertNotNil(object["positions"])
        XCTAssertNotNil(object["sha256"] as? String)

        // Pin the centre encoding as a two-element [row, col] ARRAY, in that
        // order — not an object, and not [col, row].
        let positions = try XCTUnwrap(object["positions"] as? [[String: Any]])
        let position = try XCTUnwrap(positions.first { $0["ry"] as? Int == 5 && $0["rx"] as? Int == 7 })
        let centres = try XCTUnwrap(position["centres"] as? [[NSNumber]])
        let centre = try XCTUnwrap(centres.first)
        XCTAssertEqual(centre.count, 2)
        XCTAssertEqual(centre[0].doubleValue, 12.5, accuracy: 1e-6, "index 0 must be row")
        XCTAssertEqual(centre[1].doubleValue, 3, accuracy: 1e-6, "index 1 must be col")
    }

    func testDecodeOfEncodeRoundTripsThePositions() throws {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1.5, col: 2.5), ry: 0, rx: 0)
        store.add(.init(row: 9, col: 9), ry: 0, rx: 0)
        store.add(.init(row: 4, col: 4), ry: 1, rx: 2)
        let data = try store.encodedJSON()
        let decoded = try DiskCentreLabelStore.decode(data)
        XCTAssertEqual(decoded.filePath, "/a/cube.h5")
        XCTAssertEqual(decoded.datasetPath, "/data")
        // Insertion order, preserved end to end by JSON arrays: (0,0) was
        // added to first, (1,2) second.
        XCTAssertEqual(decoded.positions.map { Pair($0.ry, $0.rx) }, [Pair(0, 0), Pair(1, 2)])
        let p00 = try XCTUnwrap(decoded.positions.first { $0.ry == 0 && $0.rx == 0 })
        XCTAssertEqual(p00.centres, [.init(row: 1.5, col: 2.5), .init(row: 9, col: 9)])
    }

    func testLoadRefusesADifferentCubeAndLeavesTheStoreEmpty() throws {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1, col: 1), ry: 0, rx: 0)
        let foreign = try store.encodedJSON()   // recorded cube: "/a/cube.h5"

        let target = DiskCentreLabelStore()
        target.reset(filePath: "/b/cube.h5", datasetPath: "/other")
        XCTAssertThrowsError(try target.load(from: foreign, expecting: "/b/cube.h5")) { error in
            XCTAssertTrue(error.localizedDescription.contains("/a/cube.h5"), error.localizedDescription)
        }
        XCTAssertTrue(target.isEmpty, "a mismatched load must keep nothing from the foreign file")
        XCTAssertEqual(target.filePath, "/b/cube.h5", "the binding from reset() survives a refused load")
    }

    func testLoadAdoptsAMatchingCube() throws {
        let store = DiskCentreLabelStore()
        store.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        store.add(.init(row: 1, col: 1), ry: 0, rx: 0)
        let data = try store.encodedJSON()

        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        try target.load(from: data, expecting: "/a/cube.h5")
        XCTAssertEqual(target.centreCount, 1)
        XCTAssertEqual(target.centres(ry: 0, rx: 0), [.init(row: 1, col: 1)])
    }
}

/// A tiny `Equatable` pair — `XCTAssertEqual` needs a conforming type, and a
/// bare tuple does not conform to any protocol.
private struct Pair: Equatable {
    let a: Int, b: Int
    init(_ a: Int, _ b: Int) { self.a = a; self.b = b }
}

// MARK: - Writer round trip

final class DiskCentreLabelSidecarTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskCentreLabelSidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private let calibration = PixelCalibration(
        rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false
    )

    func testMergeCalibrationWritesAndReadsBackTheLabelsAttribute() throws {
        let url = workDirectory.appendingPathComponent("labels.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url,
            diskCentreLabelsJSON: "{\"cube\":\"x\"}"
        )
        XCTAssertEqual(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: url), "{\"cube\":\"x\"}")
    }

    func testASecondCalibrationSaveWithNilPreservesTheLabels() throws {
        let url = workDirectory.appendingPathComponent("labels.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url,
            diskCentreLabelsJSON: "{\"cube\":\"x\"}"
        )
        // A second, unrelated calibration save — nil says nothing about
        // labels, which must NOT be read as "erase them."
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: url)
        XCTAssertEqual(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: url), "{\"cube\":\"x\"}")
    }

    func testAThirdSaveWithANewStringReplacesIt() throws {
        let url = workDirectory.appendingPathComponent("labels.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url,
            diskCentreLabelsJSON: "{\"cube\":\"x\"}"
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 8, qHeight: 8, to: url,
            diskCentreLabelsJSON: "{\"cube\":\"y\"}"
        )
        XCTAssertEqual(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: url), "{\"cube\":\"y\"}")
    }

    func testAFreshFileHasNoLabelsAttribute() throws {
        let url = workDirectory.appendingPathComponent("fresh.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 8, qHeight: 8, to: url)
        XCTAssertNil(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: url))
    }

    func testANonexistentFileReturnsNilRatherThanThrowing() throws {
        let url = workDirectory.appendingPathComponent("never-written.mac4dstem.h5")
        XCTAssertNil(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: url))
    }
}

// MARK: - AppState.toggleDiskCentre

@MainActor
final class ToggleDiskCentreTests: XCTestCase {

    func testRefusesWithNoDatasetOpen() {
        let state = AppState()
        let outcome = state.toggleDiskCentre(atPatternRow: 1, col: 1)
        XCTAssertEqual(outcome, .failed("No dataset is open."))
    }

    func testRefusesOutsideCurrentPatternDisplay() {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data",
            shape: [4, 4, 16, 16], dtypeDescription: "float32", chunkShape: nil
        )
        state.patternDisplayMode = .mean
        state.diskCentreLabels.labelling = true
        let outcome = state.toggleDiskCentre(atPatternRow: 1, col: 1)
        XCTAssertEqual(outcome, .failed(
            "Switch the pattern display to Current — Mean and Max have no single scan position to label"
        ))
    }

    func testRefusesWhileTheToggleIsOff() {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data",
            shape: [4, 4, 16, 16], dtypeDescription: "float32", chunkShape: nil
        )
        state.patternDisplayMode = .current
        state.diskCentreLabels.labelling = false
        let outcome = state.toggleDiskCentre(atPatternRow: 1, col: 1)
        XCTAssertEqual(outcome, .failed("Turn on \"Label centres on click\" in Disk detection first"))
    }

    /// Gate B 2026-09-08: the pane's tap catcher maps its border to −0.5 and
    /// q − 0.5, so a border click must be refused rather than stored off-detector.
    func testRefusesAClickOutsideThePattern() {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data",
            shape: [4, 4, 16, 16], dtypeDescription: "float32", chunkShape: nil
        )
        state.patternDisplayMode = .current
        state.diskCentreLabels.labelling = true
        XCTAssertEqual(state.toggleDiskCentre(atPatternRow: 16, col: 1), .failed("That click landed outside the pattern"))
        XCTAssertEqual(state.toggleDiskCentre(atPatternRow: 1, col: -0.5), .failed("That click landed outside the pattern"))
        XCTAssertTrue(state.diskCentreLabels.isEmpty)
    }

    func testClickAddsThenTheSameClickRemoves() async throws {
        let state = AppState()
        await state.openDemoFixture()
        state.patternDisplayMode = .current
        state.diskCentreLabels.labelling = true
        let (ry, rx) = (state.selectedScan.y, state.selectedScan.x)

        let added = state.toggleDiskCentre(atPatternRow: 12, col: 15)
        XCTAssertEqual(added, .published)
        XCTAssertEqual(state.diskCentreLabels.centres(ry: ry, rx: rx).count, 1)

        // Same point again: within the 3 px radius of what was just added.
        let removed = state.toggleDiskCentre(atPatternRow: 12, col: 15)
        XCTAssertEqual(removed, .published)
        XCTAssertEqual(state.diskCentreLabels.centres(ry: ry, rx: rx).count, 0)
    }
}
