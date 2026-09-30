//
//  DetectorTrainingReviewFixesTests.swift
//  The fixes from the independent review of phase C (C4b): memory admission counts the samples, a stored
//  model's compiled copy is really used, Remove goes to the Trash and selects Bundled, a pending review
//  dies with its dataset, and every change of the active model (a replay's included) is remembered.
//
//  Mutations stated (each goes red):
//  - `admit` ignoring `extraBytes`: testAdmissionCountsTheSamplesTheRunWillHold (the boundary at 2 GiB + extra - 1).
//  - `load` ignoring `compiledURL` (recompiling from the package): testAStoredModelLoadsFromItsCompiledCopy
//    (an empty directory as the compiled copy must throw; a recompile would not).
//  - `remove` not selecting the bundled model: testRemoveTrashesTheModelAndSelectsBundled (activeModel stays).
//  - `onDatasetCleared` not wired in `install`: testADatasetChangeDropsThePendingReviewAndItsStagedCandidate.
//  - `onModelChange` not wired (a replay's switch not remembered): testEveryChangeOfTheActiveModelIsRemembered.
//  - `activeModel(for:)` dropping `compiledURL`: the same test's last assertions.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DSTEMTraining
@testable import mac4DSTEM

final class DetectorTrainingReviewFixesTests: XCTestCase {

    func testAdmissionCountsTheSamplesTheRunWillHold() {
        let gib = 1024 * 1024 * 1024
        let extra = DetectorFineTuning.sampleBytes(positions: 275, windows: 4)
        XCTAssertEqual(extra, 275 * 4 * 3 * 256 * 256 * 2, "one fp16 (3, 256, 256) sample per position and window")
        XCTAssertNoThrow(try DetectorTraining.admit(availableBytes: 2 * gib))
        XCTAssertThrowsError(try DetectorTraining.admit(availableBytes: 2 * gib + extra - 1, extraBytes: extra))
        XCTAssertNoThrow(try DetectorTraining.admit(availableBytes: 2 * gib + extra, extraBytes: extra))
    }

    func testAStoredModelLoadsFromItsCompiledCopy() async throws {
        try XCTSkipUnless(LearnedSwiftFixture.hasNeuralEngine, "no Neural Engine on this machine: the learned detector is not loaded off it")
        let bundled = try TrainingTestSupport.bundledPackage
        let dir = try TrainingTestSupport.tempDirectory(self)
        let copy = dir.appendingPathComponent("copy.mlpackage")
        try ModelPackageWriter.write(weights: try DetectorWeights.load(fromPackage: bundled), toCopyOf: bundled, at: copy)
        let compiled = try await ModelPackageWriter.compile(packageAt: copy)
        let loaded = try await LearnedDiskDetector.load(assetURL: copy, compiledURL: compiled)
        XCTAssertEqual(loaded.assetSHA256, try LearnedDiskDetector.sha256(ofAsset: bundled), "identity stays the package's tree hash")
        // the stored-model path is the app's other way in: it must land on the Neural Engine like the first (Gate B, 2026-09-30)
        XCTAssertEqual(loaded.computeUnits, .cpuAndNeuralEngine)
        let fixture = try LearnedSwiftFixture.load()
        let (inputs, _) = fixture.batchInputs(try fixture.fittedDetector(), batch: loaded.batch)
        let ran = try await LearnedSwiftFixture.neuralEngineEvidence(loaded, inputs: inputs, heat: try await loaded.heatmaps(inputs: inputs))
        XCTAssertGreaterThan(ran.differingFromCPU, 0, "the stored model's heatmaps equal the CPU's bit for bit")
        XCTAssertEqual(ran.differingFromNeuralEngine, 0, "the stored model's heatmaps differ from a direct Neural Engine run")
        let empty = dir.appendingPathComponent("empty.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        do {
            _ = try await LearnedDiskDetector.load(assetURL: copy, compiledURL: empty)
            XCTFail("the compiled copy was ignored: a recompile would have loaded")
        } catch {}
    }

    // MARK: session bookkeeping

