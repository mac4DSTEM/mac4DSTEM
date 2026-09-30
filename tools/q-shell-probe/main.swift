//
//  tools/q-shell-probe/main.swift
//  Lane Q (v4.1 Slot 1, 2026-09-30). Which ring does the app's known-crystal Q
//  calibration take as the innermost allowed reflection, and what does its own
//  shell-ratio check say? The question came from the S20 refuter
//  (docs/archive/v4/s20-refuter-2026-09-30.md §4): on the demo cube the Q read
//  0.010386 against a true 0.012 because the majority grain [001] has no {111}
//  and the (111) reference landed on (200) — the shell check would have read
//  ≈ 1.41 against 1.155 and the tool ignored it.
//
//  Pipeline, as AppState runs it: plane origin fit (`OriginCalibration.tiledRun`),
//  synthetic kernel at the fitted probe radius, `DiskDetectionParams.detectorAdapted`,
//  descan-corrected vectors (`BraggVectors.calibrated(with:referenceOrigin:)`),
//  then `KnownCrystalQCalibration.estimate` with the DISTINCT second shell
//  length and the probe radius, exactly as `AppState.calibrateQFromCrystal`
//  passes them. Optionally an ellipse (`--ellipse a b thetaDeg`, py4DSTEM
//  convention) is applied first, as the owner's recipe for his raw cube does.
//
//  `diagnostic`, not gated: it needs machine-local datacubes and measures
//  DATASETS. Nothing here changes an app number.
//
//  Output: a readable block per cube and one `RESULT|...` line for tabulation.
//

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data("[q-shell-probe] \(message)\n".utf8))
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])
}

struct Shell { let g: Double; let hkl: String }

@main
struct QShellProbe {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let path = args.first else {
            fail("usage: q-shell-probe cube.h5 --crystal al|au|ws2 [--truth-q Q] [--label L] [--ellipse A B DEG] [--demo-truth truth.json]")
        }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let label = value("--label") ?? URL(fileURLWithPath: path).lastPathComponent
        let truthQ = value("--truth-q").flatMap(Double.init)
        let tileRows = value("--tile-rows").flatMap(Int.init)
        let minRelative = value("--min-relative").flatMap(Float.init)
        let crystal: Crystal
        switch value("--crystal") ?? "al" {
        case "al": crystal = .aluminum
        case "au": crystal = .gold
        case "ws2": crystal = .tungstenDisulfide
        default: fail("--crystal is al, au or ws2")
        }

        let reader = try H5Reader(path: path)
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        note("\(label): scan \(d.ry)×\(d.rx), detector \(d.qy)×\(d.qx)")

