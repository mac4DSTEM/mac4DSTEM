//
//  AppState+Training.swift
//  Role: the on-device training flow's orchestration (Phase C4b, ADR 048, docs/archive/v4/
//        c3-training-preregistration-2026-09-30.md §3): whether "Train Model…" is allowed, the cancellable
//        run, the review of its result, adopting the fine-tuned model, and choosing the active model.
//        Placement only for the compute: the run itself is `DSTEMTraining`'s `DetectorFineTuning`, the
//        rules are `TrainingPolicy`, the state is `DetectorTrainingSession`.
//
//  The run: labelled positions -> `HeldOutSplit` (by position) -> model inputs for the training positions
//  -> `DetectorTrainer` from the BUNDLED weights (admission refuses below 2 GB free) -> a candidate
//  package -> the active and the candidate model each detect at the held-out positions under the
//  CURRENT settings and are scored at 2 px. Nothing is adopted without the user's word, and the sheet
//  offers the candidate only under ADR 048 D7.
//

import CryptoKit
import DSTEMCore
import DSTEMSession
import DSTEMTraining
import Foundation

/// Whether the memory-pressure source cancelled a run, readable from the main-actor handler.
@MainActor
private final class TrainingRunFlags {
    var lowMemory = false
}

extension AppState {

    // MARK: - What can be trained

    /// Every labelled position with at least one centre, its centres as (row, col) in the detector's
    /// native frame (the frame the labels were clicked in).
    var trainingLabels: [ScanPosition: [ScorePoint]] {
        var out: [ScanPosition: [ScorePoint]] = [:]
        for position in diskCentreLabels.positions where !position.centres.isEmpty {
            out[ScanPosition(ry: position.ry, rx: position.rx)] = position.centres.map {
                ScorePoint(row: Double($0.row), col: Double($0.col))
            }
        }
        return out
    }

    /// The split row's counts.
    var trainingSplit: TrainingPolicy.SplitCounts { TrainingPolicy.counts(of: Array(trainingLabels.keys)) }

    /// Why "Train Model…" is unavailable now, nil when it is available.
    var trainModelRefusal: String? {
        guard hasDataset, datasetSession.fourD != nil else { return "Open a dataset first." }
        if isBusy { return "Another operation is running." }
        if learnedDetection.probeReference == nil { return "Build a probe kernel first: the model's input includes the probe image." }
        if LearnedDiskDetector.bundledAssetURL() == nil { return "The bundled neural-net model is not in this build." }
        return TrainingPolicy.trainRefusal(trainingSplit)
    }

    // MARK: - The run

    /// Fine-tunes from the bundled weights and puts the comparison in front of the user. Cancellable;
    /// leaves the active model untouched.
    func trainDetectorModel() async {
        guard trainModelRefusal == nil, let fourD = datasetSession.fourD, let d = descriptor,
              let ref = learnedDetection.probeReference, let bundled = LearnedDiskDetector.bundledAssetURL() else { return }
        detectorTraining.discardReview()
        // CR4: the epoch with the cube and descriptor captured above, before the prepare await; a dataset
        // opened meanwhile must not train the old cube on the new dataset's labels.
        let epoch = datasetSession.epoch
        statusText = "Preparing the neural-net detector…"
        let active: LearnedDiskDetector
        switch await learnedDetection.prepareForRun() {   // slow the first time: before the operation begins
        case .failure(let reason): presentComputeFailure(SimpleError(reason)); return
        case .success(let loaded): active = loaded
        }
        guard epoch == datasetSession.epoch else { return }

        let labels = trainingLabels
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac4dstem-finetune-\(UUID().uuidString)", isDirectory: true)
        let request = DetectorFineTuningRequest(
            data: fourD, qy: d.qy, qx: d.qx, labels: labels, probe: ref.pattern,
            probeCentre: (x: ref.centreX, y: ref.centreY), probeRadius: ref.radius, kernelSource: ref.source,
            params: diskDetection.diskParams, threshold: learnedDetection.threshold,
            bundledPackage: bundled, active: active, stagingDirectory: staging)
        let labelsHash = (try? diskCentreLabels.encodedJSON()).map { data in
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let datasetFile = URL(fileURLWithPath: diskCentreLabels.filePath ?? d.filePath).lastPathComponent
        let datasetPath = diskCentreLabels.datasetPath ?? d.datasetPath

        let token = beginCancellableOperation(
            "Fine-tuning", status: "Preparing training samples…", totalUnits: request.recipe.steps)
        defer { finishCancellableOperation(token) }

        // CRITICAL memory pressure stops the run: training beside a resident cube on 8 GB is the case the
        // trainer's admission cannot see coming (the 2026-09-24 panic). `.warning` is deliberately not
        // used: this 8 GB Mac sits at warning routinely, so cancelling on it would refuse every run.
        let flags = TrainingRunFlags()
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.critical], queue: .main)
        pressure.setEventHandler {
            Task { @MainActor in flags.lowMemory = true; token.cancel() }
        }
        pressure.resume()
        defer { pressure.cancel() }

