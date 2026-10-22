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

/// The orientation relationships the variant block offers. beta'' stays the default; theta' and T1 are plates (suite task 40 follow-up).
package nonisolated enum OrientationRelationshipPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case betaDoublePrimeInAl = "beta-double-prime-in-al"
    case thetaPrimeInAl = "theta-prime-in-al"
    case t1InAl = "t1-in-al"

    /// What the precipitate looks like along its habit axis: a needle lies along it, a plate stands on it.
    package enum Habit: String, Codable, Sendable { case needle, plate }

    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .betaDoublePrimeInAl: "\u{03B2}\u{2033} in Al, Andersen 1998"
        case .thetaPrimeInAl: "\u{03B8}\u{2032} in Al, Thronsen 2024"
        case .t1InAl: "T1 in Al, Thronsen 2024"
        }
    }
    package var habit: Habit {
        switch self { case .betaDoublePrimeInAl: .needle; case .thetaPrimeInAl, .t1InAl: .plate }
    }
    /// The habit axis of the precipitate as lattice indices (a direction): the needle axis (b of the monoclinic cell for beta'', Andersen 1998:
    /// b ∥ Al <001>) or the plate normal (c of the tetragonal theta' cell, [0001] of the hexagonal T1 cell).
    package var habitAxis: SIMD3<Int> {
        switch self { case .betaDoublePrimeInAl: SIMD3(0, 1, 0); case .thetaPrimeInAl, .t1InAl: SIMD3(0, 0, 1) }
    }
    /// The matrix directions the habit axis can lie along, in the matrix's Cartesian frame (cubic Al: the lattice indices themselves), ±n
    /// being one family; `familyNames` names them in the same order. Cube axes for beta'' and theta', the four <111> normals for T1.
    package var habitFamilies: [SIMD3<Double>] {
        switch self {
        case .betaDoublePrimeInAl, .thetaPrimeInAl: [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        case .t1InAl: [SIMD3(1, 1, 1), SIMD3(-1, 1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, -1)]
        }
    }
    package var familyNames: [String] {
        switch self {
        case .betaDoublePrimeInAl, .thetaPrimeInAl: ["[100]", "[010]", "[001]"]
        case .t1InAl: ["[111]", "[-111]", "[1-11]", "[11-1]"]
        }
    }
    /// The two statements the rotation is built from (`OrientationRelationship.rotation`; the first fixes an axis exactly, the second the
    /// rotation about it). beta'': a ∥ [3 2 0] and b ∥ [0 0 1] of the matrix. theta' (Thronsen 2024): (001) ∥ (001) and [100] ∥ [100].
    /// T1: (0001) ∥ (111) and, with the kit's three-index direction u a1 + v a2 + w c, [2 1 0] (four-index [10-10]) ∥ [1 -1 0].
    package var statements: (OrientationRelationship, OrientationRelationship) {
        switch self {
        case .betaDoublePrimeInAl:
            (OrientationRelationship(candidate: .direction(SIMD3(1, 0, 0)), matrix: .direction(SIMD3(3, 2, 0))),
             OrientationRelationship(candidate: .direction(SIMD3(0, 1, 0)), matrix: .direction(SIMD3(0, 0, 1))))
        case .thetaPrimeInAl:
            (OrientationRelationship(candidate: .plane(SIMD3(0, 0, 1)), matrix: .plane(SIMD3(0, 0, 1))),
             OrientationRelationship(candidate: .direction(SIMD3(1, 0, 0)), matrix: .direction(SIMD3(1, 0, 0))))
        case .t1InAl:
            (OrientationRelationship(candidate: .plane(SIMD3(0, 0, 1)), matrix: .plane(SIMD3(1, 1, 1))),
             OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, -1, 0))))
        }
    }

    /// The family whose direction is most parallel to `axis` (largest |dot|, ±n one family), in `habitFamilies` order.
    package func family(nearest axis: SIMD3<Double>) -> Int {
        let unit = simd_length(axis) > 0 ? simd_normalize(axis) : axis
        let dots = habitFamilies.map { abs(simd_dot(simd_normalize($0), unit)) }
        return dots.indices.max { dots[$0] < dots[$1] } ?? 0
    }
    /// The family lying along `axis` (a beam direction) to within a tenth of a degree, or nil when it lies along none.
    package func family(alongBeam axis: SIMD3<Double>) -> Int? {
        guard simd_length(axis) > 0 else { return nil }
        let i = family(nearest: axis)
        return abs(simd_dot(simd_normalize(habitFamilies[i]), simd_normalize(axis))) > cos(0.1 * .pi / 180) ? i : nil
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
    /// The phase that has the relationship to the matrix (a candidate phase's display name); nil is the first candidate.
    package var phaseName: String?
    package init() {}

    // MARK: lineage parameters (the sidecar's record of it; settings, not results: replay recomputes)

    package static let keys = ["variant_source", "variant_or", "variant_phase", "variant_tolerance_deg", "variant_agreement_min"]

    package var parameters: [String: String] {
        var p = ["variant_source": source, "variant_or": orientationRelationship.rawValue, "variant_agreement_min": String(agreementMinimum)]
        if let toleranceDegrees { p["variant_tolerance_deg"] = String(toleranceDegrees) }
        if let phaseName { p["variant_phase"] = phaseName }
        return p
    }

    package init?(parameters p: [String: String]) {
        guard let or = p["variant_or"].flatMap(OrientationRelationshipPreset.init(rawValue:)) else { return nil }
        self.init()
        source = p["variant_source"] ?? "known_variants"
        orientationRelationship = or
        agreementMinimum = p["variant_agreement_min"].flatMap(Double.init) ?? 0.5
        toleranceDegrees = p["variant_tolerance_deg"].flatMap(Double.init)
        phaseName = p["variant_phase"]
    }
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
    /// Which of the preset's matrix directions the habit axis lies along (index into `familyNames`: 0, 1, 2 for [100], [010], [001] for beta''); nil unless assigned.
    package let direction: Int?
    /// That direction's name ("[100]"); nil unless assigned, and in a snapshot from before the presets (the cube axes then).
    package let directionName: String?
    /// Mean angle from the voting pixels' orientations to the variant, degrees.
    package let angleDegrees: Double?
    /// The share of the object's pixels that voted for the winning variant.
    package let agreement: Double
    package let status: Status

    package var isAssigned: Bool { status == .assigned }
    package init(variant: Int?, direction: Int?, directionName: String? = nil, angleDegrees: Double?, agreement: Double, status: Status) {
        self.variant = variant; self.direction = direction; self.directionName = directionName; self.angleDegrees = angleDegrees
        self.agreement = agreement; self.status = status
    }
}

