//
//  QCalibration.swift
//  Role: Robust first-shell reciprocal-pixel calibration from detected Bragg
//        vectors and a known crystal reflection radius.
//

import Foundation

nonisolated struct QCalibrationEstimate: Sendable {
    let invAngstromPerPixel: Double
    let observedRadiusPixels: Double
    let referenceRadiusInvAngstrom: Double
    let medianAbsoluteDeviationPixels: Double
    let sampleCount: Int
}

nonisolated enum KnownCrystalQCalibration {
    /// Estimate Q scale from the median innermost non-central reflection at
    /// each scan position. The per-position statistic avoids dense patterns
    /// dominating the fit; median/MAD make isolated detection failures benign.
    static func estimate(
        bragg: BraggVectors,
        origin: (x: Float, y: Float),
        referenceRadiusInvAngstrom: Double,
        minimumRadiusPixels: Float = 2
    ) -> QCalibrationEstimate? {
        guard referenceRadiusInvAngstrom.isFinite,
              referenceRadiusInvAngstrom > 0 else { return nil }
        var firstRadii: [Double] = []
        firstRadii.reserveCapacity(bragg.peaks.count)
        for peaks in bragg.peaks {
            let radii = peaks.compactMap { peak -> Double? in
                let dx = peak.x - origin.x
                let dy = peak.y - origin.y
                let radius = (dx * dx + dy * dy).squareRoot()
                return radius.isFinite && radius > minimumRadiusPixels ? Double(radius) : nil
            }
            if let first = radii.min() { firstRadii.append(first) }
        }
        guard !firstRadii.isEmpty else { return nil }
        let observed = median(firstRadii)
        guard observed.isFinite, observed > 0 else { return nil }
        let mad = median(firstRadii.map { abs($0 - observed) })
        return QCalibrationEstimate(
            invAngstromPerPixel: referenceRadiusInvAngstrom / observed,
            observedRadiusPixels: observed,
            referenceRadiusInvAngstrom: referenceRadiusInvAngstrom,
            medianAbsoluteDeviationPixels: mad,
            sampleCount: firstRadii.count
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
