//
//  ReplayPlan.swift
//  Role: The executable reading of a `SessionReplayRecord` — v2 S6. Parses each
//        recorded step's flat string parameters back into the typed values the
//        analysis entry points take, and refuses — with a named reason — every
//        step it cannot replay faithfully.
//
//  THE FRAME RULE, decided v2 S6 (2026-08-25). Recorded parameters are
//  view-frame numbers: an aperture centre, a smoothing sigma, a g-vector are
//  all in the detector pixels of the view the analysis ran on. A SCAN crop
//  never touches the detector frame, so a recipe recorded on a scan-crop-only
//  rehearsal replays at full extent as-is — this is the flagship rehearse →
//  promote case. A DETECTOR crop or bin changes what those numbers mean, and
//  mapping them into the source frame is new coordinate math whose failure
//  mode is fabrication (a plausible aperture at the wrong pixel, overnight,
//  unattended). That math belongs with `CalibrationReReference` /
//  `transformedCalibration` and is owned by S10 under Gate B — until it
//  lands, a detector-reduced recipe's detector-frame steps are REFUSED by
//  name, never guessed at (docs/open-items.md).
//
//  REFUSAL OVER SKIPPING. A step this file cannot parse, or whose recorded
//  precondition the session cannot honour, halts the run at that step —
//  continuing past it would replay an incoherent pipeline, which is the
//  "silently past a failure" the S6 brief bans.
//
//  WHY App/ AND NOT Core/. This is parsing, and "parsing lives in Core" is
//  the letter of the placement rule — but the parser's whole OUTPUT
//  vocabulary is App workflow state (`VirtualShapeMode`, `Aperture`,
//  `ACOMRunScope`, `ACOMQualityPreset`, all defined in App/), so a Core
//  placement would make Core depend on App, inverting the layering the rule
//  exists to protect. It sits with the types it produces, beside the
//  `SessionReplay` seam whose record it reads. Raised and weighed at S6's
//  Gate A, 2026-08-25.
//

import Foundation

/// Which detector frame a recipe's parameters are expressed in. Tracked live
/// on `SessionReplay` (session state, never serialized): set when a recipe is
/// adopted from a sidecar, merged on every live recording, and consulted once
/// at replay time.
enum ReplayParameterFrame: Equatable {
    /// No detector crop, bin 1 — detector-frame parameters are already
    /// source-frame numbers. A scan crop alone stays in this case.
    case detectorIdentity
    /// Recorded on a reduced detector. Detector-frame parameters cannot be
    /// replayed at full extent until the S10 mapping exists.
    case detectorReduced(bin: Int, cropped: Bool)
    /// Steps recorded under two different detector frames in one record
    /// (adopt under one specification, re-record under another). Never
    /// un-mixes — conservative on purpose.
    case mixed
    /// A non-empty record whose frame was never established — reachable only
    /// through an adopt that failed to thread the specification. Refuses
    /// detector-frame steps: replaying an unknown frame would be the guess
    /// this file bans (Gate A finding, 2026-08-25). // v2 S6
    case unknown

    /// The frame of a load specification. Nil means the sidecar carried no
    /// specification, which the restore path already reads as full extent —
    /// detector identity, not an unknown.
    static func of(_ specification: LoadSpecification?) -> ReplayParameterFrame {
        guard let spec = specification,
              spec.detectorCrop != nil || spec.detectorBin > 1 else {
            return .detectorIdentity
        }
        return .detectorReduced(bin: spec.detectorBin, cropped: spec.detectorCrop != nil)
    }

    func merging(_ other: ReplayParameterFrame) -> ReplayParameterFrame {
        self == other ? self : .mixed
    }

    /// Why detector-frame steps refuse under this frame, in the app's voice.
    /// Nil for `.detectorIdentity`.
    var refusalReason: String? {
        switch self {
        case .detectorIdentity:
            return nil
        case .detectorReduced(let bin, let cropped):
            let what = switch (cropped, bin > 1) {
            case (true, true): "a cropped, ×\(bin)-binned detector"
            case (true, false): "a cropped detector"
            default: "a ×\(bin)-binned detector"
            }
            return "its detector-pixel parameters were recorded on \(what) and re-referencing them to the full detector is not supported yet — re-run it by hand on the promoted view"
        case .mixed:
            return "the recipe's steps were recorded on two different detector frames, so its detector-pixel parameters have no single meaning — re-run the analyses by hand on the promoted view"
        case .unknown:
            return "the detector frame the recipe was recorded in is unknown, so its detector-pixel parameters cannot be trusted — re-run the analyses by hand on the promoted view"
        }
    }
}