/// The kit's variant set for one precipitate in one matrix, with the matrix direction each variant's habit axis lies along.
package nonisolated struct VariantSetup: Sendable {
    package let set: OrientationVariantSet
    /// Per variant (kit order): the index into `familyNames` of the matrix direction its habit axis (needle axis or plate normal) lies along.
    package let habitFamily: [Int]
    package var familyNames: [String] { preset.familyNames }
    package let preset: OrientationRelationshipPreset

    package init(precipitate: CrystalStructure, matrix: CrystalStructure, preset: OrientationRelationshipPreset) throws {
        guard let matrixSymmetry = PhaseModel.orientationSymmetry(of: matrix),
              let precipitateSymmetry = PhaseModel.orientationSymmetry(of: precipitate) else { throw VariantError.noStandardSetting }
        let relation = try OrientationRelationship.rotation(preset.statements.0, preset.statements.1, precipitate: precipitate, matrix: matrix)
        set = try OrientationVariantSet(matrix: relation, matrixSymmetry: matrixSymmetry, precipitateSymmetry: precipitateSymmetry)
        guard let habit = PhaseReferenceLibrary.cartesianZoneAxis(preset.habitAxis, crystal: precipitate) else { throw VariantError.noStandardSetting }
        habitFamily = set.variants.map { preset.family(nearest: $0 * habit) }
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
        /// The matrix's own cube axis along the beam, when the matrix zone axis is one: the "end-on" direction of the cube-axis presets.
        package var matrixBeamDirection: Int?
        /// The beam as a unit vector in the matrix's Cartesian frame (the matrix entry's zone axis): the presets name the family along it.
        package var matrixBeamAxis: SIMD3<Double>?

        package init(entryPhase: [Int], entryOrientation: [simd_double3x3?], matrixOrientation: simd_double3x3, inPlaneStepDegrees: Double,
                     matrixBeamDirection: Int? = nil, matrixBeamAxis: SIMD3<Double>? = nil) {
            self.entryPhase = entryPhase; self.entryOrientation = entryOrientation; self.matrixOrientation = matrixOrientation
            self.inPlaneStepDegrees = inPlaneStepDegrees; self.matrixBeamDirection = matrixBeamDirection; self.matrixBeamAxis = matrixBeamAxis
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
            let beamAxis = PhaseReferenceLibrary.cartesianZoneAxis(matrixEntry.zoneAxis, crystal: library.phases[matrixEntry.phaseIndex].crystal)
            let beam = beamAxis
                .flatMap { axis -> Int? in
                    let m = (0..<3).max { abs(axis[$0]) < abs(axis[$1]) } ?? 0
                    return abs(abs(axis[m]) - 1) < 1e-6 ? m : nil
                }
            return Orientations(entryPhase: library.entries.map(\.phaseIndex), entryOrientation: library.entries.map(orientation),
                                matrixOrientation: matrix, inPlaneStepDegrees: library.settings.inPlaneStepDeg, matrixBeamDirection: beam, matrixBeamAxis: beamAxis)
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
                    out.perObject[object.id] = VariantAssignment(variant: winner + 1, direction: setup.habitFamily[winner],
                                                                 directionName: setup.familyNames[setup.habitFamily[winner]], angleDegrees: angle,
                                                                 agreement: agreement, status: .assigned)
                }
            }
        }
        return out
    }

    private static func degrees(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX"))) + "\u{00B0}" }
}

