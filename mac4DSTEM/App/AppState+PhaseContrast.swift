//
//  AppState+PhaseContrast.swift
//  Role: the Parallax and single-slice ptychography orchestration —
//        preview, per-level alignment, aberration fit, BF upsampling, depth
//        sections, phase correction, product selection.
//        A placement seam out of `AppState.swift`: no logic touched, only
//        `private` → internal on the members another file still reaches.
//

import Foundation
import ShellMetal
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import struct CuboParallax.ParallaxPhysicalShift
import struct CuboParallax.ParallaxAberrationFitResult
import struct CuboParallax.ParallaxHigherOrderAberrationFitResult
import struct CuboParallax.ParallaxHigherOrderAberrationOptions
import struct CuboParallax.ParallaxLowOrderAberrationOptions
import struct CuboParallax.ParallaxAberrationTerm
import enum CuboParallax.ParallaxAberrationFitMethod
#endif

extension AppState {
    /// The working limit every phase-contrast stage refuses above: half of RAM less the cube the user chose to keep in
    /// memory (`DatasetResidency.byteCount`, 0 when streamed) and less what earlier stages still hold
    /// (`phaseContrastHeldBytes`), never below the 1 GiB floor.
    var phaseContrastWorkingLimitBytes: Int { phaseContrastWorkingLimitBytes(heldBytes: phaseContrastHeldBytes) }

    func phaseContrastWorkingLimitBytes(heldBytes: Int) -> Int {
        PhaseContrastMemoryBudget.workingLimitBytes(residentCubeBytes: residency.isResident ? residency.byteCount : 0,
                                                    heldProductBytes: heldBytes)
    }

    /// The bytes earlier phase-contrast stages hold while the next one runs (review d2, 2026-10-02; the owner of the products
    /// is `phaseContrast`, this only reads them): the preprocessed stacks and the published alignment level, which every later
    /// stage leaves in memory and none counted. The products after the fit (KDE image, depth planes, correction, ptychography)
    /// are not counted.
    var phaseContrastHeldBytes: Int {
        (phaseContrast.parallaxPreprocess?.residentStackByteCount ?? 0)
            + (phaseContrast.parallaxAlignment?.heldByteCount ?? 0)
    }

    /// What the next alignment level's limit subtracts: the held stacks less what the level counts in its own peak because it
    /// reads them (the preprocessed stack at level 1, the published level's stack and masks after), so nothing counts twice.
    var parallaxAlignmentHeldBytes: Int {
        guard let preprocessing = phaseContrast.parallaxPreprocess else { return phaseContrastHeldBytes }
        return max(0, phaseContrastHeldBytes - ParallaxAligner.inputBytesCounted(
            preprocessing: preprocessing, previous: phaseContrast.parallaxAlignment))
    }

    /// A re-preview replaces both parallax products, so it releases them BEFORE its run and returns the limit read after the
    /// release (refuter fix round, 2026-10-02): otherwise the new stacks got half − (old preview 2S + old alignment 2S + planes)
    /// and a dataset whose stack passed once (S ≤ half/2) was refused on every second preview once S > half/6, with no release
    /// path short of a calibration or dataset change. The alignment goes first (its didSet drops the fit, KDE, depth and
    /// correction, as a successful preview always did). Cost: a cancelled or refused re-preview leaves no preview (the status says so).
    func releaseParallaxProductsForPreview() -> (limitBytes: Int, releasedPreview: Bool) {
        let released = phaseContrast.parallaxPreprocess != nil
        phaseContrast.parallaxAlignment = nil
        phaseContrast.parallaxPreprocess = nil
        return (phaseContrastWorkingLimitBytes, released)
    }

    /// A refusal names the resident cube and the held phase-contrast stacks when they reduced the limit (`heldBytes`: what
    /// the refused stage's limit subtracted, `phaseContrastHeldBytes` unless the stage counted some of it itself); any other
    /// failure is presented as before.
    func presentPhaseContrastFailure(_ error: Error, heldBytes: Int? = nil) {
        let resident = residency.isResident ? residency.byteCount : 0
        let held = heldBytes ?? phaseContrastHeldBytes
        if resident > 0 || held > 0, PhaseContrastMemoryBudget.isMemoryRefusal(error) {
            presentComputeFailure(SimpleError(PhaseContrastMemoryBudget.refusalMessage(
                error, residentCubeBytes: resident, heldProductBytes: held)))
        } else {
            presentComputeFailure(error)
        }
    }

