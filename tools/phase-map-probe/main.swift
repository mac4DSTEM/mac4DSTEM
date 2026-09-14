//
//  tools/phase-map-probe/main.swift
//  Step 4 of `docs/v3-vector-matching-plan.md`: run vector-matched phase
//  mapping on a real Al-Mg-Si datacube, through the app's own detector,
//  library and matcher.
//
//  `diagnostic`, not gated: it needs a machine-local cube that is not in the
//  repo, and its result is a MEASUREMENT of whether a given dataset can carry
//  this method at all — not an invariant of the code.
//
//  THE QUESTION IT ASKS FIRST, before any map is drawn, and the reason it asks
//  it first: vector matching scores DISTANCES between reciprocal-lattice
//  points. If a phase's reference vectors sit closer together than the
//  detector can resolve, every peak matches several of them and the score
//  stops meaning anything — whatever picture comes out. So the probe computes,
//  for each phase, the smallest separation between two distinct reference
//  vectors, in detector pixels, and prints it against the pair radius. A
//  phase whose vectors are one pixel apart cannot be matched on that detector,
//  and saying so is worth more than a map.
//
//  PRE-REGISTERED, before the first run (2026-09-12), from the cube's own
//  calibration of 0.04574 Å⁻¹ per detector pixel after 4x binning:
//    • β″'s a* is 0.0684 Å⁻¹ = 1.50 detector pixels, so adjacent (h0l)
//      reflections along a* are ~1.5 px apart and NOT resolvable;
//    • the pair radius must be about one detector pixel or larger to admit
//      any real peak, which is 2.3x the 0.02 Å⁻¹ default;
//    • so the prediction is that β″ is NOT separable on this cube, and the map
//      will be dominated by `.matrix` and `.notIndexed`.
//  If the map instead comes out confidently β″ everywhere, that is evidence
//  the score is saturating, not evidence of precipitates.
//

import Foundation
import simd

@main
enum Probe {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 3,
              let probeRadius = Float(args[2]),
              let qPerPixel = Double(args[3]) else {
            print("usage: probe <datacube.h5> <probe-radius-px> <inv-angstrom-per-pixel> [scan-stride]")
            exit(2)
        }
        let path = args[1]
        let stride = args.count > 4 ? (Int(args[4]) ?? 3) : 3

        guard let reader = try? H5Reader(path: path),
              let primary = try? await reader.discoverPrimaryDataset() else {
            print("could not open \(path)"); exit(1)
        }
        print("cube: ry=\(primary.ry) rx=\(primary.rx) qy=\(primary.qy) qx=\(primary.qx)")
        print(String(format: "Q calibration: %.6f Å⁻¹ per detector pixel", qPerPixel))
        let reach = Double(min(primary.qx, primary.qy)) / 2 * qPerPixel
        print(String(format: "detector reach: %.3f Å⁻¹ at the edge", reach))

        // ---- The resolution budget, before anything is matched -------------
        var referenceSettings = PhaseReferenceSettings()
        referenceSettings.kMaxInvAngstrom = reach
        referenceSettings.inPlaneStepDeg = 2

        var matchSettings = PhaseVectorSettings()
        // One detector pixel, rounded up: nothing smaller can be measured
        // here, so nothing smaller may be demanded.
        matchSettings.pairRadiusInvAngstrom = max(0.02, qPerPixel)
        matchSettings.matrixToleranceInvAngstrom = matchSettings.pairRadiusInvAngstrom
        matchSettings.notIndexedAboveInvAngstrom = matchSettings.pairRadiusInvAngstrom / 2
        matchSettings.directBeamRadiusInvAngstrom = 3 * qPerPixel

        let phases = [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                            role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
        ]
        let library: PhaseReferenceLibrary
        do {
            library = try PhaseReferenceLibrary.build(phases: phases, settings: referenceSettings)
        } catch {
            print("library: \(error)"); exit(1)
        }

        print("\n== Resolution budget ==")
        print(String(format: "pair radius: %.4f Å⁻¹ = %.2f detector pixels",
                     matchSettings.pairRadiusInvAngstrom,
                     matchSettings.pairRadiusInvAngstrom / qPerPixel))
        for (index, phase) in phases.enumerated() {
            guard let entryIndex = library.entries.firstIndex(where: { $0.phaseIndex == index })
            else { continue }
            let entry = library.entries[entryIndex]
            var closest = Double.infinity
            for i in entry.vectors.indices {
                for j in (i + 1)..<entry.vectors.count {
                    closest = min(closest, simd_distance(entry.vectors[i].q, entry.vectors[j].q))
                }
            }
            let chance = entry.chanceMatchFraction(
                pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: reach)
            print(String(format: "%@: %d vectors, closest pair %.4f Å⁻¹ = %.2f px, chance match %.1f %%",
                         phase.displayName, entry.vectors.count, closest, closest / qPerPixel,
                         100 * chance))
            if closest < 2 * matchSettings.pairRadiusInvAngstrom {
                print("    ^ UNRESOLVABLE on this detector: two distinct reflections fall inside "
                      + "one pair radius, so a single peak matches both and the score cannot "
                      + "separate them.")
            }
        }

