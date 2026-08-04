import Foundation

// Which parameter costs the automated Si_SiGe run half its Bragg peaks?
// Detects a sample of real patterns under one-parameter-at-a-time variants and
// reports peaks/pattern plus the nearest-neighbour spacing distribution, which
// is what `minPeakSpacing` actually gates against.

@main
enum SpacingProbe {
    static func main() async {
        let path = CommandLine.arguments[1]
        // The probe radius sets the correlation kernel, so it MUST be this
        // dataset's own measured value — the four training datasets range from
        // 1.86 px (WS2) to 10.6 px (Particle_1). A single hardcoded radius
        // silently produces a wrong-kernel measurement: WS2 at 5.03 px returns
        // one peak per pattern for every variant.
        guard CommandLine.arguments.count > 2,
              let probeRadius = Float(CommandLine.arguments[2]), probeRadius > 0 else {
            print("usage: probe <datacube.h5> <probe-radius-px>")
            print("  probe radius is the app's fitted value, e.g. from the QC log's 'Probe: N px'")
            exit(2)
        }
        guard let reader = try? H5Reader(path: path),
              let primary = try? await reader.discoverPrimaryDataset() else {
            print("could not open \(path)"); exit(1)
        }
        print("dataset: ry=\(primary.ry) rx=\(primary.rx) qy=\(primary.qy) qx=\(primary.qx)")
        print(String(format: "probe radius: %.2f px  (2r = %.1f px)", probeRadius, 2 * probeRadius))

        guard let kernel = ProbeKernel.synthetic(
            radius: probeRadius, qy: primary.qy, qx: primary.qx
        ) else {
            print("kernel failed"); exit(1)
        }
        guard let detector = DiskDetector(kernel: kernel) else { print("detector failed"); exit(1) }

        let qMin = Float(min(primary.qx, primary.qy))
        var shipped = DiskDetectionParams()
        shipped.minPeakSpacing = max(4, (qMin / 8).rounded())   // 16 px at 128
        shipped.edgeBoundary = max(2, Int(qMin / 24))           // 5 px at 128

        var handTuned = shipped
        handTuned.sigmaCC = 0.9
        handTuned.minPeakSpacing = 10
        handTuned.edgeBoundary = 10

        var onlySigma = shipped;   onlySigma.sigmaCC = 0.9
        var onlySpacing = shipped; onlySpacing.minPeakSpacing = 10
        var onlyEdge = shipped;    onlyEdge.edgeBoundary = 10

        // Candidate replacements for the qMin/8 heuristic, all tied to the
        // probe radius — the scale that actually sets how far apart two maxima
        // must be before they are different disks rather than one disk twice.
        func probeRule(_ multiple: Float) -> DiskDetectionParams {
            var params = shipped
            params.minPeakSpacing = max(4, (multiple * probeRadius).rounded())
            return params
        }

        let variants: [(String, DiskDetectionParams)] = [
            ("shipped default  qMin/8 = \(Int(shipped.minPeakSpacing)) px", shipped),
            ("only sigmaCC   -> 0.9", onlySigma),
            ("only spacing   -> 10 ", onlySpacing),
            ("only edge      -> 10 ", onlyEdge),
            ("hand-tuned (all three)", handTuned),
            ("probe rule 0.75r = \(Int(max(4, (0.75 * probeRadius).rounded()))) px", probeRule(0.75)),
            ("probe rule 1.00r = \(Int(max(4, probeRadius.rounded()))) px", probeRule(1.0)),
            ("probe rule 1.50r = \(Int(max(4, (1.5 * probeRadius).rounded()))) px", probeRule(1.5)),
            ("probe rule 2.00r = \(Int(max(4, (2.0 * probeRadius).rounded()))) px", probeRule(2.0)),
        ]

        // Sample patterns spread across the scan.
        var positions: [(Int, Int)] = []
        for ry in stride(from: 4, to: primary.ry, by: max(1, primary.ry / 6)) {
            for rx in stride(from: 4, to: primary.rx, by: max(1, primary.rx / 8)) {
                positions.append((ry, rx))
            }
        }
        positions = Array(positions.prefix(40))
        print("sampling \(positions.count) patterns\n")

        var patterns: [[Float]] = []
        for (ry, rx) in positions {
            if let p = try? await reader.readPattern(primary, ry: ry, rx: rx) {
                patterns.append(p)
            }
        }
        print("read \(patterns.count) patterns\n")

        for (label, params) in variants {
            var counts: [Int] = []
            var nearest: [Float] = []
            for pattern in patterns {
                let peaks = detector.detect(pattern: pattern, params: params)
                counts.append(peaks.count)
                for i in peaks.indices {
                    var best = Float.greatestFiniteMagnitude
                    for j in peaks.indices where j != i {
                        let dx = peaks[i].x - peaks[j].x
                        let dy = peaks[i].y - peaks[j].y
                        best = min(best, (dx * dx + dy * dy).squareRoot())
                    }
                    // A pattern with a single accepted peak has no neighbour;
                    // recording the sentinel would poison the percentiles.
                    if best.isFinite, best < Float(max(primary.qx, primary.qy)) {
                        nearest.append(best)
                    }
                }
            }
            let sortedCounts = counts.sorted()
            let median = sortedCounts.isEmpty ? 0 : sortedCounts[sortedCounts.count / 2]
            let sortedNearest = nearest.sorted()
            func pct(_ p: Double) -> Float {
                sortedNearest.isEmpty ? 0
                    : sortedNearest[min(sortedNearest.count - 1,
                                        Int(p * Double(sortedNearest.count)))]
            }
            print(String(
                format: "%@  median %2d peaks/pattern  total %6d  nearest-neighbour px: p05 %.1f  p25 %.1f  median %.1f",
                label, median, counts.reduce(0, +), pct(0.05), pct(0.25), pct(0.50)
            ))
        }

        // What fraction of genuine neighbour pairs sit below the shipped gate?
        var below = 0, all = 0
        for pattern in patterns {
            let peaks = detector.detect(pattern: pattern, params: handTuned)
            for i in peaks.indices {
                var best = Float.greatestFiniteMagnitude
                for j in peaks.indices where j != i {
                    let dx = peaks[i].x - peaks[j].x
                    let dy = peaks[i].y - peaks[j].y
                    best = min(best, (dx * dx + dy * dy).squareRoot())
                }
                if best.isFinite, best < Float(max(primary.qx, primary.qy)) {
                    all += 1
                    if best < shipped.minPeakSpacing { below += 1 }
                }
            }
        }
        print(String(
            format: "\nOf the peaks the hand-tuned run accepts, %.1f%% have a nearest neighbour closer than the shipped %.0f px gate.",
            100.0 * Double(below) / Double(max(all, 1)), shipped.minPeakSpacing
        ))
    }
}
