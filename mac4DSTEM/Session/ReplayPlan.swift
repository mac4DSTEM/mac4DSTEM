//
//  ReplayPlan.swift
//  Role: The executable reading of a `SessionReplayRecord` — v2 S6. Parses each
//        recorded step's flat string parameters back into the typed values the
//        analysis entry points take, and refuses — with a named reason — every
//        step it cannot replay faithfully.
//
//  THE FRAME RULE, decided v2 S6 (2026-08-25), completed v2 S10. Recorded
//  parameters are view-frame numbers: an aperture centre, a smoothing sigma,
//  a g-vector are all in the detector pixels of the view the analysis ran on.
//  A SCAN crop never touches the detector frame, so a recipe recorded on a
//  scan-crop-only rehearsal replays at full extent as-is — the flagship
//  rehearse → promote case. A DETECTOR crop or bin changes what those numbers
//  mean; since S10 the plan RE-REFERENCES them into the source frame — the
//  exact affine inverse of the load-time re-reference, built on
//  `CalibrationReReference`'s own coordinate primitives — and any value with
//  no exact re-expression (an absolute intensity threshold, an unclassified
//  key) still refuses by name, never rounds, never guesses. `.mixed` and
//  `.unknown` frames refuse wholesale, unchanged from S6.
//
//  REFUSAL OVER SKIPPING. A step this file cannot parse, or whose recorded
//  precondition the session cannot honour, halts the run at that step —
//  continuing past it would replay an incoherent pipeline, which is the
//  "silently past a failure" the S6 brief bans.
//
//  WHY App/ AND NOT Core/. This is parsing, and "parsing lives in Core" is
//  the letter of the placement rule — but the parser's whole OUTPUT
//  vocabulary is App workflow state (`VirtualShapeMode`, `Aperture`,
//  `ACOMRunScope`, `ACOMQualityPreset` — session vocabulary, now DSTEMSession), so a Core
//  placement would make Core depend on App, inverting the layering the rule
//  exists to protect. It sits with the types it produces, beside the
//  `SessionReplay` seam whose record it reads. Raised and weighed at S6's
//  Gate A, 2026-08-25.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// Moved here from App/AppState.swift 2026-09-03 (v2.5 step 2c): the recipe
// vocabulary lives with the recipe.
package enum VirtualShapeMode: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case annulus = "Annulus"
    case rectangle = "Rectangle"
    case point = "Point"

    package var id: String { rawValue }
}

