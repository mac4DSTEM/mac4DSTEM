//
//  ObjectVariants.swift
//  Role: the orientation-relationship variant of each precipitate object (suite task 40, design 2026-10-22 §3): the phase map's winning
//        library entry per scan position (phase x zone axis x in-plane rotation) becomes an orientation, DiffractoKit's
//        `OrientationVariantSet.nearestVariant` names its variant (12 for beta'' in Al), and each object takes the variant most of its
//        pixels vote for. Pure: no SwiftUI, no AppState; the kit does the rotation algebra, this file votes and says why not.
//
//  What it is not: ACOM orientations are the second source behind the same seam and are not built (`VariantSettings.source`).
//  UNVALIDATED (`validation: "none"`): the phase map is, and the variant set is planted truth, not a measured set.
//
//  Conventions (read from the kit, tested in ObjectVariantsTests): an entry's orientation is
//  `ZoneAxisFrame.matrix(detectorBasis(zoneAxis), inPlaneAngle)` of its zone axis in the crystal's own Cartesian frame (columns = the
//  detector x, y and the beam in crystal axes); the library rotates the projected vectors by +theta, which is the same matrix. The
//  precipitate-to-matrix rotation of a pixel is `M_matrix * M_precipitate^T` (`OrientationVariantSet.observedRelation`).
//

import Foundation
import simd
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DiffractoCore
import DiffractoOrientation
#endif

/// The orientation relationships the variant block offers. One today; the picker exists because a second is a case here.
package nonisolated enum OrientationRelationshipPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case betaDoublePrimeInAl = "beta-double-prime-in-al"

    package var id: String { rawValue }
    package var title: String {
        switch self { case .betaDoublePrimeInAl: "\u{03B2}\u{2033} in Al, Andersen 1998" }
    }
    /// The needle axis of the precipitate as lattice indices: b of the monoclinic cell (Andersen 1998: b ∥ Al <001>).
    package var needleAxis: SIMD3<Int> {
        switch self { case .betaDoublePrimeInAl: SIMD3(0, 1, 0) }
    }
    /// The two statements the rotation is built from (`OrientationRelationship.rotation`, the kit's planted case): a ∥ [3 2 0] and
    /// b ∥ [0 0 1] of the matrix.
    package var statements: (OrientationRelationship, OrientationRelationship) {
        switch self {
        case .betaDoublePrimeInAl:
            (OrientationRelationship(candidate: .direction(SIMD3(1, 0, 0)), matrix: .direction(SIMD3(3, 2, 0))),
             OrientationRelationship(candidate: .direction(SIMD3(0, 1, 0)), matrix: .direction(SIMD3(0, 0, 1))))
        }
    }
}

/// How objects are assigned to variants. Settings, not results: they ride in the sidecar and replay recomputes.
package nonisolated struct VariantSettings: Codable, Hashable, Sendable {
    /// Where the object's orientation comes from. Only the phase map's winning entries are built.
    package var source = "known_variants"
    package var orientationRelationship = OrientationRelationshipPreset.betaDoublePrimeInAl
    /// A pixel votes only when its nearest variant is this near (degrees); nil is half the library's in-plane step, because no pixel
    /// can say more than its grid does.
    package var toleranceDegrees: Double?
    /// The least share of the object's pixels that must vote for the winning variant.
    package var agreementMinimum = 0.5
    package init() {}
}

/// One object's variant, or why it has none.
package nonisolated struct VariantAssignment: Codable, Hashable, Sendable {
    package enum Status: Codable, Hashable, Sendable {
        case assigned
        /// The reason, in words.
        case ambiguous(String)
        case noOrientation
    }
    /// 1...12 in the kit's order; nil unless assigned.
    package let variant: Int?
    /// Which of the matrix's three cube axes the needle lies along (0, 1, 2 for [100], [010], [001]); nil unless assigned.
    package let direction: Int?
    /// Mean angle from the voting pixels' orientations to the variant, degrees.
    package let angleDegrees: Double?
    /// The share of the object's pixels that voted for the winning variant.
    package let agreement: Double
    package let status: Status

    package var isAssigned: Bool { status == .assigned }
    package init(variant: Int?, direction: Int?, angleDegrees: Double?, agreement: Double, status: Status) {
        self.variant = variant; self.direction = direction; self.angleDegrees = angleDegrees
        self.agreement = agreement; self.status = status
    }
}

