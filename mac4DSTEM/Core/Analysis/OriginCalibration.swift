//
//  OriginCalibration.swift
//  Role: The origin-calibration workflow (py4DSTEM: get_probe_size,
//        get_origin, fit_origin). GPU kernels do the per-pattern work
//        (DPStatistics.metal, OriginMeasure.metal); this file holds the
//        small CPU-side pieces — probe-size estimation on the mean pattern
//        and the smooth 2D fit of the measured origin maps — plus the
//        orchestration that ties them into a `Calibration`.
//
//  All algorithms are ports of the py4DSTEM reference implementations;
//  deviations are marked DEVIATION with a reason.
//

import CuboCore
import CuboVirtual   // FriedelOrigin and BeamstopMask are the kit's (CuboKit 0.2.0, 2026-10-16); CuboKit also exports ProbeKernel, which the app's own type of that name still shadows here
import Foundation
import Metal

package enum OriginFitFunction: String, CaseIterable, Identifiable {
    case constant = "Constant"
    case plane    = "Plane"       // py4DSTEM default
    case parabola = "Parabola"
    package var id: String { rawValue }
}

/// Why an origin calibration produced no calibration. A refusal with a
/// sentence, where until 2026-09-05 the pipeline carried on with an invented
/// 1 px probe at the geometric centre and a provenance that said "measured".
package enum OriginCalibrationError: LocalizedError, Equatable {
    /// The pattern the probe radius is measured on has no finite intensity
    /// above zero (or no mass above threshold): there is no disk to size.
    case probeNotMeasurable
    /// A vacuum scan chosen for the probe has a different detector size than the
    /// loaded dataset, so its mean pattern cannot serve as that dataset's probe. // v3.1
    case detectorMismatch(vacuum: (qx: Int, qy: Int), target: (qx: Int, qy: Int))

    package static func == (lhs: OriginCalibrationError, rhs: OriginCalibrationError) -> Bool {
        switch (lhs, rhs) {
        case (.probeNotMeasurable, .probeNotMeasurable): return true
        case let (.detectorMismatch(a, b), .detectorMismatch(c, d)): return a == c && b == d
        default: return false
        }
    }

    package var errorDescription: String? {
        switch self {
        case .probeNotMeasurable:
            return "The mean diffraction pattern has no finite intensity above zero, so no probe "
                + "radius can be measured. Check the dataset, the crop and the detector region "
                + "before calibrating the origin."
        case let .detectorMismatch(vacuum, target):
            return "The vacuum scan's detector is \(vacuum.qx)×\(vacuum.qy), but the loaded dataset's "
                + "is \(target.qx)×\(target.qy). A separate vacuum probe must be acquired on the same "
                + "detector as the data it calibrates."
        }
    }
}

/// How per-position beam origins are measured before the smooth fit. // v3.1
package nonisolated enum OriginMethod: String, Sendable, CaseIterable, Codable {
    /// The classical centre-of-mass measurement on the GPU (py4DSTEM
    /// `get_origin`). Fast, the default, and what every existing calibration used.
    case centreOfMass
    /// Friedel-symmetry self-correlation (py4DSTEM `get_origin_friedel`) with an
    /// auto-generated beamstop mask (`get_beamstop_mask`), for data whose direct
    /// beam is occluded by a beamstop — the case the centre of mass cannot serve.
    /// CPU, opt-in, and slower (an FFT per pattern); recover the origin where the
    /// classical path would be pulled by the stop's shadow.
    case friedel

    package var label: String {
        switch self {
        case .centreOfMass: return "Centre of mass"
        case .friedel: return "Friedel (beamstop-tolerant)"
        }
    }
}

