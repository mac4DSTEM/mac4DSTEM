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
    /// recovered session opened directly into Map and never formed a virtual
    /// image. A quiet ADF image gives structural contrast without replacing the
    /// retained scientific result.
    /// Quietly build persistent real-space context used for region selection
    /// and for detector/reconstruction products. Failure is non-fatal because
    /// the primary scientific result remains usable without the convenience.
    func ensureScanNavigator() async {
        guard scanNavigationImage == nil,
              let fourD, let descriptor else { return }
        let d = descriptor
        let qRadius = Float(min(d.qx, d.qy)) / 2
        let center = calibrationSession.calibration.meanOrigin
            ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
        do {
            let epoch = datasetEpoch
            let image = try await VirtualDetector.tiledImage(
                data: fourD, descriptor: d,
                shape: .annulus(
                    centerX: center.x, centerY: center.y,
                    inner: 0.25 * qRadius, outer: 0.55 * qRadius
                )
            )
            guard epoch == datasetEpoch else { return }
            scanNavigationImage = image
            bumpScanNavigationVersion()
        } catch {
            // Region selection can still use steppers if the reference image
            // cannot be formed; do not turn a navigation convenience into a
            // blocker for an otherwise valid ACOM run.
        }
    }


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
        guard let fourD, let d = descriptor, realSpaceShape != .point else { return }
        let region = DetectorShape.realSpaceRegion(
            shape: realSpaceShape, radius: realSpaceRadius, scanX: selectedScan.x, scanY: selectedScan.y)
        let epoch = datasetEpoch
        do {
            let pattern = try await VirtualDetector.tiledDiffraction(
                data: fourD, descriptor: d, region: region
            )
            guard epoch == datasetEpoch else { return }
            resultPresentation.setVirtualDiffractionPattern(pattern)
            patternVersion &+= 1
            await detectCurrentPattern()
        } catch is CancellationError {
            // Cancellation during a drag is expected.
        } catch {
            if epoch == datasetEpoch { presentComputeFailure(error) }
        }
    }


    /// Apply a standard detector geometry (BF/ADF/HAADF) and recompute.
    func applyDetectorPreset(_ preset: DetectorPreset) {
        guard let descriptor else { return }
        let qMax = Float(min(descriptor.qx, descriptor.qy)) / 2
        if let radii = preset.radii(maxRadius: qMax) {
            aperture.inner = radii.inner
            aperture.outer = radii.outer
            resultPresentation.virtualShape = preset == .brightField ? .circle : .annulus
        }
        if navigation.analysisMode != .virtualDetector { navigation.analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    private func virtualDetectorProgressTileRows(for descriptor: DatasetDescriptor) -> Int {
        let bytesPerScanRow = descriptor.rx * descriptor.qy * descriptor.qx * MemoryLayout<Float>.stride
        let targetBytes = 16 * 1024 * 1024
        return max(1, min(descriptor.ry, targetBytes / max(1, bytesPerScanRow)))
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
        guard let fourD, let descriptor else { return .failed("No dataset is loaded") }
        let totalPatterns = descriptor.rx * descriptor.ry
        let scanVerb = isLoadingDataset ? "Scanning patterns" : "Computing virtual detector…"
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
        let d = descriptor
        let maximumTileRows = virtualDetectorProgressTileRows(for: d)
        do {
            let epoch = datasetEpoch
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            let progressUpdate: (@Sendable (Double) -> Void)?
            if let token = cancellation {
                progressUpdate = { @Sendable [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrentOperation(token) else { return }
                        let clipped = min(1, max(0, fraction))
                        let processed = min(totalPatterns, max(0, Int((clipped * Double(totalPatterns)).rounded())))
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
            guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            resultPresentation.resultColormap = .viridis
            scanNavigationImage = image
            bumpScanNavigationVersion()
            resultPresentation.bumpResultVersion()
            // The product value — kind, name, units and status decided HERE,
            // by the site that computed the pixels, not re-derived later from
            // strings (v2.5 step 3). Mirrors `currentScalarResultMetadata`'s
            // `.virtualDetector` case until that switch is deleted.
            resultPresentation.replaceProduct(DisplayedProduct(
                kind: "virtual_\(shapeMode.rawValue.lowercased())",
                displayName: "Virtual detector · \(shapeMode.rawValue)",
                payload: .scalar(image), domain: .scan,
                sampling: ProductSampling(
                    row: calibrationSession.calibration.rPixelSize, column: calibrationSession.calibration.rPixelSize,
                    units: calibrationSession.calibration.rPixelUnits),
                valueUnits: "intensity", quantitativeStatus: .relative,
                // The persistence provenance (aperture etc.) plus this site's own keys.
                provenance: currentResultPersistenceMetadata.provenance.merging(
                    ["display_domain": "scan", "quantitative_status": "relative",
                     "virtual_shape": shapeMode.rawValue]) { _, site in site }))
            if !quiet {
                statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
            }
            // The recipe step, recorded at the SUCCESS publish and nowhere
            // earlier — a cancelled or failed run is not part of the pipeline.
            // (An earlier comment here claimed the automatic pass on open
            // "counts too" — refuted: it runs with defaults and would
            // overwrite an adopted recipe; `recordReplayStep` suppresses it.)
            // // v2 S5
            recordReplayStep(kind: "virtual_detector",
                              parameters: Aperture.replayParameters(shape: shapeMode.rawValue, aperture: ap),
                              replaying: replaying)
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