/// The kit's variant set for one precipitate in one matrix, with each variant's needle direction.
package nonisolated struct VariantSetup: Sendable {
    package let set: OrientationVariantSet
    /// Per variant (kit order): the matrix cube axis its needle lies along.
    package let needleDirection: [Int]
    package let preset: OrientationRelationshipPreset

    package init(precipitate: CrystalStructure, matrix: CrystalStructure, preset: OrientationRelationshipPreset) throws {
        guard let matrixSymmetry = PhaseModel.orientationSymmetry(of: matrix),
              let precipitateSymmetry = PhaseModel.orientationSymmetry(of: precipitate) else { throw VariantError.noStandardSetting }
        let relation = try OrientationRelationship.rotation(preset.statements.0, preset.statements.1, precipitate: precipitate, matrix: matrix)
        set = try OrientationVariantSet(matrix: relation, matrixSymmetry: matrixSymmetry, precipitateSymmetry: precipitateSymmetry)
        guard let needle = PhaseReferenceLibrary.cartesianZoneAxis(preset.needleAxis, crystal: precipitate) else { throw VariantError.noStandardSetting }
        needleDirection = set.variants.map { rotation in
            let axis = rotation * needle
            return (0..<3).max { abs(axis[$0]) < abs(axis[$1]) } ?? 0
        }
        self.preset = preset
    }
}

package nonisolated enum VariantError: Error, Equatable, LocalizedError {
    case noStandardSetting
    case noMatrixEntry
    package var errorDescription: String? {
        switch self {
        case .noStandardSetting: "A phase has no standard orientation setting, so its variants cannot be named."
        case .noMatrixEntry: "The phase map has no fitted matrix orientation to measure the variants from."
        }
    }
}

