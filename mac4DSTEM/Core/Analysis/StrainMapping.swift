//
//  StrainMapping.swift
//  Role: Strain mapping from detected Bragg vectors (py4DSTEM: process/strain).
//        Pipeline per py4DSTEM latticevectors.py:
//
//   1. choose two reference reciprocal-lattice vectors g1, g2
//   2. index every position's Bragg peaks to integer (h, k) about the origin
//      (index_bragg_directions: M = round(β⁻¹·(g − origin)))
//   3. fit the local lattice matrix at each position by intensity-weighted
//      least squares (fit_lattice_vectors)
//   4. take the reference lattice as the component median over valid positions
//      (get_reference_g1g2)
//   5. strain per position = deviation of the local lattice from the
//      reference (get_strain_from_reference_g1g2):
//        β = (M_ref⁻¹ · M_local)ᵀ
//        e_xx = 1 − β₀₀,  e_yy = 1 − β₁₁,
//        e_xy = −(β₀₁ + β₁₀)/2,  θ = (β₀₁ − β₁₀)/2
//
//  Strain is COMPUTED and stored in diffraction-space x/y; presentation
//  (display/export) re-expresses it in the scan frame when the calibrated
//  R–Q rotation exists — see StrainFrame.swift (v2 S8). Automatic basis
//  selection is a bounded consensus fit over repeated peak-vector clusters;
//  local fits reject off-lattice peaks, and the robust reference rejects
//  distorted positions.
//

import Foundation
import CuboStrain

package enum StrainComponent: String, CaseIterable, Identifiable {
    case exx   = "ε_xx"
    case eyy   = "ε_yy"
    case exy   = "ε_xy"
    case theta = "θ (rotation)"
    case residual = "Fit residual"
    case indexed = "Indexed"
    package var id: String { rawValue }
}

