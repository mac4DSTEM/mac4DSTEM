//
//  PtychographyReplay.swift
//  Role: The single-slice ptychography step of the replay record: the keys the
//        run writes (`recordedParameters`), the settings part the staleness
//        check compares (`Settings.parameters`), the parser
//        (`ReplayPlanner.parsePtychography`, a `ReplayContract` row) and the
//        calibration check the replay applies before it runs
//        (`calibrationRefusal`).
//
//  What the reconstruction reads, and so what the step carries: the run's
//  options (iterations, step size, the constraints), the probe it started from
//  (defocus and the two astigmatism numbers), the probe radius (the aperture's
//  outer radius, detector pixels) and the physical calibration `resolve` built
//  (scan and reciprocal sampling, energy, diffraction origin, R–Q rotation and
//  transpose). The options and the probe are controls, so the replay puts them
//  back. The calibration is not a control of this task: the replay checks that
//  the session's calibration resolves to the recorded one and refuses by name
//  when it does not, as ACOM refuses a different Q scale.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

extension ReplayStepPlan {

    package struct PtychographyReplayPlan: Equatable {

        /// The task's own controls: what `PtychographySettings` holds.
        package struct Settings: Equatable {
            package var iterations: Int
            package var stepSize: Float
            package var normalizationMinimum: Float
            package var fixProbe: Bool
            package var constrainObjectAmplitude: Bool
            package var purePhaseObject: Bool
            package var fixProbeCenterOfMass: Bool
            package var constrainProbeAmplitude: Bool
            package var probeAmplitudeRadius: Float
            package var probeAmplitudeWidth: Float
            package var defocusAngstrom: Double
            package var c12aAngstrom: Double
            package var c12bAngstrom: Double

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(
                iterations: Int, stepSize: Float, normalizationMinimum: Float, fixProbe: Bool,
                constrainObjectAmplitude: Bool, purePhaseObject: Bool, fixProbeCenterOfMass: Bool,
                constrainProbeAmplitude: Bool, probeAmplitudeRadius: Float, probeAmplitudeWidth: Float,
                defocusAngstrom: Double, c12aAngstrom: Double, c12bAngstrom: Double
            ) {
                self.iterations = iterations
                self.stepSize = stepSize
                self.normalizationMinimum = normalizationMinimum
                self.fixProbe = fixProbe
                self.constrainObjectAmplitude = constrainObjectAmplitude
                self.purePhaseObject = purePhaseObject
                self.fixProbeCenterOfMass = fixProbeCenterOfMass
                self.constrainProbeAmplitude = constrainProbeAmplitude
                self.probeAmplitudeRadius = probeAmplitudeRadius
                self.probeAmplitudeWidth = probeAmplitudeWidth
                self.defocusAngstrom = defocusAngstrom
                self.c12aAngstrom = c12aAngstrom
                self.c12bAngstrom = c12bAngstrom
            }

            /// The options a run with these settings hands the reconstructor
            /// and the probe it builds, read back into settings: the record is
            /// written from what ran, not from the fields.
            package nonisolated init(options: SingleslicePtychographyOptions, probe: PtychographyProbeAberrations) {
                self.init(
                    iterations: options.iterations, stepSize: options.stepSize,
                    normalizationMinimum: options.normalizationMinimum, fixProbe: options.fixProbe,
                    constrainObjectAmplitude: options.constrainObjectAmplitude,
                    purePhaseObject: options.purePhaseObject,
                    fixProbeCenterOfMass: options.fixProbeCenterOfMass,
                    constrainProbeAmplitude: options.constrainProbeAmplitude,
                    probeAmplitudeRadius: options.probeAmplitudeRelativeRadius,
                    probeAmplitudeWidth: options.probeAmplitudeRelativeWidth,
                    defocusAngstrom: probe.defocusAngstrom, c12aAngstrom: probe.c12aAngstrom,
                    c12bAngstrom: probe.c12bAngstrom)
            }

            /// The settings keys, written the same way by the run and by the
            /// staleness signature, so an unchanged control compares equal.
            package var parameters: [String: String] {
                [
                    "iterations": String(iterations),
                    "step_size": String(stepSize),
                    "normalization_minimum": String(normalizationMinimum),
                    "fix_probe": String(fixProbe),
                    "constrain_object_amplitude": String(constrainObjectAmplitude),
                    "pure_phase_object": String(purePhaseObject),
                    "fix_probe_center_of_mass": String(fixProbeCenterOfMass),
                    "constrain_probe_amplitude": String(constrainProbeAmplitude),
                    "probe_amplitude_radius": String(probeAmplitudeRadius),
                    "probe_amplitude_width": String(probeAmplitudeWidth),
                    "defocus_angstrom": String(defocusAngstrom),
                    "c12a_angstrom": String(c12aAngstrom),
                    "c12b_angstrom": String(c12bAngstrom),
                ]
            }
        }

        /// The physical calibration the run resolved, in the fields the
        /// reconstruction reads. The wavelength is not carried: it follows
        /// from the energy.
        package struct Calibration: Equatable {
            package var scanSamplingAngstrom: Double
            package var reciprocalSamplingInvAngstrom: Double
            package var energyEV: Double
            /// py4DSTEM's detector axes: qx is the row (app y), qy the column (app x).
            package var originQX: Double
            package var originQY: Double
            package var rotationRad: Double
            package var transpose: Bool

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(scanSamplingAngstrom: Double, reciprocalSamplingInvAngstrom: Double,
                                     energyEV: Double, originQX: Double, originQY: Double,
                                     rotationRad: Double, transpose: Bool) {
                self.scanSamplingAngstrom = scanSamplingAngstrom
                self.reciprocalSamplingInvAngstrom = reciprocalSamplingInvAngstrom
                self.energyEV = energyEV
                self.originQX = originQX
                self.originQY = originQY
                self.rotationRad = rotationRad
                self.transpose = transpose
            }

            package nonisolated init(_ physical: ParallaxPhysicalCalibration) {
                self.init(scanSamplingAngstrom: physical.scanSamplingAngstrom,
                          reciprocalSamplingInvAngstrom: physical.reciprocalSamplingInvAngstrom,
                          energyEV: physical.energyEV, originQX: physical.originQX, originQY: physical.originQY,
                          rotationRad: physical.rotationRad, transpose: physical.transpose)
            }
        }

        package var settings: Settings
        /// The aperture's outer radius the probe was built with, detector pixels.
        package var probeRadiusPixels: Float
        package var calibration: Calibration

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(settings: Settings, probeRadiusPixels: Float, calibration: Calibration) {
            self.settings = settings
            self.probeRadiusPixels = probeRadiusPixels
            self.calibration = calibration
        }

        /// Every key the run writes. The origin is stored as the app's x
        /// (column, py4DSTEM qy) and y (row, py4DSTEM qx) so the frame map
        /// moves each with its own crop offset.
        package static func recordedParameters(settings: Settings, probeRadiusPixels: Float,
                                               calibration: ParallaxPhysicalCalibration) -> [String: String] {
            var p = settings.parameters
            p["probe_radius_px"] = String(probeRadiusPixels)
            p["scan_sampling_angstrom"] = String(calibration.scanSamplingAngstrom)
            p["reciprocal_sampling_inv_angstrom_per_pixel"] = String(calibration.reciprocalSamplingInvAngstrom)
            p["energy_ev"] = String(calibration.energyEV)
            p["origin_x_px"] = String(Float(calibration.originQY))
            p["origin_y_px"] = String(Float(calibration.originQX))
            p["rotation_rad"] = String(calibration.rotationRad)
            p["transpose"] = String(calibration.transpose)
            return p
        }

        /// The staleness signature: the controls and the probe radius. The
        /// calibration keys are not compared here; the replay checks them.
        package static func currentSignature(settings: Settings, probeRadiusPixels: Float) -> [String: String] {
            var p = settings.parameters
            p["probe_radius_px"] = String(probeRadiusPixels)
            return p
        }

        /// How far the session's calibration may sit from the recorded one.
        /// The reciprocal sampling is derived from the Q the user entered (an
        /// mrad value goes through the electron wavelength), so it takes ACOM's
        /// relative tolerance for the same reason
        /// (`ACOMReplayPlan.scaleRelativeTolerance`). Typed values (R scale,
        /// voltage) and the rotation round-trip through the record exactly
        /// (`String(Double)` is lossless), so they take a tolerance that only
        /// absorbs a unit conversion's last bits. The origin is re-referenced
        /// in Float, and a fitted mean is a Float sum over every scan position
        /// (about 1e-3 px of rounding on a 512² scan); 1e-2 px is far below
        /// anything that moves a reconstruction
        /// and far above Float rounding at detector sizes.
        package nonisolated static let reciprocalRelativeTolerance = ACOMReplayPlan.scaleRelativeTolerance
        package nonisolated static let typedRelativeTolerance = 1e-6
        package nonisolated static let rotationToleranceRad = 1e-6
        package nonisolated static let originTolerancePixels = 1e-2

        /// Why the replay cannot run against `resolved` (the session's
        /// calibration, resolved the way the run resolves it), nil when it
        /// agrees with what the recorded run used. Writes nothing.
        package func calibrationRefusal(against resolved: ParallaxPhysicalCalibration) -> String? {
            let c = calibration
            if let reason = Self.samplingRefusal(
                scanSamplingAngstrom: c.scanSamplingAngstrom, reciprocalSamplingInvAngstrom: c.reciprocalSamplingInvAngstrom,
                energyEV: c.energyEV, rotationRad: c.rotationRad, transpose: c.transpose,
                resolved: resolved, task: "ptychography") { return reason }
            if abs(resolved.originQX - c.originQX) > Self.originTolerancePixels
                || abs(resolved.originQY - c.originQY) > Self.originTolerancePixels {
                return String(format: "the recipe reconstructed about the diffraction origin (x %.4g, y %.4g) px but this session's origin is (x %.4g, y %.4g) px — the rehearsal's per-position origin fit does not carry across a promote, so calibrate the origin on the promoted view, then run ptychography by hand",
                              c.originQY, c.originQX, resolved.originQY, resolved.originQX)
            }
            return nil
        }

        /// The R and Q sampling, the voltage and the R–Q rotation/transpose a
        /// run recorded against `resolved`: the part of the check single-slice
        /// ptychography and parallax share (parallax never reads the origin).
        /// `task` names the task to run by hand in the refusal.
        package static func samplingRefusal(
            scanSamplingAngstrom: Double, reciprocalSamplingInvAngstrom: Double, energyEV: Double,
            rotationRad: Double, transpose: Bool, resolved: ParallaxPhysicalCalibration, task: String
        ) -> String? {
            func relativeAgrees(_ live: Double, _ recorded: Double, _ tolerance: Double) -> Bool {
                abs(live - recorded) <= max(1e-300, abs(recorded) * tolerance)
            }
            if !relativeAgrees(resolved.scanSamplingAngstrom, scanSamplingAngstrom, typedRelativeTolerance) {
                return String(format: "the recipe reconstructed at an R sampling of %.6g Å/px but this session's is %.6g Å/px — set the R pixel size the rehearsal used, then run %@ by hand",
                              scanSamplingAngstrom, resolved.scanSamplingAngstrom, task)
            }
            if !relativeAgrees(resolved.reciprocalSamplingInvAngstrom, reciprocalSamplingInvAngstrom, reciprocalRelativeTolerance) {
                return String(format: "the recipe reconstructed at a Q sampling of %.6g Å⁻¹/px but this session's is %.6g Å⁻¹/px — recalibrate Q to the rehearsal's value, then run %@ by hand",
                              reciprocalSamplingInvAngstrom, resolved.reciprocalSamplingInvAngstrom, task)
            }
            if !relativeAgrees(resolved.energyEV, energyEV, typedRelativeTolerance) {
                return String(format: "the recipe reconstructed at %.6g kV but this session's accelerating voltage is %.6g kV — set the rehearsal's voltage, then run %@ by hand",
                              energyEV / 1_000, resolved.energyEV / 1_000, task)
            }
            if abs(resolved.rotationRad - rotationRad) > rotationToleranceRad || resolved.transpose != transpose {
                return "the recipe reconstructed with a different R–Q rotation or transpose than this session holds — set the rehearsal's rotation, then run \(task) by hand"
            }
            return nil
        }
    }
}

