//
//  PhaseMappingProduct.swift
//  Role: owns the vector-matched phase-mapping result and its run controls —
//        the phase list, the two Core settings structs, the map, and what the
//        map was actually run with. Mirrors `DiffractionGroupsProduct`'s seam:
//        `AppState+PhaseMapping.swift` is the only writer; views read
//        `phaseMapping.…` directly, with no forwarding properties on AppState.
//
//  Method: Thronsen et al., Ultramicroscopy 255 (2024) 113861, CC BY 4.0 —
//  implemented from the published description; their repository has no licence
//  and is not used. See `Core/Crystal/PhaseVectorMatching.swift`.
//
//  UNVALIDATED, and the UI says so. Step 3 of `docs/v3-features.md#vector-matching`
//  — scoring this against their published ground truth — has not run, so
//  `quantitativeStatus` below is `exploratory` and the result carries
//  `validation: "none"` into every export. That is a decision, not an
//  oversight: the feature is useful for looking, and a density taken off it is
//  not a measurement until the acceptance test passes.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation
import simd

/// One phase the user put in the list: a structure model, its role, and the
/// beam direction to sample it along.
///
/// It holds a `CrystalModel` rather than a bare `Crystal` so an imported CIF
/// arrives with its id, display name, source and content fingerprint already
/// attached — the same object ACOM's phase picker uses, which is what lets one
/// import serve both rooms.
package struct PhaseMappingSlot: Identifiable, Sendable, Equatable {
    package var model: CrystalModel
    /// Exactly one slot in the list is the matrix. It is stated, never
    /// inferred: which phase is the bulk is knowledge about the specimen.
    package var isMatrix: Bool
    /// Beam direction in lattice indices. Real-space, so [001] of a monoclinic
    /// cell is not the Cartesian z — see `PhaseReferenceLibrary.cartesianZoneAxis`.
    package var u: Int, v: Int, w: Int
    /// The orientation relationship to the matrix, kept as the user typed it —
    /// one field fits the inspector, and "(002) ∥ (200)" is how a paper
    /// states an OR, not a pre-parsed pair. Empty (the default) is free: no
    /// constraint on the in-plane rotation.
    package var orientationRelationshipText: String = ""
    /// This phase's excitation slab (Å⁻¹), or nil for the library's global value.
    /// Thronsen et al. use 0.300 for θ′ and 0.030 for T1 in one run; one global
    /// field cannot hold both (B1 reproduction, 2026-09-28).
    package var excitationSlabInvAngstrom: Double?
    /// The slot's own identity. Not the CIF's: the same structure can sit in the
    /// list twice, once per zone axis (θ′ edge-on [100] and face-on [001]), and
    /// keying slots by `model.id` made the second one collide silently.
    package var slotID = UUID()

    package var id: String { slotID.uuidString }
    package var zoneAxis: SIMD3<Int> { SIMD3(u, v, w) }
    package var zoneAxisText: String { "[\(u) \(v) \(w)]" }
    /// `orientationRelationshipText` parsed, or empty when it does not parse.
    /// The caller that needs to tell "empty" from "malformed" reads the text
    /// itself; this is for the two places that only want the constraint.
    package var orientationRelationships: [OrientationRelationship] {
        Self.parseOrientationRelationships(orientationRelationshipText) ?? []
    }

    /// The structure alone — id and content fingerprint — for the checks that
    /// ask "is this still the same crystal": not the zone axis (a fit writes
    /// it), not the flags.
    package var matrixIdentity: String { "\(model.id)|\(model.contentFingerprint)" }

    /// Identity for staleness. `contentFingerprint` is what distinguishes two
    /// CIFs that share an id, which `CrystalModel` already records.
    package var signature: String {
        "\(model.id)|\(model.contentFingerprint)|\(isMatrix ? "m" : "c")|\(u),\(v),\(w)"
            + "|\(orientationRelationshipText)|\(excitationSlabInvAngstrom.map { String($0) } ?? "global")"
    }

    package init(model: CrystalModel, isMatrix: Bool, u: Int, v: Int, w: Int,
                 orientationRelationshipText: String = "", excitationSlabInvAngstrom: Double? = nil) {
        self.model = model
        self.isMatrix = isMatrix
        self.u = u; self.v = v; self.w = w
        self.orientationRelationshipText = orientationRelationshipText
        self.excitationSlabInvAngstrom = excitationSlabInvAngstrom
    }

    /// "0 1 0", "0,1,0", "[010]" or "0 -1 2" — three integers however a
    /// crystallographer happens to write them. Nil when it is not three
    /// integers, so the caller can keep the last valid axis instead of
    /// silently becoming [0 0 0], which names no direction.
    package static func parseZoneAxis(_ text: String) -> SIMD3<Int>? {
        let cleaned = text.replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: ",", with: " ")
        var fields = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        // "010" and "0-12": single-token forms, one signed digit each.
        if fields.count == 1, let only = fields.first, only.count >= 3 {
            var split: [String] = []
            var current = ""
            for ch in only {
                if ch == "-" { if !current.isEmpty { split.append(current) }; current = "-" }
                else if ch.isNumber { current.append(ch); split.append(current); current = "" }
                else { return nil }
            }
            guard current.isEmpty else { return nil }
            fields = split
        }
        guard fields.count == 3 else { return nil }
        let values = fields.compactMap(Int.init)
        guard values.count == 3 else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    /// Grammar: pairs "A ∥ B" separated by "," or ";" — ∥, ||, // or | all
    /// accepted as the parallel sign, A this phase's vector and B the
    /// matrix's, each a plane "(hkl)" (parens optional, `parseZoneAxis`
    /// rules inside) or a direction "[uvw]" (brackets required). Empty or
    /// whitespace is `[]`, not a refusal — a string field is used because one
    /// field fits the inspector and "(002) ∥ (200)" is how a paper writes it.
    package static func parseOrientationRelationships(_ text: String) -> [OrientationRelationship]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var out: [OrientationRelationship] = []
        for rawPair in trimmed.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            guard let pair = parseOneOrientationPair(String(rawPair)) else { return nil }
            out.append(pair)
        }
        return out
    }

    /// Longest signs first, so "||" is not read as a lone "|" cut short.
    private static let orientationParallelSigns = ["∥", "||", "//", "|"]

    private static func parseOneOrientationPair(_ text: String) -> OrientationRelationship? {
        let s = text.trimmingCharacters(in: .whitespaces)
        for sign in orientationParallelSigns {
            guard let range = s.range(of: sign) else { continue }
            let lhs = String(s[s.startIndex..<range.lowerBound])
            let rhs = String(s[range.upperBound...])
            guard let candidate = parseOrientationVector(lhs),
                  let matrix = parseOrientationVector(rhs) else { return nil }
            return OrientationRelationship(candidate: candidate, matrix: matrix)
        }
        return nil
    }

    /// "[uvw]" (brackets required) is a direction; "(hkl)", or bare "hkl"
    /// with parens optional, is a plane. Either way the three integers
    /// inside parse by `parseZoneAxis`'s own rules.
    private static func parseOrientationVector(_ text: String) -> LatticeVector? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("[") {
            guard s.hasSuffix("]") else { return nil }
            guard let v = parseZoneAxis(String(s.dropFirst().dropLast())) else { return nil }
            return .direction(v)
        }
        if s.hasPrefix("(") {
            guard s.hasSuffix(")") else { return nil }
            guard let v = parseZoneAxis(String(s.dropFirst().dropLast())) else { return nil }
            return .plane(v)
        }
        guard let v = parseZoneAxis(s) else { return nil }
        return .plane(v)
    }

    package static func == (lhs: PhaseMappingSlot, rhs: PhaseMappingSlot) -> Bool {
        lhs.signature == rhs.signature && lhs.model.displayName == rhs.model.displayName
    }
}

