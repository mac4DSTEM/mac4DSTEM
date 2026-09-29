//
//  DetectorTrainerTests.swift
//  The MPSGraph fine-tuning core (Phase C4a; C3 pre-registration §3 steps 3-4; ADR 048).
//
//  Pure tests (no GPU): the heatmap target against `simulate.heatmap_target` (numbers computed with a numpy
//  copy of that function: sum 56.599432 and 493 non-zero pixels for six centres, including banker's rounding
//  at x.5, an edge centre and an off-frame one), the eight dihedral maps (each a permutation, pairwise
//  distinct, and moving image and target together), admission at exactly 2 GiB.
//  GPU tests (skipped without a Metal device): the fp32 graph against the bundled Core ML heatmap (spike
//  criterion 1: 0.0027 on the GPU, 0.0355 against the Neural Engine), and a 2-step smoke run.
//
//  Mutations stated: rounding half UP in `heatmapTarget` changes the 493 count (red); ceil(4 sigma) -> 4 sigma
//  changes it (red); a flip missing from the target but present in the input turns
//  testDihedralMapsMoveTargetAndInputTogether red; the admission bar at 1 GiB turns the boundary test red;
//  a learning rate of 1e-4 in the smoke run moves the weights past 5e-4 (red); a transposed kernel in the
//  graph makes the Core ML comparison fail by far more than 0.06; removing the per-step `autoreleasepool` in
//  `trainBlocking` turns testTheFootprintDoesNotGrowWithTheStepCount red (about +330 MB over steps 10-40).
//

import XCTest
import Metal
import DSTEMCore
import DSTEMTraining

final class DetectorTrainerTests: XCTestCase {

    // MARK: pure

    func testHeatmapTargetMatchesSimulateHeatmapTarget() {
        let centres = [ScorePoint(row: 100.3, col: 50.7), ScorePoint(row: 103, col: 52), ScorePoint(row: 0.4, col: 255.6),
                       ScorePoint(row: 300, col: 300), ScorePoint(row: 2.5, col: 10.5), ScorePoint(row: 3.5, col: 20.5)]
        let t = DetectorTraining.heatmapTarget(centres: centres, size: 256, sigma: 1.5)
        XCTAssertEqual(t.count, 256 * 256)
        XCTAssertEqual(t.reduce(0.0) { $0 + Double($1) }, 56.59943203287069, accuracy: 1e-3)
        XCTAssertEqual(t.filter { $0 > 0 }.count, 493)
        let pins: [(Int, Int, Float)] = [(100, 51, 0.9607894420623779), (101, 52, 0.6160393357276917), (103, 52, 1.0),
                                         (102, 52, 0.8007373809814453), (0, 255, 0.8908711075782776), (0, 0, 0),
                                         (2, 10, 0.894839346408844), (3, 20, 0.894839346408844), (100, 44, 0)]
        for (y, x, v) in pins { XCTAssertEqual(t[y * 256 + x], v, accuracy: 1e-6, "(\(y),\(x))") }
        XCTAssertEqual(t.max(), 1.0)
    }

    func testDihedralMapsArePermutationsAndPairwiseDistinct() {
        let S = 16
        let tables = DetectorTraining.dihedralTables(size: S)
        XCTAssertEqual(tables.count, 8)
        XCTAssertEqual(tables[0], (0 ..< Int32(S * S)).map { $0 }, "element 0 is the identity")
        for t in tables { XCTAssertEqual(Set(t).count, S * S) }
        XCTAssertEqual(Set(tables).count, 8)
        // element 4 is the horizontal flip
        XCTAssertEqual(tables[4][3 * S + 2], Int32(3 * S + (S - 1 - 2)))
    }

