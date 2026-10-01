//
//  AppState+PhaseContrast.swift
//  Role: the Parallax and single-slice ptychography orchestration —
//        preview, per-level alignment, aberration fit, BF upsampling, depth
//        sections, phase correction, product selection.
//        A placement seam out of `AppState.swift`: no logic touched, only
//        `private` → internal on the members another file still reaches.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif


extension AppState {
    /// The working limit every phase-contrast stage refuses above: half of RAM less the cube the user chose to keep in
    /// memory (`DatasetResidency.byteCount`, 0 when streamed), never below the 1 GiB floor.
    var phaseContrastWorkingLimitBytes: Int {
        PhaseContrastMemoryBudget.workingLimitBytes(residentCubeBytes: residency.isResident ? residency.byteCount : 0)
    }

    /// A refusal names the resident cube when it reduced the limit; any other failure is presented as before.
    func presentPhaseContrastFailure(_ error: Error) {
        let resident = residency.isResident ? residency.byteCount : 0
        if resident > 0, PhaseContrastMemoryBudget.isMemoryRefusal(error) {
            presentComputeFailure(SimpleError(PhaseContrastMemoryBudget.refusalMessage(error, residentCubeBytes: resident)))
        } else {
            presentComputeFailure(error)
        }
    }

    /// First parallax slice: build and preview py4DSTEM's normalized virtual-BF
    /// stack and incoherent BF initialization. No iterative reconstruction is
    /// performed or implied by this operation.
    func prepareParallaxPreview() async {
        // The view the array actually reads, not a descriptor assembled beside
        // it: a crop and the shape it produces must travel together.
        guard let source = datasetSession.reader,
              let fourD = datasetSession.fourD, let descriptor else { return }
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
            presentPhaseContrastFailure(error)
            return
        }