/// The cube seen by `FriedelOrigin.measure`, with the two things the kit does not do: the app fills a non-finite pixel
/// by the median of its finite 8-neighbours (`DiskDetector.fillNonFinite`, D019; review row 24; DEVIATION from
/// py4DSTEM, whose FFT is NaN-poisoned, and the kit refuses nothing here but would propagate NaN), and it reports the
/// fraction of rows read so far, so a tile-wise pass moves the progress bar.
private actor FriedelFilledSource: CubeSource {
    private let base: CuboCubeSource
    nonisolated let shape: CubeShape
    private let progress: (@Sendable (Double) -> Void)?

    init(_ base: CuboCubeSource, progress: (@Sendable (Double) -> Void)?) {
        self.base = base
        self.shape = base.shape
        self.progress = progress
    }

    func readPattern(row: Int, column: Int) async throws -> CuboCore.DiffractionPattern {
        try await base.readPattern(row: row, column: column)
    }

    func readScanTile(rows: Range<Int>) async throws -> ScanTile {
        progress?(Double(rows.lowerBound) / Double(shape.scanRows))
        let tile = try await base.readScanTile(rows: rows)
        var values = tile.values
        if values.contains(where: { !$0.isFinite }) {
            let h = shape.detectorRows, w = shape.detectorColumns
            values.withUnsafeMutableBufferPointer { buf in
                for k in 0..<tile.positionCount {
                    _ = DiskDetector.fillNonFinite(buf.baseAddress! + k * h * w, width: w, height: h, rowStride: w)
                }
            }
            return try ScanTile(shape: shape, rows: rows, values: values)
        }
        return tile
    }
}

