//
//  LegacySessionDiskRestoreTests.swift
//  The Bragg disks a schema-5 session sidecar stores come back on open.
//
//  A schema-5 sidecar records no view at whole file and has no replay record
//  (both arrived with schema 6). Two gates used to drop its disks: the
//  unrecorded view was refused even on a whole-file load, and the missing
//  disk-detection step returned without a word. The writer recorded a load
//  specification for every reduced view while still at schema 5, so an
//  unrecorded schema-5 file was written at whole file; its disks are restored
//  there on the shape checks alone, and still refused on a reduced view.
//
//  The sidecar is written by the production writer and its schema stamp
//  patched to "5", the attribute set a pre-2026-08-24 writer left.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class LegacySessionDiskRestoreTests: XCTestCase {

    private struct Opened {
        var state: AppState
        var written: BraggVectors
        var locator: SessionSidecarLocator
        var sidecar: URL
    }

    private func vectors(scanWidth: Int, scanHeight: Int) -> BraggVectors {
        var peaks = [[BraggPeak]](repeating: [], count: scanWidth * scanHeight)
        for y in 0..<scanHeight {
            for x in 0..<scanWidth where (x + y) % 3 != 0 {
                peaks[y * scanWidth + x] = [
                    BraggPeak(x: 3.1 + Float(x) * 0.37, y: 7.7 + Float(y) * 0.53, intensity: 0.2 + Float(x))
                ]
            }
        }
        // Schema-5 era grids carry no detection provenance.
        return BraggVectors(scanWidth: scanWidth, scanHeight: scanHeight, peaks: peaks, detectionProvenance: [:])
    }

    /// Plant a schema-5 sidecar holding a whole-file peak grid, then open the
    /// demo cube at `loaded` through the real `activate`.
    private func open(loaded: LoadSpecification) async throws -> Opened {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let locator = SessionSidecarLocator(defaults: defaults)
        let source = DemoFourDDataSource()
        let full = try await source.discoverPrimaryDataset()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacySessionDiskRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        locator.adopt(sidecar, for: full)

        let written = vectors(scanWidth: full.rx, scanHeight: full.ry)
        try BraggVectorEMDWriter.write(
            vectors: written, qWidth: full.qx, qHeight: full.qy,
            calibration: PixelCalibration(), to: sidecar)
        try SidecarPatcher.write(.variableString("5"), named: SessionSidecarFormat.schemaAttribute, into: sidecar)
        let planted = try BraggVectorEMDWriter.loadSession(from: sidecar)
        XCTAssertEqual(planted.schema, 5)
        XCTAssertEqual(planted.viewRecord, .unrecorded)
        XCTAssertNil(planted.replayRecord, "a schema-5 sidecar has no recipe")
        XCTAssertTrue(planted.inventory.hasBraggVectors)

        let state = try await reopen(locator: locator, loaded: loaded)
        return Opened(state: state, written: written, locator: locator, sidecar: sidecar)
    }

    /// A fresh window opening the demo cube at `loaded` through the real
    /// `activate`, with the sidecar `locator` already holds.
    private func reopen(locator: SessionSidecarLocator, loaded: LoadSpecification = .fullExtent) async throws -> AppState {
        let source = DemoFourDDataSource()
        let full = try await source.discoverPrimaryDataset()
        let state = AppState(sessionSidecar: locator)
        let load = state.beginDatasetLoading("Reopening source…")
        await state.activate(descriptor: full, reader: source, specification: loaded, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
        return state
    }

    /// Waits for the save the test started to publish and for the app's own
    /// follow-up read to finish (the HDF5 library is not thread-safe).
    private func waitForSave(_ state: AppState) async throws {
        for _ in 0..<200 where !state.statusText.hasPrefix("Saved") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(state.statusText.hasPrefix("Saved"), "the save never completed: \(state.statusText)")
    }

    /// The reopened window holds the planted grid bit for bit, says it came
    /// from an older session, and never reads it as current.
    private func assertRestoredWithoutRecipe(_ state: AppState, written: BraggVectors,
                                             file: StaticString = #filePath, line: UInt = #line) throws {
        let restored = try XCTUnwrap(state.resultPresentation.braggVectors,
                                     "Status was: \(state.statusText)", file: file, line: line)
        XCTAssertEqual(restored.totalPeakCount, written.totalPeakCount, file: file, line: line)
        for index in written.peaks.indices {
            XCTAssertEqual(restored.peaks[index].map(\.x.bitPattern), written.peaks[index].map(\.x.bitPattern),
                           file: file, line: line)
            XCTAssertEqual(restored.peaks[index].map(\.y.bitPattern), written.peaks[index].map(\.y.bitPattern),
                           file: file, line: line)
        }
        XCTAssertTrue(state.statusText.contains("older session"), "Status was: \(state.statusText)",
                      file: file, line: line)
        XCTAssertTrue(state.resultPresentation.braggVectorsWithoutRecipe, file: file, line: line)
        XCTAssertFalse(state.hasCurrentBraggVectors, "disks with no recorded settings never read current",
                       file: file, line: line)
        XCTAssertTrue(state.diskDetectionSettingsAreStale, "the run guards that read staleness refuse them too",
                      file: file, line: line)
    }

    /// Mutation it catches: either gate back (the unrecorded view refused at
    /// whole file, or the missing disk-detection step dropping the grid).
    func testASchema5SessionGivesItsStoredDisksBackOnTheWholeFile() async throws {
        let opened = try await open(loaded: .fullExtent)
        let state = opened.state
        let restored = try XCTUnwrap(state.resultPresentation.braggVectors,
                                     "Status was: \(state.statusText)")
        XCTAssertEqual(restored.totalPeakCount, opened.written.totalPeakCount)
        XCTAssertEqual(state.resultPresentation.braggPeakCount, opened.written.totalPeakCount)
        for index in opened.written.peaks.indices {
            XCTAssertEqual(restored.peaks[index].map(\.x.bitPattern), opened.written.peaks[index].map(\.x.bitPattern))
            XCTAssertEqual(restored.peaks[index].map(\.y.bitPattern), opened.written.peaks[index].map(\.y.bitPattern))
        }
        XCTAssertTrue(state.statusText.contains("older session"), "Status was: \(state.statusText)")
        XCTAssertFalse(state.hasCurrentBraggVectors,
                       "disks with no recorded settings never feed strain or orientation as current")
        XCTAssertNil(state.replay.record.steps.first { $0.kind == SessionPeakRestore.diskStepKind },
                     "restoring a product records no recipe step")
        let d = try XCTUnwrap(state.descriptor)
        XCTAssertEqual(state.diskDetection.diskParams,
                       DiskDetectionParams.detectorAdapted(qy: d.qy, qx: d.qx, probeRadius: state.fittedProbeRadius),
                       "with no recipe the controls stay at the detector defaults")
    }

    /// Mutation it catches: the unrecorded view treated as the whole file
    /// whatever was loaded (disks placed on a crop they were not detected on).
    func testASchema5SessionsDisksAreStillRefusedOnAReducedView() async throws {
        let crop = LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6))
        let opened = try await open(loaded: crop)
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertTrue(opened.state.statusText.contains("did not record"),
                      "Status was: \(opened.state.statusText)")
    }

    // MARK: - mac4DSTEM#61: a save after the restore keeps the disks restorable

    /// A calibration save copies the stored disks and stamps the current
    /// schema. Mutation it catches: the writer not carrying the marker for
    /// copied disks (the reopen refuses them: "no disk-detection step").
    func testRestoredSchema5DisksSurviveACalibrationSaveAndTheReopen() async throws {
        let opened = try await open(loaded: .fullExtent)
        XCTAssertNotNil(opened.state.resultPresentation.braggVectors, "Status was: \(opened.state.statusText)")
        opened.state.statusText = ""
        opened.state.saveCalibrationToSessionSidecar()
        try await waitForSave(opened.state)

        let saved = try BraggVectorEMDWriter.loadSession(from: opened.sidecar)
        XCTAssertEqual(saved.schema, SessionSidecarFormat.currentSchema, "the save restamps the file")
        XCTAssertTrue(saved.disksWithoutRecipe, "the copied disks are marked as having no recipe")

        let reopened = try await reopen(locator: opened.locator)
        try assertRestoredWithoutRecipe(reopened, written: opened.written)
    }

    /// A result save writes the restored disks afresh beside a recipe that
    /// has a step but no disk step (the shape the reopen refuses as a recipe
    /// that moved on). Mutation it catches: the save not passing the flag.
    func testRestoredSchema5DisksSurviveAResultSaveAndTheReopen() async throws {
        let opened = try await open(loaded: .fullExtent)
        let state = opened.state
        XCTAssertNotNil(state.resultPresentation.braggVectors, "Status was: \(state.statusText)")
        await state.runVirtualDetector()
        XCTAssertNotNil(state.resultPresentation.braggVectors, "a virtual image leaves the disks alone")
        XCTAssertFalse(state.replay.record.isEmpty)
        XCTAssertNil(state.replay.record.steps.first { $0.kind == SessionPeakRestore.diskStepKind })
        state.statusText = ""
        state.saveCurrentResultToSessionSidecar()
        try await waitForSave(state)

        let saved = try BraggVectorEMDWriter.loadSession(from: opened.sidecar)
        XCTAssertNotNil(saved.replayRecord, "the recipe without a disk step travels with the save")
        XCTAssertTrue(saved.disksWithoutRecipe, "the written disks are marked as having no recipe")

        let reopened = try await reopen(locator: opened.locator)
        try assertRestoredWithoutRecipe(reopened, written: opened.written)
        // And again: the reopen restores them the same way every time.
        reopened.statusText = ""
        reopened.saveCalibrationToSessionSidecar()
        try await waitForSave(reopened)
        let again = try await reopen(locator: opened.locator)
        try assertRestoredWithoutRecipe(again, written: opened.written)
    }

    /// The marker follows the disks, not the file: copied disks keep it,
    /// fresh disks written without the flag drop it, and a current file
    /// never gains it. Mutation it catches: a marker that outlives a new
    /// detection (new disks restored on shape checks alone).
    func testTheMarkerFollowsTheDisksAndClearsOnFreshOnes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisksWithoutRecipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.mac4dstem.h5")
        let grid = vectors(scanWidth: 4, scanHeight: 3)
        let map = ScalarResultMap(width: 4, height: 3, pixels: [Float](repeating: 1, count: 12),
                                  kind: "virtual_bf", displayName: "BF", valueUnits: "counts")

        try BraggVectorEMDWriter.write(vectors: grid, qWidth: 8, qHeight: 8, calibration: PixelCalibration(), to: url)
        try SidecarPatcher.write(.variableString("5"), named: SessionSidecarFormat.schemaAttribute, into: url)
        XCTAssertFalse(try BraggVectorEMDWriter.loadSession(from: url).disksWithoutRecipe, "a schema-5 file has no marker")

        try BraggVectorEMDWriter.mergeCalibration(PixelCalibration(), qWidth: 8, qHeight: 8, to: url)
        XCTAssertTrue(try BraggVectorEMDWriter.loadSession(from: url).disksWithoutRecipe, "copied from schema 5")
        try BraggVectorEMDWriter.mergeCalibration(PixelCalibration(), qWidth: 8, qHeight: 8, to: url)
        XCTAssertTrue(try BraggVectorEMDWriter.loadSession(from: url).disksWithoutRecipe, "carried from a marked file")

        try BraggVectorEMDWriter.mergeResultMap(map, vectors: grid, qWidth: 8, qHeight: 8,
                                                calibration: PixelCalibration(), to: url)
        XCTAssertFalse(try BraggVectorEMDWriter.loadSession(from: url).disksWithoutRecipe, "fresh disks, no flag")
        try BraggVectorEMDWriter.mergeCalibration(PixelCalibration(), qWidth: 8, qHeight: 8, to: url)
        XCTAssertFalse(try BraggVectorEMDWriter.loadSession(from: url).disksWithoutRecipe,
                       "a current file without a recipe never gains it")

        let presentation = ResultPresentation()
        presentation.setBraggVectors(grid, withoutRecipe: true)
        XCTAssertTrue(presentation.braggVectorsWithoutRecipe)
        presentation.setBraggVectors(grid)
        XCTAssertFalse(presentation.braggVectorsWithoutRecipe, "a new detection clears it")
    }
}
