//
//  PhaseVectorMatching.swift
//  Role: the MATCHER half of vector-matched phase mapping — for each scan
//        position, remove the matrix's reflections, score what survives
//        against every candidate entry of a `PhaseReferenceLibrary`, and
//        return a phase label, a distance, and an explicit "not indexed".
//
//  Method: Thronsen et al., Ultramicroscopy 255 (2024) 113861, CC BY 4.0 —
//  the published description only. Their repository carries no licence and is
//  not used (`decisions.md`, 2026-09-11). Three deviations from what the paper
//  describes are deliberate and are named where they occur: the matrix mask is
//  applied in VECTOR space rather than to the image, the matrix orientation is
//  fitted ONCE for the scan rather than per pattern, and the verdict carries a
//  completeness requirement the paper's mean-distance score does not have.
//
//  WHY THIS EXISTS AT ALL. On 2026-09-11 the template-matched route was
//  refuted on this repo's own measurement: a bare best-score argmax over
//  phases returned GOLD for a pattern containing only ALUMINIUM, because one
//  radial bin is 0.05 Å⁻¹ and Al-Au (111) differ by 6 % of one bin
//  (`archive/v3/phase-discrimination-2026-09-11.md`). Vector matching works on
//  the peak positions themselves, at the precision the sub-pixel refinement
//  already delivers, so the discriminating quantity is a distance in Å⁻¹ that
//  a reader can compare against the spacing they care about — not a
//  correlation score that hides its own resolution.
//
//  WHAT IT CANNOT DO, stated here rather than discovered later: it is
//  zone-axis only; it cannot separate phases overlapping along the beam; and
//  strain shifts Bragg positions, which Thronsen et al. name as the main cause
//  of their interface errors. One matrix orientation is fitted for the whole
//  scan, so a second matrix grain would be mis-removed — that is a limit of
//  this implementation, not of the method.
//
//  UNVALIDATED. Step 3 of `v3-vector-matching-plan.md` — scoring this against
//  the published ground truth of Thronsen et al. — has NOT been run: it needs a
//  ~7.4 GB download this machine has no room for. Until it has, every number
//  this file produces is an output, not a measurement, and the UI says so.
//

import Foundation
import simd

// MARK: - Settings

package nonisolated struct PhaseVectorSettings: Sendable, Equatable {
    /// Peaks within this of the pattern origin are the direct beam. Å⁻¹.
    package var directBeamRadiusInvAngstrom: Double = 0.15
    /// Peaks beyond this are not reflections: the data's own reach — a
    /// detector edge, or a mask. 0 means the detector is the limit. Å⁻¹.
    /// MEASURED (Thronsen step 3, 2026-09-15): their patterns are masked
    /// beyond 0.70 Å⁻¹, the mask edge is a ring of maxima no phase explains,
    /// and without this every Al position came back "not indexed" (86 %
    /// mislabelled against 13 % with it at the same settings).
    package var maximumVectorInvAngstrom: Double = 0
    /// An experimental vector this close to a matrix reference vector is the
    /// matrix's, and is removed. Their image-space DoG masking, done where the
    /// app already works. Å⁻¹.
    package var matrixToleranceInvAngstrom: Double = 0.02
    /// Largest distance at which an experimental and a reference vector count
    /// as the same reflection. Å⁻¹.
    ///
    /// The default is a budget, not a preference: sub-pixel peak refinement
    /// lands well inside 0.5 detector pixels, and on a typical calibration a
    /// pixel is ~0.008 Å⁻¹, so measurement contributes ~0.004. What dominates
    /// is Q-calibration error — 1 % at |q| = 0.7 Å⁻¹ is 0.007 Å⁻¹ — and
    /// strain, which shifts real Bragg positions and which Thronsen et al.
    /// name as their main source of interface error. 0.02 covers those with
    /// room. It is deliberately NOT generous: every increase widens the
    /// reference discs quadratically, and `chanceMatchFraction` is what that
    /// costs. Measured 2026-09-12: at 0.06 a large-cell precipitate entry
    /// matched a THIRD of any random vector set.
    package var pairRadiusInvAngstrom: Double = 0.02
    /// Fewer surviving vectors than this → the matrix, by exclusion.
    package var minimumVectors: Int = 2

    /// When NO candidate phase clears its guards, fall back to the matrix
    /// verdict if the matrix already explained at least this fraction of the
    /// position's detected vectors. 0 disables it — the shipped default, and
    /// nothing moves until the owner rules on the objection recorded with it.
    /// Measured 2026-09-16; see `open-items.md`.
    package var matrixFallbackExplainedFraction: Double = 0
    /// An entry must account for at least this many surviving vectors. Three,
    /// not two: two points fix a lattice only if you already know which two.
    package var minimumMatchedVectors: Int = 3
    /// … except when the survivors hold a Friedel pair — u and −u within the
    /// pair radius — which IS knowing which two: one lattice row, and the
    /// matrix removal has already said it is not the matrix's. Two, then.
    /// MEASURED on Thronsen et al.'s dataset A (step 3, 2026-09-15,
    /// `tools/thronsen-dataset`): along [001]Al a T1 variant leaves exactly
    /// that pair and nothing else inside their mask; with a floor of three
    /// T1 recall was 6 %, with two 59 %, and the Al class paid 28 positions
    /// of 21 494 (0.13 %). Two limits, both from Gate B (2026-09-15): the
    /// chance guard still applies, and for a 48-vector entry it admits a pair
    /// only when the accessible radius is above ≈ 0.3 Å⁻¹ (below that the
    /// floor is silently a no-op — recall lost, not safety); and the matrix
    /// challenge cannot reach a two-of-two winner (it must explain strictly
    /// more than two from two), so a second matrix grain whose residual is
    /// exactly a candidate's pair is labelled that candidate. Not seen on
    /// the dataset; not tested.
    package var friedelPairMinimumMatchedVectors: Int = 2
    /// … and must beat CHANCE by this multiple.
    ///
    /// THIS IS THE DEVIATION from the published mean-distance score, and it is
    /// the second thing tried, not the first. A pure mean distance lets a
    /// phase explaining one vector out of ten beat one explaining nine,
    /// because the mean of a single small number is a small number — so the
    /// first attempt required a minimum matched FRACTION. Measured 2026-09-12,
    /// that fails on real geometry: the reference library is capped at
    /// `maximumVectorsPerEntry`, so a pattern showing more spots than the
    /// library holds can never reach any fraction, and the harness's β″
    /// positions went to 0 % indexed while being perfectly matched.
    ///
    /// What actually needs excluding is a match that carries no information,
    /// and that has a number:
    /// `PhaseOrientationReference.chanceMatchFraction` is how often a vector
    /// pointing nowhere in particular lands within the pair radius of some
    /// reference. An entry is eligible only when its matched count exceeds
    /// that expectation by this multiple, so a dense library has to clear a
    /// proportionally higher bar — which is the honest way to let one phase
    /// carry forty reflections and another two.
    ///
    /// **WHEN IT ACTUALLY BINDS — corrected 2026-09-12, after Gate B refuted
    /// the first claim made for it.** The bar is `multiple · V · ρ² · n / R²`,
    /// which at the shipped settings crosses `minimumMatchedVectors` only
    /// above about **45 surviving vectors per pattern** — and the repo's own
    /// real cube has a median of **7**. So on typical SPED data the
    /// matched-vector floor is the binding constraint and this is inert.
    /// Measured, and printed by the gate (M3): removing this guard ALONE
    /// leaves random-vector accuracy at 99.2 %, unchanged; removing the FLOOR
    /// alone takes it to 48.8 %; removing both takes it to 5.5 %. The note
    /// that stood here read the 99.2 → 5.5 collapse as this guard's doing,
    /// and it is the floor's.
    ///
    /// It is kept rather than deleted as dead weight, because it is what
    /// bounds a dense library on a pattern rich enough to need bounding —
    /// exactly the case a fixed `maximumVectorsPerEntry` cannot see.
    package var chanceMatchMultiple: Double = 5
    /// Best mean distance above this → "not indexed" rather than a forced
    /// label. Å⁻¹. Under `pairRadiusInvAngstrom`: the pair radius says what
    /// could be the same reflection, this says what is close enough to call
    /// it. THREE QUARTERS of the pair radius, not half (MEASURED 2026-09-15,
    /// Thronsen step 3): a correct 6–11-vector fit under strain and
    /// sub-pixel jitter has a mean residual of 0.5–0.8 pair radii, so at
    /// half it fell over the cliff while a lucky two-vector pair passed;
    /// at 0.75 and at 1.0 both datasets read the same (Thronsen 7.96 %
    /// free / 6.64 % with the OR at 0.75, 7.94 / 6.61 at 1.0, seven
    /// positions apart; the demo cube identical at all three), Al and the
    /// demo cube's false labels unchanged. Not 1.0:
    /// a mean of distances each within the pair radius is within it, so
    /// the refusal would never fire and the setting would be dead.
    package var notIndexedAboveInvAngstrom: Double = 0.015
    /// The winner must beat the best entry of every OTHER candidate phase by
    /// this margin, else "not indexed". 0 disables the requirement. This is
    /// the contrast margin the 2026-09-11 refutation asked for; it is off by
    /// default because a margin that is not measured on the data at hand is a
    /// guess, and `tools/phase-vector-matching` is where it gets measured.
    package var minimumPhaseContrastInvAngstrom: Double = 0
    /// A candidate entry whose phase lists an orientation relationship
    /// (`PhaseDefinition.orientationRelationships`) is scored only when its
    /// derived azimuth agrees with a listed pair's, relative to the fitted
    /// matrix entry, within this many degrees. MEASURED 2026-09-15 (Thronsen step 3):
    /// correct face-on matches land within ±15° of the orientation
    /// relationship and the confusing ones — face-on taken for edge-on —
    /// at 45°; but half of the correct edge-on matches sit near 22° and
    /// 67°, which a {0, 90} list at this tolerance cuts (edge-on recall
    /// 50 → 31 %). Open in `docs/open-items.md`; no phase lists angles by
    /// default.
    package var orientationRelationshipToleranceDeg: Double = 10

    package nonisolated init() {}
}

