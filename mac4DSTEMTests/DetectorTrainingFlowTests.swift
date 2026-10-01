//
//  DetectorTrainingFlowTests.swift
//  The rules and seams of the on-device training flow (Phase C4b; ADR 048; C3 pre-registration §3):
//  the split row, the minimum-held-out gate, the D7 offer rule, the training-sample builder (its model
//  inputs against the Python reference, its centre mapping), and the active-model bookkeeping in
//  `LearnedDetectionSession` (provenance keys, a replay finding a stored model by its hash).
//
//  Mutations stated (each goes red):
//  - counts(of:) returning (heldOut, train) swapped: testSplitRowCountsFollowTheHash (275 vs 125).
//  - the gate `<` written `<=`: testTheHeldOutGateOpensAtExactlyTheMinimum (12 would be refused).
//  - the gate reading the TRAINING count: testTheHeldOutGateReadsHeldOutNotTrain (30 train, 11 held out).
//  - the offer rule accepting a tie (`>=` on both, no strict improvement): testATieIsNotOffered.
//  - the offer rule ignoring precision: testAFallOnEitherNumberIsNotOfferedAndNamesIt (recall up, precision down).
//  - comparing the percentages rounded to one decimal instead of exact fractions: testAFallTooSmallToShowInTheRoundedPercentIsStillAFall.
//  - centre mapping with row0 and col0 swapped: testCentresMapIntoTheirWindow, testTheBuilderMapsTheFixtureTruthIntoTheModelFrame.
//  - the builder taking the probe channel from the wrong crop / omitting fillNonFinite / another window origin:
//    testBuilderInputsMatchThePythonReference (2e-3, the scan path's own bar).
//  - `learned_model_parent_sha256` written for a bundled model: testProvenanceKeysNameTheModelOrigin.
//  - a replay that does not consult the store: testAReplayFindsAStoredModelByItsHash (refused instead).
//

import XCTest
import DSTEMCore
import DSTEMSession
import DSTEMTraining
@testable import mac4DSTEM

final class DetectorTrainingFlowTests: XCTestCase {

    // MARK: the split row and the gate

    /// 20 x 20 positions: 125 held out by the hash (pinned in HeldOutSplitTests), 275 train.
    func testSplitRowCountsFollowTheHash() {
        let grid = (0 ..< 20).flatMap { ry in (0 ..< 20).map { ScanPosition(ry: ry, rx: $0) } }
        let counts = TrainingPolicy.counts(of: grid)
        XCTAssertEqual(counts, TrainingPolicy.SplitCounts(train: 275, heldOut: 125))
        XCTAssertEqual(counts.labelled, 400)
        XCTAssertEqual(TrainingPolicy.splitRowText(counts), "275 train · 125 held out")
        // a duplicate position is one position
        XCTAssertEqual(TrainingPolicy.counts(of: grid + grid), counts)
        XCTAssertEqual(TrainingPolicy.counts(of: []), TrainingPolicy.SplitCounts(train: 0, heldOut: 0))
    }

    func testTheHeldOutGateOpensAtExactlyTheMinimum() {
        XCTAssertEqual(TrainingPolicy.minimumHeldOutPositions, 12)
        let below = TrainingPolicy.trainRefusal(.init(train: 28, heldOut: 11))
        XCTAssertNotNil(below)
        XCTAssertTrue(below?.contains("12 held-out positions") == true, below ?? "")
        XCTAssertTrue(below?.contains("11 of 39") == true, "the refusal states what there is: \(below ?? "")")
        XCTAssertNil(TrainingPolicy.trainRefusal(.init(train: 28, heldOut: 12)))
        XCTAssertNil(TrainingPolicy.trainRefusal(.init(train: 1, heldOut: 40)))
    }

    func testTheHeldOutGateReadsHeldOutNotTrain() {
        XCTAssertNotNil(TrainingPolicy.trainRefusal(.init(train: 30, heldOut: 11)), "plenty to train on is not enough to judge on")
    }

    func testNothingLabelledAndNothingToTrainOnAreRefusedInTheirOwnWords() {
        let none = TrainingPolicy.trainRefusal(.init(train: 0, heldOut: 0))
        XCTAssertTrue(none?.contains("No positions are labelled") == true, none ?? "")
        let noTrain = TrainingPolicy.trainRefusal(.init(train: 0, heldOut: 20))
        XCTAssertTrue(noTrain?.contains("train on") == true, noTrain ?? "")
    }

