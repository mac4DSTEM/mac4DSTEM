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
        /// the noise level, the dose and the scan size — so a field with
        /// spatial structure beats these and a spatially WHITE field does not.
        ///
        /// That is the honest statement of what the null tests, and it is
        /// narrower than "does this carry a rotation". Gate B, 2026-09-15:
        /// box-smoothed noise with NO rotation at a correlation length of two
        /// scan pixels beats all fifteen shuffles 60–80 % of the time, and
        /// probe overlap alone produces that correlation on ordinary data.
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
        /// WHAT THIS CANNOT DO, measured rather than guessed (Gate B,
        /// 2026-09-15). It catches one failure: that the field is spatially
        /// WHITE — pure Poisson shot noise produced a spurious "Measured
        /// −67.5°" on 2026-09-14. It does NOT:
        /// - catch a rotation-free field that merely has structure — a
        ///   per-row descan drift and a specimen edge were both certified
        ///   6 of 6, at 6–20× the shuffled depth, with arbitrary angles;
        /// - imply the angle is accurate. Planted 30° plus noise at sd 0.03
        ///   is certified 60 of 60 while 9 of those are more than 5° out and
        ///   one is 61° out.
        /// It does not refuse real rotations: 0 of 60 at every noise level
        /// through sd 0.05.
        ///
        /// AND THE VERDICT IS SEED-CONDITIONAL. Fifteen shuffles with
        /// "beat every one" is a rank test at a 1-in-16 design rate; the
        /// unit suite's own noise fixture is certified under 50 of 200 seeds.
        /// A deeper fix needs a statistic, not a rank.
        package var carriesRotation: Bool {
            guard depth.isFinite, !shuffledDepths.isEmpty else { return false }
            return shuffledDepths.allSatisfy { depth > $0 }
        }

        /// Why this fit may not be written, or nil when it may. The sentence
        /// lives here rather than in the caller so the refusal and the test
        /// that produces it cannot drift apart.
        package var refusalMessage: String? {
            guard !carriesRotation else { return nil }
            // "not updated", NOT "left as Not set": this declines to write and
            // never clears, so a rotation already there — from an earlier fit,
            // a session sidecar, the file, or typed by hand — survives, and
            // strain, ACOM and DPC go on using it. Gate B found the original
            // sentence claiming a state the code does not establish.
            // "surrogates", not "shuffling": the null changed on 2026-09-15
            // night and the sentence did not, and the drive of 2026-09-15
            // read the stale word on screen.
            return "This scan's centre-of-mass field carries no rotation its own "
                + "structure does not explain: surrogates with the same spectrum and "
                + "random phases fit it as well, so there is nothing here for a "
                + "curl-based fit to lock onto. The rotation is not updated. Try a "
                + "thicker or more amorphous region, or a larger scan."
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

    // Output slots for the concurrent grid search and null, written at
    // disjoint indices from `concurrentPerform` workers. // v3.1 speed
    private struct CurveSlots: @unchecked Sendable {
        let curve: UnsafeMutablePointer<Float>
        let curveT: UnsafeMutablePointer<Float>
    }
    private struct DepthSlots: @unchecked Sendable {
        let depths: UnsafeMutablePointer<Float>
    }

    /// Mean |curl| (or |divergence|, when `maximizeDivergence`) of the field
    /// rotated by θ — one point on an objective curve. Rotating (a, b) by θ:
    /// x' = cosθ·a − sinθ·b, y' = sinθ·a + cosθ·b, where (a, b) is (cx, cy),
    /// or (cy, cx) for the transposed detector. Free-standing and reading
    /// immutable inputs so the grid search and the null can evaluate it on all
    /// cores; the arithmetic is exactly the former inline objective. // v3.1 speed
    private nonisolated static func objective(cx: [Float], cy: [Float], width: Int, height: Int,
                                              thetaRad: Float, maximizeDivergence: Bool,
                                              transpose: Bool) -> Float {
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
        var cxM = [Float](repeating: 0, count: n)
        var cyM = [Float](repeating: 0, count: n)
        for i in 0..<n {
            cxM[i] = com[2 * i]
            cyM[i] = com[2 * i + 1]
        }
        let cx = cxM, cy = cyM   // immutable: the grid search and the null read them concurrently

        // The objective bound to this field, for the serial refinement pass.
        func obj(_ thetaRad: Float, _ transpose: Bool) -> Float {
            Self.objective(cx: cx, cy: cy, width: width, height: height,
                           thetaRad: thetaRad, maximizeDivergence: maximizeDivergence, transpose: transpose)
        }

        // Grid search, both transposes (py4DSTEM: −89°…90° in 1° steps). The
        // 180 angles are independent, so evaluate them on all cores — each
        // writes its own slot and the per-angle arithmetic is unchanged. // v3.1 speed
        let anglesDeg = stride(from: Float(-89), through: 90, by: 1).map { $0 }
        let angleCount = anglesDeg.count
        var curve = [Float](repeating: 0, count: angleCount)
        var curveT = [Float](repeating: 0, count: angleCount)
        curve.withUnsafeMutableBufferPointer { cp in
            curveT.withUnsafeMutableBufferPointer { ctp in
                let out = CurveSlots(curve: cp.baseAddress!, curveT: ctp.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: angleCount) { idx in
                    if cancellation?.isCancelled == true { return }
                    let rad = anglesDeg[idx] * .pi / 180
                    out.curve[idx]  = Self.objective(cx: cx, cy: cy, width: width, height: height,
                                                     thetaRad: rad, maximizeDivergence: maximizeDivergence, transpose: false)
                    out.curveT[idx] = Self.objective(cx: cx, cy: cy, width: width, height: height,
                                                     thetaRad: rad, maximizeDivergence: maximizeDivergence, transpose: true)
                }
            }
        }
        if cancellation?.isCancelled == true { return nil }

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
            let v = obj(Float(deg) * .pi / 180, transpose)
            if maximizeDivergence ? v > bestVal : v < bestVal {
                bestVal = v
                bestDeg = Float(deg)
            }
        }

        // THE NULL (rebuilt 2026-09-15 night, Gate D). Phase-randomised
        // SURROGATES of each channel, not a shuffle of the positions.
        //
        // The shuffle null shipped on 2026-09-15 morning was calibrated for
        // exchangeable samples: it destroys the spatial arrangement, so a
        // rotation-free field with any spatial correlation — which probe
        // overlap alone produces — beat it far more often than its 1-in-16
        // design rate. Measured with `tools/rotation-null-probe` before this
        // change: box-smoothed noise certified 15 % (box 1, white), 32 %
        // (box 3), 52 % (box 5), 65 % (box 7) — the rate rising with the
        // correlation length is the diagnosis's own prediction, met.
        //
        // What a rotation IS, to this objective: a fixed phase relation
        // between the two channels (cx = ∂φ/∂x, cy = ∂φ/∂y, up to the
        // rotation being measured). A surrogate that keeps each channel's
        // amplitude spectrum — hence its correlation length, its anisotropy,
        // its mean — and randomises the phases independently per channel
        // keeps everything the null should keep and destroys exactly that
        // relation. The rank test over fifteen of them is then exact by
        // construction (Theiler et al. 1992), whatever the field's structure.
        //
        // What it deliberately cannot do: a field whose rotation is carried
        // by ONE channel alone (a 1-D specimen, or a descan ramp in one axis)
        // has no cross-channel relation to destroy, so it is refused — and
        // that is right, because a drift and a striped phase object are the
        // same field. A two-channel step edge (both channels stepping at the
        // same place) IS a rotated gradient and stays certified; no method
        // that reads the field alone can tell it from a rotation.
        //
        // Deterministic by a fixed seed: a refusal that flickers between runs
        // is worse than no refusal at all. Hermitian pairs get opposite
        // phases so the inverse transform stays real; self-conjugate bins
        // (DC, Nyquist) keep theirs. Gate B (2026-09-15 night) applied the
        // unpaired variant: the probe's noisy planted rotation fell from
        // 60 of 60 certified to 16, which is what the sd-0.03 unit test
        // pins. Box-7 smoothing on a 40-px field still certifies 10 of 60
        // because the field is not periodic and the surrogate is; the same
        // field wrapped periodically certifies 5 of 60.
        //
        // DEVIATION: py4DSTEM's `_solve_for_center_of_mass_relative_rotation`
        // (phase_base_class.py) has no significance test at all — it returns
        // the grid-search optimum whatever the field. The refusal mechanism
        // from the shuffle null of 2026-09-15 morning onwards is this port's
        // own, because the owner was handed "Measured −67.5°" from shot
        // noise and no downstream consumer could tell.
        func depth(_ c: [Float]) -> Float {
            guard let lo = c.min(), let hi = c.max(), !c.isEmpty else { return .nan }
            let mean = c.reduce(0, +) / Float(c.count)
            return mean != 0 ? (hi - lo) / abs(mean) : .nan
        }
        let winningDepth = depth(transpose ? curveT : curve)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func nextUnit() -> Float {
            rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27
            return Float(Double((rng &* 2685821657736338717) >> 11) / Double(UInt64(1) << 53))
        }
        let shuffleCount = 15
        var shuffledDepths: [Float] = []
        // No FFT plan (Accelerate could not allocate one) leaves the null
        // empty, and `carriesRotation` refuses on an empty null: a fit that
        // cannot be tested is not written.
        if let fft = FFT2D(nx: width, ny: height) {
            func surrogate(_ channel: [Float]) -> [Float] {
                var re = channel
                var im = [Float](repeating: 0, count: n)
                fft.transform(re: &re, im: &im, forward: true)
                for k in 0..<n {
                    let kx = k % width, ky = k / width
                    let partner = ((height - ky) % height) * width + ((width - kx) % width)
                    if partner < k { continue }          // rotated with its pair already
                    if partner == k { continue }         // self-conjugate: keep the phase
                    let phi = nextUnit() * 2 * .pi
                    let c = cos(phi), sn = sin(phi)
                    let r0 = re[k], i0 = im[k]
                    re[k] = r0 * c - i0 * sn; im[k] = r0 * sn + i0 * c
                    let r1 = re[partner], i1 = im[partner]
                    re[partner] = r1 * c + i1 * sn; im[partner] = -r1 * sn + i1 * c
                }
                fft.transform(re: &re, im: &im, forward: false, scaleInverse: true)
                return re
            }
            // Draw the fifteen surrogate pairs SERIALLY: the phase draws must
            // keep their order or this becomes a different (though equally
            // valid) null, and a refusal that flickers between runs is worse
            // than none. Then score the independent pairs on all cores — same
            // objective, same reduction order, one depth per slot. // v3.1 speed
            var surCX = [[Float]](), surCY = [[Float]]()
            surCX.reserveCapacity(shuffleCount); surCY.reserveCapacity(shuffleCount)
            for _ in 0..<shuffleCount { surCX.append(surrogate(cx)); surCY.append(surrogate(cy)) }
            var depths = [Float](repeating: 0, count: shuffleCount)
            depths.withUnsafeMutableBufferPointer { dp in
                let out = DepthSlots(depths: dp.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: shuffleCount) { k in
                    if cancellation?.isCancelled == true { return }
                    let sCX = surCX[k], sCY = surCY[k]
                    let shuffledCurve = anglesDeg.map {
                        Self.objective(cx: sCX, cy: sCY, width: width, height: height,
                                       thetaRad: $0 * .pi / 180, maximizeDivergence: maximizeDivergence, transpose: false)
                    }
                    let shuffledCurveT = anglesDeg.map {
                        Self.objective(cx: sCX, cy: sCY, width: width, height: height,
                                       thetaRad: $0 * .pi / 180, maximizeDivergence: maximizeDivergence, transpose: true)
                    }
                    let s0 = best(shuffledCurve), sT = best(shuffledCurveT)
                    let takeTransposed = maximizeDivergence ? sT.val > s0.val : sT.val < s0.val
                    out.depths[k] = depth(takeTransposed ? shuffledCurveT : shuffledCurve)
                }
            }
            if cancellation?.isCancelled == true { return nil }
            shuffledDepths = depths
        }

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
