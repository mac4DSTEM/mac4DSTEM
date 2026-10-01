//
//  ProbeRingHint.swift
//  Role: the outer edge of a RING-STRUCTURED probe (a bullseye), read from the
//        scan's mean pattern — the number the Bragg Disks room offers as a
//        one-click probe radius. Pure; nothing here sets a default (owner,
//        2026-10-01, card "Kernel", option c).
//
//  The logic is S21's (docs/archive/v4/s21-detection-defaults-proposal-
//  2026-09-30.patch, results ...-results-2026-09-30.md), returned with the dip
//  value it already computed. `probeSize` reads such a probe at its first
//  shoulder (bullseye: 6.84 px where the ring ends at 11); the trench kernel
//  built at that radius never finds the beam (recall 0.12 against 0.78 at 11).
//  The 20 % edge and the 0.25 dip are properties of the eleven files they were
//  measured on, not of the method — hence a hint the reader may decline, not a
//  default.
//

import Foundation

package nonisolated enum ProbeRingHint {

    package nonisolated struct Result: Equatable, Sendable {
        /// Outer edge of the ring structure, detector pixels (integer bin).
        package let outerRadius: Float
        /// Profile minimum before the last ring maximum / profile maximum.
        package let dip: Float
    }

    /// The hint is worth showing only when the radius in use is not already
    /// within half a pixel of the edge.
    package nonisolated static func isWorthOffering(_ hint: Result, current: Float) -> Bool {
        abs(hint.outerRadius - current) >= 0.5
    }

    /// The azimuthal mean about `probeSize`'s centre (integer-radius bins) is
    /// read outside in: the outer edge is the largest radius still >= 20 % of
    /// the profile maximum. The probe counts as ring-structured when, out to
    /// 2 x the `probeSize` radius, the profile has a local maximum >= 20 % of
    /// its maximum after a dip below 25 % of it. Returned only when the edge
    /// is beyond the `probeSize` radius and no larger than min(qx, qy) / 8
    /// (S21's guard, chosen after Au_ref's ring at 26 px on a 64 px detector).
    package nonisolated static func outerEdge(meanDP dp: [Float], qy: Int, qx: Int) -> Result? {
        guard dp.count == qy * qx, let probe = OriginCalibration.probeSize(dp: dp, qy: qy, qx: qx) else { return nil }
        let bins = Int(Double(qx * qx + qy * qy).squareRoot()) + 2
        var sum = [Double](repeating: 0, count: bins)
        var count = [Double](repeating: 0, count: bins)
        for y in 0..<qy {
            for x in 0..<qx {
                let v = dp[y * qx + x]
                guard v.isFinite else { continue }
                let r = Int(hypot(Double(y) - Double(probe.y0), Double(x) - Double(probe.x0)))
                sum[r] += Double(v); count[r] += 1
            }
        }
        let profile = (0..<bins).map { count[$0] > 0 ? sum[$0] / count[$0] : 0 }
        guard let peak = profile.max(), peak > 0 else { return nil }
        var outer = 0
        for i in 0..<bins where profile[i] >= 0.2 * peak { outer = i + 1 }
        var ring = 0
        let upper = min(Int(2 * probe.r) + 1, bins - 1)
        guard upper > 1 else { return nil }
        for i in 1..<upper
        where profile[i] > profile[i - 1] && profile[i] >= profile[i + 1] && profile[i] >= 0.2 * peak {
            ring = i
        }
        guard ring > 1, let dip = profile[1..<ring].min(), dip / peak < 0.25 else { return nil }
        guard Float(outer) > probe.r, Float(outer) <= Float(min(qx, qy)) / 8 else { return nil }
        return Result(outerRadius: Float(outer), dip: Float(dip / peak))
    }
}