        let originStart = Date()
        guard let fit = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane, maximumTileRows: tileRows
        ) else { fail("origin calibration did not initialize") }
        let originSeconds = Date().timeIntervalSince(originStart)   // includes the window-sensitivity read
        // C14: the origin window-sensitivity quantity, once as tiledRun reported it
        // and once timed on its own (the patterns are cached by then, so the
        // timed call is the warm cost; the cold cost is the difference of the
        // tiledRun wall time with and without it, not measured here).
        let coldData = FourDArray(reader: reader, descriptor: d)   // empty pattern cache
        let coldStart = Date()
        let direct = try await OriginCalibration.windowSensitivityPixels(
            data: coldData, descriptor: d, probeRadius: fit.probeRadius)
        let coldSeconds = Date().timeIntervalSince(coldStart)
        let warmStart = Date()
        _ = try await OriginCalibration.windowSensitivityPixels(
            data: coldData, descriptor: d, probeRadius: fit.probeRadius)
        let warmSeconds = Date().timeIntervalSince(warmStart)
        print(String(format: "WINDOW|%@|reported=%.4f|direct=%.4f|coldSeconds=%.3f|warmSeconds=%.3f|tiledRunSeconds=%.2f|scan=%dx%d|probeR=%.2f",
                     label, fit.windowSensitivityPixels ?? .nan, direct ?? .nan,
                     coldSeconds, warmSeconds, originSeconds, d.ry, d.rx, fit.probeRadius))
        if args.contains("--window-only") { return }
        guard let kernel = ProbeKernel.synthetic(radius: fit.probeRadius, qy: d.qy, qx: d.qx)
        else { fail("probe kernel did not initialize") }
        var params = DiskDetectionParams.detectorAdapted(
            qy: d.qy, qx: d.qx, probeRadius: fit.probeRadius)
        if let minRelative { params.minRelativeIntensity = minRelative }
        note("Bragg detection (min spacing \(params.minPeakSpacing) px, floor \(params.minRelativeIntensity))")
        guard let raw = try await DiskDetection.detectAll(
            data: data, descriptor: d, kernel: kernel, params: params, maximumTileRows: tileRows
        ) else { fail("Bragg detection was cancelled — nothing cancels it here") }

        var calibration = Calibration()
        calibration.origin = fit.origin
        if let i = args.firstIndex(of: "--ellipse"), i + 3 < args.count,
           let a = Double(args[i + 1]), let b = Double(args[i + 2]), let deg = Double(args[i + 3]) {
            calibration.ellipseA = a
            calibration.ellipseB = b
            calibration.ellipseTheta = deg * .pi / 180
        }
        let origin = calibration.referenceOrigin(
            detectorQX: d.qx, detectorQY: d.qy, apertureCentre: nil).point
        let vectors = raw.calibrated(with: calibration, referenceOrigin: origin)

        // DISTINCT shell lengths, exactly as AppState+ACOM builds them, plus
        // the first reflection's hkl so a ring can be named.
        var shells: [Shell] = []
        for r in crystal.reflections(kMax: 2.5)
        where shells.last.map({ r.gLength > $0.g * (1 + 1e-6) }) ?? true {
            shells.append(Shell(g: r.gLength, hkl: "(\(r.h) \(r.k) \(r.l))"))
        }
        guard let first = shells.first else { fail("crystal has no reflection") }
        let second = shells.count > 1 ? shells[1].g : nil
        guard let estimate = KnownCrystalQCalibration.estimate(
            bragg: vectors, origin: origin,
            referenceRadiusInvAngstrom: first.g,
            secondShellRadiusInvAngstrom: second,
            probeRadiusPixels: Double(fit.probeRadius)
        ) else { fail("known-crystal Q calibration returned nil") }

        // Per-position innermost ring, replicating the estimator's cluster rule
        // (band = min(0.08, (g2/g1 - 1)/2), radii above 2 px) so a ring can be
        // named. The replica's median is checked against the estimator's.
        let expectedRatio = second.map { $0 / first.g }
        let band = min(0.08, expectedRatio.map { ($0 - 1) / 2 } ?? 0.08)
        var perPosition: [Int: Double] = [:]          // scan index -> cluster-mean r1 (px)
        for (index, peaks) in vectors.peaks.enumerated() {
            let radii = peaks.compactMap { p -> Double? in
                let dx = p.x - origin.x, dy = p.y - origin.y
                let r = (dx * dx + dy * dy).squareRoot()
                return r.isFinite && r > 2 ? Double(r) : nil
            }.sorted()
            guard let lowest = radii.first else { continue }
            let cluster = radii.prefix { $0 <= lowest * (1 + band) }
            perPosition[index] = cluster.reduce(0, +) / Double(cluster.count)
        }
        let replicaMedian = median(Array(perPosition.values))
        let peaksPerPosition = median(vectors.peaks.map { Double($0.count) })

        print("== \(label)")
        print(String(format: "cube %@: scan %d×%d, detector %d×%d; probe radius %.2f px; origin (%.2f, %.2f) px; %d peaks, median %.0f per position",
                     URL(fileURLWithPath: path).lastPathComponent, d.ry, d.rx, d.qy, d.qx,
                     fit.probeRadius, origin.x, origin.y, vectors.totalPeakCount, peaksPerPosition))
        print("shells (kMax 2.5, first 14 distinct |g|): " + shells.prefix(14).enumerated().map {
            String(format: "%d:%@ %.4f", $0.offset, $0.element.hkl, $0.element.g)
        }.joined(separator: " · "))
        print(String(format: "estimate: r1 %.3f px (replica %.3f), MAD %.3f px, %d positions, %.1f equivalents/position, Q %.6f Å⁻¹/px",
                     estimate.observedRadiusPixels, replicaMedian,
                     estimate.medianAbsoluteDeviationPixels, estimate.sampleCount,
                     estimate.sameShellPeaksPerPosition, estimate.invAngstromPerPixel))
        var observedRatio = Double.nan, positionsWithR2 = 0, mismatchPercent = Double.nan
        switch estimate.shellCheck {
        case .measured(let observed, let expected, let positions):
            observedRatio = observed; positionsWithR2 = positions
            mismatchPercent = abs(observed / expected - 1) * 100
            print(String(format: "shell check: r2 %.3f px, observed ratio %.4f vs expected %.4f (%.2f %% apart), %d positions have an r2",
                         estimate.secondShellRadiusPixels ?? .nan, observed, expected, mismatchPercent, positions))
        case .notSelfChecked(let reason):
            print("shell check: NOT self-checked — \(reason)")
        }

        var qErrorPercent = Double.nan
        var majorityLabel = "n/a"
        if let truthQ {
            qErrorPercent = (estimate.invAngstromPerPixel / truthQ - 1) * 100
            print(String(format: "truth Q %.6f → estimate %+.2f %%", truthQ, qErrorPercent))
            func shellIndex(forRadius r: Double) -> (index: Int, relativeError: Double) {
                let g = r * truthQ
                let best = shells.prefix(12).enumerated().min {
                    abs(g / $0.element.g - 1) < abs(g / $1.element.g - 1)
                }!
                return (best.offset, abs(g / best.element.g - 1))
            }
            var histogram: [Int: Int] = [:]
            for r in perPosition.values { histogram[shellIndex(forRadius: r).index, default: 0] += 1 }
            let total = Double(perPosition.count)
            let ordered = histogram.sorted { $0.value > $1.value }
            print("innermost detected ring at truth Q (nearest shell, share of positions): "
                  + ordered.prefix(4).map {
                      String(format: "%@ %.1f %%", shells[$0.key].hkl, Double($0.value) / total * 100)
                  }.joined(separator: " · "))
            if let top = ordered.first {
                majorityLabel = String(format: "%@ %.0f %%", shells[top.key].hkl, Double(top.value) / total * 100)
            }
            let median1 = shellIndex(forRadius: estimate.observedRadiusPixels)
            print(String(format: "the estimator's median r1 %.2f px is shell %@ at truth Q (%.1f %% off)",
                         estimate.observedRadiusPixels, shells[median1.index].hkl, median1.relativeError * 100))
            if let secondPx = estimate.secondShellRadiusPixels {
                let s2 = shellIndex(forRadius: secondPx)
                print(String(format: "its median r2 %.2f px is shell %@ at truth Q (%.1f %% off)",
                             secondPx, shells[s2.index].hkl, s2.relativeError * 100))
            }

            // Per-grain view for the demo cube (truth.json's grain_label_map).
            if let truthPath = value("--demo-truth"),
               let json = try JSONSerialization.jsonObject(
                   with: Data(contentsOf: URL(fileURLWithPath: truthPath))) as? [String: Any],
               let map = json["grain_label_map"] as? [[Int]] {
                for (code, name) in [(0, "A [001]"), (1, "B [011]"), (2, "C [111]")] {
                    var radii: [Double] = []
                    for (y, row) in map.enumerated() {
                        for (x, c) in row.enumerated() where c == code {
                            if let r = perPosition[y * d.rx + x] { radii.append(r) }
                        }
                    }
                    let r = median(radii)
                    let s = shellIndex(forRadius: r)
                    print(String(format: "grain %@: %d positions with a peak, median r1 %.2f px → %@ at truth Q (%.1f %% off); this grain alone would read Q %.6f",
                                 name, radii.count, r, shells[s.index].hkl, s.relativeError * 100,
                                 first.g / r))
                }
            }
        }
        print(String(format: "RESULT|%@|r1=%.3f|r2=%.3f|obsRatio=%.4f|expRatio=%.4f|positionsR2=%d|Q=%.6f|truthQ=%@|QerrPct=%.2f|mismatchPct=%.2f|majority=%@",
                     label, estimate.observedRadiusPixels, estimate.secondShellRadiusPixels ?? .nan,
                     observedRatio, expectedRatio ?? .nan, positionsWithR2,
                     estimate.invAngstromPerPixel, truthQ.map { String(format: "%.6f", $0) } ?? "n/a",
                     qErrorPercent, mismatchPercent, majorityLabel))
    }
}
