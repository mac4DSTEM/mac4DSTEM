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
//  C2 (2026-10-15): every evaluation of the objective — the grid, the refinement and the null's surrogates — is CuboKit's
//  `RotationSolver` (py4DSTEM's selection rule, Double). The kit speaks py4DSTEM's convention, where the field's first
//  component is the one along the detector ROWS and the angle is the negative of this app's (`RQRotationConvention`:
//  a reflection of both spaces; the transpose flag is the same). So the field goes in as (row: cy, column: cx) and
//  the kit's angle is the app's negated; the curves come back aligned with this app's angle list. The refinement, the
//  null and the verdict below are the app's own and stay.
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

import CuboCore
import CuboPhase
import Foundation
import ImagoCore

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

    private struct DepthSlots: @unchecked Sendable {
        let depths: UnsafeMutablePointer<Float>
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
        let cx = cxM, cy = cyM   // immutable: the null reads them concurrently

        // Grid search, both transposes (py4DSTEM: −89°…90° in 1° steps; here 90° is included). The kit's angle is the
        // app's negated, index for index.
        let anglesDeg = stride(from: Float(-89), through: 90, by: 1).map { $0 }
        let kitAngles = anglesDeg.map { -Double($0) }
        let criterion: RotationCriterion = maximizeDivergence ? .maximizeDivergence : .minimizeCurl
        /// The kit's field for two app channels: the kit's row component is the app's y (cy), its column the app's x.
        @Sendable func kitField(_ x: [Float], _ y: [Float]) -> ScanVectorField? {
            try? ScanVectorField(scanRows: height, scanColumns: width, row: y.map { Double($0) }, column: x.map { Double($0) })
        }
        guard let field = kitField(cx, cy),
              let grid = try? RotationSolver.solve(field, anglesDegrees: kitAngles, criterion: criterion) else {
            // The kit refuses a field that is not finite. The Metal-era code returned NaN curves for it, which carry no
            // rotation; so does this: no depth, no null, `carriesRotation` false.
            let nans = [Float](repeating: .nan, count: anglesDeg.count)
            return Result(rotationRad: 0, transpose: false, objective: .nan, anglesDeg: anglesDeg,
                          objectiveCurve: nans, objectiveCurveTransposed: nans)
        }
        if cancellation?.isCancelled == true { return nil }
        let curve = grid.curve.map { Float($0) }
        let curveT = grid.curveTransposed.map { Float($0) }
        let transpose = grid.transposed
        var bestDeg = -grid.degrees            // Double: the refinement compares in Double, as py4DSTEM does
        var bestVal = (transpose ? grid.curveTransposed : grid.curve)[kitAngles.firstIndex(of: grid.degrees) ?? 0]

        // Refinement: 0.1° steps within ±1° of the grid winner, scored by the kit's `curve` in Double (a Float
        // objective let a 3e-8 tie pick −82.7° for −82.6° on Al–Mg–Si). The first strictly better angle wins.
        let center = bestDeg
        let fine = (0...20).map { center - 1 + Double($0) * 0.1 }
        if cancellation?.isCancelled == true { return nil }
        if let fineCurve = try? RotationSolver.curve(field, anglesDegrees: fine.map { -$0 }, criterion: criterion,
                                                     transpose: transpose) {
            for (deg, v) in zip(fine, fineCurve) where (maximizeDivergence ? v > bestVal : v < bestVal) {
                bestVal = v
                bestDeg = deg
            }
        }

        // THE NULL (rebuilt 2026-09-15 night, Gate D). Phase-randomised
        // SURROGATES of each channel, not a shuffle of the positions.
        //
        // The shuffle null shipped on 2026-09-15 morning was calibrated for
        // exchangeable samples: it destroys the spatial arrangement, so a
        // rotation-free field with any spatial correlation — which probe
        // overlap alone produces — beat it far more often than its 1-in-16
        // design rate. Measured with `../_archive/mac4DSTEM/tools/rotation-null-probe` before this
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
        func depth(_ c: [Double]) -> Float {
            guard let lo = c.min(), let hi = c.max(), !c.isEmpty else { return .nan }
            let mean = c.reduce(0, +) / Double(c.count)
            return mean != 0 ? Float((hi - lo) / abs(mean)) : .nan
        }
        let winningDepth = depth(transpose ? grid.curveTransposed : grid.curve)
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
                    guard let surrogateField = kitField(surCX[k], surCY[k]),
                          let r = try? RotationSolver.solve(surrogateField, anglesDegrees: kitAngles, criterion: criterion)
                    else { out.depths[k] = .nan; return }   // NaN never certifies (`depth > NaN` is false)
                    out.depths[k] = depth(r.transposed ? r.curveTransposed : r.curve)
                }
            }
            if cancellation?.isCancelled == true { return nil }
            shuffledDepths = depths
        }

        return Result(rotationRad: Float(bestDeg * (.pi / 180)),
                      transpose: transpose,
                      objective: Float(bestVal),
                      anglesDeg: anglesDeg,
                      objectiveCurve: curve,
                      objectiveCurveTransposed: curveT,
                      depth: winningDepth,
                      shuffledDepths: shuffledDepths)
    }
}
