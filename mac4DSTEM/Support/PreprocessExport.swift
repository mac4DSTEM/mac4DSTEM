//
//  PreprocessExport.swift
//  Role: the AppState side of "Preprocess Raw Data…" (X3) — the file panels,
//        the pending open for a raw file or for the current view, and the ONE
//        write both doors share.
//
//  Both doors end in `runDataCubeWrite`, which calls the same Core writer
//  (`BraggVectorEMDWriter.writeCalibratedDataCube`) with the same options
//  value (`PreprocessDraft.options`): a setting writes the same file whether
//  the source is a raw file picked in the sheet or the cube that is open.
//  Panels live here, not in the sheet: views are SwiftUI only.
//

import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import UniformTypeIdentifiers

/// What one datacube write needs, gathered before the first suspension.
struct DataCubeWriteRequest {
    let source: any FourDDataSource
    let view: LoadView
    let calibration: PixelCalibration
    let options: CalibratedDataCubeExportOptions
    let destination: URL
    let sourceFileName: String?
    let recipe: SessionReplayRecord?
    let recipeOmission: String?
    /// True when the write belongs to the open dataset's session: its lineage
    /// records the export, and the result is dropped if the dataset changed.
    let recordsRun: Bool
}

enum DataCubeWriteOutcome: Equatable {
    case wrote(message: String)
    case cancelled
    case failed(String)
}

extension AppState {

    // MARK: - Entry

    /// File ▸ Preprocess Raw Data…, the toolbar's and the sidebar's row. With a
    /// cube open the sheet is the same one, pre-filled with the current view
    /// (owner 2026-10-01, answer 2a); without one, a file is picked first.
    func requestPreprocessRawData() {
        if hasDataset {
            requestPreprocessingExport()
            return
        }
        guard !datasetSession.isLoading, let url = chooseRawFileForPreprocessing() else { return }
        openFileForConfiguration(url: url, preprocess: true)
    }

    /// The sheet's "Choose…" beside the source file: drop this pending open and
    /// start another, so the loading card shows the new file's progress.
    func chooseOtherPreprocessSource() {
        guard let url = chooseRawFileForPreprocessing() else { return }
        discardPendingLoad()
        openFileForConfiguration(url: url, preprocess: true)
    }

    /// The open dataset's current view as a pending open, for the sheet.
    func makeCurrentViewPending(descriptor: DatasetDescriptor) -> PendingLoad? {
        guard let fourD = datasetSession.fourD, let reader = datasetSession.reader else { return nil }
        let pending = PendingLoad(
            currentView: fourD, reader: reader, url: URL(fileURLWithPath: descriptor.filePath)
        )
        pending.preprocess = PreprocessDraft(origin: .currentView(name: descriptor.fileName))
        // The preview the open already sampled: same frame, no second pass.
        pending.preview = datasetSession.preview
        pending.fetchDefaultSingleDP()
        return pending
    }

    // MARK: - Panels