    // MARK: the offer rule (D7)

    private func score(_ matched: Int, truth: Int, predicted: Int) -> DetectionScore {
        DetectionScore(matched: matched, truth: truth, predicted: predicted)
    }

    func testBetterOnBothOrBetterOnOneAndEqualOnTheOtherIsOffered() {
        let active = score(80, truth: 100, predicted: 100)
        XCTAssertEqual(TrainingPolicy.offer(active: active, candidate: score(90, truth: 100, predicted: 100)), .offer)
        // recall up, precision equal (more matched of more predicted keeps precision at 0.8)
        XCTAssertEqual(TrainingPolicy.offer(active: active, candidate: score(88, truth: 100, predicted: 110)), .offer)
        // precision up, recall equal
        XCTAssertEqual(TrainingPolicy.offer(active: active, candidate: score(80, truth: 100, predicted: 90)), .offer)
    }

    func testATieIsNotOffered() {
        let active = score(80, truth: 100, predicted: 100)
        guard case .decline(let reason) = TrainingPolicy.offer(active: active, candidate: active) else { return XCTFail("a tie was offered") }
        XCTAssertTrue(reason.contains("unchanged"), reason)
        XCTAssertTrue(reason.contains("tie is not offered"), reason)
        // the same ratios from different counts are still a tie: 3/7 and 6/14
        XCTAssertEqual(TrainingPolicy.offer(active: score(3, truth: 7, predicted: 7), candidate: score(6, truth: 14, predicted: 14)),
                       .decline("Recall and precision are unchanged. A tie is not offered."))
    }

    func testAFallOnEitherNumberIsNotOfferedAndNamesIt() {
        let active = score(80, truth: 100, predicted: 100)
        // recall up, precision down
        guard case .decline(let precisionFell) = TrainingPolicy.offer(active: active, candidate: score(85, truth: 100, predicted: 120)) else {
            return XCTFail("a precision fall was offered")
        }
        XCTAssertTrue(precisionFell.hasPrefix("Precision fell from 80.0 % to 70.8 %"), precisionFell)
        XCTAssertFalse(precisionFell.contains("ecall fell"), "only the number that fell is named: \(precisionFell)")
        // precision up, recall down
        guard case .decline(let recallFell) = TrainingPolicy.offer(active: active, candidate: score(78, truth: 100, predicted: 80)) else {
            return XCTFail("a recall fall was offered")
        }
        XCTAssertTrue(recallFell.hasPrefix("Recall fell from 80.0 % to 78.0 %"), recallFell)
        XCTAssertFalse(recallFell.contains("recision fell"), recallFell)
        // both down
        guard case .decline(let both) = TrainingPolicy.offer(active: active, candidate: score(70, truth: 100, predicted: 100)) else {
            return XCTFail("worse on both was offered")
        }
        XCTAssertTrue(both.contains("Recall fell") && both.contains("precision fell"), both)
    }

    func testAFallTooSmallToShowInTheRoundedPercentIsStillAFall() {
        // 1000/1001 = 99.9001 % against 999/1000 = 99.9 %: both print "99.9 %", the candidate is lower.
        let active = score(1000, truth: 1000, predicted: 1001)
        let candidate = score(999, truth: 999, predicted: 1000)
        XCTAssertEqual(TrainingPolicy.percent(active.precision), TrainingPolicy.percent(candidate.precision))
        guard case .decline = TrainingPolicy.offer(active: active, candidate: candidate) else { return XCTFail("a fall was offered") }
    }

    func testThePercentIsOneDecimalWithAPoint() {
        XCTAssertEqual(TrainingPolicy.percent(0.7712), "77.1 %")
        XCTAssertEqual(TrainingPolicy.percent(1), "100.0 %")
    }

    // MARK: the sample builder

    func testCentresMapIntoTheirWindow() {
        let native = [ScorePoint(row: 300, col: 20), ScorePoint(row: 100, col: 200), ScorePoint(row: 50, col: 600)]
        // window at (row0 44, col0 -36): (300,20) is 256 rows below the top -> outside; (100,200) -> (56, 236); (50,600) outside
        let mapped = TrainingSampleBuilder.centres(native, inWindowAt: 44, -36)
        XCTAssertEqual(mapped, [ScorePoint(row: 56, col: 236)])
        // a window origin of 0 keeps a centre at 255.9 and drops one at 256
        XCTAssertEqual(TrainingSampleBuilder.centres([ScorePoint(row: 255.9, col: 0), ScorePoint(row: 256, col: 0)], inWindowAt: 0, 0).count, 1)
    }

