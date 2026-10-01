//
//  CR3ReviewFixTests.swift
//  Lane CR3 (code review round 3, 2026-10-01): the dataset-path spelling of a tool-written labels file, the view
//  frame of a restored sidecar's labels, the Preprocess destination guard, and the peak-grid shape read.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class CR3ReviewFixTests: XCTestCase {
    private func store(_ path: String = "/a/cube.h5") -> DiskCentreLabelStore {
        let s = DiskCentreLabelStore()
        s.reset(filePath: path, datasetPath: "/data")
        s.add(.init(row: 1.5, col: 2.5), ry: 0, rx: 1)
        s.add(.init(row: 3, col: 4), ry: 2, rx: 2)
        return s
    }

    private let cropped = LoadSpecification(scanCrop: AxisCrop(yOffset: 2, xOffset: 0, height: 3, width: 3),
                                            detectorCrop: nil, detectorBin: 2)

    private func restoring(_ data: Data, into target: DiskCentreLabelStore, frame: String = "native",
                           detector: Int = 8) throws -> Bool {
        try target.restore(from: data, expecting: "/a/cube.h5", frame: frame,
                           scanY: 3, scanX: 3, detectorY: detector, detectorX: detector)
    }

    // MARK: 1 — the dataset spelling

    /// The committed tool-written file names its dataset without a leading "/", the app's path carries one.
    /// Mutation: compare the raw strings -> red.
    func testTheCommittedToolFileImportsAgainstTheAppsSlashedDatasetPath() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/disk-detector/labels/bullseye-2026-09-28.json")
        let data = try Data(contentsOf: url)
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cube = try XCTUnwrap(header["cube"] as? String)
        let dataset = try XCTUnwrap(header["dataset"] as? String)
        XCTAssertFalse(dataset.hasPrefix("/"), "precondition: the tool writes no leading slash")
        let frame = try XCTUnwrap(header["frame"] as? String)
        let target = DiskCentreLabelStore()
        target.reset(filePath: cube, datasetPath: "/" + dataset)
        XCTAssertTrue(target.importLabels(from: data, fileName: "bullseye.json", expecting: cube, datasetPath: "/" + dataset,
                                          frame: frame, scanY: 10_000, scanX: 10_000, detectorY: 10_000, detectorX: 10_000),
                      target.importRefusal ?? "")
        XCTAssertGreaterThan(target.centreCount, 0)
        // A genuinely different dataset still refuses.
        let other = DiskCentreLabelStore()
        other.reset(filePath: cube, datasetPath: "/other/data")
        XCTAssertFalse(other.importLabels(from: data, fileName: "bullseye.json", expecting: cube, datasetPath: "/other/data",
                                          frame: frame, scanY: 10_000, scanX: 10_000, detectorY: 10_000, detectorX: 10_000))
    }

    // MARK: 2 — the restored labels' frame

    /// Saved in a cropped view, restored in the full view: not applied, one line, store empty.
    /// Mutation: skip the frame check in `restore` -> red.
    func testLabelsSavedInACroppedViewAreNotAppliedInTheFullView() throws {
        let tag = DiskCentreLabelStore.frameTag(cropped)
        let data = try store().encodedJSON(frame: tag)
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertFalse(try restoring(data, into: target))
        XCTAssertEqual(target.centreCount, 0)
        XCTAssertTrue(try XCTUnwrap(target.importRefusal).contains("frame"))
        XCTAssertTrue(try restoring(data, into: target, frame: tag))   // the same view applies
        XCTAssertEqual(target.centreCount, 2)
    }

    /// An older sidecar without a frame: in bounds applies, out of bounds refuses.
    /// Mutation: skip the bounds check in `restore` -> red.
    func testASidecarWithoutAFrameIsCheckedByBoundsOnly() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try store().encodedJSON()) as? [String: Any])
        object.removeValue(forKey: "frame")
        let bare = try JSONSerialization.data(withJSONObject: object)
        let inBounds = DiskCentreLabelStore()
        inBounds.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertTrue(try restoring(bare, into: inBounds))
        XCTAssertEqual(inBounds.centreCount, 2)
        let outOfBounds = DiskCentreLabelStore()
        outOfBounds.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertFalse(try restoring(bare, into: outOfBounds, detector: 4))
        XCTAssertEqual(outOfBounds.centreCount, 0)
        XCTAssertNotNil(outOfBounds.importRefusal)
    }

    /// A restore of another cube's labels still throws, as `load` did.
    func testRestoreStillRefusesAnotherCube() throws {
        let data = try store("/b/cube.h5").encodedJSON()
        let target = DiskCentreLabelStore()
        target.reset(filePath: "/a/cube.h5", datasetPath: "/data")
        XCTAssertThrowsError(try restoring(data, into: target))
    }

    // MARK: 4 — the Preprocess destination

    /// The source file, its sidecar, and a symlink to the source all refuse; a new name does not.
    /// Mutation: drop either comparison -> red.
    func testPreprocessDestinationRefusesTheSourceAndItsSidecar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cr3-dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("raw.h5")
        try Data([1]).write(to: source)
        let link = directory.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: source.path)
        XCTAssertNotNil(BraggVectorEMDWriter.exportDestinationRefusal(source, sourcePath: source.path))
        XCTAssertNotNil(BraggVectorEMDWriter.exportDestinationRefusal(link, sourcePath: source.path))
        XCTAssertNotNil(BraggVectorEMDWriter.exportDestinationRefusal(sidecar, sourcePath: source.path))
        XCTAssertNil(BraggVectorEMDWriter.exportDestinationRefusal(
            directory.appendingPathComponent("raw_preprocessed.h5"), sourcePath: source.path))
    }

    /// The Core entry refuses too, before any write, and leaves the file as it was.
    /// Mutation: drop the guard in `writeCalibratedDataCube` -> red (the write would replace the file).
    func testTheCoreWriteRefusesToReplaceItsSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cr3-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let d = PreprocessFixtureSource.descriptor
        let descriptor = DatasetDescriptor(filePath: directory.appendingPathComponent("raw.h5").path, datasetPath: d.datasetPath,
                                           shape: d.shape, dtypeDescription: d.dtypeDescription, chunkShape: nil)
        let raw = Data("raw cube".utf8)
        try raw.write(to: URL(fileURLWithPath: descriptor.filePath))
        let options = CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry, scanX: 0..<descriptor.rx)
        do {
            _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: PreprocessFixtureSource(), view: LoadView(fullExtentOf: descriptor),
                calibration: PixelCalibration(), options: options, to: URL(fileURLWithPath: descriptor.filePath))
            XCTFail("the write must refuse")
        } catch {
            XCTAssertTrue("\(error)".contains("source is never changed") || error.localizedDescription.contains("source is never changed"),
                          "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: descriptor.filePath)), raw)
    }

    // MARK: 5 — the peak-grid shape read

    /// A foreign sidecar whose Qshape holds three values is refused, not read past the two-element buffer.
    /// Mutation: drop the element-count check in `readInt64Vector` -> red (or a heap overrun).
    func testAQshapeWithThreeElementsIsRefused() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/qshape3.mac4dstem.h5")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cr3-qshape-\(UUID().uuidString).h5")
        try FileManager.default.copyItem(at: fixture, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadPeakGrid(from: copy))
    }
}
