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
//  UNVALIDATED, and the UI says so. Step 3 of `docs/v3-vector-matching-plan.md`
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

    package var id: String { model.id }
    package var zoneAxis: SIMD3<Int> { SIMD3(u, v, w) }
    package var zoneAxisText: String { "[\(u) \(v) \(w)]" }
    /// `orientationRelationshipText` parsed, or empty when it does not parse.
    /// The caller that needs to tell "empty" from "malformed" reads the text
    /// itself; this is for the two places that only want the constraint.
    package var orientationRelationships: [OrientationRelationship] {
        Self.parseOrientationRelationships(orientationRelationshipText) ?? []
    }

    /// Identity for staleness. `contentFingerprint` is what distinguishes two
    /// CIFs that share an id, which `CrystalModel` already records.
    package var signature: String {
        "\(model.id)|\(model.contentFingerprint)|\(isMatrix ? "m" : "c")|\(u),\(v),\(w)"
            + "|\(orientationRelationshipText)"
    }

    package init(model: CrystalModel, isMatrix: Bool, u: Int, v: Int, w: Int,
                 orientationRelationshipText: String = "") {
        self.model = model
        self.isMatrix = isMatrix
        self.u = u; self.v = v; self.w = w
        self.orientationRelationshipText = orientationRelationshipText
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
/// without a view or a running app. Session S3,
/// `docs/v3-precipitate-classification.md` §2 step "wire".
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
    /// as not-yet-carried into that dictionary.
    package static func provenanceAdditions(for matching: PhaseVectorSettings) -> [String: String] {
        guard matching.classificationRule == .knownVariants else { return [:] }
        return [
            "classification_rule": "known_variants",
            "residual_cutoff_inv_angstrom": String(format: "%.4g", matching.residualCutoffInvAngstrom),
            "direct_matrix_maximum_vectors": String(matching.directMatrixMaximumVectors),
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
    package var zoneAxisFits: [PhaseVectorMatcher.ZoneAxisFit] = []
    /// Everything needed to say what produced `map`, and to tell whether the
    /// live controls have moved since.
    package private(set) var lastRun: RunRecord?

    package struct RunRecord: Sendable, Equatable {
        package init(phaseSignature: String, reference: PhaseReferenceSettings,
                     matching: PhaseVectorSettings, libraryEntryCount: Int,
                     matrixEntryIndex: Int, matrixInPlaneDegrees: Double,
                     worstChanceMatchPercent: Double, invAngstromPerPixel: Double,
                     qScaleIsPhysical: Bool, peakCount: Int) {
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
    }

    /// Identity of the current phase list, ORDER-DEPENDENT. The science does
    /// not depend on the order, but the colour a phase is drawn in does:
    /// `PhaseMapPresentation.color` is by list position, the legend keeps the
    /// positions of the run and the phase list shows the current ones. With a
    /// sorted signature, removing a phase and adding it back at the end left
    /// `isStale` false while the list swatch and the legend swatch for that
    /// phase disagreed (found 2026-09-14). A moved phase now reads as stale,
    /// which is the truthful state: the list no longer reads as the legend.
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
        return nil
    }

    /// The library this list and these settings would build, before building
    /// it — so the panel can show the size and the refusal without work.
    package var projectedEntryCount: Int {
        let steps = PhaseReferenceLibrary.inPlaneSteps(reference).count
        return phases.count * steps
    }

    package func publish(_ newMap: PhaseMap, ranWith record: RunRecord) {
        map = newMap
        lastRun = record
    }

    /// The published map's display name. The phase count is in it for the same
    /// reason k is in the diffraction-groups name: two runs over different
    /// phase lists are otherwise indistinguishable in Results and in the
    /// sidecar (`drive-groups` defect 2, 2026-09-06).
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
        zoneAxisFits = []
    }
}