    func testBuilderInputsMatchThePythonReference() throws {
        let fixture = try LearnedSwiftFixture.load()
        let builder = try XCTUnwrap(TrainingSampleBuilder(
            qy: fixture.native, qx: fixture.native, probe: DiffractionPattern(qy: fixture.native, qx: fixture.native, pixels: fixture.probe),
            probeCentre: fixture.probeCentre, probeRadius: fixture.probeRadius, kernelSource: .measured, params: fixture.params()))
        XCTAssertEqual(builder.windows.count, 1, "a 128-px detector is one padded window")
        for (k, index) in fixture.expected.inputs_ref_indices.enumerated() {
            let pattern = DiffractionPattern(qy: fixture.native, qx: fixture.native, pixels: fixture.patterns[index])
            let samples = builder.samples(pattern: pattern, position: ScanPosition(ry: 0, rx: index), centres: [])
            XCTAssertEqual(samples.count, 1)
            var maxDiff: Float = 0
            for i in samples[0].inputs.indices { maxDiff = max(maxDiff, abs(Float(samples[0].inputs[i]) - Float(fixture.inputsRef[k][i]))) }
            XCTAssertLessThan(maxDiff, 2e-3, "pattern \(index): the training input differs from simulate.model_inputs by \(maxDiff)")
        }
    }

    func testTheBuilderMapsTheFixtureTruthIntoTheModelFrame() throws {
        let fixture = try LearnedSwiftFixture.load()
        let builder = try XCTUnwrap(TrainingSampleBuilder(
            qy: fixture.native, qx: fixture.native, probe: DiffractionPattern(qy: fixture.native, qx: fixture.native, pixels: fixture.probe),
            probeCentre: fixture.probeCentre, probeRadius: fixture.probeRadius, kernelSource: .measured, params: fixture.params()))
        let index = fixture.expected.inputs_ref_indices[0]
        let want = try TrainingTestSupport.fixtureCentres(index, fixture: fixture)
        XCTAssertFalse(want.isEmpty)
        // the same truth in the native frame, as a user's labels are
        let r0 = Double(fixture.expected.fit_offset[0]), c0 = Double(fixture.expected.fit_offset[1])
        let native = want.map { ScorePoint(row: $0.row + r0, col: $0.col + c0) }
        let pattern = DiffractionPattern(qy: fixture.native, qx: fixture.native, pixels: fixture.patterns[index])
        let sample = try XCTUnwrap(builder.samples(pattern: pattern, position: ScanPosition(ry: 0, rx: 0), centres: native).first)
        XCTAssertEqual(sample.centres.count, want.count)
        for (a, b) in zip(sample.centres, want) {
            XCTAssertEqual(a.row, b.row, accuracy: 1e-9); XCTAssertEqual(a.col, b.col, accuracy: 1e-9)
        }
    }

    func testTheBuilderRefusesAProbeOfAnotherSize() throws {
        let fixture = try LearnedSwiftFixture.load()
        XCTAssertNil(TrainingSampleBuilder(
            qy: fixture.native, qx: fixture.native, probe: DiffractionPattern(qy: 8, qx: 8, pixels: [Float](repeating: 1, count: 64)),
            probeCentre: fixture.probeCentre, probeRadius: fixture.probeRadius, kernelSource: .measured, params: fixture.params()))
    }

    // MARK: the active model and its provenance