/// Which detector frame a recipe's parameters are expressed in. Tracked live
/// on `SessionReplay` (session state, never serialized): set when a recipe is
/// adopted from a sidecar, merged on every live recording, and consulted once
/// at replay time.
package enum ReplayParameterFrame: Equatable {
    /// No detector crop, bin 1 — detector-frame parameters are already
    /// source-frame numbers. A scan crop alone stays in this case.
    case detectorIdentity
    /// Recorded on a reduced detector. Since S10, detector-frame parameters
    /// are RE-REFERENCED into the source frame at plan time — the exact
    /// inverse of the load-time re-reference — instead of refusing wholesale;
    /// individual values that cannot be re-expressed exactly still refuse by
    /// name. The payload carries the actual crop, never a flag: two same-bin
    /// crops at DIFFERENT offsets are different frames, and collapsing them
    /// to one would map every position with the wrong offset. (Latent while
    /// S6 refused this case wholesale; armed the moment mapping exists —
    /// which is why the payload widened in the same session.) // v2 S10
    case detectorReduced(bin: Int, crop: AxisCrop?)
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
    ///
    /// The REQUESTED crop is what a specification carries; the read crop
    /// differs from it only by the bin-edge trim, which comes off the END of
    /// each axis (`LoadView`) — so the OFFSETS, the only part positions
    /// need, are identical. // v2 S10
    package static func of(_ specification: LoadSpecification?) -> ReplayParameterFrame {
        guard let spec = specification,
              spec.detectorCrop != nil || spec.detectorBin > 1 else {
            return .detectorIdentity
        }
        return .detectorReduced(bin: spec.detectorBin, crop: spec.detectorCrop)
    }

    package func merging(_ other: ReplayParameterFrame) -> ReplayParameterFrame {
        self == other ? self : .mixed
    }

    /// Why detector-frame steps refuse under this frame, in the app's voice.
    /// Nil when they can run as-is (`.detectorIdentity`) or be re-referenced
    /// (`.detectorReduced` — whose refusals are per-parameter, from the
    /// mapper, not wholesale). // v2 S10
    package var refusalReason: String? {
        switch self {
        case .detectorIdentity, .detectorReduced:
            return nil
        case .mixed:
            return "the recipe's steps were recorded on two different detector frames, so its detector-pixel parameters have no single meaning — re-run the analyses by hand on the promoted view"
        case .unknown:
            return "the detector frame the recipe was recorded in is unknown, so its detector-pixel parameters cannot be trusted — re-run the analyses by hand on the promoted view"
        }
    }

    /// The transform that re-expresses this frame's recorded numbers in the
    /// SOURCE detector frame — nil when none is needed (identity) or none
    /// exists (`.mixed`/`.unknown`, which refuse instead). // v2 S10
    package var sourceTransform: ReplayFrameTransform? {
        guard case .detectorReduced(let bin, let crop) = self,
              bin > 1 || crop != nil else { return nil }
        return .viewToSource(bin: bin,
                             xOffset: crop?.xOffset ?? 0,
                             yOffset: crop?.yOffset ?? 0)
    }

    /// One sentence for the promote caption and run summary, so a mapped
    /// replay is never a silent substitution: the numbers the entry points
    /// receive are exact re-expressions of the rehearsal's, and the carrier
    /// says so. Nil when nothing was re-referenced. // v2 S10
    package var reReferenceDescription: String? {
        guard case .detectorReduced(let bin, let crop) = self,
              bin > 1 || crop != nil else { return nil }
        let what = switch (crop != nil, bin > 1) {
        case (true, true): "a cropped, ×\(bin)-binned detector"
        case (true, false): "a cropped detector"
        default: "a ×\(bin)-binned detector"
        }
        return "recorded on \(what) — detector-pixel parameters re-referenced to the full detector"
    }
}

/// The affine re-expression of one detector frame's numbers in another's
/// pixels. Both directions live in ONE type so the promote replay
/// (view → source) and the reduced-file export's carried recipe (view → the
/// exported file's own frame) share one role table — two tables is how they
/// drift. The coordinate primitives are `CalibrationReReference`'s, so the
/// forward and inverse maps cannot disagree about the half-pixel. // v2 S10
package enum ReplayFrameTransform: Equatable {
    /// Undo the load-time reduction. `CalibrationReReference.apply` shifts by
    /// the crop offset THEN bins, so the inverse un-bins then shifts back.
    case viewToSource(bin: Int, xOffset: Int, yOffset: Int)
    /// Apply a further export-time bin. The exported reduced file has no
    /// further crop, so there is no offset.
    case viewToExport(bin: Int)

    /// A POSITION moves with the frame: un-bin about the pixel grid, then the
    /// crop offset comes back (or forward: bin about the grid).
    package func positionX(_ value: Float) -> Float {
        switch self {
        case .viewToSource(let bin, let xOffset, _):
            CalibrationReReference.sourceCoordinate(value, bin: bin) + Float(xOffset)
        case .viewToExport(let bin):
            CalibrationReReference.binnedCoordinate(value, bin: bin)
        }
    }

    package func positionY(_ value: Float) -> Float {
        switch self {
        case .viewToSource(let bin, _, let yOffset):
            CalibrationReReference.sourceCoordinate(value, bin: bin) + Float(yOffset)
        case .viewToExport(let bin):
            CalibrationReReference.binnedCoordinate(value, bin: bin)
        }
    }

    /// A LENGTH or DISPLACEMENT (a radius, a smoothing sigma, a g-vector
    /// component) scales with the pixel size and ignores the crop.
    package func length(_ value: Float) -> Float {
        switch self {
        case .viewToSource(let bin, _, _): value * Float(bin)
        case .viewToExport(let bin): value / Float(bin)
        }
    }

    /// A PER-PIXEL SAMPLING INTERVAL (Å⁻¹ per detector pixel) goes the other
    /// way from a length: fewer, bigger pixels each span more.
    package func perPixelScale(_ value: Double) -> Double {
        switch self {
        case .viewToSource(let bin, _, _): value / Double(bin)
        case .viewToExport(let bin): value * Double(bin)
        }
    }

    /// An integer length maps only when the result is exact: ×bin always is,
    /// ÷bin only when divisible. Nil is "no exact value exists", which the
    /// mapper turns into a named refusal rather than a rounding.
    package func lengthInt(_ value: Int) -> Int? {
        switch self {
        case .viewToSource(let bin, _, _): value * bin
        case .viewToExport(let bin): value.isMultiple(of: bin) ? value / bin : nil
        }
    }
}

