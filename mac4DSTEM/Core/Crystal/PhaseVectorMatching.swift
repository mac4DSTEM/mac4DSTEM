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
    /// An entry must account for at least this many surviving vectors. Three,
    /// not two: two points fix a lattice only if you already know which two.
    package var minimumMatchedVectors: Int = 3
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
    /// label. Å⁻¹. Well under `pairRadiusInvAngstrom`: the pair radius says
    /// what could be the same reflection, this says what is close enough to
    /// call it.
    package var notIndexedAboveInvAngstrom: Double = 0.01
    /// The winner must beat the best entry of every OTHER candidate phase by
    /// this margin, else "not indexed". 0 disables the requirement. This is
    /// the contrast margin the 2026-09-11 refutation asked for; it is off by
    /// default because a margin that is not measured on the data at hand is a
    /// guess, and `tools/phase-vector-matching` is where it gets measured.
    package var minimumPhaseContrastInvAngstrom: Double = 0

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
    /// tolerances, half a pixel for the verdict distance — the shipped ratio
    /// (0.02 / 0.02 / 0.01), carried onto the grid the data is on.
    package func scaledToDetector(_ settings: PhaseVectorSettings) -> PhaseVectorSettings {
        guard invAngstromPerPixel > 0 else { return settings }
        var out = settings
        out.pairRadiusInvAngstrom = invAngstromPerPixel
        out.matrixToleranceInvAngstrom = invAngstromPerPixel
        out.notIndexedAboveInvAngstrom = invAngstromPerPixel / 2
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
                                            directBeamRadiusInvAngstrom: Double)
        -> [SIMD2<Double>] {
        var out: [SIMD2<Double>] = []
        out.reserveCapacity(peaks.count)
        for p in peaks {
            let q = SIMD2(Double(p.x - originX) * invAngstromPerPixel,
                          Double(p.y - originY) * invAngstromPerPixel)
            let len = simd_length(q)
            guard len.isFinite, len > directBeamRadiusInvAngstrom else { continue }
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
    /// win over one matching nine at 0.01, which is the same completeness trap
    /// `minimumMatchedFraction` closes on the candidate side.
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
                directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom
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
                                 scratch: Scratch) -> PhaseVectorResult {
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
        for entryIndex in candidateEntryIndices {
            let entry = library.entries[entryIndex]
            guard let s = score(vectors: surviving, against: entry,
                                pairRadius: settings.pairRadiusInvAngstrom,
                                scratch: scratch) else { continue }
            let chance = entry.chanceMatchFraction(
                pairRadius: settings.pairRadiusInvAngstrom,
                accessibleRadius: accessibleRadius) * Double(surviving.count)
            guard s.matched >= settings.minimumMatchedVectors,
                  Double(s.matched) >= settings.chanceMatchMultiple * chance
            else { continue }
            let current = bestPerPhase[entry.phaseIndex]
            if current == nil || s.score < current!.score {
                bestPerPhase[entry.phaseIndex] = (entryIndex, s.score, s.matched)
            }
        }
        guard !bestPerPhase.isEmpty else {
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

        result.verdict = .indexed
        result.phaseIndex = Int32(winner.key)
        result.entryIndex = Int32(winner.value.entryIndex)
        return result
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
        let candidates = library.candidateEntryIndices
        guard !candidates.isEmpty else { return nil }

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
                        directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom
                    )
                    ptr.value[position] = classify(
                        vectors: vectors, library: library, settings: settings,
                        matrixEntry: matrixEntry, candidateEntryIndices: candidates,
                        scratch: scratch
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
