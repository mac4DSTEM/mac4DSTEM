import Foundation

// S13 E1 — the shell-consistency threshold (docs/q-calibration-design.md §3.1),
// measured rather than invented. Pre-registration in
// docs/archive/v2-session-records/s13.md §0.
//
// The estimator's own statistics are read at a series of DELIBERATELY DISPLACED
// origins, in two arms: a constant offset (the geometric-middle-fallback shape)
// and per-position Gaussian jitter (the contaminated-fit shape). The injection
// point is `calibration.origin.fittedX/Y` and not `referenceOrigin`, because
// `BraggVectors.calibrated` collapses peaks onto the PER-POSITION fitted origin
// — displacing the reference frame alone would move every peak together and
// measure nothing.

struct Aperture {  // mirrored for VirtualDetector's aperture overload
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

/// Deterministic Gaussian jitter: a fixed-seed LCG + Box-Muller, so arm B is
/// reproducible run to run and machine to machine.
struct SeededGaussian {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func normal() -> Double {
        let u1 = max(next(), 1e-12), u2 = next()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

func medianD(_ values: [Double]) -> Double {
    let s = values.sorted(); let m = s.count / 2
    return s.count.isMultiple(of: 2) ? (s[m - 1] + s[m]) / 2 : s[m]
}

/// Distinct shell lengths, grouped: `Crystal.reflections` returns every
/// symmetry-equivalent reflection separately, all at the same |g|, so the
/// "second shell" is the first gLength that differs by more than a rounding
/// tolerance — not `reflections[1]`.
func distinctShells(_ lengths: [Double], tolerance: Double = 1e-6) -> [Double] {
    var out: [Double] = []
    for g in lengths where out.last.map({ abs(g - $0) > tolerance * max(1, g) }) ?? true {
        out.append(g)
    }
    return out
}

@main
struct ShellCheck {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: shell-check <file.h5> <crystalModelID>\n".utf8))
            exit(64)
        }
        let path = args[0], modelID = args[1]
        let name = URL(fileURLWithPath: path).lastPathComponent

        guard let model = CrystalModelLibrary.model(id: modelID), model.isUsable else {
            print("FAIL: no usable crystal model '\(modelID)'"); exit(1)
        }
        let shells = distinctShells(model.crystal.reflections(kMax: 2.5).map(\.gLength))
        guard let g1 = shells.first else { print("FAIL: no allowed shell"); exit(1) }
        let g2 = shells.count > 1 ? shells[1] : Double.nan

        let reader = try H5Reader(path: path)
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        guard let fit = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane
        ) else { print("FAIL: no origin fit"); exit(1) }

        var calibration = Calibration()
        calibration.origin = fit.origin
        calibration.probeRadius = fit.probeRadius
        guard let meanOrigin = calibration.meanOrigin else { print("FAIL: no mean origin"); exit(1) }

        guard let kernel = ProbeKernel.synthetic(
            radius: fit.probeRadius, qy: d.qy, qx: d.qx
        ) else { print("FAIL: no probe kernel"); exit(1) }
        let params = DiskDetectionParams.detectorAdapted(
            qy: d.qy, qx: d.qx, probeRadius: fit.probeRadius
        )
        guard let raw = try await DiskDetection.detectAll(
            data: data, descriptor: d, kernel: kernel, params: params
        ) else { print("FAIL: detection returned nothing"); exit(1) }

