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
    func openFileForConfiguration(url: URL) {
        Task {
            beginDatasetLoading("Opening \(url.lastPathComponent)…")
            defer { if datasetSession.isLoading { finishDatasetLoading() } }
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
                case .success(let preview): pending.preview = preview
                case .failure(let error):
                    if error is CancellationError {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                        return
                    }
                    pending.previewFailure = Self.errorDetail(error)
                    statusText = "Preview unavailable: \(Self.errorDetail(error))"
                }
                pending.fetchDefaultSingleDP()
                if let displaced = promotionRun.replace(with: pending) {
                    displaced.cancelSingleDPFetch()
                    if displaced.accessedSecurityScope {
                        displaced.url.stopAccessingSecurityScopedResource()
                    }
                }
                finishDatasetLoading()
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
    func importCrystalModel(from url: URL) {
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
        } catch {
            present(error)
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
        beginDatasetLoading("Opening demo dataset…")
        defer {
            if datasetSession.isLoading { finishDatasetLoading() }
        }
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
            finishDatasetLoading()
            acomSession.display = .ipfZ
            // Keep this string's step names in sync with the current
            // workspace titles — it is data, not a UI label, so a rename
            // elsewhere will not catch a stale name here.
            statusText = "Demo ready — follow Prepare → Imaging → Strain & ACOM (Bragg disks first) → Results; each task lists anything it still needs"
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
                beginDatasetLoading("Opening \(descriptor.datasetPath)…")
                await activate(descriptor: descriptor, reader: h5)
                finishDatasetLoading()
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

    func openFileAsync(url: URL) async {
        beginDatasetLoading("Opening \(url.lastPathComponent)…")
        errorMessage = nil
        defer {
            if datasetSession.isLoading { finishDatasetLoading() }
        }

        let previousOpenURL = openURL
        let accessed = url.startAccessingSecurityScopedResource()

        do {
            let reader = try await Self.makeReader(for: url)
            beginDatasetLoadingStage("Reading file structure of \(url.lastPathComponent)…")
            let descriptor = try await reader.discoverPrimaryDataset()
            if datasetSession.loadWasCancelled {
                if accessed { url.stopAccessingSecurityScopedResource() }
                await discardPartialLoad()
                finishDatasetLoading()
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
            if datasetSession.loadWasCancelled || !hasDataset {
                // `activate` unwinds itself on cancellation; this catches the
                // case where it did, and stops the open continuing into an
                // analysis of a dataset that is no longer there.
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            // The first whole-cube pass IS part of opening, from the user's
            // point of view: the welcome card is still on screen and the
            // workspace has no image yet. Finishing the load before it ran was
            // what left the bar parked at its last stage and then vanishing
            // into a generic operation indicator.
            await runCurrentAnalysis()
            if datasetSession.loadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            // REMEMBERED ONLY ONCE THE LOAD HAS ACTUALLY FINISHED. Moved here
            // from before the whole-cube pass so that a cancel at any point
            // leaves Recents untouched — a cancelled file is one you did not
            // want, and putting it at the top of the list is backwards.
            rememberOpenedDataset(url)
            finishDatasetLoading()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            present(error)
        }
    }

    func activate(
        descriptor sourceDescriptor: DatasetDescriptor,
        reader: any FourDDataSource,
        specification: LoadSpecification = .fullExtent,
        runInitialAnalysis: Bool = true
    ) async {
        guard sourceDescriptor.is4D else {
            present(H5Error.unsupportedRank(sourceDescriptor.shape.count))
            return
        }

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
        selectedScan = ScanPos(x: 0, y: 0)
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
            outer: Float(min(descriptor.qx, descriptor.qy)) / 4
        )
        if let rawVoltage = await reader.readDoubleAttribute(
            "accelerating_voltage", onObjectPath: "/"
        ) {
            // py4DSTEM metadata commonly stores eV while microscope UI and
            // DM tags may expose kV. Keep one app convention: kV.
            calibrationSession.acceleratingVoltage = rawVoltage > 1_000 ? rawVoltage / 1_000 : rawVoltage
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
            calibrationSession.calibration.rotationRad = pc.qrRotationRad.map(Float.init)
            calibrationSession.calibration.probeRadius = pc.probeSemiangle.map(Float.init)
            calibrationSession.calibration.ellipseA = pc.ellipseA
            calibrationSession.calibration.ellipseB = pc.ellipseB
            calibrationSession.calibration.ellipseTheta = pc.ellipseTheta
            if calibrationSession.calibration.hasRotation { calibrationSession.provenance.rotation = .importedFile }
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
            apertureCenter: .init(x: aperture.centerX, y: aperture.centerY)
        )
        calibrationSession.calibration = reReferenced.calibration
        calibrationSession.provenance = reReferenced.provenance
        if let center = reReferenced.apertureCenter {
            aperture.centerX = center.x
            aperture.centerY = center.y
        } else {
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
                try diskCentreLabels.load(from: Data(json.utf8), expecting: descriptor.filePath)
            }
        } catch {
            if labelsEpoch == datasetSession.epoch {
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

        if datasetSession.loadWasCancelled { await discardPartialLoad(); return }
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
        if datasetSession.loadWasCancelled { await discardPartialLoad(); return }
        await buildDatasetPreview()
        if datasetSession.loadWasCancelled { await discardPartialLoad(); return }
        await preloadResidentCube()
        if datasetSession.loadWasCancelled { await discardPartialLoad(); return }
        if runInitialAnalysis {
            await runCurrentAnalysis()
        }
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
    private func preloadResidentCube() async {
        guard let fourD = datasetSession.fourD, let d = descriptor else { return }
        let totalPatterns = d.ry * d.rx
        guard totalPatterns > 0 else { return }
        await residency.preload(fourD, cancellation: datasetSession.loadCancellation) { [weak self] fraction in
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
    }

    /// Give the cube's memory back. Streaming resumes on the next pass, with
    /// identical numbers — the parity harness asserts exactly that.
    func releaseResidentCube() async {
        await residency.release(datasetSession.fourD)
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
        datasetSession.advanceEpochAfterDiscard()
        operationCenter.reset()
        statusText = "Load cancelled"
    }

    func beginDatasetLoading(_ status: String) {
        datasetSession.beginLoading(status)
        operationCenter.setBusy(true)
        progress = nil
        statusText = status
    }

    func finishDatasetLoading() {
        datasetSession.finishLoading()
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
            sessionLoadSpecification = snapshot.loadSpecification ?? .fullExtent
            // A colleague's recipe becomes this session's starting point
            // (v2 S5), so a later save round-trips it instead of replacing
            // it. Nil (no recorded recipe) leaves the live record alone.
            // The recipe's parameters are expressed in the frame of the
            // sidecar's OWN recorded specification (v2 S6) — not the view
            // being opened, which can legitimately differ after a
            // reconfigure.
            replay.adopt(snapshot.replayRecord,
                         recordedOn: ReplayParameterFrame.of(snapshot.loadSpecification))
            if let sessionCalibration = snapshot.calibration {
                applySessionCalibration(
                    sessionCalibration,
                    recordedOn: snapshot.loadSpecification ?? .fullExtent,
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
            sessionSidecar.noteUnreadable(
                "Could not restore \(url.lastPathComponent): \(Self.errorDetail(error))"
            )
            statusText = "Could not restore \(url.lastPathComponent): \(Self.errorDetail(error))"
            return nil
        }
    }

    private func applySessionCalibration(
        _ saved: PixelCalibration, recordedOn sessionSpecification: LoadSpecification,
        for descriptor: DatasetDescriptor
    ) {
        // P2 (Gate D): the sidecar's values are in ITS view's frame, not
        // necessarily the one now loaded — adopting them raw let a
        // full-extent session restore onto a 2× binned open put the aperture
        // centre a whole frame off (the corner BF) and feed strain a
        // doubled-frame Q scale. Policy first; geometry, when owed, through
        // the same engine the file path uses (below).
        let framePolicy = SessionCalibrationFramePolicy.decide(
            session: sessionSpecification, loaded: loadedView.specification
        )
        if case .refuse(let reason) = framePolicy {
            loadedView.appendInvalidated([
                CalibrationInvalidation(field: .sessionCalibration, reason: reason)
            ])
            statusText = "Session calibration not adopted — it was recorded on a different view"
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
                ? (savedEllipseCount == 3 ? .sessionSidecar : .mixed)
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
            showReadout("Pattern x \(selectedScan.x), y \(selectedScan.y)")   // a readout, not an event
            await detectCurrentPattern()
        } catch {
            present(error)
        }
    }


    func clearSupersededFittedOrigin() {
        supersededFittedOrigin = nil
        canRestoreFittedOrigin = false
    }

    /// The ONE path that resets the calibration — activation, a cancelled load,
    /// Prepare's Clear Calibration; a reset spelled out elsewhere is the mistake
    /// this prevents (v2 S13). NOT `datasetSession.epoch` (the cube is unchanged) and not
    /// the strain/phase maps, which are left to rerun — but it DOES discard the
    /// orientation map and parallax, and the confirmation dialog says so.
    func clearCalibration() {
        calibrationSession.clear()
        qCalibration.clear()
        clearSupersededFittedOrigin()
        phaseContrast.parallaxPreprocess = nil; phaseContrast.parallaxAlignment = nil
        acomSession.invalidateResult()
    }

    /// Undo a manual center that displaced fitted origin maps: reinstate the
    /// maps with their original provenance and recenter the aperture on
    /// their mean.
    func restoreFittedOrigin() {
        guard let superseded = supersededFittedOrigin else { return }
        clearSupersededFittedOrigin()
        calibrationSession.calibration.origin = superseded.maps
        calibrationSession.calibration.originProvenance = superseded.provenance
        if let mean = calibrationSession.calibration.meanOrigin {
            aperture.centerX = mean.x
            aperture.centerY = mean.y
        }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        statusText = "Fitted origin restored — \(superseded.provenance.displayName)"
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
                supersededFittedOrigin = (displaced, calibrationSession.calibration.originProvenance)
                canRestoreFittedOrigin = true
                statusText = "Manual aperture center — fitted origin set aside (Restore Fitted Origin in Calibration undoes this)"
            }
            calibrationSession.calibration.origin = nil
            // The file's recorded mean goes with them (Gate B): v2 S13 gave
            // that value a home of its own but did not clear it here, so
            // `referenceOrigin` kept returning `.recordedMean` — the FILE's
            // number — while `originProvenance` read `.manual`, and the CoM
            // field and the measured probe kernel silently stopped using the
            // centre the user had just dragged to. Discarding it here
            // restores the pre-S13 semantics (the aperture was the only
            // carrier then); it is not recoverable through
            // `supersededFittedOrigin`, which holds maps only.
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
    /// the action field is intentionally empty (rendered as zero by SwiftUI).
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
        } else {
            calibrationSession.calibration.qPixelSize = nil
            calibrationSession.provenance.qScale = nil
            acomSession.invalidateResult()
        }
    }

    func setManualQPixelUnits(_ units: String) {
        guard let canonical =
                CalibrationUnitConversion.canonicalEditableReciprocalUnit(units)
        else { return }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        calibrationSession.calibration.qPixelUnits = canonical
        if calibrationSession.calibration.qPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.qScale = .manual
        }
        acomSession.invalidateResult()
    }

    func setManualRPixelSize(_ value: Double) {
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
    }

    func setManualRPixelUnits(_ units: String) {
        guard let canonical = CalibrationUnitConversion.canonicalEditableRealUnit(units)
        else { return }
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        calibrationSession.calibration.rPixelUnits = canonical
        if calibrationSession.calibration.rPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.rScale = .manual
        }
    }

    func setManualAcceleratingVoltage(_ value: Double) {
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        calibrationSession.acceleratingVoltage = value.isFinite && value > 0 ? value : nil
        if CalibrationUnitConversion.normalized(calibrationSession.calibration.qPixelUnits) == "mrad" {
            acomSession.invalidateResult()
        }
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