    func testDihedralMapsMoveTargetAndInputTogether() {
        // An integer centre in the interior: the target of the mapped centre equals the mapped target, exactly.
        let S = 256, centre = ScorePoint(row: 100, col: 50)
        let target = DetectorTraining.heatmapTarget(centres: [centre], size: S, sigma: 1.5)
        let tables = DetectorTraining.dihedralTables(size: S)
        for (k, table) in tables.enumerated() {
            let moved = (0 ..< S * S).map { target[Int(table[$0])] }
            guard let peak = moved.firstIndex(of: 1.0) else { return XCTFail("k=\(k): no peak") }
            let mapped = ScorePoint(row: Double(peak / S), col: Double(peak % S))
            XCTAssertEqual(moved, DetectorTraining.heatmapTarget(centres: [mapped], size: S, sigma: 1.5), "k=\(k)")
            XCTAssertEqual(Int(table[peak]), 100 * S + 50, "k=\(k): the output peak reads the input centre")
        }
    }

    func testAdmissionRefusesBelowTwoGiBAndAdmitsAtExactlyTwoGiB() {
        let bar = 2 * 1024 * 1024 * 1024
        XCTAssertEqual(DetectorTraining.requiredAvailableBytes, bar)
        XCTAssertNoThrow(try DetectorTraining.admit(availableBytes: bar))
        XCTAssertThrowsError(try DetectorTraining.admit(availableBytes: bar - 1)) {
            guard case TrainingError.insufficientMemory(let a, let r)? = $0 as? TrainingError else { return XCTFail("\($0)") }
            XCTAssertEqual(a, bar - 1); XCTAssertEqual(r, bar)
        }
        XCTAssertGreaterThan(DetectorTraining.availableMemoryBytes(), 0, "host_statistics64 answered")
    }

    func testTrainRefusesOnLowMemoryBeforeTouchingTheGPU() async throws {
        let trainer = DetectorTrainer(parentPackage: try TrainingTestSupport.bundledPackage)
        let sample = TrainingSample(inputs: [Float16](repeating: 0, count: 3 * 256 * 256), centres: [])
        do {
            _ = try await trainer.train(samples: [sample], availableMemory: { 1_500_000_000 })
            XCTFail("expected a refusal")
        } catch let e as TrainingError {
            guard case .insufficientMemory(let a, _) = e else { return XCTFail("\(e)") }
            XCTAssertEqual(a, 1_500_000_000)
        }
    }

    func testBadInputsAreRefused() async throws {
        let trainer = DetectorTrainer(parentPackage: try TrainingTestSupport.bundledPackage)
        do { _ = try await trainer.train(samples: [], availableMemory: { Int.max }); XCTFail() }
        catch TrainingError.noTrainingSamples {}
        do {
            _ = try await trainer.train(samples: [TrainingSample(inputs: [0], centres: [])], availableMemory: { Int.max })
            XCTFail()
        } catch TrainingError.badSample {}
        var recipe = TrainingRecipe(); recipe.activations = "fp8"
        let bad = DetectorTrainer(parentPackage: try TrainingTestSupport.bundledPackage, recipe: recipe)
        do {
            _ = try await bad.train(samples: [TrainingSample(inputs: [Float16](repeating: 0, count: 3 * 65536), centres: [])], availableMemory: { Int.max })
            XCTFail()
        } catch TrainingError.invalidRecipe {}
    }

    // MARK: GPU