/// A step the replay cannot run, with the reason a person can act on.
/// `Error` only because `Result` requires it — a refusal is never thrown.
struct ReplayRefusal: Equatable, Error {
    let reason: String
}

/// One recorded step, parsed back into the typed values its entry point takes.
/// Parsing is total and explicit: every missing, malformed or out-of-vocabulary
/// value becomes a `ReplayRefusal` naming the key — never a default.
enum ReplayStepPlan: Equatable {
    case virtualDetector(shape: VirtualShapeMode, aperture: Aperture)
    /// `wantsFittedOrigin` mirrors the recorded `origin_reference`: replay must
    /// run against the same origin class or refuse — silently substituting the
    /// other one would be a parameter change the summary never states.
    case dpc(wantsFittedOrigin: Bool)
    case diskDetection(DiskDetectionParams)
    case strain(StrainReplayPlan)
    case acom(ACOMReplayPlan)

    struct StrainReplayPlan: Equatable {
        /// Manual g-vectors when the recorded basis was manual; nil replays the
        /// automatic (consensus) basis, which re-derives on the full data —
        /// the recorded resolved_g values are informational for that mode
        /// (the fidelity decision S5 left to S6).
        var manualBasis: ManualBasis?
        struct ManualBasis: Equatable {
            var g1x: Float, g1y: Float, g2x: Float, g2y: Float
        }
    }

    struct ACOMReplayPlan: Equatable {
        var materialID: String
        /// The scale the run matched at, in Å⁻¹ per detector pixel. Replay
        /// verifies the session's scale semantics agree before running —
        /// matching at a different scale gets every orientation wrong with no
        /// shape check to catch it (the Gate B-lite F3 lesson).
        var scaleInvAngstromPerPixel: Double
        var scope: ACOMRunScope
        var quality: ACOMQualityPreset
    }

    /// Whether this step consumes recorded numbers denominated in detector
    /// pixels (positions, lengths, per-pixel scales). These are the steps the
    /// frame rule gates. Automatic-basis strain replays modes only, so it is
    /// deliberately not gated; its detector-frame inputs are the freshly
    /// replayed disk detection's, not recorded numbers.
    var usesDetectorFrameParameters: Bool {
        switch self {
        case .virtualDetector, .diskDetection, .acom: true
        case .dpc: false
        case .strain(let plan): plan.manualBasis != nil
        }
    }
}

/// A record step with its parse outcome and display title, in pipeline order.
struct PlannedReplayStep: Equatable {
    let kind: String
    let title: String
    let result: Result<ReplayStepPlan, ReplayRefusal>
}

enum ReplayPlanner {

    /// Titles for the summary and progress UI, by recorded kind.
    static func title(forKind kind: String) -> String {
        switch kind {
        case "virtual_detector": "Virtual detector"
        case "dpc": "DPC"
        case "disk_detection": "Bragg disk detection"
        case "strain": "Strain mapping"
        case "acom": "ACOM orientation mapping"
        default: kind
        }
    }

    /// Parse a whole record against the frame it was recorded in. Rules that
    /// need more than one step live here: strain and ACOM consume Bragg
    /// vectors, so a recipe that lists them without an earlier disk-detection
    /// step cannot replay coherently and says so up front instead of failing
    /// mid-run on a missing-peaks guard. The FRAME GATE is applied here too —
    /// every consequence of the plan is pure and computable BEFORE the
    /// expensive reopen, and the executor and the promote caption must read
    /// the same verdict (Gate A findings E1/B5, 2026-08-25).
    static func plan(_ record: SessionReplayRecord,
                     frame: ReplayParameterFrame) -> [PlannedReplayStep] {
        var sawDiskDetection = false
        return record.steps.map { step in
            var parsed: Result<ReplayStepPlan, ReplayRefusal>
            switch step.kind {
            case "strain", "acom":
                parsed = sawDiskDetection
                    ? parse(step)
                    : .failure(ReplayRefusal(reason: "the recipe lists \(title(forKind: step.kind)) with no disk-detection step before it, so there are no Bragg vectors for it to replay against"))
            case "disk_detection":
                sawDiskDetection = true
                parsed = parse(step)
            default:
                parsed = parse(step)
            }
            if case .success(let plan) = parsed,
               plan.usesDetectorFrameParameters,
               let reason = frame.refusalReason {
                parsed = .failure(ReplayRefusal(reason: reason))
            }
            return PlannedReplayStep(kind: step.kind,
                                     title: title(forKind: step.kind),
                                     result: parsed)
        }
    }

