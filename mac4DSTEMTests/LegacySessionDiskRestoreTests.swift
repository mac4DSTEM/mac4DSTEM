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

        let state = AppState(sessionSidecar: locator)
        let load = state.beginDatasetLoading("Reopening source…")
        await state.activate(descriptor: full, reader: source, specification: loaded, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
        return Opened(state: state, written: written)
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
}