/// What the tolerances mean on a PARTICULAR detector, and whether they can be
/// met on it.
///
/// WHY THIS EXISTS. The settings are in Å⁻¹ because that is the physics; the
/// measurement is on a detector grid. The two only meet through the Q
/// calibration, and nothing showed the user the conversion. Measured on the
/// owner's own run, 2026-09-12: on a 4x-binned cube at 0.045741 Å⁻¹ per
/// detector pixel, the shipped 0.020 Å⁻¹ tolerances are **0.44 of one pixel**.
/// Matrix removal then removed NOTHING — 802 752 detected peaks across
/// 108 900 patterns, matrix verdict count **zero** — and 108 899 of 108 900
/// positions came back "not indexed". The app had every number needed to say
/// so before the run and said none of them.
///
/// It is arithmetic, not a threshold anyone tuned, and it lives in Core so it
/// is testable and so the panel and any future refusal read the same numbers.
package nonisolated struct PhaseVectorResolution: Sendable, Equatable {
    package let invAngstromPerPixel: Double
    package let pairRadiusPixels: Double
    package let matrixRemovalPixels: Double
    package let notIndexedAbovePixels: Double

    /// A sentence for the user when a tolerance is smaller than the detector
    /// grid it will be measured on, else nil.
    ///
    /// Deliberately worded as DEMANDING and not as impossible: sub-pixel
    /// refinement genuinely beats one pixel on a well-sampled disk, and this
    /// app measures it doing so. What it cannot do is beat one pixel on a
    /// heavily binned detector whose disks are two or three pixels across —
    /// which is the case that produced the run above. The number is given so
    /// the user can judge; the app does not refuse on it.
    package var advice: String? {
        guard invAngstromPerPixel > 0, pairRadiusPixels.isFinite else { return nil }
        guard pairRadiusPixels < 1 else { return nil }
        return String(
            format: "Pair radius is %.2f of one detector pixel (%.4f Å⁻¹ each). "
            + "Matching that tightly needs sub-pixel peak positions AND an "
            + "accurate Q scale; on a binned detector it will match nothing.",
            pairRadiusPixels, invAngstromPerPixel)
    }

    /// The same settings expressed on this detector: one pixel for the two
    /// tolerances, three quarters of a pixel for the verdict distance — the
    /// shipped ratio (0.02 / 0.02 / 0.015, measured 2026-09-15), carried
    /// onto the grid the data is on.
    package func scaledToDetector(_ settings: PhaseVectorSettings) -> PhaseVectorSettings {
        guard invAngstromPerPixel > 0 else { return settings }
        var out = settings
        out.pairRadiusInvAngstrom = invAngstromPerPixel
        out.matrixToleranceInvAngstrom = invAngstromPerPixel
        out.notIndexedAboveInvAngstrom = invAngstromPerPixel * 0.75
        out.directBeamRadiusInvAngstrom = max(settings.directBeamRadiusInvAngstrom,
                                              3 * invAngstromPerPixel)
        return out
    }

    package init(settings: PhaseVectorSettings, invAngstromPerPixel: Double) {
        self.invAngstromPerPixel = invAngstromPerPixel
        let scale = invAngstromPerPixel > 0 ? invAngstromPerPixel : .nan
        pairRadiusPixels = settings.pairRadiusInvAngstrom / scale
        matrixRemovalPixels = settings.matrixToleranceInvAngstrom / scale
        notIndexedAbovePixels = settings.notIndexedAboveInvAngstrom / scale
    }
}

// MARK: - Result

package nonisolated enum PhaseVerdict: UInt8, Sendable, CaseIterable {
    /// Too little survived matrix removal to index — the matrix, by exclusion.
    case matrix = 0
    /// A candidate phase won, within every threshold.
    case indexed = 1
    /// Vectors survived, and nothing explained them well enough.
    case notIndexed = 2
    /// No usable peaks at this position at all.
    case noData = 3

    package var displayName: String {
        switch self {
        case .matrix: "Matrix"
        case .indexed: "Indexed"
        case .notIndexed: "Not indexed"
        case .noData: "No peaks"
        }
    }
}

/// One scan position's verdict and the evidence behind it. Every field the
/// evidence overlay draws is here, so a label can always be taken apart.
package nonisolated struct PhaseVectorResult: Sendable, Equatable {
    package var verdict: PhaseVerdict = .noData
    /// Winning phase, or the matrix's index for `.matrix`. −1 otherwise.
    package var phaseIndex: Int32 = -1
    /// Winning library entry (phase × zone axis × in-plane rotation). −1 when
    /// the verdict did not come from an entry.
    package var entryIndex: Int32 = -1
    /// Mean |u − v| over the unique reference vectors matched, Å⁻¹. NaN when
    /// no entry was scored.
    package var score: Float = .nan
    /// Surviving experimental vectors that found a reference within
    /// `pairRadius` in the winning entry.
    package var matchedCount: Int32 = 0
    /// Experimental vectors left after the direct beam and the matrix.
    package var survivingCount: Int32 = 0
    /// Experimental vectors removed as the matrix's.
    package var removedCount: Int32 = 0
    /// Best entry of the best OTHER candidate phase — the contrast the
    /// 2026-09-11 refutation showed a bare argmax hides. −1 / NaN if there is
    /// only one candidate phase.
    package var runnerUpPhaseIndex: Int32 = -1
    package var runnerUpScore: Float = .nan

    package nonisolated init() {}

    /// Margin over the best other phase, Å⁻¹. NaN when there is no other.
    package var phaseContrast: Float {
        guard runnerUpScore.isFinite, score.isFinite else { return .nan }
        return runnerUpScore - score
    }
}