extension ReplayPlanner {

    static func parsePtychography(_ step: SessionReplayRecord.Step) -> Result<ReplayStepPlan, ReplayRefusal> {
        let p = step.parameters
        func refused(_ key: String) -> Result<ReplayStepPlan, ReplayRefusal> {
            let described = p[key].map { "'\($0)'" } ?? "missing"
            return .failure(ReplayRefusal(reason: "its recorded parameter '\(key)' is \(described), which this app cannot read"))
        }
        func float(_ key: String) -> Float? {
            guard let text = p[key], let value = Float(text), value.isFinite else { return nil }
            return value
        }
        func double(_ key: String) -> Double? {
            guard let text = p[key], let value = Double(text), value.isFinite else { return nil }
            return value
        }
        func bool(_ key: String) -> Bool? {
            switch p[key] {
            case "true": true
            case "false": false
            default: nil
            }
        }
        guard let iterations = p["iterations"].flatMap(Int.init), iterations > 0 else { return refused("iterations") }
        guard let stepSize = float("step_size"), stepSize > 0 else { return refused("step_size") }
        guard let normalizationMinimum = float("normalization_minimum"), normalizationMinimum >= 0 else {
            return refused("normalization_minimum")
        }
        guard let fixProbe = bool("fix_probe") else { return refused("fix_probe") }
        guard let constrainObject = bool("constrain_object_amplitude") else { return refused("constrain_object_amplitude") }
        guard let purePhase = bool("pure_phase_object") else { return refused("pure_phase_object") }
        guard let fixCOM = bool("fix_probe_center_of_mass") else { return refused("fix_probe_center_of_mass") }
        guard let constrainProbe = bool("constrain_probe_amplitude") else { return refused("constrain_probe_amplitude") }
        guard let amplitudeRadius = float("probe_amplitude_radius") else { return refused("probe_amplitude_radius") }
        guard let amplitudeWidth = float("probe_amplitude_width") else { return refused("probe_amplitude_width") }
        guard let defocus = double("defocus_angstrom") else { return refused("defocus_angstrom") }
        guard let c12a = double("c12a_angstrom") else { return refused("c12a_angstrom") }
        guard let c12b = double("c12b_angstrom") else { return refused("c12b_angstrom") }
        guard let probeRadius = float("probe_radius_px"), probeRadius > 0 else { return refused("probe_radius_px") }
        guard let scanSampling = double("scan_sampling_angstrom"), scanSampling > 0 else {
            return refused("scan_sampling_angstrom")
        }
        guard let reciprocal = double("reciprocal_sampling_inv_angstrom_per_pixel"), reciprocal > 0 else {
            return refused("reciprocal_sampling_inv_angstrom_per_pixel")
        }
        guard let energy = double("energy_ev"), energy > 0 else { return refused("energy_ev") }
        guard let originX = double("origin_x_px") else { return refused("origin_x_px") }
        guard let originY = double("origin_y_px") else { return refused("origin_y_px") }
        guard let rotation = double("rotation_rad") else { return refused("rotation_rad") }
        guard let transpose = bool("transpose") else { return refused("transpose") }
        return .success(.ptychography(.init(
            settings: .init(
                iterations: iterations, stepSize: stepSize, normalizationMinimum: normalizationMinimum,
                fixProbe: fixProbe, constrainObjectAmplitude: constrainObject, purePhaseObject: purePhase,
                fixProbeCenterOfMass: fixCOM, constrainProbeAmplitude: constrainProbe,
                probeAmplitudeRadius: amplitudeRadius, probeAmplitudeWidth: amplitudeWidth,
                defocusAngstrom: defocus, c12aAngstrom: c12a, c12bAngstrom: c12b),
            probeRadiusPixels: probeRadius,
            calibration: .init(scanSamplingAngstrom: scanSampling, reciprocalSamplingInvAngstrom: reciprocal,
                               energyEV: energy, originQX: originY, originQY: originX,
                               rotationRad: rotation, transpose: transpose))))
    }
}
