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

    package var id: String { model.id }
    package var zoneAxis: SIMD3<Int> { SIMD3(u, v, w) }
    package var zoneAxisText: String { "[\(u) \(v) \(w)]" }

    /// Identity for staleness. `contentFingerprint` is what distinguishes two
    /// CIFs that share an id, which `CrystalModel` already records.
    package var signature: String {
        "\(model.id)|\(model.contentFingerprint)|\(isMatrix ? "m" : "c")|\(u),\(v),\(w)"
    }

    package init(model: CrystalModel, isMatrix: Bool, u: Int, v: Int, w: Int) {
        self.model = model
        self.isMatrix = isMatrix
        self.u = u; self.v = v; self.w = w
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

    package static func == (lhs: PhaseMappingSlot, rhs: PhaseMappingSlot) -> Bool {
        lhs.signature == rhs.signature && lhs.model.displayName == rhs.model.displayName
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

    /// Identity of the current phase list, order-independent: reordering the
    /// list does not change the science, so it must not make a result stale.
    package var phaseSignature: String {
        phases.map(\.signature).sorted().joined(separator: ";")
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
    }
}
