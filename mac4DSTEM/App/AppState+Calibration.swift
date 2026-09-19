//
//  AppState+Calibration.swift
//  Role: the Prepare calibrations — DP statistics, origin, ellipse,
//        R–Q rotation — and the centre-of-mass field they and DPC share.
//        Moved verbatim out of AppState.swift on 2026-09-18 (the audit's
//        refactor row 5, one AppState seam per session): a placement change,
//        no logic touched; the only edits are `private` → internal on the
//        members the other file still reaches.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {
    /// Compute just the mean/max diffraction patterns (py4DSTEM get_dp_mean /
    /// get_dp_max) so the Mean/Max display modes work without running the
    /// full origin calibration.
    func computeDPStatistics() async {
        guard let fourD = datasetSession.fourD, let descriptor else { return }
        let cancellation = beginCancellableOperation(
            "DP statistics", status: "Computing DP mean/max…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        do {
            let epoch = datasetSession.epoch
            let statistics = try await VirtualDetector.tiledDPStatistics(
                data: fourD, descriptor: d, cancellation: cancellation
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentOperation(cancellation) else { return }
                    self.progress = fraction
                    self.statusText = "Computing DP mean/max…"
                }
            }
            let (maxDP, meanDP) = statistics
            guard epoch == datasetSession.epoch else { return }
            if cancellation.isCancelled {
                statusText = "DP statistics cancelled"
                return
            }
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: maxDP)
            patternVersion &+= 1
            statusText = "DP statistics ✓  (mean + max over \(d.rx) × \(d.ry) positions)"
        } catch {
            if cancellation.isCancelled { statusText = "DP statistics cancelled" }
            else { presentComputeFailure(error) }
        }
    }

    /// Origin calibration (py4DSTEM get_origin + fit_origin): max pattern →
    /// probe size → per-pattern beam position → smooth fit. Also fills the
    /// mean/max pattern display modes as a side effect.
    func calibrateOrigin() async {
        guard let fourD = datasetSession.fourD, let descriptor else { return }
        let cancellation = beginCancellableOperation(
            "Origin calibration", status: "Calibrating origin…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let fitFn = calibrationSession.originFitFunction
        let method = calibrationSession.originMethod
        let d = descriptor
        do {
            let epoch = datasetSession.epoch
            // The Friedel path runs CPU FFTs via `DispatchQueue.concurrentPerform`.
            // A direct await from this MainActor-owned state can enlist the main
            // thread as a dispatch-apply worker, starving the run loop and Cancel.
            // Keep the publication contract on MainActor but run the whole tiled
            // operation on its own executor, as full-scan disk detection does.
            let data = fourD
            let progress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentOperation(cancellation) else { return }
                    self.progress = fraction
                    self.statusText = "Calibrating origin…"
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try await OriginCalibration.tiledRun(
                    data: data, descriptor: d, fitFunction: fitFn, originMethod: method,
                    cancellation: cancellation, progress: progress
                )
            }.value
            guard epoch == datasetSession.epoch else { return }
            if cancellation.isCancelled {
                statusText = "Origin calibration cancelled"
                return
            }
            guard let result else { return }

            calibrationSession.calibration.probeRadius = result.probeRadius
            calibrationSession.provenance.probe = .measuredInApp
            refreshDiskDefaultsForMeasuredProbe()
            calibrationSession.calibration.origin = result.origin
            clearSupersededFittedOrigin()
            phaseContrast.parallaxPreprocess = nil
            phaseContrast.parallaxAlignment = nil
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.maxDP)
            patternVersion &+= 1

            // Recenter the aperture on the measured beam.
            if let origin = calibrationSession.calibration.meanOrigin {
                aperture.centerX = origin.x
                aperture.centerY = origin.y
                calibrationSession.calibration.originProvenance = .fitted
            }
            let rms = result.origin.rmsResidual ?? 0
            statusText = String(format: "Origin ✓  r ≈ %.1f px, fit RMS %.3f px (%@)",
                                result.probeRadius, rms, fitFn.rawValue)

            await runCurrentAnalysis()
        } catch {
            if cancellation.isCancelled { statusText = "Origin calibration cancelled" }
            else { presentComputeFailure(error) }
        }
    }

    /// Fit py4DSTEM-native `(a,b,theta)` from the detector-shaped Bragg map
    /// when one is visible, otherwise from the scan-mean diffraction pattern.
    /// The fitter owns the qx=row/qy=column convention; this method performs
    /// the single app x/y swap at its boundary.
    func calibrateEllipse(acceptSparseCoverage: Bool = false) async {
        guard let descriptor else { return }
        let detectorPattern: DiffractionPattern
        let sourceName: String
        if navigation.analysisMode == .disks, let vectors = resultPresentation.braggVectors {
            // The displayed Bragg map is log-scaled for display and already
            // carries any active ellipse correction. The intensity-weighted
            // fit needs the measured evidence instead: raw peak intensities,
            // collapsed onto the mean origin, with no ellipse applied —
            // fitting an already-corrected map would converge toward no
            // distortion and overwrite a valid calibration.
            var uncorrected = calibrationSession.calibration
            uncorrected.ellipseA = nil
            uncorrected.ellipseB = nil
            uncorrected.ellipseTheta = nil
            let origin = calibrationSession.calibration.meanOrigin
                ?? (x: Float(descriptor.qx) / 2, y: Float(descriptor.qy) / 2)
            let bvm = vectors.calibrated(
                with: uncorrected, referenceOrigin: origin
            ).map(qy: descriptor.qy, qx: descriptor.qx)
            detectorPattern = DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx, pixels: bvm.pixels
            )
            sourceName = "Bragg-vector map"
        } else {
            if meanPattern == nil { await computeDPStatistics() }
            guard let meanPattern else {
                presentComputeFailure(SimpleError("Compute a mean diffraction pattern before fitting ellipse distortion."))
                return
            }
            detectorPattern = meanPattern
            sourceName = "mean diffraction pattern"
        }
        guard calibrationSession.ellipseFitInnerRadius >= 0,
              calibrationSession.ellipseFitOuterRadius > calibrationSession.ellipseFitInnerRadius else {
            presentComputeFailure(SimpleError("Ellipse fit outer radius must be larger than its inner radius."))
            return
        }

        let centerQX = Double(aperture.centerY)
        let centerQY = Double(aperture.centerX)
        let inner = calibrationSession.ellipseFitInnerRadius
        let outer = calibrationSession.ellipseFitOuterRadius
        let epoch = datasetSession.epoch
        let cancellation = beginCancellableOperation(
            "Ellipse calibration", status: "Fitting detector ellipse…", totalUnits: 1
        )
        defer { finishCancellableOperation(cancellation) }
        do {
            let fit = try await Task.detached(priority: .userInitiated) {
                try EllipseCalibration.fitBestAvailable(
                    pattern: detectorPattern,
                    centerQX: centerQX, centerQY: centerQY,
                    innerRadius: inner, outerRadius: outer, acceptSparseCoverage: acceptSparseCoverage
                )
            }.value
            guard epoch == datasetSession.epoch, !cancellation.isCancelled else {
                statusText = "Ellipse calibration cancelled"
                return
            }
            calibrationSession.applyEllipseFit(fit)
            progress = 1

            // A displayed Bragg map can be reprojected immediately because
            // raw peak storage remains unchanged. Strain/ACOM are deliberately
            // not relabeled; users rerun those quantitative analyses.
            if navigation.analysisMode == .disks, let vectors = resultPresentation.braggVectors {
                showBraggMap(vectors, descriptor: descriptor)
            }
            statusText = fit.sparseCoverage
                ? String(format: "Ellipse fitted anyway on %d/36 sectors · a %.2f · b %.2f · θ %.1f° · residual %.3f (%@) — marked Fit anyway",
                         fit.occupiedAngularBins, fit.a, fit.b, fit.theta * 180 / .pi, fit.normalizedResidual, sourceName)
                : String(format: "Ellipse ✓  %@ · a %.2f · b %.2f · θ %.1f° · residual %.3f (%@)",
                         fit.model.rawValue, fit.a, fit.b, fit.theta * 180 / .pi, fit.normalizedResidual, sourceName)
        } catch {
            if cancellation.isCancelled { statusText = "Ellipse calibration cancelled" }
            else {
                calibrationSession.refuseEllipseFit(error)
                presentComputeFailure(error)
            }
        }
    }

    /// R–Q rotation calibration: find the rotation (and detector transpose)
    /// that makes the CoM field curl-free. Runs origin calibration first if
    /// needed — the solver wants the descan-corrected field.
    func calibrateRotation(maximizeDivergence: Bool = false) async {
        guard let descriptor else { return }

        if !calibrationSession.calibration.hasFittedOrigin {
            await calibrateOrigin()
            guard calibrationSession.calibration.hasFittedOrigin else { return }
        }

        let cancellation = beginCancellableOperation(
            "R–Q rotation", status: "Calibrating R–Q rotation…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        do {
            let epoch = datasetSession.epoch
            guard let com = try await computeCoMField(cancellation: cancellation) else {
                if cancellation.isCancelled { statusText = "R–Q rotation cancelled" }
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                RotationCalibration.solve(com: com, width: d.rx, height: d.ry,
                                          maximizeDivergence: maximizeDivergence,
                                          cancellation: cancellation)
            }.value
            guard epoch == datasetSession.epoch else { return }
            if cancellation.isCancelled {
                statusText = "R–Q rotation cancelled"
                return
            }
            guard let result else {
                presentComputeFailure(SimpleError("Scan is too small for rotation calibration (need at least 3 × 3 positions)."))
                return
            }
            if calibrationSession.applyRotation(result) != nil {   // the full refusal is in Rotation diagnostics
                lastRotationResult = result; presentComputeFailure(SimpleError("R–Q rotation not updated: the field does not beat its own null. The reason is under Rotation diagnostics in the inspector.")); return
            }
            phaseContrast.parallaxPreprocess = nil
            phaseContrast.parallaxAlignment = nil
            lastRotationResult = result
            // A cached CoM field must not show a stale rotation — and if the
            // re-derivation itself refuses (iDPC), its message must not be
            // overwritten by the ✓ line (Gate B, 2026-08-25). The rotation
            // DID calibrate either way; only the status line changes.
            // A displayed strain map is derived from the same rotation and
            // re-derives on the same rule. // v2 S8
            applyStrainDisplay()
            if applyDPCDisplay() == nil {
                statusText = String(format: "Rotation ✓  θ = %.1f°%@",
                                    result.rotationRad * 180 / .pi,
                                    result.transpose ? ", detector transposed" : "")
            }
        } catch {
            if cancellation.isCancelled { statusText = "R–Q rotation cancelled" }
            else { presentComputeFailure(error) }
        }
    }

    /// Measure the CoM shift field on the GPU, against calibrated origins when
    /// available. Shared by rotation calibration and (later) DPC.
    func computeCoMField(
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> [Float]? {
        guard cancellation?.isCancelled != true else { return nil }
        guard let fourD = datasetSession.fourD, let descriptor else { return nil }
        let origins = calibrationSession.calibration.origin?.interleavedFitted
        let center = calibrationSession.calibration.referenceOrigin(  // v2 S13: one derivation
            detectorQX: descriptor.qx, detectorQY: descriptor.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
        let d = descriptor
        let result = try await VirtualDetector.tiledCenterOfMass(
            data: fourD, descriptor: d, center: center, origins: origins,
            cancellation: cancellation
        ) { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let cancellation, !self.isCurrentOperation(cancellation) { return }
                self.progress = fraction
            }
        }
        return cancellation?.isCancelled == true ? nil : result
    }
}
