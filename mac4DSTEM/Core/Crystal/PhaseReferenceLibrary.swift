//
//  PhaseReferenceLibrary.swift
//  Role: the LIBRARY half of vector-matched phase mapping — for each phase,
//        each sampled beam direction and each in-plane rotation, the set of
//        reciprocal-lattice vectors that would appear in the detector plane.
//
//  Method: Thronsen, Hjelen, Holmestad et al., "Studying GPB zones and
//  precipitates in Al-Cu-Li with scanning precession electron diffraction",
//  Ultramicroscopy 255 (2024) 113861, CC BY 4.0. The METHOD and the paper's
//  Table 2 structures are reusable under that licence. Their GitHub repository
//  carries NO licence, so nothing there is used: this implementation is written
//  from the published description, and every parameter default below is derived
//  here rather than taken from their notebooks (decisions.md, 2026-09-11).
//
//  Why this is composition and not new mathematics: `Crystal.reflections(kMax:)`
//  already builds the reciprocal lattice of an arbitrary cell with kinematic
//  structure factors, and `OrientationPlan.project` already selects the
//  reflections excited at a beam direction and drops them into the plane
//  perpendicular to it. This file adds three things neither had: a zone axis
//  named in LATTICE indices rather than Cartesian, an explicit in-plane
//  rotation axis of the search, and a visibility cut.
//
//  The visibility cut is the one that carries scientific weight, so it is
//  stated here rather than buried in a default. A real pattern shows the few
//  strongest reflections. A library holding every kinematically allowed vector
//  gives EVERY experimental vector a near neighbour for EVERY phase, and a
//  nearest-neighbour score saturates — which is the same saturation that
//  refuted the template-matched route on 2026-09-11
//  (`archive/v3/phase-discrimination-2026-09-11.md`). `minimumIntensityFraction`
//  is the guard, and `tools/phase-vector-matching` carries a negative control
//  that fails if a deliberately over-dense library can win.
//
//  Units: |g| in Å⁻¹ with no 2π factor, matching `Crystal` and py4DSTEM.
//

import Foundation
import simd

// MARK: - One reference vector

/// A reflection projected into the detector plane, in Å⁻¹.
///
/// `hkl` is carried for reporting only — the matcher never reads it. It is what
/// lets the evidence overlay say *which* reflection a matched peak is, which is
/// the difference between a phase map a user can check and one they must trust.
package nonisolated struct ReferenceVector: Sendable, Equatable {
    package let h: Int, k: Int, l: Int
    /// In-plane reciprocal vector (Å⁻¹), after the in-plane rotation.
    package let q: SIMD2<Double>
    /// |q| (Å⁻¹). Precomputed because the matcher prunes on it.
    package let length: Double
    /// Excited intensity |F|² × exp(−(s_g/σ)²), relative to the strongest
    /// reflection in the same entry. In (0, 1].
    package let relativeIntensity: Double

    package nonisolated init(h: Int, k: Int, l: Int, q: SIMD2<Double>,
                             length: Double, relativeIntensity: Double) {
        self.h = h; self.k = k; self.l = l
        self.q = q
        self.length = length
        self.relativeIntensity = relativeIntensity
    }
}

// MARK: - One candidate orientation of one phase