/// Re-express a recorded step's parameters in another detector frame, or
/// refuse with the parameter named. The role table is the frame vocabulary of
/// the S5 recording sites — like `ReplayPlanner.parse`, it must FOLLOW those
/// sites, never lead them. A key neither classified here nor written by them
/// REFUSES rather than passing through: an unclassified number carried across
/// frames is a fabrication waiting for a reader. // v2 S10
package enum ReplayRecordFrameMap {

    package enum Role {
        case invariant
        case positionX, positionY
        case length
        case lengthInt
        /// Tuned against the correlation response, whose scale changes with
        /// pattern intensity — and binning SUMS pixel blocks. The correlation
        /// is `m·|m|^(p−1)` (DiskDetection), not intensity-normalized, so a
        /// nonzero absolute threshold has no exact value in another frame.
        /// Zero is invariant.
        case absoluteIntensity
        case perPixelScale
    }

    /// Every key the S5 recording sites write, by kind. `nil` = unknown key.
    package static func role(kind: String, key: String) -> Role? {
        switch kind {
        case "virtual_detector":
            switch key {
            case "shape": .invariant
            case "center_x": .positionX
            case "center_y": .positionY
            case "inner", "outer": .length
            default: nil
            }
        case "dpc":
            key == "origin_reference" ? .invariant : nil
        case "disk_detection":
            switch key {
            case "corr_power", "subpixel", "upsample_factor",
                 "min_relative_intensity", "relative_to_peak", "max_peaks",
                 "kernel_source": .invariant
            case "sigma_dp", "sigma_cc", "min_peak_spacing": .length
            case "edge_boundary": .lengthInt
            case "min_absolute_intensity": .absoluteIntensity
            default: nil
            }
        case "strain":
            switch key {
            case "reference_mode", "basis_mode": .invariant
            // g-vectors are DISPLACEMENTS: they scale with the pixel and
            // never see the crop offset. Mapped even for a consensus-basis
            // step (where they are informational) so every carried number
            // stays frame-true.
            case "resolved_g1_x", "resolved_g1_y",
                 "resolved_g2_x", "resolved_g2_y": .length
            default: nil
            }
        case "acom":
            switch key {
            // lattice_a is in Å — frame-invariant. Missing from this table it
            // would drop every custom-phase recipe from a binned export
            // (refuter, Gate D 2026-09-02).
            case "material", "matching_backend", "scope", "quality", "lattice_a": .invariant
            case "scale_inv_angstrom_per_pixel": .perPixelScale
            default: nil
            }
        default:
            nil
        }
    }

    /// Map one step. Total and explicit, like the parser: every value that
    /// cannot be re-expressed EXACTLY becomes a refusal naming the key.
    package static func map(_ step: SessionReplayRecord.Step,
                    through transform: ReplayFrameTransform)
        -> Result<SessionReplayRecord.Step, ReplayRefusal> {
        var mapped = step.parameters
        for (key, text) in step.parameters {
            guard let role = role(kind: step.kind, key: key) else {
                return .failure(ReplayRefusal(reason: "its recorded parameter '\(key)' is not one this app can re-reference between detector frames — re-run it by hand"))
            }
            switch role {
            case .invariant:
                continue
            case .positionX, .positionY, .length:
                guard let value = Float(text), value.isFinite else {
                    return .failure(malformed(key: key, value: text))
                }
                let result: Float = switch role {
                case .positionX: transform.positionX(value)
                case .positionY: transform.positionY(value)
                default: transform.length(value)
                }
                mapped[key] = String(result)
            case .lengthInt:
                guard let value = Int(text) else {
                    return .failure(malformed(key: key, value: text))
                }
                guard let result = transform.lengthInt(value) else {
                    return .failure(ReplayRefusal(reason: "its recorded parameter '\(key)' (\(value) px) does not divide exactly by the export bin, so it has no exact value in the exported frame"))
                }
                mapped[key] = String(result)
            case .absoluteIntensity:
                guard let value = Float(text), value.isFinite else {
                    return .failure(malformed(key: key, value: text))
                }
                if value != 0 {
                    return .failure(ReplayRefusal(reason: "its absolute-intensity threshold (min_absolute_intensity = \(text)) was tuned against the rehearsal frame's correlation scale, which does not survive a detector-frame change — re-run detection by hand and re-tune it"))
                }
            case .perPixelScale:
                guard let value = Double(text), value.isFinite else {
                    return .failure(malformed(key: key, value: text))
                }
                mapped[key] = String(transform.perPixelScale(value))
            }
        }
        return .success(SessionReplayRecord.Step(kind: step.kind,
                                                 parameters: mapped,
                                                 recorded: step.recorded))
    }

    /// The whole-record form for the exported reduced file: a recipe replays
    /// a coherent pipeline or nothing (the S5 rule), so ONE unmappable step
    /// drops the whole record — with the reason, so the export summary can
    /// say what was left out and why instead of the recipe silently missing.
    package static func mapForExport(_ record: SessionReplayRecord, exportBin: Int)
        -> Result<SessionReplayRecord, ReplayRefusal> {
        guard exportBin > 1 else { return .success(record) }
        var steps: [SessionReplayRecord.Step] = []
        for step in record.steps {
            switch map(step, through: .viewToExport(bin: exportBin)) {
            case .success(let mapped):
                steps.append(mapped)
            case .failure(let refusal):
                return .failure(ReplayRefusal(reason: "the recorded \(ReplayPlanner.title(forKind: step.kind)) step cannot be re-expressed in the exported file's detector frame: \(refusal.reason)"))
            }
        }
        var mapped = record
        mapped.steps = steps
        return .success(mapped)
    }

    private static func malformed(key: String, value: String?) -> ReplayRefusal {
        let described = value.map { "'\($0)'" } ?? "missing"
        return ReplayRefusal(reason: "its recorded parameter '\(key)' is \(described), which this app cannot read")
    }
}

