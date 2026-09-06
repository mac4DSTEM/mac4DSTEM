//
//  AppState+DiskLabels.swift
//  Role: v3-plan §3a step 5's app-side wiring for `DiskLabelStore` (the
//        confirmed/rejected learned-disk-detection patterns) — labelling the
//        currently displayed pattern, persisting the store into the session
//        sidecar (the plan's decided owner of this state), and exporting it
//        for fine-tuning. `DiskLabelStore` itself knows nothing about
//        `AppState`, `BraggPeak`, or HDF5; this file is the seam that
//        connects it to the live session.
//
//  **Why this duplicates a few lines of `ResultExport.swift`.** The panel
//  fallback in `writableDiskLabelsSidecarURL` and the grant bookkeeping in
//  `rememberDiskLabelsSidecarGrant` below are near-copies of
//  `writableSessionSidecarURL`/`rememberSidecarGrant` in that file. Both are
//  `private`, which in Swift means file-private for a top-level `private
//  func` — invisible even to another extension of the same type in a
//  different file — and this session's brief asked that `ResultExport.swift`
//  not be touched. Two call sites hand-rolling the same six-line grant
//  sequence is exactly the class of defect `SessionSidecarLocator`'s own
//  header warns about (its bookmark, `sessionSidecar.grant`/`.adopt`, IS
//  shared — only the save-panel glue around it is copied); if a third
//  sidecar-writing call site is ever added, that glue belongs in
//  `SessionSidecarLocator` itself, not copied a third time.
//

import AppKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import UniformTypeIdentifiers

extension AppState {

    // MARK: - Labelling the displayed pattern

    /// Whether `labelCurrentPatternForDisks` can succeed right now — the same
    /// three conditions it checks, exposed so `DiskLabelRows` can disable its
    /// buttons instead of letting the user press them and read a refusal.
    var canLabelCurrentPattern: Bool {
        descriptor != nil && displayedPattern != nil
            && patternDisplayMode == .current
            && learnedDetection.detectorClass == .learned
    }

    /// Record a verdict on the learned candidates at the currently displayed
    /// scan position. Not a run — it publishes nothing and touches no
    /// product; it only appends to `diskLabels`.
    ///
    /// Requires: a dataset open, the pattern display on `.current` (Mean/Max
    /// are whole-scan statistics with no single position to label — the same
    /// restriction `displayedPattern`'s own doc comment states for the
    /// virtual-diffraction case), and the learned detector selected — a
    /// verdict on candidates nobody is looking at is not a label, and
    /// classical detection has no candidate stage to confirm or reject
    /// (`DetectorClass`'s doc comment: `.learned` is the only stage that
    /// proposes CANDIDATES rather than measuring directly).
    @discardableResult
    func labelCurrentPatternForDisks(_ verdict: DiskLabelStore.Label.Verdict) -> AnalysisRunOutcome {
        guard learnedDetection.detectorClass == .learned else {
            return .failed("Select the learned detector before labelling — a label judges the learned candidate stage")
        }
        guard let descriptor, displayedPattern != nil else {
            return .failed("No diffraction pattern is displayed")
        }
        guard patternDisplayMode == .current else {
            return .failed("Switch the pattern display to Current — Mean and Max have no single scan position to label")
        }
        let scan = selectedScan
        let label = DiskLabelStore.Label(
            filePath: descriptor.filePath, scanX: scan.x, scanY: scan.y,
            detectorClass: learnedDetection.detectorClass.provenanceID,
            weightsHash: learnedDetection.assetSHA256 ?? "",
            threshold: learnedDetection.threshold,
            verdict: verdict,
            peaks: currentPeaks.map {
                DiskLabelStore.Label.Peak(x: $0.x, y: $0.y, intensity: $0.intensity)
            },
            notedAt: Date()
        )
        diskLabels.record(label)
        statusText = "\(verdict == .confirmed ? "Confirmed" : "Rejected") \(currentPeaks.count) learned "
            + "candidates at scan (\(scan.x), \(scan.y))"
        return .published
    }

    // MARK: - Session sidecar persistence