package nonisolated enum OriginCalibration {

    // MARK: - Probe size (py4DSTEM get_probe_size)

    /// Estimate the central-disk radius and position from one diffraction
    /// pattern (ideally the max or mean pattern): py4DSTEM's get_probe_size,
    /// which is CuboKit's `ProbeSize.estimate` (a step-for-step float64 port,
    /// bit for bit with py4DSTEM on the same pattern; C2, 2026-10-15). This
    /// function keeps the app's inputs and refusals around it:
    ///
    /// nil when nothing can be measured: no finite pixel above zero, or no
    /// mass above the chosen threshold (the kit's `probeNotFound`). Until
    /// 2026-09-05 both cases returned `(1, qx/2, qy/2)` — a number
    /// indistinguishable from a measurement (`docs/open-items.md`, "Origin-fit
    /// gate", hole (a)).
    ///
    /// DEVIATION from py4DSTEM: `np.max` propagates a NaN, so one bad pixel
    /// empties every threshold mask there and the result is r = 0 with a NaN
    /// centre. Here a NaN or an infinity is one dead pixel, neither a refusal
    /// nor a contribution: it enters the kit as 0, which is below every
    /// threshold (all are at least 1 % of a positive maximum) and adds nothing
    /// to the centre of mass, the same as leaving it out. A pattern with no
    /// positive finite pixel is refused here, where the kit would estimate
    /// from a non-positive maximum. The result is Float, as every caller has
    /// it; the estimate itself is Double.
    package nonisolated static func probeSize(dp: [Float], qy: Int, qx: Int,
                          threshLower: Double = 0.01, threshUpper: Double = 0.99,
                          n: Int = 100) -> (r: Float, x0: Float, y0: Float)? {
        guard dp.count == qy * qx, qy > 0, qx > 0 else { return nil }
        var dpMax: Float = 0
        for v in dp where v.isFinite && v > dpMax { dpMax = v }
        guard dpMax > 0 else { return nil }
        let pattern = DetectorImage(detectorRows: qy, detectorColumns: qx,
                                    values: dp.map { $0.isFinite ? Double($0) : 0 }, path: .cpu)
        guard let estimate = try? ProbeSize.estimate(pattern, lowerThreshold: threshLower,
                                                     upperThreshold: threshUpper, count: n) else { return nil }
        return (Float(estimate.radius), Float(estimate.centerColumn), Float(estimate.centerRow))
    }

    // MARK: - Origin fit (py4DSTEM fit_origin)

    /// Fit the measured origin maps with a smooth 2D function and return the
    /// fitted maps evaluated at every scan position. Scan coordinates are
    /// normalized to [0, 1] before fitting for numerical conditioning.
    package nonisolated static func fitOrigin(measuredX: [Float], measuredY: [Float],
                          width: Int, height: Int,
                          fitFunction: OriginFitFunction = .plane)
        -> (fittedX: [Float], fittedY: [Float]) {
        (fit2D(measuredX, width: width, height: height, function: fitFunction),
         fit2D(measuredY, width: width, height: height, function: fitFunction))
    }

    /// `fitOrigin` restricted to a subset of scan positions, evaluated
    /// everywhere. Exposed (rather than left as `fit2D`'s private parameter)
    /// so the trimmed fit's own uncertainty can be measured against the SHIPPED
    /// fitter instead of a second copy in a harness — the 2026-08-17 lesson
    /// about lists that drift applies to estimators too. // v2 S13
    package nonisolated static func fitOrigin(
        measuredX: [Float], measuredY: [Float],
        width: Int, height: Int,
        fitFunction: OriginFitFunction = .plane,
        included: [Bool]
    ) -> (fittedX: [Float], fittedY: [Float]) {
        (fit2D(measuredX, width: width, height: height, function: fitFunction, included: included),
         fit2D(measuredY, width: width, height: height, function: fitFunction, included: included))
    }

    // MARK: - Robust origin fit (v2 S13)

    /// Outcome of an iteratively-trimmed origin fit.
    package struct TrimmedFit: Sendable {
        package var fittedX: [Float]
        package var fittedY: [Float]
        /// Positions the final round kept. `false` = the position's measurement
        /// was excluded from the fit, NOT that it has no fitted origin — every
        /// position gets one, evaluated from the surface the kept positions fit.
        package var kept: [Bool]
        /// RMS(measured − fitted) over the KEPT positions only.
        package var keptResidual: Float
        /// RMS(measured − fitted) over ALL positions, which is what the shipped
        /// gate reads. Recorded because it is NOT the same number and comparing
        /// `keptResidual` to a full-scan threshold is circular — trimming
        /// removes the largest residuals by construction, so RMS(kept) is
        /// guaranteed to fall (S12 §1.2, measured: 2.19 px kept vs 18.47 px
        /// full-scan on `Particle_1`).
        package var fullScanResidual: Float
        /// nil when there are no positions at all. The first version clamped
        /// the denominator with `max(kept.count, 1)`, which turned an empty
        /// scan into a confident **1.0 — "excluded 100% of positions as
        /// outliers"** for a scan with nothing to exclude (Gate B,
        /// 2026-08-28). A NaN would have been wrong too; the honest answer is
        /// that the question does not apply.
        package var excludedFraction: Float? {
            guard !kept.isEmpty else { return nil }
            return 1 - Float(kept.filter { $0 }.count) / Float(kept.count)
        }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(fittedX: [Float], fittedY: [Float], kept: [Bool], keptResidual: Float, fullScanResidual: Float) {
            self.fittedX = fittedX
            self.fittedY = fittedY
            self.kept = kept
            self.keptResidual = keptResidual
            self.fullScanResidual = fullScanResidual
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
    /// (`../_archive/mac4DSTEM/docs/q-calibration-design.md` §1.2), so the app and the diagnostics
    /// that justified it trim identically. 1.4826 is the MAD→σ consistency
    /// factor for a normal distribution.
    ///
    /// **Where these numbers come from, stated because a reader cannot rerun
    /// them here:** every figure above is from `../_archive/mac4DSTEM/tools/origin-fit-diagnostics`,
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
    package nonisolated static func fitOriginTrimmed(
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
            // The masked fit: the kept positions only, evaluated everywhere (a constant is the kept mean).
            fittedX = fit2D(measuredX, width: width, height: height, function: fitFunction, included: mask)
            fittedY = fit2D(measuredY, width: width, height: height, function: fitFunction, included: mask)
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

    /// The least-squares surface of one measured map (constant, plane or parabola over the scan), evaluated at every
    /// position: CuboKit's `OriginFit.fit` (Householder QR in Double on [0, 1] coordinates, py4DSTEM's `fit_2D`).
    ///
    /// `included`, when given, restricts the fit to the marked scan positions; the surface is still evaluated
    /// everywhere, which is what makes a trimmed refit usable — the excluded positions get a fitted origin derived from
    /// the positions that measured well. // v2 S13
    ///
    /// Kept in the app, because the kit does not do it: a degenerate fit (a scan one position wide, or fewer included
    /// positions than the model has terms) falls back to the mean OF THE INCLUDED positions, where the kit would
    /// project onto the design's column space. Averaging positions the trim just excluded would silently undo the trim
    /// on exactly the scans where the system is worst conditioned. // v2 S13
    ///
    /// Differences from the app's former normal-equation solver, which the kit makes: a non-finite included measurement
    /// is left out of the fit instead of making every fitted value NaN, and a rank-deficient but sufficiently large
    /// included set (three collinear positions for a plane) is projected where the app averaged.
    private nonisolated static func fit2D(_ z: [Float], width: Int, height: Int, function: OriginFitFunction,
                                          included: [Bool]? = nil) -> [Float] {
        let used = z.indices.filter { included?[$0] ?? true }
        let source = used.isEmpty ? Array(z.indices) : used
        func meanSurface() -> [Float] {
            guard let m = try? OriginFit.fit(source.map { Double(z[$0]) }, rows: source.count, columns: 1, model: .constant),
                  let value = m.first else { return [Float](repeating: .nan, count: z.count) }
            return [Float](repeating: Float(value), count: z.count)
        }
        let model: OriginFitModel
        let terms: Int
        switch function {
        case .constant: return meanSurface()
        case .plane: model = .plane; terms = 3
        case .parabola: model = .parabola; terms = 6
        }
        guard width > 1, height > 1, used.count >= terms else { return meanSurface() }
        var values = [Double](repeating: .nan, count: z.count)
        for index in used { values[index] = Double(z[index]) }
        guard let surface = try? OriginFit.fit(values, rows: height, columns: width, model: model) else { return meanSurface() }
        return surface.map { Float($0) }
    }

    // MARK: - Workflow

    /// Out-of-core origin calibration: tiled statistics establish the probe
    /// radius, a second tiled pass measures every pattern, and only the two
    /// scan-sized origin fields remain for the CPU fit.
    ///
    /// `windowSensitivityPixels` (C14, lane Q 2026-09-30) is a DISCLOSURE, not a
    /// verdict: how far the refine step's answer moves between the shipped
    /// window and a wide one, on a strided sample. nil when it could not be
    /// measured. Nothing gates on it; see `windowSensitivityPixels(data:…)`.
    @concurrent
    package static func tiledRun(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        fitFunction: OriginFitFunction = .plane,
        originMethod: OriginMethod = .centreOfMass,
        rscale: Float = 1.2,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws ->
        (probeRadius: Float, origin: OriginMaps, maxDP: [Float], meanDP: [Float],
         windowSensitivityPixels: Float?)? {
        guard cancellation?.isCancelled != true else { return nil }
        let statsProgress: (@Sendable (Double) -> Void) = { fraction in
            progress?(0.35 * fraction)
        }
        let statistics = try await VirtualDetector.tiledDPStatistics(
            data: data, descriptor: d, maximumTileRows: maximumTileRows,
            cancellation: cancellation, progress: statsProgress
        )
        guard cancellation?.isCancelled != true else { return nil }
        // DEVIATION from py4DSTEM's origin path (process/calibration/origin.py:268
        // feeds get_probe_size the MAX pattern): the mean is fed instead, which is
        // what py4DSTEM's own get_probe_size docstring recommends ("a position
        // averaged ... DP works best"). Measured 2026-09-01 on real data
        // (../_archive/mac4DSTEM/tools/origin-fit-diagnostics probe-size): the max-union counts every
        // Bragg disk seen anywhere in the scan as probe area — SPED_MgO reads
        // 14.1 px from the max against 5.4 from the mean and ~3 from
        // substrate-only patterns, and the SAME specimen over a 4x larger scan
        // reads 19.1, which a per-pattern property cannot do. The mean's own
        // failure mode is bounded (descan blur + amorphous background, recorded
        // in docs/open-items.md); the max's grows with scan area and
        // diffraction strength. A single low-sum pattern is NOT a safe input:
        // Particle_1's minimum-sum position returns 31.8 px.
        guard let probe = probeSize(dp: statistics.meanDP, qy: d.qy, qx: d.qx) else {
            throw OriginCalibrationError.probeNotMeasurable
        }
        let radius = probe.r
        let originProgress: (@Sendable (Double) -> Void) = { fraction in
            progress?(0.35 + 0.55 * fraction)
        }
        let measured: [Float]
        switch originMethod {
        case .centreOfMass:
            measured = try await VirtualDetector.tiledMeasuredOrigins(
                data: data, descriptor: d, probeRadius: radius, rscale: rscale,
                maximumTileRows: maximumTileRows, cancellation: cancellation,
                progress: originProgress
            )
        case .friedel:
            // Auto-generate the beamstop mask from the mean DP (py4DSTEM
            // get_beamstop_mask; true = beamstop) and invert it for
            // get_origin_friedel (which wants true in the pattern). The kit refuses a NaN mean pattern; the
            // app's neighbour-median fill is applied first, as it is to every pattern.
            var meanDP = statistics.meanDP
            if meanDP.contains(where: { !$0.isFinite }) {
                meanDP.withUnsafeMutableBufferPointer {
                    _ = DiskDetector.fillNonFinite($0.baseAddress!, width: d.qx, height: d.qy, rowStride: d.qx)
                }
            }
            let patternMask = try BeamstopMask.make(from: DetectorImage(
                detectorRows: d.qy, detectorColumns: d.qx, values: meanDP.map(Double.init), path: .cpu)).map { !$0 }
            measured = try await friedelMeasuredOrigins(
                data: data, descriptor: d, mask: patternMask,
                maximumTileRows: maximumTileRows, cancellation: cancellation,
                progress: originProgress
            )
        }
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
        // A disclosure must never cost the calibration it describes: an error
        // here (a GPU hiccup, an unreadable pattern) leaves the quantity unread.
        // Only the centre-of-mass refine has a window; the Friedel path has none.
        var sensitivity: Float?
        if originMethod == .centreOfMass {
            sensitivity = try? await windowSensitivityPixels(
                data: data, descriptor: d, probeRadius: radius, shippedScale: rscale)
        }
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)
        return (
            radius,
            OriginMaps(width: d.rx, height: d.ry,
                       measuredX: measuredX, measuredY: measuredY,
                       fittedX: fitted.fittedX, fittedY: fitted.fittedY,
                       excludedFraction: fitted.excludedFraction,
                       robustResidual: fitted.keptResidual,
                       originValidity: fitted.kept),
            statistics.maxDP, statistics.meanDP,
            sensitivity
        )
    }

    // MARK: - Window sensitivity (C14, lane Q 2026-09-30)

    /// The refine window's two readings, in probe radii: the shipped one and a
    /// wide one. 2.5 is the S14-D registration's far end
    /// (`../_archive/mac4DSTEM/docs/archive/v4/s14d-origin-refine-gateD-2026-09-30.md`): wide enough to
    /// clear a ring outside the core (k ≈ 2 already does on the ringed fixtures),
    /// not so wide that a compact cube's scatter enters.
    package nonisolated static let shippedWindowScale: Float = 1.2
    package nonisolated static let wideWindowScale: Float = 2.5
    package nonisolated static let windowSensitivitySampleLimit = 200

    /// The sample is one Metal buffer of `count × qy × qx` floats on EVERY
    /// origin calibration: 52 MB at 256², 3.4 GB at 2048² with 200 positions
    /// (refuter, 2026-09-30). Bounded here so a large detector gets fewer
    /// positions, never a larger buffer.
    package nonisolated static let windowSensitivitySampleBudgetBytes = 256 << 20

    /// Scan indices of the strided sample: every n-th position, n the smallest
    /// step that keeps the count at or under `limit` — and, when `patternBytes`
    /// is given, under `budgetBytes / patternBytes` (at least one position).
    /// Pure, so both bounds are testable without a dataset.
    package nonisolated static func windowSensitivitySampleIndices(
        total: Int, limit: Int = windowSensitivitySampleLimit,
        patternBytes: Int = 0, budgetBytes: Int = windowSensitivitySampleBudgetBytes
    ) -> [Int] {
        guard total > 0, limit > 0 else { return [] }
        let byBytes = patternBytes > 0 ? max(1, budgetBytes / patternBytes) : limit
        let bound = min(limit, byBytes)
        let step = (total + bound - 1) / bound
        return Array(stride(from: 0, to: total, by: step))
    }

    /// Median distance (detector pixels) between the origin the refine step
    /// finds at the caller's window (`shippedScale`, 1.2 in the app) and at a
    /// wide one (k = 2.5), over a strided sample of at most 200 scan positions
    /// bounded by `windowSensitivitySampleBudgetBytes`. **A quantity, not a
    /// verdict** — nothing gates on it (owner, ADR 050: no fixed window ships).
    ///
    /// Why it exists: the refine is an iterated centre of mass inside a window
    /// `max(k r, r + 1.5)`; on a probe with a ring outside its core (the S14-D
    /// bullseye) that window cuts the ring, the true centre is an unstable fixed
    /// point, and the answer walks — 3.87 px between k = 1.2 and 2 on
    /// bullseye_sim, against ≤ 0.03 px on six compact cubes
    /// (`s14d-origin-refine-gateD-2026-09-30.md`, §10). Compact probes do not
    /// care which window they get; ringed ones do, and this reads which kind the
    /// scan is without choosing a window for it.
    ///
    /// Both readings come from the same GPU kernel on the same gathered
    /// patterns, so the only difference between them is the window.
    package nonisolated static func windowSensitivityPixels(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        probeRadius: Float,
        shippedScale: Float = shippedWindowScale
    ) async throws -> Float? {
        let patternPixels = d.qy * d.qx
        let indices = windowSensitivitySampleIndices(
            total: d.ry * d.rx, patternBytes: patternPixels * MemoryLayout<Float>.stride)
        guard !indices.isEmpty, probeRadius.isFinite, probeRadius > 0,
              shippedScale.isFinite, shippedScale > 0 else { return nil }
        var gathered = [Float]()
        gathered.reserveCapacity(indices.count * patternPixels)
        for index in indices {
            let pattern = try await data.pattern(ry: index / d.rx, rx: index % d.rx)
            gathered.append(contentsOf: pattern.pixels)
        }
        let engine = MetalEngine.shared
        guard let buffer = engine.device.makeBuffer(
            bytes: gathered, length: gathered.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }
        func measure(_ scale: Float) throws -> [Float] {
            try engine.measureOrigins(
                cube: buffer,
                params: OriginParams(ry: 1, rx: UInt32(indices.count),
                                     qy: UInt32(d.qy), qx: UInt32(d.qx),
                                     r: probeRadius, rscale: scale))
        }
        let shipped = try measure(shippedScale)
        let wide = try measure(wideWindowScale)
        var distances: [Float] = []
        distances.reserveCapacity(indices.count)
        for i in 0..<indices.count {
            let dx = wide[2 * i] - shipped[2 * i], dy = wide[2 * i + 1] - shipped[2 * i + 1]
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance.isFinite { distances.append(distance) }
        }
        return distances.isEmpty ? nil : median(distances)
    }

    /// Per-position origins by Friedel self-correlation (py4DSTEM
    /// `get_origin_friedel`) through CuboVirtual's `FriedelOrigin.measure`, the CPU analogue of
    /// `VirtualDetector.tiledMeasuredOrigins`. Returns interleaved `[x0, y0, …]` in the SAME convention that path
    /// does (`x0` the detector column, `y0` the detector row; the kit's row is py4DSTEM's qx0 = app y), so it feeds
    /// `fitOriginTrimmed` identically. `mask` is `true` in the pattern (already inverted from `BeamstopMask`). Slower
    /// than the GPU path; opt-in for beamstop data. The pass walks the cube in tiles of at most the app's tile and of
    /// about a sixteenth of the scan, so the bar moves within a long tile; the kit runs each tile across the cores
    /// and checks cancellation between tiles.
    private nonisolated static func friedelMeasuredOrigins(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        mask: [Bool],
        maximumTileRows: Int?,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [Float] {
        let appTileRows = await data.scanTileRows(maximumRows: maximumTileRows)
        let rows = max(1, min(appTileRows, (d.ry + 15) / 16))
        let base = try CuboCubeSource(data, descriptor: d, cancellation: cancellation)
        let source = FriedelFilledSource(base, progress: progress)
        let map = try await FriedelOrigin.measure(of: source, mask: mask, tiling: .rows(rows))
        guard cancellation?.isCancelled != true else { throw CancellationError() }
        progress?(1)
        let count = d.ry * d.rx
        var output = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            output[2 * i] = Float(map.column.values[i])       // measured X = detector column
            output[2 * i + 1] = Float(map.row.values[i])      // measured Y = detector row
        }
        return output
    }

    /// Build a probe kernel from a SEPARATE vacuum scan — the fix for a sample
    /// with no vacuum region in frame (py4DSTEM's `Probe.from_vacuum_data`
    /// shape, but the vacuum is its own file): the vacuum scan's MEAN
    /// diffraction pattern is the probe. Refuses when the vacuum detector
    /// differs from the dataset it will calibrate. Returns the kernel plus the
    /// mean DP and measured size so the caller can record the probe reference. // v3.1
    package nonisolated static func vacuumProbeKernel(
        vacuum: FourDArray,
        vacuumDescriptor v: DatasetDescriptor,
        targetDescriptor t: DatasetDescriptor,
        mode: ProbeKernelMode = .flat,
        probePath: String? = nil,
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> (kernel: ProbeKernel, meanDP: [Float], radius: Float, centreX: Float, centreY: Float) {
        guard v.qy == t.qy, v.qx == t.qx else {
            throw OriginCalibrationError.detectorMismatch(vacuum: (v.qx, v.qy), target: (t.qx, t.qy))
        }
        let statistics = try await VirtualDetector.tiledDPStatistics(
            data: vacuum, descriptor: v, cancellation: cancellation)
        guard let size = probeSize(dp: statistics.meanDP, qy: v.qy, qx: v.qx) else {
            throw OriginCalibrationError.probeNotMeasurable
        }
        let pattern = DiffractionPattern(qy: v.qy, qx: v.qx, pixels: statistics.meanDP)
        guard let kernel = ProbeKernel.measured(
            pattern: pattern, originX: size.x0, originY: size.y0, radius: size.r,
            mode: mode, source: .vacuumScan, probePath: probePath
        ) else {
            throw OriginCalibrationError.probeNotMeasurable
        }
        return (kernel, statistics.meanDP, size.r, size.x0, size.y0)
    }

    /// Full origin calibration on a resident cube:
    /// mean DP → probe size → per-pattern measurement → smooth fit.
    /// Returns the calibration pieces plus the max/mean patterns (useful as
    /// display modes, and the mean DP documents what the fit was based on).
    /// NOTE (Gate B, 2026-09-01): this variant has no callers in the repo —
    /// `ProbeSizeTests` pins its mean-pattern measurement anyway, so a future
    /// caller resurrects the honest statistic rather than whatever the dead
    /// code happened to feed. Deleting it instead is an owner option.
    package nonisolated static func run(cube: MTLBuffer, descriptor d: DatasetDescriptor,
                    fitFunction: OriginFitFunction = .plane,
                    rscale: Float = 1.2,
                    cancellation: AnalysisCancellationToken? = nil) throws
        -> (probeRadius: Float, origin: OriginMaps, maxDP: [Float], meanDP: [Float])? {
        guard cancellation?.isCancelled != true else { return nil }
        let engine = MetalEngine.shared
        let dims = CubeDims(d)

        let (maxDP, meanDP) = try engine.dpStatistics(cube: cube, dims: dims)
        guard cancellation?.isCancelled != true else { return nil }
        // Same DEVIATION as tiledRun above: the mean, not the max — see the
        // measurement note there.
        guard let probe = probeSize(dp: meanDP, qy: d.qy, qx: d.qx) else {
            throw OriginCalibrationError.probeNotMeasurable
        }
        let r = probe.r

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
                              robustResidual: fitted.keptResidual,
                              originValidity: fitted.kept)
        return (r, maps, maxDP, meanDP)
    }
}
