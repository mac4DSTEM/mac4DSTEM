// detection-threshold-probe.swift — the 2026-09-05 measurement behind closing
// "Disk detection at defaults finds only the beam on WS2" (closed-items-2026-09.md).
// Compile it the way run.sh compiles main.swift (swap the file name); point it at
// training cubes with ABSOLUTE paths. Diagnostic, never gates.

import Foundation

// Gate D measurement for the detection-threshold item (pre-registration:
// detection-threshold-gate-d-preregistration.md, 2026-09-05). For each cube:
// origin fit, synthetic kernel, then full-scan detection at the shipped
// detector-adapted defaults with relativeToPeak 0 (reference = brightest
// peak, the beam) and 1 (reference = second brightest, the brightest disk).
// Reports peaks per position, the per-position ratio of the second-brightest
// to the brightest accepted peak (what the disks ARE relative to the beam),
// and a lattice proxy: the fraction of non-beam peaks whose radius from the
// mean origin falls within ±6 % of the modal radius (a ring) — a crude
// false-positive indicator, not a truth claim.

func quantiles(_ v: [Double]) -> String {
    guard !v.isEmpty else { return "none" }
    let s = v.sorted()
    func q(_ f: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * f))] }
    return String(format: "min %.4g  p10 %.4g  median %.4g  p90 %.4g  max %.4g", s.first!, q(0.1), q(0.5), q(0.9), s.last!)
}

@main
struct DetectionExperiment {
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { print("usage: det-experiment <file.h5>..."); exit(64) }
        for path in args {
            let name = URL(fileURLWithPath: path).lastPathComponent
            print("=== \(name)")
            let reader = try H5Reader(path: path)
            let d = try await reader.discoverPrimaryDataset()
            let data = FourDArray(reader: reader, descriptor: d)
            guard let fit = try await OriginCalibration.tiledRun(data: data, descriptor: d, fitFunction: .plane) else {
                print("  FAIL: no origin fit"); continue
            }
            var calibration = Calibration()
            calibration.origin = fit.origin
            calibration.probeRadius = fit.probeRadius
            guard let meanOrigin = calibration.meanOrigin else { print("  FAIL: no mean origin"); continue }
            guard let kernel = ProbeKernel.synthetic(radius: fit.probeRadius, qy: d.qy, qx: d.qx) else {
                print("  FAIL: no probe kernel"); continue
            }
            print(String(format: "  scan %dx%d  detector %dx%d  probe r %.3f px  mean origin (%.2f, %.2f)",
                         d.rx, d.ry, d.qx, d.qy, fit.probeRadius, meanOrigin.x, meanOrigin.y))
            for relativeToPeak in [0, 1] {
                var params = DiskDetectionParams.detectorAdapted(qy: d.qy, qx: d.qx, probeRadius: fit.probeRadius)
                params.relativeToPeak = relativeToPeak
                if let text = ProcessInfo.processInfo.environment["DET_MIN_RELATIVE"], let value = Float(text) {
                    params.minRelativeIntensity = value
                }
                let started = Date()
                guard let raw = try await DiskDetection.detectAll(data: data, descriptor: d, kernel: kernel, params: params) else {
                    print("  relativeToPeak \(relativeToPeak): detection returned nothing"); continue
                }
                let seconds = Date().timeIntervalSince(started)
                let counts = raw.peaks.map(\.count)
                let sortedCounts = counts.sorted()
                let median = Double(sortedCounts[sortedCounts.count / 2])
                let zero = counts.filter { $0 == 0 }.count
                let one = counts.filter { $0 == 1 }.count
                let atMax = counts.filter { $0 >= params.maxNumPeaks }.count
                // second/first accepted intensity per position (sorted brightest-first by the detector)
                let ratios: [Double] = raw.peaks.compactMap { peaks in
                    guard peaks.count >= 2 else { return nil }
                    let s = peaks.map { Double($0.intensity) }.sorted(by: >)
                    return s[0] > 0 ? s[1] / s[0] : nil
                }
                // lattice proxy: radii of non-beam peaks from the mean origin
                var radii: [Double] = []
                for peaks in raw.peaks {
                    for peak in peaks {
                        let dx = Double(peak.x) - Double(meanOrigin.x), dy = Double(peak.y) - Double(meanOrigin.y)
                        let r = (dx * dx + dy * dy).squareRoot()
                        if r > Double(fit.probeRadius) * 2 { radii.append(r) }
                    }
                }
                var ringFraction = Double.nan, modal = Double.nan
                if !radii.isEmpty {
                    // modal radius over 0.5 px bins
                    var bins: [Int: Int] = [:]
                    for r in radii { bins[Int(r * 2), default: 0] += 1 }
                    let top = bins.max { $0.value < $1.value }!
                    modal = Double(top.key) / 2 + 0.25
                    ringFraction = Double(radii.filter { abs($0 - modal) / modal < 0.06 }.count) / Double(radii.count)
                }
                print(String(format: "  relativeToPeak %d  minRel %.4g  spacing %.1f  edge %d   (%.1f s)",
                             relativeToPeak, params.minRelativeIntensity, params.minPeakSpacing, params.edgeBoundary, seconds))
                print(String(format: "    peaks/position: median %.0f  zero %d  exactly-one %d  at-max %d  of %d  (min %d max %d, total %d)",
                             median, zero, one, atMax, counts.count, sortedCounts.first ?? 0, sortedCounts.last ?? 0, counts.reduce(0, +)))
                print("    second/first accepted intensity: \(quantiles(ratios))  (positions with >= 2 peaks: \(ratios.count))")
                print(String(format: "    non-beam radii: %d peaks, modal %.2f px, within 6%% of modal %.3f", radii.count, modal, ringFraction))
            }
        }
    }
}