    /// A stored model in a fresh store: a copy of the bundled package with a compiled-copy stand-in.
    @MainActor
    private func storedModel(_ session: DetectorTrainingSession) throws -> TrainedModelStore.Entry {
        let bundled = try TrainingTestSupport.bundledPackage
        let dir = try TrainingTestSupport.tempDirectory(self)
        let copy = dir.appendingPathComponent("m.mlpackage")
        try ModelPackageWriter.write(weights: try DetectorWeights.load(fromPackage: bundled), toCopyOf: bundled, at: copy)
        let compiled = dir.appendingPathComponent("m.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let sha = try LearnedDiskDetector.sha256(ofAsset: copy)
        let record = TrainedModelRecord(sha256: sha, parentSHA256: sha, labelsSHA256: nil, datasetFile: "d.h5", datasetPath: "/e",
                                        heldOut: [], trained: [], recipe: TrainingRecipe(), finalStepLoss: nil, active: nil, candidate: nil)
        let entry = try session.openStore().save(record: record, packageAt: copy, compiled: compiled)
        session.refresh()
        return entry
    }

    @MainActor
    func testRemoveTrashesTheModelAndSelectsBundled() throws {
        let root = try TrainingTestSupport.tempDirectory(self)
        let trashed = TrainingRecorder<URL>()
        let session = DetectorTrainingSession(storeRoot: root, trash: { trashed.add($0) })
        let learned = LearnedDetectionSession()
        session.install(in: learned)
        let entry = try storedModel(session)
        session.activate(entry, in: learned)
        XCTAssertEqual(learned.activeModel?.sha256, entry.record.sha256)
        try session.remove(entry, in: learned)
        XCTAssertEqual(trashed.values, [entry.directory], "the model's folder goes to the Trash, nothing else")
        XCTAssertNil(learned.activeModel, "the bundled model is active again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active.txt").path), "and the choice is forgotten")
    }

    @MainActor
    func testEveryChangeOfTheActiveModelIsRemembered() throws {
        let root = try TrainingTestSupport.tempDirectory(self)
        let session = DetectorTrainingSession(storeRoot: root, trash: { _ in })
        let learned = LearnedDetectionSession()
        session.install(in: learned)
        let entry = try storedModel(session)
        let file = root.appendingPathComponent("active.txt")
        // the switch a replay makes goes through selectModel directly, not through the picker
        learned.selectModel(DetectorTrainingSession.activeModel(for: entry))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), entry.record.sha256)
        XCTAssertEqual(learned.activeModel?.compiledURL, entry.compiledURL)
        XCTAssertNotNil(entry.compiledURL, "the store kept a compiled copy for the active model to load")
        learned.selectModel(nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        // and a fresh session restores what was last chosen
        learned.selectModel(DetectorTrainingSession.activeModel(for: entry))
        let restored = LearnedDetectionSession()
        DetectorTrainingSession(storeRoot: root, trash: { _ in }).install(in: restored)
        XCTAssertEqual(restored.activeModel?.sha256, entry.record.sha256)
    }

    @MainActor
    func testADatasetChangeDropsThePendingReviewAndItsStagedCandidate() throws {
        let session = DetectorTrainingSession(storeRoot: try TrainingTestSupport.tempDirectory(self), trash: { _ in })
        let learned = LearnedDetectionSession()
        session.install(in: learned)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(DetectorTrainingSession.stagingPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: staging) }
        let score = TrainedModelRecord.HeldOutScore(modelSHA256: "a", score: DetectionScore(matched: 1, truth: 1, predicted: 1),
                                                    heldOutPositions: 1, radiusPx: 2, threshold: 0.7)
        let outcome = DetectorFineTuningOutcome(
            candidatePackage: staging.appendingPathComponent("model.mlpackage"), candidateSHA256: "b", parentSHA256: "c",
            trained: [], heldOut: [], recipe: TrainingRecipe(), finalStepLoss: nil, secondsPerStep: 0, active: score, candidate: score)
        session.present(.init(outcome: outcome, stagingDirectory: staging, datasetFile: "d.h5", datasetPath: "/e",
                              labelsSHA256: nil, offer: .offer))
        XCTAssertNotNil(session.review)
        learned.clear()   // what dataset activation calls
        XCTAssertNil(session.review)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }
}
