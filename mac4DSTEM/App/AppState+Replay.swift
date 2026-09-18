import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// Seam 7 placement: promote-and-replay orchestration and step execution.
extension AppState {
    /// The promote control's action since v2 S6 — the release claim's
    /// "one action" (docs/v2-release.md §1, commitment 2): reopen at full
    /// extent, then replay the recorded pipeline sequentially, unattended,
    /// with the machine held awake. With an empty recipe this is exactly the
    /// S3 promote, re-establishing pass included.
    /// The record and its frame are captured BEFORE the reopen: the replay
    /// executes the recipe the user promoted, not whatever `activate`'s
    /// sidecar restore re-adopts mid-flight.
    func promoteAndReplayRecipe() async {
        let record = replay.record
        let frame = replay.parameterFrame ?? .unknown
        guard !record.isEmpty else {
            await promoteToFullExtent()
            return
        }
        // Replay is the promote's tail only — on an already-full-extent view
        // there is nothing this button's gesture means.
        guard !loadedView.isFullExtent, !datasetSession.isLoading else { return }
        // The plan is PURE, so every certain refusal is known before the
        // expensive reopen is paid for. A recipe whose FIRST step already
        // refuses will replay nothing — run the ordinary re-establishing
        // pass in that case so the morning is not "hours of reopen, zero
        // analyses, and a halt" (Gate A findings E1/B2, 2026-08-25).
        let planned = ReplayPlanner.plan(record, frame: frame)
        let firstStepRefused: Bool
        if case .failure = planned[0].result { firstStepRefused = true }
        else { firstStepRefused = false }
        // `begin` BEFORE the reopen: the keep-awake assertion must cover the
        // longest unattended phase (findings B1/C1), and its refusal is the
        // single-flight gate — a second overlapping call must not write into
        // this run's step table or release its assertion (finding A5).
        // The frame note travels into the run so the morning summary states a
        // re-referenced replay the same way the pre-click caption did — set
        // only when a planned step actually carries detector numbers. // v2 S10
        let frameNote: String?
        if let note = frame.reReferenceDescription,
           planned.contains(where: {
               if case .success(let plan) = $0.result {
                   plan.usesDetectorFrameParameters
               } else { false }
           }) {
            frameNote = "Recipe \(note)."
        } else {
            frameNote = nil
        }
        guard replayRun.begin(titles: planned.map(\.title), frameNote: frameNote) else { return }
        await promoteToFullExtent(runReestablishingAnalysis: firstStepRefused)
        // Replay only on the back of a promote that actually happened: a
        // refused or cancelled promote leaves the rehearsal (or nothing)
        // loaded, and running the recipe against it would be the promote
        // run's summary lying about which view the numbers describe.
        guard hasDataset, loadedView.isFullExtent, !datasetSession.isLoading else {
            replayRun.finish(haltReason: "the reopen did not complete, so nothing was replayed — the recipe is unchanged")
            statusText = "Promote run stopped — the reopen did not complete; nothing was replayed"
            return
        }
        await executeReplay(planned: planned)
    }

    /// Sequential replay — v2 S6. One step at a time, in recipe order; the
    /// first refusal, failure or cancellation HALTS the run (never silently
    /// past a failure, per the S6 brief) and everything after it stays "not
    /// reached" in the summary. `replayRun.begin` already ran — the caller
    /// holds the keep-awake assertion from before the reopen.
    private func executeReplay(planned: [PlannedReplayStep]) async {
        let epoch = datasetSession.epoch
        var haltReason: String?
        for (index, step) in planned.enumerated() {
            guard datasetSession.epoch == epoch, !datasetSession.isLoading else {
                haltReason = "the dataset changed while the promote run was executing"
                break
            }
            replayRun.willRun(step: index)
            switch step.result {
            case .failure(let refusal):
                replayRun.conclude(step: index, outcome: .refused(reason: refusal.reason))
                haltReason = "\(step.title) could not be replayed: \(refusal.reason)"
            case .success(let plan):
                let started = Date()
                switch await executeReplayStep(plan) {
                case .refused(let reason):
                    replayRun.conclude(step: index, outcome: .refused(reason: reason))
                    haltReason = "\(step.title) could not be replayed: \(reason)"
                case .ran(let outcome):
                    if datasetSession.epoch != epoch {
                        replayRun.conclude(step: index, outcome: .failed(
                            reason: "the dataset changed while this step was executing"))
                        haltReason = "the dataset changed while the promote run was executing"
                        break
                    }
                    switch outcome {
                    case .published:
                        // `statusText` here is the entry point's own success
                        // line — counts and fractions — written by the same
                        // function that just returned `.published`.
                        replayRun.conclude(step: index, outcome: .succeeded(
                            detail: statusText, seconds: Date().timeIntervalSince(started)))
                    case .cancelled:
                        replayRun.conclude(step: index, outcome: .cancelled)
                        haltReason = "\(step.title) was cancelled, and the run stopped there"
                    case .failed(let reason):
                        replayRun.conclude(step: index, outcome: .failed(reason: reason))
                        haltReason = "\(step.title) failed — \(reason)"
                    }
                }
            }
            if haltReason != nil { break }
        }
        replayRun.finish(haltReason: haltReason)
        statusText = haltReason.map { "Promote run halted — \($0)" }
            ?? "Promote run finished — \(planned.count) \(planned.count == 1 ? "analysis" : "analyses") replayed"
    }