/// The variant run on a phase map: which phase, the kit's variant set, the library's orientations, then `ObjectVariantAssigner.run`. A run that
/// cannot be made says why (`unavailable`), never an empty column.
package nonisolated enum ObjectVariantJoin {
    package nonisolated struct Outcome: Sendable, Equatable {
        package var result: ObjectJoinResult<VariantAssignment>
        /// The preset's matrix direction along the beam (the needles seen end-on, the plates face-on), when there is one.
        package var endOnDirection: Int?
        /// Each variant's habit direction (index into the preset's family names), in the kit's order.
        package var habitFamilies: [Int] = []
    }

    package static func run(objects: PrecipitateSegmentation.ClassMapObjects, map: PhaseMap?, library: PhaseReferenceLibrary?,
                            matrixEntryIndex: Int?, settings: VariantSettings) -> Outcome {
        func unavailable(_ why: String) -> Outcome { Outcome(result: ObjectJoinResult(unavailable: why), endOnDirection: nil, habitFamilies: []) }
        guard settings.source == "known_variants" else { return unavailable("Variants from ACOM orientations are not built yet.") }
        guard let map else { return unavailable("There is no phase map.") }
        guard let library else { return unavailable("The phase map's reference library is not kept; map the phases again.") }
        guard let matrixEntryIndex, matrixEntryIndex >= 0 else { return unavailable(VariantError.noMatrixEntry.localizedDescription) }
        let candidates = map.phaseNames.indices.filter { $0 != map.matrixPhaseIndex }
        guard let phase = settings.phaseName.flatMap({ name in candidates.first { map.phaseNames[$0] == name } }) ?? candidates.first,
              library.phases.indices.contains(phase), library.phases.indices.contains(map.matrixPhaseIndex) else {
            return unavailable("Choose the phase that has the orientation relationship to the matrix.")
        }
        guard let orientations = ObjectVariantAssigner.Orientations.make(library: library, matrixEntryIndex: matrixEntryIndex) else {
            return unavailable(VariantError.noMatrixEntry.localizedDescription)
        }
        let setup: VariantSetup
        do { setup = try VariantSetup(precipitate: library.phases[phase].crystal, matrix: library.phases[map.matrixPhaseIndex].crystal,
                                      preset: settings.orientationRelationship) }
        catch { return unavailable((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        let result = ObjectVariantAssigner.run(objects: objects, results: map.results, orientations: orientations, precipitatePhaseIndex: phase,
                                               setup: setup, settings: settings)
        // The cube-axis presets keep the orientation's own cube-axis index (unchanged for beta''); a beam along no cube axis can still be a <111> family.
        let endOn = orientations.matrixBeamAxis.map { settings.orientationRelationship.family(alongBeam: $0) } ?? orientations.matrixBeamDirection
        return Outcome(result: result, endOnDirection: endOn, habitFamilies: setup.habitFamily)
    }
}
