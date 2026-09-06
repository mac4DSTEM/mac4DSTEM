//
//  AppState+DiffractionGroups.swift
//  Role: docs/ai-ml/README.md §6's orchestration — run the classical
//        PCA + k-means baseline (`DiffractionEmbedding.compute`) over the
//        streamed cube and publish its group map, then let the user ask for
//        a similarity map against the currently selected scan position.
//        `DiffractionGroupsProduct` (Session/DiffractionGroupsProduct.swift)
//        owns the retained result and run controls this reads and writes;
//        this file owns nothing itself. Run/publish pattern follows
//        `runVirtualDetector`: a cancellable token, a progress callback
//        hopped to the main actor, a dataset-epoch guard, then the publish.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    /// Group every scan position's diffraction pattern by similarity and
    /// publish the group-index map. No dataset means nothing to embed.
    @discardableResult
    func runDiffractionGroups() async -> AnalysisRunOutcome {
        guard let fourD, let descriptor else { return .failed("No dataset is loaded") }
        let totalPatterns = descriptor.rx * descriptor.ry
        let settings = diffractionGroups.settings
        let cancellation = beginCancellableOperation(
            "Diffraction groups", status: "Grouping diffraction patterns…",
            totalUnits: totalPatterns
        )
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetEpoch

        // Hopped to the main actor exactly like runVirtualDetector's
        // progressUpdate: DiffractionEmbedding.compute calls this from its
        // own (background) task, and `updateCancellableOperation` is
        // main-actor state.
        let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentOperation(cancellation) else { return }
                let clipped = min(1, max(0, fraction))
                self.updateCancellableOperation(
                    cancellation, progress: clipped,
                    status: "Grouping diffraction patterns… \(Int((clipped * 100).rounded()))%"
                )
            }
        }

        do {
            guard let result = try await DiffractionEmbedding.compute(
                data: fourD, descriptor: descriptor, settings: settings,
                cancellation: cancellation, progress: progressUpdate
            ) else {
                statusText = "Diffraction groups cancelled"
                return .cancelled
            }
            guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
            diffractionGroups.publish(result)

            let firstThreePercent = result.explainedVariance.prefix(3).reduce(0, +) * 100
            publishProduct(
                kind: "diffraction_groups",
                displayName: "Diffraction groups (k)",
                valueUnits: "group",
                payload: .scalar(DiffractionEmbedding.groupMap(result)),
                extraProvenance: [
                    "quantitative_status": "categorical",
                    "binned_size": String(settings.binnedSize),
                    "components": String(result.componentCount),
                    "groups": String(result.groupCount),
                    "explained_variance_first3_percent": String(format: "%.1f", firstThreePercent),
                    "seed": String(settings.seed),
                ]
            )
            statusText = "\(result.groupCount) groups from \(totalPatterns) patterns, "
                + "first 3 components explain \(String(format: "%.1f", firstThreePercent)) %"
            return .published
        } catch {
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// Cosine-similarity map to the currently selected real-space scan
    /// position, against the last published grouping result. Needs a result
    /// (`runDiffractionGroups` must have published one) and a dataset whose
    /// scan shape still matches it.
    @discardableResult
    func showSimilarityToCurrentPosition() -> AnalysisRunOutcome {
        guard let result = diffractionGroups.result else {
            return .failed("Group the diffraction patterns first")
        }
        guard let descriptor else { return .failed("No dataset is loaded") }
        guard result.scanWidth == descriptor.rx, result.scanHeight == descriptor.ry else {
            return .failed("The grouped result no longer matches this dataset's scan shape")
        }
        let x = selectedScan.x, y = selectedScan.y
        let position = y * result.scanWidth + x
        guard position >= 0, position < result.scanWidth * result.scanHeight else {
            return .failed("The selected scan position is outside the grouped result")
        }
        let similarity = DiffractionEmbedding.similarity(to: position, in: result)
        diffractionGroups.referencePosition = position
        publishProduct(
            kind: "diffraction_similarity",
            displayName: "Similarity to (\(x), \(y))",
            valueUnits: "cosine",
            payload: .scalar(FloatImage(
                width: result.scanWidth, height: result.scanHeight, pixels: similarity)),
            extraProvenance: [
                "quantitative_status": "relative",
                "reference_x": String(x), "reference_y": String(y),
            ]
        )
        statusText = "Similarity to scan position (\(x), \(y))"
        return .published
    }
}
