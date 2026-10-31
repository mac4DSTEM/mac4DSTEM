//
//  ParallaxReplay.swift
//  Role: The parallax step of the replay record: the keys the stages write
//        (`recordedParameters`), the part the staleness check compares
//        (`currentSignature`), the parser (`ReplayPlanner.parseParallax`, a
//        `ReplayContract` row) and the calibration check the replay applies
//        before it runs (`calibrationRefusal`).
//
//  Parallax is one task of several stages the user runs one at a time:
//  preprocess, align level by level, fit the aberrations, then any of KDE
//  upsampling (needs the whole alignment schedule), phase correction and depth
//  sectioning (both need the fit). The record keeps ONE step for the task,
//  rewritten after every stage from what is held then (`PhaseContrastProduct`'s
//  cascades drop a later stage when an earlier one re-runs), so the step always
//  says how far the pipeline got and with what:
//
//  - the physical calibration the preprocess resolved (scan and reciprocal
//    sampling, energy, R–Q rotation and transpose; parallax never reads the
//    origin). Not a control of this task: the replay checks the session's
//    against it and refuses by name, as ptychography does.
//  - the number of alignment levels completed, and whether the schedule was
//    complete. A promote that bins the detector changes the schedule, so a
//    complete alignment replays to the end of the new schedule, not to a count.
//    The step also records the bin the alignment stopped at (detector pixels,
//    re-referenced with the frame) and the passes made there, and a partial
//    alignment replays the new schedule up to the same physical bin, or refuses
//    (`replayLevelCount`).
//  - whether the aberration fit ran (it has no settings).
//  - the controls of KDE upsampling, phase correction and depth sectioning,
//    each group written only when that stage's product is held. These are the
//    keys the staleness check compares.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

extension ReplayStepPlan {

