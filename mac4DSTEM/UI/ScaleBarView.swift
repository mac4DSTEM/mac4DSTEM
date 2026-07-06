//
//  ScaleBarView.swift
//  Role: Calibrated scale bar overlay for the image panes. Picks a "nice"
//        1-2-5 length near a target on-screen size, so it re-quantizes as the
//        user zooms. Falls back to pixel units when no calibration exists —
//        an uncalibrated bar labelled "px" is still honest and useful.
//

import SwiftUI

struct ScaleBarView: View {
    /// Physical units per screen POINT at the current zoom
    /// (= pixelSize * imagePixels / (fittedWidthPoints * zoom)).
    let unitsPerPoint: Double
    /// Unit label ("nm", "1/nm", "px", …).
    let unitLabel: String

    private static let targetPoints = 70.0

    var body: some View {
        if unitsPerPoint > 0, unitsPerPoint.isFinite {
            let nice = Self.nice125(unitsPerPoint * Self.targetPoints)
            let lengthPt = CGFloat(nice / unitsPerPoint)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Self.format(nice)) \(unitLabel)")
                Rectangle()
                    .frame(width: lengthPt, height: 2)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
        }
    }

    /// Round to the nearest 1 / 2 / 5 × 10ⁿ.
    static func nice125(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let exponent = floor(log10(value))
        let base = pow(10, exponent)
        let mantissa = value / base
        let nice: Double = mantissa < 1.5 ? 1 : (mantissa < 3.5 ? 2 : (mantissa < 7.5 ? 5 : 10))
        return nice * base
    }

    static func format(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%g", value) }
        return String(format: "%.3g", value)
    }
}
