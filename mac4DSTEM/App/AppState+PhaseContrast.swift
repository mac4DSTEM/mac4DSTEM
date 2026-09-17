//
//  AppState+PhaseContrast.swift
//  Role: the Parallax and single-slice ptychography orchestration —
//        preview, per-level alignment, aberration fit, BF upsampling, depth
//        sections, phase correction, product selection.
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
    /// First parallax slice: build and preview py4DSTEM's normalized virtual-BF
    /// stack and incoherent BF initialization. No iterative reconstruction is
    /// performed or implied by this operation.
    func prepareParallaxPreview() async {
        // The view the array actually reads, not a descriptor assembled beside
        // it: a crop and the shape it produces must travel together.
        guard let source = reader, let fourD, let descriptor else { return }
        let view = fourD.view
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibrationSession.calibration,
                apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: calibrationSession.acceleratingVoltage
            )
        } catch {
            presentComputeFailure(error)
            return
        }

        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax preprocessing", status: "Preparing virtual-BF stack…",
            totalUnits: descriptor.ry * 2
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Preparing virtual-BF stack…"
                    )
                }
            }
            let result = try await ParallaxPreprocessor.run(
                source: source, view: view, calibration: physical,
                cancellation: token, progress: progressUpdate
            )
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxPreprocess = result
            parallaxAlignment = nil
            showParallaxProduct(.preprocess)   // v2.5 step 3e: one publish site
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            Task { await ensureScanNavigator() }
            statusText = String(
                format: "Parallax preprocessing ✓  %d BF pixels · λ %.5f Å · %.2f mrad max · error %.4f",
                result.brightFieldPixelCount,
                result.calibration.wavelengthAngstrom,
                result.maximumProbeAngleMrad,
                result.initialError
            )
        } catch ParallaxPreprocessor.PreprocessError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax preprocessing cancelled"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }

    /// Run the next source-locked coarse-to-fine bin with factor-8 matrix-DFT
    /// correlation. The last completed level remains published until the next
    /// one succeeds and passes the operation/dataset publication guards.
    func alignParallaxNextLevel() async {
        guard let preprocessing = parallaxPreprocess else {
            presentComputeFailure(SimpleError("Prepare the parallax preview before alignment."))
            return
        }
        let schedule = ParallaxAligner.defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard !schedule.isEmpty else {
            presentComputeFailure(SimpleError("The bright-field mask cannot form an alignment level."))
            return
        }
        let completed = parallaxAlignment?.completedBins ?? []
        guard completed.count < schedule.count else {
            presentComputeFailure(ParallaxAligner.AlignmentError.alignmentComplete)
            return
        }
        let bin = schedule[completed.count]
        guard parallaxAlignment == nil
                || Array(schedule.prefix(completed.count)) == completed else {
            presentComputeFailure(SimpleError("Reset the stale parallax alignment before continuing."))
            return
        }
        let groups = ParallaxAligner.groups(
            detectorIndices: preprocessing.detectorIndices, alignmentBin: bin
        )
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax alignment bin \(bin)",
            status: "Aligning bin \(bin) virtual-BF groups…",
            totalUnits: groups.count + preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Aligning bin \(bin) virtual-BF groups…"
                    )
                }
            }
            var options = ParallaxAlignmentOptions()
            options.upsampleFactor = 8
            let prior = parallaxAlignment
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAligner.alignNextLevel(
                    preprocessing: preprocessing, previous: prior, options: options,
                    cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxAlignment = result
            showParallaxProduct(.alignment)   // v2.5 step 3e: one publish site
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = String(
                format: "Parallax alignment ✓  level %d/%d · bin %d · %d groups · %.2f px max shift · error %.4f → %.4f%@",
                result.completedBins.count, result.alignmentSchedule.count,
                result.alignmentBin, result.groups.count,
                result.maximumShiftPixels,
                result.errorHistory.dropLast().last ?? .nan,
                result.currentError,
                result.isComplete ? " · schedule complete" : ""
            )
        } catch ParallaxAligner.AlignmentError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax alignment bin \(bin) cancelled; last completed level retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }

    func resetParallaxAlignment() {
        guard !isBusy, parallaxPreprocess != nil else { return }
        parallaxAlignment = nil
        showParallaxProduct(.preprocess)   // v2.5 step 3e: one publish site
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        resultVersion &+= 1
        statusText = "Parallax alignment reset to the preprocessed preview"
    }

    func fitParallaxAberrations() {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment else {
            presentComputeFailure(SimpleError("Complete parallax preprocessing and alignment first."))
            return
        }
        do {
            let result = try ParallaxAberrationFitter.fitHigherOrder(
                preprocessing: preprocessing, alignment: alignment
            )
            parallaxAberrationFit = result.lowOrder
            parallaxHigherOrderFit = result
            statusText = String(
                format: "Recursive aberration fit ✓  %d terms · rotation %.2f° · RMS %.4f Å → %.4f Å",
                result.terms.count,
                result.lowOrder.rotationRad * 180 / .pi,
                result.lowOrder.rmsResidualAngstrom,
                result.rmsResidualAngstrom
            )
        } catch {
            presentComputeFailure(error)
        }
    }

    func upsampleParallaxBF() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment, alignment.isComplete else {
            presentComputeFailure(SimpleError("Complete parallax alignment before KDE upsampling."))
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax KDE", status: "Upsampling aligned virtual-BF images…",
            totalUnits: preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxSubpixelOptions()
            options.upsampleFactor = parallaxKDEUpsampleFactor > 0
                ? parallaxKDEUpsampleFactor : nil
            options.kdeSigmaPixels = parallaxKDESigmaPixels
            options.lowpassFilter = parallaxKDELowpass
            options.lanczosOrder = parallaxKDELanczosOrder > 0
                ? parallaxKDELanczosOrder : nil
            options.positionCorrectionIterations = parallaxPositionCorrectionIterations > 0
                ? parallaxPositionCorrectionIterations : nil
            options.positionCorrectionCheckerboard = parallaxPositionCorrectionCheckerboard
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Upsampling aligned virtual-BF images…"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxSubpixelReconstructor.reconstruct(
                    preprocessing: preprocessing, alignment: alignment,
                    options: options, cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxSubpixel = result
            showParallaxProduct(.subpixel)   // v2.5 step 3e: one publish site
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = String(
                format: "Parallax KDE ✓  ×%.2f · %.4f Å/px · %d × %d%@",
                result.upsampleFactor, result.outputSamplingAngstrom,
                result.croppedBF.height, result.croppedBF.width,
                result.positionCorrectionScores.isEmpty
                    ? "" : " · position corrected"
            )
        } catch ParallaxSubpixelReconstructor.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax KDE cancelled; aligned result retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }

    func computeParallaxDepthSections() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment,
              let fit = parallaxHigherOrderFit else {
            presentComputeFailure(SimpleError("Fit parallax aberrations before depth sectioning."))
            return
        }
        guard parallaxDepthPlaneCount > 0, parallaxDepthPlaneCount <= 257,
              parallaxDepthStartAngstrom.isFinite,
              parallaxDepthEndAngstrom.isFinite else {
            presentComputeFailure(SimpleError("Use 1–257 finite parallax depth planes."))
            return
        }
        let depths: [Double]
        if parallaxDepthPlaneCount == 1 {
            depths = [parallaxDepthStartAngstrom]
        } else {
            depths = (0..<parallaxDepthPlaneCount).map { index in
                parallaxDepthStartAngstrom
                    + (parallaxDepthEndAngstrom - parallaxDepthStartAngstrom)
                    * Double(index) / Double(parallaxDepthPlaneCount - 1)
            }
        }
        var options = ParallaxDepthOptions()
        options.depthsAngstrom = depths
        options.useFullFit = parallaxDepthUseFullFit
        options.informationLimitInvAngstrom = parallaxDepthInformationLimit > 0
            ? parallaxDepthInformationLimit : nil
        options.informationPower = parallaxDepthInformationPower
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax depth sectioning", status: "Computing depth planes…",
            totalUnits: depths.count
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Computing depth planes…"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxDepthSectioner.section(
                    preprocessing: preprocessing, alignment: alignment, fit: fit,
                    options: options, cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxDepth = result
            parallaxDepthSelectedIndex = depths.indices.min {
                abs(depths[$0]) < abs(depths[$1])
            } ?? 0
            showParallaxProduct(.depth)
            statusText = "Parallax depth sectioning ✓  \(depths.count) planes"
        } catch ParallaxDepthSectioner.DepthError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax depth sectioning cancelled; prior products retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }

    func runSingleslicePtychography() async {
        // As in `prepareParallaxPreview`: take the view from the array, so the
        // reader is told where the shape it is given sits in the file.
        guard let source = reader, let fourD, let descriptor else {
            presentComputeFailure(SimpleError("Open a 4D dataset before ptychographic reconstruction."))
            return
        }
        let view = fourD.view
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibrationSession.calibration, apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: calibrationSession.acceleratingVoltage
            )
        } catch {
            presentComputeFailure(error)
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Single-slice ptychography", status: "Preparing diffraction amplitudes…",
            totalUnits: descriptor.ry + max(1, ptychography.iterations)
        )
        defer { finishCancellableOperation(token) }
        do {
            let prepareProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction * 0.3,
                        status: "Preparing diffraction amplitudes…"
                    )
                }
            }
            let input = try await PtychographyPreparer.prepare(
                source: source, view: view, calibration: physical,
                probeRadiusPixels: aperture.outer, cancellation: token,
                progress: prepareProgress
            )
            var options = SingleslicePtychographyOptions()
            options.method = ptychography.method
            options.iterations = ptychography.iterations
            options.stepSize = ptychography.stepSize
            options.projectionParameter = ptychography.projectionParameter
            options.normalizationMinimum = ptychography.normalizationMinimum
            options.fixProbe = ptychography.fixProbe
            options.constrainObjectAmplitude = ptychography.constrainObjectAmplitude
            options.purePhaseObject = ptychography.purePhaseObject
            options.fixProbeCenterOfMass = ptychography.fixProbeCenterOfMass
            options.constrainProbeAmplitude = ptychography.constrainProbeAmplitude
            options.probeAmplitudeRelativeRadius = ptychography.probeAmplitudeRadius
            options.probeAmplitudeRelativeWidth = ptychography.probeAmplitudeWidth
            let reconstructProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: 0.3 + fraction * 0.7,
                        status: "Reconstructing object/probe…"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try SingleslicePtychography.reconstruct(
                    input: input, options: options, cancellation: token,
                    progress: reconstructProgress
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            singleslicePtychography = result
            showParallaxProduct(.iterativePhase)
            statusText = String(
                format: "Single-slice ptychography ✓  %@ · %d iterations · error %.6f",
                result.options.method.rawValue,
                result.errorHistory.count, result.errorHistory.last ?? .nan
            )
        } catch SingleslicePtychography.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Single-slice ptychography cancelled; prior result retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }

    var availableParallaxProducts: [ParallaxResultProduct] {
        ParallaxResultProduct.allCases.filter {
            switch $0 {
            case .preprocess: parallaxPreprocess != nil
            case .alignment: parallaxAlignment != nil
            case .subpixel: parallaxSubpixel != nil
            case .correctedPhase: parallaxCorrection != nil
            case .depth: parallaxDepth != nil
            case .iterativePhase, .iterativeAmplitude,
                 .iterativeProbePhase, .iterativeProbeAmplitude:
                singleslicePtychography != nil
            }
        }
    }

    /// The one publish site for every parallax and ptychography product: the
    /// image and its label are chosen together (v2.5 step 3e, condition 2).
    func showParallaxProduct(_ product: ParallaxResultProduct) {
        let image: FloatImage?
        let kind: String, name: String, units: String
        switch product {
        case .preprocess:
            image = parallaxPreprocess?.previewImage
            (kind, name, units) = ("parallax_preprocess", "Parallax incoherent BF preview", "normalized_intensity")
        case .alignment:
            image = parallaxAlignment?.previewImage
            (kind, name, units) = ("parallax_alignment", "Parallax aligned BF", "normalized_intensity")
        case .subpixel:
            image = parallaxSubpixel?.croppedBF
            (kind, name, units) = ("parallax_subpixel_bf", "Parallax subpixel BF", "normalized_intensity")
        case .correctedPhase:
            image = parallaxCorrection?.correctedPhase
            (kind, name, units) = ("parallax_corrected_phase", "Parallax corrected phase", "arbitrary_phase")
        case .depth:
            image = parallaxDepth?.croppedPlane(at: parallaxDepthSelectedIndex)
            let depth = parallaxDepth?.depthsAngstrom[parallaxDepthSelectedIndex] ?? 0
            (kind, name, units) = ("parallax_depth", String(format: "Parallax depth %.1f Å", depth), "arbitrary_phase")
        case .iterativePhase:
            image = singleslicePtychography?.objectPhase()
            (kind, name, units) = ("ptychography_object_phase", "Ptychography object phase", "rad")
        case .iterativeAmplitude:
            image = singleslicePtychography?.objectAmplitude()
            (kind, name, units) = ("ptychography_object_amplitude", "Ptychography object amplitude", "dimensionless")
        case .iterativeProbePhase:
            image = singleslicePtychography?.probePhase()
            (kind, name, units) = ("ptychography_probe_phase", "Ptychography probe phase", "rad")
        case .iterativeProbeAmplitude:
            image = singleslicePtychography?.probeAmplitude()
            (kind, name, units) = ("ptychography_probe_amplitude", "Ptychography probe amplitude", "dimensionless")
        }
        guard let image else { return }
        parallaxResultProduct = product
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: .scalar(image))
    }

    func selectParallaxDepthPlane(_ index: Int) {
        guard let depth = parallaxDepth, depth.depthsAngstrom.indices.contains(index) else {
            return
        }
        parallaxDepthSelectedIndex = index
        showParallaxProduct(.depth)
    }

    func correctParallaxPhase() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment,
              let fit = parallaxHigherOrderFit else {
            presentComputeFailure(SimpleError("Fit parallax aberrations before phase correction."))
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax phase correction", status: "Applying aberration CTF…",
            totalUnits: alignment.stackHeight
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxAberrationCorrectionOptions()
            options.qLowpassInvAngstrom = parallaxQLowpassInvAngstrom != 0
                ? parallaxQLowpassInvAngstrom : nil
            options.qHighpassInvAngstrom = parallaxQHighpassInvAngstrom != 0
                ? parallaxQHighpassInvAngstrom : nil
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAberrationCorrector.correct(
                    preprocessing: preprocessing, alignment: alignment,
                    fit: fit, options: options, cancellation: token
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxCorrection = result
            showParallaxProduct(.correctedPhase)   // v2.5 step 3e: one publish site
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = "Parallax phase correction ✓  full fitted CTF · DC removed"
        } catch ParallaxAberrationCorrector.CorrectionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax phase correction cancelled; fit retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
        }
    }
}
