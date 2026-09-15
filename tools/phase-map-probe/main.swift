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

/// `truth.json` as written by `tools/demo-dataset/run.sh`: which grain, which
/// precipitate, at every scan position. Only the fields the scoring needs.
struct TruthMap {
    /// One name per position, in row-major scan order.
    let className: [String]
    /// The order classes are printed in, so a missing class still shows a row.
    static let classes = ["Al [001] grain A", "Al [011] grain B", "Al [111] grain C",
                          "β″ [010] end-on", "β″ [001] needle", "vacuum"]

    init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let grain = root["grain_label_map"] as? [[Int]],
              let precipitate = root["precipitate_map"] as? [[Int]],
              grain.count == precipitate.count, let width = grain.first?.count
        else { return nil }
        var names: [String] = []
        names.reserveCapacity(grain.count * width)
        for row in grain.indices {
            guard grain[row].count == width, precipitate[row].count == width else { return nil }
            for column in 0..<width {
                // The precipitate map wins where both are set: a precipitate
                // sits INSIDE a grain, and the pattern there carries both.
                switch (grain[row][column], precipitate[row][column]) {
                case (_, 1): names.append("β″ [010] end-on")
                case (_, 2): names.append("β″ [001] needle")
                case (0, _): names.append("Al [001] grain A")
                case (1, _): names.append("Al [011] grain B")
                case (2, _): names.append("Al [111] grain C")
                case (3, _): names.append("vacuum")
                default: names.append("unknown")
                }
            }
        }
        className = names
    }
}

@main
enum Probe {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 3,
              let probeRadius = Float(args[2]),
              let qPerPixel = Double(args[3]) else {
            print("usage: probe <datacube.h5> <probe-radius-px> <inv-angstrom-per-pixel> "
                  + "[scan-stride] [out.ppm] [--truth truth.json]")
            exit(2)
        }
        let path = args[1]

        // TRUTH MODE (added 2026-09-14, Gate D for "a second matrix grain is
        // labelled as a candidate phase"). With `--truth`, the probe stops
        // asking what a dataset can carry and starts asking whether the
        // matcher is RIGHT, because the demo cube
        // (`tools/demo-dataset/run.sh`) knows the answer at every position.
        // It then runs the demo cube's own phase list at the app's shipped
        // defaults — no probe-specific tuning — and prints a confusion matrix
        // against `truth.json`. Every other mode is unchanged.
        var truthPath: String?
        var thronsenPath: String?   // step 3: their ground truth, their metric (thronsen.swift)
        // Step 3's two user-side settings, both stated in the record: the
        // detection threshold a user would raise on seeing 22 peaks on an Al
        // pattern (shipped 0.005), and the dataset's own mask radius, which
        // the app has no setting for (the mask edge at 0.70 Å⁻¹ is a ring of
        // maxima no phase explains).
        var minRelative: Float?
        var reachInvAngstrom: Double?
        var positional: [String] = []
        var index = 4
        while index < args.count {
            if args[index] == "--thronsen", index + 1 < args.count {
                thronsenPath = args[index + 1]; index += 2
            } else if args[index] == "--min-relative", index + 1 < args.count {
                minRelative = Float(args[index + 1]); index += 2
            } else if args[index] == "--reach", index + 1 < args.count {
                reachInvAngstrom = Double(args[index + 1]); index += 2
            } else if args[index] == "--truth", index + 1 < args.count {
                truthPath = args[index + 1]; index += 2
            } else {
                positional.append(args[index]); index += 1
            }
        }
        let truth = truthPath.flatMap(TruthMap.init(path:))
        if truthPath != nil, truth == nil {
            print("could not read truth map at \(truthPath!)"); exit(1)
        }
        let thronsen = thronsenPath.flatMap(Thronsen.Truth.init(path:))
        if thronsenPath != nil, thronsen == nil {
            print("could not read Thronsen labels at \(thronsenPath!)"); exit(1)
        }
        // Truth mode scores every position; a stride would compare the map
        // against truth on a subsample and call it a measurement of the map.
        let stride = (truth != nil || thronsen != nil) ? 1 : (positional.first.flatMap(Int.init) ?? 3)

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
        referenceSettings.kMaxInvAngstrom = thronsen != nil ? Thronsen.kMaxInvAngstrom : reach
        referenceSettings.inPlaneStepDeg = 2

        var matchSettings = PhaseVectorSettings()
        if truth == nil && thronsen == nil {
            // One detector pixel, rounded up: nothing smaller can be measured
            // here, so nothing smaller may be demanded.
            matchSettings.pairRadiusInvAngstrom = max(0.02, qPerPixel)
            matchSettings.matrixToleranceInvAngstrom = matchSettings.pairRadiusInvAngstrom
            matchSettings.notIndexedAboveInvAngstrom = matchSettings.pairRadiusInvAngstrom / 2
            matchSettings.directBeamRadiusInvAngstrom = 3 * qPerPixel
        }
        // In truth mode every setting is the app's shipped default, untouched
        // above: the question is what a user gets, not what a tuned probe can
        // get. On a 0.012 Å⁻¹ detector the shipped 0.15 Å⁻¹ direct-beam radius
        // is 12.5 px, which excludes the 3 px direct disk and nothing else —
        // the nearest Al reflection is at 41 px.

