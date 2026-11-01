//
//  OriginCalibration.swift
//  Role: The origin-calibration workflow (py4DSTEM: get_probe_size,
//        get_origin, fit_origin). The per-pattern work is CuboKit's
//        (`OriginMeasurement`'s iterated-window estimator, Metal or CPU; the max and mean
//        patterns are CuboKit's too); this file holds the
//        small CPU-side pieces — probe-size estimation on the mean pattern
//        and the smooth 2D fit of the measured origin maps — plus the
//        orchestration that ties them into a `Calibration`.
//
//  All algorithms are ports of the py4DSTEM reference implementations;
//  deviations are marked DEVIATION with a reason.
//

import CuboCore
import struct CuboBragg.BraggDetector   // the neighbour-median fill
import CuboVirtual   // FriedelOrigin and BeamstopMask are the kit's (CuboKit 0.2.0, 2026-10-16); CuboKit also exports ProbeKernel, which the app's own type of that name still shadows here
import Foundation

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
/// by the median of its finite 8-neighbours (`BraggDetector.fillNonFinite`, D019; review row 24; DEVIATION from
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
            for k in 0..<tile.positionCount {
                let range = (k * h * w)..<((k + 1) * h * w)
                guard values[range].contains(where: { !$0.isFinite }) else { continue }
                var pattern = Array(values[range])
                _ = BraggDetector.fillNonFinite(&pattern, rows: h, columns: w)
                values.replaceSubrange(range, with: pattern)
            }
            return try ScanTile(shape: shape, rows: rows, values: values)
        }
        return tile
    }
}