        let report: @Sendable (DetectorFineTuningStage) -> Void = { [weak self] stage in
            Task { @MainActor [weak self] in self?.showTraining(stage, token: token) }
        }
        do {
            // `DetectorFineTuning.run` is `@concurrent`: off the main actor by its own declaration.
            let outcome = try await DetectorFineTuning.run(request, cancellation: token, progress: report)
            guard epoch == datasetSession.epoch else {
                try? FileManager.default.removeItem(at: staging)
                return
            }
            detectorTraining.present(.init(
                outcome: outcome, stagingDirectory: staging, datasetFile: datasetFile, datasetPath: datasetPath,
                labelsSHA256: labelsHash,
                offer: TrainingPolicy.offer(active: outcome.active.score, candidate: outcome.candidate.score)))
            statusText = "Fine-tuning finished; review the comparison in Bragg Disks"
        } catch {
            try? FileManager.default.removeItem(at: staging)
            guard datasetSession.epoch == epoch else { return }
            if token.isCancelled {
                statusText = flags.lowMemory
                    ? "Low memory stopped fine-tuning; the active model is unchanged"
                    : "Fine-tuning cancelled; the active model is unchanged"
            } else {
                presentComputeFailure(error)
            }
        }
    }

    private func showTraining(_ stage: DetectorFineTuningStage, token: AnalysisCancellationToken) {
        guard isCurrentOperation(token), !token.isCancelled else { return }
        switch stage {
        case .preparing(let done, let total):
            updateCancellableOperation(token, progress: 0, status: "Preparing training samples \(done + 1)/\(total)…")
        case .training(let p):
            updateCancellableOperation(
                token, progress: Double(p.step) / Double(max(p.steps, 1)),
                status: String(format: "Fine-tuning · Step %d/%d · %.2f s/step", p.step, p.steps, p.secondsPerStep))
        case .writing:
            updateCancellableOperation(token, progress: 1, status: "Writing and loading the fine-tuned model…")
        case .evaluating(let done, let total):
            updateCancellableOperation(token, progress: 1, status: "Judging on held-out positions \(done + 1)/\(total)…")
        }
    }

    // MARK: - The decision

    /// "Use Fine-Tuned Model": compile it, store it with its record, make it the active model. Only when
    /// the review offers it (D7).
    func adoptFineTunedModel() async {
        let training = detectorTraining
        guard let review = training.review, review.offer == .offer, !training.isSaving else { return }
        training.setSaving(true)
        defer { training.setSaving(false) }
        statusText = "Saving the fine-tuned model…"
        let o = review.outcome
        do {
            let store = try training.openStore()
            let compiled = try await ModelPackageWriter.compile(packageAt: o.candidatePackage)
            let record = TrainedModelRecord(
                sha256: o.candidateSHA256, parentSHA256: o.parentSHA256, labelsSHA256: review.labelsSHA256,
                datasetFile: review.datasetFile, datasetPath: review.datasetPath, heldOut: o.heldOut, trained: o.trained,
                recipe: o.recipe, finalStepLoss: o.finalStepLoss, active: o.active, candidate: o.candidate)
            let entry = try store.save(record: record, packageAt: o.candidatePackage, compiled: compiled)
            training.refresh()
            training.activate(entry, in: learnedDetection)
            training.discardReview()
            statusText = "Fine-tuned model \(entry.sha8) is now the active model"
            await loadActiveDetectorModel()
        } catch {
            presentComputeFailure(error)
        }
    }

    /// "Keep Current Model", Escape, or closing the sheet: the candidate is deleted, nothing changes.
    func discardFineTunedReview() {
        guard !detectorTraining.isSaving else { return }
        detectorTraining.discardReview()
        statusText = "Kept the current model"
    }

    // MARK: - The active model

    /// The Model picker's choice: "" is the bundled model, otherwise a stored model's tree hash.
    func selectDetectorModel(sha256: String) {
        if sha256.isEmpty {
            detectorTraining.activate(nil, in: learnedDetection)
        } else if let entry = detectorTraining.entry(sha256: sha256) {
            detectorTraining.activate(entry, in: learnedDetection)
        } else {
            statusText = "Model \(sha256.prefix(8))… is not in the model store"
            return
        }
        Task { await loadActiveDetectorModel() }
    }

    /// "Remove Fine-Tuned Model…" (after its confirmation): the active stored model goes to the Trash and
    /// the bundled model is active again.
    func removeActiveFineTunedModel() {
        guard let sha = learnedDetection.activeModel?.sha256, let entry = detectorTraining.entry(sha256: sha) else { return }
        do {
            try detectorTraining.remove(entry, in: learnedDetection)
            statusText = "Moved fine-tuned model \(entry.sha8) to the Trash; the bundled model is active"
            Task { await loadActiveDetectorModel() }
        } catch {
            presentComputeFailure(error)
        }
    }

    /// Loads the active model now, so the Model row shows its identity (or why it cannot run) at once.
    private func loadActiveDetectorModel() async {
        guard let url = learnedDetection.resolvedAssetURL else { return }
        _ = try? await learnedDetection.prepare(assetURL: url)
        await detectCurrentPattern()
    }
}