    package struct ParallaxReplayPlan: Equatable {

        /// The KDE upsampling controls (`ParallaxSubpixelOptions`, as the
        /// fields hold them: 0 means the heuristic factor, bilinear deposition
        /// or no position correction).
        package struct Subpixel: Equatable {
            package var upsampleFactor: Double
            /// Scan pixels: a detector re-reference leaves it alone.
            package var kdeSigmaPixels: Double
            package var lowpass: Bool
            package var lanczosOrder: Int
            package var positionCorrectionIterations: Int
            package var positionCorrectionCheckerboard: Bool

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(upsampleFactor: Double, kdeSigmaPixels: Double, lowpass: Bool, lanczosOrder: Int,
                                     positionCorrectionIterations: Int, positionCorrectionCheckerboard: Bool) {
                self.upsampleFactor = upsampleFactor
                self.kdeSigmaPixels = kdeSigmaPixels
                self.lowpass = lowpass
                self.lanczosOrder = lanczosOrder
                self.positionCorrectionIterations = positionCorrectionIterations
                self.positionCorrectionCheckerboard = positionCorrectionCheckerboard
            }

            package var parameters: [String: String] {
                [
                    "kde_upsample_factor": String(upsampleFactor),
                    "kde_sigma_px": String(kdeSigmaPixels),
                    "kde_lowpass": String(lowpass),
                    "kde_lanczos_order": String(lanczosOrder),
                    "position_correction_iterations": String(positionCorrectionIterations),
                    "position_correction_checkerboard": String(positionCorrectionCheckerboard),
                ]
            }
        }

        /// The phase-correction filters, Å⁻¹ (0 means none).
        package struct Correction: Equatable {
            package var qLowpassInvAngstrom: Double
            package var qHighpassInvAngstrom: Double

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(qLowpassInvAngstrom: Double, qHighpassInvAngstrom: Double) {
                self.qLowpassInvAngstrom = qLowpassInvAngstrom
                self.qHighpassInvAngstrom = qHighpassInvAngstrom
            }

            package var parameters: [String: String] {
                [
                    "q_lowpass_inv_angstrom": String(qLowpassInvAngstrom),
                    "q_highpass_inv_angstrom": String(qHighpassInvAngstrom),
                ]
            }
        }

        /// The depth-sectioning controls (0 information limit means none).
        package struct Depth: Equatable {
            package var startAngstrom: Double
            package var endAngstrom: Double
            package var planeCount: Int
            package var useFullFit: Bool
            package var informationLimitInvAngstrom: Double
            package var informationPower: Double

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(startAngstrom: Double, endAngstrom: Double, planeCount: Int, useFullFit: Bool,
                                     informationLimitInvAngstrom: Double, informationPower: Double) {
                self.startAngstrom = startAngstrom
                self.endAngstrom = endAngstrom
                self.planeCount = planeCount
                self.useFullFit = useFullFit
                self.informationLimitInvAngstrom = informationLimitInvAngstrom
                self.informationPower = informationPower
            }

            package var parameters: [String: String] {
                [
                    "depth_start_angstrom": String(startAngstrom),
                    "depth_end_angstrom": String(endAngstrom),
                    "depth_plane_count": String(planeCount),
                    "depth_use_full_fit": String(useFullFit),
                    "depth_information_limit_inv_angstrom": String(informationLimitInvAngstrom),
                    "depth_information_power": String(informationPower),
                ]
            }
        }

        /// The calibration the preprocess resolved, in the fields parallax
        /// reads (no origin: parallax never reads it).
        package struct Calibration: Equatable {
            package var scanSamplingAngstrom: Double
            package var reciprocalSamplingInvAngstrom: Double
            package var energyEV: Double
            package var rotationRad: Double
            package var transpose: Bool

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(scanSamplingAngstrom: Double, reciprocalSamplingInvAngstrom: Double,
                                     energyEV: Double, rotationRad: Double, transpose: Bool) {
                self.scanSamplingAngstrom = scanSamplingAngstrom
                self.reciprocalSamplingInvAngstrom = reciprocalSamplingInvAngstrom
                self.energyEV = energyEV
                self.rotationRad = rotationRad
                self.transpose = transpose
            }

            package nonisolated init(_ physical: ParallaxPhysicalCalibration) {
                self.init(scanSamplingAngstrom: physical.scanSamplingAngstrom,
                          reciprocalSamplingInvAngstrom: physical.reciprocalSamplingInvAngstrom,
                          energyEV: physical.energyEV, rotationRad: physical.rotationRad,
                          transpose: physical.transpose)
            }
        }

        /// Where the alignment stopped: the last completed bin, in the step's
        /// detector pixels, and how many passes it made at that bin (the finest
        /// bin repeats). A level count alone is not enough: the schedule comes
        /// from the bright-field diameter in detector pixels, so a detector bin
        /// can shift it by a level and adds a finest level. The bin is a length
        /// (`ReplayContract`): ×bin into the source, ÷bin into an export, where
        /// a fraction is kept and simply matches no level of a schedule.
        package struct AlignmentStop: Equatable {
            package var bin: Double
            package var passes: Int

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
            package nonisolated init(bin: Double, passes: Int) {
                self.bin = bin
                self.passes = passes
            }

            /// Nil when no level completed.
            package nonisolated init?(completedBins: [Int]) {
                guard let last = completedBins.last else { return nil }
                self.init(bin: Double(last), passes: completedBins.filter { $0 == last }.count)
            }
        }

        package var calibration: Calibration
        /// Alignment levels completed (0: preprocessed only).
        package var alignmentLevels: Int
        /// The whole bin schedule was aligned.
        package var alignmentComplete: Bool
        /// Where the alignment stopped; nil exactly when no level completed.
        package var alignmentStop: AlignmentStop?
        package var fitsAberrations: Bool
        package var subpixel: Subpixel?
        package var correction: Correction?
        package var depth: Depth?

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(calibration: Calibration, alignmentLevels: Int, alignmentComplete: Bool,
                                 alignmentStop: AlignmentStop?,
                                 fitsAberrations: Bool, subpixel: Subpixel?, correction: Correction?, depth: Depth?) {
            self.calibration = calibration
            self.alignmentLevels = alignmentLevels
            self.alignmentComplete = alignmentComplete
            self.alignmentStop = alignmentStop
            self.fitsAberrations = fitsAberrations
            self.subpixel = subpixel
            self.correction = correction
            self.depth = depth
        }

        /// How many levels of `schedule` (this view's, detector pixels) the
        /// replay aligns: all of it for a complete alignment, none for none,
        /// and for a partial one the first prefix that ends at the recorded
        /// stopping bin with the recorded number of passes there. A coarser
        /// leading level this schedule has and the rehearsal's had not is
        /// aligned too (it only refines the start). Nil when the schedule never
        /// reaches the stopping bin that way: no level has the same physical bin.
        package func replayLevelCount(schedule: [Int]) -> Int? {
            if alignmentComplete { return schedule.count }
            guard alignmentLevels > 0 else { return 0 }
            guard let alignmentStop else { return nil }
            var passes = 0
            for (index, bin) in schedule.enumerated() where Double(bin) == alignmentStop.bin {
                passes += 1
                if passes == alignmentStop.passes { return index + 1 }
            }
            return nil
        }

        /// The refusal for `replayLevelCount` nil, naming the stop and this view's schedule.
        package func alignmentStopRefusal(schedule: [Int]) -> String {
            let stop = alignmentStop.map {
                String(format: "bin %g px after %d pass%@", $0.bin, $0.passes, $0.passes == 1 ? "" : "es")
            } ?? "an unrecorded bin"
            let bins = schedule.map(String.init).joined(separator: ", ")
            return "the recipe stopped its parallax alignment at \(stop), which this view's bin schedule (\(bins)) does not reach the same way — align parallax by hand"
        }

        /// Every key the stages write: what the plan holds, as the step
        /// carries it. The run builds the plan from what it holds after the
        /// stage (`AppState.recordParallaxStep`).
        package var recordedParameters: [String: String] {
            var p: [String: String] = [
                "scan_sampling_angstrom": String(calibration.scanSamplingAngstrom),
                "reciprocal_sampling_inv_angstrom_per_pixel": String(calibration.reciprocalSamplingInvAngstrom),
                "energy_ev": String(calibration.energyEV),
                "rotation_rad": String(calibration.rotationRad),
                "transpose": String(calibration.transpose),
                "alignment_levels": String(alignmentLevels),
                "alignment_complete": String(alignmentComplete),
                "aberration_fit": String(fitsAberrations),
            ]
            if let alignmentStop {
                p["alignment_bin"] = String(alignmentStop.bin)
                p["alignment_bin_passes"] = String(alignmentStop.passes)
            }
            p.merge(Self.currentSignature(subpixel: subpixel, correction: correction, depth: depth)) { _, new in new }
            return p
        }

        /// The staleness signature: the controls of each later stage whose
        /// product is held, written as the record writes them, so an unchanged
        /// control compares equal. The calibration and the stage progress are
        /// not compared (the replay checks the calibration).
        package static func currentSignature(subpixel: Subpixel?, correction: Correction?,
                                             depth: Depth?) -> [String: String] {
            var p: [String: String] = [:]
            if let subpixel { p.merge(subpixel.parameters) { _, new in new } }
            if let correction { p.merge(correction.parameters) { _, new in new } }
            if let depth { p.merge(depth.parameters) { _, new in new } }
            return p
        }

        /// Why the replay cannot run against `resolved` (the session's
        /// calibration, resolved as the preprocess resolves it); nil when it
        /// agrees with what the recorded run used. Ptychography's tolerances.
        package func calibrationRefusal(against resolved: ParallaxPhysicalCalibration) -> String? {
            let c = calibration
            return PtychographyReplayPlan.samplingRefusal(
                scanSamplingAngstrom: c.scanSamplingAngstrom, reciprocalSamplingInvAngstrom: c.reciprocalSamplingInvAngstrom,
                energyEV: c.energyEV, rotationRad: c.rotationRad, transpose: c.transpose,
                resolved: resolved, task: "parallax")
        }
    }
}