    /// Write the recorded labels into the session sidecar, the same way
    /// calibration is (`saveCalibrationToSessionSidecar`): the same rewrite
    /// gate (`gates.sidecarRewriteRefusal()`), the same first-save panel /
    /// remembered-grant sequence, and an attribute on the sidecar's root
    /// group — `mac4dstem_disk_labels` (`BraggVectorEMDWriter`). That writer
    /// rebuilds the whole file on every rewrite (`writeFile`), restating the
    /// load specification and replay record exactly as the calibration save
    /// does — omitting either would silently erase a recorded crop or recipe
    /// (the S5 lesson `saveCalibrationToSessionSidecar`'s own comment names).
    ///
    /// **Calibration is round-tripped, not recomputed.** `mergeCalibration`'s
    /// `calibration` argument is written VERBATIM into a freshly created HDF5
    /// group on every rewrite (`BraggVectorEMDWriter.writeCalibration` has no
    /// "leave what's already there" mode) — every other rewrite call site
    /// supplies the LIVE session calibration via `ResultExport`'s private
    /// `sessionPixelCalibration(descriptor:)`, which this file cannot call
    /// (private, and `ResultExport.swift` is out of scope for this session —
    /// see the header). Reading back whatever the sidecar already has and
    /// handing it straight to the rewrite is lossless for calibration and
    /// keeps this save from repeating that function's detector-axis-swap
    /// logic. A first-ever save with no existing sidecar writes a bare
    /// calibration group — nothing is lost, because nothing was ever
    /// recorded. If a session ever needs to save fresh calibration and disk
    /// labels together, that path should go through
    /// `saveCalibrationToSessionSidecar` with a `diskLabelsJSON` argument
    /// threaded in the same way, not duplicate the axis-swap here.
    ///
    /// Synchronous, unlike the calibration/result saves' detached-`Task`
    /// wrapping — the JSON attribute itself is tiny, and this file's
    /// signature (`AppState+DiskLabels`'s brief) returns the verdict
    /// directly rather than firing a background task. If profiling ever
    /// shows this blocking the UI on a sidecar with many large saved
    /// results, wrap it the way `saveCalibrationToSessionSidecar` is
    /// wrapped — the gate and the writer call do not need to change.
    @discardableResult
    func saveDiskLabelsToSessionSidecar() -> AnalysisRunOutcome {
        guard let descriptor else {
            return .failed("No dataset is open")
        }
        if let refusal = gates.sidecarRewriteRefusal() {
            return .failed(refusal)
        }
        guard let url = writableDiskLabelsSidecarURL(for: descriptor) else {
            return .failed("Session sidecar save cancelled")
        }
        let json: String
        do {
            json = String(decoding: try diskLabels.encodedJSON(), as: UTF8.self)
        } catch {
            return .failed("Could not encode disk labels: \(error.localizedDescription)")
        }
        let existingCalibration = (try? BraggVectorEMDWriter.loadSession(from: url))?.calibration
            ?? PixelCalibration()
        do {
            try BraggVectorEMDWriter.mergeCalibration(
                existingCalibration, qWidth: descriptor.qx, qHeight: descriptor.qy,
                to: url,
                loadSpecification: loadedView.specification,
                replayRecord: replay.recordForSaving,
                diskLabelsJSON: json
            )
        } catch {
            present(error)
            return .failed(error.localizedDescription)
        }
        rememberDiskLabelsSidecarGrant(url, for: descriptor)
        statusText = "Saved \(diskLabels.count(for: .confirmed)) confirmed, "
            + "\(diskLabels.count(for: .rejected)) rejected disk label(s) → \(url.lastPathComponent)"
        return .published
    }

    /// Populate `diskLabels` from the session sidecar. Called once per
    /// dataset activation — see this type's header for the exact call site
    /// this session could not add itself.
    ///
    /// Unconditionally clears first: labels belong to the dataset whose
    /// sidecar they came from, and a reopen with no sidecar (or a different
    /// dataset) must not leave the previous dataset's labels on screen — the
    /// same silent-stale-state class `LearnedDetectionSession.clear()` and
    /// `StrainProduct.clear()` exist to prevent for their own state.
    func loadDiskLabelsFromSessionSidecar() {
        diskLabels.clear()
        guard let descriptor else { return }
        let url = sessionSidecar.location(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            guard let json = try BraggVectorEMDWriter.loadDiskLabelsJSON(from: url) else { return }
            for label in try DiskLabelStore.decode(Data(json.utf8)) {
                diskLabels.record(label)
            }
        } catch {
            // Non-fatal and non-modal, matching `loadSessionSnapshot`'s own
            // sidecar-read failures: a session's saved analyses still load
            // even when the labels attribute cannot be read.
            statusText = "Could not restore disk labels: \(error.localizedDescription)"
        }
    }

    // MARK: - Fine-tuning export

    /// Export every recorded label to `~/Documents/mac4DSTEM/disk-labels/` —
    /// see `DiskLabelStore.exportForFineTuning`'s doc comment for why not
    /// directly into the repo's gitignored `tools/disk-detector/labels/`
    /// (the app has no repo path, and would not be right to assume the
    /// owner's checkout layout even if it did). The owner copies from the
    /// Documents folder into that tree when a fine-tuning run is ready
    /// (docs/v3-plan.md §3a).
    @discardableResult
    func exportDiskLabelsForFineTuning() -> AnalysisRunOutcome {
        guard !diskLabels.labels.isEmpty else {
            return .failed("No confirmed or rejected disk labels to export")
        }
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return .failed("Could not resolve the Documents folder")
        }
        let folder = documents.appendingPathComponent("mac4DSTEM/disk-labels", isDirectory: true)
        let datasetName = descriptor.map {
            URL(fileURLWithPath: $0.filePath).deletingPathExtension().lastPathComponent
        } ?? "session"
        do {
            let url = try diskLabels.exportForFineTuning(to: folder, datasetName: datasetName)
            statusText = "Exported \(diskLabels.labels.count) disk label(s) → \(url.path)"
            return .published
        } catch {
            return .failed("Could not export disk labels: \(error.localizedDescription)")
        }
    }

    // MARK: - Sidecar URL / grant (duplicated from `ResultExport.swift` — see header)

    private func writableDiskLabelsSidecarURL(for descriptor: DatasetDescriptor) -> URL? {
        if let granted = sessionSidecar.grant(for: descriptor) { return granted }
        let suggested = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        let panel = NSSavePanel()
        panel.title = "Choose Session Sidecar"
        panel.message = "Choose the companion file mac4DSTEM may update and reopen."
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "Session sidecar save cancelled"
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        sessionSidecar.adopt(url, for: descriptor)
        return url
    }

    private func rememberDiskLabelsSidecarGrant(_ url: URL, for descriptor: DatasetDescriptor) {
        do {
            try sessionSidecar.remember(url, for: descriptor)
        } catch {
            statusText = "Saved disk labels; choose the sidecar again after relaunch"
            errorMessage = "Disk labels were saved to \(url.lastPathComponent), but mac4DSTEM could not "
                + "remember access for a future launch: \(error.localizedDescription)"
        }
    }
}