        print("=== \(name)  model \(modelID)")
        print("scan \(d.rx)x\(d.ry)  detector \(d.qx)x\(d.qy)  probe r = \(String(format: "%.3f", fit.probeRadius)) px")
        let middle = (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
        let fallbackDistance = ((meanOrigin.x - middle.x) * (meanOrigin.x - middle.x)
            + (meanOrigin.y - middle.y) * (meanOrigin.y - middle.y)).squareRoot()
        print(String(format: "mean fitted origin (%.3f, %.3f)  detector middle (%.3f, %.3f)  "
            + "geometric-middle fallback would displace by %.3f px = %.2f x probe r",
            meanOrigin.x, meanOrigin.y, middle.x, middle.y,
            fallbackDistance, fallbackDistance / fit.probeRadius))
        print("peaks \(raw.totalPeakCount)  first shell g1 = \(String(format: "%.5f", g1)) A^-1"
            + (g2.isFinite ? "  second shell g2 = \(String(format: "%.5f", g2)) A^-1  g2/g1 = \(String(format: "%.5f", g2 / g1))" : "  (only one shell)"))
        print("")
        print("arm      delta_px  observed_px    MAD_px  MAD/obs  obs/probe_r  median_r2/r1  q_AperPx    q_err  originRMS  origin_gate")

        func radiiPerPosition(_ vectors: BraggVectors, origin: (x: Float, y: Float)) -> [[Double]] {
            vectors.peaks.map { peaks in
                peaks.compactMap { peak -> Double? in
                    let dx = peak.x - origin.x, dy = peak.y - origin.y
                    let r = (dx * dx + dy * dy).squareRoot()
                    return r.isFinite && r > 2 ? Double(r) : nil
                }.sorted()
            }
        }

        // §3.2 AS DESIGNED: the two innermost radii per position, ungrouped.
        func shellRatio(_ all: [[Double]]) -> Double {
            var r1: [Double] = [], r2: [Double] = []
            for radii in all where radii.count >= 2 { r1.append(radii[0]); r2.append(radii[1]) }
            guard !r1.isEmpty else { return .nan }
            return medianD(r2) / medianD(r1)
        }

        // §3.2 WITH SHELL SEPARATION: r2 is the innermost radius that is at
        // least `separation` LARGER than r1, so two peaks of the SAME shell —
        // several symmetry equivalents of one |g| are excited at once — cannot
        // be read as two different shells.
        func separatedShellRatio(_ all: [[Double]], separation: Double) -> (ratio: Double, coverage: Double) {
            var r1: [Double] = [], r2: [Double] = []
            var withSecond = 0
            for radii in all where !radii.isEmpty {
                r1.append(radii[0])
                if let second = radii.first(where: { $0 > radii[0] * (1 + separation) }) {
                    r2.append(second); withSecond += 1
                }
            }
            guard !r1.isEmpty, !r2.isEmpty else { return (.nan, 0) }
            return (medianD(r2) / medianD(r1), Double(withSecond) / Double(r1.count))
        }

        var baselineQ = Double.nan

        func run(arm: String, delta: Double, perturb: (inout OriginMaps) -> Void) {
            var perturbed = fit.origin
            perturb(&perturbed)
            var c = calibration
            c.origin = perturbed
            let vectors = raw.calibrated(with: c, referenceOrigin: meanOrigin)
            guard let estimate = KnownCrystalQCalibration.estimate(
                bragg: vectors, origin: meanOrigin, referenceRadiusInvAngstrom: g1,
                secondShellRadiusInvAngstrom: g2.isFinite ? g2 : nil,
                probeRadiusPixels: Double(fit.probeRadius)
            ) else { print("\(arm)  \(delta)  ESTIMATE FAILED"); return }
            let ratio = estimate.medianAbsoluteDeviationPixels / estimate.observedRadiusPixels
            let overProbe = estimate.observedRadiusPixels / Double(fit.probeRadius)
            let all = radiiPerPosition(vectors, origin: meanOrigin)
            let r2r1 = shellRatio(all)
            if delta == 0 && arm == "A" { baselineQ = estimate.invAngstromPerPixel }
            let qErr = baselineQ.isFinite
                ? (estimate.invAngstromPerPixel - baselineQ) / baselineQ * 100 : .nan
            // The SHIPPED origin-fit gate, evaluated on the SAME perturbed
            // maps: whether the layer above the estimator would have refused
            // before the estimator ever ran. Measured, not argued from algebra.
            let originRMS = c.origin?.rmsResidual ?? .nan
            print(String(
                format: "%-7@  %8.1f  %11.4f  %8.4f  %7.4f  %11.3f  %12.4f  %8.6f  %+6.1f%%  %9.4f  %@",
                arm as NSString, delta, estimate.observedRadiusPixels,
                estimate.medianAbsoluteDeviationPixels, ratio, overProbe, r2r1,
                estimate.invAngstromPerPixel, qErr, Double(originRMS),
                (c.originFitIsSane ? "pass" : "BLOCK") as NSString
            ))
        }

        // Arm A — constant displacement (delta/sqrt2, delta/sqrt2).
        for delta in [0.0, 1, 2, 3, 5, 8, 12, 20] {
            run(arm: "A", delta: delta) { maps in
                let step = Float(delta / 2.0.squareRoot())
                maps.fittedX = maps.fittedX.map { $0 + step }
                maps.fittedY = maps.fittedY.map { $0 + step }
            }
        }
        // Arm B — per-position isotropic Gaussian jitter of RMS delta.
        // Each component gets sigma = delta/sqrt(2) so the 2D displacement's
        // RMS magnitude is delta.
        for delta in [1.0, 2, 3, 5] {
            run(arm: "B", delta: delta) { maps in
                var rng = SeededGaussian(seed: 0x5133_2026_08_28)
                let sigma = delta / 2.0.squareRoot()
                for i in maps.fittedX.indices {
                    maps.fittedX[i] += Float(rng.normal() * sigma)
                    maps.fittedY[i] += Float(rng.normal() * sigma)
                }
            }
        }

        // The shell-separation sweep, on the UNPERTURBED vectors. §3.2 assumes
        // the second-smallest radius at a position belongs to the second shell;
        // if several equivalents of the FIRST shell are excited at once it does
        // not, and the check compares a shell against itself.
        print("")
        print("shell separation sweep (unperturbed):  g2/g1 = \(String(format: "%.5f", g2 / g1))")
        let baseline = radiiPerPosition(
            raw.calibrated(with: calibration, referenceOrigin: meanOrigin), origin: meanOrigin
        )
        print("  separation   median(r2)/median(r1)   positions with an r2")
        // The DERIVED separation: half the expected gap to the next shell,
        // which the app already knows from `Crystal.reflections`. Not a number
        // anyone picked — it is (g2/g1 - 1)/2.
        let derived = g2.isFinite ? (g2 / g1 - 1) / 2 : Double.nan
        for separation in [0.0, 0.01, 0.03, 0.05, derived, 0.08, 0.10].sorted() {
            let (ratio, coverage) = separatedShellRatio(baseline, separation: separation)
            print(String(format: "  %8.0f%%   %21.5f   %19.1f%%", separation * 100, ratio, coverage * 100))
        }
        // The pooled radius distribution, so the shells are visible rather than
        // inferred: are there resolvable clusters at all on this data?
        let pooled = baseline.flatMap { $0 }.sorted()
        print("  pooled radii: n = \(pooled.count)  deciles:")
        var line = "   "
        for decile in 0...10 {
            let i = min(pooled.count - 1, Int(Double(decile) / 10 * Double(pooled.count - 1)))
            line += String(format: " %7.2f", pooled[i])
        }
        print(line)
    }
}