        let epoch = datasetSession.epoch
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
            var preprocessOptions = ParallaxPreprocessOptions()
            preprocessOptions.maxStackBytes = phaseContrastWorkingLimitBytes
            let result = try await ParallaxPreprocessor.run(
                source: source, view: view, calibration: physical, options: preprocessOptions,
                cancellation: token, progress: progressUpdate
            )
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.parallaxPreprocess = result
            phaseContrast.parallaxAlignment = nil
            showParallaxProduct(.preprocess)   // one publish site
            resultPresentation.resultGamma = 1
            resultPresentation.displayRangeLo = 0
            resultPresentation.displayRangeHi = 1
            resultPresentation.bumpResultVersion()
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }

    /// Run the next source-locked coarse-to-fine bin with factor-8 matrix-DFT
    /// correlation. The last completed level remains published until the next
    /// one succeeds and passes the operation/dataset publication guards.
    func alignParallaxNextLevel() async {
        guard let preprocessing = phaseContrast.parallaxPreprocess else {
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
        let completed = phaseContrast.parallaxAlignment?.completedBins ?? []
        guard completed.count < schedule.count else {
            presentComputeFailure(ParallaxAligner.AlignmentError.alignmentComplete)
            return
        }
        let bin = schedule[completed.count]
        guard phaseContrast.parallaxAlignment == nil
                || Array(schedule.prefix(completed.count)) == completed else {
            presentComputeFailure(SimpleError("Reset the stale parallax alignment before continuing."))
            return
        }
        let groups = ParallaxAligner.groups(
            detectorIndices: preprocessing.detectorIndices, alignmentBin: bin
        )
        let epoch = datasetSession.epoch
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
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes
            options.upsampleFactor = 8
            let prior = phaseContrast.parallaxAlignment
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAligner.alignNextLevel(
                    preprocessing: preprocessing, previous: prior, options: options,
                    cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.parallaxAlignment = result
            showParallaxProduct(.alignment)   // one publish site
            resultPresentation.resultGamma = 1
            resultPresentation.displayRangeLo = 0
            resultPresentation.displayRangeHi = 1
            resultPresentation.bumpResultVersion()
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }

    func resetParallaxAlignment() {
        guard !isBusy, phaseContrast.parallaxPreprocess != nil else { return }
        phaseContrast.parallaxAlignment = nil
        showParallaxProduct(.preprocess)   // one publish site
        resultPresentation.resultGamma = 1
        resultPresentation.displayRangeLo = 0
        resultPresentation.displayRangeHi = 1
        resultPresentation.bumpResultVersion()
        statusText = "Parallax alignment reset to the preprocessed preview"
    }

    func fitParallaxAberrations() {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment else {
            presentComputeFailure(SimpleError("Complete parallax preprocessing and alignment first."))
            return
        }
        do {
            let result = try ParallaxAberrationFitter.fitHigherOrder(
                preprocessing: preprocessing, alignment: alignment
            )
            phaseContrast.parallaxAberrationFit = result.lowOrder
            phaseContrast.parallaxHigherOrderFit = result
            // The fit's RMS residual is not shown (lane R4, 2026-10-01): the alignment hands the fit an exactly linear shift field
            // (py4DSTEM's regularised shifts, parallax.py:1380-1384), so the residual is 0.0000 Å on every dataset - "RMS 0.0000 Å → 0.0000 Å"
            // was a real zero by construction (graphene: 4e-7 Å), a number that cannot move.
            statusText = String(
                format: "Recursive aberration fit ✓  %d terms · rotation %.2f°",
                result.terms.count,
                result.lowOrder.rotationRad * 180 / .pi
            )
        } catch {
            presentPhaseContrastFailure(error)
        }
    }

    func upsampleParallaxBF() async {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment, alignment.isComplete else {
            presentComputeFailure(SimpleError("Complete parallax alignment before KDE upsampling."))
            return
        }
        let epoch = datasetSession.epoch
        let token = beginCancellableOperation(
            "Parallax KDE", status: "Upsampling aligned virtual-BF images…",
            totalUnits: preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxSubpixelOptions()
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes
            options.upsampleFactor = phaseContrast.parallaxKDEUpsampleFactor > 0
                ? phaseContrast.parallaxKDEUpsampleFactor : nil
            options.kdeSigmaPixels = phaseContrast.parallaxKDESigmaPixels
            options.lowpassFilter = phaseContrast.parallaxKDELowpass
            options.lanczosOrder = phaseContrast.parallaxKDELanczosOrder > 0
                ? phaseContrast.parallaxKDELanczosOrder : nil
            options.positionCorrectionIterations = phaseContrast.parallaxPositionCorrectionIterations > 0
                ? phaseContrast.parallaxPositionCorrectionIterations : nil
            options.positionCorrectionCheckerboard = phaseContrast.parallaxPositionCorrectionCheckerboard
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.parallaxSubpixel = result
            showParallaxProduct(.subpixel)   // one publish site
            resultPresentation.resultGamma = 1
            resultPresentation.displayRangeLo = 0
            resultPresentation.displayRangeHi = 1
            resultPresentation.bumpResultVersion()
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }

    func computeParallaxDepthSections() async {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment,
              let fit = phaseContrast.parallaxHigherOrderFit else {
            presentComputeFailure(SimpleError("Fit parallax aberrations before depth sectioning."))
            return
        }
        guard phaseContrast.parallaxDepthPlaneCount > 0, phaseContrast.parallaxDepthPlaneCount <= 257,
              phaseContrast.parallaxDepthStartAngstrom.isFinite,
              phaseContrast.parallaxDepthEndAngstrom.isFinite else {
            presentComputeFailure(SimpleError("Use 1–257 finite parallax depth planes."))
            return
        }
        let depths: [Double]
        if phaseContrast.parallaxDepthPlaneCount == 1 {
            depths = [phaseContrast.parallaxDepthStartAngstrom]
        } else {
            depths = (0..<phaseContrast.parallaxDepthPlaneCount).map { index in
                phaseContrast.parallaxDepthStartAngstrom
                    + (phaseContrast.parallaxDepthEndAngstrom - phaseContrast.parallaxDepthStartAngstrom)
                    * Double(index) / Double(phaseContrast.parallaxDepthPlaneCount - 1)
            }
        }
        var options = ParallaxDepthOptions()
        options.maxWorkingBytes = phaseContrastWorkingLimitBytes
        options.depthsAngstrom = depths
        options.useFullFit = phaseContrast.parallaxDepthUseFullFit
        options.informationLimitInvAngstrom = phaseContrast.parallaxDepthInformationLimit > 0
            ? phaseContrast.parallaxDepthInformationLimit : nil
        options.informationPower = phaseContrast.parallaxDepthInformationPower
        let epoch = datasetSession.epoch
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.parallaxDepth = result
            phaseContrast.parallaxDepthSelectedIndex = depths.indices.min {
                abs(depths[$0]) < abs(depths[$1])
            } ?? 0
            showParallaxProduct(.depth)
            statusText = "Parallax depth sectioning ✓  \(depths.count) planes"
        } catch ParallaxDepthSectioner.DepthError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax depth sectioning cancelled; prior products retained"
        } catch {
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }

    func runSingleslicePtychography() async {
        // As in `prepareParallaxPreview`: take the view from the array, so the
        // reader is told where the shape it is given sits in the file.
        guard let source = datasetSession.reader,
              let fourD = datasetSession.fourD, let descriptor else {
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
            presentPhaseContrastFailure(error)
            return
        }
        let epoch = datasetSession.epoch
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
            // The probe the run starts from is what the fields show (`PtychographySettings.probeAberrations`).
            let aberrations = ptychography.probeAberrations
            var prepareOptions = PtychographyPreparationOptions()
            prepareOptions.maxResidentBytes = phaseContrastWorkingLimitBytes
            let input = try await PtychographyPreparer.prepare(
                source: source, view: view, calibration: physical,
                probeRadiusPixels: aperture.outer, aberrations: aberrations, options: prepareOptions,
                cancellation: token, progress: prepareProgress
            )
            var options = SingleslicePtychographyOptions()
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes
            options.iterations = ptychography.iterations
            options.stepSize = ptychography.stepSize
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
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.singleslicePtychography = result
            showParallaxProduct(.iterativePhase)
            // What the run started from is read back from the RESULT (the input `prepare` built), not from the settings, so a
            // run that did not receive the fields cannot publish them.
            statusText = String(
                format: "Single-slice ptychography ✓  gradient descent · defocus %g Å · %d iterations · error %.6f",
                result.probeAberrations.defocusAngstrom,
                result.errorHistory.count, result.errorHistory.last ?? .nan
            )
        } catch SingleslicePtychography.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Single-slice ptychography cancelled; prior result retained"
        } catch {
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }

    var availableParallaxProducts: [ParallaxResultProduct] {
        ParallaxResultProduct.allCases.filter {
            switch $0 {
            case .preprocess: phaseContrast.parallaxPreprocess != nil
            case .alignment: phaseContrast.parallaxAlignment != nil
            case .subpixel: phaseContrast.parallaxSubpixel != nil
            case .correctedPhase: phaseContrast.parallaxCorrection != nil
            case .depth: phaseContrast.parallaxDepth != nil
            case .iterativePhase, .iterativeAmplitude,
                 .iterativeProbePhase, .iterativeProbeAmplitude:
                phaseContrast.singleslicePtychography != nil
            }
        }
    }

    /// " · defocus -600 Å": the defocus the retained reconstruction's probe started from, so the product says what it was made with.
    private var ptychographyProbeSuffix: String {
        phaseContrast.singleslicePtychographyProbe.map {
            String(format: " · defocus %g Å", $0.defocusAngstrom)
        } ?? ""
    }

    /// "Use Parallax Fit": write the probe fields from the parallax aberration fit (`PtychographySettings.useParallaxFit` holds
    /// the sign rule). Nothing runs; the fields are what the next reconstruction starts from.
    func usePtychographyProbeFromParallaxFit() {
        guard let lowOrder = phaseContrast.parallaxAberrationFit else { return }
        ptychography.useParallaxFit(lowOrder: lowOrder)
        // The sign rule (defocus = -C1) holds on the rotation branch the fit used; the ptychography runs with the calibrated
        // rotation, which nothing here checks. Both are shown so the reader can judge.
        // The angle between them is printed, not judged (no 180° case has been measured; the auto-flip is the owner's card R1 c).
        let fitDegrees = lowOrder.rotationRad * 180 / .pi
        let calibrated = calibrationSession.calibration.rotationRad.map { rad -> String in
            let degrees = Double(rad) * 180 / .pi
            let apart = abs((degrees - fitDegrees).truncatingRemainder(dividingBy: 360))
            return String(format: "%.2f°, %.2f° apart; the sign flips at 180°", degrees, min(apart, 360 - apart))
        } ?? "not set; the sign holds on the fit's rotation"
        statusText = String(
            format: "Probe seeded from the parallax fit ✓  defocus %g Å · C12 %g / %g Å · fit rotation %.2f°, calibrated rotation %@",
            ptychography.defocusAngstrom, ptychography.c12aAngstrom, ptychography.c12bAngstrom,
            fitDegrees, calibrated
        )
    }

    /// The one publish site for every parallax and ptychography product: the
    /// image and its label are chosen together.
    func showParallaxProduct(_ product: ParallaxResultProduct) {
        let image: FloatImage?
        let kind: String, name: String, units: String
        switch product {
        case .preprocess:
            image = phaseContrast.parallaxPreprocess?.previewImage
            (kind, name, units) = ("parallax_preprocess", "Parallax incoherent BF preview", "normalized_intensity")
        case .alignment:
            image = phaseContrast.parallaxAlignment?.previewImage
            (kind, name, units) = ("parallax_alignment", "Parallax aligned BF", "normalized_intensity")
        case .subpixel:
            image = phaseContrast.parallaxSubpixel?.croppedBF
            (kind, name, units) = ("parallax_subpixel_bf", "Parallax subpixel BF", "normalized_intensity")
        case .correctedPhase:
            image = phaseContrast.parallaxCorrection?.correctedPhase
            (kind, name, units) = ("parallax_corrected_phase", "Parallax corrected phase", "arbitrary_phase")
        case .depth:
            image = phaseContrast.parallaxDepth?.croppedPlane(at: phaseContrast.parallaxDepthSelectedIndex)
            let depth = phaseContrast.parallaxDepth?.depthsAngstrom[phaseContrast.parallaxDepthSelectedIndex] ?? 0
            (kind, name, units) = ("parallax_depth", String(format: "Parallax depth %.1f Å", depth), "arbitrary_phase")
        case .iterativePhase:
            image = phaseContrast.singleslicePtychography?.objectPhase()
            (kind, name, units) = ("ptychography_object_phase", "Ptychography object phase" + ptychographyProbeSuffix, "rad")
        case .iterativeAmplitude:
            image = phaseContrast.singleslicePtychography?.objectAmplitude()
            (kind, name, units) = ("ptychography_object_amplitude", "Ptychography object amplitude" + ptychographyProbeSuffix, "dimensionless")
        case .iterativeProbePhase:
            image = phaseContrast.singleslicePtychography?.probePhase()
            (kind, name, units) = ("ptychography_probe_phase", "Ptychography probe phase" + ptychographyProbeSuffix, "rad")
        case .iterativeProbeAmplitude:
            image = phaseContrast.singleslicePtychography?.probeAmplitude()
            (kind, name, units) = ("ptychography_probe_amplitude", "Ptychography probe amplitude" + ptychographyProbeSuffix, "dimensionless")
        }
        guard let image else { return }
        phaseContrast.parallaxResultProduct = product
        resultPresentation.resultGamma = 1
        resultPresentation.displayRangeLo = 0
        resultPresentation.displayRangeHi = 1
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: .scalar(image))
    }

    func selectParallaxDepthPlane(_ index: Int) {
        guard let depth = phaseContrast.parallaxDepth, depth.depthsAngstrom.indices.contains(index) else {
            return
        }
        phaseContrast.parallaxDepthSelectedIndex = index
        showParallaxProduct(.depth)
    }

    func correctParallaxPhase() async {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment,
              let fit = phaseContrast.parallaxHigherOrderFit else {
            presentComputeFailure(SimpleError("Fit parallax aberrations before phase correction."))
            return
        }
        let epoch = datasetSession.epoch
        let token = beginCancellableOperation(
            "Parallax phase correction", status: "Applying aberration CTF…",
            totalUnits: alignment.stackHeight
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxAberrationCorrectionOptions()
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes / 2   // keeps its half share
            options.qLowpassInvAngstrom = phaseContrast.parallaxQLowpassInvAngstrom != 0
                ? phaseContrast.parallaxQLowpassInvAngstrom : nil
            options.qHighpassInvAngstrom = phaseContrast.parallaxQHighpassInvAngstrom != 0
                ? phaseContrast.parallaxQHighpassInvAngstrom : nil
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAberrationCorrector.correct(
                    preprocessing: preprocessing, alignment: alignment,
                    fit: fit, options: options, cancellation: token
                )
            }.value
            guard isCurrentOperation(token), datasetSession.epoch == epoch,
                  !token.isCancelled else { return }
            phaseContrast.parallaxCorrection = result
            showParallaxProduct(.correctedPhase)   // one publish site
            resultPresentation.resultGamma = 1
            resultPresentation.displayRangeLo = 0
            resultPresentation.displayRangeHi = 1
            resultPresentation.bumpResultVersion()
            statusText = "Parallax phase correction ✓  full fitted CTF · DC removed"
        } catch ParallaxAberrationCorrector.CorrectionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax phase correction cancelled; fit retained"
        } catch {
            guard isCurrentOperation(token), datasetSession.epoch == epoch else { return }
            presentPhaseContrastFailure(error)
        }
    }
}