extension ReplayPlanner {

    /// Every always-written key is required; a stage's group is all or
    /// nothing, and a stage needs the stages it stands on (KDE a complete
    /// alignment, correction and depth the fit, the fit one level).
    static func parseParallax(_ step: SessionReplayRecord.Step) -> Result<ReplayStepPlan, ReplayRefusal> {
        let p = step.parameters
        func refused(_ key: String) -> Result<ReplayStepPlan, ReplayRefusal> {
            let described = p[key].map { "'\($0)'" } ?? "missing"
            return .failure(ReplayRefusal(reason: "its recorded parameter '\(key)' is \(described), which this app cannot read"))
        }
        func inconsistent(_ what: String) -> Result<ReplayStepPlan, ReplayRefusal> {
            .failure(ReplayRefusal(reason: "its recorded stages are inconsistent: \(what)"))
        }
        func double(_ key: String) -> Double? {
            guard let text = p[key], let value = Double(text), value.isFinite else { return nil }
            return value
        }
        func int(_ key: String) -> Int? { p[key].flatMap { Int($0) } }
        func bool(_ key: String) -> Bool? {
            switch p[key] {
            case "true": true
            case "false": false
            default: nil
            }
        }
        func present(_ keys: [String: String]) -> Bool { keys.keys.contains { p[$0] != nil } }

        guard let scanSampling = double("scan_sampling_angstrom"), scanSampling > 0 else {
            return refused("scan_sampling_angstrom")
        }
        guard let reciprocal = double("reciprocal_sampling_inv_angstrom_per_pixel"), reciprocal > 0 else {
            return refused("reciprocal_sampling_inv_angstrom_per_pixel")
        }
        guard let energy = double("energy_ev"), energy > 0 else { return refused("energy_ev") }
        guard let rotation = double("rotation_rad") else { return refused("rotation_rad") }
        guard let transpose = bool("transpose") else { return refused("transpose") }
        guard let levels = int("alignment_levels"), levels >= 0 else { return refused("alignment_levels") }
        guard let complete = bool("alignment_complete") else { return refused("alignment_complete") }
        guard let fit = bool("aberration_fit") else { return refused("aberration_fit") }
        if complete, levels == 0 { return inconsistent("a complete alignment with no level") }
        if fit, levels == 0 { return inconsistent("an aberration fit with no alignment") }

        typealias Plan = ReplayStepPlan.ParallaxReplayPlan
        let template = Plan.Subpixel(upsampleFactor: 0, kdeSigmaPixels: 0, lowpass: false, lanczosOrder: 0,
                                     positionCorrectionIterations: 0, positionCorrectionCheckerboard: false)
        var subpixel: Plan.Subpixel?
        if present(template.parameters) {
            guard let factor = double("kde_upsample_factor"), factor >= 0 else { return refused("kde_upsample_factor") }
            guard let sigma = double("kde_sigma_px"), sigma >= 0 else { return refused("kde_sigma_px") }
            guard let lowpass = bool("kde_lowpass") else { return refused("kde_lowpass") }
            guard let lanczos = int("kde_lanczos_order"), lanczos >= 0 else { return refused("kde_lanczos_order") }
            guard let iterations = int("position_correction_iterations"), iterations >= 0 else {
                return refused("position_correction_iterations")
            }
            guard let checkerboard = bool("position_correction_checkerboard") else {
                return refused("position_correction_checkerboard")
            }
            guard complete else { return inconsistent("KDE upsampling without a complete alignment") }
            subpixel = Plan.Subpixel(upsampleFactor: factor, kdeSigmaPixels: sigma, lowpass: lowpass,
                                     lanczosOrder: lanczos, positionCorrectionIterations: iterations,
                                     positionCorrectionCheckerboard: checkerboard)
        }
        var correction: Plan.Correction?
        if present(Plan.Correction(qLowpassInvAngstrom: 0, qHighpassInvAngstrom: 0).parameters) {
            guard let lowpass = double("q_lowpass_inv_angstrom") else { return refused("q_lowpass_inv_angstrom") }
            guard let highpass = double("q_highpass_inv_angstrom") else { return refused("q_highpass_inv_angstrom") }
            guard fit else { return inconsistent("a phase correction without the aberration fit") }
            correction = Plan.Correction(qLowpassInvAngstrom: lowpass, qHighpassInvAngstrom: highpass)
        }
        var depth: Plan.Depth?
        if present(Plan.Depth(startAngstrom: 0, endAngstrom: 0, planeCount: 0, useFullFit: false,
                              informationLimitInvAngstrom: 0, informationPower: 0).parameters) {
            guard let start = double("depth_start_angstrom") else { return refused("depth_start_angstrom") }
            guard let end = double("depth_end_angstrom") else { return refused("depth_end_angstrom") }
            guard let count = int("depth_plane_count"), (1...257).contains(count) else {
                return refused("depth_plane_count")
            }
            guard let fullFit = bool("depth_use_full_fit") else { return refused("depth_use_full_fit") }
            guard let limit = double("depth_information_limit_inv_angstrom") else {
                return refused("depth_information_limit_inv_angstrom")
            }
            guard let power = double("depth_information_power") else { return refused("depth_information_power") }
            guard fit else { return inconsistent("depth sections without the aberration fit") }
            depth = Plan.Depth(startAngstrom: start, endAngstrom: end, planeCount: count, useFullFit: fullFit,
                               informationLimitInvAngstrom: limit, informationPower: power)
        }
        // Where the alignment stopped: both keys exactly when a level completed.
        var alignmentStop: Plan.AlignmentStop?
        if levels > 0 {
            guard let bin = double("alignment_bin"), bin > 0 else { return refused("alignment_bin") }
            guard let passes = int("alignment_bin_passes"), (1...levels).contains(passes) else {
                return refused("alignment_bin_passes")
            }
            alignmentStop = Plan.AlignmentStop(bin: bin, passes: passes)
        } else if p["alignment_bin"] != nil || p["alignment_bin_passes"] != nil {
            return inconsistent("a stopping bin for an alignment with no level")
        }
        return .success(.parallax(Plan(
            calibration: .init(scanSamplingAngstrom: scanSampling, reciprocalSamplingInvAngstrom: reciprocal,
                               energyEV: energy, rotationRad: rotation, transpose: transpose),
            alignmentLevels: levels, alignmentComplete: complete, alignmentStop: alignmentStop,
            fitsAberrations: fit,
            subpixel: subpixel, correction: correction, depth: depth)))
    }
}