/// A step the replay cannot run, with the reason a person can act on.
/// `Error` only because `Result` requires it — a refusal is never thrown.
package struct ReplayRefusal: Equatable, Error {
    package let reason: String

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(reason: String) {
        self.reason = reason
    }
}

/// One recorded step, parsed back into the typed values its entry point takes.
/// Parsing is total and explicit: every missing, malformed or out-of-vocabulary
/// value becomes a `ReplayRefusal` naming the key — never a default.
package enum ReplayStepPlan: Equatable {
    case virtualDetector(shape: VirtualShapeMode, aperture: Aperture)
    /// `wantsFittedOrigin` mirrors the recorded `origin_reference`: replay must
    /// run against the same origin class or refuse — silently substituting the
    /// other one would be a parameter change the summary never states.
    case dpc(wantsFittedOrigin: Bool)
    case diskDetection(DiskDetectionParams)
    case strain(StrainReplayPlan)
    case acom(ACOMReplayPlan)

    package struct StrainReplayPlan: Equatable {
        /// Manual g-vectors when the recorded basis was manual; nil replays the
        /// automatic (consensus) basis, which re-derives on the full data —
        /// the recorded resolved_g values are informational for that mode
        /// (the fidelity decision S5 left to S6).
        package var manualBasis: ManualBasis?
        package struct ManualBasis: Equatable {
            package var g1x: Float, g1y: Float, g2x: Float, g2y: Float

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
            package nonisolated init(g1x: Float, g1y: Float, g2x: Float, g2y: Float) {
                self.g1x = g1x
                self.g1y = g1y
                self.g2x = g2x
                self.g2y = g2y
            }
        }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(manualBasis: ManualBasis? = nil) {
            self.manualBasis = manualBasis
        }
    }

    package struct ACOMReplayPlan: Equatable {
        package var materialID: String
        /// Lattice constant (Å) the custom-cubic model was rehearsed with. The
        /// custom id encodes structure and Z but not a₀, so without this a
        /// restored session whose `a` field drifted replayed a different
        /// crystal under the same id (Gate D 2026-09-02). nil for library and
        /// imported ids, and for records that predate the key.
        package var latticeA: Double? = nil
        /// The scale the run matched at, in Å⁻¹ per detector pixel. Replay
        /// verifies the session's scale semantics agree before running —
        /// matching at a different scale gets every orientation wrong with no
        /// shape check to catch it (the Gate B-lite F3 lesson).
        package var scaleInvAngstromPerPixel: Double
        package var scope: ACOMRunScope
        package var quality: ACOMQualityPreset

        /// What the session holds that a recorded material id can resolve
        /// against. Library models are global and need no field.
        package struct SessionMaterials {
            package var importedIDs: Set<String>
            package var customStructure: Crystal.CubicStructure
            package var customLatticeA: Double
            package var customZ: Int

            // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
            package nonisolated init(importedIDs: Set<String>, customStructure: Crystal.CubicStructure, customLatticeA: Double, customZ: Int) {
                self.importedIDs = importedIDs
                self.customStructure = customStructure
                self.customLatticeA = customLatticeA
                self.customZ = customZ
            }
        }

        /// The parameters the record site writes — built here so the write
        /// path is pinned by the same tests that pin the parser. `lattice_a`
        /// comes from the model that ran, not from the selection.
        package static func recordedParameters(model: CrystalModel, scale: Double, backend: String,
                                       scope: ACOMRunScope, quality: ACOMQualityPreset) -> [String: String] {
            var p = [
                "material": model.id,
                "scale_inv_angstrom_per_pixel": String(scale),
                "matching_backend": backend,
                "scope": String(describing: scope),
                "quality": String(describing: quality),
            ]
            if model.source == .custom { p["lattice_a"] = String(model.crystal.a) }
            return p
        }

        package enum MaterialResolution: Equatable {
            case library(String)
            case imported(String)
            case customCubic
            /// The refusal reason, in the recipe summary's voice.
            case unavailable(String)
        }

        /// Resolve the recorded material BY ID — a replay that cannot resolve
        /// it fails by name, never falls back to a different crystal. Library
        /// first, then the session's imports, then the session's custom-cubic
        /// fields when they produce exactly the recorded id AND the recorded
        /// lattice constant. Pure so the arm is testable without running ACOM.
        package func resolveMaterial(in session: SessionMaterials) -> MaterialResolution {
            if CrystalModelLibrary.model(id: materialID) != nil { return .library(materialID) }
            if session.importedIDs.contains(materialID) { return .imported(materialID) }
            let custom = CrystalModelLibrary.customCubic(
                structure: session.customStructure, latticeA: session.customLatticeA,
                atomicNumber: session.customZ)
            guard custom.id == materialID else {
                return .unavailable("the recipe's phase model '\(materialID)' is not available in this session — select or import the phase model it names, then run ACOM by hand")
            }
            guard let latticeA else {
                return .unavailable("the recipe's custom phase '\(custom.displayName)' was recorded before recipes carried the lattice constant — confirm a matches the rehearsal, then run ACOM by hand")
            }
            guard abs(latticeA - session.customLatticeA) <= max(1e-9, abs(latticeA) * 1e-6) else {
                return .unavailable(String(
                    format: "the recipe's custom phase was rehearsed with a = %.4g Å but this session has a = %.4g Å — set a to the rehearsed value or run ACOM by hand",
                    latticeA, session.customLatticeA))
            }
            return .customCubic
        }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(materialID: String, latticeA: Double? = nil, scaleInvAngstromPerPixel: Double, scope: ACOMRunScope, quality: ACOMQualityPreset) {
            self.materialID = materialID
            self.latticeA = latticeA
            self.scaleInvAngstromPerPixel = scaleInvAngstromPerPixel
            self.scope = scope
            self.quality = quality
        }
    }

    /// Whether this step consumes recorded numbers denominated in detector
    /// pixels (positions, lengths, per-pixel scales). These are the steps the
    /// frame rule gates. Automatic-basis strain replays modes only, so it is
    /// deliberately not gated; its detector-frame inputs are the freshly
    /// replayed disk detection's, not recorded numbers.
    package var usesDetectorFrameParameters: Bool {
        switch self {
        case .virtualDetector, .diskDetection, .acom: true
        case .dpc: false
        case .strain(let plan): plan.manualBasis != nil
        }
    }
}

