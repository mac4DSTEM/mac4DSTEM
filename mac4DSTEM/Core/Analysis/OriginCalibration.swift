//
//  OriginCalibration.swift
//  Role: The origin-calibration workflow (py4DSTEM: get_probe_size,
//        get_origin, fit_origin). GPU kernels do the per-pattern work
//        (DPStatistics.metal, OriginMeasure.metal); this file holds the
//        small CPU-side pieces — probe-size estimation on the max pattern
//        and the smooth 2D fit of the measured origin maps — plus the
//        orchestration that ties them into a `Calibration`.
//
//  All algorithms are ports of the py4DSTEM reference implementations;
//  deviations are marked DEVIATION with a reason.
//

import Foundation
import Metal

enum OriginFitFunction: String, CaseIterable, Identifiable {
    case constant = "Constant"
    case plane    = "Plane"       // py4DSTEM default
    case parabola = "Parabola"
    var id: String { rawValue }
}

nonisolated enum OriginCalibration {

    // MARK: - Probe size (py4DSTEM get_probe_size)

    /// Estimate the central-disk radius and position from one diffraction
    /// pattern (ideally the max or mean pattern). Port of get_probe_size:
    /// threshold the pattern at N levels, convert each mask area to an
    /// equivalent circle radius, keep the threshold range where r(thresh) is
    /// stable (derivative near zero), and take the CoM at that threshold.
    nonisolated static func probeSize(dp: [Float], qy: Int, qx: Int,
                          threshLower: Float = 0.01, threshUpper: Float = 0.99,
                          n: Int = 100) -> (r: Float, x0: Float, y0: Float) {
        let dpMax = dp.max() ?? 0
        guard dpMax > 0 else { return (1, Float(qx) / 2, Float(qy) / 2) }

        let threshVals = (0..<n).map { i in
            threshLower + (threshUpper - threshLower) * Float(i) / Float(n - 1)
        }
        let rVals: [Float] = threshVals.map { t in
            let area = dp.reduce(into: 0) { c, v in if v > dpMax * t { c += 1 } }
            return (Float(area) / .pi).squareRoot()
        }

        // Central-difference gradient, one-sided at the ends (np.gradient).
        var dr = [Float](repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 { dr[i] = rVals[1] - rVals[0] }
            else if i == n - 1 { dr[i] = rVals[n - 1] - rVals[n - 2] }
            else { dr[i] = (rVals[i + 1] - rVals[i - 1]) / 2 }
        }
        let sorted = dr.sorted()
        let median = sorted[n / 2]

        // Trustworthy where the (negative) slope is between 2*median and 0.
        var trusted: [Int] = []
        for i in 0..<n where dr[i] <= 0 && dr[i] >= 2 * median {
            trusted.append(i)
        }
        // DEVIATION: py4DSTEM returns NaN if no thresholds qualify; we fall
        // back to the middle of the threshold range so calibration always
        // produces something usable, and the caller can inspect the result.
        if trusted.isEmpty { trusted = [n / 2] }

        let r = trusted.reduce(Float(0)) { $0 + rVals[$1] } / Float(trusted.count)
        let thresh = trusted.reduce(Float(0)) { $0 + threshVals[$1] } / Float(trusted.count)

        // CoM of the pattern masked at that threshold.
        var sumI: Float = 0, sumIX: Float = 0, sumIY: Float = 0
        for y in 0..<qy {
            for x in 0..<qx {
                let v = dp[y * qx + x]
                if v > dpMax * thresh {
                    sumI += v
                    sumIX += v * Float(x)
                    sumIY += v * Float(y)
                }
            }
        }
        guard sumI > 0 else { return (r, Float(qx) / 2, Float(qy) / 2) }
        return (r, sumIX / sumI, sumIY / sumI)
    }

    // MARK: - Origin fit (py4DSTEM fit_origin)

    /// Fit the measured origin maps with a smooth 2D function and return the
    /// fitted maps evaluated at every scan position. Scan coordinates are
    /// normalized to [0, 1] before fitting for numerical conditioning.
    nonisolated static func fitOrigin(measuredX: [Float], measuredY: [Float],
                          width: Int, height: Int,
                          fitFunction: OriginFitFunction = .plane)
        -> (fittedX: [Float], fittedY: [Float]) {
        switch fitFunction {
        case .constant:
            let n = Float(measuredX.count)
            let mx = measuredX.reduce(0, +) / n
            let my = measuredY.reduce(0, +) / n
            return ([Float](repeating: mx, count: measuredX.count),
                    [Float](repeating: my, count: measuredY.count))
        case .plane:
            return (fit2D(measuredX, width: width, height: height, terms: 3),
                    fit2D(measuredY, width: width, height: height, terms: 3))
        case .parabola:
            return (fit2D(measuredX, width: width, height: height, terms: 6),
                    fit2D(measuredY, width: width, height: height, terms: 6))
        }
    }

    /// `fitOrigin` restricted to a subset of scan positions, evaluated
    /// everywhere. Exposed (rather than left as `fit2D`'s private parameter)
    /// so the trimmed fit's own uncertainty can be measured against the SHIPPED
    /// fitter instead of a second copy in a harness — the 2026-08-17 lesson
    /// about lists that drift applies to estimators too. // v2 S13
    nonisolated static func fitOrigin(
        measuredX: [Float], measuredY: [Float],
        width: Int, height: Int,
        fitFunction: OriginFitFunction = .plane,
        included: [Bool]
    ) -> (fittedX: [Float], fittedY: [Float]) {
        switch fitFunction {
        case .constant:
            let indices = measuredX.indices.filter { included[$0] }
            let source = indices.isEmpty ? Array(measuredX.indices) : indices
            let n = Float(source.count)
            let mx = source.reduce(Float(0)) { $0 + measuredX[$1] } / n
            let my = source.reduce(Float(0)) { $0 + measuredY[$1] } / n
            return ([Float](repeating: mx, count: measuredX.count),
                    [Float](repeating: my, count: measuredY.count))
        case .plane, .parabola:
            let terms = fitFunction == .plane ? 3 : 6
            return (fit2D(measuredX, width: width, height: height, terms: terms, included: included),
                    fit2D(measuredY, width: width, height: height, terms: terms, included: included))
        }
    }

    // MARK: - Robust origin fit (v2 S13)

    /// Outcome of an iteratively-trimmed origin fit.
    struct TrimmedFit: Sendable {
        var fittedX: [Float]
        var fittedY: [Float]
        /// Positions the final round kept. `false` = the position's measurement
        /// was excluded from the fit, NOT that it has no fitted origin — every
        /// position gets one, evaluated from the surface the kept positions fit.
        var kept: [Bool]
        /// RMS(measured − fitted) over the KEPT positions only.
        var keptResidual: Float
        /// RMS(measured − fitted) over ALL positions, which is what the shipped
        /// gate reads. Recorded because it is NOT the same number and comparing
        /// `keptResidual` to a full-scan threshold is circular — trimming
        /// removes the largest residuals by construction, so RMS(kept) is
        /// guaranteed to fall (S12 §1.2, measured: 2.19 px kept vs 18.47 px
        /// full-scan on `Particle_1`).
        var fullScanResidual: Float
        /// nil when there are no positions at all. The first version clamped
        /// the denominator with `max(kept.count, 1)`, which turned an empty
        /// scan into a confident **1.0 — "excluded 100% of positions as
        /// outliers"** for a scan with nothing to exclude (Gate B,
        /// 2026-08-28). A NaN would have been wrong too; the honest answer is
        /// that the question does not apply.
        var excludedFraction: Float? {
            guard !kept.isEmpty else { return nil }
            return 1 - Float(kept.filter { $0 }.count) / Float(kept.count)
        }
    }

    /// **DEVIATION from py4DSTEM `fit_origin`, which is ordinary least squares
    /// over every scan position.** On a scan where a minority of positions fail
    /// origin measurement outright, unweighted OLS is dragged by them: measured
    /// on `Particle_1…bin8`, a quarter of positions fail (median/RMS residual
    /// 0.183 — a heavy tail, against ≈0.83 for Rayleigh scatter) and the shipped
    /// plane sits up to **6.00 px** away from the trimmed one, past the ≈2 px
    /// where the Q estimator breaks down (#29 item 1). Reason for the
    /// deviation: the app *refuses* on this fit, so a displaced fit is not a
    /// cosmetic difference — it is a wrong number the app then declines to
    /// admit for the wrong reason.
    ///
    /// Up to three rounds at `median + 3·1.4826·MAD` — **"up to", because the
    /// loop terminates as soon as the residuals stop moving, and in practice it
    /// exits at round 2**: after the first refit the inliers sit on the surface,
    /// the MAD is zero, and the guard below stops it. The first version of this
    /// sentence said "three rounds" flatly; a Gate B mutation showed
    /// `rounds: 3 → 2` changes nothing on any case measured (2026-08-28).
    /// Those constants are **not chosen here** — they are the ones S12 measured the design's numbers with
    /// (`docs/q-calibration-design.md` §1.2), so the app and the diagnostics
    /// that justified it trim identically. 1.4826 is the MAD→σ consistency
    /// factor for a normal distribution.
    ///
    /// **Where these numbers come from, stated because a reader cannot rerun
    /// them here:** every figure above is from `tools/origin-fit-diagnostics`,
    /// which needs the gitignored training data and is deliberately not in the
    /// `scientific` array. They are the justification for deviating from
    /// py4DSTEM and they are not reproducible from a clean checkout — a real
    /// limit under the repo's own claims rule, raised by Gate B 2026-08-28 and
    /// left standing rather than quietly dropped.
    ///
    /// **Measured limits of the trim itself** (Gate B, same day): it recovers
    /// the truth exactly for 5%–33% contamination, independent of outlier
    /// magnitude from 1 px to 40 px, and converges — 0 of 60 randomized trials
    /// were still changing after round 3. It does **not** work when the failed
    /// positions are spatially clustered (a contiguous quarter thrown 40 px:
    /// 100% kept, fit 20.6 px off) or at/above the 50% breakdown point of a
    /// median/MAD estimator (0% excluded, 30.4 px off). In both regimes it
    /// degrades to ordinary least squares rather than excluding everything,
    /// which is the safe direction, but the excluded fraction reads zero and
    /// says nothing about why.
    ///
    /// Converges to keeping every position when there is no tail to trim —
    /// measured on `downsample_Si_SiGe_exp`, 100.0% kept, RMS moved by nothing
    /// (11.6551 → 11.6551). **Broad measurement failure excludes nothing**,
    /// which is why the excluded fraction cannot be the refusal statistic.
    nonisolated static func fitOriginTrimmed(
        measuredX: [Float], measuredY: [Float],
        width: Int, height: Int,
        fitFunction: OriginFitFunction = .plane,
        trimSigma: Float = 3, rounds: Int = 3
    ) -> TrimmedFit {
        let count = measuredX.count
        var kept = [Bool](repeating: true, count: count)
        var fittedX = measuredX, fittedY = measuredY
        // A mismatch used to return `fittedX = measuredX` (n) beside
        // `fittedY = measuredY` (m ≠ n) — an `OriginMaps` whose two fitted
        // arrays differ in length, reading as a clean fully-supported fit,
        // which `meanOrigin` would then have averaged (Gate B, 2026-08-28).
        // Return a degenerate-but-consistent pair instead.
        guard count > 0, measuredY.count == count else {
            let empty = [Float]()
            return TrimmedFit(fittedX: empty, fittedY: empty, kept: [],
                              keptResidual: .nan, fullScanResidual: .nan)
        }

        func residuals(_ fx: [Float], _ fy: [Float]) -> [Float] {
            (0..<count).map { index in
                let dx = measuredX[index] - fx[index], dy = measuredY[index] - fy[index]
                return (dx * dx + dy * dy).squareRoot()
            }
        }

        // The loop fits on `kept`, then updates it. The FIRST version left the
        // last update unpaired, so `fittedX/Y` came from round n's mask while
        // `kept`, `excludedFraction` and `keptResidual` all described round
        // n+1's — measured divergence up to 9.86 px between the reported
        // surface and a refit on the reported set (Gate B, 2026-08-28). The
        // final refit below closes it: whatever `kept` says at exit is what
        // produced the surface.
        for _ in 0..<max(rounds, 1) {
            let mask = kept
            switch fitFunction {
            case .constant:
                // The masked analogue of the constant branch: the mean over the
                // kept positions, not over all of them.
                let indices = (0..<count).filter { mask[$0] }
                let source = indices.isEmpty ? Array(0..<count) : indices
                let n = Float(source.count)
                let mx = source.reduce(Float(0)) { $0 + measuredX[$1] } / n
                let my = source.reduce(Float(0)) { $0 + measuredY[$1] } / n
                fittedX = [Float](repeating: mx, count: count)
                fittedY = [Float](repeating: my, count: count)
            case .plane, .parabola:
                let terms = fitFunction == .plane ? 3 : 6
                fittedX = fit2D(measuredX, width: width, height: height, terms: terms, included: mask)
                fittedY = fit2D(measuredY, width: width, height: height, terms: terms, included: mask)
            }
            let residual = residuals(fittedX, fittedY)
            let centre = median(residual)
            let deviation = 1.4826 * median(residual.map { abs($0 - centre) })
            // A zero MAD means the residuals are degenerate (every position
            // identical, or a scan too small to have a spread). Cutting at
            // `centre` alone would then exclude half the scan for no reason, so
            // stop trimming instead. // v2 S13
            //
            // **This is also where the trim gives up on an exactly bimodal
            // residual distribution** — a flat truth with a third of positions
            // thrown a constant distance makes every majority deviation equal,
            // so the MAD is exactly 0 and the loop breaks having excluded
            // nothing. Found while trying to build a control for the masked
            // `.constant` branch, 2026-08-28. It is the same failure Gate B
            // measured at the 50% breakdown point, arriving earlier for this
            // shape, and it reports `excludedFraction == 0` — which the refusal
            // text must therefore not read as "the whole scan is failing".
            guard deviation.isFinite, deviation > 0 else { break }
            let cutoff = centre + trimSigma * deviation
            let next = residual.map { $0 <= cutoff }
            if !next.contains(true) { break }
            if next == kept { kept = next; break }
            kept = next
        }

        // Final refit on the mask actually being reported.
        if kept.contains(true) {
            let refit = fitOrigin(measuredX: measuredX, measuredY: measuredY,
                                  width: width, height: height,
                                  fitFunction: fitFunction, included: kept)
            fittedX = refit.fittedX
            fittedY = refit.fittedY
        }

        let residual = residuals(fittedX, fittedY)
        let keptIndices = (0..<count).filter { kept[$0] }
        func rms(_ indices: [Int]) -> Float {
            guard !indices.isEmpty else { return .nan }
            let total = indices.reduce(Float(0)) { $0 + residual[$1] * residual[$1] }
            return (total / Float(indices.count)).squareRoot()
        }
        return TrimmedFit(
            fittedX: fittedX, fittedY: fittedY, kept: kept,
            keptResidual: rms(keptIndices), fullScanResidual: rms(Array(0..<count))
        )
    }

    private nonisolated static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Least-squares fit of z(x, y) with polynomial basis
    ///   terms == 3: [1, x, y]                       (plane)
    ///   terms == 6: [1, x, y, x², xy, y²]           (parabola)
    /// solved via the normal equations; the systems are tiny (≤ 6×6).
    ///
    /// `included`, when given, restricts the ACCUMULATION to the marked scan
    /// positions; the fitted surface is still evaluated everywhere, which is
    /// what makes a trimmed refit usable — the excluded positions get a fitted
    /// origin derived from the positions that measured well. // v2 S13
    private nonisolated static func fit2D(_ z: [Float], width: Int, height: Int, terms: Int,
                                          included: [Bool]? = nil) -> [Float] {
        var ata = [Double](repeating: 0, count: terms * terms)
        var atb = [Double](repeating: 0, count: terms)
        var basis = [Double](repeating: 0, count: terms)

        func fillBasis(_ x: Double, _ y: Double) {
            basis[0] = 1; basis[1] = x; basis[2] = y
            if terms == 6 {
                basis[3] = x * x; basis[4] = x * y; basis[5] = y * y
            }
        }

        let sx = width > 1 ? 1.0 / Double(width - 1) : 0
        let sy = height > 1 ? 1.0 / Double(height - 1) : 0

        for ry in 0..<height {
            let y = Double(ry) * sy
            for rx in 0..<width {
                if let included, !included[ry * width + rx] { continue }
                let x = Double(rx) * sx
                fillBasis(x, y)
                let v = Double(z[ry * width + rx])
                for i in 0..<terms {
                    atb[i] += basis[i] * v
                    for j in i..<terms {
                        ata[i * terms + j] += basis[i] * basis[j]
                    }
                }
            }
        }
        // Mirror the upper triangle.
        for i in 0..<terms {
            for j in 0..<i { ata[i * terms + j] = ata[j * terms + i] }
        }

        guard let coef = solve(ata, atb, n: terms) else {
            // Degenerate fit (e.g. 1×1 scan) — fall back to the mean OF THE
            // INCLUDED positions. Averaging positions the trim just excluded
            // would silently undo the trim on exactly the scans where the
            // system is worst conditioned. // v2 S13
            let contributing = included.map { mask in
                z.indices.filter { mask[$0] }.map { z[$0] }
            } ?? z
            let source = contributing.isEmpty ? z : contributing
            let mean = source.reduce(0, +) / Float(source.count)
            return [Float](repeating: mean, count: z.count)
        }

        var out = [Float](repeating: 0, count: z.count)
        for ry in 0..<height {
            let y = Double(ry) * sy
            for rx in 0..<width {
                let x = Double(rx) * sx
                fillBasis(x, y)
                var v = 0.0
                for i in 0..<terms { v += coef[i] * basis[i] }
                out[ry * width + rx] = Float(v)
            }
        }
        return out
    }

    /// Gaussian elimination with partial pivoting for the (tiny) n×n system.
    private nonisolated static func solve(_ aIn: [Double], _ bIn: [Double], n: Int) -> [Double]? {
        var a = aIn, b = bIn
        for col in 0..<n {
            // Pivot
            var pivot = col
            for row in (col + 1)..<n where abs(a[row * n + col]) > abs(a[pivot * n + col]) {
                pivot = row
            }
            if abs(a[pivot * n + col]) < 1e-12 { return nil }
            if pivot != col {
                for k in 0..<n { a.swapAt(col * n + k, pivot * n + k) }
                b.swapAt(col, pivot)
            }
            // Eliminate below
            for row in (col + 1)..<n {
                let f = a[row * n + col] / a[col * n + col]
                if f == 0 { continue }
                for k in col..<n { a[row * n + k] -= f * a[col * n + k] }
                b[row] -= f * b[col]
            }
        }
        // Back-substitute
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var v = b[row]
            for k in (row + 1)..<n { v -= a[row * n + k] * x[k] }
            x[row] = v / a[row * n + row]
        }
        return x
    }

    // MARK: - Workflow

    /// Out-of-core origin calibration: tiled statistics establish the probe
    /// radius, a second tiled pass measures every pattern, and only the two
    /// scan-sized origin fields remain for the CPU fit.
    nonisolated static func tiledRun(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        fitFunction: OriginFitFunction = .plane,
        rscale: Float = 1.2,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws ->
        (probeRadius: Float, origin: OriginMaps, maxDP: [Float], meanDP: [Float])? {
        guard cancellation?.isCancelled != true else { return nil }
        let statsProgress: (@Sendable (Double) -> Void) = { fraction in
            progress?(0.35 * fraction)
        }
        let statistics = try await VirtualDetector.tiledDPStatistics(
            data: data, descriptor: d, maximumTileRows: maximumTileRows,
            cancellation: cancellation, progress: statsProgress
        )
        guard cancellation?.isCancelled != true else { return nil }
        let (radius, _, _) = probeSize(dp: statistics.maxDP, qy: d.qy, qx: d.qx)
        let originProgress: (@Sendable (Double) -> Void) = { fraction in
            progress?(0.35 + 0.55 * fraction)
        }
        let measured = try await VirtualDetector.tiledMeasuredOrigins(
            data: data, descriptor: d, probeRadius: radius, rscale: rscale,
            maximumTileRows: maximumTileRows, cancellation: cancellation,
            progress: originProgress
        )
        guard cancellation?.isCancelled != true else { return nil }
        let count = d.ry * d.rx
        var measuredX = [Float](repeating: 0, count: count)
        var measuredY = [Float](repeating: 0, count: count)
        for index in 0..<count {
            measuredX[index] = measured[2 * index]
            measuredY[index] = measured[2 * index + 1]
        }
        let fitted = fitOriginTrimmed(measuredX: measuredX, measuredY: measuredY,
                                      width: d.rx, height: d.ry,
                                      fitFunction: fitFunction)
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)
        return (
            radius,
            OriginMaps(width: d.rx, height: d.ry,
                       measuredX: measuredX, measuredY: measuredY,
                       fittedX: fitted.fittedX, fittedY: fitted.fittedY,
                       excludedFraction: fitted.excludedFraction,
                       robustResidual: fitted.keptResidual),
            statistics.maxDP, statistics.meanDP
        )
    }

    /// Full origin calibration on a resident cube:
    /// max DP → probe size → per-pattern measurement → smooth fit.
    /// Returns the calibration pieces plus the max/mean patterns (useful as
    /// display modes, and the max DP documents what the fit was based on).
    nonisolated static func run(cube: MTLBuffer, descriptor d: DatasetDescriptor,
                    fitFunction: OriginFitFunction = .plane,
                    rscale: Float = 1.2,
                    cancellation: AnalysisCancellationToken? = nil) throws
        -> (probeRadius: Float, origin: OriginMaps, maxDP: [Float], meanDP: [Float])? {
        guard cancellation?.isCancelled != true else { return nil }
        let engine = MetalEngine.shared
        let dims = CubeDims(d)

        let (maxDP, meanDP) = try engine.dpStatistics(cube: cube, dims: dims)
        guard cancellation?.isCancelled != true else { return nil }
        let (r, _, _) = probeSize(dp: maxDP, qy: d.qy, qx: d.qx)

        let measured = try engine.measureOrigins(
            cube: cube,
            params: OriginParams(ry: dims.ry, rx: dims.rx, qy: dims.qy, qx: dims.qx,
                                 r: r, rscale: rscale))
        guard cancellation?.isCancelled != true else { return nil }

        let n = d.ry * d.rx
        var mx = [Float](repeating: 0, count: n)
        var my = [Float](repeating: 0, count: n)
        for i in 0..<n {
            if cancellation?.isCancelled == true { return nil }
            mx[i] = measured[2 * i]
            my[i] = measured[2 * i + 1]
        }

        let fitted = fitOriginTrimmed(measuredX: mx, measuredY: my,
                                      width: d.rx, height: d.ry,
                                      fitFunction: fitFunction)
        guard cancellation?.isCancelled != true else { return nil }
        let maps = OriginMaps(width: d.rx, height: d.ry,
                              measuredX: mx, measuredY: my,
                              fittedX: fitted.fittedX, fittedY: fitted.fittedY,
                              excludedFraction: fitted.excludedFraction,
                              robustResidual: fitted.keptResidual)
        return (r, maps, maxDP, meanDP)
    }
}
