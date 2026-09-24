//
//  tools/matrix-orientation-probe/main.swift
//  Gate D instrument for docs/archive/v4/almgsi-gateD-2026-09-24.md: why does
//  the matrix lose on the owner's real Al-Mg-Si cube? Three pre-registered
//  hypotheses, each measured here on the app's own pipeline:
//    H1  the Al orientation varies, so one global matrix entry cannot remove
//        matrix peaks everywhere (per-position in-plane refit, and a coarse
//        every-axis refit);
//    H2  the survivors are reflections the reference omits (|q| against the
//        Al shell radii and a uniform-chance baseline; a floor-0 entry);
//    H3  the survivors are weak spurious maxima, and the two-vector exclusion
//        rule turns any two into "not matrix" (intensity relative to the same
//        pattern's matrix peaks).
//
//  `diagnostic`, not gated: it needs a machine-local cube and measures a
//  DATASET, not an invariant of the code. Nothing here changes an app number.
//
//  Pipeline, as the app runs it (read 2026-09-24): plane origin fit
//  (`OriginCalibration.tiledRun`), synthetic kernel at the fitted probe
//  radius, `DiskDetectionParams.detectorAdapted`, descan-corrected vectors
//  (`BraggVectors.calibrated(with:referenceOrigin:)`), tolerances from
//  `PhaseVectorResolution.scaledToDetector`, the zone axis from
//  `fitZoneAxis`, the matrix entry from `fitMatrixOrientation`, and the
//  drive's map (Al + β″ at [010] and [001], search rule) from
//  `PhaseVectorMatcher.map`. Its first output is the reproduction check.
//
//  Usage: run.sh <cube.h5> [--q 0.045741] [--min-relative 0.0015]
//                [--stride 2] [--csv out.csv] [--overlay out.json]
//

import Foundation
import simd

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s[min(s.count - 1, max(0, Int((p * Double(s.count - 1)).rounded())))]
}

/// One experimental vector with its detected intensity — `experimentalVectors`
/// drops the intensity, and H3 needs it. Same filter, same arithmetic.
struct Vec { let q: SIMD2<Double>; let intensity: Float }

func vectors(_ peaks: [BraggPeak], originX: Float, originY: Float, scale: Double,
             directBeam: Double, reach: Double) -> [Vec] {
    var out: [Vec] = []
    for p in peaks {
        let q = SIMD2(Double(p.x - originX) * scale, Double(p.y - originY) * scale)
        let len = simd_length(q)
        guard len.isFinite, len > directBeam, reach <= 0 || len < reach else { continue }
        out.append(Vec(q: q, intensity: p.intensity))
    }
    return out
}

func matchedMask(_ v: [Vec], _ refs: [ReferenceVector], _ radius: Double) -> [Bool] {
    v.map { PhaseVectorMatcher.nearest($0.q, in: refs, radius: radius) != nil }
}

