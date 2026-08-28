import Foundation

// S13 E2 — where a hard ceiling on the excluded fraction would go
// (docs/q-calibration-design.md §6b). Pre-registration in
// docs/archive/v2-session-records/s13.md §0.
//
// The owner decided (§6a) to ADMIT a trimmed calibration and show the fraction.
// Whether there is a fraction above which the app should refuse ANYWAY is open,
// and S13 must measure where such a ceiling would go rather than pick a round
// number. This sweeps the trim aggressiveness to generate a range of kept
// fractions, and at each one measures what actually degrades: the fit's own
// uncertainty, and the kept set's spatial support.
//
// It calls the SHIPPED fitter — `OriginCalibration.fitOriginTrimmed` and the
// masked `fitOrigin` — so nothing here can drift from what the app does.

struct Aperture {  // mirrored for VirtualDetector's aperture overload
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next(_ bound: Int) -> Int {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Int(state % UInt64(max(bound, 1)))
    }
}

@main
struct TrimSweep {
    static func main() async throws {
        for path in Array(CommandLine.arguments.dropFirst()) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let reader: H5Reader
            let d: DatasetDescriptor
            do {
                reader = try H5Reader(path: path)
                d = try await reader.discoverPrimaryDataset()
            } catch { print("=== \(name): SKIPPED — \(error)"); continue }
            let data = FourDArray(reader: reader, descriptor: d)
            guard let fit = try await OriginCalibration.tiledRun(
                data: data, descriptor: d, fitFunction: .plane
            ), let mx = fit.origin.measuredX, let my = fit.origin.measuredY else {
                print("=== \(name): no measured origin maps"); continue
            }
            let count = mx.count
            print("=== \(name)  scan \(d.rx)x\(d.ry) = \(count) positions  probe r = "
                + String(format: "%.3f px", fit.probeRadius))
            print("  The CEILING CRITERION, fixed before this ran: a ceiling is defensible at the")
            print("  kept fraction where the fitted origin's own uncertainty reaches 2 px — #29's")
            print("  estimator-breakdown scale, the point where the fit is as uncertain as the")
            print("  error it exists to remove.")
            print("")
            print("  trim k   kept      RMS(kept)  RMS(all)  bootstrapSD_px(median/max)  maxGap_px")

            func measure(label: String, kept: [Bool], seed: UInt64,
                         keptResidual: Float, fullScanResidual: Float) {
                let keptIndices = (0..<count).filter { kept[$0] }
                guard keptIndices.count >= 4 else {
                    print("  \(label)  degenerate — fewer than 4 kept positions")
                    return
                }

                // Subsampling, m out of n WITHOUT replacement at m = n/2, 200
                // draws. A Bool mask cannot express a with-replacement
                // bootstrap, and using the app's own fitter is worth more than
                // the textbook variant: m-out-of-n subsampling is standard, and
                // a half-sample SD converts to a full-sample one by sqrt(m/n) =
                // sqrt(1/2). Stated because the scaling is the step a reader
                // would otherwise have to guess at.
                let draws = 200
                let m = max(4, keptIndices.count / 2)
                var sumX = [Double](repeating: 0, count: count)
                var sumXX = [Double](repeating: 0, count: count)
                var sumY = [Double](repeating: 0, count: count)
                var sumYY = [Double](repeating: 0, count: count)
                var rng = SeededRNG(seed: seed)
                for _ in 0..<draws {
                    var pool = keptIndices
                    var mask = [Bool](repeating: false, count: count)
                    for slot in 0..<m {
                        let pick = slot + rng.next(pool.count - slot)
                        pool.swapAt(slot, pick)
                        mask[pool[slot]] = true
                    }
                    let sample = OriginCalibration.fitOrigin(
                        measuredX: mx, measuredY: my, width: d.rx, height: d.ry,
                        fitFunction: .plane, included: mask
                    )
                    for i in 0..<count {
                        let vx = Double(sample.fittedX[i]), vy = Double(sample.fittedY[i])
                        sumX[i] += vx; sumXX[i] += vx * vx
                        sumY[i] += vy; sumYY[i] += vy * vy
                    }
                }
                let scale = (Double(m) / Double(keptIndices.count)).squareRoot()
                var sd = [Double](repeating: 0, count: count)
                for i in 0..<count {
                    let n = Double(draws)
                    let vx = max(0, sumXX[i] / n - (sumX[i] / n) * (sumX[i] / n))
                    let vy = max(0, sumYY[i] / n - (sumY[i] / n) * (sumY[i] / n))
                    sd[i] = (vx + vy).squareRoot() * scale
                }
                let sdSorted = sd.sorted()

                // Spatial support: the largest distance from ANY scan position
                // to the nearest KEPT one, by multi-source BFS on the scan grid
                // (Chebyshev). This is what actually goes wrong when trimming
                // leaves the kept set clustered — the plane extrapolates over a
                // region nothing constrains.
                var distance = [Int](repeating: Int.max, count: count)
                var frontier: [Int] = []
                for i in keptIndices { distance[i] = 0; frontier.append(i) }
                while !frontier.isEmpty {
                    var next: [Int] = []
                    for index in frontier {
                        let x = index % d.rx, y = index / d.rx
                        for dy in -1...1 {
                            for dx in -1...1 where !(dx == 0 && dy == 0) {
                                let nx = x + dx, ny = y + dy
                                guard nx >= 0, nx < d.rx, ny >= 0, ny < d.ry else { continue }
                                let neighbour = ny * d.rx + nx
                                if distance[neighbour] > distance[index] + 1 {
                                    distance[neighbour] = distance[index] + 1
                                    next.append(neighbour)
                                }
                            }
                        }
                    }
                    frontier = next
                }
                let maxGap = distance.max() ?? 0

                print(String(
                    format: "  %-6@   %4.1f%%     %8.4f  %8.4f      %8.4f / %8.4f  %9d",
                    label as NSString, 100 * Double(keptIndices.count) / Double(count),
                    Double(keptResidual), Double(fullScanResidual),
                    sdSorted[sdSorted.count / 2], sdSorted.last ?? .nan, maxGap
                ))
            }

            for k in [Float(4), 3, 2, 1.5, 1.0] {
                let trimmed = OriginCalibration.fitOriginTrimmed(
                    measuredX: mx, measuredY: my, width: d.rx, height: d.ry,
                    fitFunction: .plane, trimSigma: k
                )
                measure(label: String(format: "k=%.1f", Double(k)), kept: trimmed.kept,
                        seed: 0x5133_2026 &+ UInt64(k * 10),
                        keptResidual: trimmed.keptResidual,
                        fullScanResidual: trimmed.fullScanResidual)
            }

            // The trim converges long before it excludes much — the sweep above
            // bottoms out around two thirds kept — so it cannot answer the
            // ceiling question by itself. FORCE the kept fraction instead: keep
            // the N positions with the smallest residual to the ordinary
            // full-scan fit and refit on those. This is not what the app does;
            // it is the only way to observe the regime a ceiling would govern.
            print("  — forced kept fractions (not the app's trim; the regime a ceiling governs) —")
            let ordinary = OriginCalibration.fitOrigin(
                measuredX: mx, measuredY: my, width: d.rx, height: d.ry, fitFunction: .plane
            )
            let ordered = (0..<count).sorted { lhs, rhs in
                func residual(_ i: Int) -> Float {
                    let dx = mx[i] - ordinary.fittedX[i], dy = my[i] - ordinary.fittedY[i]
                    return dx * dx + dy * dy
                }
                return residual(lhs) < residual(rhs)
            }
            for target in [0.60, 0.40, 0.20, 0.10, 0.05, 0.02] {
                let keepCount = max(4, Int((Double(count) * target).rounded()))
                guard keepCount < count else { continue }
                var kept = [Bool](repeating: false, count: count)
                for i in ordered.prefix(keepCount) { kept[i] = true }
                let refit = OriginCalibration.fitOrigin(
                    measuredX: mx, measuredY: my, width: d.rx, height: d.ry,
                    fitFunction: .plane, included: kept
                )
                func rms(_ indices: [Int]) -> Float {
                    guard !indices.isEmpty else { return .nan }
                    let total = indices.reduce(Float(0)) { sum, i in
                        let dx = mx[i] - refit.fittedX[i], dy = my[i] - refit.fittedY[i]
                        return sum + dx * dx + dy * dy
                    }
                    return (total / Float(indices.count)).squareRoot()
                }
                measure(label: String(format: "%.0f%%", target * 100), kept: kept,
                        seed: 0x7E51_2026 &+ UInt64(target * 1000),
                        keptResidual: rms((0..<count).filter { kept[$0] }),
                        fullScanResidual: rms(Array(0..<count)))
            }
            print("")
        }
    }
}
