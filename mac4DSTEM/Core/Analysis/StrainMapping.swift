//
//  StrainMapping.swift
//  Role: Strain mapping from detected Bragg vectors: the app's adaptation of CuboStrain's `StrainMapping.compute`
//        (py4DSTEM process/strain, latticevectors.py). The numerics are CuboKit's (0.7.0):
//
//   1. choose two reference reciprocal-lattice vectors g1, g2 (`LatticeStrain.chooseBasisConsensusResult`, or the
//      caller's manual basis, refused above condition number 8: the app's rule)
//   2. index every position's peaks to integer (h, k) about the origin, `indexing: .basisRounding`
//      (py4DSTEM index_bragg_directions: M = round(β⁻¹·(g − origin)), within the indexing tolerance, |h|,|k| <= 8)
//   3. fit the local lattice matrix by intensity-weighted least squares with one robust reweighting pass
//      (`fitMethod: .robustIntensityOnce`; DEVIATION from py4DSTEM's fit_lattice_vectors: Σ w·r², not Σ w²·r²)
//   4. take the reference lattice as the component median over the valid positions of the optional reference region,
//      after rejecting distorted candidates (`referenceMethod: .madRejection`; DEVIATION from py4DSTEM's plain median
//      in get_reference_g1g2, so a strained sub-region inside the mask cannot pull the reference off the bulk)
//   5. strain per position from the deviation of the local lattice from the reference (get_strain_from_reference_g1g2):
//        β = (M_ref⁻¹ · M_local)ᵀ
//        e_xx = 1 − β₀₀,  e_yy = 1 − β₁₁,
//        e_xy = −(β₀₁ + β₁₀)/2,  θ = (β₀₁ − β₁₀)/2
//
//  What stays here: the Float image type `StrainMap` and its diagnostics, the display components, the Bragg-vector
//  adaptation (centring, dropping non-finite peaks, intensities floored at 0), the manual-basis refusal, and the
//  cancellation token checked around the kit call (the kit's `compute` has no cancellation hook).
//
//  Strain is COMPUTED and stored in diffraction-space x/y; presentation (display/export) re-expresses it in the scan
//  frame when the calibrated R–Q rotation exists — see StrainFrame.swift (v2 S8).
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