/// A record step with its parse outcome and display title, in pipeline order.
package struct PlannedReplayStep: Equatable {
    package let kind: String
    package let title: String
    package let result: Result<ReplayStepPlan, ReplayRefusal>

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(kind: String, title: String, result: Result<ReplayStepPlan, ReplayRefusal>) {
        self.kind = kind
        self.title = title
        self.result = result
    }
}

package enum ReplayPlanner {

    /// Titles for the summary and progress UI, by recorded kind.
    package static func title(forKind kind: String) -> String {
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
    package static func plan(_ record: SessionReplayRecord,
                     frame: ReplayParameterFrame) -> [PlannedReplayStep] {
        let transform = frame.sourceTransform
        var sawDiskDetection = false
        return record.steps.map { recorded in
            // Re-reference FIRST, parse second (v2 S10): the parser's numeric
            // guards then run against the exact numbers the entry points will
            // receive. A step whose mapping refuses is refused outright —
            // including one whose only unmappable value is informational,
            // because a step carrying a number this app cannot re-express is
            // not a step it can attest to.
            let step: SessionReplayRecord.Step
            var mappingRefusal: ReplayRefusal?
            if let transform {
                switch ReplayRecordFrameMap.map(recorded, through: transform) {
                case .success(let mapped):
                    step = mapped
                case .failure(let refusal):
                    step = recorded
                    mappingRefusal = refusal
                }
            } else {
                step = recorded
            }
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
            if let mappingRefusal {
                parsed = .failure(mappingRefusal)
            }
            if case .success(let plan) = parsed,
               plan.usesDetectorFrameParameters,
               let reason = frame.refusalReason {
                parsed = .failure(ReplayRefusal(reason: reason))
            }
            return PlannedReplayStep(kind: recorded.kind,
                                     title: title(forKind: recorded.kind),
                                     result: parsed)
        }
    }

    /// Parse one step. The keys and vocabularies are exactly what the S5
    /// recording sites write (`AppState.recordReplayStep` call sites) — this
    /// function must follow those sites, never lead them.
    package static func parse(_ step: SessionReplayRecord.Step) -> Result<ReplayStepPlan, ReplayRefusal> {
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
            // Optional key: absent on records that predate it. Present but
            // unparseable is a refusal like every other malformed value.
            var latticeA: Double? = nil
            if let text = p["lattice_a"] {
                guard let value = finiteDouble(text), value > 0 else {
                    return refused(step, key: "lattice_a", value: text)
                }
                latticeA = value
            }
            return .success(.acom(.init(materialID: material,
                                        latticeA: latticeA,
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