/// Two small pure functions the classifier picker needs
/// (`UI/PhaseMappingSettings.swift`) and `AppState+PhaseMapping.swift`'s
/// provenance writer needs — kept here, in Session, so both are testable
/// without a view or a running app
/// (`docs/v3-features.md#precipitate-classification` §2 step "wire").
package enum PhaseMappingRuleDefaults {
    /// What the picker sets `PhaseReferenceSettings.minimumIntensityFraction`
    /// to when the classifier rule changes — a UI DEFAULT applied once, not
    /// a constraint `PhaseReferenceLibrary` itself enforces, so the user can
    /// still edit the field afterwards. `.knownVariants` (Thronsen et al.'s
    /// own rule, `PhaseVectorMatching.swift` "The known-variants rule"):
    /// every surviving vector is scored, unranked by intensity, so a floor
    /// only discards information the argmin needs — 0. `.search`: the
    /// shipped default, read from `PhaseReferenceSettings` itself rather
    /// than copied as a literal, so the two can never drift apart.
    package static func minimumIntensityFraction(
        for rule: PhaseVectorSettings.ClassificationRule
    ) -> Double {
        switch rule {
        case .knownVariants: return 0
        case .search: return PhaseReferenceSettings().minimumIntensityFraction
        }
    }

    /// Additive sidecar-provenance keys for `matching.classificationRule`.
    /// Empty for `.search`, so `AppState+PhaseMapping.swift`'s hand-written
    /// `phaseProvenance` dictionary is BYTE-IDENTICAL to before this session
    /// for the shipped default (checked by
    /// `PhaseMapObjectsWiringTests`); `.knownVariants` contributes the three
    /// keys `PhaseVectorSettings.classificationRule`'s own doc comment named
    /// as not-yet-carried into that dictionary, plus the evidence guard's.
    package static func provenanceAdditions(for matching: PhaseVectorSettings) -> [String: String] {
        guard matching.classificationRule == .knownVariants else { return [:] }
        return [
            "classification_rule": "known_variants",
            "residual_cutoff_inv_angstrom": String(format: "%.4g", matching.residualCutoffInvAngstrom),
            "direct_matrix_maximum_vectors": String(matching.directMatrixMaximumVectors),
            // The evidence guard (Gate D 2026-09-23): a saved map records
            // whether it was guarded.
            "known_variants_minimum_specific_reflections":
                String(matching.knownVariantsMinimumSpecificReflections),
        ]
    }
}

