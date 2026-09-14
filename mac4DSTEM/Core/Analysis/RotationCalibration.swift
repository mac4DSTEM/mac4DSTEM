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

package enum RotationCalibration {

    package struct Result {
        package let rotationRad: Float
        package let transpose: Bool
        /// Objective value at the optimum (mean |curl| or mean |div|).
        package let objective: Float
        /// The 1°-grid search curves, for plotting/inspection:
        /// angles in degrees, objective without and with transpose.
        package let anglesDeg: [Float]
        package let objectiveCurve: [Float]
        package let objectiveCurveTransposed: [Float]
        /// Depth of the WINNING curve, `(max − min) / mean`. Not pooled across
        /// the two transpose curves: the answer came from one of them, and
        /// pooling reports a contrast the fit never saw.
        package let depth: Float
        /// The same depth, measured on scan-position-shuffled copies of the
        /// same field. Shuffling destroys the spatial arrangement and keeps
        /// everything else — the noise level, the dose, the scan size — so a
        /// real curl-free direction beats these and noise does not.
        package let shuffledDepths: [Float]

        /// Did this field carry a rotation at all?
        ///
        /// A permutation test rather than a threshold, because the number a
        /// threshold would need is not a constant: measured 2026-09-14, the
        /// depth of a pure-noise field runs 0.016 at a 100 × 100 scan and
        /// 0.089 at 20 × 20, and varies 13-fold with the signal's spatial
        /// frequency at fixed signal-to-noise. The shuffle carries the
        /// dataset's own scale with it and needs no constant to defend.
        ///
        /// WHAT THIS CANNOT DO, stated because the opposite is temptingly
        /// easy to claim: it does not certify a measurement. A thick or
        /// strongly diffracting specimen gives a deep, sharp, reproducible
        /// minimum at an angle that need not be the detector rotation. This
        /// catches ONE failure — that there is no signal at all — which on
        /// 2026-09-14 was reported to the owner as "Measured −67.5°" from a
        /// field that was pure Poisson shot noise.
        package var carriesRotation: Bool {
            guard depth.isFinite, !shuffledDepths.isEmpty else { return false }
            return shuffledDepths.allSatisfy { depth > $0 }
        }

        /// Why this fit may not be written, or nil when it may. The sentence
        /// lives here rather than in the caller so the refusal and the test
        /// that produces it cannot drift apart.
        package var refusalMessage: String? {
            guard !carriesRotation else { return nil }
            return "The scan's centre-of-mass field carries no measurable R–Q rotation: "
                + "shuffling the scan positions gives an equally good answer, so this is "
                + "the shape of noise rather than of a rotation. The rotation is left as "
                + "Not set. A curl-based fit needs a specimen that behaves like a phase "
                + "object over the scan — try a thicker or more amorphous region, or a "
                + "larger scan."
        }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(rotationRad: Float, transpose: Bool, objective: Float, anglesDeg: [Float], objectiveCurve: [Float], objectiveCurveTransposed: [Float], depth: Float = .nan, shuffledDepths: [Float] = []) {
            self.rotationRad = rotationRad
            self.transpose = transpose
            self.objective = objective
            self.anglesDeg = anglesDeg
            self.objectiveCurve = objectiveCurve
            self.objectiveCurveTransposed = objectiveCurveTransposed
            self.depth = depth
            self.shuffledDepths = shuffledDepths
        }
    }

    /// Solve for rotation + transpose from an interleaved CoM field
    /// [cx0, cy0, cx1, cy1, ...] of scan shape width × height.
    /// The field should already be descan-corrected (measured against fitted
    /// origins), i.e. py4DSTEM's "normalized" CoM.
    package nonisolated static func solve(com: [Float], width: Int, height: Int,
                      maximizeDivergence: Bool = false,
                      cancellation: AnalysisCancellationToken? = nil) -> Result? {
        guard cancellation?.isCancelled != true else { return nil }
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
            if cancellation?.isCancelled == true { return nil }
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
            if cancellation?.isCancelled == true { return nil }
            let v = objective(thetaRad: Float(deg) * .pi / 180, transpose: transpose)
            if maximizeDivergence ? v > bestVal : v < bestVal {
                bestVal = v
                bestDeg = Float(deg)
            }
        }

        // THE NULL. Shuffle the scan positions — carrying each position's
        // (cx, cy) together, so only the spatial arrangement is destroyed —
        // and run the same grid. Deterministic by a fixed seed: a refusal that
        // flickers between runs is worse than no refusal at all.
        func depth(_ c: [Float]) -> Float {
            guard let lo = c.min(), let hi = c.max(), !c.isEmpty else { return .nan }
            let mean = c.reduce(0, +) / Float(c.count)
            return mean != 0 ? (hi - lo) / abs(mean) : .nan
        }
        let winningDepth = depth(transpose ? curveT : curve)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func nextIndex(_ bound: Int) -> Int {
            rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27
            return Int((rng &* 2685821657736338717) >> 33) % max(1, bound)
        }
        var shuffledDepths: [Float] = []
        let shuffleCount = 15
        shuffledDepths.reserveCapacity(shuffleCount)
        let originalCX = cx, originalCY = cy
        for _ in 0..<shuffleCount {
            if cancellation?.isCancelled == true { return nil }
            var order = Array(0..<n)
            for i in stride(from: n - 1, to: 0, by: -1) { order.swapAt(i, nextIndex(i + 1)) }
            for i in 0..<n { cx[i] = originalCX[order[i]]; cy[i] = originalCY[order[i]] }
            let shuffledCurve = anglesDeg.map { objective(thetaRad: $0 * .pi / 180, transpose: false) }
            let shuffledCurveT = anglesDeg.map { objective(thetaRad: $0 * .pi / 180, transpose: true) }
            let s0 = best(shuffledCurve), sT = best(shuffledCurveT)
            let takeTransposed = maximizeDivergence ? sT.val > s0.val : sT.val < s0.val
            shuffledDepths.append(depth(takeTransposed ? shuffledCurveT : shuffledCurve))
        }
        cx = originalCX; cy = originalCY

        return Result(rotationRad: bestDeg * .pi / 180,
                      transpose: transpose,
                      objective: bestVal,
                      anglesDeg: anglesDeg,
                      objectiveCurve: curve,
                      objectiveCurveTransposed: curveT,
                      depth: winningDepth,
                      shuffledDepths: shuffledDepths)
    }
}