/// The reference vectors of one phase at one beam direction and one in-plane
/// rotation. `vectors` is sorted by increasing `length`, which the matcher's
/// pruning depends on.
package nonisolated struct PhaseOrientationReference: Sendable {
    package let phaseIndex: Int
    /// Beam direction as lattice indices [u v w], the way a crystallographer
    /// names a zone axis. Cartesian is derivable but not what anyone reads.
    package let zoneAxis: SIMD3<Int>
    package let inPlaneRotationRad: Double
    /// Sorted by increasing `length`.
    package let vectors: [ReferenceVector]

    /// The fraction of the accessible plane this entry's reference vectors
    /// cover at a given pair radius — an upper bound on how often a vector
    /// pointing NOWHERE IN PARTICULAR matches this entry by chance.
    ///
    /// `V·ρ²/R²` by the union bound over EVERY reference — an upper bound,
    /// not an estimate. See the body for why restricting it to the references
    /// the data can reach was tried, measured, and reverted.
    /// It is the number that says whether a match carries information: an
    /// entry covering a third of the plane explains a third of any random set,
    /// and its "match" means nothing. Reported in provenance rather than
    /// enforced, because the threshold at which it becomes unacceptable
    /// depends on how many vectors a pattern has — and a limit invented here
    /// would be a guess where a printed number is a measurement.
    package func chanceMatchFraction(pairRadius: Double, accessibleRadius: Double) -> Double {
        guard accessibleRadius > 0, pairRadius > 0 else { return 0 }
        // EVERY reference counts, including the ones outside the data's reach,
        // and that is deliberate — it is what makes this an UPPER BOUND rather
        // than an estimate.
        //
        // Gate B (2026-09-12) called the whole count against a restricted area
        // a 12x overestimate and proposed restricting the numerator to match.
        // That remedy was implemented and MEASURED, and it made the guard
        // weaker in exactly the case the guard exists for: with the numerator
        // restricted, `testOneDistantSpuriousPeakDoesNotWeakenTheChanceGuard`
        // went red on its FIRST assertion — random vectors in a narrow annulus
        // were indexed with no outlier at all — because a lower chance
        // estimate is a lower bar for eligibility. Reverted.
        //
        // The reason the whole count is the right conservative choice: the
        // uniform-disc model puts most of its area at large r, while real and
        // spurious peaks cluster at small r where a reference set is densest,
        // so the model UNDERSTATES the true chance for the distributions that
        // matter. Counting every reference pushes the other way. An
        // overestimate of chance demands more evidence, which is the safe
        // direction for a guard whose whole job is refusing uninformative
        // matches. It is not a probability and this comment does not call it
        // one.
        let p = Double(vectors.count) * pairRadius * pairRadius
            / (accessibleRadius * accessibleRadius)
        return min(1, p)
    }

    package nonisolated init(phaseIndex: Int, zoneAxis: SIMD3<Int>,
                             inPlaneRotationRad: Double, vectors: [ReferenceVector]) {
        self.phaseIndex = phaseIndex
        self.zoneAxis = zoneAxis
        self.inPlaneRotationRad = inPlaneRotationRad
        self.vectors = vectors
    }
}

// MARK: - The orientation relationship, stated the way a crystallographer writes it

/// A lattice vector named the way a crystallographer names it: a plane
/// "(hkl)" — a reciprocal vector, `h·a* + k·b* + l·c*` — or a direction
/// "[uvw]" — a real one, `u·a + v·b + w·c`. Both come out as Cartesian
/// vectors in the crystal's own frame (`Crystal.latInv` rows for a plane,
/// `Crystal.latReal` rows for a direction), which is all the projection
/// (`PhaseVectorMatcher.projectedAzimuth`) needs — it never sees `hkl` or
/// `uvw` again.
package nonisolated enum LatticeVector: Sendable, Equatable {
    case plane(SIMD3<Int>)
    case direction(SIMD3<Int>)

    /// This vector's Cartesian form in `crystal`'s own frame. Not normalised
    /// — `projectedAzimuth` only needs its direction, and the caller never
    /// reads its length.
    package func cartesian(in crystal: Crystal) -> SIMD3<Double> {
        switch self {
        case .plane(let hkl):
            return Double(hkl.x) * crystal.latInv[0]
                + Double(hkl.y) * crystal.latInv[1]
                + Double(hkl.z) * crystal.latInv[2]
        case .direction(let uvw):
            return Double(uvw.x) * crystal.latReal[0]
                + Double(uvw.y) * crystal.latReal[1]
                + Double(uvw.z) * crystal.latReal[2]
        }
    }
}

/// One statement of an orientation relationship: this phase's vector is
/// parallel to the matrix's — the way a paper states it, e.g.
/// "(002)θ′ ∥ (200)Al". List every symmetry-equivalent variant explicitly;
/// Core knows no symmetry.
package nonisolated struct OrientationRelationship: Sendable, Equatable {
    package let candidate: LatticeVector
    package let matrix: LatticeVector

    package nonisolated init(candidate: LatticeVector, matrix: LatticeVector) {
        self.candidate = candidate
        self.matrix = matrix
    }
}