@Observable
@MainActor
package final class PhaseMappingProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    // MARK: Run controls (survive a dataset change, like StrainProduct's)

    /// The phase list. Empty is the honest starting state: this method cannot
    /// guess a specimen's phases, and a pre-seeded aluminium would be a guess
    /// wearing the look of a default.
    package var phases: [PhaseMappingSlot] = []
    package var reference = PhaseReferenceSettings()
    package var matching = PhaseVectorSettings()

    // MARK: Result

    package private(set) var map: PhaseMap?
    /// The top few zone-axis fits from the last `findMatrixZoneAxis`, so the
    /// panel can show the runners-up. A tie across a symmetry-equivalent
    /// family is what says the fit is real rather than arbitrary, and only the
    /// runners-up show it. Cleared with the dataset, like the map.
    package private(set) var zoneAxisFits: [PhaseVectorMatcher.ZoneAxisFit] = []
    /// The Q scale and calibration `zoneAxisFits` were computed under, written
    /// with them and cleared with them (S4: the list used to outlive a
    /// calibration change and read as current).
    package private(set) var zoneAxisRun: ZoneAxisRun?

    package func setZoneAxisFits(_ fits: [PhaseVectorMatcher.ZoneAxisFit], ranWith run: ZoneAxisRun) {
        zoneAxisFits = fits
        zoneAxisRun = run
    }

    /// The structure of the phase marked as the matrix now, or "" when none is
    /// (`PhaseMappingSlot.matrixIdentity`).
    package var matrixIdentity: String {
        phases.first(where: \.isMatrix)?.matrixIdentity ?? ""
    }

    /// Why the shown zone-axis list must not be offered against the live
    /// calibration, or nil. The list is dropped, not recomputed: only a rerun
    /// answers for the new scale.
    package func zoneAxisStaleness(currentInvAngstromPerPixel q: Double,
                                   currentCalibration: CalibrationStamp) -> String? {
        guard !zoneAxisFits.isEmpty else { return nil }
        return zoneAxisRun?.staleness(
            currentInvAngstromPerPixel: q, currentCalibration: currentCalibration,
            currentMatrixPhase: matrixIdentity,
            currentMatrixToleranceInvAngstrom: matching.matrixToleranceInvAngstrom)
    }
    /// Everything needed to say what produced `map`, and to tell whether the
    /// live controls have moved since.
    package private(set) var lastRun: RunRecord?
    /// The reference library `lastRun` was made with, kept so the claimed-disks
    /// overlay does not rebuild it (seconds) every time its layer is created.
    /// One pair: it dies with the run (`publish` replaces it, `clear` drops
    /// it). nil when a run was published without one.
    package private(set) var lastLibrary: PhaseReferenceLibrary?

    package struct RunRecord: Sendable, Equatable {
        package init(phaseSignature: String, reference: PhaseReferenceSettings,
                     matching: PhaseVectorSettings, libraryEntryCount: Int,
                     matrixEntryIndex: Int, matrixInPlaneDegrees: Double,
                     worstChanceMatchPercent: Double, invAngstromPerPixel: Double,
                     qScaleIsPhysical: Bool, peakCount: Int,
                     calibration: CalibrationStamp) {
            self.phaseSignature = phaseSignature
            self.reference = reference
            self.matching = matching
            self.libraryEntryCount = libraryEntryCount
            self.matrixEntryIndex = matrixEntryIndex
            self.matrixInPlaneDegrees = matrixInPlaneDegrees
            self.worstChanceMatchPercent = worstChanceMatchPercent
            self.invAngstromPerPixel = invAngstromPerPixel
            self.qScaleIsPhysical = qScaleIsPhysical
            self.peakCount = peakCount
            self.calibration = calibration
        }

        package var phaseSignature: String
        package var reference: PhaseReferenceSettings
        package var matching: PhaseVectorSettings
        package var libraryEntryCount: Int
        package var matrixEntryIndex: Int
        package var matrixInPlaneDegrees: Double
        /// Chance-match fraction of the densest candidate entry, as a
        /// percentage. The number that says whether a match carries
        /// information — see `PhaseOrientationReference.chanceMatchFraction`.
        package var worstChanceMatchPercent: Double
        package var invAngstromPerPixel: Double
        package var qScaleIsPhysical: Bool
        package var peakCount: Int
        /// The origin and ellipse the run calibrated its Bragg vectors with.
        /// Always recorded: `lastRun` is memory-only and cleared on every load,
        /// so no run exists that predates the stamp.
        package var calibration: CalibrationStamp

        /// Why the claimed-disks overlay must not be drawn against this run,
        /// or nil. The overlay re-calibrates the raw peaks with the CURRENT
        /// calibration and replays the matcher's pairing against this run's
        /// entry; if the Q scale, the origin or the ellipse differs from what
        /// the run used, the rings would answer a different question than the
        /// map's colours (Fable review of aa920d0, 2026-09-30: only Q was
        /// compared). Pure, so the comparison is unit-tested.
        package func claimsRefusal(currentInvAngstromPerPixel q: Double,
                                   currentCalibration: CalibrationStamp) -> String? {
            guard abs(q - invAngstromPerPixel) <= 1e-12 * max(1, abs(invAngstromPerPixel)) else {
                return "Q calibration changed since the map — run again"
            }
            guard calibration == currentCalibration else {
                return "Origin or ellipse changed since the map — run again"
            }
            return nil
        }
    }

    /// The claimed-disks overlay's task key for the calibration. The quick
    /// stamp cannot tell two origin fits apart that share a mean origin and map
    /// dimensions (Measure Origin again, Constant then Plane, no Clear in
    /// between), yet `BraggVectors.calibrated` re-centres every position on
    /// `fittedX/Y`. The arrays themselves join the key: Swift compares equal
    /// buffers by identity first, so an unchanged calibration costs O(1) per
    /// SwiftUI body pass where a digest would walk both maps.
    package struct CalibrationKey: Equatable {
        package var quick: CalibrationStamp
        package var fittedX: [Float]?
        package var fittedY: [Float]?

        package nonisolated init(calibration: Calibration, referenceOrigin: (x: Float, y: Float)) {
            quick = CalibrationStamp(calibration: calibration, referenceOrigin: referenceOrigin,
                                     includeMapDigest: false)
            fittedX = calibration.origin?.fittedX
            fittedY = calibration.origin?.fittedY
        }
    }

    /// What a Find Matrix Zone Axis ranking was computed under.
    package struct ZoneAxisRun: Sendable, Equatable {
        package var invAngstromPerPixel: Double
        package var calibration: CalibrationStamp
        /// The matrix phase the axes were fitted for (`PhaseMappingSlot.matrixIdentity`:
        /// the structure, not its zone axis — the fit itself writes the winner
        /// into the slot's axis, which must not read as "changed").
        package var matrixPhase: String
        /// The tolerance the sweep scored with (`fitZoneAxis`: `matrixToleranceInvAngstrom`).
        package var matrixToleranceInvAngstrom: Double

        package init(invAngstromPerPixel: Double, calibration: CalibrationStamp,
                     matrixPhase: String, matrixToleranceInvAngstrom: Double) {
            self.invAngstromPerPixel = invAngstromPerPixel
            self.calibration = calibration
            self.matrixPhase = matrixPhase
            self.matrixToleranceInvAngstrom = matrixToleranceInvAngstrom
        }

        package func staleness(currentInvAngstromPerPixel q: Double,
                               currentCalibration: CalibrationStamp,
                               currentMatrixPhase: String,
                               currentMatrixToleranceInvAngstrom tolerance: Double) -> String? {
            guard abs(q - invAngstromPerPixel) <= 1e-12 * max(1, abs(invAngstromPerPixel)) else {
                return "The Q scale changed since this ranking — fit again"
            }
            guard calibration == currentCalibration else {
                return "The origin or ellipse changed since this ranking — fit again"
            }
            guard matrixPhase == currentMatrixPhase else {
                return "The matrix phase changed since this ranking — fit again"
            }
            guard abs(tolerance - matrixToleranceInvAngstrom) <= 1e-12 * max(1, abs(matrixToleranceInvAngstrom)) else {
                return "The matrix removal tolerance changed since this ranking — fit again"
            }
            return nil
        }
    }

    /// The part of `Calibration` that moves Bragg-vector positions before
    /// matching (`BraggVectors.calibrated`): the reference origin, the ellipse
    /// and, when they are used, the per-position origin maps. Q is compared
    /// separately (`RunRecord.invAngstromPerPixel`). There was no such
    /// fingerprint in the code to reuse.
    package struct CalibrationStamp: Sendable, Equatable {
        package var originX: Float
        package var originY: Float
        /// a, b, theta — empty when the calibration has no valid ellipse.
        package var ellipse: [Double]
        /// Size and FNV-1a digest of the fitted origin maps; nil when there are none.
        package var originMaps: OriginMapsStamp?

        package struct OriginMapsStamp: Sendable, Equatable {
            package var width: Int, height: Int, count: Int
            package var digest: UInt64
        }

        /// `includeMapDigest: false` is for a SwiftUI task key, which is
        /// evaluated on every body pass; the digest walks both maps.
        package nonisolated init(calibration: Calibration, referenceOrigin: (x: Float, y: Float),
                                 includeMapDigest: Bool = true) {
            originX = referenceOrigin.x
            originY = referenceOrigin.y
            ellipse = calibration.hasEllipse
                ? [calibration.ellipseA ?? 0, calibration.ellipseB ?? 0, calibration.ellipseTheta ?? 0] : []
            if let maps = calibration.origin {
                var hash: UInt64 = 0xcbf29ce484222325
                if includeMapDigest {
                    for value in maps.fittedX + maps.fittedY {
                        hash = (hash ^ UInt64(value.bitPattern)) &* 0x100000001b3
                    }
                }
                originMaps = OriginMapsStamp(width: maps.width, height: maps.height,
                                             count: maps.fittedX.count, digest: hash)
            } else {
                originMaps = nil
            }
        }
    }

    /// Identity of the current phase list, ORDER-DEPENDENT. The science does
    /// not depend on the order, but the colour a phase is drawn in does:
    /// `PhaseMapPresentation.color` is by list position, the legend keeps the
    /// positions of the run and the phase list shows the current ones. With a
    /// sorted signature, removing a phase and adding it back at the end left
    /// `isStale` false while the list swatch and the legend swatch for that
    /// phase disagreed. A moved phase now reads as stale, which is the
    /// truthful state: the list no longer reads as the legend.
    package var phaseSignature: String {
        phases.map(\.signature).joined(separator: ";")
    }

    package var isStale: Bool {
        guard let lastRun else { return false }
        return lastRun.phaseSignature != phaseSignature
            || lastRun.reference != reference
            || lastRun.matching != matching
    }

    /// Why the run button is not available, in one sentence, or nil.
    /// Stated here rather than in the view so the same words reach the
    /// keyboard path and the toolbar button.
    package var runRefusal: String? {
        let matrices = phases.filter(\.isMatrix).count
        if phases.isEmpty { return "Add the matrix phase and at least one precipitate phase." }
        if matrices == 0 { return "Mark one phase as the matrix." }
        if matrices > 1 { return "Exactly one phase can be the matrix; \(matrices) are marked." }
        if phases.count < 2 { return "Add a candidate phase to look for." }
        if phases.contains(where: { $0.zoneAxis == SIMD3(0, 0, 0) }) {
            return "A zone axis of [0 0 0] names no direction."
        }
        for slot in phases where !slot.model.isUsable {
            return "\(slot.model.displayName) has validation issues and cannot be used."
        }
        // The same structure twice is allowed (one slot per zone axis); twice at the
        // same zone axis is the same reference twice, which can only split its votes.
        for (i, slot) in phases.enumerated() {
            if phases[..<i].contains(where: { $0.model.id == slot.model.id
                && $0.model.contentFingerprint == slot.model.contentFingerprint && $0.zoneAxis == slot.zoneAxis }) {
                return "\(slot.model.displayName) is in the list twice at \(slot.zoneAxisText); give each copy its own zone axis."
            }
        }
        return nil
    }

    /// Change the phase with this id, if it is still in the list. Deferred
    /// writes (`PendingEdits` flushes a field's closure as it was at the last
    /// keystroke) must name a phase by its stable id: a list position captured
    /// then names a different phase once an earlier one has been removed.
    /// Returns whether the phase was found.
    @discardableResult
    package func updatePhase(id: String, _ change: (inout PhaseMappingSlot) -> Void) -> Bool {
        guard let i = phases.firstIndex(where: { $0.id == id }) else { return false }
        change(&phases[i])
        return true
    }

    /// The one rule for adding a phase (moved out of AppState 2026-09-28): the first
    /// phase in an empty list becomes the matrix, since a list with phases and no
    /// matrix cannot run. A structure already in the list is added again, because
    /// one structure seen along two zone axes is two phases (θ′ edge-on [100] and
    /// face-on [001]); until its zone axis differs, `runRefusal` says so. Before
    /// 2026-09-28 the second add was skipped without a word. Returns whether the
    /// structure was already in the list.
    @discardableResult
    package func add(_ model: CrystalModel) -> Bool {
        let repeated = phases.contains(where: { $0.model.id == model.id })
        phases.append(PhaseMappingSlot(model: model, isMatrix: phases.isEmpty, u: 0, v: 0, w: 1))
        return repeated
    }

    /// Al–Mg–Si preset: the DATASET-INDEPENDENT phase setup only (owner
    /// decision 2026-09-30, from `docs/archive/v4/almgsi-raw-stride3-registration-2026-09-29.md`
    /// "The app recipe for this cube"). Replaces the phase list with
    /// Al (matrix, zone [0 0 1]) and the given β″ (Mg5Si6) structure twice —
    /// zone [0 1 0] (needles end-on) and [0 0 1] (in-plane) — with
    /// "Parallel to matrix" empty, and selects the Known-variants classifier
    /// (with that rule's own intensity-floor default, exactly what the picker
    /// does on a switch). It touches NOTHING else: not the tolerances, not
    /// the reference settings beyond that floor, and — living elsewhere — not
    /// the calibration (ellipse, Q, R). A calibration is a property of its
    /// dataset and is never a default (CLAUDE.md, the threshold rule).
    /// The β″ structure is passed in because the repo does not redistribute
    /// its CIF (`tools/crystal-structures/make_beta_double_prime.py`).
    /// Stale zone-axis fits belonged to the old list and are dropped.
    package func applyAlMgSiPreset(precipitate: CrystalModel,
                                   matrix: CrystalModel? = CrystalModelLibrary.model(id: "al_fcc")) {
        guard let matrix else { return }
        phases = [
            PhaseMappingSlot(model: matrix, isMatrix: true, u: 0, v: 0, w: 1),
            PhaseMappingSlot(model: precipitate, isMatrix: false, u: 0, v: 1, w: 0),
            PhaseMappingSlot(model: precipitate, isMatrix: false, u: 0, v: 0, w: 1),
        ]
        if matching.classificationRule != .knownVariants {
            matching.classificationRule = .knownVariants
            reference.minimumIntensityFraction =
                PhaseMappingRuleDefaults.minimumIntensityFraction(for: .knownVariants)
        }
        zoneAxisFits = []
        zoneAxisRun = nil
    }

    /// The library this list and these settings would build, before building
    /// it — so the panel can show the size and the refusal without work.
    package var projectedEntryCount: Int {
        let steps = PhaseReferenceLibrary.inPlaneSteps(reference).count
        return phases.count * steps
    }

    package func publish(_ newMap: PhaseMap, ranWith record: RunRecord,
                         library: PhaseReferenceLibrary? = nil) {
        map = newMap
        lastRun = record
        lastLibrary = library
    }

    /// The published map's display name. The phase count is in it for the same
    /// reason k is in the diffraction-groups name: two runs over different
    /// phase lists are otherwise indistinguishable in Results and in the
    /// sidecar (`drive-groups` defect 2).
    package nonisolated static func mapDisplayName(candidatePhases: Int) -> String {
        "Phase map (\(candidatePhases) candidate\(candidatePhases == 1 ? "" : "s"))"
    }

    package nonisolated static let distanceDisplayName = "Phase match distance"

    /// Dataset activation: the map dies with the dataset, the controls do not.
    /// A phase list is about the specimen the user is studying and survives
    /// switching between cubes of the same alloy, which is the whole workflow
    /// the multi-dataset density needs.
    package func clear() {
        map = nil
        lastRun = nil
        lastLibrary = nil
        zoneAxisFits = []
        zoneAxisRun = nil
    }
}