/// A verdict per scan position, row-major.
package nonisolated struct PhaseMap: Sendable {
    package let width: Int, height: Int
    package var results: [PhaseVectorResult]
    /// The one matrix entry fitted for the whole scan. −1 if none was fitted.
    package let matrixEntryIndex: Int
    /// Phase display names, indexed by `phaseIndex`.
    package let phaseNames: [String]
    package let matrixPhaseIndex: Int

    package nonisolated init(width: Int, height: Int, matrixEntryIndex: Int,
                             phaseNames: [String], matrixPhaseIndex: Int) {
        self.width = width; self.height = height
        self.results = Array(repeating: PhaseVectorResult(), count: max(0, width * height))
        self.matrixEntryIndex = matrixEntryIndex
        self.phaseNames = phaseNames
        self.matrixPhaseIndex = matrixPhaseIndex
    }

    package func count(of verdict: PhaseVerdict) -> Int {
        results.reduce(0) { $0 + ($1.verdict == verdict ? 1 : 0) }
    }

    /// Positions labelled with each phase, by phase index.
    package var phaseCounts: [Int] {
        var out = [Int](repeating: 0, count: phaseNames.count)
        for r in results where r.phaseIndex >= 0 && Int(r.phaseIndex) < out.count {
            if r.verdict == .indexed || r.verdict == .matrix { out[Int(r.phaseIndex)] += 1 }
        }
        return out
    }
}

// MARK: - The matcher

