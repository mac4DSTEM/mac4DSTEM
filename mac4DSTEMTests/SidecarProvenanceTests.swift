//
//  SidecarProvenanceTests.swift
//  S18 (f) and (d): what a session sidecar says about its view, and what the
//  restore does when the calibration it carries does not fit the frame.
//
//  (f) The writer records a load specification only for a REDUCED view, so
//  "no attribute" is the writer's own statement "whole file" from schema 6 on
//  (2026-08-24) — and no statement at all before it (schema 5 stayed 5 across
//  the 2026-08-18 addition). Restore used to read both as `.fullExtent`
//  (`?? .fullExtent` at three sites): a schema-5 sidecar was re-referenced
//  into a binned view as if it had been recorded on the whole file.
//
//  (d) Saved fitted-origin maps are sized against the frame the sidecar
//  describes. A sidecar recorded on a scan crop restored on the whole cube is
//  refused whole by the frame policy with a named reason; maps whose shape is
//  not the frame's scan (a copied or hand-built sidecar) used to fall through
//  `appOriginMaps`'s shape check to the mean origin without a word.
//
//  A legacy sidecar is synthesised with the production writer and the schema
//  stamp then patched to "5" — the attribute set a pre-2026-08-24 writer left
//  (no specification at whole file, no replay record), the same construction
//  `makeV6Sidecar` uses for schema 6.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SidecarViewRecordTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarViewRecord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private let calibration = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)

    private func sidecar(_ name: String, specification: LoadSpecification?, stamp: String?) throws -> URL {
        let url = workDirectory.appendingPathComponent("\(name).mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url, loadSpecification: specification)
        if let stamp {
            try SidecarPatcher.write(.variableString(stamp), named: SessionSidecarFormat.schemaAttribute, into: url)
        }
        return url
    }

    /// The writer's own convention: a current sidecar with no attribute IS
    /// the whole file. Mutation it catches: absence read as unrecorded
    /// whatever the schema (every current whole-file session refused).
    func testACurrentSidecarWithNoSpecificationIsRecordedAsTheWholeFile() throws {
        let snapshot = try BraggVectorEMDWriter.loadSession(
            from: sidecar("current", specification: nil, stamp: nil))
        XCTAssertEqual(snapshot.schema, SessionSidecarFormat.currentSchema)
        XCTAssertNil(snapshot.loadSpecification)
        XCTAssertEqual(snapshot.viewRecord, .recorded(.fullExtent))
    }

    /// Mutation it catches: `viewRecord` keeps reading a missing attribute as
    /// `.fullExtent` whatever the schema (the pre-S18 behaviour).
    func testASchema5SidecarWithNoSpecificationIsUnrecorded() throws {
        let snapshot = try BraggVectorEMDWriter.loadSession(
            from: sidecar("legacy", specification: nil, stamp: "5"))
        XCTAssertEqual(snapshot.schema, 5)
        XCTAssertEqual(snapshot.viewRecord, .unrecorded)
    }

    /// An old sidecar that DID say its view keeps saying it. Mutation it
    /// catches: unrecorded whenever the schema is below 6.
    func testASchema5SidecarThatRecordedACropStaysRecorded() throws {
        let binned = LoadSpecification(detectorBin: 2)
        let snapshot = try BraggVectorEMDWriter.loadSession(
            from: sidecar("legacyBinned", specification: binned, stamp: "5"))
        XCTAssertEqual(snapshot.viewRecord, .recorded(binned))
    }

    func testASidecarWithoutAReadableStampIsUnrecordedNotWholeFile() {
        // No file: an empty snapshot carries no stamp and no specification.
        let snapshot = SessionSidecarSnapshot(
            inventory: .empty, calibration: nil, currentResult: nil, currentRGBAResult: nil)
        XCTAssertNil(snapshot.schema)
        XCTAssertEqual(snapshot.viewRecord, .unrecorded)
    }

    func testUnrecordedIsAdoptedOnlyOntoAWholeFileLoad() {
        XCTAssertEqual(SessionCalibrationFramePolicy.decide(
            record: .unrecorded, loaded: .fullExtent), .identity)
        guard case .refuse(let reason) = SessionCalibrationFramePolicy.decide(
            record: .unrecorded, loaded: LoadSpecification(detectorBin: 2)) else {
            return XCTFail("an unrecorded view must not be re-referenced into a reduced one")
        }
        XCTAssertTrue(reason.contains("did not record"), reason)
        // The recorded cases are the pre-S18 decisions, unchanged.
        XCTAssertEqual(SessionCalibrationFramePolicy.decide(
            record: .recorded(.fullExtent), loaded: LoadSpecification(detectorBin: 2)), .reReference)
    }

    func testDisksDetectedOnAnUnrecordedViewAreNotUsed() {
        let reason = SessionPeakRestore.refusalBeforeReading(
            viewRecord: .unrecorded, loadedSpecification: .fullExtent, replay: nil)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("did not record") == true, reason ?? "")
    }
}