    /// First parallax slice: build and preview py4DSTEM's normalized virtual-BF
    /// stack and incoherent BF initialization. No iterative reconstruction is
    /// performed or implied by this operation.
    ///
    /// Every parallax stage returns the typed run verdict (`runVirtualDetector`'s
    /// note) and, when it publishes, rewrites the task's one replay step from
    /// what is held then (`recordParallaxStep`).
    @discardableResult
    func prepareParallaxPreview(replaying: Bool = false) async -> AnalysisRunOutcome {
        // The view the array actually reads, not a descriptor assembled beside
        // it: a crop and the shape it produces must travel together.
        guard let source = datasetSession.reader,
              let fourD = datasetSession.fourD, let descriptor else {
            return .failed("Open a 4D dataset before parallax preprocessing.")
        }
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
            return .failed(error.localizedDescription)
        }

        let epoch = datasetSession.epoch
        // Refused before the release below: a refused run must not discard the parallax products it would replace.
        guard !promoteRunRefusesUserRuns else {
            statusText = "Parallax preprocessing not started — the promote run is replaying the recipe; wait for it, or cancel it first"
            return .failed(statusText)
        }
        let release = releaseParallaxProductsForPreview()
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
            preprocessOptions.maxStackBytes = release.limitBytes
            let result = try await ParallaxPreprocessor.run(
                source: source, view: view, calibration: physical, options: preprocessOptions,
                cancellation: token, progress: progressUpdate
            )
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
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
            recordParallaxStep(replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch ParallaxPreprocessor.PreprocessError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = release.releasedPreview
                ? "Parallax preprocessing cancelled; the previous preview was released"
                : "Parallax preprocessing cancelled"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// Rewrite parallax's one replay step from what the task holds now
    /// (`PhaseContrastProduct.parallaxReplayPlan`): every stage calls this
    /// after it publishes, so a re-run earlier stage drops the later ones its
    /// cascade cleared. A replayed stage records nothing (`recordReplayStep`).
    func recordParallaxStep(replaying: Bool, stampsDisplayedProduct: Bool) {
        guard let plan = phaseContrast.parallaxReplayPlan else { return }
        recordReplayStep(kind: "parallax", parameters: plan.recordedParameters,
                         replaying: replaying, stampsDisplayedProduct: stampsDisplayedProduct)
    }

    /// Run the next source-locked coarse-to-fine bin with factor-8 matrix-DFT
    /// correlation. The last completed level remains published until the next
    /// one succeeds and passes the operation/dataset publication guards.
    @discardableResult
    func alignParallaxNextLevel(replaying: Bool = false) async -> AnalysisRunOutcome {
        func refuse(_ error: Error) -> AnalysisRunOutcome {
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
        guard let preprocessing = phaseContrast.parallaxPreprocess else {
            return refuse(SimpleError("Prepare the parallax preview before alignment."))
        }
        let schedule = ParallaxAligner.defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard !schedule.isEmpty else {
            return refuse(SimpleError("The bright-field mask cannot form an alignment level."))
        }
        let completed = phaseContrast.parallaxAlignment?.completedBins ?? []
        guard completed.count < schedule.count else {
            return refuse(ParallaxAligner.AlignmentError.alignmentComplete)
        }
        let bin = schedule[completed.count]
        guard phaseContrast.parallaxAlignment == nil
                || Array(schedule.prefix(completed.count)) == completed else {
            return refuse(SimpleError("Reset the stale parallax alignment before continuing."))
        }
        let groups = ParallaxAligner.groups(
            detectorIndices: preprocessing.detectorIndices, alignmentBin: bin
        )
        let alignmentHeldBytes = parallaxAlignmentHeldBytes
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
            let prior = phaseContrast.parallaxAlignment
            // The level counts what it reads (the preprocessed stack, or the prior's stack and masks) in its own peak.
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes(heldBytes: alignmentHeldBytes)
            options.upsampleFactor = 8
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAligner.alignNextLevel(
                    preprocessing: preprocessing, previous: prior, options: options,
                    cancellation: token, progress: progressUpdate
                )
            }.value
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
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
            recordParallaxStep(replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch ParallaxAligner.AlignmentError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = "Parallax alignment bin \(bin) cancelled; last completed level retained"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error, heldBytes: alignmentHeldBytes)
            return .failed(error.localizedDescription)
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
        // The reset drops every stage after the preprocess (`PhaseContrastProduct`'s cascades) with no stage
        // publishing after it: rewrite the step, or a promote would replay the alignment the user threw away.
        recordParallaxStep(replaying: false, stampsDisplayedProduct: true)
    }

    @discardableResult
    func fitParallaxAberrations(replaying: Bool = false) -> AnalysisRunOutcome {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment else {
            let reason = "Complete parallax preprocessing and alignment first."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        // Synchronous, so it takes no operation and `isBusy` does not hold it off between replayed steps;
        // a fit now records, and mid-promote it would write the recipe and clear the replayed later stages.
        guard !promoteRunRefusesUserRuns else {
            statusText = "Aberration fit not started — the promote run is replaying the recipe; wait for it, or cancel it first"
            return .failed(statusText)
        }
        let began = ContinuousClock.now
        do {
            let result = try ParallaxAberrationFitter.fitHigherOrder(
                preprocessing: preprocessing, alignment: alignment
            )
            phaseContrast.parallaxAberrationFit = result.lowOrder
            phaseContrast.parallaxHigherOrderFit = result
            recordInstantRun("Aberration fit", since: began)
            // The fit's RMS residual is not shown (lane R4, 2026-10-01): the alignment hands the fit an exactly linear shift field
            // (py4DSTEM's regularised shifts, parallax.py:1380-1384), so the residual is 0.0000 Å on every dataset - "RMS 0.0000 Å → 0.0000 Å"
            // was a real zero by construction (graphene: 4e-7 Å), a number that cannot move.
            statusText = String(
                format: "Recursive aberration fit ✓  %d terms · rotation %@",
                result.terms.count,
                RQRotationConvention.degreesText(result.lowOrder.rotationRad * 180 / .pi, decimals: 2)
            )
            // The fit publishes no image. The parallax image on screen names the new step only while its
            // stage is still held: a re-fit drops the correction and the depth sections, and a map of either
            // left on screen must not be credited to a step that no longer carries that stage.
            recordParallaxStep(replaying: replaying,
                               stampsDisplayedProduct: availableParallaxProducts.contains(phaseContrast.parallaxResultProduct))
            return .published
        } catch {
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func upsampleParallaxBF(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment, alignment.isComplete else {
            let reason = "Complete parallax alignment before KDE upsampling."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        let controls = phaseContrast.parallaxSubpixelSettings
        let epoch = datasetSession.epoch
        let token = beginCancellableOperation(
            "Parallax KDE", status: "Upsampling aligned virtual-BF images…",
            totalUnits: preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxSubpixelOptions()
            options.maxWorkingBytes = phaseContrastWorkingLimitBytes
            // From `controls`, read once above: the record says what this run was handed.
            options.upsampleFactor = controls.upsampleFactor > 0 ? controls.upsampleFactor : nil
            options.kdeSigmaPixels = controls.kdeSigmaPixels
            options.lowpassFilter = controls.lowpass
            options.lanczosOrder = controls.lanczosOrder > 0 ? controls.lanczosOrder : nil
            options.positionCorrectionIterations = controls.positionCorrectionIterations > 0
                ? controls.positionCorrectionIterations : nil
            options.positionCorrectionCheckerboard = controls.positionCorrectionCheckerboard
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
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
            phaseContrast.parallaxSubpixel = result
            phaseContrast.parallaxSubpixelControls = controls
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
            recordParallaxStep(replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch ParallaxSubpixelReconstructor.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = "Parallax KDE cancelled; aligned result retained"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func computeParallaxDepthSections(replaying: Bool = false) async -> AnalysisRunOutcome {
        func refuse(_ reason: String) -> AnalysisRunOutcome {
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment,
              let fit = phaseContrast.parallaxHigherOrderFit else {
            return refuse("Fit parallax aberrations before depth sectioning.")
        }
        // Read once: the options below and the record are this one value.
        let controls = phaseContrast.parallaxDepthSettings
        guard controls.planeCount > 0, controls.planeCount <= 257,
              controls.startAngstrom.isFinite, controls.endAngstrom.isFinite else {
            return refuse("Use 1–257 finite parallax depth planes.")
        }
        let depths: [Double]
        if controls.planeCount == 1 {
            depths = [controls.startAngstrom]
        } else {
            depths = (0..<controls.planeCount).map { index in
                controls.startAngstrom
                    + (controls.endAngstrom - controls.startAngstrom)
                    * Double(index) / Double(controls.planeCount - 1)
            }
        }
        var options = ParallaxDepthOptions()
        options.maxWorkingBytes = phaseContrastWorkingLimitBytes
        options.depthsAngstrom = depths
        options.useFullFit = controls.useFullFit
        options.informationLimitInvAngstrom = controls.informationLimitInvAngstrom > 0
            ? controls.informationLimitInvAngstrom : nil
        options.informationPower = controls.informationPower
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
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
            phaseContrast.parallaxDepth = result
            phaseContrast.parallaxDepthControls = controls
            phaseContrast.parallaxDepthSelectedIndex = depths.indices.min {
                abs(depths[$0]) < abs(depths[$1])
            } ?? 0
            showParallaxProduct(.depth)
            statusText = "Parallax depth sectioning ✓  \(depths.count) planes"
            recordParallaxStep(replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch ParallaxDepthSectioner.DepthError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = "Parallax depth sectioning cancelled; prior products retained"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// Returns the typed run verdict (`runVirtualDetector`'s note); a published
    /// run records its replay step (`PtychographyReplayPlan.recordedParameters`)
    /// from what it ran with: the options it handed the reconstructor, the
    /// probe `prepare` received, the probe radius and the resolved calibration.
    @discardableResult
    func runSingleslicePtychography(replaying: Bool = false) async -> AnalysisRunOutcome {
        // As in `prepareParallaxPreview`: take the view from the array, so the
        // reader is told where the shape it is given sits in the file.
        guard let source = datasetSession.reader,
              let fourD = datasetSession.fourD, let descriptor else {
            let reason = "Open a 4D dataset before ptychographic reconstruction."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
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
            return .failed(error.localizedDescription)
        }
        let probeRadiusPixels = aperture.outer
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
                probeRadiusPixels: probeRadiusPixels, aberrations: aberrations, options: prepareOptions,
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
                try PtychographyReconstructor.reconstruct(
                    input: input, options: options, cancellation: token,
                    progress: reconstructProgress
                )
            }.value
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
            phaseContrast.singleslicePtychography = result
            showParallaxProduct(.iterativePhase)
            // What the run started from is read back from the RESULT (the input `prepare` built), not from the settings, so a
            // run that did not receive the fields cannot publish them.
            statusText = String(
                format: "Single-slice ptychography ✓  gradient descent · defocus %g Å · %d iterations · error %.6f",
                result.probeAberrations.defocusAngstrom,
                result.errorHistory.count, result.errorHistory.last ?? .nan
            )
            // Recipe step, after the publish (as DPC): the product on screen is this run's. The probe's higher-order terms are
            // not carried: no control fills them (`PtychographySettings.setProbe`), so they are empty on every run.
            recordReplayStep(
                kind: "ptychography",
                parameters: ReplayStepPlan.PtychographyReplayPlan.recordedParameters(
                    settings: .init(options: result.options, probe: result.probeAberrations),
                    probeRadiusPixels: probeRadiusPixels, calibration: physical),
                replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch PtychographyReconstructor.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = "Single-slice ptychography cancelled; prior result retained"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
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
        // ONE convention, py4DSTEM's (ADR 040), for both angles and their difference: the fit's rotation already is py4DSTEM's
        // sign, the calibration is held in the app's (its negative). Measured (lane C Gate D, 2026-10-02): a detector rotation
        // planted at ±37° gives py4DSTEM DPC ∓37.000°, py4DSTEM Parallax ∓37.02°, this fit ∓37.03°, app calibration ±37.10° - so
        // printing the app's angle beside the fit read "74° apart" (2|θ|) for one branch, ≈180° near |θ| = 90°.
        let fitDegrees = lowOrder.rotationRad * 180 / .pi
        let calibrated = calibrationSession.calibration.rotationRad.map { rad -> String in
            let degrees = RQRotationConvention.displayDegrees(fromApp: rad)
            let apart = abs((degrees - fitDegrees).truncatingRemainder(dividingBy: 360))
            return String(format: "%@, %@ apart; the sign flips at 180°",
                          RQRotationConvention.degreesText(degrees, decimals: 2),
                          RQRotationConvention.degreesText(min(apart, 360 - apart), decimals: 2))
        } ?? "not set; the sign holds on the fit's rotation"
        statusText = String(
            format: "Probe seeded from the parallax fit ✓  defocus %g Å · C12 %g / %g Å · fit rotation %@, calibrated rotation %@",
            ptychography.defocusAngstrom, ptychography.c12aAngstrom, ptychography.c12bAngstrom,
            RQRotationConvention.degreesText(fitDegrees, decimals: 2), calibrated
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
        // A product names its own colormap: a diverging one left by iDPC or strain turned values near 1 solid red.
        resultPresentation.resultColormap = product.displayColormap
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: .scalar(image))
    }

    func selectParallaxDepthPlane(_ index: Int) {
        guard let depth = phaseContrast.parallaxDepth, depth.depthsAngstrom.indices.contains(index) else {
            return
        }
        phaseContrast.parallaxDepthSelectedIndex = index
        showParallaxProduct(.depth)
    }

    @discardableResult
    func correctParallaxPhase(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let preprocessing = phaseContrast.parallaxPreprocess,
              let alignment = phaseContrast.parallaxAlignment,
              let fit = phaseContrast.parallaxHigherOrderFit else {
            let reason = "Fit parallax aberrations before phase correction."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
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
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token), !token.isCancelled else { return .cancelled }
            phaseContrast.parallaxCorrection = result
            showParallaxProduct(.correctedPhase)   // one publish site
            resultPresentation.resultGamma = 1
            resultPresentation.displayRangeLo = 0
            resultPresentation.displayRangeHi = 1
            resultPresentation.bumpResultVersion()
            statusText = "Parallax phase correction ✓  full fitted CTF · DC removed"
            // The filters are recorded from the result, which carries them as run.
            recordParallaxStep(replaying: replaying, stampsDisplayedProduct: true)
            return .published
        } catch ParallaxAberrationCorrector.CorrectionError.cancelled {
            guard isCurrentOperation(token) else { return .cancelled }
            statusText = "Parallax phase correction cancelled; fit retained"
            return .cancelled
        } catch {
            guard datasetSession.epoch == epoch else { return .failed("The dataset changed during the run") }
            guard isCurrentOperation(token) else { return .cancelled }
            presentPhaseContrastFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// The replay of a recorded parallax step: every stage the rehearsal
    /// reached, in order, through the same entry points the user's clicks run,
    /// each with `replaying: true`. The first stage that does not publish
    /// stops the run with its verdict. The controls are already back
    /// (`PhaseContrastProduct.apply`).
    func runParallaxReplay(_ plan: ReplayStepPlan.ParallaxReplayPlan) async -> AnalysisRunOutcome {
        var outcome = await prepareParallaxPreview(replaying: true)
        guard outcome == .published else { return outcome }
        // A complete alignment replays to the end of THIS view's schedule (a
        // binned detector has a different one); otherwise the recorded count.
        var levels = 0
        while plan.alignmentComplete
                ? phaseContrast.parallaxAlignment?.isComplete != true
                : levels < plan.alignmentLevels {
            outcome = await alignParallaxNextLevel(replaying: true)
            guard outcome == .published else { return outcome }
            levels += 1
        }
        if plan.fitsAberrations {
            outcome = fitParallaxAberrations(replaying: true)
            guard outcome == .published else { return outcome }
        }
        if plan.subpixel != nil {
            outcome = await upsampleParallaxBF(replaying: true)
            guard outcome == .published else { return outcome }
        }
        if plan.correction != nil {
            outcome = await correctParallaxPhase(replaying: true)
            guard outcome == .published else { return outcome }
        }
        if plan.depth != nil {
            outcome = await computeParallaxDepthSections(replaying: true)
            guard outcome == .published else { return outcome }
        }
        return .published
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
        if case PtychographyReconstructor.ReconstructionError.memoryLimit = error { return true }
        return false
    }

    /// The refusal's own text, plus — when a resident cube or held phase-contrast stacks reduced the limit — what the limit
    /// is made of.
    nonisolated static func refusalMessage(_ error: Error, residentCubeBytes: Int, heldProductBytes: Int = 0) -> String {
        let base = error.localizedDescription
        guard residentCubeBytes > 0 || heldProductBytes > 0, isMemoryRefusal(error) else { return base }
        var parts = [String]()
        if residentCubeBytes > 0 {
            let cube = ByteCountFormatter.string(fromByteCount: Int64(residentCubeBytes), countStyle: .file)
            parts.append("the \(cube) cube kept in memory")
        }
        if heldProductBytes > 0 {
            let held = ByteCountFormatter.string(fromByteCount: Int64(heldProductBytes), countStyle: .file)
            parts.append("the \(held) the parallax preview and alignment already hold")
        }
        return base + " The limit is half of RAM less " + parts.joined(separator: " and ") + "."
    }
}

extension ParallaxResultProduct {
    /// Signed phase products read on a diverging map; brightness-like products (bright field, amplitudes) on the sequential one.
    var displayColormap: ColormapKind {
        switch self {
        case .correctedPhase, .depth, .iterativePhase, .iterativeProbePhase: return .rdbu
        case .preprocess, .alignment, .subpixel, .iterativeAmplitude, .iterativeProbeAmplitude: return .viridis
        }
    }
}