        // ---- Detect, then match --------------------------------------------
        guard let kernel = ProbeKernel.synthetic(radius: probeRadius, qy: primary.qy, qx: primary.qx),
              let detector = DiskDetector(kernel: kernel) else {
            print("kernel/detector failed"); exit(1)
        }
        var params = DiskDetectionParams()
        params.minPeakSpacing = max(3, probeRadius.rounded())
        params.edgeBoundary = 2

        let rows = Swift.stride(from: 0, to: primary.ry, by: stride).map { $0 }
        let cols = Swift.stride(from: 0, to: primary.rx, by: stride).map { $0 }
        print("\n== Detection ==")
        print("sampling \(rows.count) x \(cols.count) = \(rows.count * cols.count) positions "
              + "(stride \(stride)), probe radius \(probeRadius) px")

        let view = LoadView(fullExtentOf: primary)
        var peaks: [[BraggPeak]] = []
        peaks.reserveCapacity(rows.count * cols.count)
        var read = 0
        for ry in rows {
            for rx in cols {
                if let pattern = try? await reader.readPattern(view, ry: ry, rx: rx) {
                    peaks.append(detector.detect(pattern: pattern, params: params))
                    read += 1
                } else {
                    peaks.append([])
                }
            }
        }
        let counts = peaks.map(\.count)
        let total = counts.reduce(0, +)
        print("read \(read) patterns, \(total) peaks, median "
              + "\(counts.sorted()[counts.count / 2]), range "
              + "\(counts.min() ?? 0)–\(counts.max() ?? 0)")

        let bragg = BraggVectors(scanWidth: cols.count, scanHeight: rows.count, peaks: peaks)

        // THE ORIGIN IS MEASURED, not assumed to be the detector centre.
        // Half a pixel here is 0.023 Å⁻¹, which is half the pair radius on
        // this cube — an assumed centre would shift every experimental vector
        // by more than the tolerance the match is judged on. Centre of mass of
        // the mean pattern inside the direct beam, which is what
        // `OriginCalibration` does per position in the app.
        var mean = [Double](repeating: 0, count: primary.qy * primary.qx)
        var meanCount = 0
        for ry in Swift.stride(from: 0, to: primary.ry, by: max(1, primary.ry / 20)) {
            guard let pattern = try? await reader.readPattern(view, ry: ry, rx: primary.rx / 2)
            else { continue }
            for i in 0..<min(mean.count, pattern.count) { mean[i] += Double(pattern[i]) }
            meanCount += 1
        }
        var sum = 0.0, sx = 0.0, sy = 0.0
        let cy = Double(primary.qy - 1) / 2, cx = Double(primary.qx - 1) / 2
        for y in 0..<primary.qy {
            for x in 0..<primary.qx {
                let r = ((Double(y) - cy) * (Double(y) - cy)
                         + (Double(x) - cx) * (Double(x) - cx)).squareRoot()
                guard r <= 6 else { continue }
                let w = mean[y * primary.qx + x]
                sum += w; sy += w * Double(y); sx += w * Double(x)
            }
        }
        let originX = sum > 0 ? Float(sx / sum) : Float(cx)
        let originY = sum > 0 ? Float(sy / sum) : Float(cy)
        print(String(format: "\nmeasured origin: (%.3f, %.3f) from %d patterns; "
                     + "the geometric centre is (%.1f, %.1f), a difference of %.3f px = %.4f Å⁻¹",
                     originX, originY, meanCount, cx, cy,
                     ((Double(originX) - cx) * (Double(originX) - cx)
                      + (Double(originY) - cy) * (Double(originY) - cy)).squareRoot(),
                     ((Double(originX) - cx) * (Double(originX) - cx)
                      + (Double(originY) - cy) * (Double(originY) - cy)).squareRoot() * qPerPixel))