    @MainActor
    func testProvenanceKeysNameTheModelOrigin() {
        let session = LearnedDetectionSession()
        var bundled = session.replayParameters(for: .learned)
        // The bundled model adds no key: the signature stays the one every
        // session before 2026-09-30 recorded, so their disks do not go stale
        // (BraggPeakSeedsControlsOnOpenTests caught the first version).
        XCTAssertNil(bundled["learned_model_origin"])
        XCTAssertNil(bundled["learned_model_parent_sha256"], "a bundled model has no parent")
        XCTAssertEqual(session.replayParameters(for: .classical), ["detector_class": "classical"], "a classical step names no model")

        session.selectModel(.init(packageURL: URL(fileURLWithPath: "/tmp/x.mlpackage"), parentSHA256: "p" + String(repeating: "0", count: 63), sha256: "abcd1234"))
        let tuned = session.replayParameters(for: .learned)
        XCTAssertEqual(tuned["learned_model_origin"], "fine-tuned")
        XCTAssertEqual(tuned["learned_model_parent_sha256"], "p" + String(repeating: "0", count: 63))
        XCTAssertEqual(tuned["learned_model_sha256"], "abcd1234", "a stored model's identity is known before it loads")

        session.selectModel(nil)
        bundled = session.replayParameters(for: .learned)
        XCTAssertNil(bundled["learned_model_origin"])
        XCTAssertNil(bundled["learned_model_parent_sha256"])
        XCTAssertEqual(bundled["learned_model_sha256"], "", "the bundled model's identity is not known until it loads")
    }

    @MainActor
    func testSelectingTheSameModelChangesNothing() {
        let session = LearnedDetectionSession()
        let model = LearnedDetectionSession.ActiveModel(packageURL: URL(fileURLWithPath: "/tmp/x.mlpackage"), sha256: "abcd1234")
        session.selectModel(model)
        XCTAssertEqual(session.activeModel, model)
        XCTAssertEqual(session.assetSHA256, "abcd1234")
        XCTAssertEqual(session.resolvedAssetURL, model.packageURL)
        session.selectModel(nil)
        XCTAssertNil(session.activeModel)
        XCTAssertNil(session.assetSHA256)
    }

    /// A recipe recorded against a stored fine-tuned model: the replay finds the model by its hash and
    /// makes it active; without the store it is refused, naming the hash and saying it is not on this Mac.
    @MainActor
    func testAReplayFindsAStoredModelByItsHash() async throws {
        try XCTSkipUnless(LearnedSwiftFixture.hasNeuralEngine, "no Neural Engine on this machine: the learned detector is not loaded off it")
        let bundled = try TrainingTestSupport.bundledPackage
        let dir = try TrainingTestSupport.tempDirectory(self)
        var weights = try DetectorWeights.load(fromPackage: bundled)
        weights.w[14] = weights.w[14].map { -$0 }
        let tunedURL = dir.appendingPathComponent("tuned.mlpackage")
        try ModelPackageWriter.write(weights: weights, toCopyOf: bundled, at: tunedURL)
        let tunedSHA = try LearnedDiskDetector.sha256(ofAsset: tunedURL)
        let bundledSHA = try LearnedDiskDetector.sha256(ofAsset: bundled)
        XCTAssertNotEqual(tunedSHA, bundledSHA)
        let recorded = ReplayStepPlan.DiskDetectorReplay(detectorClass: .learned, learnedThreshold: 0.6, learnedModelSHA256: tunedSHA)

        // no store: refused, the picker and the model untouched
        let without = LearnedDetectionSession()
        let refusal = await without.replayRefusal(for: recorded)
        XCTAssertTrue(refusal?.contains("not on this Mac") == true, refusal ?? "nil")
        XCTAssertTrue(refusal?.contains(String(tunedSHA.prefix(8))) == true, refusal ?? "nil")
        XCTAssertEqual(without.detectorClass, .classical)
        XCTAssertNil(without.activeModel)

        // a store that has it: the replay proceeds on the stored model
        let session = LearnedDetectionSession()
        session.modelLookup = { sha in
            tunedSHA.hasPrefix(sha) ? .init(packageURL: tunedURL, parentSHA256: bundledSHA, sha256: tunedSHA) : nil
        }
        let found = await session.replayRefusal(for: recorded)
        XCTAssertNil(found, found ?? "")
        XCTAssertEqual(session.detectorClass, .learned)
        XCTAssertEqual(session.threshold, 0.6)
        XCTAssertEqual(session.assetSHA256, tunedSHA)
        XCTAssertEqual(session.modelOrigin, "fine-tuned")

        // and back: a recipe recorded against the bundled model switches the active model back to it
        let back = await session.replayRefusal(for: .init(detectorClass: .learned, learnedThreshold: 0.7, learnedModelSHA256: bundledSHA))
        XCTAssertNil(back, back ?? "")
        XCTAssertNil(session.activeModel)
        XCTAssertEqual(session.assetSHA256, bundledSHA)
    }
}
