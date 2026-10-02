//
//  AppState+ResultPresentation.swift
//  Role: AppState seam 5 — cross-owner orchestration for the shared result
//        presentation. Mutable presentation state lives in ResultPresentation.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

extension AppState {
    // MARK: - Analyses

    /// Run the lightweight/default action for the current mode. Expensive
    /// whole-scan workflows remain explicit buttons in their tool sections.
    func runCurrentAnalysis() async {
        switch navigation.analysisMode {
        case .virtualDetector: await runVirtualDetector()
        case .dpc:             await runDPC()
        case .disks:
            // Live overlay on the current pattern; the full-scan pass is
            // explicit (Detect All Disks) because it's expensive.
            await detectCurrentPattern()
            if let bv = resultPresentation.braggVectors, let d = descriptor { showBraggMap(bv, descriptor: d) }
        case .strain:
            // Strain is computed explicitly (needs a disk-detection pass);
            // just re-show it if already computed.
            if strain.map != nil { applyStrainDisplay() }
        case .ptychography:
            if phaseContrast.parallaxAlignment != nil { showParallaxProduct(.alignment) }
            else if phaseContrast.parallaxPreprocess != nil { showParallaxProduct(.preprocess) }
        case .singleslicePtychography:
            if phaseContrast.singleslicePtychography != nil { showParallaxProduct(.iterativePhase) }
        case .acom:
            if acomSession.orientationMap != nil { applyACOMDisplay() }
        case .diffractionGroups, .phaseMapping:
            break   // a whole-scan run is explicit, never the default action
        }
    }

    /// Ensure ACOM region selection has a real-space canvas even when a
    /// recovered session opened directly into Map and never formed a
    /// virtual image: builds a quiet ADF image for structural context.
    /// Failure is non-fatal — the primary scientific result remains usable
    /// without this convenience.
    func ensureScanNavigator() async {
        guard scanNavigationImage == nil,
              let fourD = datasetSession.fourD, let descriptor else { return }
        let d = descriptor
        let qRadius = Float(min(d.qx, d.qy)) / 2
        let center = calibrationSession.calibration.meanOrigin
            ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
        do {
            let epoch = datasetSession.epoch
            let image = try await VirtualDetector.tiledImage(
                data: fourD, descriptor: d,
                shape: .annulus(
                    centerX: center.x, centerY: center.y,
                    inner: 0.25 * qRadius, outer: 0.55 * qRadius
                )
            )
            guard epoch == datasetSession.epoch else { return }
            scanNavigationImage = image
            bumpScanNavigationVersion()
        } catch {
            // Region selection can still use steppers if the reference image
            // cannot be formed; do not turn a navigation convenience into a
            // blocker for an otherwise valid ACOM run.
        }
    }


    /// Test seam (review row 25): awaited after the pixels are computed and
    /// before the run lands, so a test can hold a quiet run back and force the
    /// ordering "commit lands first, the stale quiet run second" without sleeps.
    /// Nil in production.
    static var virtualDetectorBeforeLanding: (@MainActor (_ quiet: Bool, _ aperture: Aperture) async -> Void)?

    func scheduleLiveVirtualDetector() {
        guard navigation.analysisMode == .virtualDetector else { return }
        if resultPresentation.vdInFlight { resultPresentation.vdPending = true; return }
        resultPresentation.vdInFlight = true
        Task {
            await runVirtualDetector(quiet: true)
            resultPresentation.vdInFlight = false
            if resultPresentation.vdPending { resultPresentation.vdPending = false; scheduleLiveVirtualDetector() }
        }
    }

    func commitApertureChange() {
        guard navigation.analysisMode == .virtualDetector else { return }
        Task { await runVirtualDetector() }   // final pass, with status
    }

    /// Live scan-position scrub (drag in the real-space image). A point ROI
    /// streams the single pattern; a region ROI streams the summed pattern.
    func scrubTo(x: Int, y: Int) {
        guard let d = descriptor else { return }
        if navigation.analysisMode == .acom, acomSession.scope == .selectedRegion {
            acomSession.regionSelectionActive = true
        }
        let clamped = ScanPos(x: min(max(0, x), d.rx - 1), y: min(max(0, y), d.ry - 1))
        if clamped != selectedScan { selectedScan = clamped }
        if realSpaceShape == .point {
            scheduleLoadPattern()
        } else {
            scheduleVirtualDiffraction()
        }
    }