func angleDiffDeg(_ a: Double, _ b: Double) -> Double {
    var d = (a - b) * 180 / .pi
    d = d.truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

struct PositionRecord {
    var x = 0, y = 0, n = 0
    var globalMatched = 0
    var localTheta = Double.nan, localMatched = 0
    var bestAxis = SIMD3<Int>(0, 0, 0), bestAxisTheta = Double.nan, bestAxisMatched = 0
    var survivors = 0, survivorsOnShell = 0, survivorsOnFloor0 = 0
    var survivorRelIntensities: [Double] = []
    var allSurvivorsWeak = false
    var verdict = -1
}

@main
enum MatrixOrientationProbe {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let path = args.first else { fail("usage: run.sh <cube.h5> [options]") }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var qPerPixel = Double(value("--q") ?? "0.045741") ?? 0.045741
        let distortionCorrect = args.contains("--distortion-correct")
        let minRelative = Float(value("--min-relative") ?? "0.0015") ?? 0.0015
        let stride = max(1, Int(value("--stride") ?? "2") ?? 2)
        let csvPath = value("--csv")
        let overlayPath = value("--overlay")

        let reader = try H5Reader(path: path)
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        print("cube: \(URL(fileURLWithPath: path).lastPathComponent)  scan \(d.ry)×\(d.rx)  detector \(d.qy)×\(d.qx)")
        print(String(format: "Q %.6f Å⁻¹/px · detection floor %.4f %% · stride %d", qPerPixel, 100 * minRelative, stride))

        // ---- The app's pipeline -------------------------------------------
        guard let fit = try await OriginCalibration.tiledRun(data: data, descriptor: d, fitFunction: .plane)
        else { fail("origin calibration did not initialize") }
        let fx = fit.origin.fittedX, fy = fit.origin.fittedY
        print(String(format: "origin plane fit: probe radius %.2f px; fitted origin spans x %.2f–%.2f, y %.2f–%.2f px (descan, corrected below)",
                     fit.probeRadius, fx.min() ?? .nan, fx.max() ?? .nan, fy.min() ?? .nan, fy.max() ?? .nan))
        guard let kernel = ProbeKernel.synthetic(radius: fit.probeRadius, qy: d.qy, qx: d.qx)
        else { fail("kernel") }
        var params = DiskDetectionParams.detectorAdapted(qy: d.qy, qx: d.qx, probeRadius: fit.probeRadius)
        params.minRelativeIntensity = minRelative
        print(String(format: "detection: min spacing %.0f px, edge %d px, max peaks %d",
                     params.minPeakSpacing, params.edgeBoundary, params.maxNumPeaks))
        guard let raw = try await DiskDetection.detectAll(data: data, descriptor: d, kernel: kernel, params: params)
        else { fail("detection cancelled") }
        var calibration = Calibration()
        calibration.origin = fit.origin
        guard let origin = calibration.meanOrigin else { fail("no mean origin") }
        let calibrated = raw.calibrated(with: calibration, referenceOrigin: origin)
        let allCounts = calibrated.peaks.map(\.count)
        print("detected \(allCounts.reduce(0, +)) peaks over \(allCounts.count) positions, median \(Int(median(allCounts.map(Double.init))))")

        // Strided sub-scan: the questions are distributions.
        let rows = Array(Swift.stride(from: 0, to: d.ry, by: stride))
        let cols = Array(Swift.stride(from: 0, to: d.rx, by: stride))
        var subPeaks: [[BraggPeak]] = []
        var subXY: [(Int, Int)] = []
        for ry in rows { for rx in cols {
            subPeaks.append(calibrated.peaks[ry * d.rx + rx]); subXY.append((rx, ry))
        } }
        var bragg = BraggVectors(scanWidth: cols.count, scanHeight: rows.count, peaks: subPeaks)
        var distortion: simd_double2x2? = nil
        // --dump-peaks: the descan-corrected peaks of the strided scan, in
        // detector pixels, with the reference origin — so a refuter can
        // re-derive the rings without this file's code.
        if let dumpPath = value("--dump-peaks") {
            let payload: [String: Any] = [
                "origin": [Double(origin.x), Double(origin.y)], "stride": stride,
                "cols": cols.count, "rows": rows.count, "detector": [d.qx, d.qy],
                "probe_radius_px": Double(fit.probeRadius),
                "peaks": subPeaks.map { $0.map { [Double($0.x), Double($0.y), Double($0.intensity)] } },
            ]
            try JSONSerialization.data(withJSONObject: payload).write(to: URL(fileURLWithPath: dumpPath))
            print("wrote the strided scan's peaks to \(dumpPath)")
        }

        // ---- H4 (added after the overlay, pre-registered before this ran):
        // where are the disks, in PIXELS, independent of any Q calibration?
        // Two strongest rings by count, then each ring's four azimuth
        // clusters: [001] predicts 90° gaps and a 45° offset between rings;
        // ⟨110⟩ {111} would give 70.5° / 109.5°.
        rings: do {
            let binPx = 0.25, maxR = 46.0
            var radial = [Int](repeating: 0, count: Int(maxR / binPx))
            let inner = Double(2 * fit.probeRadius)
            var polar: [(r: Double, phi: Double)] = []
            for peaks in subPeaks {
                for p in peaks {
                    let dx = Double(p.x - origin.x), dy = Double(p.y - origin.y)
                    let r = (dx * dx + dy * dy).squareRoot()
                    guard r > inner, r < maxR else { continue }
                    radial[Int(r / binPx)] += 1
                    polar.append((r, atan2(dy, dx) * 180 / .pi))
                }
            }
            // Local maxima of a 5-bin running sum, strongest two, ≥ 3 px apart.
            let smooth = radial.indices.map { i in (max(0, i - 2)...min(radial.count - 1, i + 2)).reduce(0) { $0 + radial[$1] } }
            let maxima = smooth.indices.filter { i in
                i > 0 && i < smooth.count - 1 && smooth[i] >= smooth[i - 1] && smooth[i] > smooth[i + 1]
            }.sorted { smooth[$0] > smooth[$1] }
            var rings: [Double] = []
            for i in maxima {
                let r = (Double(i) + 0.5) * binPx
                if rings.allSatisfy({ abs($0 - r) >= 3 }) { rings.append(r) }
                if rings.count == 3 { break }
            }
            print("\n== H4: rings in detector pixels (no Q involved) ==")
            let within1 = polar.filter { $0.r < (rings.min() ?? 0) - 1.5 }.count
            print(String(format: "  peaks between %.1f px (2 × probe radius) and 46 px: %d; strongest rings at %@ px",
                         inner, polar.count, rings.map { String(format: "%.2f", $0) }.joined(separator: ", ") as NSString))
            if rings.count >= 2 {
                let r1 = min(rings[0], rings[1]), r2 = max(rings[0], rings[1])
                print(String(format: "  two strongest: r1 %.2f px, r2 %.2f px, r2/r1 %.4f (√2 = 1.4142; ⟨110⟩ {200}/{111} 1.1547, {220}/{111} 1.6330)",
                             r1, r2, r2 / r1))
                print(String(format: "  peaks inside r1 − 1.5 px (excluding the direct beam): %d (%.2f %% of all)",
                             within1, 100 * Double(within1) / Double(max(1, polar.count))))
                func clusters(_ ring: Double) -> [Double] {
                    var h = [Int](repeating: 0, count: 120)
                    for p in polar where abs(p.r - ring) <= 1 {
                        h[Int(((p.phi + 360).truncatingRemainder(dividingBy: 360)) / 3) % 120] += 1
                    }
                    let s = h.indices.map { i in h[(i + 119) % 120] + h[i] + h[(i + 1) % 120] }
                    var centres: [Double] = []
                    for i in s.indices.sorted(by: { s[$0] > s[$1] }) {
                        let c = (Double(i) + 0.5) * 3
                        if centres.allSatisfy({ d in let x = abs(d - c); return min(x, 360 - x) >= 20 }) { centres.append(c) }
                        if centres.count == 4 { break }
                    }
                    return centres.sorted()
                }
                for (name, ring) in [("r1", r1), ("r2", r2)] {
                    let c = clusters(ring)
                    let gaps = c.indices.map { i in i + 1 < c.count ? c[i + 1] - c[i] : c[0] + 360 - c[i] }
                    print(String(format: "  %@ azimuth clusters %@°, gaps %@°", name as NSString,
                                 c.map { String(format: "%.1f", $0) }.joined(separator: ", ") as NSString,
                                 gaps.map { String(format: "%.1f", $0) }.joined(separator: ", ") as NSString))
                }
                let c1 = clusters(r1), c2 = clusters(r2)
                let offsets = c2.map { b in c1.map { a in let x = abs(a - b).truncatingRemainder(dividingBy: 360); return min(x, 360 - x) }.min() ?? .nan }
                print(String(format: "  r2 clusters' nearest r1 cluster: %@° (a [001] pattern predicts 45°)",
                             offsets.map { String(format: "%.1f", $0) }.joined(separator: ", ") as NSString))
                print(String(format: "  if r1 is Al {200} (0.4939 Å⁻¹): Q = %.6f Å⁻¹/px, the file's %.6f is %.3f× that",
                             0.4939 / r1, qPerPixel, qPerPixel / (0.4939 / r1)))

                // ---- H5: one linear map A from ideal [001] to the data ----
                // Inner cluster k ↔ e_k (unit {200}, rotating +90° per k);
                // outer cluster between k and k+1 ↔ e_k + e_{k+1} ({220}).
                func angDist(_ a: Double, _ b: Double) -> Double {
                    let x = abs(a - b).truncatingRemainder(dividingBy: 360); return min(x, 360 - x)
                }
                func centroid(_ keep: ((r: Double, phi: Double)) -> Bool) -> SIMD2<Double>? {
                    var sx = 0.0, sy = 0.0, n = 0.0
                    for p in polar where keep(p) {
                        sx += p.r * cos(p.phi * .pi / 180); sy += p.r * sin(p.phi * .pi / 180); n += 1
                    }
                    return n >= 20 ? SIMD2(sx / n, sy / n) : nil
                }
                guard c1.count == 4 else { print("  H5: ring 1 did not give four clusters"); break rings }
                let e: [SIMD2<Double>] = [SIMD2(1, 0), SIMD2(0, 1), SIMD2(-1, 0), SIMD2(0, -1)]
                var ideal: [SIMD2<Double>] = [], seen: [SIMD2<Double>] = [], names: [String] = []
                for k in 0..<4 {
                    if let p = centroid({ abs($0.r - r1) <= 1.5 && angDist($0.phi, c1[k]) <= 15 }) {
                        ideal.append(e[k]); seen.append(p); names.append("inner \(k)")
                    }
                    let a = c1[k], b = c1[(k + 1) % 4] + (k == 3 ? 360 : 0)
                    let mid = (a + b) / 2
                    if let p = centroid({ $0.r >= 1.2 * r1 && $0.r <= 1.7 * r1 && angDist($0.phi, mid) <= 12 }) {
                        ideal.append(e[k] + e[(k + 1) % 4]); seen.append(p); names.append("outer \(k)")
                    }
                }
                guard ideal.count >= 6 else { print("  H5: only \(ideal.count) cluster centres found"); break rings }
                // Least squares, one row of A at a time: seen.x = a11 s.x + a12 s.y.
                var sxx = 0.0, sxy = 0.0, syy = 0.0, bx1 = 0.0, bx2 = 0.0, by1 = 0.0, by2 = 0.0
                for (s, p) in zip(ideal, seen) {
                    sxx += s.x * s.x; sxy += s.x * s.y; syy += s.y * s.y
                    bx1 += s.x * p.x; bx2 += s.y * p.x; by1 += s.x * p.y; by2 += s.y * p.y
                }
                let det = sxx * syy - sxy * sxy
                let a11 = (syy * bx1 - sxy * bx2) / det, a12 = (sxx * bx2 - sxy * bx1) / det
                let a21 = (syy * by1 - sxy * by2) / det, a22 = (sxx * by2 - sxy * by1) / det
                let A = simd_double2x2(columns: (SIMD2(a11, a21), SIMD2(a12, a22)))
                var sq = 0.0
                print("\n== H5: one linear map from ideal [001] ({200} = unit) to the data, px ==")
                for (i, (s, p)) in zip(ideal, seen).enumerated() {
                    let r = simd_length(A * s - p); sq += r * r
                    print(String(format: "  %@  ideal (%+.0f, %+.0f)  seen (%+.2f, %+.2f)  residual %.2f px",
                                 names[i] as NSString, s.x, s.y, p.x, p.y, r))
                }
                let rms = (sq / Double(ideal.count)).squareRoot()
                // Singular values of A: the ellipse's semi-axes per unit {200}.
                let ata = A.transpose * A
                let tr = ata[0][0] + ata[1][1], dt = ata[0][0] * ata[1][1] - ata[0][1] * ata[1][0]
                let l1 = tr / 2 + ((tr * tr / 4 - dt).squareRoot()), l2 = tr / 2 - ((tr * tr / 4 - dt).squareRoot())
                let s1 = l1.squareRoot(), s2 = l2.squareRoot()
                let aat = A * A.transpose
                let major = 0.5 * atan2(2 * aat[1][0], aat[0][0] - aat[1][1]) * 180 / .pi
                print(String(format: "  RMS residual %.3f px over %d centres; axis ratio %.4f (major axis at %.1f° in the detector); {200} = %.2f–%.2f px; Q = %.6f Å⁻¹/px (0.4939 / √det A)",
                             rms, ideal.count, s1 / s2, major, s2, s1, 0.4939 / (s1 * s2).squareRoot()))
                distortion = A

                // (d) {400}/{420}: never used by the fit.
                let far: [SIMD2<Double>] = [SIMD2(2, 0), SIMD2(-2, 0), SIMD2(0, 2), SIMD2(0, -2),
                                            SIMD2(2, 1), SIMD2(2, -1), SIMD2(-2, 1), SIMD2(-2, -1),
                                            SIMD2(1, 2), SIMD2(-1, 2), SIMD2(1, -2), SIMD2(-1, -2)]
                let halfW = Double(d.qx) / 2 - Double(params.edgeBoundary), halfH = Double(d.qy) / 2 - Double(params.edgeBoundary)
                var observed = 0, expected = 0.0, used = 0
                for s in far {
                    let t = A * s
                    guard abs(t.x) < halfW - 1, abs(t.y) < halfH - 1 else { continue }
                    used += 1
                    let rt = simd_length(t)
                    var inAnnulus = 0
                    for p in polar where abs(p.r - rt) <= 1 {
                        inAnnulus += 1
                        let v = SIMD2(p.r * cos(p.phi * .pi / 180), p.r * sin(p.phi * .pi / 180))
                        if simd_length(v - t) <= 1 { observed += 1 }
                    }
                    expected += Double(inAnnulus) * (Double.pi * 1) / (2 * Double.pi * rt * 2)
                }
                let beyond = polar.filter { $0.r > 33 }.count
                print(String(format: "  (d) {400}/{420} inside the detector: %d of 12 positions; peaks within 1 px: %d, chance %.1f → %.2f×; peaks beyond 33 px: %d",
                             used, observed, expected, Double(observed) / max(expected, 1e-9), beyond))
            }
        }
        if distortionCorrect, let A = distortion {
            // Every peak mapped through A⁻¹ onto an undistorted virtual
            // detector at the scale where one {200} is 0.4939 / Qv px.
            let qVirtual = 0.026518
            let unit = 0.4939 / qVirtual
            let inv = A.inverse
            subPeaks = subPeaks.map { peaks in peaks.map { p in
                let v = inv * SIMD2(Double(p.x - origin.x), Double(p.y - origin.y)) * unit
                return BraggPeak(x: origin.x + Float(v.x), y: origin.y + Float(v.y), intensity: p.intensity)
            } }
            bragg = BraggVectors(scanWidth: cols.count, scanHeight: rows.count, peaks: subPeaks)
            qPerPixel = qVirtual
            print(String(format: "\n** distortion-corrected: every peak mapped through A⁻¹; virtual Q %.6f Å⁻¹/px **", qVirtual))
        }

        var settings = PhaseVectorResolution(settings: PhaseVectorSettings(), invAngstromPerPixel: qPerPixel)
            .scaledToDetector(PhaseVectorSettings())
        let reach = Double(min(d.qx, d.qy)) / 2 * qPerPixel
        let tol = settings.matrixToleranceInvAngstrom
        print(String(format: "matching (scaled to detector): pair %.4f, matrix tolerance %.4f, not indexed above %.4f, direct beam %.4f Å⁻¹; detector reach %.3f Å⁻¹",
                     settings.pairRadiusInvAngstrom, tol, settings.notIndexedAboveInvAngstrom,
                     settings.directBeamRadiusInvAngstrom, reach))
        settings.classificationRule = .search

        // ---- Reproduction: the drive's zone axis, matrix entry and map ------
        let refSettings = PhaseReferenceSettings()
        let axes = PhaseVectorMatcher.fitZoneAxis(
            bragg: bragg, crystal: .aluminum, referenceSettings: refSettings, settings: settings,
            originX: origin.x, originY: origin.y, invAngstromPerPixel: qPerPixel)
        guard let top = axes.first else { fail("no zone axis fitted") }
        print("\n== Reproduction (drive B1: ⟨110⟩, 43 % of vectors once scaled) ==")
        for a in axes.prefix(5) {
            print(String(format: "  [%d %d %d] at %.0f°: %d of %d vectors (%.1f %%)",
                         a.zoneAxis.x, a.zoneAxis.y, a.zoneAxis.z, a.inPlaneRotationRad * 180 / .pi,
                         a.matchedVectors, a.totalVectors, 100 * Double(a.matchedVectors) / Double(a.totalVectors)))
        }
        let axis = top.zoneAxis
        let phases = [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum, role: .matrix, zoneAxes: [axis]),
            PhaseDefinition(id: "b010", displayName: "β″[010]", crystal: .betaDoublePrime, role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
            PhaseDefinition(id: "b001", displayName: "β″[001]", crystal: .betaDoublePrime, role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
        ]
        let library = try PhaseReferenceLibrary.build(phases: phases, settings: refSettings)
        guard let global = PhaseVectorMatcher.fitMatrixOrientation(
            bragg: bragg, library: library, settings: settings,
            originX: origin.x, originY: origin.y, invAngstromPerPixel: qPerPixel)
        else { fail("no matrix entry") }
        let globalEntry = library.entries[global.entryIndex]
        let theta0 = globalEntry.inPlaneRotationRad
        print(String(format: "  global matrix entry: [%d %d %d] at %.1f°, %d reference vectors",
                     axis.x, axis.y, axis.z, theta0 * 180 / .pi, globalEntry.vectors.count))
        guard let map = PhaseVectorMatcher.map(
            bragg: bragg, library: library, settings: settings,
            originX: origin.x, originY: origin.y, invAngstromPerPixel: qPerPixel,
            matrixEntryIndex: global.entryIndex)
        else { fail("map failed") }
        let total = Double(map.results.count)
        var byLabel: [String: Int] = [:]
        for r in map.results {
            let key: String
            switch r.verdict {
            case .matrix: key = "matrix"
            case .indexed: key = phases[Int(r.phaseIndex)].displayName
            case .notIndexed: key = "not indexed"
            case .noData: key = "no data"
            }
            byLabel[key, default: 0] += 1
        }
        print("  map (drive B2 at 0.15 %: matrix 0.7, β″[010] 27.1, β″[001] 16.6, not indexed 55.7 %):")
        for key in ["matrix", "β″[010]", "β″[001]", "not indexed", "no data"] {
            print(String(format: "    %-12@ %6.1f %%", key as NSString, 100 * Double(byLabel[key, default: 0]) / total))
        }

        // ---- Per-position fits ---------------------------------------------
        let reflections = Crystal.aluminum.reflections(kMax: refSettings.kMaxInvAngstrom)
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: reflections, crystal: .aluminum, zoneAxis: axis, settings: refSettings)
        var floor0Settings = refSettings
        floor0Settings.minimumIntensityFraction = 0
        floor0Settings.maximumVectorsPerEntry = 1000
        let baseFloor0 = PhaseReferenceLibrary.projectedVectors(
            reflections: reflections, crystal: .aluminum, zoneAxis: axis, settings: floor0Settings)
        print(String(format: "\n⟨%d %d %d⟩Al reference: %d vectors at the shipped 5 %% floor, %d at floor 0",
                     axis.x, axis.y, axis.z, base.count, baseFloor0.count))

        // Fine in-plane sweep around the global angle: ±20° at 0.5°.
        let fineThetas = (-40...40).map { theta0 + Double($0) * 0.5 * .pi / 180 }
        let fineEntries = fineThetas.map { PhaseReferenceLibrary.rotate(base, by: $0) }
        // Coarse sweep over every low-index axis at 5°.
        var coarseSettings = refSettings
        coarseSettings.inPlaneStepDeg = 5
        var coarse: [(axis: SIMD3<Int>, theta: Double, refs: [ReferenceVector])] = []
        for a in PhaseReferenceLibrary.lowIndexZoneAxes {
            let b = PhaseReferenceLibrary.projectedVectors(
                reflections: reflections, crystal: .aluminum, zoneAxis: a, settings: refSettings)
            guard !b.isEmpty else { continue }
            for t in PhaseReferenceLibrary.inPlaneSteps(coarseSettings) {
                coarse.append((a, t, PhaseReferenceLibrary.rotate(b, by: t)))
            }
        }
        print("fine sweep: \(fineEntries.count) rotations of the global axis; coarse sweep: \(coarse.count) entries over \(PhaseReferenceLibrary.lowIndexZoneAxes.count) axes")

        // Al shell radii for H2, and their uniform-chance coverage of the
        // accessible annulus (area-weighted, numerically).
        var shells: [Double] = []
        for g in reflections.map(\.gLength).sorted() where g < reach + tol {
            if shells.last.map({ g > $0 + 1e-6 }) ?? true { shells.append(g) }
        }
        let rLo = settings.directBeamRadiusInvAngstrom, rHi = reach
        var inBand = 0.0, all = 0.0
        for i in 0..<20000 {
            let r = rLo + (rHi - rLo) * (Double(i) + 0.5) / 20000
            all += r
            if shells.contains(where: { abs($0 - r) <= tol }) { inBand += r }
        }
        let shellChance = inBand / all

        var records = [PositionRecord](repeating: PositionRecord(), count: subPeaks.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: subPeaks.count) { i in
            var rec = PositionRecord()
            rec.x = subXY[i].0; rec.y = subXY[i].1
            rec.verdict = Int(map.results[i].verdict.rawValue)
            let v = vectors(subPeaks[i], originX: origin.x, originY: origin.y, scale: qPerPixel,
                            directBeam: settings.directBeamRadiusInvAngstrom,
                            reach: settings.maximumVectorInvAngstrom)
            rec.n = v.count
            guard !v.isEmpty else { lock.withLock { records[i] = rec }; return }
            rec.globalMatched = matchedMask(v, globalEntry.vectors, tol).filter { $0 }.count
            // Fine: most matched; ties go to the smallest |Δθ| so a flat
            // score cannot manufacture a rotation.
            var bestK = 40, bestCount = -1
            for (k, refs) in fineEntries.enumerated() {
                let c = matchedMask(v, refs, tol).filter { $0 }.count
                if c > bestCount || (c == bestCount && abs(k - 40) < abs(bestK - 40)) {
                    bestCount = c; bestK = k
                }
            }
            rec.localTheta = fineThetas[bestK]; rec.localMatched = bestCount
            // Coarse: most matched; ties go to the global axis.
            var bc = -1
            for e in coarse {
                let c = matchedMask(v, e.refs, tol).filter { $0 }.count
                if c > bc || (c == bc && e.axis == axis && rec.bestAxis != axis) {
                    bc = c; rec.bestAxis = e.axis; rec.bestAxisTheta = e.theta
                }
            }
            rec.bestAxisMatched = bc
            // Survivors after the per-position best in-plane entry.
            let mask = matchedMask(v, fineEntries[bestK], tol)
            let matrixI = zip(v, mask).filter { $0.1 }.map { Double($0.0.intensity) }
            let survivors = zip(v, mask).filter { !$0.1 }.map(\.0)
            rec.survivors = survivors.count
            let floor0 = PhaseReferenceLibrary.rotate(baseFloor0, by: fineThetas[bestK])
            let matrixMedian = median(matrixI)
            for s in survivors {
                let r = simd_length(s.q)
                if shells.contains(where: { abs($0 - r) <= tol }) { rec.survivorsOnShell += 1 }
                if PhaseVectorMatcher.nearest(s.q, in: floor0, radius: tol) != nil { rec.survivorsOnFloor0 += 1 }
                if matrixMedian.isFinite, matrixMedian > 0 {
                    rec.survivorRelIntensities.append(Double(s.intensity) / matrixMedian)
                }
            }
            rec.allSurvivorsWeak = survivors.count >= 2
                && rec.survivorRelIntensities.count == survivors.count
                && rec.survivorRelIntensities.allSatisfy { $0 < 0.1 }
            lock.withLock { records[i] = rec }
        }

        // ---- H1 ----------------------------------------------------------------
        let nAll = Double(records.map(\.n).reduce(0, +))
        let fitted = records.filter { $0.localMatched >= 3 }
        let dTheta = fitted.map { angleDiffDeg($0.localTheta, theta0) }
        let absD = dTheta.map(abs)
        print("\n== H1: does the Al orientation vary? ==")
        print(String(format: "  positions with ≥ 3 vectors matched by the refit: %d of %d", fitted.count, records.count))
        print(String(format: "  Δθ (refit − global): median %+.2f°, IQR %+.2f…%+.2f°, median |Δθ| %.2f°, 95th pct |Δθ| %.2f°",
                     median(dTheta), percentile(dTheta, 0.25), percentile(dTheta, 0.75), median(absD), percentile(absD, 0.95)))
        print(String(format: "  |Δθ| > 2.5°: %.1f %% of fitted positions; at the ±20° edge: %.1f %%",
                     100 * Double(absD.filter { $0 > 2.5 }.count) / Double(max(1, absD.count)),
                     100 * Double(absD.filter { $0 >= 19.99 }.count) / Double(max(1, absD.count))))
        // Spatial coherence: right-neighbour differences against random pairs.
        var grid = [Double?](repeating: nil, count: records.count)
        for (i, r) in records.enumerated() where r.localMatched >= 3 { grid[i] = angleDiffDeg(r.localTheta, theta0) }
        var neighbour: [Double] = [], random: [Double] = []
        var rng = SystemRandomNumberGenerator()
        for i in grid.indices {
            guard let a = grid[i] else { continue }
            if (i + 1) % cols.count != 0, let b = grid[i + 1] { neighbour.append(abs(a - b)) }
            if let b = grid[Int.random(in: 0..<grid.count, using: &rng)] { random.append(abs(a - b)) }
        }
        print(String(format: "  coherence: median |Δθ − neighbour's| %.2f° vs random pair %.2f°", median(neighbour), median(random)))
        let explainedGlobal = Double(records.map(\.globalMatched).reduce(0, +)) / max(1, nAll)
        let explainedLocal = Double(records.map(\.localMatched).reduce(0, +)) / max(1, nAll)
        let explainedAny = Double(records.map(\.bestAxisMatched).reduce(0, +)) / max(1, nAll)
        print(String(format: "  explained fraction of all vectors: global %.1f %% → in-plane refit %.1f %% → any-axis refit %.1f %%",
                     100 * explainedGlobal, 100 * explainedLocal, 100 * explainedAny))
        var axisCount: [SIMD3<Int>: Int] = [:]
        for r in records where r.n > 0 { axisCount[r.bestAxis, default: 0] += 1 }
        let withData = Double(records.filter { $0.n > 0 }.count)
        print("  best coarse axis per position (top 5):")
        for (a, c) in axisCount.sorted(by: { $0.value > $1.value }).prefix(5) {
            print(String(format: "    [%d %d %d] %5.1f %%%@", a.x, a.y, a.z, 100 * Double(c) / withData,
                         (a == axis ? "  ← global" : "") as NSString))
        }
        let matrixGlobal = records.filter { $0.n > 0 && $0.n - $0.globalMatched < settings.minimumVectors }.count
        let matrixLocal = records.filter { $0.n > 0 && $0.survivors < settings.minimumVectors }.count
        print(String(format: "  positions with < %d survivors (matrix by exclusion): global %.1f %%, in-plane refit %.1f %%",
                     settings.minimumVectors, 100 * Double(matrixGlobal) / withData, 100 * Double(matrixLocal) / withData))

        // ---- H2 ----------------------------------------------------------------
        let survivorsTotal = records.map(\.survivors).reduce(0, +)
        let onShell = records.map(\.survivorsOnShell).reduce(0, +)
        let onFloor0 = records.map(\.survivorsOnFloor0).reduce(0, +)
        print("\n== H2: are the survivors reflections the reference omits? ==")
        print(String(format: "  survivors after the in-plane refit: %d (median %d per position)",
                     survivorsTotal, Int(median(records.filter { $0.n > 0 }.map { Double($0.survivors) }))))
        print(String(format: "  on an Al shell radius (±%.3f Å⁻¹): %.1f %%; uniform chance %.1f %%; ratio %.2f×",
                     tol, 100 * Double(onShell) / Double(max(1, survivorsTotal)), 100 * shellChance,
                     Double(onShell) / Double(max(1, survivorsTotal)) / shellChance))
        print(String(format: "  on a ⟨%d %d %d⟩Al reflection at intensity floor 0 (same rotation): %.1f %%",
                     axis.x, axis.y, axis.z, 100 * Double(onFloor0) / Double(max(1, survivorsTotal))))
        // |q| histogram of survivors, 0.02 Å⁻¹ bins, with the Al shells marked.
        var hist = [Int](repeating: 0, count: Int((reach / 0.02).rounded(.up)) + 1)
        for (i, _) in records.enumerated() {
            let v = vectors(subPeaks[i], originX: origin.x, originY: origin.y, scale: qPerPixel,
                            directBeam: settings.directBeamRadiusInvAngstrom,
                            reach: settings.maximumVectorInvAngstrom)
            guard !v.isEmpty, records[i].localMatched >= 0 else { continue }
            let k = Int(((records[i].localTheta - theta0) * 180 / .pi / 0.5).rounded()) + 40
            guard k >= 0, k < fineEntries.count else { continue }
            for (s, m) in zip(v, matchedMask(v, fineEntries[k], tol)) where !m {
                let b = Int(simd_length(s.q) / 0.02)
                if b < hist.count { hist[b] += 1 }
            }
        }
        let peak = max(1, hist.max() ?? 1)
        print("  survivor |q| histogram (0.02 Å⁻¹ bins; * = an Al shell within the bin):")
        for (b, c) in hist.enumerated() where c > 0 {
            let lo = Double(b) * 0.02
            let mark = shells.contains(where: { $0 >= lo && $0 < lo + 0.02 }) ? "*" : " "
            print(String(format: "    %.2f–%.2f %@ %6d %@", lo, lo + 0.02, mark as NSString, c,
                         String(repeating: "█", count: max(1, 50 * c / peak)) as NSString))
        }

        // ---- H3 ----------------------------------------------------------------
        let rel = records.flatMap(\.survivorRelIntensities)
        print("\n== H3: are the survivors weak spurious maxima? ==")
        print(String(format: "  survivor intensity / the same pattern's median matrix-peak intensity: median %.3f, 25th %.3f, 75th %.3f, 90th %.3f",
                     median(rel), percentile(rel, 0.25), percentile(rel, 0.75), percentile(rel, 0.9)))
        let twoPlus = records.filter { $0.survivors >= 2 }.count
        let weak = records.filter(\.allSurvivorsWeak).count
        print(String(format: "  positions with ≥ 2 survivors: %.1f %%; of all positions, ≥ 2 survivors all < 0.1: %.1f %%",
                     100 * Double(twoPlus) / withData, 100 * Double(weak) / withData))

        // ---- Dumps ---------------------------------------------------------------
        if let csvPath {
            var lines = ["x,y,n,global_matched,local_dtheta_deg,local_matched,best_axis,best_axis_theta_deg,best_axis_matched,survivors,survivors_on_shell,survivors_on_floor0,all_survivors_weak,verdict"]
            for r in records {
                lines.append(String(format: "%d,%d,%d,%d,%.2f,%d,%d_%d_%d,%.1f,%d,%d,%d,%d,%d,%d",
                                    r.x, r.y, r.n, r.globalMatched,
                                    r.localTheta.isFinite ? angleDiffDeg(r.localTheta, theta0) : .nan,
                                    r.localMatched, r.bestAxis.x, r.bestAxis.y, r.bestAxis.z,
                                    r.bestAxisTheta.isFinite ? r.bestAxisTheta * 180 / .pi : .nan,
                                    r.bestAxisMatched, r.survivors, r.survivorsOnShell, r.survivorsOnFloor0,
                                    r.allSurvivorsWeak ? 1 : 0, r.verdict))
            }
            try lines.joined(separator: "\n").write(toFile: csvPath, atomically: true, encoding: .utf8)
            print("\nwrote \(records.count) positions to \(csvPath)")
        }
        if let overlayPath {
            // Three positions per drive label, spread along the scan so they
            // are not all from one corner.
            let view = LoadView(fullExtentOf: d)
            var picks: [Int] = []
            for verdict in [0, 1, 2] {
                for phase in (verdict == 1 ? [1, 2] : [-9]) {
                    let idx = records.indices.filter {
                        records[$0].verdict == verdict
                            && (verdict != 1 || Int(map.results[$0].phaseIndex) == phase)
                    }
                    guard !idx.isEmpty else { continue }
                    for f in [0.2, 0.5, 0.8] { picks.append(idx[Int(Double(idx.count - 1) * f)]) }
                }
            }
            var out: [[String: Any]] = []
            for i in picks {
                let (rx, ry) = subXY[i]
                guard let pattern = try? await reader.readPattern(view, ry: ry, rx: rx) else { continue }
                let rawPeaks = raw.peaks[ry * d.rx + rx]
                let ox = fit.origin.fittedX[ry * d.rx + rx], oy = fit.origin.fittedY[ry * d.rx + rx]
                let theta = records[i].localTheta
                let tmpl = PhaseReferenceLibrary.rotate(baseFloor0, by: theta)
                let label: String = {
                    switch map.results[i].verdict {
                    case .matrix: return "matrix"
                    case .indexed: return phases[Int(map.results[i].phaseIndex)].displayName
                    case .notIndexed: return "not indexed"
                    case .noData: return "no data"
                    }
                }()
                let v = vectors(subPeaks[i], originX: origin.x, originY: origin.y, scale: qPerPixel,
                                directBeam: settings.directBeamRadiusInvAngstrom,
                                reach: settings.maximumVectorInvAngstrom)
                let mask = matchedMask(v, PhaseReferenceLibrary.rotate(base, by: theta), tol)
                out.append([
                    "x": rx, "y": ry, "label": label, "w": d.qx, "h": d.qy,
                    "pattern": pattern.map(Double.init),
                    "origin": [Double(ox), Double(oy)],
                    "peaks": rawPeaks.map { [Double($0.x), Double($0.y), Double($0.intensity)] },
                    // Peaks as matched (m) / survivor (s), in raw detector pixels.
                    "classified": zip(v, mask).map { pair -> [Any] in
                        [Double(ox) + pair.0.q.x / qPerPixel, Double(oy) + pair.0.q.y / qPerPixel, pair.1 ? "m" : "s"]
                    },
                    "template": tmpl.map { [Double(ox) + $0.q.x / qPerPixel, Double(oy) + $0.q.y / qPerPixel,
                                            $0.relativeIntensity >= refSettings.minimumIntensityFraction ? 1.0 : 0.0] },
                    "tolerance_px": tol / qPerPixel,
                    "dtheta_deg": angleDiffDeg(theta, theta0),
                ])
            }
            let json = try JSONSerialization.data(withJSONObject: out)
            try json.write(to: URL(fileURLWithPath: overlayPath))
            print("wrote \(out.count) overlay patterns to \(overlayPath)")
        }
    }
}