@MainActor
final class SidecarRestoreProvenanceTests: XCTestCase {

    private let savedQSize = 0.01

    private func cube(_ specification: LoadSpecification, maps: PixelOriginMaps? = nil,
                      savedSpecification: LoadSpecification? = nil,
                      stamp: String? = nil) async throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let locator = SessionSidecarLocator(defaults: defaults)
        let source = DemoFourDDataSource(includesCalibration: false)
        let sourceDescriptor = try await source.discoverPrimaryDataset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarRestoreProvenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        locator.adopt(sidecar, for: sourceDescriptor)
        var saved = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: savedQSize, qUnits: "A^-1", qrFlip: false)
        saved.originMaps = maps
        try BraggVectorEMDWriter.mergeCalibration(
            saved, qWidth: sourceDescriptor.qx, qHeight: sourceDescriptor.qy, to: sidecar,
            loadSpecification: savedSpecification)
        if let stamp {
            try SidecarPatcher.write(.variableString(stamp), named: SessionSidecarFormat.schemaAttribute, into: sidecar)
        }

        let state = AppState(sessionSidecar: locator)
        let load = state.beginDatasetLoading("Reopening source…")
        await state.activate(descriptor: sourceDescriptor, reader: source,
                             specification: specification, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
        return state
    }

    private func maps(rows: Int, columns: Int, qx: Double = 31.5, qy: Double = 32.5) -> PixelOriginMaps {
        PixelOriginMaps(shape: [rows, columns],
                        fittedQX: Array(repeating: qx, count: rows * columns),
                        fittedQY: Array(repeating: qy, count: rows * columns))
    }

    private var binned: LoadSpecification { LoadSpecification(detectorBin: 2) }

    // MARK: (f) unrecorded provenance

    /// Mutation it catches: the frame decision reads the missing attribute as
    /// the whole file (the pre-S18 `?? .fullExtent`) — the calibration is
    /// re-referenced into the binned view and adopted.
    func testALegacySidecarIsNotMovedIntoAReducedView() async throws {
        let state = try await cube(binned, stamp: "5")

        XCTAssertNil(state.calibrationSession.calibration.qPixelSize,
                     "a calibration whose view was never recorded is not re-referenced into another")
        XCTAssertNil(state.calibrationSession.provenance.qScale)
        let refusal = state.loadedView.invalidatedCalibration.first { $0.field == .sessionCalibration }
        XCTAssertNotNil(refusal, "the refusal is named on the view, not silent")
        XCTAssertTrue(refusal?.reason.contains("did not record") == true, refusal?.reason ?? "")
    }

    /// The one case where an unrecorded sidecar is used: a whole-file load,
    /// with the log saying what was assumed. Mutation it catches: unrecorded
    /// refused everywhere (a legacy session's calibration lost on its own file).
    func testALegacySidecarStillRestoresOntoTheWholeFileAndSaysWhatWasAssumed() async throws {
        let state = try await cube(.fullExtent, stamp: "5")

        XCTAssertEqual(state.calibrationSession.calibration.qPixelSize, savedQSize)
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .sessionSidecar)
        XCTAssertNil(state.sessionLoadSpecification,
                     "no claim that the session was recorded on the whole file")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("before sessions recorded their view") },
                      state.activityLog.messages.joined(separator: "\n"))
    }

    /// A current sidecar's silence stays "whole file". Mutation it catches:
    /// absence read as unrecorded whatever the schema.
    func testACurrentWholeFileSidecarStillRestoresIntoAReducedView() async throws {
        let state = try await cube(binned)

        XCTAssertEqual(state.calibrationSession.provenance.qScale, .sessionSidecar)
        XCTAssertNil(state.loadedView.invalidatedCalibration.first { $0.field == .sessionCalibration })
        XCTAssertEqual(state.sessionLoadSpecification, .fullExtent)
    }

    /// The stored disks of an unrecorded session are not used, by the
    /// production path (`restoreSessionPeaks`), with the reason. Hand-built
    /// snapshot: the recipe vouches, the view is the only thing missing.
    func testTheStoredDisksOfAnUnrecordedSessionAreRefusedByTheRestorePath() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let descriptor = try XCTUnwrap(state.descriptor)
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"], at: Date(timeIntervalSince1970: 1))
        func snapshot(schema: Int) -> SessionSidecarSnapshot {
            SessionSidecarSnapshot(
                inventory: SessionSidecarInventory(
                    hasSidecar: true, hasBraggVectors: true, hasCalibration: false,
                    results: [], currentResultID: nil),
                calibration: nil, currentResult: nil, currentRGBAResult: nil,
                schema: schema, replayRecord: record)
        }

        let legacy = await state.restoreSessionPeaks(from: snapshot(schema: 5), for: descriptor)
        XCTAssertTrue(legacy?.contains("did not record") == true, legacy ?? "nil")

        let current = await state.restoreSessionPeaks(from: snapshot(schema: 7), for: descriptor)
        XCTAssertFalse(current?.contains("did not record") == true,
                       "a current sidecar's whole-file silence is a statement, not a gap")
    }

    // MARK: (d) fitted origin maps and the frame

    /// A sidecar recorded on a scan crop, restored on the whole cube: refused
    /// whole with the frame policy's reason; the crop-shaped maps are never
    /// applied to the 12 x 12 scan. (Characterises the existing policy —
    /// this held before S18; the mutation is the policy adopting it.)
    func testCropShapedMapsFromACropSessionAreNotAppliedToTheWholeCube() async throws {
        var crop = LoadSpecification()
        crop.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 5, width: 7)
        let state = try await cube(.fullExtent, maps: maps(rows: 5, columns: 7), savedSpecification: crop)

        XCTAssertNil(state.calibrationSession.calibration.origin, "no mis-shaped maps on the scan")
        XCTAssertNotEqual(state.calibrationSession.calibration.originProvenance, .sessionMaps)
        let refusal = state.loadedView.invalidatedCalibration.first { $0.field == .sessionCalibration }
        XCTAssertTrue(refusal?.reason.contains("different view") == true, refusal?.reason ?? "no refusal")
        XCTAssertEqual(state.sessionLoadSpecification, crop)
    }

    /// Maps that are not the frame's scan (the sidecar says whole file, the
    /// maps are 5 x 7): not applied, named, the mean stands in. Mutation it
    /// catches: the shape refusal is dropped (silent downgrade to the mean).
    func testMapsThatAreNotTheFramesScanAreNamedNotSilentlyDropped() async throws {
        let state = try await cube(.fullExtent, maps: maps(rows: 5, columns: 7))

        XCTAssertNil(state.calibrationSession.calibration.origin)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .sessionMean,
                       "the mean origin stands in, labelled as the mean")
        let refusal = state.loadedView.invalidatedCalibration.first { $0.field == .origin }
        XCTAssertNotNil(refusal, "the dropped maps are named on the view")
        XCTAssertTrue(refusal?.reason.contains("7 × 5") == true, refusal?.reason ?? "")
        XCTAssertTrue(refusal?.reason.contains("12 × 12") == true, refusal?.reason ?? "")
    }

    /// The same through the re-reference path (whole-file session, binned view).
    func testMapsThatAreNotTheSourceScanAreNamedThroughTheReReferencePathToo() async throws {
        let state = try await cube(binned, maps: maps(rows: 5, columns: 7))

        XCTAssertNil(state.calibrationSession.calibration.origin)
        XCTAssertNotNil(state.loadedView.invalidatedCalibration.first { $0.field == .origin })
    }

    /// The refusal must not swallow correct maps. Mutation it catches: the
    /// refusal fires whenever maps are present.
    func testMapsThatFitTheScanAreAppliedAndNothingIsRefused() async throws {
        let state = try await cube(.fullExtent, maps: maps(rows: 12, columns: 12))

        XCTAssertNotNil(state.calibrationSession.calibration.origin)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .sessionMaps)
        XCTAssertNil(state.loadedView.invalidatedCalibration.first { $0.field == .origin })
    }
}