// MARK: - A phase as the library sees it

/// One phase in the library: a structure, a name, and whether it is the matrix.
///
/// The matrix is not a label the method infers — it is stated by the user,
/// because "which phase is the bulk" is knowledge about the specimen and not
/// about the data. Their method leaves the matrix out of the candidate set and
/// assigns it by exclusion; `role` is what makes that possible.
package nonisolated struct PhaseDefinition: Sendable {
    package enum Role: String, Sendable {
        /// The bulk. Its reflections are removed from every pattern, and it is
        /// the label assigned when too little survives removal to index.
        case matrix
        /// A candidate phase. Scored.
        case candidate
    }

    package let id: String
    package let displayName: String
    package let crystal: Crystal
    package let role: Role
    /// Beam directions to sample, as lattice indices. Empty means the caller
    /// wants `PhaseReferenceLibrary.lowIndexZoneAxes` for this phase.
    package let zoneAxes: [SIMD3<Int>]
    /// The orientation relationship this phase is stated to have with the
    /// matrix, as pairs of parallel lattice vectors — "(002) ∥ (200)", not a
    /// pre-computed angle. Empty is free — today's behaviour, and the caller
    /// lists every symmetry-equivalent variant explicitly; Core knows no
    /// symmetry.
    ///
    /// DERIVED, PER ENTRY (2026-09-15, replacing a library-frame degree
    /// list): each pair's candidate and matrix vectors are projected into
    /// their OWN entry's detector frame (`ACOMOrientation.detectorBasis` of
    /// that entry's zone axis, then that entry's own in-plane rotation) and
    /// compared as azimuths — so the same statement is checked against
    /// every zone axis and rotation a phase samples, rather than one library
    /// frame the caller had to work out by hand. The comparison is modulo
    /// 180°: a ZOLZ under the flat Ewald sphere this file already uses (see
    /// `projectedVectors`) is centrosymmetric, g and −g both excited, so a
    /// plane and its negative are indistinguishable and "parallel" only
    /// means so up to sign.
    package let orientationRelationships: [OrientationRelationship]

    package nonisolated init(id: String, displayName: String, crystal: Crystal,
                             role: Role, zoneAxes: [SIMD3<Int>],
                             orientationRelationships: [OrientationRelationship] = []) {
        self.id = id
        self.displayName = displayName
        self.crystal = crystal
        self.role = role
        self.zoneAxes = zoneAxes
        self.orientationRelationships = orientationRelationships
    }
}

// MARK: - Generation parameters

package nonisolated struct PhaseReferenceSettings: Sendable, Equatable {
    /// Largest |q| kept, Å⁻¹. Should be the detector's calibrated reach: a
    /// reference vector beyond it can never be matched, only counted.
    package var kMaxInvAngstrom: Double = 1.6
    /// Half-thickness of the slab about the zero-order Laue zone, Å⁻¹
    /// (`sgMax` in `OrientationPlan.project`). Larger admits reflections the
    /// beam excites only weakly; smaller risks dropping ones precession
    /// excites. Thronsen et al. use phase-dependent values (0.030 and 0.300
    /// Å⁻¹); ours is one number and is derived, not copied.
    package var excitationSlabInvAngstrom: Double = 0.05
    /// Gaussian width of the excitation weight, Å⁻¹ (`sgWidth`).
    package var excitationWidthInvAngstrom: Double = 0.03
    /// Reflections weaker than this fraction of the entry's strongest are
    /// dropped. One half of the guard against a saturating library — see the
    /// file header, and `maximumVectorsPerEntry`, which is the half that
    /// actually bounds the density.
    package var minimumIntensityFraction: Double = 0.05
    /// At most this many reference vectors per entry, strongest kept.
    ///
    /// An intensity fraction alone does NOT control density, which is what
    /// matters: measured 2026-09-12, a β″ [010] entry at
    /// `minimumIntensityFraction` 0.02 holds 130 vectors out to 1.2 Å⁻¹, and
    /// with a 0.06 Å⁻¹ pair radius those cover a THIRD of the plane — so a
    /// third of any random vector set matched by chance and the harness's
    /// random-vector positions were labelled β″ 100 % of the time. A cap is
    /// the direct control, and it is also the physical statement: a real
    /// pattern from a thin precipitate shows a few dozen clear reflections,
    /// not every kinematically allowed one. See
    /// `PhaseOrientationReference.chanceMatchFraction`, which is what makes
    /// the trade visible rather than a matter of taste.
    package var maximumVectorsPerEntry: Int = 48
    /// In-plane rotation step, degrees. The search is over [0, 360).
    package var inPlaneStepDeg: Double = 2
    /// Refuse to build a library with more entries than this. A phase map is
    /// entries × scan positions × vectors of work; a library that takes an hour
    /// is a mistake in the settings, and saying so beats discovering it.
    package var maximumEntries: Int = 4000

    package nonisolated init() {}
}