        // WHICH ZONE AXIS IS THE MATRIX ON? Asked rather than assumed: a phase
        // map built on the wrong matrix orientation removes nothing and calls
        // the whole scan "not indexed", which looks exactly like a method that
        // does not work. Every low-index axis is fitted and the best five are
        // printed with what they explain.
        print("\n== Matrix zone axis ==")
        var sweepSettings = referenceSettings
        sweepSettings.inPlaneStepDeg = 5
        sweepSettings.maximumEntries = 60000
        if let sweep = try? PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: []),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                            role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
        ], settings: sweepSettings) {
            var byAxis: [SIMD3<Int>: (matched: Int, mean: Double, deg: Double)] = [:]
            let scratch = PhaseVectorMatcher.Scratch(
                capacity: sweep.entries.map(\.vectors.count).max() ?? 1)
            let sample = Swift.stride(from: 0, to: peaks.count, by: max(1, peaks.count / 400))
                .map { PhaseVectorMatcher.experimentalVectors(
                    peaks: peaks[$0], originX: originX, originY: originY,
                    invAngstromPerPixel: qPerPixel,
                    directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom) }
                .filter { !$0.isEmpty }
            for entryIndex in sweep.matrixEntryIndices {
                let entry = sweep.entries[entryIndex]
                var matched = 0, pairs = 0
                var total = 0.0
                for vectors in sample {
                    guard let sc = PhaseVectorMatcher.score(
                        vectors: vectors, against: entry,
                        pairRadius: matchSettings.matrixToleranceInvAngstrom,
                        scratch: scratch) else { continue }
                    matched += sc.matched
                    total += sc.score * Double(sc.uniqueReferences)
                    pairs += sc.uniqueReferences
                }
                guard pairs > 0 else { continue }
                let record = (matched, total / Double(pairs),
                              entry.inPlaneRotationRad * 180 / .pi)
                if let existing = byAxis[entry.zoneAxis], existing.matched >= matched { continue }
                byAxis[entry.zoneAxis] = record
            }
            let ranked = byAxis.sorted { $0.value.matched > $1.value.matched }.prefix(5)
            let peaksInSample = sample.reduce(0) { $0 + $1.count }
            print("  \(sample.count) sampled patterns, \(peaksInSample) vectors outside the direct beam")
            for (axis, record) in ranked {
                print(String(format: "  [%d %d %d]  explains %5d of %d (%4.1f %%)  "
                             + "mean %.4f Å⁻¹  at %.0f°",
                             axis.x, axis.y, axis.z, record.matched, peaksInSample,
                             100 * Double(record.matched) / Double(max(1, peaksInSample)),
                             record.mean, record.deg))
            }
        }

        print("\n== Matching ==")
        guard let map = PhaseVectorMatcher.map(
            bragg: bragg, library: library, settings: matchSettings,
            originX: originX, originY: originY, invAngstromPerPixel: qPerPixel
        ) else { print("matcher returned nil"); exit(1) }

        let n = Double(max(1, map.results.count))
        for verdict in PhaseVerdict.allCases {
            let c = map.count(of: verdict)
            print(String(format: "  %-12@ %6d  %5.1f %%", verdict.displayName as NSString,
                         c, 100 * Double(c) / n))
        }
        for (index, name) in map.phaseNames.enumerated() {
            let c = map.phaseCounts[index]
            print(String(format: "  phase %-8@ %6d  %5.1f %%", name as NSString,
                         c, 100 * Double(c) / n))
        }
        if map.matrixEntryIndex >= 0 {
            print(String(format: "  matrix in-plane fit: %.1f° (mod the projected symmetry)",
                         library.entries[map.matrixEntryIndex].inPlaneRotationRad * 180 / .pi))
        }
        let scores = map.results.filter { $0.verdict == .indexed && $0.score.isFinite }
            .map { Double($0.score) }.sorted()
        if !scores.isEmpty {
            print(String(format: "  indexed mean distance: median %.4f Å⁻¹ (%.2f px), worst %.4f",
                         scores[scores.count / 2], scores[scores.count / 2] / qPerPixel,
                         scores.last!))
        }

        // ---- The map, as a PPM the reader can open --------------------------
        let image = PhaseMapPresentation.image(map)
        var ppm = "P6\n\(image.width) \(image.height)\n255\n".data(using: .ascii)!
        for i in 0..<(image.width * image.height) {
            let base: Int = i * 4
            let triple: [UInt8] = [image.rgba[base], image.rgba[base + 1], image.rgba[base + 2]]
            ppm.append(contentsOf: triple)
        }
        let out = (args.count > 5 ? args[5] : "phase-map.ppm")
        try? ppm.write(to: URL(fileURLWithPath: out))
        print("\nwrote \(out)  (\(image.width) x \(image.height))")
        for row in PhaseMapPresentation.legend(map) {
            print(String(format: "  legend %-16@ rgb(%3d,%3d,%3d)%@ %5.1f %%",
                         row.label as NSString, Int(row.color.r), Int(row.color.g),
                         Int(row.color.b), row.hatched ? " hatched" : "        ",
                         100 * row.fraction))
        }
    }
}
