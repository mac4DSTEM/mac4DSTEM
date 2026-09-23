//
//  AppState+DPC.swift
//  Role: the DPC orchestration — the CoM-field run, the 180° rotation flip,
//        and the one display-derivation site every DPC mode publishes
//        through. Moved verbatim out of AppState.swift on 2026-09-18 (seam
//        4, docs/archive/v4/appstate-seams-plan.md, the last of the night's four
//        unattended seams): a placement change, no logic touched.
//        `dpcDisplay` moved into `Session/DPCProduct.swift` in the same
//        seam — the reads of it here are renamed to `dpc.dpcDisplay`;
//        `dpcMilliradiansPerDetectorPixel` stays on AppState (see that
//        file's header for why the plan's "Moves" naming was corrected) and
//        keeps its pre-seam unqualified name. `comField` widens from
//        `private` to a plain `var` (1 widening for this seam) so this file
//        can read/write it — an extension in a different file cannot see a
//        `private` stored property declared in AppState.swift.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    // MARK: - DPC

    /// Measure the CoM field (against calibrated origins) and cache it, then
    /// render the selected DPC view. The field is cached so switching between
    /// magnitude / angle / color-wheel / iDPC is instant (no GPU re-run).
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runDPC(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("No dataset is loaded") }
        let cancellation = beginCancellableOperation(
            "DPC", status: "Computing DPC (center of mass)…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        do {
            let epoch = datasetSession.epoch
            let field = try await computeCoMField(cancellation: cancellation)
            guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
            if cancellation.isCancelled {
                statusText = "DPC cancelled"
                return .cancelled
            }
            // A nil field here is not a publish: `computeCoMField` bails to
            // nil when the cube is gone. The first version ran the success
            // block anyway — "DPC ✓" over nothing, and a phantom recipe step
            // (Gate A finding A6, 2026-08-25).
            guard let field else {
                statusText = "DPC could not run — no data is loaded"
                return .failed("DPC could not run — no data is loaded")
            }
            comField = field
            // A failed display derivation (an iDPC integration refusal) must
            // not be papered over with "DPC ✓", must not become a recipe
            // step, and must not report `.published` over a blank pane —
            // Gate B refuted the first version on all three (2026-08-25).
            // `presentComputeFailure` inside the derivation already put the
            // reason in the durable log; withholding the ✓ line keeps it on
            // the status bar too.
            if let displayFailure = applyDPCDisplay() {
                return .failed(displayFailure)
            }
            let ref = calibrationSession.calibration.hasFittedOrigin ? "calibrated origins" : "global center"
            statusText = "DPC ✓  (\(dpc.dpcDisplay.rawValue) vs \(ref))"
            // Recipe step (v2 S5). ONLY the origin source: `computeCoMField`
            // takes no aperture at all — its parameterization is which origin
            // it subtracts (fitted per-position maps / mean origin, or the
            // geometric fallback), and those come from `calibration` at run
            // time exactly as they will at replay time. The first version
            // recorded the aperture here; refuted by the function 45 lines up
            // (Gate B-lite F2) — recording values the computation never used
            // is false precision a replay would faithfully reproduce wrongly.
            recordReplayStep(kind: "dpc", parameters: ["origin_reference": ref], replaying: replaying)
            return .published
        } catch {
            if cancellation.isCancelled {
                statusText = "DPC cancelled"
                return .cancelled
            }
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// Flip the calibrated R–Q rotation by 180° — the curl/divergence solver
    /// is blind to this (flipping both CoM components leaves both invariant),
    /// so inverted iDPC contrast is fixed here, by hand.
    func flipRotation180() {
        guard var rotation = calibrationSession.calibration.rotationRad else { return }
        rotation += .pi
        if rotation > .pi { rotation -= 2 * .pi }
        calibrationSession.calibration.rotationRad = rotation
        calibrationSession.provenance.rotation = .manual
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        // Same rule as `calibrateRotation`: the flip stands either way, but a
        // refused re-derivation keeps its own message on the status bar.
        // The strain tensor is mathematically invariant under a 180° flip
        // (ε' = (−I)·ε·(−I)ᵀ = ε), but the displayed frame label shows the
        // angle, so the display re-derives on the same one rule. // v2 S8
        applyStrainDisplay()
        if applyDPCDisplay() == nil {
            statusText = String(format: "Rotation flipped → θ = %.1f°", rotation * 180 / .pi)
        }
    }

    /// Derive the displayed image from the cached CoM field per `dpcDisplay`.
    /// The calibrated R–Q rotation/transpose is applied first so the field is
    /// in the scan frame. Cheap enough (scan-sized) to run on the main actor.
    /// Returns the failure reason when the derivation could not produce an
    /// image (today: an iDPC integration refusal), nil on success — so a
    /// caller that writes its own "✓" status line can withhold it. The first
    /// S7 version reported the failure only through `presentComputeFailure`
    /// and `runDPC` then overwrote it with "DPC ✓", recorded a recipe step
    /// and returned `.published` over a blank pane — the S1 channel defect
    /// plus the A6 phantom-step defect, both found by Gate B (2026-08-25).
    @discardableResult
    /// The one publish site for every DPC display mode: pixels and label
    /// chosen together (v2.5 step 3e, condition 2).
    func applyDPCDisplay() -> String? {
        guard var com = comField, let d = descriptor, navigation.analysisMode == .dpc else { return nil }
        if let rotation = calibrationSession.calibration.rotationRad {
            com = DPC.applyRotation(com: com, rotationRad: rotation,
                                    transpose: calibrationSession.calibration.transposeQR ?? false)
        }
        let payload: ProductPayload
        let kind: String, name: String, units: String
        switch dpc.dpcDisplay {
        case .magnitude:
            resultPresentation.resultColormap = .viridis
            payload = .scalar(DPC.magnitudeImage(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_magnitude", "DPC magnitude", "detector_px")
        case .magnitudeMrad:
            resultPresentation.resultColormap = .viridis
            if let scale = dpcMilliradiansPerDetectorPixel {
                payload = .scalar(DPC.physicalMagnitudeImage(
                    com: com, width: d.rx, height: d.ry, milliradiansPerPixel: scale))
                (kind, name, units) = ("dpc_magnitude_mrad", "DPC magnitude (mrad)", "mrad")
            } else {
                payload = .scalar(DPC.magnitudeImage(com: com, width: d.rx, height: d.ry))
                (kind, name, units) = ("dpc_magnitude", "DPC magnitude", "detector_px")
            }
        case .angle:
            resultPresentation.resultColormap = .viridis
            payload = .scalar(DPC.angleImage(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_angle", "DPC angle", "rad")
        case .colorWheel:
            resultPresentation.resultColormap = .viridis
            payload = .rgba(DPC.colorWheelRGBA(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_color", "DPC color wheel", "rgba")
        case .idpc:
            resultPresentation.resultColormap = .rdbu
            // `integrateIDPC` now throws instead of returning a zero image
            // (v2 S7): a failed integration must leave NO image on screen —
            // neither a fabricated flat map nor the previous display's
            // pixels under an iDPC label — and must say why.
            do {
                if let physical = idpcPhysicalCalibration {
                    payload = .scalar(try DPC.integratePhysicalIDPC(
                        com: com, width: d.rx, height: d.ry,
                        calibration: physical, boundary: .zeroPadded, paddingFactor: 2))
                    (kind, name, units) = ("idpc_phase", "iDPC projected phase", "rad")
                } else {
                    payload = .scalar(try DPC.integrateIDPC(
                        com: com, width: d.rx, height: d.ry,
                        boundary: .zeroPadded, paddingFactor: 2))
                    (kind, name, units) = ("idpc_qualitative", "iDPC (qualitative)", "detector_px_scan_px")
                }
            } catch {
                resultPresentation.replaceProduct(nil)
                resultPresentation.bumpResultVersion()
                presentComputeFailure(error)
                return error.localizedDescription
            }
        }
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: payload)
        return nil
    }
}