package nonisolated enum PhaseVectorMatcher {

    /// One pattern's peaks as calibrated in-plane vectors (Å⁻¹), with the
    /// direct beam removed.
    ///
    /// The frame is exactly ACOM's — `dx = x − originX`, `dy = y − originY`,
    /// times `invAngstromPerPixel` — so a vector here and a vector there mean
    /// the same thing. Ellipse correction and per-position origin collapse are
    /// the caller's job, through `BraggVectors.calibrated(with:referenceOrigin:)`,
    /// for the same reason ACOM does it that way: they belong to calibration,
    /// not to matching. The R-Q rotation is deliberately NOT applied — the
    /// in-plane rotation is an axis of this search, fitted from the data, so
    /// applying a stored rotation as well would double-count it.
    package static func experimentalVectors(peaks: [BraggPeak],
                                            originX: Float, originY: Float,
                                            invAngstromPerPixel: Double,
                                            directBeamRadiusInvAngstrom: Double,
                                            maximumVectorInvAngstrom: Double = 0)
        -> [SIMD2<Double>] {
        var out: [SIMD2<Double>] = []
        out.reserveCapacity(peaks.count)
        for p in peaks {
            let q = SIMD2(Double(p.x - originX) * invAngstromPerPixel,
                          Double(p.y - originY) * invAngstromPerPixel)
            let len = simd_length(q)
            guard len.isFinite, len > directBeamRadiusInvAngstrom,
                  maximumVectorInvAngstrom <= 0 || len < maximumVectorInvAngstrom else { continue }
            out.append(q)
        }
        return out
    }

    // MARK: Nearest reference, with a length-band prune

    /// Index of and distance to the nearest vector of `refs` within `radius`.
    ///
    /// `refs` must be sorted by `length`, which `PhaseReferenceLibrary`
    /// guarantees: the reverse triangle inequality gives
    /// `| |u| − |v| | ≤ |u − v|`, so only the band `|u| ± radius` can hold a
    /// match and the rest is skipped without a distance computation.
    package static func nearest(_ u: SIMD2<Double>, in refs: [ReferenceVector],
                                radius: Double) -> (index: Int, distance: Double)? {
        guard !refs.isEmpty else { return nil }
        let uLen = simd_length(u)
        var lo = 0, hi = refs.count
        let lowerLength = uLen - radius
        while lo < hi {
            let mid = (lo + hi) / 2
            if refs[mid].length < lowerLength { lo = mid + 1 } else { hi = mid }
        }
        let upperLength = uLen + radius
        var best = -1
        var bestD = Double.infinity
        var i = lo
        while i < refs.count, refs[i].length <= upperLength {
            let d = simd_distance(u, refs[i].q)
            if d < bestD { bestD = d; best = i }
            i += 1
        }
        return (best >= 0 && bestD <= radius) ? (best, bestD) : nil
    }

    /// Per-worker scratch: one slot per reference vector, so scoring an entry
    /// allocates nothing.
    package nonisolated final class Scratch: @unchecked Sendable {
        var bestPerRef: [Double]
        var touched: [Int]
        package init(capacity: Int) {
            bestPerRef = [Double](repeating: .infinity, count: max(1, capacity))
            touched = []
            touched.reserveCapacity(max(1, capacity))
        }
    }

    /// Score `vectors` against one entry.
    ///
    /// For each experimental vector keep only its closest reference vector
    /// (their per-pattern reference subset, so a thin precipitate showing two
    /// spots is not penalised against a phase with forty), then average over
    /// the UNIQUE references hit — a reference claimed twice contributes its
    /// better distance once. Returns nil when nothing matched.
    package static func score(vectors: [SIMD2<Double>],
                              against entry: PhaseOrientationReference,
                              pairRadius: Double,
                              scratch: Scratch)
        -> (score: Double, matched: Int, uniqueReferences: Int)? {
        if scratch.bestPerRef.count < entry.vectors.count {
            scratch.bestPerRef = [Double](repeating: .infinity, count: entry.vectors.count)
        }
        scratch.touched.removeAll(keepingCapacity: true)
        var matched = 0
        for u in vectors {
            guard let hit = nearest(u, in: entry.vectors, radius: pairRadius) else { continue }
            matched += 1
            if scratch.bestPerRef[hit.index].isInfinite { scratch.touched.append(hit.index) }
            if hit.distance < scratch.bestPerRef[hit.index] {
                scratch.bestPerRef[hit.index] = hit.distance
            }
        }
        defer { for i in scratch.touched { scratch.bestPerRef[i] = .infinity } }
        guard !scratch.touched.isEmpty else { return nil }
        var sum = 0.0
        for i in scratch.touched { sum += scratch.bestPerRef[i] }
        return (sum / Double(scratch.touched.count), matched, scratch.touched.count)
    }

    /// Do `vectors` hold a Friedel pair — some u and v with |u + v| within
    /// `radius`? A ±g pair is one reciprocal-lattice row, the smallest thing
    /// that is evidence of a lattice rather than of two coincidences.
    package static func containsFriedelPair(_ vectors: [SIMD2<Double>], radius: Double) -> Bool {
        guard vectors.count >= 2 else { return false }
        for i in 0..<(vectors.count - 1) {
            for j in (i + 1)..<vectors.count
            where simd_length(vectors[i] + vectors[j]) <= radius && simd_length(vectors[i]) > radius {
                return true
            }
        }
        return false
    }

    // MARK: Which zone axis is the specimen on?

    /// One candidate beam direction, scored against the scan's own peaks.
    package nonisolated struct ZoneAxisFit: Sendable, Equatable {
        package let zoneAxis: SIMD3<Int>
        package let inPlaneRotationRad: Double
        /// Experimental vectors this axis accounts for, across the sample.
        package let matchedVectors: Int
        /// Experimental vectors in the sample, total.
        package let totalVectors: Int
        /// Mean |u − v| over the pairs it made, Å⁻¹.
        package let meanDistance: Double
        /// How many of `totalVectors` an entry this dense would match by
        /// accident, summed over the sampled patterns at each pattern's own
        /// reach. The number that says whether `matchedVectors` is evidence.
        ///
        /// WHY IT IS HERE (2026-09-14). Without it the sweep presented a
        /// ⟨112⟩ family at 8 % exactly the way it presents a ⟨110⟩ family at
        /// 38 %, and the owner read a coin toss as a fit. It is computed from
        /// the same `chanceMatchFraction` the matcher's own guard uses, so
        /// there is one definition of chance in this file rather than two.
        ///
        /// **IT DOES NOT MARK THAT MOTIVATING CASE, and saying so is the
        /// point** (Gate B, 2026-09-14). At the app's default reference
        /// settings aluminium's ⟨112⟩ entries carry 12 to 16 vectors, not the
        /// 48 the cap allows, so the expectation is 0.37–1.3 % and 8 % clears
        /// five times it. The mark fires only while each pattern's
        /// second-largest |u| stays under about 0.55–0.63 Å⁻¹, and Al {220}
        /// alone is at 0.699. What this buys is the number itself, reported
        /// instead of absent. The owner's case is caught by the SECOND null
        /// below, `sweepMedianFraction`, not by a threshold on this one.
        package let chanceMatchedVectors: Double
        /// The sweep's own null (Gate D, 2026-09-15 night): the explained
        /// fraction of the MEDIAN axis in the sweep this fit came from.
        ///
        /// WHY A SECOND NULL. On a real crystal every wrong axis explains a
        /// large share of the vectors by SHARED reflections, not by chance:
        /// measured on planted aluminium at 2° steps with 30 % of spots
        /// missing, 0.004 Å⁻¹ of jitter and three spurious peaks per
        /// pattern, the median wrong axis explains 11–16 % (⟨110⟩, ⟨112⟩
        /// and ⟨001⟩ plants) and the worst wrong family up to 25 %, while
        /// every one of the 49 axes clears five times the disc-chance
        /// expectation. That is why the owner's ⟨112⟩ at 8 % could never be
        /// marked by `chanceMatchedVectors`: it was not chance, it was the
        /// true axis's reflections seen through a wrong projection. Against
        /// the sweep's median those true families sat at 4.8–6.8× and every
        /// wrong family at 0.7–1.6×; the bar is placed at 2×. On vectors
        /// pointing nowhere the sweep median is ~0.5 % and the disc rule is
        /// what refuses; the two rules cover different failures and both
        /// must pass.
        ///
        /// WHAT THE BAR IS NOT (Gate B, 2026-09-15 night): a clean separator
        /// for every truth. ⟨111⟩, ⟨012⟩ and ⟨210⟩ plants put the true family
        /// at 2.7–2.8× and the worst wrong at 1.0–2.0×; a ⟨122⟩ plant puts
        /// the true family at 2.8× and the ⟨100⟩ family at 2.7–2.9× — a
        /// wrong family clearing the bar, sometimes above the truth. A
        /// high-index truth with few reflections shares too much with a
        /// low-index axis for a ratio to tell them apart; both rows then
        /// read as informative and the tie caption is the honest thing on
        /// screen. Heavier degradation (to 92 % missing, 15 spurious) never
        /// made the sweep rule bind before the disc rule; a two-grain scan
        /// left both true families at 5×. DEVIATION: py4DSTEM's zone-axis
        /// tools have no sweep null and no informativeness verdict.
        ///
        /// Fewer than five axes in the sweep is no null at all — with two,
        /// the "median" is the top axis's own fraction and the ratio
        /// saturates at 1 — so the median is reported as 0 (ratio infinite,
        /// the sweep rule inert) below that count.
        package let sweepMedianFraction: Double
        /// Explained fraction relative to the sweep's median axis.
        package var sweepRatio: Double {
            sweepMedianFraction > 0 ? explainedFraction / sweepMedianFraction : .infinity
        }
        /// Below this ratio an axis explains no more than a wrong axis does
        /// on the same data (measured: wrong ≤ 1.6×, true ≥ 4.8×).
        package static let informativeSweepRatio = 2.0
        package var isAboveSweep: Bool { sweepRatio >= Self.informativeSweepRatio }
        /// Both nulls: chance vectors (the disc model) and wrong axes on a
        /// real crystal (the sweep median).
        package func isInformative(multiple: Double) -> Bool {
            isAboveChance(multiple: multiple) && isAboveSweep
        }

        package var explainedFraction: Double {
            totalVectors > 0 ? Double(matchedVectors) / Double(totalVectors) : 0
        }
        /// The same fraction chance alone would explain.
        package var chanceFraction: Double {
            totalVectors > 0 ? chanceMatchedVectors / Double(totalVectors) : 0
        }
        /// Does this fit carry information, by the matcher's own standard?
        /// `multiple` is `PhaseVectorSettings.chanceMatchMultiple`.
        package func isAboveChance(multiple: Double) -> Bool {
            Double(matchedVectors) >= multiple * chanceMatchedVectors
        }
        package var inPlaneDegrees: Double { inPlaneRotationRad * 180 / .pi }
    }

    /// Rank beam directions by how much of the scan's measured peaks each one
    /// explains — the question "what orientation is this specimen on?", asked
    /// of the data instead of assumed.
    ///
    /// WHY IT EXISTS. A matrix viewed down an axis it is not on presents no
    /// reflections to remove, nothing is removed, and every position comes
    /// back "not indexed" — which on screen is indistinguishable from a method
    /// that does not work. The owner hit exactly that on 2026-09-12: Al set to
    /// [001], matrix verdict count **zero** across 108 900 positions. Measured
    /// afterwards by `tools/phase-map-probe`, his specimen is on **⟨110⟩**, and
    /// all five sampled ⟨110⟩ equivalents tied at 39.0 % — an exact tie across
    /// the family being what cubic symmetry requires, and therefore a check
    /// that the sweep is behaving rather than merely returning something.
    ///
    /// Ranked by explained fraction, tie-broken on the lower mean distance.
    /// NOT by mean distance alone, for the same reason `fitMatrixOrientation`
    /// is not: an axis explaining one vector at 0.001 Å⁻¹ would beat one
    /// explaining nine at 0.01.
    package static func fitZoneAxis(bragg: BraggVectors,
                                    crystal: Crystal,
                                    referenceSettings: PhaseReferenceSettings,
                                    settings: PhaseVectorSettings,
                                    originX: Float, originY: Float,
                                    invAngstromPerPixel: Double,
                                    candidateAxes: [SIMD3<Int>]
                                        = PhaseReferenceLibrary.lowIndexZoneAxes,
                                    inPlaneStepDeg: Double = 5,
                                    sampleLimit: Int = 400,
                                    cancellation: AnalysisCancellationToken? = nil)
        -> [ZoneAxisFit] {
        guard !bragg.peaks.isEmpty, !candidateAxes.isEmpty else { return [] }

        // A subsample, spread across the scan: this answers a question about
        // the GRAIN, and a grain does not change between neighbouring probe
        // positions. Sampling is what keeps a 62-axis sweep interactive.
        let step = max(1, bragg.peaks.count / max(1, sampleLimit))
        var sample: [[SIMD2<Double>]] = []
        var index = 0
        while index < bragg.peaks.count {
            let v = experimentalVectors(
                peaks: bragg.peaks[index], originX: originX, originY: originY,
                invAngstromPerPixel: invAngstromPerPixel,
                directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom,
                maximumVectorInvAngstrom: settings.maximumVectorInvAngstrom)
            if !v.isEmpty { sample.append(v) }
            index += step
        }
        guard !sample.isEmpty else { return [] }
        let totalVectors = sample.reduce(0) { $0 + $1.count }

        // Each pattern's own reach, for the chance expectation: the
        // SECOND-largest |u|, the same rule `classify` uses and for the same
        // measured reason — with `max`, one spurious maximum far out inflates
        // the area and weakens the estimate for every other vector.
        let reach: [Double] = sample.map { vectors in
            var largest = 0.0, second = 0.0
            for u in vectors {
                let r = simd_length(u)
                if r > largest { second = largest; largest = r }
                else if r > second { second = r }
            }
            return second > 0 ? second : largest
        }

        var reference = referenceSettings
        reference.inPlaneStepDeg = inPlaneStepDeg
        let reflections = crystal.reflections(kMax: reference.kMaxInvAngstrom)
        let rotations = PhaseReferenceLibrary.inPlaneSteps(reference)
        let scratch = Scratch(capacity: max(1, reference.maximumVectorsPerEntry))

        // Every axis's best rotation first; the sweep median is known only
        // once all of them are, and each fit carries it.
        var winners: [(axis: SIMD3<Int>, theta: Double, matched: Int, meanDistance: Double, chance: Double)] = []
        for axis in candidateAxes {
            if cancellation?.isCancelled == true { break }
            let base = PhaseReferenceLibrary.projectedVectors(
                reflections: reflections, crystal: crystal,
                zoneAxis: axis, settings: reference)
            guard !base.isEmpty else { continue }
            // Constant across this axis's rotations: rotating an entry moves
            // its references, it does not change how many there are.
            let unrotated = PhaseOrientationReference(
                phaseIndex: 0, zoneAxis: axis, inPlaneRotationRad: 0, vectors: base)
            var chanceMatched = 0.0
            for (index, vectors) in sample.enumerated() {
                chanceMatched += unrotated.chanceMatchFraction(
                    pairRadius: settings.matrixToleranceInvAngstrom,
                    accessibleRadius: reach[index]) * Double(vectors.count)
            }
            var best: (theta: Double, matched: Int, meanDistance: Double)?
            for theta in rotations {
                let entry = PhaseOrientationReference(
                    phaseIndex: 0, zoneAxis: axis, inPlaneRotationRad: theta,
                    vectors: PhaseReferenceLibrary.rotate(base, by: theta))
                var matched = 0, pairs = 0
                var total = 0.0
                for vectors in sample {
                    guard let sc = score(vectors: vectors, against: entry,
                                         pairRadius: settings.matrixToleranceInvAngstrom,
                                         scratch: scratch) else { continue }
                    matched += sc.matched
                    total += sc.score * Double(sc.uniqueReferences)
                    pairs += sc.uniqueReferences
                }
                guard pairs > 0 else { continue }
                let meanDistance = total / Double(pairs)
                if best == nil || matched > best!.matched
                    || (matched == best!.matched && meanDistance < best!.meanDistance) {
                    best = (theta, matched, meanDistance)
                }
            }
            if let best {
                winners.append((axis, best.theta, best.matched, best.meanDistance, chanceMatched))
            }
        }
        let fractions = winners.map { Double($0.matched) / Double(totalVectors) }.sorted()
        let sweepMedian = fractions.count >= 5 ? fractions[fractions.count / 2] : 0
        var out = winners.map {
            ZoneAxisFit(zoneAxis: $0.axis, inPlaneRotationRad: $0.theta,
                        matchedVectors: $0.matched, totalVectors: totalVectors,
                        meanDistance: $0.meanDistance, chanceMatchedVectors: $0.chance,
                        sweepMedianFraction: sweepMedian)
        }
        out.sort {
            $0.matchedVectors != $1.matchedVectors
                ? $0.matchedVectors > $1.matchedVectors
                : $0.meanDistance < $1.meanDistance
        }
        return out
    }

    // MARK: The matrix orientation, fitted once

    /// The single matrix entry that best explains the whole scan.
    ///
    /// DEVIATION, deliberate: the paper masks the matrix per pattern. Here the
    /// matrix is one grain across the scan, so its in-plane rotation is one
    /// number — fitting it once is both faster and steadier than re-deciding
    /// it at every position from a handful of peaks. The cost is stated in the
    /// file header: a second matrix grain would be mis-removed.
    ///
    /// Chosen by total matched vectors, tie-broken by lower mean distance. Not
    /// by mean distance alone: an entry matching one vector at 0.001 Å⁻¹ would
    /// win over one matching nine at 0.01.
    ///
    /// This sentence used to end "…the same completeness trap
    /// `minimumMatchedFraction` closes on the candidate side". **There is no
    /// such symbol and there never was** (`grep -rn` over every `.swift` and
    /// `.md`, introduced with this comment in `cee63e6`; corrected
    /// 2026-09-16). The candidate side is guarded by `minimumMatchedVectors`
    /// and `chanceMatchMultiple`, which are floors on COUNT, not on the
    /// fraction of an entry's accessible vectors that matched — a different
    /// quantity, and not the one the sentence claimed. So the trap IS open on
    /// the candidate side: the cross-phase winner below is still chosen by mean
    /// distance alone, and a 2-vector Friedel pair at 0.004 beats a 10-vector
    /// match at 0.012. That is measured, not hypothetical (`open-items.md`).
    package static func fitMatrixOrientation(bragg: BraggVectors,
                                             library: PhaseReferenceLibrary,
                                             settings: PhaseVectorSettings,
                                             originX: Float, originY: Float,
                                             invAngstromPerPixel: Double,
                                             sampleLimit: Int = 2000,
                                             cancellation: AnalysisCancellationToken? = nil)
        -> (entryIndex: Int, matched: Int, meanDistance: Double)? {
        let matrixEntries = library.matrixEntryIndices
        guard !matrixEntries.isEmpty, !bragg.peaks.isEmpty else { return nil }

        let stride = max(1, bragg.peaks.count / max(1, sampleLimit))
        var sample: [[SIMD2<Double>]] = []
        sample.reserveCapacity(min(bragg.peaks.count, sampleLimit) + 1)
        var index = 0
        while index < bragg.peaks.count {
            let v = experimentalVectors(
                peaks: bragg.peaks[index], originX: originX, originY: originY,
                invAngstromPerPixel: invAngstromPerPixel,
                directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom,
                maximumVectorInvAngstrom: settings.maximumVectorInvAngstrom
            )
            if !v.isEmpty { sample.append(v) }
            index += stride
        }
        guard !sample.isEmpty else { return nil }

        let capacity = matrixEntries.map { library.entries[$0].vectors.count }.max() ?? 1
        let scratch = Scratch(capacity: capacity)
        var best: (entryIndex: Int, matched: Int, meanDistance: Double)?
        for entryIndex in matrixEntries {
            if cancellation?.isCancelled == true { return best }
            let entry = library.entries[entryIndex]
            var matched = 0
            var sum = 0.0
            var pairs = 0
            for vectors in sample {
                guard let s = score(vectors: vectors, against: entry,
                                    pairRadius: settings.matrixToleranceInvAngstrom,
                                    scratch: scratch) else { continue }
                matched += s.matched
                sum += s.score * Double(s.uniqueReferences)
                pairs += s.uniqueReferences
            }
            guard matched > 0, pairs > 0 else { continue }
            let mean = sum / Double(pairs)
            if let b = best {
                if matched > b.matched || (matched == b.matched && mean < b.meanDistance) {
                    best = (entryIndex, matched, mean)
                }
            } else {
                best = (entryIndex, matched, mean)
            }
        }
        return best
    }

    // MARK: One pattern

    /// Classify one pattern's already-calibrated vectors.
    package static func classify(vectors: [SIMD2<Double>],
                                 library: PhaseReferenceLibrary,
                                 settings: PhaseVectorSettings,
                                 matrixEntry: PhaseOrientationReference?,
                                 candidateEntryIndices: [Int],
                                 scratch: Scratch,
                                 matrixChallenge: [PhaseOrientationReference] = []) -> PhaseVectorResult {
        var result = PhaseVectorResult()
        guard !vectors.isEmpty else { return result }

        // 1 — matrix removal in vector space.
        var surviving: [SIMD2<Double>] = []
        surviving.reserveCapacity(vectors.count)
        if let matrixEntry {
            for u in vectors {
                if nearest(u, in: matrixEntry.vectors,
                           radius: settings.matrixToleranceInvAngstrom) == nil {
                    surviving.append(u)
                }
            }
        } else {
            surviving = vectors
        }
        result.survivingCount = Int32(surviving.count)
        result.removedCount = Int32(vectors.count - surviving.count)

        // 2 — the matrix, by exclusion.
        if surviving.count < settings.minimumVectors {
            result.verdict = .matrix
            result.phaseIndex = Int32(library.matrixPhaseIndex)
            return result
        }

        // 3 — score every candidate entry; keep the best per phase.
        //
        // The area chance is measured against is the one the DATA occupies,
        // not the library's kMax: if every surviving vector sits inside
        // 0.7 Å⁻¹, references beyond it cannot be hit by accident and must not
        // dilute the estimate.
        // The radius is the SECOND largest |u|, not the largest. Measured
        // 2026-09-12 (Gate B finding 6): with `max`, one spurious maximum far
        // out inflates the area the chance expectation is computed over,
        // weakens the guard for every other vector in the pattern, and took a
        // 1024-pattern false-positive rate from 0 to 10. Second-largest costs
        // nothing, is exact whenever the outermost peak is real, and cannot be
        // moved by a single outlier.
        var largest = 0.0, accessibleRadius = 0.0
        for u in surviving {
            let r = simd_length(u)
            if r > largest { accessibleRadius = largest; largest = r }
            else if r > accessibleRadius { accessibleRadius = r }
        }
        if accessibleRadius <= 0 { accessibleRadius = largest }
        var bestPerPhase: [Int: (entryIndex: Int, score: Double, matched: Int)] = [:]
        // The floor a candidate must clear: `minimumMatchedVectors`, or the
        // Friedel-pair floor when the survivors hold u and −u (see the
        // setting's note). Computed once per pattern, not per entry.
        let matchedFloor = containsFriedelPair(surviving, radius: settings.pairRadiusInvAngstrom)
            ? min(settings.minimumMatchedVectors, settings.friedelPairMinimumMatchedVectors)
            : settings.minimumMatchedVectors
        for entryIndex in candidateEntryIndices {
            let entry = library.entries[entryIndex]
            guard let s = score(vectors: surviving, against: entry,
                                pairRadius: settings.pairRadiusInvAngstrom,
                                scratch: scratch) else { continue }
            let chance = entry.chanceMatchFraction(
                pairRadius: settings.pairRadiusInvAngstrom,
                accessibleRadius: accessibleRadius) * Double(surviving.count)
            guard s.matched >= matchedFloor,
                  Double(s.matched) >= settings.chanceMatchMultiple * chance
            else { continue }
            let current = bestPerPhase[entry.phaseIndex]
            if current == nil || s.score < current!.score {
                bestPerPhase[entry.phaseIndex] = (entryIndex, s.score, s.matched)
            }
        }
        guard !bestPerPhase.isEmpty else {
            if settings.matrixFallbackExplainedFraction > 0, !vectors.isEmpty,
               Double(result.removedCount) / Double(vectors.count)
                   >= settings.matrixFallbackExplainedFraction {
                result.verdict = .matrix
                result.phaseIndex = Int32(library.matrixPhaseIndex)
                result.entryIndex = -1
                return result
            }
            result.verdict = .notIndexed
            return result
        }

        let ranked = bestPerPhase.sorted { $0.value.score < $1.value.score }
        let winner = ranked[0]
        result.score = Float(winner.value.score)
        result.matchedCount = Int32(winner.value.matched)
        if ranked.count > 1 {
            result.runnerUpPhaseIndex = Int32(ranked[1].key)
            result.runnerUpScore = Float(ranked[1].value.score)
        }

        // 4 — the two refusals. Both are recorded with the winner's numbers
        // still attached, so "not indexed" can be inspected rather than
        // guessed at.
        if winner.value.score > settings.notIndexedAboveInvAngstrom {
            result.verdict = .notIndexed
            return result
        }
        if settings.minimumPhaseContrastInvAngstrom > 0, ranked.count > 1 {
            let margin = ranked[1].value.score - winner.value.score
            if margin < settings.minimumPhaseContrastInvAngstrom {
                result.verdict = .notIndexed
                return result
            }
        }

        // 5 — the matrix gets the last word.
        //
        // WHY, and what it fixes (2026-09-14, Gate D). Steps 1-4 ask only
        // which CANDIDATE explains the surviving vectors best. They never ask
        // whether those vectors are unexplained at all. At a position where
        // the matrix crystal is present on a zone axis other than the fitted
        // one, step 1 removes almost nothing and the whole pattern is offered
        // to the candidates — and a candidate coherent with the matrix wins by
        // default, because nothing else is in the competition. Measured on the
        // demo cube: 2 250 positions of pure aluminium on [011] came back
        // 100 % "β″ [001]". β″ [001] covers 10 of the 16 [011]Al reflections
        // at 0.0059 Å⁻¹; Al [011] covers all 16 at 0.0000 Å⁻¹, and was never
        // asked.
        //
        // So before a position may be called a candidate phase, the matrix
        // crystal is offered every low-index zone axis
        // (`matrixChallengeBases`, the fixed 49-direction list — NOT a list
        // the scan selects, and it ignores any zone axis the user restricted
        // the matrix phase to), scored by the same rule and held to the same
        // eligibility as any candidate.
        //
        // THE RULE: the challenger must explain STRICTLY MORE vectors, at a
        // smaller mean distance. See `challengeByMatrix` for why "strictly
        // more" rather than "at least as many" — it is what makes a fully
        // explained precipitate impossible to erase.
        //
        // THE IN-PLANE ROTATION IS DERIVED HERE, NOT FITTED FOR THE SCAN, and
        // that correction is the whole reason this comment is long. The first
        // implementation took one rotation per axis from `fitZoneAxis` — a
        // whole-scan fit — and the fixture refuted it the same evening: at a
        // grain-B position the pool carried [-1 1 0] at 100°, matching NOTHING,
        // while the same axis at 130° matches 8 of 8 at 0.0001 Å⁻¹. A
        // whole-scan fit ranks a rotation by matches summed over every grain,
        // so a rotation picking up scattered matches everywhere outranks the
        // one that fits the grain exactly. A grain's rotation is a property of
        // the GRAIN, and must be asked at the position.
        //
        // Searching 180 rotations × 49 axes per position would cost more than
        // the whole map. Instead the rotations that can possibly win are
        // enumerated: if an orientation explains this pattern, it puts each
        // reference under an observed vector of the same length, so taking the
        // longest few observed vectors and every reference of matching length
        // gives every rotation worth testing — exactly, not on a 2° grid.
        if !matrixChallenge.isEmpty,
           let challenged = challengeByMatrix(
               surviving: surviving, bases: matrixChallenge, settings: settings,
               accessibleRadius: accessibleRadius,
               beating: (matched: winner.value.matched, score: winner.value.score),
               scratch: scratch) {
            result.verdict = .matrix
            result.phaseIndex = Int32(library.matrixPhaseIndex)
            result.entryIndex = -1
            // The CHALLENGER's numbers, not the rejected candidate's: they are
            // the ones that describe the verdict given. Gate B caught the first
            // version discarding them while a comment claimed the verdict could
            // be inspected.
            result.score = Float(challenged.score)
            result.matchedCount = Int32(challenged.matched)
            return result
        }

        result.verdict = .indexed
        result.phaseIndex = Int32(winner.key)
        result.entryIndex = Int32(winner.value.entryIndex)
        return result
    }

    /// The MATRIX crystal projected down every low-index zone axis, unrotated —
    /// the pool `classify` challenges a candidate label with. One entry per
    /// axis (49 at the shipped list), built once per scan; the in-plane
    /// rotation is derived at each position by `challengeByMatrix`, because a
    /// grain's rotation is a property of the grain and not of the scan.
    package static func matrixChallengeBases(
        library: PhaseReferenceLibrary
    ) -> [PhaseOrientationReference] {
        guard library.phases.indices.contains(library.matrixPhaseIndex) else { return [] }
        let crystal = library.phases[library.matrixPhaseIndex].crystal
        let reflections = crystal.reflections(kMax: library.settings.kMaxInvAngstrom)
        guard !reflections.isEmpty else { return [] }
        var out: [PhaseOrientationReference] = []
        out.reserveCapacity(PhaseReferenceLibrary.lowIndexZoneAxes.count)
        for axis in PhaseReferenceLibrary.lowIndexZoneAxes {
            let base = PhaseReferenceLibrary.projectedVectors(
                reflections: reflections, crystal: crystal,
                zoneAxis: axis, settings: library.settings)
            guard !base.isEmpty else { continue }
            out.append(PhaseOrientationReference(
                phaseIndex: library.matrixPhaseIndex, zoneAxis: axis,
                inPlaneRotationRad: 0, vectors: base))
        }
        return out
    }

    /// Does any orientation of the matrix crystal explain `surviving` at least
    /// as well as the winning candidate does? Returns the orientation that
    /// does, or nil.
    ///
    /// THE RULE, and why it is what it is. A challenger must explain STRICTLY
    /// MORE of the pattern than the winning candidate, at a smaller mean
    /// distance, having cleared the same floors a candidate clears.
    ///
    /// "Strictly more" is not fussiness; it is what makes the guard unable to
    /// erase a precipitate. A candidate that already explains every surviving
    /// vector cannot be beaten on count by anything, so a genuine precipitate
    /// pattern is safe BY CONSTRUCTION. The first version required only "at
    /// least as many", and Gate B measured what that costs: with a sparse
    /// precipitate of 3 to 6 vectors and 0.004 Å⁻¹ of jitter — a third of a
    /// detector pixel on the demo cube, inside this file's own stated
    /// measurement budget — a 49-axis search found a coincidental matrix fit
    /// with the same count and a smaller distance, and took 26.5 % of
    /// three-vector precipitates. A second matrix grain is the opposite case:
    /// the candidate explains part of it and the matrix explains all of it.
    ///
    /// Rotations are enumerated, not searched on a grid: an orientation that
    /// explains the pattern must put some reference of matching length under
    /// each observed vector, so every rotation worth testing is
    /// `angle(u) − angle(v)` for an observed `u` and a reference `v` with
    /// `||u| − |v||` inside the pair radius, taken over every surviving
    /// vector. The enumerated angle is exact only for a zero-distance match —
    /// its error is about `asin(ρ/|u|)` — and that error biases toward keeping
    /// the candidate label, which is the safe direction.
    package static func challengeByMatrix(
        surviving: [SIMD2<Double>],
        bases: [PhaseOrientationReference],
        settings: PhaseVectorSettings,
        accessibleRadius: Double,
        beating winner: (matched: Int, score: Double),
        scratch: Scratch
    ) -> (entry: PhaseOrientationReference, score: Double, matched: Int)? {
        guard !surviving.isEmpty, !bases.isEmpty else { return nil }
        let radius = settings.pairRadiusInvAngstrom
        // EVERY surviving vector seeds a rotation, not a chosen few. The first
        // version took the three LONGEST, on the reasoning that an angle is
        // most precise far out — and Gate B measured that backwards: spurious
        // maxima are typically FARTHER out than any real reflection, so the
        // longest-three rule hands the seeds to exactly them. With three
        // spurious peaks beyond the outermost real one, the catch rate for a
        // second matrix grain went from 100 % to 0 % (2026-09-14, 200 trials
        // per scenario). Seeding on all of them removes the failure mode and
        // the arbitrary constant with it; the cost is linear in the vector
        // count, measured at ~1.6 µs per surviving vector per challenged
        // position.
        //
        // The BEST qualifying orientation is returned, not the first. The
        // numbers it carries reach the result and the user, so "whichever
        // zone axis came first in the list" is not good enough for them.
        var best: (entry: PhaseOrientationReference, score: Double, matched: Int)?
        var rotated = surviving
        for base in bases {
            let chance = base.chanceMatchFraction(
                pairRadius: radius, accessibleRadius: accessibleRadius)
                * Double(surviving.count)
            for u in surviving {
                let uLength = simd_length(u)
                guard uLength > 0 else { continue }
                let uAngle = atan2(u.y, u.x)
                for v in base.vectors where abs(v.length - uLength) <= radius {
                    // Rotating the references by θ puts v under u; scoring the
                    // observations rotated by −θ against the unrotated base is
                    // the same comparison and rotates 8 vectors instead of 48.
                    let theta = uAngle - atan2(v.q.y, v.q.x)
                    let c = cos(theta), s = sin(theta)
                    for i in surviving.indices {
                        rotated[i] = SIMD2(surviving[i].x * c + surviving[i].y * s,
                                           -surviving[i].x * s + surviving[i].y * c)
                    }
                    guard let candidate = score(vectors: rotated, against: base,
                                                pairRadius: radius, scratch: scratch)
                    else { continue }
                    guard candidate.matched > winner.matched,
                          candidate.score < winner.score,
                          candidate.matched >= settings.minimumMatchedVectors,
                          Double(candidate.matched) >= settings.chanceMatchMultiple * chance
                    else { continue }
                    if let current = best,
                       current.matched > candidate.matched
                        || (current.matched == candidate.matched
                            && current.score <= candidate.score) { continue }
                    // Rotated, because the entry claims `theta`: a
                    // `PhaseOrientationReference`'s vectors are defined to be
                    // the ones AFTER its in-plane rotation, and handing back
                    // the unrotated base with a non-zero angle would be a trap
                    // for the next caller.
                    best = (PhaseOrientationReference(
                        phaseIndex: base.phaseIndex, zoneAxis: base.zoneAxis,
                        inPlaneRotationRad: theta,
                        vectors: PhaseReferenceLibrary.rotate(base.vectors, by: theta)),
                        candidate.score, candidate.matched)
                }
            }
        }
        return best
    }

    // MARK: The orientation relationship

    /// The in-plane azimuth, radians, of a Cartesian vector projected into
    /// an entry's detector frame (`ACOMOrientation.detectorBasis` of its
    /// zone axis, then the entry's own in-plane rotation) — nil when the
    /// vector is not in the zone (|v·n̂| > 1e-6·|v|, `n̂` the unit zone axis)
    /// or is zero.
    package static func projectedAzimuth(of v: SIMD3<Double>, zoneAxis n: SIMD3<Double>,
                                         inPlaneRotationRad: Double) -> Double? {
        let vLen = simd_length(v)
        guard vLen.isFinite, vLen > 1e-12 else { return nil }
        let nLen = simd_length(n)
        guard nLen.isFinite, nLen > 1e-12 else { return nil }
        let nHat = n / nLen
        guard abs(simd_dot(v, nHat)) <= 1e-6 * vLen else { return nil }

        let basis = ACOMOrientation.detectorBasis(zoneAxis: nHat)
        let x0 = simd_dot(v, basis.columns.0)
        let y0 = simd_dot(v, basis.columns.1)
        let c = cos(inPlaneRotationRad), s = sin(inPlaneRotationRad)
        // The library's own rotate convention (`PhaseReferenceLibrary.rotate`):
        // x' = c·x − s·y, y' = s·x + c·y, i.e. azimuth + θ.
        let x = c * x0 - s * y0
        let y = s * x0 + c * y0
        return atan2(y, x)
    }

    /// Is a candidate entry consistent with any listed relationship, given
    /// the fitted matrix entry?
    ///
    /// For each pair: the candidate's azimuth (its vector in the candidate
    /// crystal, projected through the candidate entry's own zone and
    /// rotation) minus the matrix's azimuth (likewise, through the matrix
    /// entry's own zone and rotation) must be within `toleranceDeg` of 0
    /// modulo 180° (see `PhaseDefinition.orientationRelationships` for why
    /// 180 and not 360). A pair whose vector is not in the respective zone
    /// does not apply to this (candidate, matrix) pair of entries; if no
    /// listed pair applies, the entry is free (true). An empty list is free.
    package static func orientationConsistent(candidate: PhaseOrientationReference,
                                               candidateCrystal: Crystal,
                                               matrix: PhaseOrientationReference,
                                               matrixCrystal: Crystal,
                                               relationships: [OrientationRelationship],
                                               toleranceDeg: Double) -> Bool {
        guard !relationships.isEmpty else { return true }
        guard let candidateZone = PhaseReferenceLibrary.cartesianZoneAxis(
                candidate.zoneAxis, crystal: candidateCrystal),
              let matrixZone = PhaseReferenceLibrary.cartesianZoneAxis(
                matrix.zoneAxis, crystal: matrixCrystal)
        else { return true } // a degenerate zone axis never reaches an entry; defensive.

        var anyApplicable = false
        for relationship in relationships {
            let candidateVector = relationship.candidate.cartesian(in: candidateCrystal)
            let matrixVector = relationship.matrix.cartesian(in: matrixCrystal)
            guard let candidateAz = projectedAzimuth(
                    of: candidateVector, zoneAxis: candidateZone,
                    inPlaneRotationRad: candidate.inPlaneRotationRad),
                  let matrixAz = projectedAzimuth(
                    of: matrixVector, zoneAxis: matrixZone,
                    inPlaneRotationRad: matrix.inPlaneRotationRad)
            else { continue }
            anyApplicable = true
            var d = (candidateAz - matrixAz) * 180 / .pi
            d = d.truncatingRemainder(dividingBy: 180)
            if d < 0 { d += 180 }
            let distance = min(d, 180 - d)
            if distance < toleranceDeg { return true }
        }
        return !anyApplicable
    }

    // MARK: The whole scan

    package static func map(bragg: BraggVectors,
                            library: PhaseReferenceLibrary,
                            settings: PhaseVectorSettings,
                            originX: Float, originY: Float,
                            invAngstromPerPixel: Double,
                            matrixEntryIndex: Int? = nil,
                            cancellation: AnalysisCancellationToken? = nil,
                            progress: ((Double) -> Void)? = nil) -> PhaseMap? {
        guard bragg.scanWidth > 0, bragg.scanHeight > 0,
              bragg.peaks.count == bragg.scanWidth * bragg.scanHeight else { return nil }

        let fitted = matrixEntryIndex ?? fitMatrixOrientation(
            bragg: bragg, library: library, settings: settings,
            originX: originX, originY: originY,
            invAngstromPerPixel: invAngstromPerPixel, cancellation: cancellation
        )?.entryIndex
        guard cancellation?.isCancelled != true else { return nil }

        let matrixEntry = fitted.map { library.entries[$0] }
        // The orientation relationship (2026-09-15): once the matrix is
        // fitted, a candidate entry whose phase lists an orientation
        // relationship is scored only when the relationship's derived
        // azimuth agrees with the fitted matrix entry's — this is what keeps
        // a θ′ edge-on entry, rotated 45° so its (002) at 0.345 Å⁻¹ sits on
        // face-on's (110) at 0.350, from being offered as face-on. A phase
        // with an empty list stays free, so the default (no matrix, or no
        // list anywhere) moves nothing.
        let candidates: [Int]
        if let matrixEntry {
            let matrixCrystal = library.phases[library.matrixPhaseIndex].crystal
            candidates = library.candidateEntryIndices.filter { index in
                let entry = library.entries[index]
                let relationships = library.phases[entry.phaseIndex].orientationRelationships
                // An empty list means free: it would otherwise empty the
                // candidate set and refuse the whole map.
                guard !relationships.isEmpty else { return true }
                return Self.orientationConsistent(
                    candidate: entry, candidateCrystal: library.phases[entry.phaseIndex].crystal,
                    matrix: matrixEntry, matrixCrystal: matrixCrystal,
                    relationships: relationships, toleranceDeg: settings.orientationRelationshipToleranceDeg)
            }
        } else {
            candidates = library.candidateEntryIndices
        }
        guard !candidates.isEmpty else { return nil }

        // Built once for the scan, scored only at positions that would
        // otherwise be labelled — see `classify` step 5 for what it is for.
        let challenge = matrixChallengeBases(library: library)

        var map = PhaseMap(width: bragg.scanWidth, height: bragg.scanHeight,
                           matrixEntryIndex: fitted ?? -1,
                           phaseNames: library.phases.map(\.displayName),
                           matrixPhaseIndex: library.matrixPhaseIndex)

        let capacity = library.entries.map(\.vectors.count).max() ?? 1
        let total = bragg.peaks.count
        let lock = NSLock()
        var done = 0

        map.results.withUnsafeMutableBufferPointer { out in
            let ptr = SendableBox(out.baseAddress!)
            let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, total))
            let progressBatch = max(1, total / (workers * 100))
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                guard cancellation?.isCancelled != true else { return }
                let scratch = Scratch(capacity: capacity)
                var pending = 0
                for position in Swift.stride(from: worker, to: total, by: workers) {
                    if cancellation?.isCancelled == true { break }
                    let vectors = experimentalVectors(
                        peaks: bragg.peaks[position], originX: originX, originY: originY,
                        invAngstromPerPixel: invAngstromPerPixel,
                        directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom,
                        maximumVectorInvAngstrom: settings.maximumVectorInvAngstrom
                    )
                    ptr.value[position] = classify(
                        vectors: vectors, library: library, settings: settings,
                        matrixEntry: matrixEntry, candidateEntryIndices: candidates,
                        scratch: scratch, matrixChallenge: challenge
                    )
                    pending += 1
                    if progress != nil && pending >= progressBatch {
                        lock.lock(); done += pending; let completed = done; lock.unlock()
                        pending = 0
                        progress?(Double(completed) / Double(total))
                    }
                }
                if progress != nil && pending > 0 {
                    lock.lock(); done += pending; let completed = done; lock.unlock()
                    progress?(Double(completed) / Double(total))
                }
            }
        }
        guard cancellation?.isCancelled != true else { return nil }
        return map
    }

    /// Minimal wrapper to pass a mutable pointer into the concurrent closure,
    /// the same shape `OrientationMatcher` uses for its own scan loop.
    private nonisolated struct SendableBox: @unchecked Sendable {
        let value: UnsafeMutablePointer<PhaseVectorResult>
        init(_ v: UnsafeMutablePointer<PhaseVectorResult>) { value = v }
    }
}