    private enum ReplayStepExecution {
        /// The entry point ran and returned its own typed verdict.
        case ran(AnalysisRunOutcome)
        /// A recorded precondition this session cannot honour — the step never
        /// ran. Substituting the session's different value silently would be a
        /// parameter change no summary states.
        case refused(String)
    }

    /// Apply one parsed step's recorded parameters to live state and run the
    /// SAME entry point the user's click runs — replay must not grow a second
    /// execution path that can drift from the interactive one.
    /// v2.5 step 5a: a replayed step refuses for exactly the reason the live
    /// checklist would block the same task — one requirements list. Called
    /// after a step has written its recorded parameters, so the answer is
    /// about the state the run would actually see.
    func replayRefusal(for mode: AnalysisMode) -> String? {
        if case .unavailable(let reason) = ProductWorkflow.readiness(
            for: mode, readiness: productWorkflowReadiness) {
            return "this step cannot run on the promoted view — \(reason)"
        }
        return nil
    }

    private func executeReplayStep(_ plan: ReplayStepPlan) async -> ReplayStepExecution {
        switch plan {
        case .virtualDetector(let shape, let recordedAperture):
            resultPresentation.virtualShape = shape
            aperture = recordedAperture
            if let reason = replayRefusal(for: .virtualDetector) { return .refused(reason) }
            return .ran(await runVirtualDetector(replaying: true))

        case .dpc(let wantsFittedOrigin):
            guard calibrationSession.calibration.hasFittedOrigin == wantsFittedOrigin else {
                // The wanted-but-absent direction is the EXPECTED one after a
                // promote: per-position origin maps are fitted at the
                // rehearsal's extent and do not carry across the reopen
                // (the same inverse-mapping family as S10's detector-frame
                // work — Gate A findings A2/C2, 2026-08-25). The refusal
                // must say what to do, not just what is missing.
                if wantsFittedOrigin {
                    return .refused("the recipe ran DPC against calibrated origins, and the rehearsal's per-position origin fit does not carry across a promote — calibrate the origin on the promoted view, then run DPC by hand")
                }
                return .refused("the recipe ran DPC against the global center, but this session holds a fitted origin — running it anyway would silently change the measurement's reference")
            }
            if let reason = replayRefusal(for: .dpc) { return .refused(reason) }
            return .ran(await runDPC(replaying: true))

        case .diskDetection(let params, let detector):
            diskDetection.diskParams = params
            if let reason = await learnedDetection.replayRefusal(for: detector) { return .refused(reason) }
            if let reason = replayRefusal(for: .disks) { return .refused(reason) }
            return .ran(await runDiskDetection(replaying: true))

        case .strain(let strainPlan):
            strain.referenceMode = .wholeScan
            if let basis = strainPlan.manualBasis {
                strain.basisMode = .manual
                strain.g1X = basis.g1x
                strain.g1Y = basis.g1y
                strain.g2X = basis.g2x
                strain.g2Y = basis.g2y
            } else {
                strain.basisMode = .automatic
            }
            if let reason = replayRefusal(for: .strain) { return .refused(reason) }
            return .ran(await runStrainMapping(replaying: true))

        case .acom(let acomPlan):
            // Resolution is `ACOMReplayPlan.resolveMaterial` (pure, tested):
            // by id, never a fallback crystal; the custom-cubic arm exists
            // because `activate` reset the SELECTION but the fields survive
            // (Gate A finding C4), and it now also requires the rehearsed
            // lattice constant (Gate D 2026-09-02).
            switch acomPlan.resolveMaterial(in: .init(
                importedIDs: Set(acomSession.importedCrystalModels.map(\.id)),
                // The content check: an imported id is a file stem, so the
                // recipe's fingerprint must match THIS session's import.
                importedFingerprints: Dictionary(
                    acomSession.importedCrystalModels.map { ($0.id, $0.contentFingerprint) },
                    uniquingKeysWith: { _, last in last }),
                customStructure: acomSession.customStructure, customLatticeA: acomSession.customLatticeA,
                customZ: acomSession.customZ)) {
            case .library(let id): acomSession.modelSelection = .library(id)
            case .imported(let id): acomSession.modelSelection = .imported(id)
            case .customCubic: acomSession.modelSelection = .customCubic
            case .unavailable(let reason): return .refused(reason)
            }
            guard resolvedACOMModel?.id == acomPlan.materialID else {
                return .refused("the recipe's phase model '\(acomPlan.materialID)' is not available in this session — select or import the phase model it names, then run ACOM by hand")
            }
            let sessionScale = acomScaleSemantics.invAngstromPerPixel
            let recordedScale = acomPlan.scaleInvAngstromPerPixel
            guard abs(sessionScale - recordedScale) <= max(1e-12, abs(recordedScale) * 1e-6) else {
                return .refused(String(
                    format: "the recipe matched at %.6g Å⁻¹/px but this session's scale is %.6g Å⁻¹/px — matching at a different scale gets orientations wrong with nothing to catch it, so recalibrate Q or run ACOM by hand",
                    recordedScale, sessionScale))
            }
            acomSession.scope = acomPlan.scope
            acomSession.quality = acomPlan.quality
            if let reason = replayRefusal(for: .acom) { return .refused(reason) }
            return .ran(await runACOM(replaying: true))
        }
    }
}