/// App-level: names every stage's error type, which the Core harness groups do not all compile together.
extension PhaseContrastMemoryBudget {
    /// A memory refusal from any phase-contrast stage (the stages' own enums stay as they are: the real-probe tools
    /// match their `(bytes, limit)` payloads).
    nonisolated static func isMemoryRefusal(_ error: Error) -> Bool {
        if case ParallaxPreprocessor.PreprocessError.stackTooLarge = error { return true }
        if case ParallaxAligner.AlignmentError.memoryLimit = error { return true }
        if case ParallaxSubpixelReconstructor.ReconstructionError.memoryLimit = error { return true }
        if case ParallaxDepthSectioner.DepthError.memoryLimit = error { return true }
        if case ParallaxAberrationCorrector.CorrectionError.memoryLimit = error { return true }
        if case SingleslicePtychography.ReconstructionError.memoryLimit = error { return true }
        return false
    }

    /// The refusal's own text, plus — when a resident cube reduced the limit — what the limit is made of.
    nonisolated static func refusalMessage(_ error: Error, residentCubeBytes: Int) -> String {
        let base = error.localizedDescription
        guard residentCubeBytes > 0, isMemoryRefusal(error) else { return base }
        let cube = ByteCountFormatter.string(fromByteCount: Int64(residentCubeBytes), countStyle: .file)
        return base + " The limit is half of RAM less the \(cube) cube kept in memory."
    }
}
