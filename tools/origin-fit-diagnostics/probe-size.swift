import Foundation

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

// The SPED_MgO / demo probe-radius discriminator, run on real data — the
// experiment `docs/open-items.md`'s probeSize entry records as designed but
// never run outside synthetic patterns. For each dataset it feeds the REAL
// `OriginCalibration.probeSize` four different diffraction patterns:
//
//   maxDP    — what the app fed it BEFORE 2026-09-01 (pixel-wise max over
//              the scan; py4DSTEM's origin path still does, origin.py:268)
//   meanDP   — what py4DSTEM's own docstring says "works best"
//   minSum   — the scan position with the lowest total intensity, the closest
//              thing the cube has to a vacuum/substrate-only pattern
//   p05Sum   — the 5th-percentile-sum position, in case minSum is a dead or
//              edge artefact
//
// Under the recorded hypothesis (Bragg content above threshold is counted as
// probe area, worst in the max-union), maxDP over-measures and the other
// three land near the true central-disk radius. If meanDP ≈ maxDP, the
// threshold semantics — not the max-union — drive the error. Measures, does
// not assert; not in run-tests.sh (needs gitignored training data).

@main
struct Probe {
    static func main() async throws {
        for path in CommandLine.arguments.dropFirst() {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let reader: H5Reader
            let d: DatasetDescriptor
            do {
                reader = try H5Reader(path: path)
                d = try await reader.discoverPrimaryDataset()
            } catch {
                print("=== \(name): SKIPPED — \(error)")
                continue
            }
            let data = FourDArray(reader: reader, descriptor: d)

            guard let fit = try await OriginCalibration.tiledRun(
                data: data, descriptor: d, fitFunction: .plane
            ) else { print("=== \(name): no origin fit"); continue }

            print("=== \(name)  scan \(d.ry)x\(d.rx)  detector \(d.qy)x\(d.qx)")
            print(String(format: "  app tiledRun probeRadius   = %8.3f px   (the shipped number; fed meanDP since 2026-09-01)",
                         fit.probeRadius))
            func size(_ dp: [Float], _ label: String) {
                let (r, x0, y0) = OriginCalibration.probeSize(dp: dp, qy: d.qy, qx: d.qx)
                print(String(format: "  probeSize(%@) r = %8.3f px   centre (%.2f, %.2f)", label, r, x0, y0))
            }
            size(fit.maxDP, "maxDP )")
            size(fit.meanDP, "meanDP)")

            var sums: [(Float, Int, Int)] = []
            sums.reserveCapacity(d.ry * d.rx)
            for y in 0..<d.ry {
                let tile = try await data.scanTile(yRange: y..<(y + 1))
                let per = d.qy * d.qx
                for x in 0..<d.rx {
                    var s: Float = 0
                    for i in (x * per)..<((x + 1) * per) { s += tile.pixels[i] }
                    sums.append((s, y, x))
                }
            }
            sums.sort { $0.0 < $1.0 }
            let lo = sums[0]
            let p05 = sums[max(0, Int(0.05 * Double(sums.count - 1)))]
            let patternLo = try await data.pattern(ry: lo.1, rx: lo.2)
            let patternP05 = try await data.pattern(ry: p05.1, rx: p05.2)
            size(patternLo.pixels, "minSum) @(\(lo.1),\(lo.2))  ")
            size(patternP05.pixels, "p05Sum) @(\(p05.1),\(p05.2))")
        }
    }
}