    /// Re-run whichever real-space product matches the current region shape
    /// (called when the shape or radius changes).
    func updateRealSpaceRegion() {
        if realSpaceShape == .point {
            resultPresentation.setVirtualDiffractionPattern(nil)
            patternVersion &+= 1
            scheduleLoadPattern()
        } else {
            scheduleVirtualDiffraction()
        }
    }

    private func scheduleLoadPattern() {
        if resultPresentation.patternInFlight { resultPresentation.patternPending = true; return }
        resultPresentation.patternInFlight = true
        Task {
            await loadCurrentPattern()
            resultPresentation.patternInFlight = false
            if resultPresentation.patternPending { resultPresentation.patternPending = false; scheduleLoadPattern() }
        }
    }

    private func scheduleVirtualDiffraction() {
        if resultPresentation.vdiffInFlight { resultPresentation.vdiffPending = true; return }
        resultPresentation.vdiffInFlight = true
        Task {
            await computeVirtualDiffraction()
            resultPresentation.vdiffInFlight = false
            if resultPresentation.vdiffPending { resultPresentation.vdiffPending = false; scheduleVirtualDiffraction() }
        }
    }

    /// Sum the patterns over the current real-space region into the CBED pane.
    private func computeVirtualDiffraction() async {
        guard let fourD = datasetSession.fourD, let d = descriptor,
              realSpaceShape != .point else { return }
        let region = DetectorShape.realSpaceRegion(
            shape: realSpaceShape, radius: realSpaceRadius, scanX: selectedScan.x, scanY: selectedScan.y)
        let epoch = datasetSession.epoch
        do {
            let pattern = try await VirtualDetector.tiledDiffraction(
                data: fourD, descriptor: d, region: region
            )
            guard epoch == datasetSession.epoch else { return }
            resultPresentation.setVirtualDiffractionPattern(pattern)
            patternVersion &+= 1
            await detectCurrentPattern()
        } catch is CancellationError {
            // Cancellation during a drag is expected.
        } catch {
            if epoch == datasetSession.epoch { presentComputeFailure(error) }
        }
    }