    /// Parse one step. The keys and vocabularies are exactly what the S5
    /// recording sites write (`AppState.recordReplayStep` call sites) — this
    /// function must follow those sites, never lead them.
    static func parse(_ step: SessionReplayRecord.Step) -> Result<ReplayStepPlan, ReplayRefusal> {
        let p = step.parameters
        switch step.kind {
        case "virtual_detector":
            guard let shapeText = p["shape"], let shape = VirtualShapeMode(rawValue: shapeText) else {
                return refused(step, key: "shape", value: p["shape"])
            }
            guard let centerX = finiteFloat(p["center_x"]) else { return refused(step, key: "center_x", value: p["center_x"]) }
            guard let centerY = finiteFloat(p["center_y"]) else { return refused(step, key: "center_y", value: p["center_y"]) }
            guard let inner = finiteFloat(p["inner"]), inner >= 0 else { return refused(step, key: "inner", value: p["inner"]) }
            guard let outer = finiteFloat(p["outer"]), outer >= inner else { return refused(step, key: "outer", value: p["outer"]) }
            return .success(.virtualDetector(
                shape: shape,
                aperture: Aperture(centerX: centerX, centerY: centerY, inner: inner, outer: outer)
            ))

        case "dpc":
            // The two strings `runDPC` writes, verbatim.
            switch p["origin_reference"] {
            case "calibrated origins": return .success(.dpc(wantsFittedOrigin: true))
            case "global center": return .success(.dpc(wantsFittedOrigin: false))
            default: return refused(step, key: "origin_reference", value: p["origin_reference"])
            }

        case "disk_detection":
            // The kernel class is a detection parameter even though the
            // struct does not carry it: the correlation response the
            // thresholds were tuned against depends on it. A MEASURED kernel
            // came from a vacuum ROI the recipe cannot carry, so replaying
            // with the synthetic one would be a silent substitution — the
            // exact class this executor bans (Gate A finding C3, 2026-08-25).
            switch p["kernel_source"] {
            case "synthetic":
                break
            case "measured_roi":
                return .failure(ReplayRefusal(reason: "it detected disks with a probe kernel measured from a vacuum ROI, and the recipe cannot carry that measurement — measure a kernel on the promoted view, then run detection by hand"))
            default:
                return refused(step, key: "kernel_source", value: p["kernel_source"])
            }
            var params = DiskDetectionParams()
            guard let corrPower = finiteFloat(p["corr_power"]) else { return refused(step, key: "corr_power", value: p["corr_power"]) }
            guard let sigmaDP = finiteFloat(p["sigma_dp"]) else { return refused(step, key: "sigma_dp", value: p["sigma_dp"]) }
            guard let sigmaCC = finiteFloat(p["sigma_cc"]) else { return refused(step, key: "sigma_cc", value: p["sigma_cc"]) }
            guard let subpixelText = p["subpixel"],
                  let subpixel = SubpixelMode.allCases.first(where: { $0.provenanceID == subpixelText }) else {
                return refused(step, key: "subpixel", value: p["subpixel"])
            }
            guard let upsample = int(p["upsample_factor"]) else { return refused(step, key: "upsample_factor", value: p["upsample_factor"]) }
            guard let minAbs = finiteFloat(p["min_absolute_intensity"]) else { return refused(step, key: "min_absolute_intensity", value: p["min_absolute_intensity"]) }
            guard let minRel = finiteFloat(p["min_relative_intensity"]) else { return refused(step, key: "min_relative_intensity", value: p["min_relative_intensity"]) }
            guard let relativeTo = int(p["relative_to_peak"]) else { return refused(step, key: "relative_to_peak", value: p["relative_to_peak"]) }
            guard let spacing = finiteFloat(p["min_peak_spacing"]) else { return refused(step, key: "min_peak_spacing", value: p["min_peak_spacing"]) }
            guard let edge = int(p["edge_boundary"]) else { return refused(step, key: "edge_boundary", value: p["edge_boundary"]) }
            guard let maxPeaks = int(p["max_peaks"]) else { return refused(step, key: "max_peaks", value: p["max_peaks"]) }
            params.corrPower = corrPower
            params.sigmaDP = sigmaDP
            params.sigmaCC = sigmaCC
            params.subpixel = subpixel
            params.upsampleFactor = upsample
            params.minAbsoluteIntensity = minAbs
            params.minRelativeIntensity = minRel
            params.relativeToPeak = relativeTo
            params.minPeakSpacing = spacing
            params.edgeBoundary = edge
            params.maxNumPeaks = maxPeaks
            return .success(.diskDetection(params))

        case "strain":
            // Vocabulary shared with result provenance (Gate B-lite F10):
            // "whole-scan"/"selected-region", "consensus"/"manual".
            switch p["reference_mode"] {
            case "whole-scan":
                break
            case "selected-region":
                // The recipe records the MODE but not the region geometry, so
                // there is nothing faithful to replay it against.
                return .failure(ReplayRefusal(reason: "it used a selected-region reference and the recipe does not carry the region — pick the reference region on the promoted view and run strain by hand"))
            default:
                return refused(step, key: "reference_mode", value: p["reference_mode"])
            }
            switch p["basis_mode"] {
            case "consensus":
                return .success(.strain(.init(manualBasis: nil)))
            case "manual":
                guard let g1x = finiteFloat(p["resolved_g1_x"]) else { return refused(step, key: "resolved_g1_x", value: p["resolved_g1_x"]) }
                guard let g1y = finiteFloat(p["resolved_g1_y"]) else { return refused(step, key: "resolved_g1_y", value: p["resolved_g1_y"]) }
                guard let g2x = finiteFloat(p["resolved_g2_x"]) else { return refused(step, key: "resolved_g2_x", value: p["resolved_g2_x"]) }
                guard let g2y = finiteFloat(p["resolved_g2_y"]) else { return refused(step, key: "resolved_g2_y", value: p["resolved_g2_y"]) }
                return .success(.strain(.init(manualBasis: .init(g1x: g1x, g1y: g1y, g2x: g2x, g2y: g2y))))
            default:
                return refused(step, key: "basis_mode", value: p["basis_mode"])
            }

        case "acom":
            guard let material = p["material"], !material.isEmpty else {
                return refused(step, key: "material", value: p["material"])
            }
            guard let scale = finiteDouble(p["scale_inv_angstrom_per_pixel"]), scale > 0 else {
                return refused(step, key: "scale_inv_angstrom_per_pixel", value: p["scale_inv_angstrom_per_pixel"])
            }
            // Scope and quality were recorded via `String(describing:)` — case
            // names, not raw values — so they are parsed the same way.
            guard let scopeText = p["scope"],
                  let scope = ACOMRunScope.allCases.first(where: { String(describing: $0) == scopeText }) else {
                return refused(step, key: "scope", value: p["scope"])
            }
            if scope == .selectedRegion {
                return .failure(ReplayRefusal(reason: "it ran on a selected region and the recipe does not carry the region — select it on the promoted view and run ACOM by hand"))
            }
            guard let qualityText = p["quality"],
                  let quality = ACOMQualityPreset.allCases.first(where: { String(describing: $0) == qualityText }) else {
                return refused(step, key: "quality", value: p["quality"])
            }
            return .success(.acom(.init(materialID: material,
                                        scaleInvAngstromPerPixel: scale,
                                        scope: scope,
                                        quality: quality)))

        default:
            // A kind this build does not know — a newer app's recipe, or a
            // hand-edited file. Refusing by name beats dropping it silently.
            return .failure(ReplayRefusal(reason: "this version of mac4DSTEM does not know how to replay a '\(step.kind)' step"))
        }
    }

    // MARK: - Parsing primitives

    private static func refused(_ step: SessionReplayRecord.Step, key: String, value: String?) -> Result<ReplayStepPlan, ReplayRefusal> {
        let described = value.map { "'\($0)'" } ?? "missing"
        return .failure(ReplayRefusal(reason: "its recorded parameter '\(key)' is \(described), which this app cannot read"))
    }

    private static func finiteFloat(_ text: String?) -> Float? {
        guard let text, let value = Float(text), value.isFinite else { return nil }
        return value
    }

    private static func finiteDouble(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func int(_ text: String?) -> Int? {
        text.flatMap(Int.init)
    }
}
