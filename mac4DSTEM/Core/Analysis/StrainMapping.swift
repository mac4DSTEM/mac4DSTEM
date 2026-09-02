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
    package init(width: Int, height: Int, exx: [Float], eyy: [Float], exy: [Float], theta: [Float], mask: [Bool], localG1x: [Float], localG1y: [Float], localG2x: [Float], localG2y: [Float], localResidualPixels: [Float], refG1: (x: Float, y: Float), refG2: (x: Float, y: Float), referencePositionCount: Int, indexedFraction: Float, diagnostics: StrainFitDiagnostics) {
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

package struct StrainFitDiagnostics: Sendable {
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(automaticBasis: Bool, referenceMaskApplied: Bool, basisObservationCount: Int, basisSupportCount: Int, basisSupportFraction: Float, basisResidualPixels: Float, basisConditionNumber: Float, indexingTolerancePixels: Float, localResidualMedianPixels: Float, referenceCandidateCount: Int, referenceRejectedCount: Int) {
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
                                    cancellation: AnalysisCancellationToken? = nil) -> StrainMap? {
        guard cancellation?.isCancelled != true else { return nil }
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
                bragg: bragg, x0: originX, y0: originY, cancellation: cancellation
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
                  let fit = robustFitLattice(hks, minNumPeaks: minNumPeaks) else { continue }
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
        guard cancellation?.isCancelled != true,
              let refG1X = median(referenceInliers.map { lg1x[$0] }),
              let refG1Y = median(referenceInliers.map { lg1y[$0] }),
              let refG2X = median(referenceInliers.map { lg2x[$0] }),
              let refG2Y = median(referenceInliers.map { lg2y[$0] }) else { return nil }
        let refG1 = (x: refG1X, y: refG1Y)
        let refG2 = (x: refG2X, y: refG2Y)
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
            referenceRejectedCount: referenceCandidates.count - valid
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

    private struct VectorCluster {
        package var sumX: Float
        package var sumY: Float
        package var count: Int

        package var x: Float { sumX / Float(count) }
        package var y: Float { sumY / Float(count) }
        package var radius: Float { hypot(x, y) }
    }

    private struct VectorCell: Hashable {
        package let x: Int
        package let y: Int
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

    /// Cluster repeated peak vectors, test bounded candidate pairs, and choose
    /// the well-conditioned basis explaining the largest observation consensus.
    private nonisolated static func estimateLatticeBasis(
        bragg: BraggVectors, x0: Float, y0: Float, minRadius: Float = 2,
        cancellation: AnalysisCancellationToken?
    ) -> BasisEstimate? {
        let observations = vectorObservations(
            bragg: bragg, x0: x0, y0: y0,
            minRadius: minRadius, cancellation: cancellation
        )
        guard cancellation?.isCancelled != true, observations.count >= 2 else { return nil }

        // A typical first-shell scale from each position's nearest non-central
        // peak makes clustering insensitive to a handful of globally short
        // false detections.
        var nearestRadii: [Float] = []
        for peaks in bragg.peaks {
            var nearest = Float.greatestFiniteMagnitude
            for peak in peaks {
                let radius = hypot(peak.x - x0, peak.y - y0)
                if radius > minRadius { nearest = min(nearest, radius) }
            }
            if nearest.isFinite { nearestRadii.append(nearest) }
        }
        guard let typicalRadius = median(nearestRadii) else { return nil }
        let clusterTolerance = max(0.5, typicalRadius * 0.18)

        func cell(x: Float, y: Float) -> VectorCell {
            VectorCell(
                x: Int(floor(Double(x / clusterTolerance))),
                y: Int(floor(Double(y / clusterTolerance)))
            )
        }

        // A spatial hash keeps this pass near-linear even when a noisy dataset
        // contains many unique outliers. Cluster centers can drift across cell
        // boundaries, so their bucket membership is updated after every merge.
        var clusters: [VectorCluster] = []
        var clusterCells: [VectorCell] = []
        var buckets: [VectorCell: [Int]] = [:]
        for observation in observations.sorted(by: { $0.radius < $1.radius }) {
            var nearestIndex: Int?
            var nearestDistance = clusterTolerance
            let observationCell = cell(x: observation.x, y: observation.y)
            for cellY in (observationCell.y - 1)...(observationCell.y + 1) {
                for cellX in (observationCell.x - 1)...(observationCell.x + 1) {
                    for index in buckets[VectorCell(x: cellX, y: cellY)] ?? [] {
                        let distance = hypot(observation.x - clusters[index].x,
                                             observation.y - clusters[index].y)
                        if distance < nearestDistance {
                            nearestDistance = distance
                            nearestIndex = index
                        }
                    }
                }
            }
            if let nearestIndex {
                let oldCell = clusterCells[nearestIndex]
                clusters[nearestIndex].sumX += observation.x
                clusters[nearestIndex].sumY += observation.y
                clusters[nearestIndex].count += 1
                let newCell = cell(
                    x: clusters[nearestIndex].x, y: clusters[nearestIndex].y
                )
                if newCell != oldCell {
                    buckets[oldCell]?.removeAll { $0 == nearestIndex }
                    if buckets[oldCell]?.isEmpty == true { buckets[oldCell] = nil }
                    buckets[newCell, default: []].append(nearestIndex)
                    clusterCells[nearestIndex] = newCell
                }
            } else {
                let index = clusters.count
                clusters.append(VectorCluster(
                    sumX: observation.x, sumY: observation.y, count: 1
                ))
                clusterCells.append(observationCell)
                buckets[observationCell, default: []].append(index)
            }
        }

        let occupiedPositions = max(1, bragg.peaks.filter { !$0.isEmpty }.count)
        let minimumClusterSupport = max(1, Int(ceil(Double(occupiedPositions) * 0.08)))
        let candidates = clusters
            .filter { $0.count >= minimumClusterSupport && $0.radius > minRadius }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.radius < $1.radius
            }
            .prefix(24)

        // MAC4DSTEM_STRAIN_DEBUG: the #18 instrumented diff (v2 S8). Print-only
        // — the search itself is untouched. Dumps the clustering inputs, every
        // candidate, and the best-supported pairs whether or not they pass the
        // gates, so a run that returns nil says WHICH gate the nearest miss
        // died on instead of only "no basis".
        let debug = ProcessInfo.processInfo.environment["MAC4DSTEM_STRAIN_DEBUG"] != nil
        func debugPrint(_ line: String) {
            // stderr, deliberately: the campaign harness pipes stdout into
            // report.json, and a diagnostic that corrupts the report would be
            // a gate widened by instrumentation.
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        var debugPairs: [(g1: (x: Float, y: Float), g2: (x: Float, y: Float),
                          condition: Float, support: Int, residual: Float)] = []
        var debugConditionRejected = 0
        if debug {
            debugPrint(String(format: "STRAIN_DEBUG origin=(%.3f, %.3f) minRadius=%.2f", x0, y0, minRadius))
            debugPrint(String(format: "STRAIN_DEBUG observations=%d occupied=%d "
                         + "typicalRadius=%.3f clusterTolerance=%.3f clusters=%d "
                         + "minClusterSupport=%d candidates=%d",
                         observations.count, occupiedPositions, typicalRadius,
                         clusterTolerance, clusters.count, minimumClusterSupport,
                         candidates.count))
            let radii = observations.map(\.radius).sorted()
            if !radii.isEmpty {
                func q(_ f: Double) -> Float { radii[min(radii.count - 1, Int(Double(radii.count) * f))] }
                debugPrint(String(format: "STRAIN_DEBUG obsRadius q05=%.2f q25=%.2f q50=%.2f q75=%.2f q95=%.2f",
                             q(0.05), q(0.25), q(0.50), q(0.75), q(0.95)))
            }
            let nearest = nearestRadii.sorted()
            if !nearest.isEmpty {
                func qn(_ f: Double) -> Float { nearest[min(nearest.count - 1, Int(Double(nearest.count) * f))] }
                debugPrint(String(format: "STRAIN_DEBUG nearestRadius q05=%.2f q25=%.2f q50=%.2f q75=%.2f q95=%.2f",
                             qn(0.05), qn(0.25), qn(0.50), qn(0.75), qn(0.95)))
            }
            for (i, c) in clusters.sorted(by: { $0.count > $1.count }).prefix(12).enumerated() {
                debugPrint(String(format: "STRAIN_DEBUG cluster[%d] (%.3f, %.3f) r=%.3f count=%d",
                             i, c.x, c.y, c.radius, c.count))
            }
            for (i, c) in candidates.enumerated() {
                debugPrint(String(format: "STRAIN_DEBUG candidate[%d] (%.3f, %.3f) r=%.3f count=%d",
                             i, c.x, c.y, c.radius, c.count))
            }
        }
        guard candidates.count >= 2 else { return nil }

        var best: BasisEstimate?
        for first in candidates.indices {
            for second in candidates.indices where second > first {
                if cancellation?.isCancelled == true { return nil }
                let g1 = (x: candidates[first].x, y: candidates[first].y)
                let g2 = (x: candidates[second].x, y: candidates[second].y)
                guard let condition = conditionNumber(g1: g1, g2: g2), condition <= 8 else {
                    debugConditionRejected += 1
                    continue
                }
                let tolerance = indexingTolerance(g1: g1, g2: g2)
                let score = scoreBasis(
                    g1: g1, g2: g2,
                    observations: observations, tolerance: tolerance
                )
                if debug {
                    debugPairs.append((g1: g1, g2: g2, condition: condition,
                                       support: score.support, residual: score.residual))
                }
                guard score.support >= 2,
                      Float(score.support) / Float(observations.count) >= 0.5 else { continue }
                let estimate = BasisEstimate(
                    g1: g1, g2: g2,
                    observationCount: observations.count,
                    supportCount: score.support,
                    residualPixels: score.residual,
                    conditionNumber: condition,
                    indexingTolerancePixels: tolerance
                )
                guard let current = best else { best = estimate; continue }
                let supportGain = estimate.supportCount - current.supportCount
                if supportGain > 0
                    || (supportGain == 0 && estimate.residualPixels < current.residualPixels - 1e-5)
                    || (supportGain == 0
                        && abs(estimate.residualPixels - current.residualPixels) <= 1e-5
                        && hypot(estimate.g1.x, estimate.g1.y)
                            + hypot(estimate.g2.x, estimate.g2.y)
                            < hypot(current.g1.x, current.g1.y)
                                + hypot(current.g2.x, current.g2.y)) {
                    best = estimate
                }
            }
        }
        if debug {
            debugPrint("STRAIN_DEBUG conditionRejectedPairs=\(debugConditionRejected)")
            let total = Float(max(1, observations.count))
            for pair in debugPairs.sorted(by: { $0.support > $1.support }).prefix(12) {
                debugPrint(String(
                    format: "STRAIN_DEBUG pair g1=(%.3f, %.3f) g2=(%.3f, %.3f) "
                        + "κ=%.2f support=%d (%.1f%%) rms=%.3f px%@",
                    pair.g1.x, pair.g1.y, pair.g2.x, pair.g2.y,
                    pair.condition, pair.support,
                    Float(pair.support) / total * 100, pair.residual,
                    Float(pair.support) / total >= 0.5 ? "" : "  [FAILS 50% support gate]"
                ))
            }
            if let best {
                debugPrint(String(format: "STRAIN_DEBUG chosen g1=(%.3f, %.3f) g2=(%.3f, %.3f) κ=%.2f",
                             best.g1.x, best.g1.y, best.g2.x, best.g2.y, best.conditionNumber))
            } else {
                debugPrint("STRAIN_DEBUG chosen NONE")
            }
        }
        return best
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

    /// Intensity-weighted least-squares fit of [origin, g1, g2] to indexed
    /// peaks. Basis row for a peak is [1, h, k]; solves the 3×3 normal
    /// equations for each of the x and y coordinates.
    ///
    /// DEVIATION (measured 2026-08-04, tools/training-dataset-campaign parity):
    /// py4DSTEM's fit_lattice_vectors multiplies both the design matrix and
    /// the data by the intensity weight before lstsq, which minimizes
    /// Σ w²·r². These normal equations weight by w once, minimizing Σ w·r² —
    /// the statistically standard weighted least squares. On sim_Au the two
    /// estimators differ by ~5e-3 median per strain component (vs ~2e-4 when
    /// the estimators are matched). The parity record reports the deviation
    /// magnitude per dataset; see parity_py4dstem.py `weighting_deviation_*`.
    private nonisolated static func fitLattice(
        _ peaks: [(h: Float, k: Float, x: Float, y: Float, wgt: Float)]
    ) -> (originX: Float, originY: Float,
          g1x: Float, g1y: Float, g2x: Float, g2y: Float,
          residual: Float)? {
        // Normal equations MᵀW M (3×3, symmetric) and MᵀW·[x, y] (3×2).
        var ata = [Double](repeating: 0, count: 9)
        var atbx = [Double](repeating: 0, count: 3)
        var atby = [Double](repeating: 0, count: 3)
        for p in peaks {
            let w = Double(p.wgt)
            let b = [1.0, Double(p.h), Double(p.k)]
            for i in 0..<3 {
                atbx[i] += w * b[i] * Double(p.x)
                atby[i] += w * b[i] * Double(p.y)
                for j in 0..<3 { ata[i * 3 + j] += w * b[i] * b[j] }
            }
        }
        guard let cx = solve3(ata, atbx), let cy = solve3(ata, atby) else { return nil }
        var squaredResidual: Double = 0
        var weightSum: Double = 0
        for peak in peaks {
            let predictedX = cx[0] + cx[1] * Double(peak.h) + cx[2] * Double(peak.k)
            let predictedY = cy[0] + cy[1] * Double(peak.h) + cy[2] * Double(peak.k)
            let dx = Double(peak.x) - predictedX
            let dy = Double(peak.y) - predictedY
            let weight = Double(peak.wgt)
            squaredResidual += weight * (dx * dx + dy * dy)
            weightSum += weight
        }
        // c[0] = origin, c[1] = g1, c[2] = g2 for each coordinate.
        return (
            originX: Float(cx[0]), originY: Float(cy[0]),
            g1x: Float(cx[1]), g1y: Float(cy[1]),
            g2x: Float(cx[2]), g2y: Float(cy[2]),
            residual: weightSum > 0 ? Float(sqrt(squaredResidual / weightSum)) : .infinity
        )
    }

    /// One reweighted pass removes a peak that happened to fall inside the
    /// coarse indexing gate but is inconsistent with the local lattice fit.
    private nonisolated static func robustFitLattice(
        _ peaks: [(h: Float, k: Float, x: Float, y: Float, wgt: Float)],
        minNumPeaks: Int
    ) -> (originX: Float, originY: Float,
          g1x: Float, g1y: Float, g2x: Float, g2y: Float,
          residual: Float)? {
        guard let initial = fitLattice(peaks) else { return nil }
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
        return fitLattice(inliers) ?? initial
    }

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

    /// Solve a 3×3 system by Gaussian elimination with partial pivoting.
    private nonisolated static func solve3(_ aIn: [Double], _ bIn: [Double]) -> [Double]? {
        var a = aIn, b = bIn
        for col in 0..<3 {
            var pivot = col
            for row in (col + 1)..<3 where abs(a[row * 3 + col]) > abs(a[pivot * 3 + col]) {
                pivot = row
            }
            if abs(a[pivot * 3 + col]) < 1e-12 { return nil }
            if pivot != col {
                for k in 0..<3 { a.swapAt(col * 3 + k, pivot * 3 + k) }
                b.swapAt(col, pivot)
            }
            for row in (col + 1)..<3 {
                let f = a[row * 3 + col] / a[col * 3 + col]
                for k in col..<3 { a[row * 3 + k] -= f * a[col * 3 + k] }
                b[row] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: 3)
        for row in stride(from: 2, through: 0, by: -1) {
            var v = b[row]
            for k in (row + 1)..<3 { v -= a[row * 3 + k] * x[k] }
            x[row] = v / a[row * 3 + row]
        }
        return x
    }
}