        // Two β″ entries as two PHASES, not one phase with two axes: that is
        // what the app's phase list makes when the owner adds β″ twice, and
        // `bestPerPhase` keeps one winner per phase, so the shape of the
        // competition depends on it.
        let phases = thronsen != nil ? Thronsen.phases : truth != nil
            ? [
                PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                                role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
                PhaseDefinition(id: "beta010", displayName: "β″[010]",
                                crystal: .betaDoublePrime,
                                role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
                PhaseDefinition(id: "beta001", displayName: "β″[001]",
                                crystal: .betaDoublePrime,
                                role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
            ]
            : [
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
        if let minRelative {
            params.minRelativeIntensity = minRelative
            print(String(format: "detection: min relative intensity %.3f (shipped 0.005)", minRelative))
        }

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

        if let reachInvAngstrom {
            // Everything at or beyond the dataset's own mask radius is the
            // mask's edge, not a reflection; the app has no such setting.
            var dropped = 0
            for i in peaks.indices {
                let before = peaks[i].count
                peaks[i].removeAll {
                    Double(((($0.x - originX) * ($0.x - originX)
                             + ($0.y - originY) * ($0.y - originY)).squareRoot())) * qPerPixel
                        >= reachInvAngstrom
                }
                dropped += before - peaks[i].count
            }
            print(String(format: "reach: dropped %d peaks at or beyond %.3f Å⁻¹ (the dataset's mask radius)",
                         dropped, reachInvAngstrom))
        }
        let bragg = BraggVectors(scanWidth: cols.count, scanHeight: rows.count, peaks: peaks)

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
        let out = positional.count > 1 ? positional[1] : "phase-map.ppm"
        try? ppm.write(to: URL(fileURLWithPath: out))
        print("\nwrote \(out)  (\(image.width) x \(image.height))")
        // If a position is still labelled where truth says matrix, say what
        // the matrix COULD have done there — the question the 2026-09-14 Gate D
        // turned on, and the one a reader asks next.
        if let truth, truth.className.count == map.results.count,
           let probe = truth.className.indices.first(where: {
               truth.className[$0] == "Al [011] grain B"
                   && map.results[$0].verdict == .indexed
           }) {
            print("\n== A grain-B position is still labelled: position \(probe) ==")
            let vectors = PhaseVectorMatcher.experimentalVectors(
                peaks: bragg.peaks[probe], originX: originX, originY: originY,
                invAngstromPerPixel: qPerPixel,
                directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom)
            let matrixEntry = map.matrixEntryIndex >= 0
                ? library.entries[map.matrixEntryIndex] : nil
            var surviving: [SIMD2<Double>] = []
            for u in vectors {
                if let m = matrixEntry,
                   m.vectors.contains(where: {
                       simd_distance($0.q, u) <= matchSettings.matrixToleranceInvAngstrom
                   }) { continue }
                surviving.append(u)
            }
            let r = map.results[probe]
            print("  \(vectors.count) vectors, \(surviving.count) survive matrix removal; "
                  + "winner \(map.phaseNames[Int(r.phaseIndex)]) "
                  + "matched \(r.matchedCount) at \(String(format: "%.4f", r.score))")
            let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
            let bases = PhaseVectorMatcher.matrixChallengeBases(library: library)
            var free: (SIMD3<Int>, Double, Int, Double) = (SIMD3(0, 0, 0), 0, 0, .infinity)
            for base in bases {
                for theta in PhaseReferenceLibrary.inPlaneSteps(library.settings) {
                    let entry = PhaseOrientationReference(
                        phaseIndex: 0, zoneAxis: base.zoneAxis, inPlaneRotationRad: theta,
                        vectors: PhaseReferenceLibrary.rotate(base.vectors, by: theta))
                    guard let s = PhaseVectorMatcher.score(
                        vectors: surviving, against: entry,
                        pairRadius: matchSettings.pairRadiusInvAngstrom, scratch: scratch)
                    else { continue }
                    if s.matched > free.2 || (s.matched == free.2 && s.score < free.3) {
                        free = (base.zoneAxis, theta * 180 / .pi, s.matched, s.score)
                    }
                }
            }
            print(String(format: "  best matrix orientation here, searched free over %d axes: "
                         + "[%d %d %d] at %5.1f°  matched %2d  mean %.4f",
                         bases.count, free.0.x, free.0.y, free.0.z, free.1, free.2, free.3))
        }

        if let truth {
            print("\n== Against truth ==")
            guard truth.className.count == map.results.count else {
                print("  truth has \(truth.className.count) positions, the map has "
                      + "\(map.results.count) — refusing to score a mismatch")
                exit(1)
            }
            func observed(_ result: PhaseVectorResult) -> String {
                switch result.verdict {
                case .noData: return "no data"
                case .matrix: return "matrix"
                case .notIndexed: return "not indexed"
                case .indexed:
                    let i = Int(result.phaseIndex)
                    return map.phaseNames.indices.contains(i) ? map.phaseNames[i] : "indexed"
                }
            }
            var table: [String: [String: Int]] = [:]
            var columns: Set<String> = []
            for (index, result) in map.results.enumerated() {
                let label = observed(result)
                columns.insert(label)
                table[truth.className[index], default: [:]][label, default: 0] += 1
            }
            let order = ["matrix", "β″[010]", "β″[001]", "not indexed", "no data"]
            let printed = order.filter { columns.contains($0) }
                + columns.subtracting(order).sorted()
            print("  " + String(repeating: " ", count: 18)
                  + printed.map { String(format: "%13@", $0 as NSString) }.joined()
                  + "      total")
            for name in TruthMap.classes {
                guard let row = table[name] else { continue }
                let total = row.values.reduce(0, +)
                let cells = printed.map { column -> String in
                    let count = row[column] ?? 0
                    return count == 0 ? String(format: "%13@", "·" as NSString)
                        : String(format: "%8d%4.0f%%", count,
                                 100 * Double(count) / Double(max(1, total)))
                }
                print(String(format: "  %-18@", name as NSString)
                      + cells.joined() + String(format: "%11d", total))
            }
            // The pre-registered numbers, printed as numbers so the prediction
            // can be checked without arithmetic in the reader's head.
            func fraction(_ truthClass: String, _ observedLabels: [String]) -> Double {
                guard let row = table[truthClass] else { return .nan }
                let total = row.values.reduce(0, +)
                let hit = observedLabels.reduce(0) { $0 + (row[$1] ?? 0) }
                return total > 0 ? 100 * Double(hit) / Double(total) : .nan
            }
            print(String(format: "\n  grain B labelled β″          %5.1f %%  (prediction: < 5)",
                         fraction("Al [011] grain B", ["β″[010]", "β″[001]"])))
            print(String(format: "  end-on recall as β″[010]     %5.1f %%  (prediction: ≥ 95)",
                         fraction("β″ [010] end-on", ["β″[010]"])))
            print(String(format: "  needle recall as β″[001]     %5.1f %%  (prediction: ≥ 95)",
                         fraction("β″ [001] needle", ["β″[001]"])))
            print(String(format: "  grain A as matrix            %5.1f %%  (prediction: ≥ 95)",
                         fraction("Al [001] grain A", ["matrix"])))
            print(String(format: "  vacuum as no data            %5.1f %%  (prediction: 100)",
                         fraction("vacuum", ["no data"])))
        }

        if let thronsen {
            print("\n== Against Thronsen et al.'s ground truth, by their metric ==")
            guard thronsen.labels.count == map.results.count else {
                print("  truth has \(thronsen.labels.count) positions, the map has "
                      + "\(map.results.count) — refusing to score a mismatch")
                exit(1)
            }
            var table: [Int: [Int: Int]] = [:]
            var mislabelled = 0
            for (index, result) in map.results.enumerated() {
                let ours = Thronsen.label(of: result, phaseNames: map.phaseNames)
                let theirs = thronsen.labels[index]
                table[theirs, default: [:]][ours, default: 0] += 1
                if ours != theirs { mislabelled += 1 }
            }
            let columns = [0, 1, 2, 3, -1]
            let name: (Int) -> String = { $0 == -1 ? "not indexed" : (thronsen.classes[$0] ?? "\($0)") }
            print("  " + String(repeating: " ", count: 16)
                  + columns.map { String(format: "%14@", name($0) as NSString) }.joined() + "      total")
            for theirs in [0, 1, 2, 3, 4] {
                guard let row = table[theirs] else { continue }
                let total = row.values.reduce(0, +)
                let cells = columns.map { column -> String in
                    let count = row[column] ?? 0
                    return count == 0 ? String(format: "%14@", "·" as NSString)
                        : String(format: "%9d%4.0f%%", count, 100 * Double(count) / Double(max(1, total)))
                }
                print(String(format: "  %-16@", name(theirs) as NSString) + cells.joined()
                      + String(format: "%11d", total))
            }
            let fraction = 100 * Double(mislabelled) / Double(map.results.count)
            print(String(format: "\n  mislabelled %d of %d positions = %.2f %%", mislabelled,
                         map.results.count, fraction))
            print("  their four methods on the full 512 × 512: vector matching 1.54 %, template matching 1.75 %, "
                  + "NMF 1.50 %, ANN 0.96 % (reproduced from their published maps, 2026-09-15)")
            print("  pre-registered acceptance (v3-vector-matching-plan.md step 3): inside their band, "
                  + "which is 0.96–1.75 %")
            print(fraction <= 1.75 ? "  VERDICT: inside the band" : "  VERDICT: OUTSIDE the band — the implementation is wrong, not the method")
        }

        for row in PhaseMapPresentation.legend(map) {
            print(String(format: "  legend %-16@ rgb(%3d,%3d,%3d)%@ %5.1f %%",
                         row.label as NSString, Int(row.color.r), Int(row.color.g),
                         Int(row.color.b), row.hatched ? " hatched" : "        ",
                         100 * row.fraction))
        }
    }
}