package nonisolated enum ObjectVariantAssigner {

    /// The orientations of a library's entries and of the scan's matrix, in the kit's matrix convention.
    package nonisolated struct Orientations: Sendable {
        package var entryPhase: [Int]
        package var entryOrientation: [simd_double3x3?]
        package var matrixOrientation: simd_double3x3
        package var inPlaneStepDegrees: Double
        /// The matrix's own cube axis along the beam, when the matrix zone axis is one: the "end-on" direction.
        package var matrixBeamDirection: Int?

        package init(entryPhase: [Int], entryOrientation: [simd_double3x3?], matrixOrientation: simd_double3x3, inPlaneStepDegrees: Double,
                     matrixBeamDirection: Int? = nil) {
            self.entryPhase = entryPhase; self.entryOrientation = entryOrientation; self.matrixOrientation = matrixOrientation
            self.inPlaneStepDegrees = inPlaneStepDegrees; self.matrixBeamDirection = matrixBeamDirection
        }

        /// From the phase map's library and its matrix entry. Nil without a matrix entry.
        package static func make(library: PhaseReferenceLibrary, matrixEntryIndex: Int) -> Orientations? {
            guard library.entries.indices.contains(matrixEntryIndex) else { return nil }
            func orientation(_ entry: PhaseOrientationReference) -> simd_double3x3? {
                guard library.phases.indices.contains(entry.phaseIndex) else { return nil }
                return ObjectVariantAssigner.entryOrientation(entry, crystal: library.phases[entry.phaseIndex].crystal)
            }
            let matrixEntry = library.entries[matrixEntryIndex]
            guard let matrix = orientation(matrixEntry) else { return nil }
            let beam = PhaseReferenceLibrary.cartesianZoneAxis(matrixEntry.zoneAxis, crystal: library.phases[matrixEntry.phaseIndex].crystal)
                .flatMap { axis -> Int? in
                    let m = (0..<3).max { abs(axis[$0]) < abs(axis[$1]) } ?? 0
                    return abs(abs(axis[m]) - 1) < 1e-6 ? m : nil
                }
            return Orientations(entryPhase: library.entries.map(\.phaseIndex), entryOrientation: library.entries.map(orientation),
                                matrixOrientation: matrix, inPlaneStepDegrees: library.settings.inPlaneStepDeg, matrixBeamDirection: beam)
        }
    }

    /// An entry's orientation: its zone axis in the crystal's Cartesian frame, then its in-plane rotation (the library rotates the projected
    /// vectors by +theta, which is `ZoneAxisFrame.matrix`'s in-plane matrix).
    package static func entryOrientation(_ entry: PhaseOrientationReference, crystal: CrystalStructure) -> simd_double3x3? {
        guard let n = PhaseReferenceLibrary.cartesianZoneAxis(entry.zoneAxis, crystal: crystal) else { return nil }
        return ZoneAxisFrame.matrix(detectorBasis: ZoneAxisFrame.detectorBasis(zoneAxis: n), inPlaneAngle: Float(entry.inPlaneRotationRad))
    }

    /// Assigns each object of `precipitatePhaseIndex`'s class. Objects of other classes are not in the result. `results` is the phase map's
    /// verdict per scan position, row-major; a position votes when it is indexed to an entry of that phase and its nearest variant lies within
    /// the tolerance. The winner is the variant with the most votes (a tie is ambiguous); it is assigned when its share of the object's
    /// pixels reaches the agreement floor.
    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, results: [PhaseVectorResult], orientations: Orientations,
                            precipitatePhaseIndex: Int, setup: VariantSetup, settings: VariantSettings) -> ObjectJoinResult<VariantAssignment> {
        let tolerance = settings.toleranceDegrees ?? orientations.inPlaneStepDegrees / 2
        var nearest: [Int32: (variant: Int, angleDegrees: Double)?] = [:]
        func variant(of entry: Int32) -> (variant: Int, angleDegrees: Double)? {
            if let cached = nearest[entry] { return cached }
            var found: (variant: Int, angleDegrees: Double)?
            if let p = orientations.entryOrientation[Int(entry)],
               let hit = setup.set.nearestVariant(matrixOrientation: orientations.matrixOrientation, precipitateOrientation: p) {
                found = (hit.index, hit.disorientationRad * 180 / .pi)
            }
            nearest[entry] = .some(found)
            return found
        }
        var out = ObjectJoinResult<VariantAssignment>()
        for classObjects in objects.classes where Int(classObjects.label) == precipitatePhaseIndex {
            for object in classObjects.objects {
                var votes = [Int: (count: Int, angleSum: Double)]()
                var oriented = 0
                for i in object.pixelIndices where results.indices.contains(i) {
                    let r = results[i]
                    guard r.verdict == .indexed, r.entryIndex >= 0, Int(r.entryIndex) < orientations.entryPhase.count,
                          orientations.entryPhase[Int(r.entryIndex)] == precipitatePhaseIndex,
                          let hit = variant(of: r.entryIndex) else { continue }
                    oriented += 1
                    if hit.angleDegrees <= tolerance {
                        let old = votes[hit.variant] ?? (0, 0)
                        votes[hit.variant] = (old.count + 1, old.angleSum + hit.angleDegrees)
                    }
                }
                let pixels = max(object.pixelIndices.count, 1)
                guard oriented > 0 else {
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: nil, agreement: 0, status: .noOrientation)
                    out.reasons[object.id] = "no pixel has an orientation"
                    continue
                }
                let top = votes.values.map(\.count).max() ?? 0
                let leaders = votes.filter { $0.value.count == top }.keys.sorted()
                guard top > 0 else {
                    let why = "no pixel is within \(Self.degrees(tolerance)) of a variant"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: nil, agreement: 0, status: .ambiguous(why))
                    out.reasons[object.id] = why
                    continue
                }
                let winner = leaders[0]
                let agreement = Double(top) / Double(pixels)
                let angle = votes[winner].map { $0.angleSum / Double($0.count) }
                if leaders.count > 1 {
                    let why = "variants \(leaders.map { String($0 + 1) }.joined(separator: " and ")) tie"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: angle, agreement: agreement, status: .ambiguous(why))
                    out.reasons[object.id] = why
                } else if agreement < settings.agreementMinimum {
                    let why = "only \(Int((agreement * 100).rounded())) % of the pixels agree on variant \(winner + 1)"
                    out.perObject[object.id] = VariantAssignment(variant: nil, direction: nil, angleDegrees: angle, agreement: agreement, status: .ambiguous(why))
                    out.reasons[object.id] = why
                } else {
                    out.perObject[object.id] = VariantAssignment(variant: winner + 1, direction: setup.needleDirection[winner], angleDegrees: angle,
                                                                 agreement: agreement, status: .assigned)
                }
            }
        }
        return out
    }

    private static func degrees(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX"))) + "\u{00B0}" }
}
