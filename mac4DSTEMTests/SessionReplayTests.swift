//
//  SessionReplayTests.swift
//  Pins v2 S5: the replay record's semantics and serialization, the
//  minimum-reader gate, the specification surviving EVERY sidecar rewrite,
//  and the recovery record's frame rules.
//
//  File-level fixtures are written by the PRODUCTION writer and read by the
//  PRODUCTION reader — but never compared type-to-same-type only: the Gate B
//  warning about self-consistent round-trips is answered by asserting
//  specific VALUES (schema numbers, step order, attribute survival), not
//  merely that a thing equals itself after a trip.
//

import XCTest
@testable import mac4DSTEM

final class SessionReplayTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReplayTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private var calibration: PixelCalibration {
        PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1",
                         qrFlip: false)
    }

    private var croppedSpecification: LoadSpecification {
        var specification = LoadSpecification.fullExtent
        specification.scanCrop = AxisCrop(yOffset: 2, xOffset: 4, height: 8, width: 16)
        return specification
    }

    // MARK: - Record semantics

    func testStepsKeepFirstRunOrderAndARerunUpdatesInPlace() {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"])
        record.record(kind: "strain", parameters: ["basis_mode": "automatic"])
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "3.5"])
        XCTAssertEqual(record.steps.map(\.kind), ["disk_detection", "strain"],
                       "A re-run must update in place — the pipeline ORDER is first-run order")
        XCTAssertEqual(record.steps[0].parameters["sigma_cc"], "3.5",
                       "The recipe keeps the parameters the user SETTLED on")
    }

    func testReRunningAnUpstreamStepInvalidatesItsDownstreamSteps() {
        // disks(A) -> strain -> disks(B): the strain step was built on A's
        // peaks; keeping it beside B's detection is a recipe that replays
        // neither the saved map nor a coherent pipeline (Gate B-lite F4).
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"])
        record.record(kind: "strain", parameters: ["basis_mode": "consensus"])
        record.record(kind: "acom", parameters: ["material": "library:au_fcc"])
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "4.0"],
                      invalidating: ["strain", "acom"])
        XCTAssertEqual(record.steps.map(\.kind), ["disk_detection"],
                       "Downstream steps built on superseded peaks must not survive")
        XCTAssertEqual(record.steps.first?.parameters["sigma_cc"], "4.0")
        // Re-running the downstream analysis re-records it, after the upstream.
        record.record(kind: "strain", parameters: ["basis_mode": "consensus"])
        XCTAssertEqual(record.steps.map(\.kind), ["disk_detection", "strain"])
    }

    func testJSONRoundTripPreservesOrderAndIsByteStable() throws {
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector", parameters: ["outer": "20.0"],
                      at: Date(timeIntervalSince1970: 100))
        record.record(kind: "dpc", parameters: ["inner": "0.0"],
                      at: Date(timeIntervalSince1970: 200))
        let json = try XCTUnwrap(record.jsonString)
        let decoded = try XCTUnwrap(SessionReplayRecord.parse(json))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.steps.map(\.kind), ["virtual_detector", "dpc"])
        // Byte stability is what makes the attribute diffable across saves.
        XCTAssertEqual(decoded.jsonString, json)
    }

    func testMalformedJSONYieldsNoRecordNotAnEmptyOne() {
        XCTAssertNil(SessionReplayRecord.parse("not json"))
        XCTAssertNil(SessionReplayRecord.parse(""))
    }

    // MARK: - The live seam

    @MainActor
    func testAnEmptyLiveRecordIsSavedAsNilSoItCannotEraseAColleaguesRecipe() {
        let replay = SessionReplay()
        XCTAssertNil(replay.recordForSaving,
                     "An empty record asserts nothing — writing it would replace a recipe with nothing")
        replay.record(kind: "strain", parameters: [:])
        XCTAssertNotNil(replay.recordForSaving)
        replay.reset()
        XCTAssertNil(replay.recordForSaving)
    }

    @MainActor
    func testAdoptingNilLeavesTheLiveRecordAlone() {
        let replay = SessionReplay()
        replay.record(kind: "dpc", parameters: [:])
        replay.adopt(nil)
        XCTAssertEqual(replay.record.steps.map(\.kind), ["dpc"],
                       "Absence of a recorded recipe is absence — it must not clear this session's")
    }

    // MARK: - File round-trip through the production writer/reader

    func testTheRecipeAndTheSpecificationRoundTripThroughTheSidecar() throws {
        let url = workDirectory.appendingPathComponent("session.mac4dstem.h5")
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"],
                      at: Date(timeIntervalSince1970: 42))
        record.record(kind: "strain", parameters: ["basis_mode": "automatic"],
                      at: Date(timeIntervalSince1970: 43))
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: croppedSpecification, replayRecord: record
        )
        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        XCTAssertEqual(snapshot.replayRecord, record)
        XCTAssertEqual(snapshot.replayRecord?.steps.map(\.kind),
                       ["disk_detection", "strain"])
        XCTAssertEqual(snapshot.loadSpecification, croppedSpecification)
    }

    func testASaveWithoutARecipePreservesTheRecipeAlreadyInTheFile() throws {
        // A colleague adjusting calibration in a session that ran no analyses
        // must not erase the recipe the sidecar exists to carry.
        let url = workDirectory.appendingPathComponent("session.mac4dstem.h5")
        var record = SessionReplayRecord()
        record.record(kind: "acom", parameters: ["material": "library:au_fcc"],
                      at: Date(timeIntervalSince1970: 7))
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url, replayRecord: record
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url, replayRecord: nil
        )
        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        XCTAssertEqual(snapshot.replayRecord, record,
                       "A nil-recipe rewrite must PRESERVE the file's recipe, like result nodes")
    }

    func testAResultSaveRestatesTheSpecificationInsteadOfErasingIt() throws {
        // The S5-found defect: the writer rebuilds the whole file on every
        // save, so a result merge that omitted the specification silently
        // dropped the crop attribute — a reopen then restored scan-indexed
        // results against the full extent.
        let url = workDirectory.appendingPathComponent("session.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: croppedSpecification
        )
        let map = ScalarResultMap(
            width: 16, height: 8,
            pixels: (0..<128).map(Float.init),
            kind: "virtual_detector", displayName: "VD", valueUnits: "counts"
        )
        try BraggVectorEMDWriter.mergeResultMap(
            map, vectors: nil, qWidth: 32, qHeight: 32,
            calibration: calibration, to: url,
            loadSpecification: croppedSpecification
        )
        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        XCTAssertEqual(snapshot.loadSpecification, croppedSpecification,
                       "The crop must survive a result save — every rewrite restates the view")
        XCTAssertEqual(snapshot.inventory.results.count, 1)
    }

    // MARK: - The minimum-reader gate

    func testACroppedSidecarRefusesAReaderOlderThanItsMarker() throws {
        // A REAL file through the REAL gate: cropped ⇒ marker 6; a schema-5
        // reader must be refused whole, with both numbers named — a partial
        // restore is the right-numbers-wrong-positions failure the marker
        // exists to prevent.
        let url = workDirectory.appendingPathComponent("cropped.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: croppedSpecification
        )
        do {
            _ = try BraggVectorEMDWriter.loadSession(from: url, supportedSchema: 5)
            XCTFail("A schema-5 reader must be refused a min-reader-6 file")
        } catch let BraggVectorEMDWriter.WriterError.sidecarRequiresNewerReader(minimum, supported) {
            XCTAssertEqual(minimum, 6)
            XCTAssertEqual(supported, 5)
        }
        // The build's own reader is new enough — the same file opens.
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: url).loadSpecification,
                       croppedSpecification)
    }

    func testAFullExtentSidecarWithARecipeIsReadableByAFiveReader() throws {
        // THE claim behind minimumReaderSchema's values: the replay record is
        // additive — a 5-reader ignoring it loses the recipe, not correctness
        // — so a full-extent file WITH a record must not be refused. A fixture
        // without the record would never reach the interesting case
        // (Gate B-lite F16).
        let url = workDirectory.appendingPathComponent("full.mac4dstem.h5")
        var record = SessionReplayRecord()
        record.record(kind: "dpc", parameters: ["origin_reference": "calibrated origins"],
                      at: Date(timeIntervalSince1970: 5))
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url, replayRecord: record
        )
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: url, supportedSchema: 5))
    }

    func testTheDirectResultReadersHonourTheGateToo() throws {
        // loadResultMap(id:) / loadRGBAResultMap(id:) hand back pixel arrays
        // without going through loadSession — they bypassed the gate and
        // partially restored a refused file (Gate B-lite F5).
        let url = workDirectory.appendingPathComponent("cropped-with-result.mac4dstem.h5")
        let map = ScalarResultMap(
            width: 16, height: 8, pixels: (0..<128).map(Float.init),
            kind: "virtual_detector", displayName: "VD", valueUnits: "counts"
        )
        try BraggVectorEMDWriter.mergeResultMap(
            map, vectors: nil, qWidth: 32, qHeight: 32,
            calibration: calibration, to: url,
            loadSpecification: croppedSpecification
        )
        let id = try XCTUnwrap(
            try BraggVectorEMDWriter.loadSession(from: url).inventory.results.first?.id
        )
        XCTAssertThrowsError(
            try BraggVectorEMDWriter.loadResultMap(id: id, from: url, supportedSchema: 5),
            "A direct result read from a refused file is a partial restore"
        )
        XCTAssertThrowsError(
            try BraggVectorEMDWriter.loadRGBAResultMap(id: id, from: url, supportedSchema: 5)
        )
    }

    func testARewriteOfATooNewFileIsRefusedAndTheFileSurvives() throws {
        // The write side of the gate (Gate B-lite F6): a save into a file
        // whose marker demands a newer reader would drop the content this
        // build cannot see and stamp the marker back down — a mangled file
        // claiming to be safely readable. Refused instead; atomic publish
        // leaves the original untouched.
        let url = workDirectory.appendingPathComponent("cropped.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: croppedSpecification
        )
        XCTAssertThrowsError(
            try BraggVectorEMDWriter.mergeCalibration(
                calibration, qWidth: 32, qHeight: 32, to: url, supportedSchema: 5
            )
        ) { error in
            guard case BraggVectorEMDWriter.WriterError
                .sidecarRequiresNewerReader(let minimum, let supported) = error else {
                return XCTFail("Expected the refusal, got \(error)")
            }
            XCTAssertEqual(minimum, 6)
            XCTAssertEqual(supported, 5)
        }
        // The refused rewrite left the original intact, crop and all.
        XCTAssertEqual(try BraggVectorEMDWriter.loadSession(from: url).loadSpecification,
                       croppedSpecification)
    }

    func testANilSpecificationRewriteErasesTheCropAndThatIsTheContract() throws {
        // Deliberate asymmetry with the replay record (which IS preserved on
        // nil): nil specification MEANS full extent — the identity, no
        // attribute — so it cannot double as "unknown, keep the old one".
        // Pinned so the behaviour is a stated contract, not an accident
        // (Gate B-lite F17); the caller-side hazard this leaves open (a save
        // after a FAILED crop restore erases the crop) is recorded in
        // docs/open-items.md for S7's save-refusal policy.
        let url = workDirectory.appendingPathComponent("erase.mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url,
            loadSpecification: croppedSpecification
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 32, qHeight: 32, to: url, loadSpecification: nil
        )
        XCTAssertNil(try BraggVectorEMDWriter.loadSession(from: url).loadSpecification)
    }

    func testMinimumReaderSchemaRaisesOnlyForContentDangerousToIgnore() {
        XCTAssertEqual(BraggVectorEMDWriter.minimumReaderSchema(for: nil), 5)
        XCTAssertEqual(BraggVectorEMDWriter.minimumReaderSchema(for: .fullExtent), 5)
        XCTAssertEqual(BraggVectorEMDWriter.minimumReaderSchema(for: croppedSpecification), 6)
    }

    // MARK: - Recovery frame rules (the promote/recovery finding)

    private func recoveryRecord(
        x: Int, y: Int, frame: LoadSpecification?
    ) -> DatasetRecoveryRecord {
        DatasetRecoveryRecord(
            datasetID: "/tmp/a.h5", bookmark: Data(),
            selectedX: x, selectedY: y,
            analysisMode: "virtualDetector", updated: Date(timeIntervalSince1970: 0),
            loadSpecification: frame
        )
    }

    func testAPositionAppliesOnlyInItsOwnFrame() {
        // (5, 3) fits INSIDE the cropped view's extents on purpose: if the
        // frame check were dropped, the inside-guard alone would happily
        // apply it, so this coordinate is what makes the mutation visible —
        // an outside coordinate would pass the test for the wrong reason.
        let record = recoveryRecord(x: 5, y: 3, frame: .fullExtent)
        // Same frame, inside: applied.
        XCTAssertEqual(record.position(inViewWith: .fullExtent, rx: 200, ry: 50)?.x, 5)
        // Different frame (the promote-then-crop-restore case): DROPPED even
        // though it fits — full-extent (5, 3) is not crop-relative (5, 3),
        // and applying it would be a pixel the user never chose.
        XCTAssertNil(record.position(inViewWith: croppedSpecification, rx: 16, ry: 8))
    }

    func testADetectorOnlyFrameChangeDoesNotDropTheScanPosition() {
        // Scan coordinates live in the SCAN crop's frame; a detector crop or
        // bin moves no scan index. A whole-spec comparison dropped honest
        // positions here (Gate B-lite F13).
        var detectorOnly = LoadSpecification.fullExtent
        detectorOnly.detectorBin = 4
        let record = recoveryRecord(x: 5, y: 3, frame: .fullExtent)
        XCTAssertEqual(record.position(inViewWith: detectorOnly, rx: 200, ry: 50)?.x, 5)
    }

    func testAFramelessOldRecordAppliesOnlyWhenItFits() {
        let record = recoveryRecord(x: 100, y: 40, frame: nil)
        XCTAssertEqual(record.position(inViewWith: .fullExtent, rx: 200, ry: 50)?.x, 100)
        // Outside a smaller view: nil, never (15, 7).
        XCTAssertNil(record.position(inViewWith: croppedSpecification, rx: 16, ry: 8))
        XCTAssertNil(record.position(inViewWith: .fullExtent, rx: 0, ry: 0))
    }

    func testAnOldPersistedRecordWithoutTheFrameStillDecodes() throws {
        // A pre-S5 payload is EXACTLY a current record encoded by the
        // production coder with the new key stripped — built that way, and
        // decoded with the production coder's configuration (a bare
        // JSONDecoder, same as WorkspaceRecoveryStore), not a hand-tuned one:
        // the first version of this test used .secondsSince1970/.base64,
        // a configuration that exists nowhere in production, and would have
        // stayed green through any store change (Gate B-lite F15).
        let current = recoveryRecord(x: 3, y: 4, frame: .fullExtent)
        let encoded = try JSONEncoder().encode(current)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "loadSpecification")
        let oldPayload = try JSONSerialization.data(withJSONObject: json)
        let record = try JSONDecoder().decode(DatasetRecoveryRecord.self, from: oldPayload)
        XCTAssertNil(record.loadSpecification)
        XCTAssertEqual(record.selectedX, 3)
        XCTAssertEqual(record.selectedY, 4)
    }
}
