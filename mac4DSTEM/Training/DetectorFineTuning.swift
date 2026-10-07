//
//  DetectorFineTuning.swift
//  Role: one fine-tuning run end to end, off the UI (Phase C4b; C3 pre-registration §3 steps 3-4, ADR 048):
//        model inputs for the training positions -> `DetectorTrainer` from the BUNDLED weights -> a
//        candidate package on disk -> `LearnedDiskDetector.load` -> the ACTIVE and the CANDIDATE model
//        each detect at every HELD-OUT position with the same settings and are scored at 2 px.
//
//  Nothing here is stored or adopted: the outcome carries the numbers, and the candidate stays in the
//  staging directory the caller gave until the caller saves it (`TrainedModelStore.save`) or deletes it.
//  A held-out position is never read before training ends and never enters the training set (the split is
//  `HeldOutSplit`, by position). Call `run` from a detached task: the sample building and the detection
//  are CPU-bound and `nonisolated async` runs on its caller's executor.
//

import DSTEMCore
import Foundation

package nonisolated struct DetectorFineTuningRequest: Sendable {
    package var data: FourDArray
    package var qy: Int
    package var qx: Int
    /// Hand-labelled centres (row, col) in the detector's native frame, by scan position; only positions
    /// with at least one centre.
    package var labels: [ScanPosition: [ScorePoint]]
    package var probe: DiffractionPattern
    package var probeCentre: (x: Float, y: Float)
    package var probeRadius: Float
    package var kernelSource: ProbeKernelSource
    /// The user's current detection settings and pick threshold: both models are judged under them.
    package var params: DiskDetectionParams
    package var threshold: Float
    /// The bundled `.mlpackage`: the parent of every run (D4).
    package var bundledPackage: URL
    /// The model the candidate is judged against (already loaded).
    package var active: LearnedDiskDetector
    /// A directory that does not exist yet; the candidate package is written to `model.mlpackage` in it.
    package var stagingDirectory: URL
    package var recipe = TrainingRecipe()

    package init(data: FourDArray, qy: Int, qx: Int, labels: [ScanPosition: [ScorePoint]], probe: DiffractionPattern,
                 probeCentre: (x: Float, y: Float), probeRadius: Float, kernelSource: ProbeKernelSource,
                 params: DiskDetectionParams, threshold: Float, bundledPackage: URL, active: LearnedDiskDetector,
                 stagingDirectory: URL, recipe: TrainingRecipe = TrainingRecipe()) {
        self.data = data; self.qy = qy; self.qx = qx; self.labels = labels; self.probe = probe
        self.probeCentre = probeCentre; self.probeRadius = probeRadius; self.kernelSource = kernelSource
        self.params = params; self.threshold = threshold; self.bundledPackage = bundledPackage
        self.active = active; self.stagingDirectory = stagingDirectory; self.recipe = recipe
    }
}

package nonisolated enum DetectorFineTuningStage: Sendable {
    case preparing(done: Int, of: Int)
    case training(TrainingProgress)
    case writing
    case evaluating(done: Int, of: Int)
}

package nonisolated struct DetectorFineTuningOutcome: Sendable {
    package var candidatePackage: URL
    package var candidateSHA256: String
    package var parentSHA256: String
    package var trained: [ScanPosition]
    package var heldOut: [ScanPosition]
    package var recipe: TrainingRecipe
    package var finalStepLoss: Double?
    package var secondsPerStep: Double
    package var active: TrainedModelRecord.HeldOutScore
    package var candidate: TrainedModelRecord.HeldOutScore

    package init(candidatePackage: URL, candidateSHA256: String, parentSHA256: String, trained: [ScanPosition],
                 heldOut: [ScanPosition], recipe: TrainingRecipe, finalStepLoss: Double?, secondsPerStep: Double,
                 active: TrainedModelRecord.HeldOutScore, candidate: TrainedModelRecord.HeldOutScore) {
        self.candidatePackage = candidatePackage; self.candidateSHA256 = candidateSHA256; self.parentSHA256 = parentSHA256
        self.trained = trained; self.heldOut = heldOut; self.recipe = recipe; self.finalStepLoss = finalStepLoss
        self.secondsPerStep = secondsPerStep; self.active = active; self.candidate = candidate
    }
}

package nonisolated enum DetectorFineTuningError: Error, CustomStringConvertible, LocalizedError {
    case noHeldOutPositions
    case invalidSettings
    case detectionFailed(ScanPosition)
    package var description: String {
        switch self {
        case .noHeldOutPositions: return "no labelled position is held out, so nothing can judge the fine-tuned model"
        case .invalidSettings: return "the probe or the detection settings cannot build model inputs at this detector size"
        case .detectionFailed(let p): return "neural-net detection failed at scan position (\(p.ry), \(p.rx))"
        }
    }
    package var errorDescription: String? { description }
}

