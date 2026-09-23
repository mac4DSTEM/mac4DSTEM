//
//  AppState+DiskDetection.swift
//  Role: the disk-detection orchestration — probe-kernel generation, the
//        live overlay, the full-scan run, the Bragg vector map, the
//        classical/neural-net disagreement map, and the one calibrated-
//        Bragg-vectors derivation strain/ACOM/the Bragg map all share.
//        Moved verbatim out of AppState.swift on 2026-09-18 (seam 3,
//        docs/archive/v4/appstate-seams-plan.md): a placement change, no logic touched.
//        `diskParams` moved into `Session/DiskDetectionProduct.swift` in the
//        same seam — the two reads of it here are renamed to
//        `diskDetection.diskParams`; everything else (`probeKernel`,
//        `currentPeaks`, `currentDiskDiagnostics`, `resultPresentation.braggVectors`,
//        `resultPresentation.braggPeakCount`, `completedDiskSummary`, `liveDetectionRequest`)
//        stays AppState's per the plan and keeps its pre-seam name — three of
//        those (`currentDiskDiagnostics`, `resultPresentation.braggVectors`,
//        `completedDiskSummary`) widen from `private(set)` to a plain `var`
//        so this file can set them, and `liveDetectionRequest` and
//        `Self.makeReader` widen from `private` to `internal` for the same
//        reason (4 widenings total for this seam).
//        `liveDetectionInFlight`/`liveDetectionPending` — the single-flight
//        coalescing flags `detectCurrentPattern`/`performLiveDetection` use
//        — cannot follow as AppState stored properties (an extension can't
//        declare them) and are not named as staying by the plan, so they
//        moved to `diskDetection` instead of widening; see that file's
//        header.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    // MARK: - Disk detection

    /// Runs origin calibration if the radius is unknown; nil on failure.
    /// Shared by the two generators below that need a calibrated radius.
    private func ensureProbeRadius() async -> Float? {
        if calibrationSession.calibration.probeRadius == nil { await calibrateOrigin() }
        return calibrationSession.calibration.probeRadius
    }

    /// Build the synthetic probe kernel from the calibrated probe radius,
    /// running origin calibration first if needed.
    func generateProbeKernel() async {
        guard let descriptor else { return }
        guard let radius = await ensureProbeRadius() else { return }

        guard let kernel = ProbeKernel.synthetic(radius: radius, qy: descriptor.qy, qx: descriptor.qx) else {
            presentComputeFailure(SimpleError("Could not build a probe kernel (radius \(radius) px)."))
            return
        }
        probeKernel = kernel
        // The learned path needs the full probe IMAGE; draw one (no measured pattern here).
        let origin = calibrationSession.calibration.referenceOrigin(
            detectorQX: descriptor.qx, detectorQY: descriptor.qy, apertureCentre: (x: aperture.centerX, y: aperture.centerY)).point
        learnedDetection.probeReference = .init(
            pattern: LearnedDetectionSession.syntheticProbe(qy: descriptor.qy, qx: descriptor.qx, centre: (x: origin.x, y: origin.y), radius: radius),
            centreX: origin.x, centreY: origin.y, radius: radius, source: .synthetic)
        statusText = String(format: "Probe kernel ✓  r = %.1f px, trench %.0f–%.0f px",
                            radius, kernel.trenchRadii.inner, kernel.trenchRadii.outer)
        await detectCurrentPattern()
    }

    /// Build a measured kernel from the CBED currently displayed. With a
    /// rectangle/circle real-space ROI this is its summed vacuum pattern;
    /// normalization makes sum versus mean immaterial.
    func generateMeasuredProbeKernel(mode: ProbeKernelMode = .sigmoidTrench) async {
        guard let d = descriptor, let pattern = displayedPattern else { return }
        guard let radius = await ensureProbeRadius() else { return }
        let origin = calibrationSession.calibration.referenceOrigin(  // v2 S13: one derivation
            detectorQX: d.qx, detectorQY: d.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
        guard let kernel = ProbeKernel.measured(
            pattern: pattern, originX: origin.x, originY: origin.y, radius: radius, mode: mode
        ) else {
            presentComputeFailure(SimpleError("The current CBED/ROI did not contain a usable measured probe."))
            return
        }
        probeKernel = kernel
        learnedDetection.probeReference = .init(pattern: pattern, centreX: origin.x, centreY: origin.y, radius: radius, source: .measured)
        statusText = String(
            format: "Measured probe kernel ✓  r = %.1f px from current CBED/ROI, %@", radius,
            mode.rawValue.lowercased()
        )
        await detectCurrentPattern()
    }

    /// Build the kernel from a probe image the FILE carries (py4DSTEM's
    /// `probe` / `probe_template`), the way the bullseye tutorial does. The
    /// probe's own centre and radius come from the probe-size estimator on
    /// that image, as `get_probe_kernel_flat` does with `origin=None`. The
    /// first candidate on the detector grid is used; the status names it.
    func generateFileProbeKernel(mode: ProbeKernelMode = .flat) async {
        guard let descriptor, let reader = datasetSession.reader else { return }
        let candidates: [ProbeCandidate]
        do {
            candidates = try await reader.probeCandidates(detectorQY: descriptor.qy, detectorQX: descriptor.qx)
        } catch {
            presentComputeFailure(error)
            return
        }
        guard let candidate = candidates.first else {
            presentComputeFailure(SimpleError("This file carries no probe image on the \(descriptor.qx) × \(descriptor.qy) detector grid — use a vacuum CBED / ROI instead."))
            return
        }
        let pattern: DiffractionPattern
        do {
            pattern = DiffractionPattern(qy: candidate.qy, qx: candidate.qx, pixels: try await reader.readProbe(candidate))
        } catch {
            presentComputeFailure(error)
            return
        }
        guard let size = OriginCalibration.probeSize(dp: pattern.pixels, qy: pattern.qy, qx: pattern.qx) else {
            presentComputeFailure(SimpleError("The probe image at \(candidate.path) has no measurable disk."))
            return
        }
        guard let kernel = ProbeKernel.measured(
            pattern: pattern, originX: size.x0, originY: size.y0, radius: size.r,
            mode: mode, source: .fileProbe, probePath: candidate.path
        ) else {
            presentComputeFailure(SimpleError("The probe image at \(candidate.path) did not yield a usable kernel."))
            return
        }
        probeKernel = kernel
        learnedDetection.probeReference = .init(pattern: pattern, centreX: size.x0, centreY: size.y0, radius: size.r, source: .fileProbe)
        let others = candidates.count > 1 ? " (\(candidates.count - 1) more in the file)" : ""
        statusText = String(
            format: "File probe kernel ✓  r = %.1f px, %@, from %@%@", size.r,
            mode.rawValue.lowercased(), candidate.path, others
        )
        await detectCurrentPattern()
    }

    /// Build the kernel from a SEPARATE vacuum scan file — the fix for a sample
    /// with no vacuum region in frame (the MgO disk-radius finding). The vacuum
    /// scan's mean pattern is the probe; `OriginCalibration.vacuumProbeKernel`
    /// refuses if its detector differs from the loaded dataset's. // v3.1
    func generateVacuumProbeKernel(fromScan url: URL, mode: ProbeKernelMode = .flat) async {
        guard let descriptor else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let reader = try await Self.makeReader(for: url)
            let vacuumDescriptor = try await reader.discoverPrimaryDataset()
            let vacuumData = FourDArray(reader: reader, descriptor: vacuumDescriptor)
            let result = try await OriginCalibration.vacuumProbeKernel(
                vacuum: vacuumData, vacuumDescriptor: vacuumDescriptor,
                targetDescriptor: descriptor, mode: mode, probePath: url.lastPathComponent
            )
            probeKernel = result.kernel
            let pattern = DiffractionPattern(qy: vacuumDescriptor.qy, qx: vacuumDescriptor.qx,
                                             pixels: result.meanDP)
            learnedDetection.probeReference = .init(
                pattern: pattern, centreX: result.centreX, centreY: result.centreY,
                radius: result.radius, source: .vacuumScan)
            statusText = String(format: "Vacuum probe kernel ✓  r = %.1f px from %@, %@",
                                result.radius, url.lastPathComponent, mode.rawValue.lowercased())
            await detectCurrentPattern()
        } catch {
            presentComputeFailure(error)
        }
    }

    /// Live overlay: detect disks in the currently displayed pattern only.
    /// Same coalescing contract as the live virtual-detector drag: at most one
    /// detection in flight; parameter changes during a slider drag mark work
    /// pending instead of piling up detached detections that only get
    /// discarded by the request counter after running to completion. The two
    /// flags live on `diskDetection` (an extension cannot hold stored state).
    func detectCurrentPattern() async {
        if diskDetection.liveDetectionInFlight {
            diskDetection.liveDetectionPending = true
            return
        }
        diskDetection.liveDetectionInFlight = true
        await performLiveDetection()
        diskDetection.liveDetectionInFlight = false
        if diskDetection.liveDetectionPending {
            diskDetection.liveDetectionPending = false
            Task { await detectCurrentPattern() }
        }
    }

    /// One live-detection pass over the latest displayed pattern/parameters.
    private func performLiveDetection() async {
        liveDetectionRequest &+= 1
        let request = liveDetectionRequest
        guard navigation.analysisMode == .disks, let kernel = probeKernel,
              let pattern = displayedPattern else {
            if !currentPeaks.isEmpty { currentPeaks = [] }
            currentDiskDiagnostics = nil
            return
        }
        let params = diskDetection.diskParams
        let context = DiskDetectionContext(
            qy: pattern.qy, qx: pattern.qx, probeRadius: kernel.probeRadius
        )
        guard !params.validationIssues(in: context).contains(where: {
            $0.severity == .error
        }) else {
            currentPeaks = []
            currentDiskDiagnostics = nil
            return
        }
        let epoch = datasetSession.epoch
        // Detector-picker overlay: the net's own candidates are the rings (no classical funnel).
        if let peaks = await learnedDetection.livePeaks(pattern: pattern, params: params) {
            guard epoch == datasetSession.epoch, request == liveDetectionRequest,
                  navigation.analysisMode == .disks else { return }
            currentPeaks = peaks; currentDiskDiagnostics = nil
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            () -> DiskDetectionPatternResult? in
            guard let detector = DiskDetector(kernel: kernel) else { return nil }
            return detector.detectWithDiagnostics(
                pattern: pattern.pixels, params: params
            )
        }.value
        guard epoch == datasetSession.epoch,
              request == liveDetectionRequest,
              navigation.analysisMode == .disks else { return }
        currentPeaks = result?.peaks ?? []
        currentDiskDiagnostics = result?.diagnostics
    }

    /// Full-scan detection → BraggVectors + Bragg vector map.
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runDiskDetection(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let fourD = datasetSession.fourD, let descriptor else { return .failed("No dataset is loaded") }
        if probeKernel == nil { await generateProbeKernel() }
        guard let kernel = probeKernel else {
            return .failed("No probe kernel could be generated")
        }

        let params = diskDetection.diskParams
        let context = DiskDetectionContext(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: kernel.probeRadius
        )
        let errors = params.validationIssues(in: context).filter {
            $0.severity == .error
        }
        guard errors.isEmpty else {
            let reason = "Disk-detection settings are invalid: "
                + errors.map(\.message).joined(separator: " ")
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }

        // Prepare the learned asset (first use only) before the cancellable operation begins.
        let detectorClass = learnedDetection.detectorClass
        let statusPrefix = detectorClass == .learned ? "Detecting Bragg disks (neural net)…" : "Detecting Bragg disks…"
        var preparedLearned: LearnedDiskDetector?
        if detectorClass == .learned {
            statusText = "Preparing the neural-net detector…"
            switch await learnedDetection.prepareForRun() {
            case .failure(let reason): presentComputeFailure(SimpleError(reason)); return .failed(reason)
            case .success(let loaded): preparedLearned = loaded
            }
        }

        let cancellation = beginCancellableOperation(
            "Disk detection", status: statusPrefix, totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        // `detectAll` now throws a `FullScanError` naming what failed and
        // where; nil means cancelled and nothing else. The previous contract
        // returned nil for everything, and the guard below then attributed a
        // NAS tile-read failure to "its FFT plan" — the error-attribution
        // defect this session exists to fix. // v2 S7
        let epoch = datasetSession.epoch
        let vectors: BraggVectors?
        do {
            // P1 (Gate D, 2026-09-01): run the full-scan detection OFF the
            // main actor. `detectAll` is nonisolated async and ran on the
            // caller's executor here, and its `concurrentPerform` then
            // conscripted the MAIN thread as a dispatch_apply worker for each
            // tile's entire CPU-FFT workload — sampled live during the
            // owner's frozen run: 2518/2519 main-thread samples inside
            // FFT2D.transform, AX ping 7 s, progress unpaintable, Cancel
            // dead. The detached task keeps the worker pool saturated while
            // the runloop stays free. The progress closure already hopped to
            // the main actor explicitly, so it is unchanged.
            let data = fourD
            // Read on the main actor, before the detach below.
            let (learnedRef, learnedThreshold) = (learnedDetection.probeReference, learnedDetection.threshold)
            let progress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    self.progress = fraction
                    self.showReadout(statusPrefix)   // the bar draws the fraction
                }
            }
            switch detectorClass {
            case .classical:
                vectors = try await Task.detached(priority: .userInitiated) {
                    try await DiskDetection.detectAll(
                        data: data, descriptor: d, kernel: kernel,
                        params: params, cancellation: cancellation,
                        progress: progress
                    )
                }.value
            case .learned:
                guard let learned = preparedLearned, let ref = learnedRef else {
                    throw SimpleError("The learned detector is not ready — this is a defect; please report it.") }
                vectors = try await Task.detached(priority: .userInitiated) {
                    try await learned.detectAll(
                        data: data, descriptor: d, probe: ref.pattern,
                        probeCentre: (x: ref.centreX, y: ref.centreY), probeRadius: ref.radius,
                        kernelSource: ref.source, params: params, threshold: learnedThreshold,
                        cancellation: cancellation, progress: progress
                    )
                }.value
            }
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            if cancellation.isCancelled {
                statusText = resultPresentation.braggVectors == nil
                    ? "Disk detection cancelled — no peaks were published"
                    : "Disk detection cancelled; the previous full-scan peaks are still shown"
                return .cancelled
            }
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
        guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
                // `DiskDetection.detectAll` returns nil on cancellation — never
                // a partial `BraggVectors` — so nothing here is a half-finished
                // result. What stays on screen is the PREVIOUS completed run,
                // and saying so is the difference between this and the silent
                // "it showed a Bragg vector map regardless" the release owner
            // reported (backlog #34). Every other cancellable step in this
            // file already names what it retained; this one did not.
            statusText = resultPresentation.braggVectors == nil
                ? "Disk detection cancelled — no peaks were published"
                : "Disk detection cancelled; the previous full-scan peaks are still shown"
            return .cancelled
        }
        guard let vectors else {
            // With the throwing contract, nil-and-not-cancelled cannot
            // happen; if it ever does, say that rather than invent a cause.
            let reason = "Disk detection returned no result and no reason — this is a defect; please report it."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        resultPresentation.setBraggVectors(vectors)
        learnedDetection.record(vectors, as: detectorClass)
        // Recipe step (v2 S5): the canonical example of why the record exists
        // separately from per-result controls — detection's own product
        // (BraggVectors) is often never saved as a result, but strain's is,
        // and replaying strain without these parameters is impossible.
        // Re-detection INVALIDATES downstream steps: a strain or ACOM step
        // recorded against the old peaks would otherwise survive next to the
        // new detection — a recipe that replays neither the saved maps nor a
        // coherent pipeline (Gate B-lite F4). Re-running them re-records them.
        var replayParameters = params.replayParameters(kernel: kernel)
        replayParameters.merge(learnedDetection.replayParameters(for: detectorClass)) { _, new in new }
        recordReplayStep(kind: "disk_detection", parameters: replayParameters,
                          invalidating: ["strain", "acom"], replaying: replaying)
        completedDiskSummary = DiskDetectionScanSummary(
            vectors: vectors, maximumPeaks: params.maxNumPeaks, parameters: params
        )
        resultPresentation.setBraggPeakCount(vectors.totalPeakCount)
        showBraggMap(vectors, descriptor: d)
        if vectors.totalPeakCount == 0 {
            // An empty result is a dead end unless it points at the
            // evidence: the live acceptance funnel and scan summary in
            // the Bragg panel show which filter removed everything.
            statusText = "Disk detection accepted no peaks — check the acceptance funnel and warnings in the Bragg panel, then relax the intensity or spacing thresholds"
        } else if detectorClass == .learned {
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks (neural net, \(params.subpixel.rawValue) subpixel)"
        } else {
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks (\(params.subpixel.rawValue) subpixel)"
        }
        return .published
    }

    /// Show the Bragg vector map (log-scaled — the central beam dominates the
    /// raw histogram) in the result pane.
    func showBraggMap(_ vectors: BraggVectors, descriptor d: DatasetDescriptor) {
        let calibrated = calibratedBraggVectors(vectors, descriptor: d).vectors
        let bvm = calibrated.map(qy: d.qy, qx: d.qx)
        resultPresentation.resultColormap = .viridis
        publishProduct(   // v2.5 step 3e: its own label
            kind: "bragg_vector_map", displayName: "Bragg vector map", valueUnits: "log_intensity",
            payload: .scalar(FloatImage(width: bvm.width, height: bvm.height,
                                        pixels: bvm.pixels.map { log10(1 + max($0, 0)) })))
        Task { await ensureScanNavigator() }
    }

    /// Publish where the last neural-net and the last classical full-scan run
    /// on this dataset disagree, peak against peak, as a scan map (C7 session
    /// 3; docs/archive/v3/learned-detector-preregistration-2026-09-07.md (was docs/v3-plan.md §3a) — "a product like any other"). Runs nothing and
    /// records no recipe step: both inputs are completed results held by
    /// `learnedDetection`, which clears them on dataset activation, so the pair
    /// is always one dataset's; a replay reproduces it by re-running both.
    @discardableResult
    func runDiskDisagreement() -> AnalysisRunOutcome {
        guard let classical = learnedDetection.lastClassical,
              let learned = learnedDetection.lastLearned else {
            return .failed("Run Detect All Disks with each detector on this dataset first")
        }
        guard let (image, summary) = DiskDisagreement.positionMatchedMap(
            classical: classical, learned: learned
        ) else {
            return .failed("The classical and neural-net runs do not share a scan shape")
        }
        resultPresentation.resultColormap = .viridis
        // The mode's own metadata describes the current Bragg vectors; the
        // product overrides what differs (domain, source, both classes, the
        // compared learned run's identity, the statistics).
        publishProduct(
            kind: "disk_disagreement", displayName: "Detector disagreement (unmatched peaks)",
            valueUnits: "peaks", payload: .scalar(image), domain: .scan,
            extraProvenance: summary.provenance(learnedRun: learned.detectionProvenance))
        statusText = summary.statusLine
        return .published
    }

    /// Raw peaks remain the source of truth; analysis calibration is derived
    /// on demand so imported or newly fitted origin/ellipse values immediately
    /// affect Bragg maps, strain, and ACOM without re-running detection.
    func calibratedBraggVectors(          // internal since 2026-09-12: AppState+PhaseMapping
        _ vectors: BraggVectors,
        descriptor d: DatasetDescriptor,
        positions: [Int]? = nil
    ) -> (vectors: BraggVectors, origin: Calibration.ReferenceOrigin) {
        // v2 S13: ONE derivation, `Calibration.referenceOrigin`. This line used
        // to read `calibration.meanOrigin ?? (qx/2, qy/2)`, and `meanOrigin` is
        // nil in exactly the `.fileMean`/`.sessionMean` states — so the file's
        // recorded beam centre was replaced by the detector's geometric middle
        // in Q calibration, strain, ACOM and the Bragg map at once, while the
        // inspector went on displaying the file's origin (S11, 2026-08-28).
        // Three sibling call sites fell back to the aperture instead; they now
        // ask the same function, and the KIND travels with the value so a
        // caller that must not accept a stand-in can refuse on it.
        let origin = calibrationSession.calibration.referenceOrigin(
            detectorQX: d.qx, detectorQY: d.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        )
        return (
            vectors.calibrated(
                with: calibrationSession.calibration, referenceOrigin: origin.point, positions: positions
            ),
            origin
        )
    }
}
