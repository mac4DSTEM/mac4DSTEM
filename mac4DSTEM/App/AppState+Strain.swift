//
//  AppState+Strain.swift
//  The strain-mapping run: the stale-settings and missing-peaks refusals,
//  the cancellable whole-scan fit, and its publication. The product's
//  settings and result live on `Session/StrainProduct.swift` (`strain`); its
//  display derivation is `applyStrainDisplay` in
//  AppState+ResultPresentation.swift. Moved here 2026-09-29 so every analysis
//  run has its own extension file, as ACOM, DPC and phase mapping do — a
//  move, not a rewrite; nothing needed widening.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    // MARK: - Strain mapping

    /// Compute a strain map from the detected Bragg vectors (needs a prior
    /// disk-detection pass). Automatic mode uses repeated-vector consensus;
    /// local fits and the reference population reject outliers independently.
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runStrainMapping(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("No dataset is loaded") }
        guard !diskDetectionSettingsAreStale else {
            let reason = "Detection settings changed — run Detect All Disks again before computing strain."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let bragg = resultPresentation.braggVectors else {
            let reason = "Run disk detection first — strain mapping needs detected Bragg peaks."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        let cancellation = beginCancellableOperation(
            "Strain mapping", status: "Computing strain map…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let calibrated = calibratedBraggVectors(bragg, descriptor: descriptor)
        let origin = calibrated.origin.point
        let referenceMask = strain.referenceMode == .selectedRegion
            ? realSpaceRegionMask(descriptor) : nil
        let initialBasis = strain.manualInitialBasis
        let epoch = datasetSession.epoch
        let map = await Task.detached(priority: .userInitiated) {
            StrainMapping.compute(bragg: calibrated.vectors,
                                  originX: origin.x, originY: origin.y,
                                  referenceMask: referenceMask,
                                  initialBasis: initialBasis,
                                  cancellation: cancellation)
        }.value
        guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
            statusText = "Strain mapping cancelled"
            return .cancelled
        }
        guard let map else {
            // Classify before wording: a starved peak population and an
            // ill-conditioned lattice are different failures with different
            // fixes, and naming both remedies every time (backlog #8) told the
            // user to go and change settings in a task that was not at fault.
            let cause: StrainFailureCause
            if let summary = completedDiskSummary, summary.positionCount > 0 {
                cause = .classify(
                    medianPeaks: summary.medianPeakCount,
                    emptyPercent: summary.zeroPeakPositionCount * 100 / summary.positionCount
                )
            } else {
                cause = .illConditionedBasis
            }
            strain.recordFailure(cause)

            var detail: String
            switch cause {
            case .starvedInput(let medianPeaks, let emptyPercent):
                detail = String(
                    format: "Only %.1f peaks per pattern were detected (%d%% of positions "
                        + "had none). Indexing a lattice needs the direct beam plus two "
                        + "more reflections, so lower the detection thresholds in Bragg "
                        + "disks and detect again.",
                    medianPeaks, emptyPercent
                )
            case .illConditionedBasis:
                detail = strain.basisMode == .manual
                    ? "The manual basis is ill-conditioned, or too few peaks index to it. "
                        + "Check g₁ and g₂, or switch the basis back to Automatic."
                    : "The peak population is healthy, but no single lattice explains "
                        + "enough of it — which is what happens when the reference "
                        + "averages over regions with different lattices. "
                        + (strain.referenceMode == .wholeScan
                           ? "Pick an unstrained region as the reference instead."
                           : "Try a different reference region, or set g₁ and g₂ manually.")
                if let summary = completedDiskSummary, summary.positionCount > 0 {
                    detail += String(
                        format: " (Detected input: median %.1f peaks per pattern, "
                            + "%d%% of positions empty.)",
                        summary.medianPeakCount,
                        summary.zeroPeakPositionCount * 100 / summary.positionCount
                    )
                }
            }
            if let warning = completedDiskSummary?.warnings.first {
                detail += " " + warning
            }
            presentComputeFailure(SimpleError("Could not publish strain. \(detail)"))
            return .failed("Could not publish strain. \(detail)")
        }
        // Snapshot the origin provenance WITH the map (Gate B, 2026-08-28):
        // these keys describe the fit this map was computed against, and
        // reading them at export time let them describe a different one.
        strain.publish(map, originProvenance: originFitProvenance)
        // Recipe step (v2 S5): the run's modes plus the RESOLVED basis — an
        // automatic basis re-derived on a different view can legitimately
        // differ, so the recipe records both; S6 decides which fidelity a
        // replay wants. Tokens are the RESULT-PROVENANCE vocabulary
        // ("consensus"/"manual", "selected-region"/"whole-scan"), not Swift
        // case names — the two carriers share keys and must share values
        // (Gate B-lite F10).
        recordReplayStep(kind: "strain", parameters: [
            "reference_mode": map.diagnostics.referenceMaskApplied
                ? "selected-region" : "whole-scan",
            "basis_mode": map.diagnostics.automaticBasis ? "consensus" : "manual",
            "resolved_g1_x": String(map.refG1.x), "resolved_g1_y": String(map.refG1.y),
            "resolved_g2_x": String(map.refG2.x), "resolved_g2_y": String(map.refG2.y),
        ], replaying: replaying)
        resultPresentation.resultColormap = .rdbu   // diverging map without recoloring the CBED pane
        applyStrainDisplay()
        statusText = String(format: "Strain ✓  %.0f%% indexed · %.0f%% basis support · RMS %.3g px · κ %.2f · %d/%d ref",
                            map.indexedFraction * 100,
                            map.diagnostics.basisSupportFraction * 100,
                            map.diagnostics.basisResidualPixels,
                            map.diagnostics.basisConditionNumber,
                            map.referencePositionCount,
                            map.diagnostics.referenceCandidateCount)
        return .published
    }
}