package nonisolated enum DetectorFineTuning {
    /// The registered match radius (`DetectionScorer.defaultRadius`, 2 px).
    package static let matchRadius = DetectionScorer.defaultRadius

    @concurrent
    package static func run(
        _ request: DetectorFineTuningRequest, cancellation: AnalysisCancellationToken,
        progress: @escaping @Sendable (DetectorFineTuningStage) -> Void
    ) async throws -> DetectorFineTuningOutcome {
        let split = HeldOutSplit.split(Array(request.labels.keys))
        guard !split.heldOut.isEmpty else { throw DetectorFineTuningError.noHeldOutPositions }
        guard !split.train.isEmpty else { throw TrainingError.noTrainingSamples }
        guard let builder = TrainingSampleBuilder(
            qy: request.qy, qx: request.qx, probe: request.probe, probeCentre: request.probeCentre,
            probeRadius: request.probeRadius, kernelSource: request.kernelSource, params: request.params)
        else { throw DetectorFineTuningError.invalidSettings }
        // Admission before any sample is built: the trainer's 2 GB plus the samples this run will hold.
        try DetectorTraining.admit(
            availableBytes: DetectorTraining.availableMemoryBytes(),
            extraBytes: sampleBytes(positions: split.train.count, windows: builder.windows.count))

        var samples: [TrainingSample] = []
        for (i, position) in split.train.enumerated() {
            if cancellation.isCancelled { throw TrainingError.cancelled }
            progress(.preparing(done: i, of: split.train.count))
            let pattern = try await request.data.pattern(ry: position.ry, rx: position.rx)
            samples += builder.samples(pattern: pattern, position: position, centres: request.labels[position] ?? [])
        }

        let trainer = DetectorTrainer(parentPackage: request.bundledPackage, recipe: request.recipe)
        let result = try await trainer.train(samples: samples, cancellation: cancellation, progress: { progress(.training($0)) })
        samples = []   // release before the candidate is loaded and the models run

        if cancellation.isCancelled { throw TrainingError.cancelled }
        progress(.writing)
        let candidatePackage = request.stagingDirectory.appendingPathComponent(TrainedModelStore.packageName)
        do {
            try ModelPackageWriter.write(weights: result.weights, toCopyOf: request.bundledPackage, at: candidatePackage)
            let candidate = try await LearnedDiskDetector.load(assetURL: candidatePackage)
            let (activeScore, candidateScore) = try await evaluate(
                active: request.active, candidate: candidate, heldOut: split.heldOut, request: request,
                cancellation: cancellation, progress: progress)
            return DetectorFineTuningOutcome(
                candidatePackage: candidatePackage, candidateSHA256: candidate.assetSHA256,
                parentSHA256: try LearnedDiskDetector.sha256(ofAsset: request.bundledPackage),
                trained: split.train, heldOut: split.heldOut, recipe: request.recipe,
                finalStepLoss: result.stepLosses.last, secondsPerStep: result.secondsPerStep,
                active: .init(modelSHA256: request.active.assetSHA256, score: activeScore, heldOutPositions: split.heldOut.count,
                              radiusPx: matchRadius, threshold: request.threshold),
                candidate: .init(modelSHA256: candidate.assetSHA256, score: candidateScore, heldOutPositions: split.heldOut.count,
                                 radiusPx: matchRadius, threshold: request.threshold))
        } catch {
            try? FileManager.default.removeItem(at: request.stagingDirectory)
            throw error
        }
    }

    /// The model inputs of `positions` training positions with `windows` windows each, held in memory
    /// for the whole run (one sample per position and window).
    package static func sampleBytes(positions: Int, windows: Int) -> Int {
        positions * windows * DetectorTraining.sampleInputBytes
    }

    /// Both models detect at every held-out position under the same settings; the pooled scores.
    static func evaluate(
        active: LearnedDiskDetector, candidate: LearnedDiskDetector, heldOut: [ScanPosition],
        request: DetectorFineTuningRequest, cancellation: AnalysisCancellationToken,
        progress: @Sendable (DetectorFineTuningStage) -> Void
    ) async throws -> (active: DetectionScore, candidate: DetectionScore) {
        var activeScores: [DetectionScore] = [], candidateScores: [DetectionScore] = []
        for (i, position) in heldOut.enumerated() {
            if cancellation.isCancelled { throw TrainingError.cancelled }
            progress(.evaluating(done: i, of: heldOut.count))
            let pattern = try await request.data.pattern(ry: position.ry, rx: position.rx)
            let truth = request.labels[position] ?? []
            for (model, into) in [(active, 0), (candidate, 1)] {
                guard let peaks = await model.detect(
                    pattern: pattern, probe: request.probe, probeCentre: request.probeCentre, probeRadius: request.probeRadius,
                    kernelSource: request.kernelSource, params: request.params, threshold: request.threshold)
                else { throw DetectorFineTuningError.detectionFailed(position) }
                let score = DetectionScorer.score(truth: truth, predicted: peaks.map { ScorePoint(row: Double($0.y), col: Double($0.x)) },
                                                  radius: matchRadius)
                if into == 0 { activeScores.append(score) } else { candidateScores.append(score) }
            }
        }
        return (DetectionScorer.pooled(activeScores), DetectionScorer.pooled(candidateScores))
    }
}
