//
//  AgentDoorCalibration.swift
//  Role: The agent door's calibration tools (issue #208): Prepare's Calibration section. An agent types the Q and R pixel sizes
//        with their units and the voltage, through the setters the readiness rows' fields commit to (`setManualQPixelSize`, ...),
//        and starts the measured steps, through the entry points of Calibrate Origin, Origin from Bragg Peaks, Fit Ellipse and
//        Measure R–Q Rotation. Each answers with the calibration as `get_window` shows it.
//
//  The setters act, so they run only while "Let agents run analyses" is on (`AgentDoorRuns.swift`'s rules). Clear Calibration
//  removes measured values and stays with the person.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let calibrationTools: [AgentTool] = [
        AgentTool(name: "set_calibration", title: "Set calibration",
                  summary: "Types the Q pixel size, the R pixel size (each with its unit) and the accelerating voltage, as Prepare's "
                      + "fields do; only the ones given, recorded as manual. A value the file gave is overridden. Answers with the "
                      + "calibration as get_window shows it.",
                  input: .window,
                  parameters: [
                      AgentParameter("q_pixel_size", .number(1e-9...1e9), summary: "Detector (reciprocal) pixel size, in q_units."),
                      AgentParameter("q_units", .text, summary: "Å⁻¹ (also A^-1, 1/A), nm⁻¹ (nm^-1, 1/nm) or mrad (needs the "
                                         + "voltage). Default: the unit in force, else nm⁻¹."),
                      AgentParameter("r_pixel_size", .number(1e-9...1e9), summary: "Scan step, in r_units."),
                      AgentParameter("r_units", .text, summary: "Å (A), nm or pm. Default: the unit in force, else nm."),
                      AgentParameter("voltage_kv", .number(1...10_000), summary: "Accelerating voltage, kV."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            let arguments = call.arguments
            let qUnits = arguments["q_units"].map { (typed: $0, unit: CalibrationUnitConversion.canonicalEditableReciprocalUnit($0)) }
            if let qUnits, qUnits.unit == nil {
                return .refusal(status: 400, message: "q_units is Å⁻¹, nm⁻¹ or mrad, not \(qUnits.typed).")
            }
            let rUnits = arguments["r_units"].map { (typed: $0, unit: CalibrationUnitConversion.canonicalEditableRealUnit($0)) }
            if let rUnits, rUnits.unit == nil {
                return .refusal(status: 400, message: "r_units is Å, nm or pm, not \(rUnits.typed).")
            }
            // The voltage first (mrad needs its wavelength), then each unit before its size, as the row's picker and field.
            if let kV = arguments["voltage_kv"].flatMap(Double.init) { state.setManualAcceleratingVoltage(kV) }
            if let unit = qUnits?.unit { state.setManualQPixelUnits(unit) }
            if let size = arguments["q_pixel_size"].flatMap(Double.init) { state.setManualQPixelSize(size) }
            if let unit = rUnits?.unit { state.setManualRPixelUnits(unit) }
            if let size = arguments["r_pixel_size"].flatMap(Double.init) { state.setManualRPixelSize(size) }
            // An Output line names what the agent typed, so the person sees which values were not theirs.
            let typed = arguments.keys.sorted().compactMap { name in arguments[name].map { "\(name) \($0)" } }
            state.statusText = "An agent set the calibration: " + typed.joined(separator: ", ") + "."
            return .json(["calibration": state.agentCalibration])
        },
        AgentTool(name: "run_calibration", title: "Calibrate",
                  summary: "Starts one of Prepare's measured calibration steps, as its button does: origin (Calibrate Origin, also "
                      + "the probe radius), origin_from_bragg_peaks (after Detect All Disks), ellipse (Fit Ellipse in the fit annulus) "
                      + "rotation (Measure R–Q Rotation; calibrates the origin first if needed), q_from_material (Calibrate from Selected "
                      + "Material: ACOM's phase model against the detected disks), restore_fitted_origin, fit_distortion_from_spots "
                      + "(a single crystal's stretch, shown in get_window, nothing applied), apply_spot_distortion, flip_rotation_180 (Flip 180°: the rotation measurement cannot tell θ from θ + 180°), or manual_ellipse "
                      + "(py4DSTEM's a, b, θ). A long step answers at once; get_window says busy until it finishes, then its "
                      + "calibration rows and get_log say how it ended.",
                  input: .window,
                  parameters: [
                      AgentParameter("step", .choice(CalibrationStep.allCases.map(\.rawValue)), summary: "The step.", required: true),
                      AgentParameter("origin_method", .choice(OriginMethod.allCases.map(\.rawValue)),
                                     summary: "For origin: centreOfMass (default, fast) or friedel (a beamstop hides the direct beam)."),
                      AgentParameter("fit_inner_px", .number(0...100_000), summary: "For ellipse: inner radius of the fit annulus, px."),
                      AgentParameter("fit_outer_px", .number(0...100_000), summary: "For ellipse: outer radius of the fit annulus, px."),
                      AgentParameter("ellipse_a", .number(0.001...100_000), summary: "For manual_ellipse: semi-axis a (the longer), px."),
                      AgentParameter("ellipse_b", .number(0.001...100_000), summary: "For manual_ellipse: semi-axis b, px."),
                      AgentParameter("ellipse_theta_deg", .number(-360...360), summary: "For manual_ellipse: tilt of a from qx, degrees."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard let step = call.arguments["step"].flatMap(CalibrationStep.init(rawValue:)) else {
                return .refusal(status: 400, message: "Name the step.")
            }
            let session = state.calibrationSession
            switch step {
            case .origin:
                if let method = call.arguments["origin_method"].flatMap(OriginMethod.init(rawValue:)) { session.originMethod = method }
                Task { await state.calibrateOrigin() }
            case .originFromBraggPeaks:
                guard state.resultPresentation.braggVectors != nil else {
                    return .refusal(status: 409, message: "Detect All Disks first: this follows the direct beam among the detected disks.")
                }
                Task { await state.calibrateOriginFromBraggPeaks() }
            case .ellipse:
                let inner = call.arguments["fit_inner_px"].flatMap(Double.init) ?? session.ellipseFitInnerRadius
                let outer = call.arguments["fit_outer_px"].flatMap(Double.init) ?? session.ellipseFitOuterRadius
                guard inner < outer else {
                    return .refusal(status: 400, message: "The fit annulus's inner radius (\(inner) px) must be below its outer (\(outer) px).")
                }
                session.ellipseFitInnerRadius = inner
                session.ellipseFitOuterRadius = outer
                Task { await state.calibrateEllipse() }
            case .rotation:
                Task { await state.calibrateRotation() }
            case .qFromMaterial:
                guard state.hasCurrentBraggVectors, state.resolvedACOMModel != nil else {
                    return .refusal(status: 409, message: "This needs detected disks (run_task in Disks) and ACOM's phase model "
                        + "(set_acom phase_cif).")
                }
                Task { await state.calibrateQFromCrystal() }
            case .restoreFittedOrigin:
                state.restoreFittedOrigin()
            case .fitDistortionFromSpots:
                if let blocker = state.spotDistortionBlocker {
                    // The person's line names the Orientation picker; through the door the matrix crystal is set_acom's.
                    let door = state.resolvedACOMModel == nil && state.hasCurrentBraggVectors
                        ? " Through the door: set_acom phase_cif names the matrix crystal." : ""
                    return .refusal(status: 409, message: blocker + door)
                }
                Task { await state.fitDistortionFromSpots() }
            case .applySpotDistortion:
                guard state.spotDistortion.pending != nil else {
                    return .refusal(status: 409, message: "There is no spot distortion fit to apply (fit_distortion_from_spots).")
                }
                let before = state.calibrationSession.calibration.qPixelSize
                state.applySpotDistortion()
                guard state.spotDistortion.pending == nil else {
                    return .refusal(status: 409, message: "The spot distortion was not applied; get_log says why.")
                }
                let after = state.calibrationSession.calibration
                state.statusText = "An agent applied the spot distortion."
                return .json(["applied": step.rawValue,
                              "q_inv_angstrom_per_px_before": AgentJSON.number(before),
                              "q_inv_angstrom_per_px_after": AgentJSON.number(after.qPixelSize),
                              "note": "The Q pixel scale changed with the ellipse; vectors and maps computed before use the old scale."])
            case .flipRotation180:
                guard let before = state.calibrationSession.calibration.rotationRad else {
                    return .refusal(status: 409, message: "There is no R–Q rotation to flip yet (step rotation).")
                }
                state.flipRotation180()
                let after = state.calibrationSession.calibration.rotationRad ?? before
                return .json(["applied": step.rawValue,
                              "rotation_deg_before": AgentJSON.number(RQRotationConvention.displayDegrees(fromApp: before)),
                              "rotation_deg_after": AgentJSON.number(RQRotationConvention.displayDegrees(fromApp: after)),
                              "transposed": state.calibrationSession.calibration.transposeQR ?? false])
            case .manualEllipse:
                guard let a = call.arguments["ellipse_a"].flatMap(Double.init),
                      let b = call.arguments["ellipse_b"].flatMap(Double.init) else {
                    return .refusal(status: 400, message: "manual_ellipse needs ellipse_a and ellipse_b (and ellipse_theta_deg).")
                }
                state.applyManualEllipse(a: a, b: b, thetaDegrees: call.arguments["ellipse_theta_deg"].flatMap(Double.init) ?? 0)
            }
            state.statusText = "An agent started \(step.title)."
            return .json(["started": step.rawValue])
        },
    ]

    /// Prepare's measured calibration steps, as an agent names them.
    enum CalibrationStep: String, CaseIterable {
        case origin
        case originFromBraggPeaks = "origin_from_bragg_peaks"
        case ellipse
        case rotation
        case qFromMaterial = "q_from_material"
        case restoreFittedOrigin = "restore_fitted_origin"
        case fitDistortionFromSpots = "fit_distortion_from_spots"
        case applySpotDistortion = "apply_spot_distortion"
        case manualEllipse = "manual_ellipse"
        case flipRotation180 = "flip_rotation_180"

        var title: String {
            switch self {
            case .origin: "Calibrate Origin"
            case .originFromBraggPeaks: "Origin from Bragg Peaks"
            case .ellipse: "Fit Ellipse"
            case .rotation: "Measure R–Q Rotation"
            case .qFromMaterial: "Calibrate from Selected Material"
            case .restoreFittedOrigin: "Restore Fitted Origin"
            case .fitDistortionFromSpots: "Fit Distortion from Spots"
            case .applySpotDistortion: "Apply Distortion"
            case .manualEllipse: "Apply Ellipse"
            case .flipRotation180: "Flip 180°"
            }
        }
    }
}
