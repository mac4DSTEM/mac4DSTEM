//
//  AppState+SpotDistortion.swift
//  Role: "Fit Distortion from Spots" (mac4DSTEM#210). A scan of one crystal has no ring for Fit Detector Ellipse; with the
//        matrix crystal known (the Orientation task's phase model) the matrix's own spots are the reference. The fit is
//        DiffractoKit's `matrixSpotDistortion`; nothing is changed until the user applies it.
//

import Foundation
import DiffractoOrientation
import DiffractoCore
#if canImport(DSTEMCore)
import DiffractoScattering
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    /// The most scan positions the fit reads: the distortion is one property of the detector, and a few thousand patterns fix it.
    nonisolated static let spotDistortionMaximumPositions = 2_500

    /// Why the fit cannot run now, or nil. The button's help and the action's refusal are this one sentence.
    var spotDistortionBlocker: String? {
        if resultPresentation.braggVectors == nil { return "Needs Detect All Disks first." }
        if diskDetectionSettingsAreStale { return "Detection settings changed: run Detect All Disks again first." }
        if calibrationSession.calibration.hasEllipse { return "An ellipse correction is set: clear it first, the fit measures the uncorrected pattern." }
        if acomScaleSemantics.provenance == .exploratory { return "Needs the Q pixel scale first." }
        if resolvedACOMModel == nil { return acomSession.modelSelectionIssue ?? "Needs the matrix crystal: choose it in Crystal Maps › Orientation." }
        return nil
    }

    /// Fit the detector's distortion on the matrix's spots and hold the result (`spotDistortion.pending`) for the user to apply.
    func fitDistortionFromSpots() async {
        if let blocker = spotDistortionBlocker {
            presentComputeFailure(SimpleError("Cannot fit the distortion from spots. " + blocker))
            return
        }
        guard let descriptor, let raw = resultPresentation.braggVectors, let model = resolvedACOMModel else { return }
        let q = acomScaleSemantics.invAngstromPerPixel
        let calibrated = calibratedBraggVectors(raw, descriptor: descriptor)
        let origin = calibrated.origin.point
        // Every n-th position of a regular grid, at most `spotDistortionMaximumPositions`.
        let width = calibrated.vectors.scanWidth, height = calibrated.vectors.scanHeight
        let full = calibrated.vectors.phaseScan
        guard width > 0, height > 0, full.count == width * height else { return }
        var step = 1
        while ((width + step - 1) / step) * ((height + step - 1) / step) > Self.spotDistortionMaximumPositions { step += 1 }
        var scan: [[SIMD2<Double>]] = []
        for y in stride(from: 0, to: height, by: step) { for x in stride(from: 0, to: width, by: step) { scan.append(full[y * width + x]) } }
        let scanWidth = (width + step - 1) / step, scanHeight = (height + step - 1) / step
        // The matrix's reflections out to the detector's edge.
        let kMax = q * Double(min(descriptor.qx, descriptor.qy)) / 2
        let structure = model.structure
        let epoch = datasetSession.epoch
        let cancellation = beginCancellableOperation("Distortion from spots", status: "Fitting the distortion from the matrix spots…")
        defer { finishCancellableOperation(cancellation) }
        let outcome = await Task.detached(priority: .userInitiated) { () -> (fit: MatrixSpotDistortion, firstShell: Double)? in
            guard let list = try? structure.kinematicReflections(kMax: kMax, retainingAll: false).kept, !list.isEmpty,
                  let library = try? ACOMTemplateLibrary.generate(crystal: structure, kMax: kMax),
                  let matcher = ACOMMatcher(library: library) else { return nil }
            let reflections = list.map { ACOMReflection(g: $0.reflection.g, intensity: $0.structureFactor.intensity) }
            guard let field = PhaseVectorMatcher.matrixOrientations(scan: scan, scanWidth: scanWidth, scanHeight: scanHeight, matcher: matcher,
                                                                    originX: origin.x, originY: origin.y, invAngstromPerPixel: q,
                                                                    maximumVectorInvAngstrom: kMax, maximumWorkers: 8),
                  let fit = PhaseVectorMatcher.matrixSpotDistortion(scan: scan, field: field, reflections: reflections,
                                                                    originX: origin.x, originY: origin.y, invAngstromPerPixel: q,
                                                                    maximumVectorInvAngstrom: kMax),
                  let firstShell = reflections.map({ ($0.g * $0.g).sum().squareRoot() }).filter({ $0 > 0 }).min() else { return nil }
            return (fit, firstShell)
        }.value
        guard epoch == datasetSession.epoch, !cancellation.isCancelled else { return }
        guard let outcome, let fit = SpotDistortionFit(outcome.fit, invAngstromPerPixel: q, firstShellInvAngstrom: outcome.firstShell,
                                                       positionCount: scan.count) else {
            spotDistortion.clear()
            presentComputeFailure(SimpleError("No distortion could be fitted: too few of \(model.displayName)'s spots were found in the detected disks, or they lie along one line."))
            return
        }
        guard fit.stretchRatio >= SpotDistortionFit.smallestStretchOffered else {
            spotDistortion.clear()
            statusText = "Distortion from spots: none found (stretch \(CalibrationUnitConversion.displayNumber(fit.stretchRatio, digits: 4)), \(fit.pairCount) spots of \(model.displayName))"
            return
        }
        guard fit.isCredible else {
            spotDistortion.clear()
            presentComputeFailure(SimpleError("No distortion is offered: the detected spots do not fit one stretched lattice of \(model.displayName) (\(fit.summary())). Check the crystal, the origin and the disk detection."))
            return
        }
        spotDistortion.record(fit)
        statusText = "Distortion from spots ✓  stretch \(fit.summary()). Apply it in Prepare to correct."
    }

    /// The user's confirmation: the pending fit becomes the ellipse correction and the Q pixel scale that goes with it.
    func applySpotDistortion() {
        guard let fit = spotDistortion.pending else { return }
        if let refusal = calibrationSession.applyManualEllipse(a: fit.ellipseA, b: fit.ellipseB, thetaDegrees: fit.ellipseThetaDegrees) {
            presentComputeFailure(SimpleError(refusal))
            return
        }
        calibrationSession.provenance.ellipse = .measuredInApp
        calibrationSession.calibration.qPixelSize = fit.invAngstromPerPixel
        calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        calibrationSession.provenance.qScale = .measuredInApp
        spotDistortion.clear()
        if navigation.analysisMode == .disks, let vectors = resultPresentation.braggVectors, let descriptor {
            showBraggMap(vectors, descriptor: descriptor)
        }
        statusText = "Distortion applied · " + CalibrationUnitConversion.ellipseSummary(a: fit.ellipseA, b: fit.ellipseB, thetaDegrees: fit.ellipseThetaDegrees)
            + " · Q " + CalibrationUnitConversion.displayNumber(fit.invAngstromPerPixel, digits: 4) + "\u{00A0}Å⁻¹/px"
        recordEllipseCalibrationRun()
    }
}