// MARK: - The library

package nonisolated struct PhaseReferenceLibrary: Sendable {

    package enum Failure: Error, Equatable {
        /// A phase's structure has elements with no scattering factors.
        case unsupportedElements(phase: String, z: [Int])
        /// A zone axis of [0 0 0], which names no direction.
        case degenerateZoneAxis(phase: String)
        /// A phase produced no visible reflection at any sampled orientation.
        case noVisibleReflections(phase: String)
        /// `maximumEntries` exceeded. Carries what it would have been.
        case libraryTooLarge(requested: Int, limit: Int)
        /// No phase was marked `.matrix`, or more than one was.
        case matrixPhaseNotUnique(count: Int)
        /// Nothing to score.
        case noCandidatePhases
    }

    package let phases: [PhaseDefinition]
    package let settings: PhaseReferenceSettings
    /// Every candidate entry, matrix included. `matrixEntryIndices` selects the
    /// matrix's; `candidateEntryIndices` the rest.
    package let entries: [PhaseOrientationReference]
    package let matrixPhaseIndex: Int

    package var matrixEntryIndices: [Int] {
        entries.indices.filter { entries[$0].phaseIndex == matrixPhaseIndex }
    }
    package var candidateEntryIndices: [Int] {
        entries.indices.filter { entries[$0].phaseIndex != matrixPhaseIndex }
    }

    /// Low-index beam directions, one per ±pair, |u|,|v|,|w| ≤ 2 and coprime.
    /// Deliberately NOT reduced by crystal symmetry: `.identity` ("Unreduced")
    /// is exactly the symmetry a monoclinic precipitate imports as
    /// (`CIFImport`, 2026-09-11), so a symmetry reduction would be a no-op
    /// where it matters most and an inconsistency everywhere else.
    package static let lowIndexZoneAxes: [SIMD3<Int>] = {
        var seen = Set<SIMD3<Int>>()
        var out: [SIMD3<Int>] = []
        for u in -2...2 {
            for v in -2...2 {
                for w in -2...2 {
                    if u == 0 && v == 0 && w == 0 { continue }
                    // max(1, …) at the END, not inside `gcd`: a `gcd`
                    // that floors itself at 1 returns gcd(0, 0) = 1, so
                    // [0 0 2] never reduced and the list held it beside
                    // [0 0 1] — 50 entries for 49 directions, and 180
                    // redundant library entries per phase at the default
                    // step (Gate B finding 9, 2026-09-12).
                    let g = max(1, gcd(gcd(abs(u), abs(v)), abs(w)))
                    let r = SIMD3(u / g, v / g, w / g)
                    // One of each ±pair: [uvw] and [-u-v-w] are the same axis
                    // viewed from opposite sides, and the projected vector set
                    // of one is the other's reflected through the origin —
                    // which a set containing both ±g cannot tell apart.
                    let neg = SIMD3(-r.x, -r.y, -r.z)
                    if seen.contains(r) || seen.contains(neg) { continue }
                    seen.insert(r)
                    out.append(r)
                }
            }
        }
        return out
    }()

    /// A true gcd: `gcd(0, 0)` is 0, not 1. Callers floor the RESULT.
    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    // MARK: Build

    package static func build(phases: [PhaseDefinition],
                              settings: PhaseReferenceSettings = .init(),
                              cancellation: AnalysisCancellationToken? = nil)
        throws -> PhaseReferenceLibrary {

        let matrixIndices = phases.indices.filter { phases[$0].role == .matrix }
        guard matrixIndices.count == 1 else {
            throw Failure.matrixPhaseNotUnique(count: matrixIndices.count)
        }
        guard phases.contains(where: { $0.role == .candidate }) else {
            throw Failure.noCandidatePhases
        }
        for phase in phases {
            let unsupported = phase.crystal.unsupportedElements
            guard unsupported.isEmpty else {
                throw Failure.unsupportedElements(phase: phase.displayName, z: unsupported)
            }
        }

        // Size the library before building it, so a refusal costs nothing.
        let steps = inPlaneSteps(settings)
        var requested = 0
        for phase in phases {
            let axes = phase.zoneAxes.isEmpty ? lowIndexZoneAxes : phase.zoneAxes
            guard !axes.contains(where: { $0 == SIMD3(0, 0, 0) }) else {
                throw Failure.degenerateZoneAxis(phase: phase.displayName)
            }
            requested += axes.count * steps.count
        }
        guard requested <= settings.maximumEntries else {
            throw Failure.libraryTooLarge(requested: requested, limit: settings.maximumEntries)
        }

        var entries: [PhaseOrientationReference] = []
        entries.reserveCapacity(requested)

        for (phaseIndex, phase) in phases.enumerated() {
            if cancellation?.isCancelled == true { break }
            let reflections = phase.crystal.reflections(kMax: settings.kMaxInvAngstrom)
            let axes = phase.zoneAxes.isEmpty ? lowIndexZoneAxes : phase.zoneAxes
            var phaseHasAny = false

            for axis in axes {
                if cancellation?.isCancelled == true { break }
                let base = projectedVectors(reflections: reflections,
                                            crystal: phase.crystal,
                                            zoneAxis: axis,
                                            settings: settings)
                if base.isEmpty { continue }
                phaseHasAny = true
                for theta in steps {
                    entries.append(PhaseOrientationReference(
                        phaseIndex: phaseIndex, zoneAxis: axis, inPlaneRotationRad: theta,
                        vectors: rotate(base, by: theta)
                    ))
                }
            }
            guard phaseHasAny else {
                throw Failure.noVisibleReflections(phase: phase.displayName)
            }
        }

        return PhaseReferenceLibrary(phases: phases, settings: settings,
                                     entries: entries,
                                     matrixPhaseIndex: matrixIndices[0])
    }

    /// In-plane rotations sampled, radians. Always includes 0.
    package static func inPlaneSteps(_ settings: PhaseReferenceSettings) -> [Double] {
        let step = settings.inPlaneStepDeg
        guard step.isFinite, step > 0, step <= 360 else { return [0] }
        let n = max(1, Int((360.0 / step).rounded()))
        return (0..<n).map { Double($0) * (2 * Double.pi / Double(n)) }
    }

    // MARK: The projection itself

    /// The beam direction [u v w] as a Cartesian unit vector.
    ///
    /// A zone axis is a REAL-space direction, so it is `u·a₁ + v·a₂ + w·a₃`
    /// over `latReal`, not the Cartesian triple (u, v, w). For a cubic cell the
    /// two agree, which is exactly why getting it wrong stays invisible until
    /// the first monoclinic phase — the case this whole feature exists for.
    package static func cartesianZoneAxis(_ uvw: SIMD3<Int>, crystal: Crystal)
        -> SIMD3<Double>? {
        let v = Double(uvw.x) * crystal.latReal[0]
            + Double(uvw.y) * crystal.latReal[1]
            + Double(uvw.z) * crystal.latReal[2]
        let n = simd_length(v)
        guard n.isFinite, n > 1e-12 else { return nil }
        return v / n
    }

    /// Reflections excited at `zoneAxis`, projected into the detector plane at
    /// in-plane rotation 0 and cut to the visible ones. Sorted by |q|.
    package static func projectedVectors(reflections: [Reflection],
                                         crystal: Crystal,
                                         zoneAxis uvw: SIMD3<Int>,
                                         settings: PhaseReferenceSettings)
        -> [ReferenceVector] {
        guard let n = cartesianZoneAxis(uvw, crystal: crystal) else { return [] }
        let basis = ACOMOrientation.detectorBasis(zoneAxis: n)
        let e1 = basis.columns.0, e2 = basis.columns.1
        let sgMax = settings.excitationSlabInvAngstrom
        let sgWidth = max(settings.excitationWidthInvAngstrom, 1e-9)

        // MEASURED 2026-09-12 (Gate B finding 7), and it changes how the two
        // excitation settings should be read: with a flat sphere
        // s_g = g·n = (hu + kv + lw)/|r_uvw|, which is EXACTLY 0 for every
        // zone-law reflection and at least 1/|r_uvw| otherwise. For every axis
        // in play that spacing is 0.066 Å⁻¹ or more — above
        // `excitationSlabInvAngstrom` — so no non-ZOLZ reflection is admitted
        // and the Gaussian is identically 1 on everything that is. The slab is
        // therefore a ZONE SELECTOR here, not a weighting, and
        // `excitationWidthInvAngstrom` cannot change any output until the
        // Ewald curvature is restored or the slab is widened past a Laue-zone
        // spacing. Both settings are kept because that is exactly what changes
        // for a long-axis cell, where 1/|r_uvw| falls below the slab.
        //
        // Flat Ewald sphere: s_g = g·n. Deliberately flat, and NOT the
        // curvature-corrected form `OrientationPlan.project` offers. The
        // curvature term exists there to break a 180° ambiguity in an
        // AZIMUTHAL CORRELATION by making g and −g excite differently. Here the
        // score is a distance between vectors, the in-plane rotation is an
        // explicit axis of the search rather than something recovered from an
        // FFT, and there is no ambiguity to break — so the curvature would only
        // add a wavelength the caller may not have and an asymmetry nothing
        // reads. Under precession, which is how SPED data is taken, the
        // effective excitation is symmetrised anyway.
        var raw: [(ReferenceVector, Double)] = []
        raw.reserveCapacity(reflections.count)
        var strongest = 0.0
        for refl in reflections {
            let sg = simd_dot(refl.g, n)
            if abs(sg) > sgMax { continue }
            let excited = refl.intensity * exp(-(sg / sgWidth) * (sg / sgWidth))
            guard excited.isFinite, excited > 0 else { continue }
            let x = simd_dot(refl.g, e1)
            let y = simd_dot(refl.g, e2)
            let q = SIMD2(x, y)
            let len = simd_length(q)
            guard len.isFinite, len > 1e-9, len <= settings.kMaxInvAngstrom else { continue }
            strongest = max(strongest, excited)
            raw.append((ReferenceVector(h: refl.h, k: refl.k, l: refl.l,
                                        q: q, length: len, relativeIntensity: excited), excited))
        }
        guard strongest > 0 else { return [] }

        let floor = settings.minimumIntensityFraction * strongest
        var kept = raw.filter { $0.1 >= floor }
        // Strongest first, then cap, then sort by length for the matcher's
        // prune. Ties broken on |q| so the cap is deterministic: a set that
        // depends on hash or enumeration order is a gate that drifts.
        if settings.maximumVectorsPerEntry > 0, kept.count > settings.maximumVectorsPerEntry {
            kept.sort {
                $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.length < $1.0.length
            }
            kept.removeLast(kept.count - settings.maximumVectorsPerEntry)
        }
        var out = kept.map { pair in
            ReferenceVector(h: pair.0.h, k: pair.0.k, l: pair.0.l, q: pair.0.q,
                            length: pair.0.length, relativeIntensity: pair.1 / strongest)
        }
        out.sort { $0.length < $1.length }
        return out
    }

    /// Rotate a projected set in the detector plane. Keeps the sort, because
    /// a rotation does not change any |q|.
    package static func rotate(_ vectors: [ReferenceVector], by theta: Double)
        -> [ReferenceVector] {
        guard theta != 0 else { return vectors }
        let c = cos(theta), s = sin(theta)
        return vectors.map {
            ReferenceVector(h: $0.h, k: $0.k, l: $0.l,
                            q: SIMD2(c * $0.q.x - s * $0.q.y, s * $0.q.x + c * $0.q.y),
                            length: $0.length, relativeIntensity: $0.relativeIntensity)
        }
    }
}