    /// The measured beam radius the BF/ADF presets follow (polish lane F, S3):
    /// the Prepare calibration's probe radius, only when it is a usable number.
    /// Nil → presets use detector fractions and Imaging says so.
    var presetProbeRadius: Float? {
        calibrationSession.calibration.probeRadius.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    /// Entering Phase mapping or Diffraction groups (S5 item 2): a published
    /// product survives a task switch, so these two modes showed whatever was
    /// last on screen (the Strain map before a first phase run). Show the
    /// mode's own product, or nothing. Diffraction groups' own product is
    /// republished only by its run, so with a result it is left as is.
    func presentProductForEnteredMode(_ mode: AnalysisMode) {
        switch mode {
        case .phaseMapping:
            let kind = resultPresentation.product?.kind
            if phaseMapping.map != nil, phaseMapping.lastRun != nil {
                if kind != "phase_map", kind != "phase_match_distance", kind != "precipitate_objects" {
                    publishPhaseMapProduct()
                }
            } else if resultPresentation.product != nil {
                resultPresentation.replaceProduct(nil)
                resultPresentation.bumpResultVersion()
            }
        case .diffractionGroups:
            // OPEN (lane F report): with a result, the grouping map is not
            // republished here — that needs the run's settings.
            if diffractionGroups.result == nil, resultPresentation.product != nil {
                resultPresentation.replaceProduct(nil)
                resultPresentation.bumpResultVersion()
            }
        case .strain, .acom, .dpc, .ptychography, .singleslicePtychography:
            // Polish lane J (owner card S5 a): the same rule for the other rooms. A product of
            // another room is replaced by this room's own result through the room's own show
            // function (no compute, no new state), or by nothing.
            guard let kind = resultPresentation.product?.kind,
                  AnalysisMode.owning(productKind: kind) != mode else { return }
            switch mode {
            case .strain:
                if strain.map != nil { applyStrainDisplay() }
            case .acom:
                if acomSession.orientationMap != nil { applyACOMDisplay() }
            case .dpc:
                if comField != nil { _ = applyDPCDisplay() }
            case .ptychography:
                let remembered = phaseContrast.parallaxResultProduct
                showParallaxProduct(remembered.isIterative ? .preprocess : remembered)
            default:   // .singleslicePtychography
                let remembered = phaseContrast.parallaxResultProduct
                showParallaxProduct(remembered.isIterative ? remembered : .iterativePhase)
            }
            // Still another room's product (no own result, or its show function declined): clear.
            if let still = resultPresentation.product?.kind, AnalysisMode.owning(productKind: still) != mode {
                resultPresentation.replaceProduct(nil)
                resultPresentation.bumpResultVersion()
            }
        case .disks:
            // Entering another room clears its product (above); coming back re-shows the
            // Bragg map from the vectors the session still holds. Nothing held: left as is.
            if let kind = resultPresentation.product?.kind, AnalysisMode.owning(productKind: kind) == .disks { return }
            guard let vectors = resultPresentation.braggVectors, let d = descriptor else { return }
            showBraggMap(vectors, descriptor: d)
        default: break
        }
    }

    /// Apply a standard detector geometry (BF/ADF/HAADF) and recompute.
    func applyDetectorPreset(_ preset: DetectorPreset) {
        guard let descriptor else { return }
        let qMax = Float(min(descriptor.qx, descriptor.qy)) / 2
        if let radii = preset.radii(maxRadius: qMax, probeRadius: presetProbeRadius) {
            aperture.inner = radii.inner
            aperture.outer = radii.outer
            resultPresentation.virtualShape = preset == .brightField ? .circle : .annulus
        }
        if navigation.analysisMode != .virtualDetector { navigation.analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    /// Rows per streamed tile for the virtual-image pass: 16 MiB tiles, so the
    /// progress bar ticks. Sized at the READ extent, not the view's — H5's
    /// hyperslab and DM4's gather allocate the tile pre-bin before
    /// `LoadView.binned` reduces it, and sizing from the binned descriptor let
    /// that transient reach bin² × 16 MiB (1 GiB at bin 8; pre-release review
    /// d1 residual, 2026-10-02). The read extent is the expression
    /// `FourDArray.scanTileRows` uses. Bin 1: it is the view's extent, so the
    /// rows are unchanged.
    /// No number depends on the grouping: both kernels sum one scan position's
    /// own pattern (VirtualAperture.metal, VirtualMask.metal).
    /// `static` and not private so `ReviewTileBudgetSiblingsTests` can pin it.
    static func virtualDetectorProgressTileRows(for view: LoadView) -> Int {
        let readHeight = view.readDetectorCrop?.height ?? view.source.qy
        let readWidth = view.readDetectorCrop?.width ?? view.source.qx
        let bytesPerScanRow = view.descriptor.rx * readHeight * readWidth * MemoryLayout<Float>.stride
        let targetBytes = 16 * 1024 * 1024
        return max(1, min(view.descriptor.ry, targetBytes / max(1, bytesPerScanRow)))
    }

    /// Virtual-detector imaging over the whole cube. The annulus uses the
    /// analytic fast path; rectangle/point use the general mask kernel. The
    /// blocking GPU call is pushed off the main actor.
    /// Returns the typed run verdict — `.published` exactly on the path that
    /// records the recipe step. `replaying` marks a replay-initiated run,
    /// whose recording is suppressed. S6's executor is the consumer;
    /// interactive call sites ignore both. // v2 S6
    @discardableResult
    func runVirtualDetector(quiet: Bool = false, replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let fourD = datasetSession.fourD, let descriptor else {
            return .failed("No dataset is loaded")
        }
        let totalPatterns = descriptor.rx * descriptor.ry
        let scanVerb = datasetSession.isLoading ? "Scanning patterns" : "Computing virtual detector…"
        let cancellation = quiet ? nil : beginCancellableOperation(
            "Virtual detector",
            status: SystemMonitor.scanProgressStatus(
                scanVerb, processed: 0, total: totalPatterns, descriptor: descriptor
            ),
            totalUnits: totalPatterns
        )
        defer {
            if let cancellation { finishCancellableOperation(cancellation) }
        }

        let ap = aperture
        let shapeMode = resultPresentation.virtualShape
        // FC2 item 3: runs are numbered at start; an older run never lands over a newer one
        // that already landed (commit after a newer quiet drag). Owner: ResultPresentation.
        let generation = resultPresentation.nextVDGeneration()
        let d = descriptor
        let maximumTileRows = Self.virtualDetectorProgressTileRows(for: fourD.view)
        do {
            let epoch = datasetSession.epoch
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            // The bottom workspace's Run tab "Streamed" row (ADR 034): the
            // same float32 working-size arithmetic `SystemMonitor.scanProgressStatus`
            // already does internally, exposed here because that function
            // only returns the composed status string, not the byte count.
            let bytesPerPattern = d.qy * d.qx * MemoryLayout<Float>.stride
            let progressUpdate: (@Sendable (Double) -> Void)?
            if let token = cancellation {
                progressUpdate = { @Sendable [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrentOperation(token) else { return }
                        let clipped = min(1, max(0, fraction))
                        let processed = min(totalPatterns, max(0, Int((clipped * Double(totalPatterns)).rounded())))
                        // Routed through `OperationCenter.update(_:bytesStreamed:)`,
                        // not a bare property write, so a cancelled token is
                        // rejected the same way `updateCancellableOperation`
                        // below already rejects it for progress — otherwise
                        // "Streamed" keeps climbing after Cancel while the
                        // progress bar and position count it sits beside have
                        // already frozen (Gate-B finding).
                        self.operationCenter.update(token, bytesStreamed: Int64(processed) * Int64(bytesPerPattern))
                        self.updateCancellableOperation(
                            token,
                            progress: clipped,
                            status: SystemMonitor.scanProgressStatus(
                                scanVerb, processed: processed,
                                total: totalPatterns, descriptor: d
                            )
                        )
                    }
                }
            } else {
                progressUpdate = nil
            }
            let image: FloatImage
            switch shapeMode {
            case .circle:
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .circle(centerX: ap.centerX, centerY: ap.centerY,
                                   radius: ap.outer),
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            case .annulus:
                image = try await VirtualDetector.tiledRun(
                    data: fourD, descriptor: d, aperture: ap,
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            case .rectangle:
                let half = Int(ap.outer.rounded())
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .rectangle(
                        xMin: Int(ap.centerX.rounded()) - half,
                        xMax: Int(ap.centerX.rounded()) + half,
                        yMin: Int(ap.centerY.rounded()) - half,
                        yMax: Int(ap.centerY.rounded()) + half),
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            case .point:
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .point(x: Int(ap.centerX.rounded()),
                                  y: Int(ap.centerY.rounded())),
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            }
            await Self.virtualDetectorBeforeLanding?(quiet, ap)
            guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            // Row 25: a quiet (live-drag) run lands only while it still describes the
            // live aperture and shape. A quiet run that finished after the commit run
            // (or after a newer drag) is stale: landing it would overwrite the newer
            // image and record the older aperture with no re-run pending.
            // DEVIATION (from the review's proposed request counter): a staleness check
            // on the inputs, because the counter's owner file is outside this lane; the
            // landed image is the one for the live aperture either way.
            if quiet, ap != aperture || shapeMode != resultPresentation.virtualShape {
                return .cancelled
            }
            guard resultPresentation.claimVDLanding(generation) else { return .cancelled }
            resultPresentation.resultColormap = .viridis
            scanNavigationImage = image
            bumpScanNavigationVersion()
            // Row 8: published like every other site. The provenance is the MODE's own
            // (`currentScalarPersistenceMetadata`) plus this site's keys, never the
            // product that happens to be on screen. The kind, name, units and status are
            // decided HERE, by the site that computed the pixels (v2.5 step 3).
            publishProduct(
                kind: "virtual_\(shapeMode.rawValue.lowercased())",
                displayName: "Virtual detector · \(shapeMode.rawValue)",
                valueUnits: "intensity", payload: .scalar(image),
                domain: .scan,
                sampling: ProductSampling(
                    row: calibrationSession.calibration.rPixelSize, column: calibrationSession.calibration.rPixelSize,
                    units: calibrationSession.calibration.rPixelUnits),
                // analysis_mode is pinned to this product's own mode; it cannot remove stray
                // keys the CURRENT mode's metadata adds (replay/rewind/opening paths: separate item).
                extraProvenance: ["analysis_mode": AnalysisMode.virtualDetector.rawValue,
                                  "quantitative_status": "relative", "virtual_shape": shapeMode.rawValue],
                ownProvenanceOnly: true)
            if !quiet {
                statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
            }
            // The recipe step, recorded at the SUCCESS publish and nowhere
            // earlier — a cancelled or failed run is not part of the
            // pipeline. The automatic pass on open does not count: it runs
            // with defaults and would overwrite an adopted recipe;
            // `recordReplayStep` suppresses it.
            recordReplayStep(kind: "virtual_detector",
                              parameters: Aperture.replayParameters(shape: shapeMode.rawValue, aperture: ap),
                              replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch {
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            if !quiet { presentComputeFailure(error) }
            return .failed(error.localizedDescription)
        }
    }


    func showComputedProduct(_ product: ComputedProduct) {
        resultPresentation.inspectQualityField = false
        switch product {
        case .strain:
            guard strain.map != nil else { return }
            navigation.analysisMode = .strain
            navigation.workspaceArea = .map
            applyStrainDisplay()
        case .orientation:
            guard acomSession.hasOrientationMap else { return }
            navigation.analysisMode = .acom
            navigation.workspaceArea = .map
            applyACOMDisplay()
        }
    }

    /// The frame strain is presented in right now, derived from the CURRENT
    /// calibration on every read (the `applyDPCDisplay` pattern) — a later
    /// rotation calibration changes what is shown, never silently desyncs
    /// from it. // v2 S8
    var strainPresentationFrame: StrainPresentationFrame {
        .resolve(rotationRad: calibrationSession.calibration.rotationRad,
                 transposeQR: calibrationSession.calibration.transposeQR)
    }

    /// Show the selected strain component, expressed in the presentation
    /// frame; masked positions remain NaN and render with the explicit
    /// no-data color, never as neutral zero strain.
    /// The one publish site for the strain product (v2.5 step 3e, condition 2).
    func applyStrainDisplay() {
        guard let map = strain.map, navigation.analysisMode == .strain else { return }
        resultPresentation.resultColormap = (strain.component == .residual || strain.component == .indexed)
            ? .viridis : .rdbu
        let kind: String, units: String
        switch strain.component {
        case .exx:      (kind, units) = ("strain_exx", "strain")
        case .eyy:      (kind, units) = ("strain_eyy", "strain")
        case .exy:      (kind, units) = ("strain_exy", "strain")
        case .theta:    (kind, units) = ("strain_theta", "rad")
        case .residual: (kind, units) = ("strain_fit_residual", "detector_px")
        case .indexed:  (kind, units) = ("strain_indexed", "boolean")
        }
        publishProduct(
            kind: kind, displayName: "Strain · \(strain.component.rawValue)", valueUnits: units,
            payload: .scalar(map.presented(in: strainPresentationFrame).component(strain.component)),
            validityMask: map.mask,
            qualityFields: [
                ProductQualityField(
                    name: "fit residual", units: "detector_px",
                    image: FloatImage(width: map.width, height: map.height, pixels: map.localResidualPixels)),
                ProductQualityField(
                    name: "indexed", units: "boolean",
                    image: FloatImage(width: map.width, height: map.height, pixels: map.mask.map { $0 ? 1 : 0 })),
            ],
            overlays: [ProductOverlayDescriptor(
                kind: "local_lattice_fit", provenance: "retained Bragg-vector least-squares fit")])
    }


}

extension AnalysisMode {
    /// The room a published product's `kind` belongs to; nil for kinds no room owns
    /// (virtual image, Bragg map, calibration views, ...). Polish lane J (card S5 a).
    static func owning(productKind kind: String) -> AnalysisMode? {
        if kind.hasPrefix("strain_") { return .strain }
        if kind.hasPrefix("acom_") { return .acom }
        if kind.hasPrefix("dpc_") || kind.hasPrefix("idpc_") { return .dpc }
        if kind.hasPrefix("parallax_") { return .ptychography }
        if kind.hasPrefix("ptychography_") { return .singleslicePtychography }
        if kind.hasPrefix("diffraction_") { return .diffractionGroups }
        if kind == "bragg_vector_map" || kind == "disk_disagreement" { return .disks }
        if kind == "phase_map" || kind == "phase_match_distance" || kind == "precipitate_objects" { return .phaseMapping }
        return nil
    }
}

extension ParallaxResultProduct {
    /// The single-slice ptychography products (kinds "ptychography_*"); the rest are parallax.
    var isIterative: Bool {
        switch self {
        case .iterativePhase, .iterativeAmplitude, .iterativeProbePhase, .iterativeProbeAmplitude: true
        default: false
        }
    }
}
