import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// Seam 7 placement: configured-open entry points and preview/demo helpers.
extension AppState {
    /// Open far enough to look at, then **stop and ask**.
    /// Reached only from "Open with options…" — `openFile` still loads the whole
    /// file with no interruption, which is the entry point almost every open
    /// uses. Everything done here is cheap: open the reader, discover the
    /// descriptor, sample a strided preview. The expensive pass waits for
    /// `commitPendingLoad`.
    ///
    /// `preprocess` makes the same pending open the "Preprocess Raw Data…"
    /// sheet's (X3): the previews and crop are the configurator's, the file
    /// written is a reduced copy instead of a load.
    func openFileForConfiguration(url: URL, preprocess: Bool = false) {
        // Review a6 / owner card D2 (a): a dataset another window holds is refused before this window changes, and
        // the open claims its file while in flight. A Preprocess source is only read — never a session, never its
        // sidecar — so it is neither refused nor claimed.
        if !preprocess, let refusal = OpenDatasetRegistry.refusal(opening: url, by: self) {
            present(SimpleError(refusal))
            return
        }
        if !preprocess { OpenDatasetRegistry.beginOpening(url, by: self) }
        Task {
            defer { if !preprocess { OpenDatasetRegistry.endOpening(url, by: self) } }
            let load = beginDatasetLoading("Opening \(url.lastPathComponent)…")
            defer { finishDatasetLoading(owner: load) }
            let accessed = url.startAccessingSecurityScopedResource()
            do {
                let reader = try await Self.makeReader(for: url)
                beginDatasetLoadingStage("Reading file structure of \(url.lastPathComponent)…")
                let source = try await reader.discoverPrimaryDataset()
                guard source.is4D else {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    present(H5Error.unsupportedRank(source.shape.count))
                    return
                }
                // Asked again by the dataset's own file: a reader can resolve another one (an EMPAD .xml names its .raw).
                if !preprocess, let refusal = OpenDatasetRegistry.refusal(
                    opening: URL(fileURLWithPath: source.filePath), by: self
                ) {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    present(SimpleError(refusal))
                    return
                }
                if datasetSession.loadWasCancelled {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    return
                }
                let size = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size]) as? NSNumber
                let pending = PendingLoad(
                    source: source, reader: reader, url: url,
                    accessedSecurityScope: accessed,
                    fileByteCount: size?.intValue
                )
                let pendingEpoch = datasetSession.epoch
                // Sample the full source through the pending array's shared cache.
                // Both open paths report determinate progress for the same epoch.
                beginDatasetLoadingStage("Sampling a preview…")
                let previewResult = await PendingLoad.makePreview(
                    data: pending.data, descriptor: source,
                    cancellation: datasetSession.loadCancellation,
                    progress: previewProgressHandler(
                        rows: DatasetPreviewBuilder.sampledRowCount(for: source), epoch: pendingEpoch
                    )
                )
                guard datasetSession.epoch == pendingEpoch, !datasetSession.loadWasCancelled else {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    return
                }
                switch previewResult {
                case .success(let preview):
                    pending.preview = preview
                    // The last progress tick ("Sampling a preview · row 24 of 25") would
                    // otherwise stay in the footer under the drawn previews (drive 3).
                    statusText = preprocess
                        ? "Preview ready — choose what to write"
                        : "Preview ready — choose what to load"
                case .failure(let error):
                    if error is CancellationError {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                        return
                    }
                    pending.previewFailure = Self.errorDetail(error)
                    statusText = "Preview unavailable: \(Self.errorDetail(error))"
                }
                if preprocess { pending.preprocess = PreprocessDraft(origin: .rawFile) }
                pending.fetchDefaultSingleDP()
                if let displaced = promotionRun.replace(with: pending) {
                    displaced.cancelSingleDPFetch()
                    if displaced.accessedSecurityScope {
                        displaced.url.stopAccessingSecurityScopedResource()
                    }
                }
                finishDatasetLoading(owner: load)
            } catch {
                if accessed { url.stopAccessingSecurityScopedResource() }
                present(error)
            }
        }
    }

    /// Shared progress for both open paths. Weak capture avoids retaining the
    /// window; epoch AND loading state reject late ticks from a previous open.
    private func previewProgressHandler(rows: Int, epoch: Int) -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.datasetSession.epoch == epoch,
                      self.datasetSession.isLoading else { return }
                let done = min(rows, max(0, Int((fraction * Double(rows)).rounded())))
                self.reportDatasetLoadingProgress(
                    fraction, "Sampling a preview · row \(done) of \(rows)"
                )
            }
        }
    }
    /// Reads and parses a local CIF file, adding the result to this run's
    /// imported-phase-model list and selecting it. Reading/parsing is Core's
    /// job even though it is triggered from a picker — `CIFImport` does the
    /// parsing, this just owns the file access and the resulting state.
    /// Failure here is routed like opening a dataset (`present`, the
    /// window-modal path), not `presentComputeFailure`: a bad CIF is a fresh
    /// file that never entered analysis state, so there is nothing mid-step
    /// to keep usable — same category as a corrupt or unreadable dataset
    /// file. `CIFImportError.errorDescription` names the offending tag,
    /// value, symbol, or point group, so the modal shows a specific reason.
    /// Returns the model it parsed (nil on a refusal) so a caller adds exactly
    /// that model — never `importedCrystalModels.last`, which is another
    /// model after a refusal or an in-place replacement (review e2).
    @discardableResult
    func importCrystalModel(from url: URL) -> CrystalModel? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let baseName = url.deletingPathExtension().lastPathComponent
            let model = try CIFImport.crystalModel(from: text, fileBaseName: baseName)
            if let index = acomSession.importedCrystalModels.firstIndex(where: { $0.id == model.id }) {
                acomSession.importedCrystalModels[index] = model
            } else {
                acomSession.importedCrystalModels.append(model)
            }
            acomSession.modelSelection = .imported(model.id)
            statusText = "Imported phase model \"\(model.displayName)\" from \(url.lastPathComponent)"
            return model
        } catch {
            present(error)
            return nil
        }
    }
    /// Deterministic in-memory dataset shared by UI automation, repeatable
    /// design walkthroughs, and the welcome screen's Try Demo Data path —
    /// every workspace works without a file and nothing on disk is touched.
    /// `specification` exists for tests that need a *reduced* view without a
    /// file on disk (the promote wiring, v2 S3). The app's own callers pass
    /// nothing and open the demo whole.
    func openDemoFixture(
        calibrated: Bool = true,
        specification: LoadSpecification = .fullExtent
    ) async {
        let source = DemoFourDDataSource(includesCalibration: calibrated)
        // Same rule as `commitPendingLoad`: a dataset change outside
        // `openFileAsync` drops the previous dataset's restore-failure
        // flag (v2 S7).
        gates.clearSidecarRestoreFailure()
        let load = beginDatasetLoading("Opening demo dataset…")
        defer { finishDatasetLoading(owner: load) }
        do {
            beginDatasetLoadingStage("Reading file structure of the demo dataset…")
            let descriptor = try await source.discoverPrimaryDataset()
            datasetSession.prepare(reader: source, datasets: [descriptor])
            openURL = nil
            await activate(descriptor: descriptor, reader: source,
                           specification: specification)
            // `activate` fails by presenting and returning, not by throwing —
            // without this guard a specification that does not fit the demo
            // cube still printed "Demo ready…" over the error status, with
            // reader/datasets already swapped and nothing loaded. Both checks
            // are needed: the specification comparison catches a failed
            // re-open OVER a previous demo (a spec that fits the demo does
            // not fail, so a stale spec cannot equal the failing one), and
            // the file-path comparison catches a previous real dataset that
            // happened to share the requested spec (Gate A review).
            guard datasetSession.loadView?.specification == specification,
                  self.descriptor?.filePath == datasetSession.datasets.first?.filePath else { return }
            finishDatasetLoading(owner: load)
            acomSession.display = .ipfZ
            // Keep this string's step names in sync with the current
            // workspace titles — it is data, not a UI label, so a rename
            // elsewhere will not catch a stale name here.
            statusText = "Demo ready — start in Prepare"
        } catch {
            present(error)
        }
    }
    func openManualPath(_ datasetPath: String) {
        guard let reader = datasetSession.reader else {
            present(SimpleError("Open a file before entering a dataset path."))
            return
        }

        Task {
            operationCenter.setBusy(true)
            defer { operationCenter.setBusy(false) }

            do {
                guard let h5 = reader as? H5Reader else {
                    present(SimpleError("Manual dataset paths are only supported for HDF5 files."))
                    return
                }
                let descriptor = try await h5.describe(path: datasetPath)
                datasetSession.addDatasetIfNeeded(descriptor)
                // Bracketed for the same reason as `selectDataset` above: every
                // stage line, the preview sampling and the resident preload
                // are gated on `datasetSession.isLoading` — without this the
                // whole open runs silently while `activate` reports
                // "Loaded …" with the bar at 1.0 (the same #36 stall, one
                // layer down).
                // Unreachable today (nothing calls `openManualPath`), fixed
                // anyway so the trap does not wait for whoever wires it to a
                // control (found by `/code-review ultra`).
                let load = beginDatasetLoading("Opening \(descriptor.datasetPath)…")
                await activate(descriptor: descriptor, reader: h5)
                finishDatasetLoading(owner: load)
            } catch {
                present(error)
            }
        }
    }

    /// The reader for a URL, by extension. Extracted so the configured open and
    /// the direct open cannot drift apart on which formats they accept.
    /// Widened from `private` (seam 3, docs/archive/v4/appstate-seams-plan.md):
    /// `App/AppState+DiskDetection.swift`'s `generateVacuumProbeKernel` calls
    /// it from outside this file.
    static func makeReader(for url: URL) async throws -> any FourDDataSource {
        switch url.pathExtension.lowercased() {
        case "dm4", "dm3": return try await DM4Reader(path: url.path)
        case "mib": return try MIBReader(path: url.path)
        case "raw", "xml": return try EMPADReader(path: url.path)
        default: return try H5Reader(path: url.path)
        }
    }



    func reopenIgnoringSessionSidecar() {
        guard let recoveryRecord,
              let recent = recents.entry(withID: recoveryRecord.datasetID) else {
            present(SimpleError("The current dataset has no recorded reopen path."))
            return
        }
        ignoreSessionForDatasetID = recent.id
        openRecent(recent)
    }


    func selectScan(x: Int, y: Int) {
        if navigation.analysisMode == .acom, acomSession.scope == .selectedRegion {
            acomSession.regionSelectionActive = true
        }
        selectedScan = ScanPos(x: x, y: y)
        persistRecoveryPosition()
        Task { await loadCurrentPattern() }
    }

    /// Session-level failure (file open/read, dataset activation, export
    /// write): raises the window-modal "Something went wrong" alert in
    /// addition to the status bar + log.
    func present(_ error: Error) {
        errorMessage = Self.errorDetail(error)
        statusText = "Error: \(Self.errorDetail(error))"
    }

    /// Recoverable compute failure (an analysis step that did not converge or
    /// whose preconditions are not met, e.g. no strain basis found): surfaces
    /// on the existing non-blocking status bar + log pane only, so the rest
    /// of the window stays usable (docs/ui-workflow-backlog.md #9).
    /// A data-source failure that reaches a compute catch block (corrupted or
    /// vanished file mid-scan) is NOT a compute failure — it invalidates the
    /// session, so it escalates to the modal path regardless of which stage
    /// surfaced it.
    func presentComputeFailure(_ error: Error) {
        if SessionGates.isDataSourceFailure(error) {   // moved here, C7 session 4 (budget)
            present(error)
            return
        }
        statusText = "Error: \(Self.errorDetail(error))"
    }

    /// The dataset files this window holds, for `OpenDatasetRegistry` (review a6, owner card D2 a): the loaded dataset,
    /// and an Open with Options… waiting in the configurator (the file picked and the file its reader resolved). A
    /// Preprocess source is only read, never a session, so it holds nothing.
    var heldDatasetFilePaths: [String] {
        var paths = descriptor.map { [$0.filePath] } ?? []
        if let pending = promotionRun.pendingLoad, pending.preprocess == nil {
            paths += [pending.url.path, pending.source.filePath]
        }
        return paths
    }

    /// Enrols this window's state graph, weakly, with the process's open-dataset registry — from `init`, and again
    /// when its window reappears (the window withdraws it on close). Nothing is stored on AppState for it.
    func enrollInOpenDatasetRegistry() {
        OpenDatasetRegistry.enroll(self) { [weak self] in self?.heldDatasetFilePaths ?? [] }
    }

    func openFileAsync(url: URL) async {
        // Review a6 / owner card D2 (a): one dataset, one window — the two windows' saves would replace each other's
        // session sidecar. Refused before anything of this window changes; this window's own dataset (a reopen,
        // Open with Options…) is never refused. The open claims its file while in flight (`OpenDatasetRegistry`).
        if let refusal = OpenDatasetRegistry.refusal(opening: url, by: self) {
            present(SimpleError(refusal))
            return
        }
        OpenDatasetRegistry.beginOpening(url, by: self)
        defer { OpenDatasetRegistry.endOpening(url, by: self) }
        let load = beginDatasetLoading("Opening \(url.lastPathComponent)…")
        errorMessage = nil
        defer { finishDatasetLoading(owner: load) }

        let previousOpenURL = openURL
        let accessed = url.startAccessingSecurityScopedResource()

        do {
            let reader = try await Self.makeReader(for: url)
            beginDatasetLoadingStage("Reading file structure of \(url.lastPathComponent)…")
            let descriptor = try await reader.discoverPrimaryDataset()
            if await unwindLoadIfNeeded(owner: load) {
                // The scope is this call's own, released whoever owns the reset.
                if accessed { url.stopAccessingSecurityScopedResource() }
                finishDatasetLoading(owner: load)
                return
            }
            // Asked again by the dataset's own file, before the current dataset is released: a reader can resolve
            // another one (an EMPAD .xml names its .raw).
            if let refusal = OpenDatasetRegistry.refusal(opening: URL(fileURLWithPath: descriptor.filePath), by: self) {
                if accessed { url.stopAccessingSecurityScopedResource() }
                finishDatasetLoading(owner: load)
                present(SimpleError(refusal))
                return
            }
            if let previousOpenURL {
                previousOpenURL.stopAccessingSecurityScopedResource()
            }
            sessionSidecar.release()
            // Paired with every `release()`: the restore-failure gate must
            // never outlive the dataset it describes. // v2 S7
            gates.clearSidecarRestoreFailure()
            openURL = accessed ? url : nil
            datasetSession.prepare(reader: reader, datasets: [descriptor])
            let recorded = await recordedLoadSpecification(
                forSourcePath: url.path, source: descriptor
            )
            await activate(
                descriptor: descriptor, reader: reader,
                specification: recorded ?? .fullExtent,
                runInitialAnalysis: false
            )
            if await unwindLoadIfNeeded(owner: load, orNoDataset: true) {
                // `activate` unwinds itself on cancellation; this catches the
                // case where it did, and stops the open continuing into an
                // analysis of a dataset that is no longer there.
                finishDatasetLoading(owner: load)
                return
            }
            // The first whole-cube pass IS part of opening, from the user's
            // point of view: the welcome card is still on screen and the
            // workspace has no image yet. Finishing the load before it ran was
            // what left the bar parked at its last stage and then vanishing
            // into a generic operation indicator.
            await runOpeningAnalysis()
            if await unwindLoadIfNeeded(owner: load) {
                finishDatasetLoading(owner: load)
                return
            }
            // REMEMBERED ONLY ONCE THE LOAD HAS ACTUALLY FINISHED. Moved here
            // from before the whole-cube pass so that a cancel at any point
            // leaves Recents untouched — a cancelled file is one you did not
            // want, and putting it at the top of the list is backwards.
            rememberOpenedDataset(url)
            finishDatasetLoading(owner: load)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            present(error)
        }
    }

    func activate(
        descriptor sourceDescriptor: DatasetDescriptor,
        reader: any FourDDataSource,
        specification: LoadSpecification = .fullExtent,
        runInitialAnalysis: Bool = true,
        keepInMemory: Bool = false,
        initialScan: ScanPos? = nil
    ) async {
        guard sourceDescriptor.is4D else {
            present(H5Error.unsupportedRank(sourceDescriptor.shape.count))
            return
        }
        // The load this activation belongs to: every caller brackets it with
        // `beginDatasetLoading` first. Its cancelled tails reset the session
        // only while that load is still the current one (S18).
        let loadOwner = datasetSession.loadCancellation

        // Dataset replacement is also a cancellation boundary. The epoch still
        // independently prevents any non-cooperative GPU result from landing.
        operationCenter.reset()
        if !isBusy { progress = nil }
        datasetSession.beginActivation()
        beginDatasetLoadingStage("Reading calibration metadata…")
        // ONE view, built once and shared: the array reads through it, the
        // calibration is re-referenced into it, and `loadedView` records it.
        // The specification is `.fullExtent` on every path except L5's
        // configurator, which only offers specifications it has already
        // validated against the source — a specification that does not fit
        // is a caller error, not a user error, so there is no silent
        // fallback to full extent here.
        let view: LoadView
        do {
            view = try LoadView(source: sourceDescriptor, specification: specification)
        } catch {
            present(error)
            return
        }
        self.descriptor = view.descriptor
        datasetSession.install(reader: reader, view: view)

        // EVERYTHING BELOW USES THE VIEW, and the parameter is deliberately
        // named `sourceDescriptor` so that reaching for the file's own extent
        // is something you have to type on purpose. The two are identical on
        // every shipped path today — which is exactly the trap: an
        // adversarial review found four detector-frame defaults still
        // derived from the source, and a fifth (`minPeakSpacing`) whose unit
        // test pinned the function by calling `detectorAdapted` with a view
        // descriptor directly rather than pinning the call site. A crop or
        // bin would have made all five wrong at once, and every one
        // plausible-looking.
        let descriptor = view.descriptor
        // A new array is a new (absent) buffer; the old cube dies with the old
        // array. Resetting here keeps the panel from claiming residency that
        // belonged to the previous dataset.
        residency.reset()
        loadedView.reset()
        sessionLoadSpecification = nil
        datasetSession.publishPreview(nil)
        // The scan position a caller carries across the reopen (promote), only
        // where it is a real position of THIS view; otherwise the origin.
        selectedScan = initialScan.flatMap { start in
            (0..<descriptor.rx).contains(start.x) && (0..<descriptor.ry).contains(start.y) ? start : nil
        } ?? ScanPos(x: 0, y: 0)
        resultPresentation.displayRangeLo = 0
        resultPresentation.displayRangeHi = 1
        resultPresentation.resultGamma = 1
        patternDisplayRangeLo = 0
        patternDisplayRangeHi = 1
        patternGamma = 1
        lastRotationResult = nil
        calibrationSession.lastEllipseFit = nil   // before activate suspends (GB3)
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        phaseContrast.singleslicePtychography = nil
        phaseContrast.parallaxResultProduct = .preprocess
        // THE VIEW'S detector, not the source's. These four are lengths and a
        // position in DETECTOR PIXELS, and a binned or cropped view has
        // fewer of them: on a 256 px detector binned by 4, a "quarter of the
        // detector" aperture read against the source would come out at 64 px
        // on a 64 px detector, with `ellipseFitOuterRadius` at 115 px
        // entirely off it — both plausible-looking numbers, which is what
        // makes this class of bug dangerous (adversarial review finding;
        // trap for L5).
        // `CalibrationReReference` takes the aperture CENTRE as a parameter
        // on the principle that every detector-frame rule belongs in one
        // file. These are defaults rather than re-referenced values — there
        // is no prior value to move — so they belong here, but must be
        // derived from the same frame.
        let detectorHalfSize = Double(min(descriptor.qx, descriptor.qy)) / 2
        calibrationSession.ellipseFitInnerRadius = max(1, detectorHalfSize * 0.35)
        calibrationSession.ellipseFitOuterRadius = max(calibrationSession.ellipseFitInnerRadius + 2, detectorHalfSize * 0.9)
        aperture = Aperture(
            centerX: Float(descriptor.qx) / 2,
            centerY: Float(descriptor.qy) / 2,
            inner: 0,
            outer: Float(defaultBrightFieldRadius(qx: descriptor.qx, qy: descriptor.qy))  // one source with the preview's bright-field disk
        )
        if let rawVoltage = await reader.readDoubleAttribute(
            AcceleratingVoltage.attributeName, onObjectPath: "/"
        ) {
            // One app convention, kV — the rule (eV above 1000) is Core's, shared with the preprocessing export.
            calibrationSession.acceleratingVoltage = AcceleratingVoltage.kilovolts(fromAttribute: rawVoltage)
        } else {
            calibrationSession.acceleratingVoltage = nil
        }
        // Strain dies BEFORE the calibration reset: `activate` suspends on reader
        // awaits in between, the export menu is reachable during a suspension, and
        // the strain frame keys come from the LIVE calibration — an uncleared map
        // would export the previous dataset's scan-frame pixels under this reset's
        // "rotation not calibrated" claim (Gate B finding 3). The group
        // and phase maps are scan-indexed for the same reason.
        strain.clear()
        diffractionGroups.clear()
        phaseMapping.clear()
        // Built from the phase map's OWN scan positions and this session's
        // calibration; neither survives a dataset change, so this dies with
        // the map that produced it, not on its own later trigger.
        precipitateClassification.clear()
        clearCalibration()
        // A DM4 whose axis units cannot be trusted opens WITHOUT its pixel
        // sizes, and the reason goes to the log — the status line is what the
        // log records — so the empty readiness rows are explained, not mute.
        if let dm4 = reader as? DM4Reader, let note = await dm4.calibrationNote {
            statusText = note
        }
        // The aperture centre the FILE recorded, in SOURCE detector pixels — the only
        // aperture position `CalibrationReReference` may move. The default above is a
        // VIEW-frame value (already binned / cropped); re-referencing it a second time
        // put the ring at 7.75 on a 32 px view after bin 2 (drive 3, shot 52).
        var fileApertureCenter: CalibrationReReference.DetectorPoint?
        // Pixel sizes from file metadata (DM4 tags or py4DSTEM EMD bundle).
        if let pc = await reader.pixelCalibration() {
            var rSize = pc.rSize
            var rUnits = pc.rUnits
            // Normalize µm → nm (STEM-scale bars read better in nm).
            if let r = rSize, ["µm", "um", "micron"].contains(rUnits?.lowercased() ?? "") {
                rSize = r * 1000
                rUnits = "nm"
            }
            calibrationSession.calibration.rPixelSize = rSize
            calibrationSession.calibration.rPixelUnits = rUnits
            calibrationSession.calibration.qPixelSize = pc.qSize
            calibrationSession.calibration.qPixelUnits = pc.qUnits
            if rSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.rScale = .importedFile
            }
            if pc.qSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.qScale = .importedFile
            }
            if let flip = pc.qrFlip { calibrationSession.calibration.transposeQR = flip }
            // ADR 040: a file's QR_rotation is py4DSTEM's sign; the app's is its negative.
            calibrationSession.calibration.rotationRad = pc.qrRotationRad
                .map { Float(RQRotationConvention.app(fromPy4DSTEM: $0)) }
            calibrationSession.calibration.probeRadius = pc.probeSemiangle.map(Float.init)
            calibrationSession.calibration.ellipseA = pc.ellipseA
            calibrationSession.calibration.ellipseB = pc.ellipseB
            calibrationSession.calibration.ellipseTheta = pc.ellipseTheta
            if calibrationSession.calibration.hasRotation { calibrationSession.provenance.rotation = .importedFile }
            // S15: an R–Q rotation this app exported before 2026-09-28 carries no sign
            // marker; the value is read as today and the doubt is shown, never resolved.
            if calibrationSession.calibration.hasRotation, let note = pc.qrRotationNote {
                calibrationSession.provenance.rotationImportNote = note
                statusText = note
            }
            if calibrationSession.calibration.probeRadius.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.probe = .importedFile
            }
            if calibrationSession.calibration.hasEllipse { calibrationSession.provenance.ellipse = .importedFile }
            // AXIS SWAP (single documented conversion point — see
            // PixelCalibration.qx0Mean/qy0Mean doc comment): py4DSTEM indexes
            // patterns (qx, qy) with qx as the first/row axis, which is this
            // app's detector y; qy is the second/column axis, this app's x.
            // So app aperture x = qy0Mean, app aperture y = qx0Mean.
            if let qx0 = pc.qx0Mean, let qy0 = pc.qy0Mean {
                aperture.centerX = Float(qy0)
                aperture.centerY = Float(qx0)
                fileApertureCenter = .init(x: Float(qy0), y: Float(qx0))
                // The value gets a HOME, not just a provenance label (v2
                // S13) — stored only in the aperture it would be lost the
                // moment the user moved the detector, leaving every analysis
                // fall through to the detector's geometric middle while the
                // inspector still displayed the file's origin (S11).
                calibrationSession.calibration.recordedOriginX = Float(qy0)
                calibrationSession.calibration.recordedOriginY = Float(qx0)
                calibrationSession.calibration.originProvenance = .fileMean
            }
            // Full py4DSTEM origin maps use real-space order [R_Nx, R_Ny],
            // matching app [Ry, Rx]. Detector coordinates still need the one
            // documented swap: py4DSTEM qx -> app y, qy -> app x.
            // Read at the SOURCE extent — a file's origin map describes the
            // whole scan, not the loaded crop — and moved into the view's frame
            // by `CalibrationReReference` below. Sizing this against the *view*
            // instead would fail the shape check and drop the origin silently,
            // which is the quiet-failure shape this stage exists to remove.
            if let maps = pc.originMaps,
               let appMaps = maps.appOriginMaps(width: sourceDescriptor.rx,
                                                height: sourceDescriptor.ry) {
                calibrationSession.calibration.origin = appMaps
                if let origin = calibrationSession.calibration.meanOrigin {
                    aperture.centerX = origin.x
                    aperture.centerY = origin.y
                    fileApertureCenter = .init(x: origin.x, y: origin.y)
                }
                calibrationSession.calibration.originProvenance = .fileMaps
            }
        }

        // MOVE THE CALIBRATION INTO THE LOADED FRAME, or lose the values that
        // cannot make the trip — with a named reason for each.
        // Everything above read the file at its SOURCE extent, because that is
        // what the file describes. This is the single point where those values
        // become values *about the view*. At full extent it is the identity, so
        // the shipped path is unchanged; it stops being the identity the moment
        // L5's configurator hands `activate` a real specification.
        // The rules are in `CalibrationReReference`, deliberately not here: they
        // are pure geometry and they are testable without an AppState.
        let reReferenced = CalibrationReReference.apply(
            view, to: calibrationSession.calibration, provenance: calibrationSession.provenance,
            apertureCenter: fileApertureCenter
        )
        calibrationSession.calibration = reReferenced.calibration
        calibrationSession.provenance = reReferenced.provenance
        if let center = reReferenced.apertureCenter {
            aperture.centerX = center.x
            aperture.centerY = center.y
        } else if fileApertureCenter != nil {
            // The beam is not inside the diffraction crop. Fall back to the
            // geometric default rather than leaving the aperture pointed at a
            // detector pixel that is no longer loaded.
            aperture.centerX = Float(view.descriptor.qx) / 2
            aperture.centerY = Float(view.descriptor.qy) / 2
            calibrationSession.calibration.originProvenance = .geometricDefault
        }
        loadedView.publish(
            view: view,
            pushdown: reader.loadPushdown(for: view),
            outcome: reReferenced
        )

        patternDisplayMode = .current
        meanPattern = nil
        maxPattern = nil
        resultPresentation.replaceProduct(nil)
        scanNavigationImage = nil
        scanNavigationVersion = 0
        sessionInventory = .empty
        sessionLoadSpecification = nil
        // The recipe belongs to the session it was built in. A restore of the
        // NEW dataset's sidecar re-adopts its own record two stages later —
        // this only guarantees the previous dataset's recipe cannot leak
        // into it. // v2 S5
        replay.reset()
        // The previous dataset's promote-run summary would be misread under a
        // new dataset. No-op while a run executes — the executor sees the
        // epoch change and halts through `finish`, keeping the keep-awake
        // release on its one path. // v2 S6
        replayRun.clearUnlessRunning()
        // Viewer-level inspection state belongs to the product being inspected,
        // not to the app. Left set, it carried a previous dataset's "show me the
        // fit residual instead" into a fresh file.
        resultPresentation.inspectQualityField = false
        comField = nil
        probeKernel = nil
        learnedDetection.clear()
        // Labels are dataset-scoped (C7 session 4): drop the old, bind to the
        // new, restore from the sidecar if there is one. A restore failure is
        // status-line only, the same non-blocking treatment every other
        // restore below gets — never a modal, never a refusal.
        diskCentreLabels.reset(filePath: descriptor.filePath, datasetPath: descriptor.datasetPath)
        let labelsURL = sessionSidecar.location(for: descriptor)
        let labelsEpoch = datasetSession.epoch
        do {
            if let json = try await Task.detached(priority: .utility, operation: {
                try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: labelsURL)
            }).value, labelsEpoch == datasetSession.epoch {
                if try !diskCentreLabels.restore(
                    from: Data(json.utf8), expecting: descriptor.filePath,
                    frame: DiskCentreLabelStore.frameTag(loadedView.specification),
                    scanY: descriptor.ry, scanX: descriptor.rx, detectorY: descriptor.qy, detectorX: descriptor.qx) {
                    // Not applied: the sidecar keeps them — `restore` flagged the store, so a later save keeps them
                    // too instead of replacing them (review 2026-10-02 a3) — and the line says why (never silent).
                    statusText = diskCentreLabels.importRefusal ?? ""
                }
            }
        } catch {
            if labelsEpoch == datasetSession.epoch {
                diskCentreLabels.noteSidecarLabelsNotRestored()
                statusText = "Could not restore disk-centre labels: \(Self.errorDetail(error))"
            }
        }
        resultPresentation.setBraggVectors(nil)
        completedDiskSummary = nil
        resultPresentation.setBraggPeakCount(nil)
        currentPeaks = []
        currentDiskDiagnostics = nil
        // L3 step 3 — "a real-space crop makes existing scan-indexed results
        // AMBIGUOUS, not stale" — is satisfied here rather than by a second
        // mechanism, and deliberately so. Changing the load specification is a
        // *reopen* (docs/v2-scope.md §6.1), a reopen runs `activate`, and
        // `activate` already clears every scan-indexed product below. What the
        // user needed and did not have is the *reason*, which
        // `loadedView.invalidatedCalibration` now carries. Adding a separate
        // invalidation pass would be a second code path clearing the same state.
        // (Strain cleared earlier, before the calibration reset — see the
        // Gate B finding 3 comment above the `calibration = Calibration()`
        // line.)
        acomSession.resetForDataset(rx: descriptor.rx, ry: descriptor.ry)
        acomSession.lastMeasuredTemplateCount = nil
        acomSession.lastMeasuredBackend = nil
        realSpaceDisplayOrientation = .identity
        realSpaceDisplayMirrored = false
        activePane = .diffraction
        realSpaceShape = .point
        resultPresentation.setVirtualDiffractionPattern(nil)
        realSpaceRadius = Float(max(3, min(descriptor.rx, descriptor.ry) / 12))
        navigation.workspaceArea = .prepare

        // Seeded with the probe radius when the file already carried one (an
        // imported py4DSTEM/EMD calibration), so an import that never runs
        // Origin calibration still gets a probe-scaled minimum spacing. Read
        // after `probeKernel = nil` above, so this cannot pick up the previous
        // dataset's kernel radius.
        diskDetection.diskParams = .detectorAdapted(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: fittedProbeRadius
        )

        if let recovery = pendingRecovery,
           recovery.datasetID == URL(fileURLWithPath: descriptor.filePath).standardizedFileURL.path,
           // The position is applied only when it is honest in THIS view —
           // same frame, inside the extents. The old clamp forced a
           // full-extent position (e.g. persisted after a promote) into a
           // crop-restored view: a defensible pixel the user never chose
           // (S3's carried finding, fixed v2 S5). No position beats a
           // manufactured one.
           let position = recovery.position(
               inViewWith: loadedView.specification,
               rx: descriptor.rx, ry: descriptor.ry
           ) {
            selectedScan = ScanPos(x: position.x, y: position.y)
            // The remembered task is restored, but the WORKSPACE is not: a
            // reopened dataset always lands on Prepare. Dropping the user
            // back into Map or Reconstruct would start them mid-flow, past
            // the step that confirms the dataset and its calibration are
            // what they think — and calibration is per-session state the
            // recovery record does not carry.
            if let mode = AnalysisMode(rawValue: recovery.analysisMode) {
                navigation.analysisMode = mode
            }
        }
        pendingRecovery = nil

        if await unwindLoadIfNeeded(owner: loadOwner) { return }
        beginDatasetLoadingStage("Checking for a saved session…")
        let sessionSnapshot = await loadSessionSnapshot(for: descriptor)
        beginDatasetLoadingStage("Loading first diffraction pattern…")
        await loadCurrentPattern()
        if let sessionSnapshot {
            restoreSessionResult(from: sessionSnapshot, for: descriptor)
        }
        if datasetSession.isLoading {
            // statusText is about to be driven by the measured whole-cube pass;
            // don't flash a finished-looking bar in the performance panel first.
            beginDatasetLoadingStage("Preparing workspace…")
        } else {
            statusText = "Loaded \(descriptor.fileName) at \(descriptor.datasetPath)"
            progress = 1
        }
        if await unwindLoadIfNeeded(owner: loadOwner) { return }
        await buildDatasetPreview()
        if await unwindLoadIfNeeded(owner: loadOwner) { return }
        await preloadResidentCube(keepInMemory: keepInMemory)
        if await unwindLoadIfNeeded(owner: loadOwner) { return }
        // After the cube is settled, before the opening pass. That pass shows
        // only the virtual image (Prepare's own result): restored disks reach
        // the screen when Bragg Disks is entered, not here. The status line is
        // re-asserted after the pass because that analysis (and the load's own
        // stage lines) would otherwise overwrite the one sentence that says
        // what happened to the stored disks.
        let peaksNote = await restoreSessionPeaks(from: sessionSnapshot, for: descriptor)
        if runInitialAnalysis {
            await runOpeningAnalysis()
        }
        if let peaksNote { statusText = peaksNote }
    }

    /// Adopt the peaks a session sidecar stores, when every check passes
    /// (`SessionPeakRestore`); otherwise leave `braggVectors` nil and return
    /// the reason. Returns the status sentence either way, nil when the
    /// sidecar simply holds no peaks. Restores the PRODUCT only: no replay
    /// step is recorded (the sidecar's own record was adopted above and is
    /// what vouched for the peaks) and the learned-detector record is not
    /// touched (`learnedDetection.record` is for a completed run). The read
    /// is off the main actor and epoch-guarded like the calibration restore.
    func restoreSessionPeaks(
        from snapshot: SessionSidecarSnapshot?, for descriptor: DatasetDescriptor
    ) async -> String? {
        guard let snapshot, snapshot.inventory.hasBraggVectors,
              resultPresentation.braggVectors == nil else { return nil }
        if let reason = SessionPeakRestore.refusalBeforeReading(
            viewRecord: snapshot.viewRecord,
            loadedSpecification: loadedView.specification,
            replay: snapshot.replayRecord
        ) { return reason }
        guard let step = SessionPeakRestore.diskStep(in: snapshot.replayRecord) else { return nil }
        let url = sessionSidecar.location(for: descriptor)
        let epoch = datasetSession.epoch
        let grid: BraggVectorEMDWriter.StoredPeakGrid?
        do {
            grid = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadPeakGrid(from: url)
            }.value
        } catch {
            guard epoch == datasetSession.epoch else { return nil }
            return "Stored disks not used — \(Self.errorDetail(error))"
        }
        guard epoch == datasetSession.epoch else { return nil }
        guard let grid else {
            return "Stored disks not used — the session's peak grid could not be read"
        }
        if let reason = SessionPeakRestore.refusal(
            for: grid, scanWidth: descriptor.rx, scanHeight: descriptor.ry,
            detectorWidth: descriptor.qx, detectorHeight: descriptor.qy, step: step
        ) { return reason }
        resultPresentation.setBraggVectors(grid.vectors)
        resultPresentation.setBraggPeakCount(grid.vectors.totalPeakCount)
        // Only on adoption: the controls show what these disks were detected
        // with, so a kernel built later with the same class judges them
        // `.current` until the user changes a control. A refusal returned
        // above and left the controls at the detector defaults.
        if let controls = DiskDetectionRecordMatch.controls(fromStepParameters: step.parameters) {
            diskDetection.diskParams = controls.params
            learnedDetection.detectorClass = controls.detectorClass
            if let threshold = controls.learnedThreshold { learnedDetection.threshold = threshold }
        }
        let detected = step.recorded.formatted(date: .abbreviated, time: .omitted)
        return "Disks restored from the session — \(SystemMonitor.count(grid.vectors.totalPeakCount)) peaks (detected \(detected))"
    }

    /// Sample a cheap preview before the expensive passes, so the open shows
    /// something real early. Bounded by a byte budget rather than a fixed grid,
    /// so the wait is roughly the same on a 64² and a 512² detector.
    /// Failure is not fatal; the status strip records why it was unavailable.
    private func buildDatasetPreview() async {
        guard let fourD = datasetSession.fourD, let d = descriptor, d.is4D else { return }
        let epoch = datasetSession.epoch
        beginDatasetLoadingStage("Sampling a preview…")
        let previewResult = await PendingLoad.makePreview(
            data: fourD, descriptor: d, cancellation: datasetSession.loadCancellation,
            progress: previewProgressHandler(
                rows: DatasetPreviewBuilder.sampledRowCount(for: d), epoch: epoch
            )
        )
        guard datasetSession.epoch == epoch else { return }
        switch previewResult {
        case .success(let preview): datasetSession.publishPreview(preview)
        case .failure(let error):
            if !(error is CancellationError) {
                statusText = "Preview unavailable: \(Self.errorDetail(error))"
            }
        }
    }

    /// Hold the cube in memory when this machine admits it, before the first
    /// whole-cube pass so that pass benefits from it.
    /// Reported in the same two quantities L1 established — patterns and MB —
    /// because on a multi-gigabyte cube this read is the longest single phase
    /// of the whole open. A silent preload would reintroduce the stall L1 just
    /// removed, one layer down (invariant I5). It is a *distinct* phase from
    /// the one L1 wired: L1 routes the first analysis pass, this is the read
    /// into the buffer that happens before it.
    /// Does nothing visible when the cube is not admitted, which today is
    /// always — the shipped default request is `.streamed` (`.automatic` was
    /// dropped, v2 S3), and nothing in the UI requests `.resident` yet.
    private func preloadResidentCube(keepInMemory: Bool = false) async {
        guard let fourD = datasetSession.fourD, let d = descriptor else { return }
        let totalPatterns = d.ry * d.rx
        guard totalPatterns > 0 else { return }
        // The per-open "Keep in memory" switch is the only caller that asks
        // for `.resident`; `preload` stamps the seam's mode, so it is set first.
        if keepInMemory { await residency.request(.resident, on: fourD) }
        let held = await residency.preload(fourD, cancellation: datasetSession.loadCancellation) { [weak self] fraction in
            guard let self, self.datasetSession.isLoading else { return }
            let processed = min(
                totalPatterns, max(0, Int((fraction * Double(totalPatterns)).rounded()))
            )
            self.reportDatasetLoadingProgress(
                fraction,
                SystemMonitor.scanProgressStatus(
                    "Loading into memory", processed: processed,
                    total: totalPatterns, descriptor: d
                )
            )
        }
        // CR1 4a: a cancelled preload is the user's own Cancel, not a failure to hold.
        if keepInMemory, !held, !datasetSession.loadWasCancelled { statusText = "Could not hold the cube in memory; streaming" }
    }

    /// Give the cube's memory back. Streaming resumes on the next pass, with
    /// identical numbers — the parity harness asserts exactly that.
    func releaseResidentCube() async {
        await residency.release(datasetSession.fourD)
    }

    /// The tail every load runs after a step that can notice a cancel: true
    /// means "stop". A load stops when its OWN token is cancelled or the
    /// current one is, but resets the session only while its own load is still
    /// the current one — a superseded load's tail must not discard whatever
    /// load replaced it (S18; the owned cancel token of S5 stopped it clearing
    /// busy, not this).
    /// `orNoDataset` also stops (and resets) when `activate` left nothing
    /// loaded — the failure path that presents its own error.
    func unwindLoadIfNeeded(
        owner: AnalysisCancellationToken?, orNoDataset: Bool = false
    ) async -> Bool {
        let cancelled = (owner?.isCancelled ?? false) || datasetSession.loadWasCancelled
        guard cancelled || (orNoDataset && !hasDataset) else { return false }
        if let owner, datasetSession.loadCancellation === owner {
            await discardPartialLoad()
        }
        return true
    }

    /// Unwind a cancelled open back to the welcome screen.
    /// **The failure mode this is written against is a half-loaded dataset that
    /// LOOKS loaded** — an inspector showing dimensions and a calibration for a
    /// cube whose pixels were never read. That would be worse than having no
    /// cancel at all, because every number computed afterwards would be about
    /// data the app never finished reading.
    /// The invariant that makes it tractable: `hasDataset` is
    /// `descriptor?.is4D == true`, and every workspace view is gated on the
    /// descriptor. So clearing the descriptor is what returns the app to the
    /// welcome screen, and the rest of this is releasing what was already
    /// allocated rather than hiding it.
    /// Internal rather than private **so the invariant can be tested**: the
    /// value of this function is entirely in what it leaves behind, and a test
    /// that could not call it would be testing the button instead of the
    /// property.
    func discardPartialLoad() async {
        if let fourD = datasetSession.fourD { await residency.release(fourD) }
        residency.reset()
        loadedView.reset()
        datasetSession.clearReaderAndArray()
        descriptor = nil
        datasetSession.clearDatasetListAndPreview()
        clearCalibration()
        // A cancelled open must not be remembered — owner decision: you
        // cancelled because it was the wrong file, so promoting it to the
        // top of Recents is precisely backwards. `openFileAsync` also defers
        // `rememberOpenedDataset` until the load has actually finished, so
        // on the normal path there is nothing here to undo.
        if let openURL {
            openURL.stopAccessingSecurityScopedResource()
            self.openURL = nil
        }
        sessionSidecar.release()
        gates.clearSidecarRestoreFailure() // paired with release() // v2 S7
        // The sidecar inventory (Results badge, session tree) describes the
        // dataset just discarded; `openFile` clears it only when the NEXT
        // dataset starts, so without this the sidebar kept its Results badge
        // on the welcome screen.
        sessionInventory = .empty
        sessionLoadSpecification = nil
        datasetSession.advanceEpochAfterDiscard()
        operationCenter.reset()
        statusText = "Load cancelled"
    }

    /// Returns the load's token: pass it to `finishDatasetLoading(owner:)`
    /// so this load's tail can only ever end this load (S5).
    @discardableResult
    func beginDatasetLoading(_ status: String) -> AnalysisCancellationToken {
        let load = datasetSession.beginLoading(status)
        operationCenter.setBusy(true)
        progress = nil
        statusText = status
        return load
    }

    /// A superseded or already-finished load's tail touches nothing — not the
    /// session's loading state, and not the newer load's busy flag.
    func finishDatasetLoading(owner load: AnalysisCancellationToken) {
        guard datasetSession.finishLoading(owner: load) else { return }
        operationCenter.setBusy(false)
        progress = nil
    }

    /// A named phase with no knowable denominator: spinner, no percentage.
    /// Deliberately does **not** fabricate a fraction — see the
    /// `datasetSession.loadingProgress` doc comment.
    private func beginDatasetLoadingStage(_ status: String) {
        guard datasetSession.isLoading else { return }
        datasetSession.beginLoadingStage(status)
        if activeOperation == nil { progress = nil }
        statusText = status
    }

    /// A measured phase: `fraction` must come from work actually completed,
    /// never from an estimate of how far through the open we probably are.
    private func reportDatasetLoadingProgress(_ fraction: Double, _ status: String) {
        guard datasetSession.isLoading else { return }
        let clipped = min(1, max(0, fraction))
        datasetSession.reportLoadingProgress(clipped, status)
        if activeOperation == nil { progress = clipped }
        statusText = status
    }

    private func loadSessionSnapshot(
        for descriptor: DatasetDescriptor
    ) async -> SessionSidecarSnapshot? {
        // D4: a one-shot, identity-stamped skip. Consumed unconditionally so
        // it cannot linger past this open; honored only when it names the
        // dataset actually being opened.
        if let ignored = ignoreSessionForDatasetID {
            ignoreSessionForDatasetID = nil
            if ignored == URL(fileURLWithPath: descriptor.filePath).standardizedFileURL.path {
                statusText = "Opened without the saved session — the sidecar file is untouched"
                return nil
            }
        }
        let url = sessionSidecar.location(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let epoch = datasetSession.epoch
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadSession(from: url)
            }.value
            guard epoch == datasetSession.epoch else { return nil }
            sessionInventory = snapshot.inventory
            // What the sidecar SAYS, not what its absence could be read as:
            // an unrecorded view is not claimed to be the whole file (S18).
            switch snapshot.viewRecord {
            case .recorded(let specification):
                sessionLoadSpecification = specification
            case .unrecorded:
                sessionLoadSpecification = nil
                activityLog.record("This session was saved before sessions recorded their view, so which part of the file it describes is not recorded. Its calibration is used only on a whole-file load; stored disks are not used.")
            }
            // A colleague's recipe becomes this session's starting point
            // (v2 S5), so a later save round-trips it instead of replacing
            // it. Nil (no recorded recipe) leaves the live record alone.
            // The recipe's parameters are expressed in the frame of the
            // sidecar's OWN recorded specification (v2 S6) — not the view
            // being opened, which can legitimately differ after a
            // reconfigure.
            replay.adopt(snapshot.replayRecord, lineage: snapshot.lineage,
                         recordedOn: ReplayParameterFrame.of(snapshot.loadSpecification))
            // A lineage that disagreed with its record was read as v1 (ADR 047
            // R7): say so where the session log is read, not only in the file.
            if let note = snapshot.lineageNote { activityLog.record(note) }
            if let sessionCalibration = snapshot.calibration {
                applySessionCalibration(
                    sessionCalibration,
                    recordedOn: snapshot.viewRecord,
                    for: descriptor
                )
            }
            return snapshot
        } catch {
            guard epoch == datasetSession.epoch else { return nil }
            // The DURABLE channel, not only `statusText` — measured
            // `statusText` set here being overwritten within the same
            // `activate` call (three times, S1). The minimum-reader refusal
            // in particular exists to be READ: without this, a too-new
            // sidecar opens as a dataset with no results and no reason
            // (Gate B-lite F7, v2 S5).
            // The sentence is the one `recordedOutcome` wrote a moment ago (P5c); the raw error is the
            // diagnostic, so it goes to the log and not over the warning.
            let reason = SessionSidecarReadFailure.reason(sidecar: url.lastPathComponent, error: error)
            sessionSidecar.noteUnreadable(reason)
            activityLog.record("\(url.lastPathComponent) could not be read: \(Self.errorDetail(error))")
            statusText = reason
            return nil
        }
    }

    /// Owner decision 2 (2026-09-30 night): the "Fit anyway" caveat survives a
    /// reopen through the lineage the sidecar already carries. The ACTIVE
    /// `calibration_ellipse` node must say `source` "fitAnyway" AND describe the
    /// ellipse this sidecar saved (a, b, theta within a relative 1e-6 of the
    /// SAVED values, before any frame translation) — a node for another ellipse
    /// is not this one's record. Absent lineage (schema 6, a recipe-only save)
    /// reads nothing, and the ellipse stays "From session".
    private func savedEllipseIsFitAnyway(_ saved: PixelCalibration) -> Bool {
        guard let node = replay.lineage.activeNodes().first(where: { $0.kind == "calibration_ellipse" }),
              node.parameters["source"] == "fitAnyway",
              let a = node.parameters["a_px"].flatMap(Double.init), let savedA = saved.ellipseA,
              let b = node.parameters["b_px"].flatMap(Double.init), let savedB = saved.ellipseB,
              let thetaDegrees = node.parameters["theta_deg"].flatMap(Double.init),
              let savedTheta = saved.ellipseTheta else { return false }
        func same(_ x: Double, _ y: Double) -> Bool {
            x.isFinite && y.isFinite && abs(x - y) <= 1e-6 * max(abs(x), abs(y))
        }
        return same(a, savedA) && same(b, savedB) && same(thetaDegrees * .pi / 180, savedTheta)
    }

    private func applySessionCalibration(
        _ saved: PixelCalibration, recordedOn sessionView: SessionViewRecord,
        for descriptor: DatasetDescriptor
    ) {
        // P2 (Gate D): the sidecar's values are in ITS view's frame, not
        // necessarily the one now loaded — adopting them raw let a
        // full-extent session restore onto a 2× binned open put the aperture
        // centre a whole frame off (the corner BF) and feed strain a
        // doubled-frame Q scale. Policy first; geometry, when owed, through
        // the same engine the file path uses (below).
        let framePolicy = SessionCalibrationFramePolicy.decide(
            record: sessionView, loaded: loadedView.specification
        )
        if case .refuse(let reason) = framePolicy {
            loadedView.appendInvalidated([
                CalibrationInvalidation(field: .sessionCalibration, reason: reason)
            ])
            // Name what happened: an older sidecar did not record its view at all (drive, 2026-09-30 night).
            statusText = sessionView == .unrecorded
                ? "Session calibration not adopted — the session did not record which view it was measured on"
                : "Session calibration not adopted — it was recorded on a different view"
            return
        }
        // PHASES 1–2 (P2): pure translation — the sidecar's values into
        // their own frame, then through the engine when the policy says so.
        // Extracted to `SessionCalibrationTranslation` because the unit gate
        // stayed green across a known-flawed intermediate of this very code:
        // the wiring needs its own pins. Running the engine over the MERGED
        // live state instead would re-reference file-carried fields a second
        // time — the double-application caught in this fix's own review.
        guard let translated = SessionCalibrationTranslation.translate(
            saved: saved, policy: framePolicy, view: datasetSession.loadView, descriptor: descriptor
        ) else {
            // Unreachable by construction: a non-identity policy implies a
            // reduced loaded view, which only exists with a live LoadView.
            assertionFailure("reReference policy with no active LoadView")
            return
        }
        let mapped = translated.calibration
        let mappedCenter = translated.center
        let restoredMaps = translated.restoredMaps
        let sessionInvalidated = translated.invalidated
        if !sessionInvalidated.isEmpty {
            loadedView.appendInvalidated(sessionInvalidated)
        }
        // Saved fitted-origin maps that do not fit this frame's scan are named,
        // never applied and never dropped in silence; the mean stands in (S18).
        if let refusal = translated.mapsRefusal {
            loadedView.appendInvalidated([
                CalibrationInvalidation(field: .origin, reason: refusal)
            ])
        }

        // PHASE 3: merge — only the fields the sidecar actually carried, from
        // the mapped snapshot. Validity checks stay on the SAVED values
        // (finiteness and sign are frame-invariant under crop and bin).
        if let value = saved.rSize {
            calibrationSession.calibration.rPixelSize = mapped.rPixelSize
            calibrationSession.provenance.rScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if saved.rUnits != nil { calibrationSession.calibration.rPixelUnits = mapped.rPixelUnits }
        if let value = saved.qSize {
            calibrationSession.calibration.qPixelSize = mapped.qPixelSize
            calibrationSession.provenance.qScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if saved.qUnits != nil { calibrationSession.calibration.qPixelUnits = mapped.qPixelUnits }
        if saved.qrFlip != nil { calibrationSession.calibration.transposeQR = mapped.transposeQR }
        if let value = saved.qrRotationRad {
            calibrationSession.calibration.rotationRad = mapped.rotationRad
            calibrationSession.provenance.rotation = value.isFinite ? .sessionSidecar : nil
        }
        if let value = saved.probeSemiangle,
           !sessionInvalidated.contains(where: { $0.field == .probeRadius }) {
            calibrationSession.calibration.probeRadius = mapped.probeRadius
            calibrationSession.provenance.probe = value.isFinite && value > 0 ? .sessionSidecar : nil
            refreshDiskDefaultsForMeasuredProbe()
        }
        let savedEllipseCount = [saved.ellipseA, saved.ellipseB, saved.ellipseTheta]
            .compactMap { $0 }.count
        if savedEllipseCount > 0,
           !sessionInvalidated.contains(where: { $0.field == .ellipse }) {
            if saved.ellipseA != nil { calibrationSession.calibration.ellipseA = mapped.ellipseA }
            if saved.ellipseB != nil { calibrationSession.calibration.ellipseB = mapped.ellipseB }
            if saved.ellipseTheta != nil { calibrationSession.calibration.ellipseTheta = mapped.ellipseTheta }
            calibrationSession.provenance.ellipse = calibrationSession.calibration.hasEllipse
                ? (savedEllipseCount == 3
                    ? (savedEllipseIsFitAnyway(saved) ? .fitAnyway : .sessionSidecar)
                    : .mixed)
                : nil
        }
        if restoredMaps, mapped.origin != nil {
            calibrationSession.calibration.origin = mapped.origin
            calibrationSession.calibration.originProvenance = .sessionMaps
            if let center = mappedCenter {
                aperture.centerX = center.x
                aperture.centerY = center.y
            }
        }
        // Engine-invalidated maps are already surfaced through
        // `appendInvalidated` above; the live origin is left untouched then.
        if !restoredMaps, saved.qx0Mean != nil, saved.qy0Mean != nil,
           !sessionInvalidated.contains(where: { $0.field == .origin }) {
            calibrationSession.calibration.origin = nil
            calibrationSession.calibration.recordedOriginX = mapped.recordedOriginX
            calibrationSession.calibration.recordedOriginY = mapped.recordedOriginY
            calibrationSession.calibration.originProvenance = .sessionMean
            if let center = mappedCenter {
                aperture.centerX = center.x
                aperture.centerY = center.y
            }
        }
        // No strain-display refresh here, deliberately (Gate B finding 4):
        // this function's only caller chain is `loadSessionSnapshot` ←
        // `activate`, which always runs after `strain.clear()` — a refresh
        // would be an unconditionally guarded no-op. The S4 Change… path
        // never adopts a calibration in-session (it retargets the file and
        // asks for a reopen). If an in-session "adopt calibration" path is
        // ever added, it must refresh the strain display itself — the live
        // sites are `calibrateRotation` and `flipRotation180` (v2 S8).
    }

    private func restoreSessionResult(
        from snapshot: SessionSidecarSnapshot, for descriptor: DatasetDescriptor
    ) {
        let url = sessionSidecar.location(for: descriptor)
        if let map = snapshot.currentResult {
            // A scan-domain map is drawn over THIS scan, so a sidecar saved on a crop of the
            // file must not reopen onto the full view (review H1) — the RGBA branch's rule.
            // Only scan-domain: a detector product (the Bragg vector map, qx × qy) or a
            // reconstruction has its own grid. The domain is resolved exactly as
            // `publishRestoredProduct` will label it.
            let domain = map.provenance["display_domain"].flatMap(ProductDomain.init)
                ?? activeResultDomain
            guard domain != .scan || (map.width == descriptor.rx && map.height == descriptor.ry) else {
                statusText = "Ignored \(url.lastPathComponent): saved scalar map is \(map.width) × \(map.height), expected \(descriptor.rx) × \(descriptor.ry)"
                return
            }
            publishRestoredProduct(   // v2.5 step 3b-6
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                payload: .scalar(FloatImage(width: map.width, height: map.height, pixels: map.pixels)),
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                pixelUnits: map.pixelUnits, provenance: map.provenance)
        } else if let map = snapshot.currentRGBAResult {
            guard map.width == descriptor.rx, map.height == descriptor.ry else {
                statusText = "Ignored \(url.lastPathComponent): saved RGBA map is \(map.width) × \(map.height), expected \(descriptor.rx) × \(descriptor.ry)"
                return
            }
            publishRestoredProduct(   // v2.5 step 3b-6
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                payload: .rgba(RGBAImage(width: map.width, height: map.height, rgba: map.rgba)),
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                pixelUnits: map.pixelUnits, provenance: map.provenance)
        } else {
            return
        }
        resultPresentation.bumpResultVersion()
        statusText = "Restored \(resultPresentation.product?.displayName ?? "result") ← \(url.lastPathComponent)"
    }

    func loadCurrentPattern() async {
        guard descriptor != nil, let fourD = datasetSession.fourD else { return }

        do {
            let epoch = datasetSession.epoch
            let pattern = try await fourD.pattern(ry: selectedScan.y, rx: selectedScan.x)
            guard epoch == datasetSession.epoch else { return }
            currentPattern = pattern
            patternVersion &+= 1
            showReadout(OpeningAnalysis.patternReadout(selectedScan))   // a readout, not an event
            await detectCurrentPattern()
        } catch {
            present(error)
        }
    }


    func clearSupersededFittedOrigin() {
        supersededFittedOrigin = nil
        calibrationSession.parkedRecordedOrigin = nil
        canRestoreFittedOrigin = false
    }

    /// The provenance of the origin a centre drag set aside — the fitted maps', else the
    /// file's recorded centre's — for the origin row's sentence.
    var setAsideOriginProvenance: OriginProvenance? {
        supersededFittedOrigin?.provenance ?? calibrationSession.parkedRecordedOrigin?.provenance
    }

    /// The ONE path that resets the calibration — activation, a cancelled load,
    /// Prepare's Clear Calibration; a reset spelled out elsewhere is the mistake
    /// this prevents (v2 S13). NOT `datasetSession.epoch` (the cube is unchanged) and not
    /// the strain/phase maps, which are left to rerun — but it DOES discard the
    /// orientation map, parallax and the ptychography reconstruction (whose Å
    /// sampling came from this calibration), and the confirmation dialog says so.
    func clearCalibration() {
        calibrationSession.clear()
        qCalibration.clear()
        clearSupersededFittedOrigin()
        phaseContrast.parallaxPreprocess = nil; phaseContrast.parallaxAlignment = nil
        phaseContrast.singleslicePtychography = nil
        // What is shown goes too: a computed parallax or ptychography image
        // keeps the Å sampling of the calibration being cleared (a saved one
        // shown from the sidecar is its file's record, and stays).
        if let shown = resultPresentation.product, shown.origin == .computed,
           shown.kind.hasPrefix("parallax_") || shown.kind.hasPrefix("ptychography_") {
            resultPresentation.replaceProduct(nil)
            resultPresentation.bumpResultVersion()
        }
        rederiveDisplayedDPCForScaleChange()   // its Q, R and rotation just went
        acomSession.invalidateResult()
    }

    /// Undo a manual center: reinstate the fitted maps it set aside (with their original
    /// provenance) and the file's recorded centre it parked, and recenter the aperture on
    /// them. Either may be absent — a file with only a recorded mean has no maps.
    func restoreFittedOrigin() {
        let superseded = supersededFittedOrigin
        let parked = calibrationSession.parkedRecordedOrigin
        guard superseded != nil || parked != nil else { return }
        clearSupersededFittedOrigin()
        if let superseded {
            calibrationSession.calibration.origin = superseded.maps
            calibrationSession.calibration.originProvenance = superseded.provenance
        }
        if let parked {
            calibrationSession.calibration.recordedOriginX = parked.x
            calibrationSession.calibration.recordedOriginY = parked.y
            if superseded == nil { calibrationSession.calibration.originProvenance = parked.provenance }
        }
        if let mean = calibrationSession.calibration.meanOrigin {
            aperture.centerX = mean.x
            aperture.centerY = mean.y
        } else if let parked {
            aperture.centerX = parked.x
            aperture.centerY = parked.y
        }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        let restored = superseded?.provenance ?? parked?.provenance
        statusText = "Fitted origin restored — \(restored?.displayName ?? "origin")"
        // The set-aside recorded a lineage node only for fitted maps (`recordOriginSetAsideRun`).
        if let superseded { recordOriginRestoredRun(fitParameters: superseded.lineage) }
        scheduleLiveVirtualDetector()
    }

    /// Live aperture edit during a drag: store, then recompute the real-space
    /// image continuously (coalesced, quiet — no status/busy churn).
    func updateAperture(_ newAperture: Aperture) {
        activePane = .diffraction
        if newAperture.centerX != aperture.centerX || newAperture.centerY != aperture.centerY {
            // A manual center supersedes fitted per-position maps. Retaining
            // those maps inside `calibration` would make export silently
            // ignore the manual value — so they move to the recoverable
            // superseded slot instead of being destroyed.
            if let displaced = calibrationSession.calibration.origin {
                let fitLineage = replay.lineage.activeNodes()
                    .first { $0.kind == "calibration_origin" }?.parameters
                supersededFittedOrigin = (displaced, calibrationSession.calibration.originProvenance, fitLineage)
                canRestoreFittedOrigin = true
                statusText = "Manual aperture center — fitted origin set aside (Restore Fitted Origin in Calibration undoes this)"
                recordOriginSetAsideRun()
            }
            calibrationSession.calibration.origin = nil
            // The file's recorded mean leaves the live calibration with them (Gate B): v2 S13
            // gave that value a home of its own but did not clear it here, so
            // `referenceOrigin` kept returning `.recordedMean` — the FILE's
            // number — while `originProvenance` read `.manual`, and the CoM
            // field and the measured probe kernel silently stopped using the
            // centre the user had just dragged to. It is PARKED, not destroyed
            // (owner, ADR 050 card A1): Restore returns it. Read before
            // `originProvenance` is overwritten below.
            if let x = calibrationSession.calibration.recordedOriginX,
               let y = calibrationSession.calibration.recordedOriginY {
                calibrationSession.parkedRecordedOrigin = .init(
                    x: x, y: y, provenance: calibrationSession.calibration.originProvenance)
                canRestoreFittedOrigin = true
                if supersededFittedOrigin == nil {
                    statusText = "Manual aperture center — the file's recorded center set aside (Restore Fitted Origin in Calibration undoes this)"
                }
            }
            calibrationSession.calibration.recordedOriginX = nil
            calibrationSession.calibration.recordedOriginY = nil
            calibrationSession.calibration.originProvenance = .manual
            phaseContrast.parallaxPreprocess = nil
            phaseContrast.parallaxAlignment = nil
        }
        aperture = newAperture
        scheduleLiveVirtualDetector()
    }

    var manualQPixelUnits: String {
        CalibrationUnitConversion.canonicalEditableReciprocalUnit(
            calibrationSession.calibration.qPixelUnits
        ) ?? "nm⁻¹"
    }

    /// Do not place an imported `1 pixels/px` placeholder beside the manual
    /// physical-unit picker. Until the user supplies a physical unit/value,
    /// the action field is intentionally empty (it shows "Not set").
    var manualQPixelSize: Double? {
        guard CalibrationUnitConversion.canonicalEditableReciprocalUnit(
            calibrationSession.calibration.qPixelUnits
        ) != nil else { return nil }
        return calibrationSession.calibration.qPixelSize
    }

    var manualRPixelUnits: String {
        CalibrationUnitConversion.canonicalEditableRealUnit(
            calibrationSession.calibration.rPixelUnits
        ) ?? "nm"
    }

    var manualRPixelSize: Double? {
        guard CalibrationUnitConversion.canonicalEditableRealUnit(
            calibrationSession.calibration.rPixelUnits
        ) != nil else { return nil }
        return calibrationSession.calibration.rPixelSize
    }

    /// Only the manual Q/R fields call this (`CalibrationReadinessRow`), through
    /// `NumberEntryField`, whose `resolve` never commits the text a field shows
    /// for the value in effect — so a Return or blur on an untouched "0,1904"
    /// (restored from the session) does not arrive here, and no unchanged-value
    /// guard is needed (P1, 2026-10-04: it replaced a 5e-7 tolerance here).
    func setManualQPixelSize(_ value: Double) {
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibrationSession.calibration.qPixelSize = value
            // A manual number is entered beside a physical-unit picker. If the
            // file only supplied `pixels`, replace that index placeholder with
            // the picker's visible default instead of retaining pixels/px.
            calibrationSession.calibration.qPixelUnits = manualQPixelUnits
            calibrationSession.provenance.qScale = .manual
            acomSession.invalidateResult()
            recordQCalibrationRun()   // lineage node (ADR 047)
        } else {
            calibrationSession.calibration.qPixelSize = nil
            calibrationSession.provenance.qScale = nil
            acomSession.invalidateResult()
        }
        rederiveDisplayedDPCForScaleChange()
    }

    func setManualQPixelUnits(_ units: String) {
        guard let canonical =
                CalibrationUnitConversion.canonicalEditableReciprocalUnit(units)
        else { return }
        // Same unit, however the file spelled it ("A^-1" from py4DSTEM files is Å⁻¹): CR1 item 3, CR2 item A.
        if CalibrationUnitConversion.canonicalEditableReciprocalUnit(calibrationSession.calibration.qPixelUnits) == canonical { return }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        calibrationSession.calibration.qPixelUnits = canonical
        if calibrationSession.calibration.qPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.qScale = .manual
            // A unit change is a scale change (nm⁻¹ → Å⁻¹ is 10× the Q every
            // phase-map tolerance reads); the lineage judges staleness by the
            // active `calibration_q` node, so it gets one here as the size
            // setter gives it (review 2026-09-30 row 2).
            recordQCalibrationRun()   // lineage node (ADR 047)
        }
        acomSession.invalidateResult()
        rederiveDisplayedDPCForScaleChange()
    }

    func setManualRPixelSize(_ value: Double) {
        let before = calibrationSession.calibration
        defer { resampleDisplayedProductForRChange(oldSize: before.rPixelSize, oldUnits: before.rPixelUnits) }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibrationSession.calibration.rPixelSize = value
            calibrationSession.calibration.rPixelUnits = manualRPixelUnits
            calibrationSession.provenance.rScale = .manual
        } else {
            calibrationSession.calibration.rPixelSize = nil
            calibrationSession.provenance.rScale = nil
        }
        rederiveDisplayedDPCForScaleChange()   // physical iDPC integrates with R
    }

    func setManualRPixelUnits(_ units: String) {
        guard let canonical = CalibrationUnitConversion.canonicalEditableRealUnit(units)
        else { return }
        let before = calibrationSession.calibration
        defer { resampleDisplayedProductForRChange(oldSize: before.rPixelSize, oldUnits: before.rPixelUnits) }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        calibrationSession.calibration.rPixelUnits = canonical
        if calibrationSession.calibration.rPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.rScale = .manual
        }
        rederiveDisplayedDPCForScaleChange()
    }

    func setManualAcceleratingVoltage(_ value: Double) {
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        let previous = calibrationSession.acceleratingVoltage
        calibrationSession.acceleratingVoltage = value.isFinite && value > 0 ? value : nil
        // The orientation plan is generated with this voltage's wavelength
        // (`generateOrientationPlan`: Ewald curvature of every template), so a
        // different voltage needs a new plan, not just a new match — and that
        // covers the mrad-scale case too (review 2026-09-30 row 5). A
        // same-value commit keeps both, as the Q/R fields do.
        if calibrationSession.acceleratingVoltage != previous {
            acomSession.invalidatePlan()
        }
        rederiveDisplayedDPCForScaleChange()
    }


    /// Boolean scan mask sharing the point/rectangle/circle semantics of the
    /// visible real-space ROI. Used as the unstrained strain reference.
    /// Derived from the same DetectorShape as virtual diffraction so both
    /// consumers select the identical pixel set (the previous hand-written
    /// circle predicate diverged from the ROI by half a pixel).
    func realSpaceRegionMask(_ d: DatasetDescriptor) -> [Bool] {
        let shape = DetectorShape.realSpaceRegion(
            shape: realSpaceShape, radius: realSpaceRadius, scanX: selectedScan.x, scanY: selectedScan.y)
        return VirtualDetector.makeMask(shape: shape, qy: d.ry, qx: d.rx).map { $0 != 0 }
    }



}
