//
//  ProbeRingHint.swift
//  Role: the outer edge of a RING-STRUCTURED probe (a bullseye), read from the
//        scan's mean pattern — the number the Bragg Disks room offers as a
//        one-click probe radius. Pure; nothing here sets a default (owner,
//        2026-10-01, card "Kernel", option c).
//
//  The rules are S21's (../_archive/mac4DSTEM/docs/archive/v4/s21-detection-defaults-proposal-
//  2026-09-30.patch, results ...-results-2026-09-30.md), returned with the dip
//  value it already computed. `probeSize` reads such a probe at its first
//  shoulder (bullseye: 6.84 px where the ring ends at 11); the trench kernel
//  built at that radius never finds the beam (recall 0.12 against 0.78 at 11).
//  The 20 % edge and the 0.25 dip are properties of the eleven files they were
//  measured on, not of the method — hence a hint the reader may decline, not a
//  default.
//

import CuboBragg
import CuboVirtual
import Foundation

package nonisolated enum ProbeRingHint {

    package nonisolated struct Result: Equatable, Sendable {
        /// Outer edge of the ring structure, detector pixels (integer bin).
        package let outerRadius: Float
        /// Profile minimum before the last ring maximum / profile maximum.
        package let dip: Float
    }

    /// The hint is worth showing only when the radius in use is not already
    /// within half a pixel of the edge. Since 2026-10-20 the radius in use is measured on the MAX pattern
    /// (`OriginCalibration.ProbeRadiusSource.maxPattern`), usually larger than the mean pattern's, so the offer
    /// threshold compares against a max-based radius and appears less often than it did.
    package nonisolated static func isWorthOffering(_ hint: Result, current: Float) -> Bool {
        abs(hint.outerRadius - current) >= 0.5
    }

    /// The outer edge of a ring-structured probe, read from the scan's mean pattern: CuboKit's
    /// `CuboBragg.ProbeRingHint.outerEdge(of:)` (the app's code of 2026-10-01, moved into the kit unchanged in its
    /// rules: the 20 % edge, the 0.25 dip, the `min(qx, qy) / 8` guard, a probe size on the pattern with non-finite
    /// pixels as 0). The kit returns the radius as an `Int` bin and the dip in Double; the app's `Result` is Float,
    /// converted exactly (an integer below 2^24, a dip narrowed to Float).
    package nonisolated static func outerEdge(meanDP dp: [Float], qy: Int, qx: Int) -> Result? {
        guard dp.count == qy * qx, qy > 0, qx > 0 else { return nil }
        let pattern = DetectorImage(detectorRows: qy, detectorColumns: qx, values: dp.map(Double.init), path: .cpu)
        guard let hint = CuboBragg.ProbeRingHint.outerEdge(of: pattern) else { return nil }
        return Result(outerRadius: Float(hint.outerRadius), dip: Float(hint.dip))
    }
}