package nonisolated enum OriginCalibration {

    // MARK: - Probe radius source

    /// Which pattern the ORIGIN WINDOW's radius of an origin calibration is measured on (`tiledRun`'s `probeRadius`). The probe radius
    /// stored in the calibration is a separate number, measured on the mean pattern as py4DSTEM's `DataCube.get_probe_size` does
    /// (`tiledRun`'s `meanProbeRadius`), and only when no file, session or manual value stands (`AppState.calibrateOrigin`).
    ///
    /// `.maxPattern` is py4DSTEM's `dp_max` default (process/calibration/origin.py: `get_origin` feeds `get_probe_size` the
    /// maximum pattern) and CuboKit's `OriginMeasurement`; owner decision 2026-10-19 (`docs/open-items.md`).
    ///
    /// `.meanPattern` is the app's former default, kept as a named option. DEVIATION from py4DSTEM: measured 2026-09-01 on
    /// real data, the max-union counts every Bragg disk seen anywhere in the scan as probe area (SPED_MgO reads 14.1 px from
    /// the max against 5.4 from the mean and ~3 from substrate-only patterns, and the same specimen over a 4x larger scan
    /// reads 19.1, which a per-pattern property cannot do); the mean's own failure mode is bounded (descan blur plus
    /// amorphous background). A single low-sum pattern is not a safe input: Particle_1's minimum-sum position returns 31.8 px.
    package enum ProbeRadiusSource: Sendable, Hashable {
        case maxPattern
        case meanPattern

        func pattern(max: [Float], mean: [Float]) -> [Float] { self == .maxPattern ? max : mean }

        /// The lineage key an origin run records its source under (`calibration_origin` parameters).
        package static let lineageKey = "probe_radius_source"

        /// "max" or "mean": the value recorded under `lineageKey`. A node written without a measurement (a manual
        /// centre, a restored fit) records "unknown"; a recording without the key predates the max default (2026-10-20)
        /// and was measured on the mean.
        package var lineageValue: String { self == .maxPattern ? "max" : "mean" }
    }

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
    /// (archived `docs/q-calibration-design.md` §1.2), so the app and the diagnostics
    /// that justified it trim identically. 1.4826 is the MAD→σ consistency
    /// factor for a normal distribution.
    ///
    /// **Where these numbers come from, stated because a reader cannot rerun
    /// them here:** every figure above is from archived `tools/origin-fit-diagnostics`,
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
        // A mismatch used to return `fittedX = measuredX` (n) beside `fittedY = measuredY` (m != n), an `OriginMaps`
        // whose two fitted arrays differ in length, reading as a clean fully-supported fit (Gate B, 2026-08-28). Return
        // a degenerate-but-consistent empty pair instead; so for a map the kit refuses (no finite position, a shape
        // that is not width * height).
        let empty = TrimmedFit(fittedX: [], fittedY: [], kept: [], keptResidual: .nan, fullScanResidual: .nan)
        guard count > 0, measuredY.count == count else { return empty }
        let model: OriginFitModel
        switch fitFunction {
        case .constant: model = .constant
        case .plane: model = .plane
        case .parabola: model = .parabola
        }
        // The fit is CuboKit's `OriginFit.fitTrimmed` (0.6.0; Double, Householder QR, py4DSTEM's `fit_2D` surfaces); the app's
        // Float copy of the loop is gone. The Float surfaces below are the kit's Double ones rounded.
        guard let fit = try? OriginFit.fitTrimmed(
            originRow: measuredX.map(Double.init), originColumn: measuredY.map(Double.init),
            rows: height, columns: width, model: model, trimSigma: Double(trimSigma), rounds: rounds) else { return empty }
        return TrimmedFit(
            fittedX: fit.fittedRow.map(Float.init), fittedY: fit.fittedColumn.map(Float.init), kept: fit.kept,
            keptResidual: Float(fit.keptResidual), fullScanResidual: Float(fit.fullScanResidual))
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
        probeSource: ProbeRadiusSource = .maxPattern,
        maximumTileRows: Int? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws ->
        (probeRadius: Float, meanProbeRadius: Float?, origin: OriginMaps, maxDP: [Float], meanDP: [Float],
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
        guard let probe = probeSize(dp: probeSource.pattern(max: statistics.maxDP, mean: statistics.meanDP),
                                    qy: d.qy, qx: d.qx) else {
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
            measured = try await friedelMeasuredOrigins(
                data: data, descriptor: d, mask: friedelPatternMask(meanDP: statistics.meanDP, descriptor: d),
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
        // The origin gate's bias test reads this; only the centre-of-mass refine has a window.
        var pull: Float?
        if originMethod == .centreOfMass, !fitted.fittedX.isEmpty, fitted.fittedY.count == fitted.fittedX.count {
            // Summed in Double: a Float sum over a large scan loses the fraction (512 x 512 positions near 127 px).
            let n = Double(fitted.fittedX.count)
            let centre = (x: Float(fitted.fittedX.reduce(0.0) { $0 + Double($1) } / n),
                          y: Float(fitted.fittedY.reduce(0.0) { $0 + Double($1) } / n))
            pull = windowPull(meanDP: statistics.meanDP, qy: d.qy, qx: d.qx, centre: centre,
                              windowRadius: originWindowRadius(probeRadius: radius, radiusScale: rscale))?.boundPixels
        }
        // A beam stop over the direct beam: the centre-of-mass maps are refused (`Calibration.originBeamStopIsAcceptable`)
        // and the Friedel origin is tried on the same cube, so the refusal can say whether that method fits this scan.
        // Its own failure (a mask with no pattern left, say) leaves the fallback unknown, which is not offered.
        var stopCoversBeam: Bool?
        var fallbackResidual: Float?
        if originMethod == .centreOfMass, let stop = beamStop(meanDP: statistics.meanDP, qy: d.qy, qx: d.qx) {
            stopCoversBeam = stop.detected
            if stop.detected {
                fallbackResidual = try? await friedelFallbackResidual(
                    data: data, descriptor: d, meanDP: statistics.meanDP, fitFunction: fitFunction,
                    maximumTileRows: maximumTileRows, cancellation: cancellation)
            }
        }
        guard cancellation?.isCancelled != true else { return nil }
        progress?(1)
        // The calibration's probe radius: py4DSTEM's `DataCube.get_probe_size` default is the MEAN pattern (`radius` above is
        // `get_origin`'s working radius, the origin window's). nil when the mean pattern has no measurable probe.
        let meanRadius = probeSize(dp: statistics.meanDP, qy: d.qy, qx: d.qx)?.r
        return (
            radius,
            meanRadius,
            OriginMaps(width: d.rx, height: d.ry,
                       measuredX: measuredX, measuredY: measuredY,
                       fittedX: fitted.fittedX, fittedY: fitted.fittedY,
                       excludedFraction: fitted.excludedFraction,
                       robustResidual: fitted.keptResidual,
                       originValidity: fitted.kept,
                       windowPullBoundPixels: pull,
                       beamStopCoversBeam: stopCoversBeam,
                       friedelFallbackResidualPixels: fallbackResidual),
            statistics.maxDP, statistics.meanDP,
            sensitivity
        )
    }

    // MARK: - Beam stop (2026-10-31)

    /// What the mean pattern says about a beam stop over the direct beam: a dark disk at the pattern's centre of mass
    /// with bright surroundings. Under a stop the centre-of-mass refine measures the centre of whatever is left around
    /// the stop (the halo, cut by the stop's arm), not the beam, and the window pull cannot see it: the window holds no
    /// beam at all, only the bright rim, which the pull counts as beam.
    package struct BeamStop: Sendable, Equatable {
        /// The mean pattern's centre of mass (detector column, row), where the rings are read about.
        package var centreX: Float
        package var centreY: Float
        /// Mean intensity within 2 px of the centre over the mean of the brightest 1 px ring about it: about 1 for a
        /// direct beam (the centre is the brightest ring), near 0 under a stop.
        package var centreContrast: Float
        /// The dark disk's radius: the first 1 px ring, going out, whose mean reaches `rimFraction` of the brightest
        /// ring's, in detector pixels (its inner edge). 0 for a direct beam. A tenth, not the centre's quarter: the
        /// brightest ring can be a ring of Bragg disks well outside the stop, brighter than the halo at the stop's
        /// edge (on the planted cube the halo there is about a quarter of it, and a quarter put the rim at 12 px, past
        /// the 7.5 px stop).
        package var darkRadius: Int
        /// The surroundings close round the dark disk: the fraction of 16 sectors of the rim (the rings `darkRadius`
        /// to `darkRadius + 2`) whose mean is at least half the rim's. All but the arm under a stop; two bright regions
        /// either side of a dark middle read about half or less.
        package var coverage: Float

        package static let contrastLimit: Float = 0.25
        package static let rimFraction: Float = 0.1
        package static let minimumDarkRadius = 2
        package static let minimumCoverage: Float = 0.6

        /// A dark centre at least 2 px in radius, closed round by a bright rim.
        package var detected: Bool {
            centreContrast < Self.contrastLimit && darkRadius >= Self.minimumDarkRadius && coverage >= Self.minimumCoverage
        }
    }

    /// Reads `BeamStop` on the mean pattern (non-finite pixels filled by the neighbour median, negative ones count as 0). The rings are 1 px bins of the
    /// distance from the centre of mass, out to the nearest detector edge so every ring is whole. nil when there is no
    /// positive intensity or the centre is within 4 px of an edge.
    package nonisolated static func beamStop(meanDP: [Float], qy: Int, qx: Int) -> BeamStop? {
        guard meanDP.count == qy * qx, qy > 0, qx > 0 else { return nil }
        // A non-finite pixel is filled by its neighbours first, as for every pattern the app measures: a saturated core
        // flagged NaN would otherwise read as a dark centre inside a bright rim, a stop that is not there. The fill is one
        // pass of 8-neighbours, so a NaN core wider than about 1 px keeps its middle at 0 and can still read as a stop.
        var filled = meanDP
        if filled.contains(where: { !$0.isFinite }) {
            _ = BraggDetector.fillNonFinite(&filled, rows: qy, columns: qx)
        }
        let v = filled.map { $0.isFinite ? Double(max($0, 0)) : 0 }
        var total = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<qy { for x in 0..<qx {
            let w = v[y * qx + x]
            total += w; sx += w * Double(x); sy += w * Double(y)
        } }
        guard total > 0 else { return nil }
        let cx = sx / total, cy = sy / total
        let reach = Int(min(min(cx, Double(qx - 1) - cx), min(cy, Double(qy - 1) - cy)).rounded(.down))
        guard reach >= 4 else { return nil }
        var ringSum = [Double](repeating: 0, count: reach), ringCount = ringSum
        var inner = 0.0, innerCount = 0.0
        for y in 0..<qy { for x in 0..<qx {
            let r = hypot(Double(x) - cx, Double(y) - cy)
            if r < 2 { inner += v[y * qx + x]; innerCount += 1 }
            let bin = Int(r)
            if bin < reach { ringSum[bin] += v[y * qx + x]; ringCount[bin] += 1 }
        } }
        let profile = (0..<reach).map { ringCount[$0] > 0 ? ringSum[$0] / ringCount[$0] : 0 }
        let ringMean = profile.max() ?? 0
        guard ringMean > 0, innerCount > 0 else { return nil }
        let dark = profile.firstIndex { $0 >= Double(BeamStop.rimFraction) * ringMean } ?? 0
        let sectors = 16
        var sectorSum = [Double](repeating: 0, count: sectors), sectorCount = sectorSum
        var annulus = 0.0, annulusCount = 0.0
        for y in 0..<qy { for x in 0..<qx {
            let dx = Double(x) - cx, dy = Double(y) - cy
            let bin = Int(hypot(dx, dy))
            guard bin >= dark, bin <= min(dark + 2, reach - 1) else { continue }   // whole rings only
            let angle = atan2(dy, dx) + Double.pi   // 0 ... 2 pi
            let s = min(sectors - 1, Int(angle / (2 * Double.pi) * Double(sectors)))
            sectorSum[s] += v[y * qx + x]; sectorCount[s] += 1
            annulus += v[y * qx + x]; annulusCount += 1
        } }
        let annulusMean = annulus / max(annulusCount, 1)
        var bright = 0
        for s in 0..<sectors where sectorCount[s] > 0 && sectorSum[s] / sectorCount[s] >= 0.5 * annulusMean { bright += 1 }
        return BeamStop(centreX: Float(cx), centreY: Float(cy),
                        centreContrast: Float((inner / innerCount) / ringMean), darkRadius: dark,
                        coverage: Float(bright) / Float(sectors))
    }

    // MARK: - Window pull (the origin gate's bias test, 2026-10-31)

    /// Passes and margin of the per-position refine the app runs (`VirtualDetector.tiledMeasuredOrigins`: CuboKit's
    /// `.iteratedWindow()` with its defaults).
    package static let originRefinePasses = 4
    package static let originRefineMargin: Float = 1.5

    /// The refine's window radius: `max(r · k, r + margin)`, as the kit's iterated-window estimator.
    package nonisolated static func originWindowRadius(probeRadius r: Float, radiusScale k: Float) -> Float {
        max(r * k, r + originRefineMargin)
    }

    /// How much of the origin window is the direct beam, and the most the rest can have biased the refine.
    ///
    /// The refine is a centre of mass over a disk of radius `windowRadius` around its previous centre `c`. With a flat
    /// background `b` filling the window, the background's own centre of mass is `c`, so one pass moves the centre to
    /// `f · beam + (1 − f) · c`, `f` the beam's share of the window's counts: the error shrinks by `(1 − f)` per pass and
    /// after `passes` passes is at most `(1 − f)^passes` times the starting error. The start (the brightest block) is
    /// taken as at most a window radius off, the farthest it can be with the beam still in the window, so the bound is
    /// `(1 − f)^passes · windowRadius`. The block-centre start is usually closer (about 0.7 · round(r)), so the bound
    /// over-states the pull, by 2 to 7 times on the cubes measured.
    ///
    /// Assumptions, stated because a case outside them is not covered:
    /// - the background is roughly flat across the window, and the beam is inside the first window (a noise or
    ///   hot-pixel argmax farther off is not covered);
    /// - the window is not cut by the detector edge (a cut window's background pulls inward by a fixed amount the
    ///   `(1 − f)` term does not shrink);
    /// - the data are not background-subtracted: the refine clamps each pattern at 0, which turns zero-mean noise into a
    ///   positive background, while the mean pattern's median reads about 0 here, so such data read as no pull;
    /// - `f` from the mean pattern stands for every pattern; at low dose single patterns scatter about it and, the bound
    ///   being convex in `f`, the mean understates their average a little;
    /// - structure inside the window that is not centred on the beam (a ring cut by the window, the S14-D bullseye) is a
    ///   different bias this does not see: the ringed fixture of `OriginWindowSensitivityTests` reads 0 here with its
    ///   fit 4 px off.
    /// A window that covers the whole detector has no outside to read a background from: nil, so unknown, not refused.
    ///
    /// `f` is read on the MEAN pattern: the window centred on the mean fitted origin, intensities clamped at 0, the
    /// background `b` the
    /// median of the pixels outside the window, `f = (S − b·A) / S` over the window's sum `S` and area `A` (clamped to
    /// 0...1). Diffraction outside the window does not enter `S`; a halo rising toward the beam counts as beam, which is
    /// right for the bias because it is centred on the beam. The window, sized from the maximum pattern, holds the
    /// descan spread of the beam (the maximum pattern is the union over it).
    ///
    /// Measured 2026-10-31 (`NoisyOriginTests`): bound 6.5 px at 3 counts per pixel (fit 2.69 px off), 7.2 px at 1
    /// (3.19 off), 1.84 px at 5 (0.29 off), 0.072 px at 10 (0.042 off), below 0.001 px on the demo cubes.
    /// nil when there is no window pixel, no pixel outside it to read a background from, or no counts in it.
    package nonisolated static func windowPull(
        meanDP: [Float], qy: Int, qx: Int, centre: (x: Float, y: Float), windowRadius w: Float,
        passes: Int = originRefinePasses
    ) -> (signalFraction: Float, boundPixels: Float)? {
        guard meanDP.count == qy * qx, qy > 0, qx > 0, w.isFinite, w > 0,
              centre.x.isFinite, centre.y.isFinite, passes >= 0 else { return nil }
        let w2 = Double(w) * Double(w)
        var sum = 0.0, area = 0.0
        var outside: [Float] = []
        outside.reserveCapacity(meanDP.count)
        for y in 0..<qy {
            let dy = Double(y) - Double(centre.y)
            for x in 0..<qx {
                let raw = meanDP[y * qx + x]
                let v = raw.isFinite ? max(raw, 0) : 0
                let dx = Double(x) - Double(centre.x)
                if dx * dx + dy * dy <= w2 {
                    sum += Double(v); area += 1
                } else {
                    outside.append(v)
                }
            }
        }
        guard area > 0, !outside.isEmpty, sum > 0 else { return nil }
        outside.sort()
        let m = outside.count / 2
        let background = outside.count.isMultiple(of: 2) ? (Double(outside[m - 1]) + Double(outside[m])) / 2 : Double(outside[m])
        let f = min(1, max(0, (sum - background * area) / sum))
        let bound = pow(1 - f, Double(passes)) * Double(w)
        return (Float(f), Float(bound))
    }

    // MARK: - Window sensitivity (C14, lane Q 2026-09-30)

    /// Median distance (detector pixels) between the origin the refine step
    /// finds at the caller's window (`shippedScale`, 1.2 in the app) and at a
    /// wide one (k = 2.5), over a strided sample of at most 200 scan positions
    /// bounded by 256 MB of gathered patterns: CuboVirtual's
    /// `OriginMeasurement.windowSensitivity` (CuboKit 0.7.0, Metal path). **A quantity, not a
    /// verdict** — nothing gates on it (owner, ADR 050: no fixed window ships).
    ///
    /// Why it exists: the refine is an iterated centre of mass inside a window
    /// `max(k r, r + 1.5)`; on a probe with a ring outside its core (the S14-D
    /// bullseye) that window cuts the ring, the true centre is an unstable fixed
    /// point, and the answer walks — 3.87 px between k = 1.2 and 2 on
    /// bullseye_sim, against ≤ 0.03 px on six compact cubes. Compact probes do not
    /// care which window they get; ringed ones do, and this reads which kind the
    /// scan is without choosing a window for it. nil when it cannot be measured.
    package nonisolated static func windowSensitivityPixels(
        data: FourDArray,
        descriptor d: DatasetDescriptor,
        probeRadius: Float,
        shippedScale: Float = 1.2
    ) async throws -> Float? {
        let source = try CuboCubeSource(data, descriptor: d)
        let value: Double?
        do {
            value = try await OriginMeasurement.windowSensitivity(
                of: source, radius: Double(probeRadius), shippedScale: Double(shippedScale), path: .metal)
        } catch CuboVirtualError.noMetalDevice {
            value = try await OriginMeasurement.windowSensitivity(
                of: source, radius: Double(probeRadius), shippedScale: Double(shippedScale), path: .cpu)
        }
        return value.map { Float($0) }
    }

    /// The Friedel path's mask: the beamstop mask auto-generated from the mean pattern (py4DSTEM get_beamstop_mask with
    /// its defaults; true = beamstop), inverted for get_origin_friedel (which wants true in the pattern). The kit refuses
    /// a NaN mean pattern; the app's neighbour-median fill is applied first, as it is to every pattern.
    private nonisolated static func friedelPatternMask(meanDP: [Float], descriptor d: DatasetDescriptor) throws -> [Bool] {
        var meanDP = meanDP
        if meanDP.contains(where: { !$0.isFinite }) {
            _ = BraggDetector.fillNonFinite(&meanDP, rows: d.qy, columns: d.qx)
        }
        return try BeamstopMask.make(from: DetectorImage(
            detectorRows: d.qy, detectorColumns: d.qx, values: meanDP.map(Double.init), path: .cpu)).map { !$0 }
    }

    /// The Friedel origin tried as a fallback when a centre-of-mass run finds a beam stop: the same measurement and fit
    /// as `originMethod: .friedel`, returning only the fit's RMS residual over every scan position (detector pixels),
    /// the number the refusal decides on. A second pass over the cube, CPU, paid only when a stop is found.
    package nonisolated static func friedelFallbackResidual(
        data: FourDArray, descriptor d: DatasetDescriptor, meanDP: [Float], fitFunction: OriginFitFunction,
        maximumTileRows: Int?, cancellation: AnalysisCancellationToken?
    ) async throws -> Float? {
        let measured = try await friedelMeasuredOrigins(
            data: data, descriptor: d, mask: friedelPatternMask(meanDP: meanDP, descriptor: d),
            maximumTileRows: maximumTileRows, cancellation: cancellation, progress: nil)
        let count = d.ry * d.rx
        guard measured.count == 2 * count else { return nil }
        let x = (0..<count).map { measured[2 * $0] }, y = (0..<count).map { measured[2 * $0 + 1] }
        let fit = fitOriginTrimmed(measuredX: x, measuredY: y, width: d.rx, height: d.ry, fitFunction: fitFunction)
        return fit.fullScanResidual.isFinite ? fit.fullScanResidual : nil
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

}