package nonisolated enum StrainMapper {

    private struct BasisEstimate {
        let basis: LatticeBasis
        let observationCount: Int
        let supportCount: Int
        let residualPixels: Float
        let conditionNumber: Float
        let indexingTolerancePixels: Float
    }

    /// Full strain-map computation from a set of Bragg vectors and a diffraction
    /// origin. Returns nil if a lattice basis can't be established, if there is no
    /// position to take the reference from, or on cancellation.
    package nonisolated static func compute(bragg: BraggVectors,
                                    originX: Float, originY: Float,
                                    minNumPeaks: Int = 5,
                                    referenceMask: [Bool]? = nil,
                                    initialBasis: (g1: (x: Float, y: Float),
                                                   g2: (x: Float, y: Float))? = nil,
                                    cancellation: AnalysisCancellationToken? = nil,
                                    onRefusal: ((String) -> Void)? = nil) -> StrainMap? {
        guard cancellation?.isCancelled != true else { return nil }
        let w = bragg.scanWidth, h = bragg.scanHeight
        let n = w * h
        guard referenceMask == nil || referenceMask?.count == n else { return nil }

        let basisEstimate: BasisEstimate?
        let automaticBasis = initialBasis == nil
        if let initialBasis {
            let basis = LatticeBasis(
                g1: LatticeVector(row: Double(initialBasis.g1.x), column: Double(initialBasis.g1.y)),
                g2: LatticeVector(row: Double(initialBasis.g2.x), column: Double(initialBasis.g2.y)))
            // The app's rule: a given basis whose vectors are nearly parallel indexes nothing meaningful.
            guard let condition = LatticeStrain.conditionNumber(basis: basis), condition <= 8 else { return nil }
            let observations = vectorObservations(
                bragg: bragg, x0: originX, y0: originY,
                minRadius: 0, cancellation: cancellation
            )
            let tolerance = LatticeStrain.indexingTolerance(basis: basis)
            let score = LatticeStrain.scoreBasis(basis: basis, observations: observations, tolerance: tolerance)
            basisEstimate = BasisEstimate(
                basis: basis,
                observationCount: observations.count,
                supportCount: score.support,
                residualPixels: Float(score.residual),
                conditionNumber: Float(condition),
                indexingTolerancePixels: Float(tolerance)
            )
        } else {
            basisEstimate = estimateLatticeBasis(
                bragg: bragg, x0: originX, y0: originY, cancellation: cancellation, onRefusal: onRefusal
            )
        }
        guard let basisEstimate, cancellation?.isCancelled != true else { return nil }

        // Centred peaks (Float subtraction, as the detector measured them). A non-finite coordinate cannot be
        // indexed and is dropped; a negative or non-finite intensity weighs as 0 (the kit floors weights at 1e-6).
        // The fit depends on the intensities only through their ratios; `LatticeStrain.fitRobust` rescales an intensity of 1e10 or more
        // itself since CuboKit 0.9.0 (the app's own division is gone).
        let peaks: [[StrainPeak]] = bragg.peaks.map { list in
            list.compactMap { p in
                let vx = p.x - originX, vy = p.y - originY
                guard vx.isFinite, vy.isFinite else { return nil }
                return StrainPeak(row: Double(vx), column: Double(vy),
                                  intensity: p.intensity.isFinite ? max(Double(p.intensity), 0) : 0)
            }
        }
        var options = StrainMapOptions(maximumPeakSpacing: Double(basisEstimate.indexingTolerancePixels))
        options.minimumPeaks = minNumPeaks
        options.fitMethod = .robustIntensityOnce
        options.referenceMethod = .madRejection
        options.reference = referenceMask.map { .region($0) } ?? .fittedMedian
        options.indexing = .basisRounding(maximumOrder: 8)
        options.indexingTolerance = Double(basisEstimate.indexingTolerancePixels)

        let result: StrainMapResult
        do {
            // The detector size only places the Bragg-vector histogram, which the supplied directions skip.
            result = try StrainMapping.compute(
                peaks: peaks, scanRows: h, scanColumns: w, detectorRows: 1, detectorColumns: 1,
                origin: LatticeVector(row: 0, column: 0),
                directions: try StrainDirections.lattice(basis: basisEstimate.basis),
                options: options)
        } catch LatticeStrainError.emptyReference {
            return nil     // no fitted position inside the reference region
        } catch {
            onRefusal?("strain map: \(error.localizedDescription)")
            return nil
        }
        guard cancellation?.isCancelled != true else { return nil }

        func floats(_ values: [Double]) -> [Float] {
            (0..<n).map { result.valid[$0] ? Float(values[$0]) : 0 }
        }
        let mask = result.valid
        let localResiduals = floats(result.residual)
        let validLocalResiduals = (0..<n).compactMap { mask[$0] ? localResiduals[$0] : nil }
        let candidates = result.referencePositionCount
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
            referenceCandidateCount: candidates,
            referenceRejectedCount: candidates - result.referenceInlierCount,
            refusedLocalFitCount: result.refusedFitCount,
            firstLocalFitRefusal: result.firstRefusal
        )
        return StrainMap(width: w, height: h,
                         exx: floats(result.exx), eyy: floats(result.eyy), exy: floats(result.exy),
                         theta: floats(result.theta), mask: mask,
                         localG1x: floats(result.g1Row), localG1y: floats(result.g1Column),
                         localG2x: floats(result.g2Row), localG2y: floats(result.g2Column),
                         localResidualPixels: localResiduals,
                         refG1: (x: Float(result.reference.g1.row), y: Float(result.reference.g1.column)),
                         refG2: (x: Float(result.reference.g2.row), y: Float(result.reference.g2.column)),
                         referencePositionCount: result.referenceInlierCount,
                         indexedFraction: Float(mask.filter { $0 }.count) / Float(n),
                         diagnostics: diagnostics)
    }

    // MARK: - Lattice-vector selection

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
        return ((x: Float(estimate.basis.g1.row), y: Float(estimate.basis.g1.column)),
                (x: Float(estimate.basis.g2.row), y: Float(estimate.basis.g2.column)))
    }

    private nonisolated static func vectorObservations(
        bragg: BraggVectors, x0: Float, y0: Float, minRadius: Float,
        cancellation: AnalysisCancellationToken?
    ) -> [LatticeVector] {
        var observations: [LatticeVector] = []
        for positionPeaks in bragg.peaks {
            if cancellation?.isCancelled == true { return [] }
            for p in positionPeaks {
                let vx = p.x - x0, vy = p.y - y0
                let radius = hypot(vx, vy)
                if radius > minRadius, radius.isFinite {
                    observations.append(LatticeVector(row: Double(vx), column: Double(vy)))
                }
            }
        }
        return observations
    }

    /// The automatic basis: CuboStrain's `LatticeStrain.chooseBasisConsensusResult` (clustering, bounded candidate pairs,
    /// consensus scoring; pinned to this app's original Float32 source) chooses g1 and g2 and returns the observation and
    /// support counts, residual, condition number and indexing tolerance the diagnostics report. Cancellation is asked
    /// inside the kit's search (`CancellationError`).
    private nonisolated static func estimateLatticeBasis(
        bragg: BraggVectors, x0: Float, y0: Float, minRadius: Float = 2,
        cancellation: AnalysisCancellationToken?, onRefusal: ((String) -> Void)? = nil
    ) -> BasisEstimate? {
        guard cancellation?.isCancelled != true else { return nil }
        // Non-finite coordinates were ignored by the inline search (a NaN radius is never above minRadius); the kit rejects
        // them as invalid input, so they are dropped here. Intensity is not used by the selection; the kit wants it >= 0.
        let positions = bragg.peaks.map { peaks in
            peaks.compactMap { p -> LatticePeak? in
                guard p.x.isFinite, p.y.isFinite else { return nil }
                return LatticePeak(row: Double(p.x), column: Double(p.y),
                                   intensity: p.intensity.isFinite ? max(Double(p.intensity), 0) : 0)
            }
        }
        let chosen: LatticeStrain.ConsensusBasis?
        do {
            chosen = try LatticeStrain.chooseBasisConsensusResult(
                positions, origin: LatticeVector(row: Double(x0), column: Double(y0)),
                minimumRadius: Double(minRadius), isCancelled: { cancellation?.isCancelled == true })
        } catch is CancellationError { return nil
        } catch { onRefusal?("lattice basis: \(error.localizedDescription)"); return nil }
        guard let chosen, cancellation?.isCancelled != true else { return nil }
        return BasisEstimate(
            basis: chosen.basis,
            observationCount: chosen.observationCount,
            supportCount: chosen.supportCount,
            residualPixels: Float(chosen.residual),
            conditionNumber: Float(chosen.conditionNumber),
            indexingTolerancePixels: Float(chosen.indexingTolerance)
        )
    }

    // MARK: - Helpers

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