    private func chooseRawFileForPreprocessing() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Preprocess Raw Data"
        panel.message = "Choose the file to reduce. It is never changed."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // The same types Open Dataset… accepts.
        panel.allowedContentTypes = ["h5", "hdf5", "emd", "dm4", "dm3", "mib", "raw", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func choosePreprocessDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Write Preprocessed py4DSTEM DataCube"
        panel.message = "The source stays unchanged. mac4DSTEM writes a new canonical EMD file."
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Write

    /// Write what the sheet shows. `finish` runs once, on the main actor, with
    /// how it ended; the sheet decides whether to close.
    func writePreprocessed(
        pending: PendingLoad, to url: URL,
        finish: @escaping @MainActor (DataCubeWriteOutcome) -> Void
    ) {
        guard var draft = pending.preprocess else { return }
        let options = draft.options(for: pending.configuration)
        draft.destination = url
        draft.failure = nil
        draft.writeProgress = 0
        pending.preprocess = draft
        let progress: @MainActor (Double) -> Void = { fraction in
            pending.preprocess?.writeProgress = fraction
        }
        let done: @MainActor (DataCubeWriteOutcome) -> Void = { outcome in
            pending.preprocess?.writeProgress = nil
            if case .failed(let message) = outcome { pending.preprocess?.failure = message }
            finish(outcome)
        }
        switch draft.origin {
        case .currentView:
            exportCalibratedDataCube(options: options, to: url, progress: progress, finish: done)
        case .rawFile:
            // The file's own calibration and nothing else (owner 2026-10-01,
            // answer 1a): no session calibration exists for it, and no value
            // is invented to fill one.
            Task { @MainActor in
                let calibration = await pending.reader.pixelCalibration() ?? PixelCalibration()
                runDataCubeWrite(
                    DataCubeWriteRequest(
                        source: pending.reader,
                        view: LoadView(fullExtentOf: pending.source),
                        calibration: calibration, options: options,
                        destination: url, sourceFileName: pending.source.fileName,
                        recipe: nil, recipeOmission: nil, recordsRun: false
                    ),
                    progress: progress, finish: done
                )
            }
        }
    }

    /// A progress tick reaches the sheet only while its operation is still the
    /// current one: a late hop after done/cancel/failure must not put the sheet
    /// back into "writing" (CR1 item 2).
    func deliverWriteProgress(_ token: AnalysisCancellationToken, _ fraction: Double,
                              to progress: @MainActor (Double) -> Void) {
        guard isCurrentOperation(token) else { return }
        progress(fraction)
    }

    /// The one write: Core's writer, atomic, cancellable, progress in the
    /// shared operation (its Cancel is `cancelActiveOperation`).
    func runDataCubeWrite(
        _ request: DataCubeWriteRequest,
        progress: @escaping @MainActor (Double) -> Void,
        finish: @escaping @MainActor (DataCubeWriteOutcome) -> Void
    ) {
        let options = request.options
        let url = request.destination
        let epoch = datasetSession.epoch
        let token = beginCancellableOperation(
            "Preprocessing export", status: "Writing preprocessed DataCube…",
            totalUnits: options.scanYPositions.count * options.scanXPositions.count
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.updateCancellableOperation(
                            token, progress: fraction,
                            status: "Writing preprocessed DataCube… \(Int(fraction * 100)) %"
                        )
                        self?.deliverWriteProgress(token, fraction, to: progress)
                    }
                }
                let summary = try await Task.detached(priority: .userInitiated) {
                    try await BraggVectorEMDWriter.writeCalibratedDataCube(
                        source: request.source, view: request.view,
                        calibration: request.calibration,
                        options: options, to: url,
                        sourceFileName: request.sourceFileName,
                        replayRecord: request.recipe,
                        cancellation: token,
                        progress: progressUpdate
                    )
                }.value
                // A superseded write reports nothing of its own, but the sheet
                // must still leave its writing state.
                guard self.isCurrentOperation(token), self.datasetSession.epoch == epoch else {
                    finish(.cancelled)
                    return
                }
                let dropped = summary.discardedQRows + summary.discardedQColumns
                var suffix = dropped == 0
                    ? ""
                    : " (trimmed \(summary.discardedQRows) Q row, \(summary.discardedQColumns) Q column)"
                if options.hotPixelThreshold != nil {
                    suffix += " · \(summary.hotPixels.count) hot pixel\(summary.hotPixels.count == 1 ? "" : "s") replaced"
                }
                if let omission = request.recipeOmission {
                    // A partial truth stated whole: the file exists and is
                    // correct; the recipe attribute is absent, and this is
                    // the one carrier of why.
                    suffix += " · recipe not carried: \(omission)"
                }
                let message = "Wrote \(url.lastPathComponent) · "
                    + summary.shape.map(String.init).joined(separator: " × ")
                    + " · " + summary.shape.reduce(MemoryLayout<Float>.size, *).formatted(.byteCount(style: .file))   // same style as UI/LayoutPolicy `displayByteString` (Finder's); Support does not call UI
                    + suffix
                self.statusText = message
                if request.recordsRun {
                    self.recordExportRun(format: "py4dstem_datacube", fileName: url.lastPathComponent)   // lineage sink (ADR 047)
                }
                finish(.wrote(message: message))
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                guard self.isCurrentOperation(token) else {
                    finish(.cancelled)
                    return
                }
                self.statusText = "Preprocessing cancelled"
                finish(.cancelled)
            } catch {
                guard self.isCurrentOperation(token), self.datasetSession.epoch == epoch else {
                    finish(.cancelled)
                    return
                }
                let detail = Self.errorDetail(error)
                self.statusText = "Preprocessing failed: \(detail)"
                finish(.failed(detail))
            }
        }
    }
}