    private func requireMetal() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
    }

    func testTheFP32GraphMatchesTheBundledCoreMLHeatmap() async throws {
        try requireMetal()
        let bundled = try TrainingTestSupport.bundledPackage
        let fixture = try LearnedSwiftFixture.load()
        let det = try await LearnedSwiftFixture.loadDetector()
        let n3 = 3 * 256 * 256, n = fixture.inputsRef.count
        var padded = [Float16](repeating: 0, count: det.batch * n3)
        for k in 0 ..< n { padded.replaceSubrange(k * n3 ..< (k + 1) * n3, with: fixture.inputsRef[k]) }
        let coreML = try await det.heatmaps(inputs: padded)
        let gpu = try DetectorTrainer.forward(weights: try DetectorWeights.load(fromPackage: bundled), inputs: Array(padded[0 ..< n * n3]))
        XCTAssertEqual(gpu.count, n * 65536)
        var maxDelta: Float = 0
        for i in 0 ..< n * 65536 { maxDelta = max(maxDelta, abs(gpu[i] - Float(coreML[i]))) }
        XCTAssertLessThan(maxDelta, 0.06, "the spike measured 0.0355 against the Neural Engine at batch 32")
        XCTAssertGreaterThan(gpu.max() ?? 0, 0.5, "not two empty maps")
    }

    func testTwoStepsTrainAndMoveTheWeightsALittle() async throws {
        try requireMetal()
        let bundled = try TrainingTestSupport.bundledPackage
        let fixture = try LearnedSwiftFixture.load()
        let samples = try TrainingTestSupport.fixtureSamples(fixture)
        XCTAssertEqual(samples.count, 2)
        var recipe = TrainingRecipe(); recipe.steps = 2; recipe.accumulation = 2
        let seen = TrainingRecorder<TrainingProgress>()
        let result = try await DetectorTrainer(parentPackage: bundled, recipe: recipe).train(
            samples: samples, heldOut: [samples[0]], availableMemory: { Int.max }, progress: { seen.add($0) })

        XCTAssertEqual(result.stepLosses.count, 2)
        XCTAssertTrue(result.stepLosses.allSatisfy { $0.isFinite && $0 > 0 })
        XCTAssertEqual(seen.values.map(\.step), [1, 2]); XCTAssertEqual(seen.values.map(\.steps), [2, 2])
        XCTAssertTrue(try XCTUnwrap(result.heldOutLossBefore).isFinite)
        XCTAssertTrue(try XCTUnwrap(result.heldOutLossAfter).isFinite)
        XCTAssertGreaterThan(result.secondsPerStep, 0)

        let parent = try DetectorWeights.load(fromPackage: bundled)
        XCTAssertEqual(result.weights.parameters.map(\.count), DetectorWeights.elementCounts)
        var maxDelta: Float = 0
        for (a, b) in zip(parent.parameters, result.weights.parameters) { for (x, y) in zip(a, b) { maxDelta = max(maxDelta, abs(x - y)) } }
        XCTAssertGreaterThan(maxDelta, 1e-6, "training moved the weights")
        XCTAssertLessThan(maxDelta, 5e-4, "lr 1e-5 for 2 steps moves a weight by about 1e-4 at most")
        XCTAssertTrue(result.weights.parameters.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    /// The 2026-09-29 leak: the whole loop is one `Task.detached` job, so every autoreleased MPSGraph result piled up until
    /// training returned — 10.9 MB of physical footprint per step (5.7 GB at 500 steps; the C5 probe swap-filled the disk).
    /// Steps 10 -> 40 leaked about 330 MB before the per-step autorelease pool; with it the footprint is flat (probe: 0.04 MB/step).
    func testTheFootprintDoesNotGrowWithTheStepCount() async throws {
        try requireMetal()
        let fixture = try LearnedSwiftFixture.load()
        var recipe = TrainingRecipe(); recipe.steps = 40
        let feet = TrainingRecorder<Double>()
        _ = try await DetectorTrainer(parentPackage: try TrainingTestSupport.bundledPackage, recipe: recipe).train(
            samples: try TrainingTestSupport.fixtureSamples(fixture), availableMemory: { Int.max },
            progress: { if $0.step == 10 || $0.step == 40 { feet.add(DetectorTraining.footprintMB()) } })
        let f = feet.values
        XCTAssertEqual(f.count, 2)
        XCTAssertLessThan(f[1] - f[0], 120, "footprint grew \(Int(f[1] - f[0])) MB over 30 steps (the leak: about 330 MB)")
    }

    func testACancelledTokenStopsTheRun() async throws {
        try requireMetal()
        let fixture = try LearnedSwiftFixture.load()
        let token = AnalysisCancellationToken(); token.cancel()
        do {
            _ = try await DetectorTrainer(parentPackage: try TrainingTestSupport.bundledPackage)
                .train(samples: try TrainingTestSupport.fixtureSamples(fixture), availableMemory: { Int.max }, cancellation: token)
            XCTFail("expected cancellation")
        } catch TrainingError.cancelled {}
    }
}
