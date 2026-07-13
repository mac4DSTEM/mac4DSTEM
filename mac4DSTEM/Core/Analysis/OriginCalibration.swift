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

    /// Least-squares fit of z(x, y) with polynomial basis
    ///   terms == 3: [1, x, y]                       (plane)
    ///   terms == 6: [1, x, y, x², xy, y²]           (parabola)
    /// solved via the normal equations; the systems are tiny (≤ 6×6).
    private nonisolated static func fit2D(_ z: [Float], width: Int, height: Int, terms: Int) -> [Float] {
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
            // Degenerate fit (e.g. 1×1 scan) — fall back to the mean.
            let mean = z.reduce(0, +) / Float(z.count)
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
        let fitted = fitOrigin(measuredX: measuredX, measuredY: measuredY,
                               width: d.rx, height: d.ry,
                               fitFunction: fitFunction)
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)
        return (
            radius,
            OriginMaps(width: d.rx, height: d.ry,
                       measuredX: measuredX, measuredY: measuredY,
                       fittedX: fitted.fittedX, fittedY: fitted.fittedY),
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

        let (fx, fy) = fitOrigin(measuredX: mx, measuredY: my,
                                 width: d.rx, height: d.ry,
                                 fitFunction: fitFunction)
        guard cancellation?.isCancelled != true else { return nil }
        let maps = OriginMaps(width: d.rx, height: d.ry,
                              measuredX: mx, measuredY: my,
                              fittedX: fx, fittedY: fy)
        return (r, maps, maxDP, meanDP)
    }
}