// nonisolated: pure data/math (the S3-rider pattern) — presentation code in
// StrainFrame.swift derives from it off the default actor.
package nonisolated struct StrainMap {
    package let width: Int
    package let height: Int
    package let exx: [Float]
    package let eyy: [Float]
    package let exy: [Float]
    package let theta: [Float]
    package let mask: [Bool]                      // false → too few peaks to fit
    /// Per-position fitted lattice vectors and fit residuals (calibrated
    /// detector px). Retained so the local fit can be verified against the
    /// measured peaks on the diffraction pattern; zero where `mask` is false.
    package let localG1x: [Float]
    package let localG1y: [Float]
    package let localG2x: [Float]
    package let localG2y: [Float]
    package let localResidualPixels: [Float]
    package let refG1: (x: Float, y: Float)
    package let refG2: (x: Float, y: Float)
    package let referencePositionCount: Int
    package let indexedFraction: Float           // fraction of positions successfully fit
    package let diagnostics: StrainFitDiagnostics

    /// One component as a display image. Masked (unfittable) positions become
    /// NaN so they render as explicitly invalid — never as 0, which a diverging
    /// colormap would show as "zero strain".
    package func component(_ c: StrainComponent) -> FloatImage {
        let source: [Float]
        switch c {
        case .exx:   source = exx
        case .eyy:   source = eyy
        case .exy:   source = exy
        case .theta: source = theta
        case .residual: source = localResidualPixels
        case .indexed:
            return FloatImage(
                width: width, height: height,
                pixels: mask.map { $0 ? 1 : Float.nan }
            )
        }
        var out = source
        for i in 0..<out.count where !mask[i] { out[i] = .nan }
        return FloatImage(width: width, height: height, pixels: out)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(width: Int, height: Int, exx: [Float], eyy: [Float], exy: [Float], theta: [Float], mask: [Bool], localG1x: [Float], localG1y: [Float], localG2x: [Float], localG2y: [Float], localResidualPixels: [Float], refG1: (x: Float, y: Float), refG2: (x: Float, y: Float), referencePositionCount: Int, indexedFraction: Float, diagnostics: StrainFitDiagnostics) {
        self.width = width
        self.height = height
        self.exx = exx
        self.eyy = eyy
        self.exy = exy
        self.theta = theta
        self.mask = mask
        self.localG1x = localG1x
        self.localG1y = localG1y
        self.localG2x = localG2x
        self.localG2y = localG2y
        self.localResidualPixels = localResidualPixels
        self.refG1 = refG1
        self.refG2 = refG2
        self.referencePositionCount = referencePositionCount
        self.indexedFraction = indexedFraction
        self.diagnostics = diagnostics
    }
}

package nonisolated struct StrainFitDiagnostics: Sendable {
    package let automaticBasis: Bool
    package let referenceMaskApplied: Bool
    package let basisObservationCount: Int
    package let basisSupportCount: Int
    package let basisSupportFraction: Float
    package let basisResidualPixels: Float
    package let basisConditionNumber: Float
    package let indexingTolerancePixels: Float
    package let localResidualMedianPixels: Float
    package let referenceCandidateCount: Int
    package let referenceRejectedCount: Int
    /// Local fits CuboStrain refused (invalid input) and so left unindexed, and the first reason; 0 / nil when none.
    package let refusedLocalFitCount: Int
    package let firstLocalFitRefusal: String?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(automaticBasis: Bool, referenceMaskApplied: Bool, basisObservationCount: Int, basisSupportCount: Int, basisSupportFraction: Float, basisResidualPixels: Float, basisConditionNumber: Float, indexingTolerancePixels: Float, localResidualMedianPixels: Float, referenceCandidateCount: Int, referenceRejectedCount: Int, refusedLocalFitCount: Int = 0, firstLocalFitRefusal: String? = nil) {
        self.automaticBasis = automaticBasis
        self.referenceMaskApplied = referenceMaskApplied
        self.basisObservationCount = basisObservationCount
        self.basisSupportCount = basisSupportCount
        self.basisSupportFraction = basisSupportFraction
        self.basisResidualPixels = basisResidualPixels
        self.basisConditionNumber = basisConditionNumber
        self.indexingTolerancePixels = indexingTolerancePixels
        self.localResidualMedianPixels = localResidualMedianPixels
        self.referenceCandidateCount = referenceCandidateCount
        self.referenceRejectedCount = referenceRejectedCount
        self.refusedLocalFitCount = refusedLocalFitCount
        self.firstLocalFitRefusal = firstLocalFitRefusal
    }
}

/// Kit refusals met while fitting, kept so a position left unindexed (or a run with no basis) says why.
private nonisolated struct RefusalLog {
    var count = 0
    var first: String?
    mutating func note(_ error: Error, _ what: String) {
        count += 1
        if first == nil { first = "\(what): \(error.localizedDescription)" }
    }
}

package nonisolated enum StrainMapping {

    private struct BasisEstimate {
        package let g1: (x: Float, y: Float)
        package let g2: (x: Float, y: Float)
        package let observationCount: Int
        package let supportCount: Int
        package let residualPixels: Float
        package let conditionNumber: Float
        package let indexingTolerancePixels: Float
    }

    /// Full strain-map computation from a set of Bragg vectors and a diffraction
    /// origin. Returns nil if a lattice basis can't be established.
    package nonisolated static func compute(bragg: BraggVectors,
                                    originX: Float, originY: Float,
                                    minNumPeaks: Int = 5,
                                    referenceMask: [Bool]? = nil,
                                    initialBasis: (g1: (x: Float, y: Float),
                                                   g2: (x: Float, y: Float))? = nil,
                                    cancellation: AnalysisCancellationToken? = nil,
                                    onRefusal: ((String) -> Void)? = nil) -> StrainMap? {
        guard cancellation?.isCancelled != true else { return nil }
        var refusals = RefusalLog()
        let w = bragg.scanWidth, h = bragg.scanHeight
        let n = w * h
        guard referenceMask == nil || referenceMask?.count == n else { return nil }

        let basisEstimate: BasisEstimate?
        let automaticBasis = initialBasis == nil
        if let initialBasis {
            guard let condition = conditionNumber(
                g1: initialBasis.g1, g2: initialBasis.g2
            ), condition <= 8 else { return nil }
            let observations = vectorObservations(
                bragg: bragg, x0: originX, y0: originY,
                minRadius: 0, cancellation: cancellation
            )
            let tolerance = indexingTolerance(g1: initialBasis.g1, g2: initialBasis.g2)
            let score = scoreBasis(
                g1: initialBasis.g1, g2: initialBasis.g2,
                observations: observations, tolerance: tolerance
            )
            basisEstimate = BasisEstimate(
                g1: initialBasis.g1, g2: initialBasis.g2,
                observationCount: observations.count,
                supportCount: score.support,
                residualPixels: score.residual,
                conditionNumber: condition,
                indexingTolerancePixels: tolerance
            )
        } else {
            basisEstimate = estimateLatticeBasis(
                bragg: bragg, x0: originX, y0: originY, cancellation: cancellation, onRefusal: onRefusal
            )
        }
        guard let basisEstimate else { return nil }
        let g1 = basisEstimate.g1
        let g2 = basisEstimate.g2

        // Per-position local lattice vectors, from indexing + weighted fit.
        var lg1x = [Float](repeating: 0, count: n)
        var lg1y = [Float](repeating: 0, count: n)
        var lg2x = [Float](repeating: 0, count: n)
        var lg2y = [Float](repeating: 0, count: n)
        var mask = [Bool](repeating: false, count: n)
        var localResiduals = [Float](repeating: 0, count: n)

        // β for indexing: columns are g1, g2. index = β⁻¹ · (peak − origin).
        guard let betaInv = invert2x2(g1.x, g2.x, g1.y, g2.y) else { return nil }

        for idx in 0..<n {
            if cancellation?.isCancelled == true { return nil }
            let peaks = bragg.peaks[idx]
            if peaks.count < minNumPeaks { continue }

            // Index and accumulate the weighted normal equations for the fit
            // of [x0, y0, g1, g2] (basis rows [1, h, k]).
            var hks = [(h: Float, k: Float, x: Float, y: Float, wgt: Float)]()
            hks.reserveCapacity(peaks.count)
            for p in peaks {
                let vx = p.x - originX, vy = p.y - originY
                let hf = betaInv.a * vx + betaInv.b * vy
                let kf = betaInv.c * vx + betaInv.d * vy
                let hIndex = hf.rounded(), kIndex = kf.rounded()
                let predictedX = hIndex * g1.x + kIndex * g2.x
                let predictedY = hIndex * g1.y + kIndex * g2.y
                let residual = hypot(vx - predictedX, vy - predictedY)
                if residual <= basisEstimate.indexingTolerancePixels,
                   abs(hIndex) <= 8, abs(kIndex) <= 8 {
                    hks.append((h: hIndex, k: kIndex,
                                x: vx, y: vy,
                                wgt: max(p.intensity, 1e-6)))
                }
            }
            guard hks.count >= minNumPeaks,
                  let fit = robustFitLattice(hks, minNumPeaks: minNumPeaks, refusals: &refusals) else { continue }
            lg1x[idx] = fit.g1x; lg1y[idx] = fit.g1y
            lg2x[idx] = fit.g2x; lg2y[idx] = fit.g2y
            localResiduals[idx] = fit.residual
            mask[idx] = true
        }

        // Reference lattice = component median over robust inliers in the optional
        // user-selected unstrained region (whole scan when absent).
        let referenceCandidates = (0..<n).filter {
            mask[$0] && (referenceMask?[$0] ?? true)
        }
        guard !referenceCandidates.isEmpty else { return nil }
        let referenceInliers = robustReferenceIndices(
            candidates: referenceCandidates,
            g1x: lg1x, g1y: lg1y, g2x: lg2x, g2y: lg2y
        )
        guard !referenceInliers.isEmpty else { return nil }
        // The reference lattice is CuboStrain's `referenceMAD` over the candidates (the same MAD rejection and component
        // median, Float32); `robustReferenceIndices` stays for the inlier count the diagnostics report.
        // delete at CuboKit 0.5: referenceMAD returns the basis only (ask: also the inlier count or indices).
        let candidateBases = referenceCandidates.map {
            LatticeBasis(g1: LatticeVector(row: Double(lg1x[$0]), column: Double(lg1y[$0])),
                         g2: LatticeVector(row: Double(lg2x[$0]), column: Double(lg2y[$0])))
        }
        guard cancellation?.isCancelled != true else { return nil }
        let reference: LatticeBasis
        do { reference = try LatticeStrain.referenceMAD(candidateBases) }
        catch { onRefusal?("reference lattice: \(error.localizedDescription)"); return nil }
        let refG1 = (x: Float(reference.g1.row), y: Float(reference.g1.column))
        let refG2 = (x: Float(reference.g2.row), y: Float(reference.g2.column))
        let valid = referenceInliers.count

        // Strain per position vs reference.
        var exx = [Float](repeating: 0, count: n)
        var eyy = [Float](repeating: 0, count: n)
        var exy = [Float](repeating: 0, count: n)
        var theta = [Float](repeating: 0, count: n)
        // M_ref rows are the reference g1, g2.
        guard let mRefInv = invert2x2(refG1.x, refG1.y, refG2.x, refG2.y) else { return nil }

        for idx in 0..<n where mask[idx] {
            if cancellation?.isCancelled == true { return nil }
            // X = M_ref⁻¹ · M_local ; β = Xᵀ.  M_local rows = local g1, g2.
            let m00 = lg1x[idx], m01 = lg1y[idx]
            let m10 = lg2x[idx], m11 = lg2y[idx]
            let x00 = mRefInv.a * m00 + mRefInv.b * m10
            let x01 = mRefInv.a * m01 + mRefInv.b * m11
            let x10 = mRefInv.c * m00 + mRefInv.d * m10
            let x11 = mRefInv.c * m01 + mRefInv.d * m11
            // β = Xᵀ
            let b00 = x00, b01 = x10, b10 = x01, b11 = x11
            exx[idx]   = 1 - b00
            eyy[idx]   = 1 - b11
            exy[idx]   = -(b01 + b10) / 2
            theta[idx] = (b01 - b10) / 2
        }

        let validLocalResiduals = localResiduals.enumerated().compactMap {
            mask[$0.offset] ? $0.element : nil
        }
        let diagnostics = StrainFitDiagnostics(
            automaticBasis: automaticBasis,
            referenceMaskApplied: referenceMask != nil,
            basisObservationCount: basisEstimate.observationCount,
            basisSupportCount: basisEstimate.supportCount,
            basisSupportFraction: basisEstimate.observationCount > 0
                ? Float(basisEstimate.supportCount) / Float(basisEstimate.observationCount) : 0,
            basisResidualPixels: basisEstimate.residualPixels,
            basisConditionNumber: basisEstimate.conditionNumber,
            indexingTolerancePixels: basisEstimate.indexingTolerancePixels,
            localResidualMedianPixels: median(validLocalResiduals) ?? 0,
            referenceCandidateCount: referenceCandidates.count,
            referenceRejectedCount: referenceCandidates.count - valid,
            refusedLocalFitCount: refusals.count,
            firstLocalFitRefusal: refusals.first
        )
        return StrainMap(width: w, height: h,
                         exx: exx, eyy: eyy, exy: exy, theta: theta, mask: mask,
                         localG1x: lg1x, localG1y: lg1y,
                         localG2x: lg2x, localG2y: lg2y,
                         localResidualPixels: localResiduals,
                         refG1: refG1, refG2: refG2,
                         referencePositionCount: valid,
                         indexedFraction: Float(mask.filter { $0 }.count) / Float(n),
                         diagnostics: diagnostics)
    }

    // MARK: - Lattice-vector selection

    private struct VectorObservation {
        package let x: Float
        package let y: Float
        package let radius: Float
    }

    /// Compatibility entry point for callers that only need the vectors. The
    /// full solver consumes `estimateLatticeBasis` so it can retain confidence
    /// and residual diagnostics.
    package nonisolated static func chooseLatticeVectors(bragg: BraggVectors,
                                                 x0: Float, y0: Float,
                                                 minRadius: Float = 2,
                                                 cancellation: AnalysisCancellationToken? = nil)
        -> (g1: (x: Float, y: Float), g2: (x: Float, y: Float))? {
        guard let estimate = estimateLatticeBasis(
            bragg: bragg, x0: x0, y0: y0,
            minRadius: minRadius, cancellation: cancellation
        ) else { return nil }
        return (estimate.g1, estimate.g2)
    }

    private nonisolated static func vectorObservations(
        bragg: BraggVectors, x0: Float, y0: Float, minRadius: Float,
        cancellation: AnalysisCancellationToken?
    ) -> [VectorObservation] {
        var observations: [VectorObservation] = []
        for positionPeaks in bragg.peaks {
            if cancellation?.isCancelled == true { return [] }
            for p in positionPeaks {
                let vx = p.x - x0, vy = p.y - y0
                let radius = hypot(vx, vy)
                if radius > minRadius, radius.isFinite {
                    observations.append(VectorObservation(x: vx, y: vy, radius: radius))
                }
            }
        }
        return observations
    }

    /// The automatic basis: CuboStrain's `LatticeStrain.chooseBasisConsensus` (clustering, bounded candidate pairs, consensus
    /// scoring; pinned to this app's original Float32 source) chooses g1 and g2; the diagnostics that came with the old inline
    /// search (observations, support, residual, condition, tolerance) are re-derived here from the chosen pair, with the same
    /// functions the `initialBasis` path uses.
    // delete at CuboKit 0.5: chooseBasisConsensus takes no cancellation token and returns the basis only (ask: a cancellation
    // closure and the support/residual/condition it computed, so these diagnostics need no second scoring pass).
    private nonisolated static func estimateLatticeBasis(
        bragg: BraggVectors, x0: Float, y0: Float, minRadius: Float = 2,
        cancellation: AnalysisCancellationToken?, onRefusal: ((String) -> Void)? = nil
    ) -> BasisEstimate? {
        let observations = vectorObservations(
            bragg: bragg, x0: x0, y0: y0,
            minRadius: minRadius, cancellation: cancellation
        )
        guard cancellation?.isCancelled != true, observations.count >= 2 else { return nil }
        // Non-finite coordinates were ignored by the inline search (a NaN radius is never above minRadius); the kit rejects
        // them as invalid input, so they are dropped here. Intensity is not used by the selection; the kit wants it >= 0.
        let positions = bragg.peaks.map { peaks in
            peaks.compactMap { p -> LatticePeak? in
                guard p.x.isFinite, p.y.isFinite else { return nil }
                return LatticePeak(row: Double(p.x), column: Double(p.y),
                                   intensity: p.intensity.isFinite ? max(Double(p.intensity), 0) : 0)
            }
        }
        let chosen: LatticeBasis?
        do {
            chosen = try LatticeStrain.chooseBasisConsensus(
                positions, origin: LatticeVector(row: Double(x0), column: Double(y0)),
                minimumRadius: Double(minRadius))
        } catch { onRefusal?("lattice basis: \(error.localizedDescription)"); return nil }
        guard let basis = chosen, cancellation?.isCancelled != true else { return nil }
        let g1 = (x: Float(basis.g1.row), y: Float(basis.g1.column))
        let g2 = (x: Float(basis.g2.row), y: Float(basis.g2.column))
        guard let condition = conditionNumber(g1: g1, g2: g2) else { return nil }
        let tolerance = indexingTolerance(g1: g1, g2: g2)
        let score = scoreBasis(g1: g1, g2: g2, observations: observations, tolerance: tolerance)
        return BasisEstimate(
            g1: g1, g2: g2,
            observationCount: observations.count,
            supportCount: score.support,
            residualPixels: score.residual,
            conditionNumber: condition,
            indexingTolerancePixels: tolerance
        )
    }

    private nonisolated static func scoreBasis(
        g1: (x: Float, y: Float), g2: (x: Float, y: Float),
        observations: [VectorObservation], tolerance: Float
    ) -> (support: Int, residual: Float) {
        guard let inverse = invert2x2(g1.x, g2.x, g1.y, g2.y) else {
            return (0, .infinity)
        }
        var support = 0
        var squaredResidual: Double = 0
        for observation in observations {
            let h = (inverse.a * observation.x + inverse.b * observation.y).rounded()
            let k = (inverse.c * observation.x + inverse.d * observation.y).rounded()
            guard abs(h) <= 8, abs(k) <= 8, h != 0 || k != 0 else { continue }
            let residual = hypot(
                observation.x - h * g1.x - k * g2.x,
                observation.y - h * g1.y - k * g2.y
            )
            if residual <= tolerance {
                support += 1
                squaredResidual += Double(residual * residual)
            }
        }
        return (
            support,
            support > 0 ? Float(sqrt(squaredResidual / Double(support))) : .infinity
        )
    }

    private nonisolated static func indexingTolerance(
        g1: (x: Float, y: Float), g2: (x: Float, y: Float)
    ) -> Float {
        max(0.5, 0.18 * min(hypot(g1.x, g1.y), hypot(g2.x, g2.y)))
    }

    private nonisolated static func conditionNumber(
        g1: (x: Float, y: Float), g2: (x: Float, y: Float)
    ) -> Float? {
        let trace = g1.x * g1.x + g1.y * g1.y + g2.x * g2.x + g2.y * g2.y
        let determinant = g1.x * g2.y - g2.x * g1.y
        let discriminant = max(0, trace * trace - 4 * determinant * determinant)
        let root = sqrt(discriminant)
        let maximum = (trace + root) / 2
        let minimum = (trace - root) / 2
        guard minimum > 1e-10, maximum.isFinite else { return nil }
        return sqrt(maximum / minimum)
    }

    // MARK: - Weighted lattice fit (fit_lattice_vectors)

    /// Intensity-weighted fit of [origin, g1, g2] to indexed peaks: CuboStrain's `LatticeStrain.fitIntensityOnce` (the
    /// intensity-once normal equations of this app's original source; Float32 vectors, RMS residual). The weighting
    /// DEVIATION from py4DSTEM (Σ w·r², not Σ w²·r²; measured 2026-08-04) is the kit option's, documented there.
    private nonisolated static func fitLattice(
        _ peaks: [(h: Float, k: Float, x: Float, y: Float, wgt: Float)], refusals: inout RefusalLog
    ) -> (originX: Float, originY: Float,
          g1x: Float, g1y: Float, g2x: Float, g2y: Float,
          residual: Float)? {
        // The fit depends on the weights only through their ratios, so they are divided by the largest when it exceeds 1: a
        // hot peak of 1e10 or more would otherwise trip the kit's representability guard and unindex the position.
        let top = peaks.reduce(Float(0)) { max($0, $1.wgt) }
        let scale = top > 1 ? 1 / Double(top) : 1
        let lattice = peaks.map {
            LatticePeak(row: Double($0.x), column: Double($0.y), intensity: Double($0.wgt) * scale,
                        h: Double($0.h), k: Double($0.k))
        }
        let result: LatticeFit?
        do { result = try LatticeStrain.fitIntensityOnce(lattice) }
        catch { refusals.note(error, "local lattice fit"); return nil }
        guard let fit = result else { return nil }
        return (originX: Float(fit.origin.row), originY: Float(fit.origin.column),
                g1x: Float(fit.basis.g1.row), g1y: Float(fit.basis.g1.column),
                g2x: Float(fit.basis.g2.row), g2y: Float(fit.basis.g2.column),
                residual: Float(fit.residual))
    }

    /// One reweighted pass removes a peak that happened to fall inside the
    /// coarse indexing gate but is inconsistent with the local lattice fit.
    private nonisolated static func robustFitLattice(
        _ peaks: [(h: Float, k: Float, x: Float, y: Float, wgt: Float)],
        minNumPeaks: Int, refusals: inout RefusalLog
    ) -> (originX: Float, originY: Float,
          g1x: Float, g1y: Float, g2x: Float, g2y: Float,
          residual: Float)? {
        guard let initial = fitLattice(peaks, refusals: &refusals) else { return nil }
        let residuals = peaks.map { peak in
            hypot(
                peak.x - initial.originX - peak.h * initial.g1x - peak.k * initial.g2x,
                peak.y - initial.originY - peak.h * initial.g1y - peak.k * initial.g2y
            )
        }
        guard let center = median(residuals) else { return initial }
        let deviations = residuals.map { abs($0 - center) }
        let mad = median(deviations) ?? 0
        let threshold = max(0.35, center + 3 * max(1.4826 * mad, 0.05))
        let inliers = zip(peaks, residuals).compactMap { peak, residual in
            residual <= threshold ? peak : nil
        }
        guard inliers.count >= minNumPeaks, inliers.count < peaks.count else { return initial }
        return fitLattice(inliers, refusals: &refusals) ?? initial
    }

    /// DEVIATION from py4DSTEM: `get_reference_g1g2` (process/strain/latticevectors.py)
    /// takes the plain component-wise median of every position inside the caller's
    /// mask. This is called first, and discards candidates whose fitted (g1, g2)
    /// deviate from that median by more than a MAD-derived threshold (falling back
    /// to the full candidate set when fewer than half of the candidates survive) —
    /// the robust reference rejects distorted positions, per this file's own header
    /// above, so a strained or mis-indexed sub-region inside the reference mask
    /// cannot pull the reference lattice off the bulk.
    private nonisolated static func robustReferenceIndices(
        candidates: [Int],
        g1x: [Float], g1y: [Float], g2x: [Float], g2y: [Float]
    ) -> [Int] {
        guard candidates.count > 2 else { return candidates }
        let centerG1X = median(candidates.map { g1x[$0] }) ?? 0
        let centerG1Y = median(candidates.map { g1y[$0] }) ?? 0
        let centerG2X = median(candidates.map { g2x[$0] }) ?? 0
        let centerG2Y = median(candidates.map { g2y[$0] }) ?? 0
        let residuals = candidates.map { index in
            hypot(g1x[index] - centerG1X, g1y[index] - centerG1Y)
                + hypot(g2x[index] - centerG2X, g2y[index] - centerG2Y)
        }
        let center = median(residuals) ?? 0
        let mad = median(residuals.map { abs($0 - center) }) ?? 0
        let basisScale = (
            hypot(centerG1X, centerG1Y) + hypot(centerG2X, centerG2Y)
        ) / 2
        let threshold = center + max(3 * 1.4826 * mad, 0.02 * basisScale)
        let inliers = zip(candidates, residuals).compactMap { index, residual in
            residual <= threshold ? index : nil
        }
        // Do not let aggressive rejection turn a broad but valid reference
        // population into a tiny, overconfident subset.
        return inliers.count * 2 >= candidates.count ? inliers : candidates
    }

    // MARK: - Linear algebra helpers

    private nonisolated static func invert2x2(_ a: Float, _ b: Float, _ c: Float, _ d: Float)
        -> (a: Float, b: Float, c: Float, d: Float)? {
        // Inverse of [[a, b], [c, d]].
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return nil }
        let inv = 1 / det
        return (a: d * inv, b: -b * inv, c: -c * inv, d: a * inv)
    }

    private nonisolated static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
