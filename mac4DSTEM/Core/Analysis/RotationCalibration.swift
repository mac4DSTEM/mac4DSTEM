//
//  RotationCalibration.swift
//  Role: Solve for the relative rotation between the scan (R) axes and the
//        detector (Q) axes — and whether the detector axes are transposed —
//        from a measured CoM vector field. Port of py4DSTEM's
//        _solve_for_center_of_mass_relative_rotation (phase_base_class.py).
//
//  PHYSICS: for a (near-)phase object the CoM shift field is the gradient of
//  a scalar potential, so in the correct coordinate frame it is curl-free.
//  A rotation offset between R and Q mixes the components and introduces
//  curl. We scan candidate angles (and the transposed field), rotate the
//  field, and keep the combination minimizing mean |curl| — or, optionally,
//  maximizing mean |divergence|, which is more robust for thick samples
//  where the curl-free assumption weakens.
//
//  DEVIATION from py4DSTEM: after the same 1° grid search (−89°…90°), we add
//  a 0.1° refinement pass around the winning angle. py4DSTEM stops at 1°.
//
//  NOTE: a 180° ambiguity is inherent to the method (flipping both field
//  components leaves curl and divergence unchanged); like py4DSTEM we search
//  a half circle. If iDPC contrast comes out inverted, the true rotation is
//  θ + 180° — a manual override is the standard fix. // FUTURE: expose one.
//
//  Coordinate convention (app-wide, see Calibration.swift): X = detector
//  column / scan column, Y = row. Curl and divergence use central
//  differences on the interior of the scan grid.
//

import Foundation

enum RotationCalibration {

    struct Result {
        let rotationRad: Float
        let transpose: Bool
        /// Objective value at the optimum (mean |curl| or mean |div|).
        let objective: Float
        /// The 1°-grid search curves, for plotting/inspection:
        /// angles in degrees, objective without and with transpose.
        let anglesDeg: [Float]
        let objectiveCurve: [Float]
        let objectiveCurveTransposed: [Float]
    }

    /// Solve for rotation + transpose from an interleaved CoM field
    /// [cx0, cy0, cx1, cy1, ...] of scan shape width × height.
    /// The field should already be descan-corrected (measured against fitted
    /// origins), i.e. py4DSTEM's "normalized" CoM.
    nonisolated static func solve(com: [Float], width: Int, height: Int,
                      maximizeDivergence: Bool = false) -> Result? {
        guard width >= 3, height >= 3 else { return nil }

        let n = width * height
        var cx = [Float](repeating: 0, count: n)
        var cy = [Float](repeating: 0, count: n)
        for i in 0..<n {
            cx[i] = com[2 * i]
            cy[i] = com[2 * i + 1]
        }

        // Objective for one candidate (θ, transpose). Rotating (a, b) by θ:
        // x' = cosθ·a − sinθ·b, y' = sinθ·a + cosθ·b, where (a, b) is
        // (cx, cy), or (cy, cx) for the transposed detector.
        func objective(thetaRad: Float, transpose: Bool) -> Float {
            let a = transpose ? cy : cx
            let b = transpose ? cx : cy
            let c = cos(thetaRad), s = sin(thetaRad)

            var acc: Float = 0
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    if maximizeDivergence {
                        // div = ∂x'/∂x + ∂y'/∂y  (central differences, ×½ dropped
                        // — constant scale doesn't move the argmin/argmax)
                        let dxdx = (c * a[i + 1] - s * b[i + 1])
                                 - (c * a[i - 1] - s * b[i - 1])
                        let dydy = (s * a[i + width] + c * b[i + width])
                                 - (s * a[i - width] + c * b[i - width])
                        acc += abs(dxdx + dydy)
                    } else {
                        // curl_z = ∂y'/∂x − ∂x'/∂y
                        let dydx = (s * a[i + 1] + c * b[i + 1])
                                 - (s * a[i - 1] + c * b[i - 1])
                        let dxdy = (c * a[i + width] - s * b[i + width])
                                 - (c * a[i - width] - s * b[i - width])
                        acc += abs(dydx - dxdy)
                    }
                }
            }
            return acc / Float((width - 2) * (height - 2))
        }

        // Grid search, both transposes (py4DSTEM: −89°…90° in 1° steps).
        let anglesDeg = stride(from: Float(-89), through: 90, by: 1).map { $0 }
        var curve = [Float](), curveT = [Float]()
        curve.reserveCapacity(anglesDeg.count)
        curveT.reserveCapacity(anglesDeg.count)
        for deg in anglesDeg {
            let rad = deg * .pi / 180
            curve.append(objective(thetaRad: rad, transpose: false))
            curveT.append(objective(thetaRad: rad, transpose: true))
        }

        func best(_ c: [Float]) -> (idx: Int, val: Float) {
            var bi = 0
            for i in 1..<c.count {
                if maximizeDivergence ? c[i] > c[bi] : c[i] < c[bi] { bi = i }
            }
            return (bi, c[bi])
        }
        let b0 = best(curve)
        let bT = best(curveT)
        let transpose = maximizeDivergence ? bT.val > b0.val : bT.val < b0.val
        var bestDeg = anglesDeg[transpose ? bT.idx : b0.idx]
        var bestVal = transpose ? bT.val : b0.val

        // Refinement: 0.1° steps within ±1° of the grid winner.
        for deg in stride(from: bestDeg - 1, through: bestDeg + 1, by: 0.1) {
            let v = objective(thetaRad: Float(deg) * .pi / 180, transpose: transpose)
            if maximizeDivergence ? v > bestVal : v < bestVal {
                bestVal = v
                bestDeg = Float(deg)
            }
        }

        return Result(rotationRad: bestDeg * .pi / 180,
                      transpose: transpose,
                      objective: bestVal,
                      anglesDeg: anglesDeg,
                      objectiveCurve: curve,
                      objectiveCurveTransposed: curveT)
    }
}
