//
//  DatasetSession.swift
//  Role: seam 6 (docs/appstate-seams-plan.md) — the one owner of the open
//        dataset, its stale-publish epoch, preview and loading state.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class DatasetSession {

    package nonisolated init() {}

    package private(set) var reader: (any FourDDataSource)?
    package private(set) var fourD: FourDArray?
    package private(set) var datasets: [DatasetDescriptor] = []
    package private(set) var preview: DatasetPreview?

    /// Increments whenever a new dataset is activated or a partial load is
    /// discarded. Long-running work captures this value and refuses to publish
    /// when it no longer matches.
    package private(set) var epoch = 0

    /// Nil during phases whose duration cannot be measured honestly.
    package private(set) var loadingProgress: Double?
    package private(set) var loadingStatus: String?
    package private(set) var isLoading = false
    package private(set) var loadCancellation: AnalysisCancellationToken?
    package private(set) var isCancellingLoad = false

    package var loadWasCancelled: Bool {
        loadCancellation?.isCancelled == true
    }

    package var canCancelLoad: Bool {
        isLoading && loadCancellation != nil && !isCancellingLoad
    }

    package var loadView: LoadView? { fourD?.view }

    package var cubeAndDescriptor: (FourDArray, DatasetDescriptor)? {
        guard let fourD else { return nil }
        return (fourD, fourD.view.descriptor)
    }

    /// Starts dataset replacement at the same point the pre-seam AppState did:
    /// before view validation and before the activation pipeline can suspend.
    package func beginActivation() {
        epoch &+= 1
    }

    /// Installs the exact reader/view pair after synchronous view validation.
    package func install(reader: any FourDDataSource, view: LoadView) {
        let array = FourDArray(reader: reader, view: view)
        self.reader = reader
        self.fourD = array
    }

    /// Records file discovery before activation. This preserves the configured
    /// open pipeline's existing ordering without advancing the publish guard;
    /// `activate(reader:view:)` remains the sole successful-activation bump.
    package func prepare(reader: any FourDDataSource, datasets: [DatasetDescriptor]) {
        self.reader = reader
        self.datasets = datasets
    }

    package func addDatasetIfNeeded(_ descriptor: DatasetDescriptor) {
        if !datasets.contains(where: { $0.datasetPath == descriptor.datasetPath }) {
            datasets.append(descriptor)
        }
    }

    package func publishPreview(_ preview: DatasetPreview?) {
        self.preview = preview
    }

    package func clearReaderAndArray() {
        fourD = nil
        reader = nil
    }

    package func clearDatasetListAndPreview() {
        datasets = []
        preview = nil
    }

    package func advanceEpochAfterDiscard() {
        epoch &+= 1
    }

    package func beginLoading(_ status: String) {
        isLoading = true
        loadCancellation = AnalysisCancellationToken()
        isCancellingLoad = false
        loadingProgress = nil
        loadingStatus = status
    }

    package func finishLoading() {
        isLoading = false
        loadCancellation = nil
        isCancellingLoad = false
        loadingProgress = nil
        loadingStatus = nil
    }

    @discardableResult
    package func requestCancellation() -> Bool {
        guard let token = loadCancellation, !isCancellingLoad else { return false }
        isCancellingLoad = true
        token.cancel()
        loadingProgress = nil
        loadingStatus = "Cancelling…"
        return true
    }

    package func beginLoadingStage(_ status: String) {
        guard isLoading else { return }
        loadingProgress = nil
        loadingStatus = status
    }

    package func reportLoadingProgress(_ fraction: Double, _ status: String) {
        guard isLoading else { return }
        loadingProgress = min(1, max(0, fraction))
        loadingStatus = status
    }

    package func mirrorOperationProgress(_ progress: Double?, _ status: String) {
        guard isLoading else { return }
        loadingProgress = progress
        loadingStatus = status
    }
}
