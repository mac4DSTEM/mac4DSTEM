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
        var minMatched: Int?        // the rule step 3 turned on: `minimumMatchedVectors`
        var referenceOutsidePx: Float?   // decision 3: the relative reference excludes the direct beam
        var notIndexedAbove: Double?
        // 2026-09-16: the cap is applied at DETECTION and keeps the strongest
        // by net score, so what it drops is the weakest — here the precipitate
        // reflections at 1–5 % of a saturated beam. On this cube the outer
        // reach alone (0.68 Å⁻¹ = 35.7 px, 224 px of circumference at a 3 px
        // minimum spacing) can hold 74 maxima, more than the whole cap, and
        // `--reach` discards them only AFTER detection has spent it on them.
        // `--noise-floor` already raises this to 200; the pipeline never did.
        var maxPeaks: Int?
        var matrixFallback: Double?
        var noiseFloor = false      // the noise-floor experiment (Gate D record: docs/open-items.md, step 3); only with --thronsen
        var t1OriginExperiment = false   // Gate D (docs/open-items.md, T1 entry): re-run the not-indexed T1 positions with a PER-POSITION direct-beam origin; only with --thronsen
        var dumpPeaksPath: String?   // export the calibrated experimental peaks (qx,qy,intensity Å⁻¹) + truth + verdict per position, for a py4DSTEM head-to-head; only with --thronsen
        var completenessGuard = false   // item K: PhaseVectorSettings.completenessAwareCrossPhaseRanking, off-by-default candidate
        var orientationRelationship = false   // 2026-09-15: constrain candidates to their listed in-plane angles
        // 2026-09-15 evening: what ARE the surviving spots at correctly-labelled
        // edge-on positions whose winner sits near 22°/67° to the matrix, not at
        // the OR's {0, 90}? (docs/open-items.md, step 3, "Next instrument".)
        var dumpEdgeOnCount: Int?
        // Gate D measurement, 2026-09-21 (v3-vector-matching-plan.md step 1):
        // additive, off by default, zero behaviour change without it. Breaks
        // named truth→ours confusion cells into survivingCount/matchedCount/
        // removedCount histograms and score quantiles, so a residual can be
        // read instead of re-derived by hand.
        var residualDetail = false
        // Session S1 (v3-precipitates-and-materials-project-plan.md §2):
        // `--rule known-variants` runs Thronsen et al.'s own per-position
        // rule (`PhaseVectorSettings.ClassificationRule.knownVariants`)
        // instead of the library search; `--residual-cutoff` and
        // `--direct-matrix-max` are that rule's two settings, plumbed
        // through so the pre-registered 0.07 / 1 can be swept without
        // editing the app.
        var ruleArg: String?
        var residualCutoffArg: Double?
        var directMatrixMaxArg: Int?
        // Gate D MEASUREMENT, 2026-09-21 (docs/archive/v3/phase-map-residual-detail-2026-09-21.md
        // follow-up): additive, off by default, zero behaviour change without
        // it. `--rule known-variants` only. For truth-T1 positions, the
        // per-survivor nearest-reference distance and |q| against the
        // winning (or would-be winning) T1 entry, bucketed — is the excess
        // of not-indexed T1 residual explained by detection noise (far
        // survivors spread in |q|) or by real unmodelled reflections (far
        // survivors peaked at specific |q|)?
        var survivorDetail = false
        // Gate D MEASUREMENT, 2026-09-21 (survivor-detail follow-up): additive,
        // off by default, zero behaviour change without them. `--min-intensity`
        // and `--max-vectors` plumb straight to `PhaseReferenceSettings`'
        // `minimumIntensityFraction` (shipped 0.05) and `maximumVectorsPerEntry`
        // (shipped 48) — the two settings suspected of dropping T1's [0 -4 1]
        // ZOLZ reflections at 0.233/0.367/0.679 Å⁻¹ from the library entry.
        // `--dump-entry PHASE` prints that entry's own vector table so the
        // suspicion can be read directly instead of re-derived.
        var minIntensityArg: Double?
        var maxVectorsArg: Int?
        var dumpEntryPhase: String?
        var positional: [String] = []
        var index = 4
        while index < args.count {
            if args[index] == "--thronsen", index + 1 < args.count {
                thronsenPath = args[index + 1]; index += 2
            } else if args[index] == "--min-relative", index + 1 < args.count {
                minRelative = Float(args[index + 1]); index += 2
            } else if args[index] == "--reach", index + 1 < args.count {
                reachInvAngstrom = Double(args[index + 1]); index += 2
            } else if args[index] == "--not-indexed-above", index + 1 < args.count {
                // The verdict cliff as an absolute Å⁻¹ value (shipped 0.015, 0.75
                // a pixel); the cliff pre-registration of 2026-09-15 evening.
                notIndexedAbove = Double(args[index + 1]); index += 2
            } else if args[index] == "--matrix-fallback", index + 1 < args.count {
                matrixFallback = Double(args[index + 1]); index += 2
            } else if args[index] == "--max-peaks", index + 1 < args.count {
                maxPeaks = Int(args[index + 1]); index += 2
            } else if args[index] == "--min-matched", index + 1 < args.count {
                minMatched = Int(args[index + 1]); index += 2
            } else if args[index] == "--reference-outside", index + 1 < args.count {
                referenceOutsidePx = Float(args[index + 1]); index += 2
            } else if args[index] == "--truth", index + 1 < args.count {
                truthPath = args[index + 1]; index += 2
            } else if args[index] == "--completeness-guard" {
                completenessGuard = true; index += 1
            } else if args[index] == "--noise-floor" {
                noiseFloor = true; index += 1
            } else if args[index] == "--t1-origin-experiment" {
                t1OriginExperiment = true; index += 1
            } else if args[index] == "--dump-peaks", index + 1 < args.count {
                dumpPeaksPath = args[index + 1]; index += 2
            } else if args[index] == "--or" {
                orientationRelationship = true; index += 1
            } else if args[index] == "--residual-detail" {
                residualDetail = true; index += 1
            } else if args[index] == "--survivor-detail" {
                survivorDetail = true; index += 1
            } else if args[index] == "--rule", index + 1 < args.count {
                ruleArg = args[index + 1]; index += 2
            } else if args[index] == "--residual-cutoff", index + 1 < args.count {
                residualCutoffArg = Double(args[index + 1]); index += 2
            } else if args[index] == "--direct-matrix-max", index + 1 < args.count {
                directMatrixMaxArg = Int(args[index + 1]); index += 2
            } else if args[index] == "--min-intensity", index + 1 < args.count {
                minIntensityArg = Double(args[index + 1]); index += 2
            } else if args[index] == "--max-vectors", index + 1 < args.count {
                maxVectorsArg = Int(args[index + 1]); index += 2
            } else if args[index] == "--dump-entry", index + 1 < args.count {
                dumpEntryPhase = args[index + 1]; index += 2
            } else if args[index] == "--dump-edge-on" {
                if index + 1 < args.count, let n = Int(args[index + 1]) {
                    dumpEdgeOnCount = n; index += 2
                } else {
                    dumpEdgeOnCount = 12; index += 1
                }
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
        if noiseFloor, thronsen == nil {
            print("--noise-floor only means anything with --thronsen; ignoring")
            noiseFloor = false
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
        if let minIntensityArg {
            referenceSettings.minimumIntensityFraction = minIntensityArg
            print(String(format: "reference library: minimum intensity fraction %.4f (shipped 0.05)",
                         minIntensityArg))
        }
        if let maxVectorsArg {
            referenceSettings.maximumVectorsPerEntry = maxVectorsArg
            print("reference library: maximum vectors per entry \(maxVectorsArg) (shipped 48)")
        }

        var matchSettings = PhaseVectorSettings()   // `var`: the reach and the floor are set below
        if completenessGuard {
            matchSettings.completenessAwareCrossPhaseRanking = true
            print("matching: cross-phase ranking is completeness-aware (shipped: mean distance alone)")
        }
        if let minMatched {
            matchSettings.minimumMatchedVectors = minMatched
            print("matching: minimumMatchedVectors \(minMatched) (shipped 3)")
        }
        if let matrixFallback {
            matchSettings.matrixFallbackExplainedFraction = matrixFallback
            print(String(format: "matching: matrix fallback at %.2f explained (shipped 0 = off)", matrixFallback))
        }
        if let notIndexedAbove {
            matchSettings.notIndexedAboveInvAngstrom = notIndexedAbove
            print(String(format: "matching: not indexed above %.4f Å⁻¹ (shipped 0.015)", notIndexedAbove))
        }
        if let ruleArg {
            switch ruleArg {
            case "search": matchSettings.classificationRule = .search
            case "known-variants": matchSettings.classificationRule = .knownVariants
            default:
                print("--rule must be 'search' or 'known-variants', got '\(ruleArg)'"); exit(2)
            }
            print("matching: classification rule \(ruleArg) (shipped search)")
        }
        if let residualCutoffArg {
            matchSettings.residualCutoffInvAngstrom = residualCutoffArg
            print(String(format: "matching: residual cutoff %.4f Å⁻¹ (shipped 0.07, knownVariants only)",
                         residualCutoffArg))
        }
        if let directMatrixMaxArg {
            matchSettings.directMatrixMaximumVectors = directMatrixMaxArg
            print("matching: direct matrix max \(directMatrixMaxArg) survivors (shipped 1, knownVariants only)")
        }
        if truth == nil && thronsen == nil {
            // One detector pixel, rounded up: nothing smaller can be measured
            // here, so nothing smaller may be demanded.
            matchSettings.pairRadiusInvAngstrom = max(0.02, qPerPixel)
            matchSettings.matrixToleranceInvAngstrom = matchSettings.pairRadiusInvAngstrom
            matchSettings.notIndexedAboveInvAngstrom = matchSettings.pairRadiusInvAngstrom * 0.75
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
        let phases = thronsen != nil ? Thronsen.phases(constrained: orientationRelationship) : truth != nil
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

        // --dump-entry PHASE: additive, off by default. The entry at in-plane
        // rotation 0 (or the phase's first entry, if 0 was somehow absent) —
        // not the whole rotation sweep — because the vector SET a phase's
        // entries carry does not depend on the in-plane rotation, only on
        // `minimumIntensityFraction` and `maximumVectorsPerEntry` above.
        if let dumpEntryPhase {
            print("\n== --dump-entry \(dumpEntryPhase) ==")
            print("  total library entries: \(library.entries.count)")
            if let phaseIndex = phases.firstIndex(where: { $0.displayName == dumpEntryPhase }) {
                let candidates = library.entries.indices.filter { library.entries[$0].phaseIndex == phaseIndex }
                if candidates.isEmpty {
                    print("  phase '\(dumpEntryPhase)' has no library entries")
                } else {
                    let entryIndex = candidates.first(where: { library.entries[$0].inPlaneRotationRad == 0 })
                        ?? candidates[0]
                    let entry = library.entries[entryIndex]
                    let chance = entry.chanceMatchFraction(
                        pairRadius: matchSettings.pairRadiusInvAngstrom, accessibleRadius: reach)
                    print(String(format: "  entry: zone axis [%d %d %d], in-plane rotation %.1f°, %d vectors",
                                 entry.zoneAxis.x, entry.zoneAxis.y, entry.zoneAxis.z,
                                 entry.inPlaneRotationRad * 180 / .pi, entry.vectors.count))
                    print(String(format: "  chanceMatchFraction(pairRadius: %.4f, accessibleRadius: %.4f) = %.4f (%.1f %%)",
                                 matchSettings.pairRadiusInvAngstrom, reach, chance, 100 * chance))
                    // Already sorted by |q| (`ReferenceVector`'s own contract).
                    for v in entry.vectors {
                        print(String(format: "    |q| %.4f  rel.intensity %.4f  (%d %d %d)",
                                     v.length, v.relativeIntensity, v.h, v.k, v.l))
                    }
                }
            } else {
                print("  no phase named '\(dumpEntryPhase)' in this run")
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
        if let maxPeaks {
            params.maxNumPeaks = maxPeaks
            print("detection: max peaks \(maxPeaks) (shipped 70)")
        }
        if let minRelative {
            params.minRelativeIntensity = minRelative
            // %.3f printed 0.0005 as "0.001" — a log that misstates the setting it
            // was run at is worse than no log (2026-09-16).
            print(String(format: "detection: min relative intensity %.5f (shipped 0.005)", minRelative))
        }
        if let referenceOutsidePx {
            params.relativeReferenceMinimumRadiusPx = referenceOutsidePx
            print(String(format: "detection: relative reference is the brightest maximum outside %.1f px of the brightest maximum", referenceOutsidePx))
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
        // Whether the cap BOUND is the whole question of the 2026-09-16
        // pre-registration, so it is printed, not left to be inferred from
        // the range. A position at the cap had its weakest peaks cut.
        let atCap = counts.filter { $0 >= params.maxNumPeaks }.count
        print(String(format: "peak cap %d: %d of %d positions at it (%.1f %%)",
                     params.maxNumPeaks, atCap, counts.count,
                     100 * Double(atCap) / Double(max(1, counts.count))))

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
            // The dataset's own mask radius, through the app's own setting
            // (`maximumVectorInvAngstrom`, 2026-09-15): everything at or
            // beyond it is the mask's edge, not a reflection.
            matchSettings.maximumVectorInvAngstrom = reachInvAngstrom
            print(String(format: "reach: peaks at or beyond %.3f Å⁻¹ are ignored (the dataset's mask radius)",
                         reachInvAngstrom))
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
                    directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                    maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom) }
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
            let fittedMatrixEntry = library.entries[map.matrixEntryIndex]
            print(String(format: "  matrix in-plane fit: %.1f° (mod the projected symmetry)",
                         fittedMatrixEntry.inPlaneRotationRad * 180 / .pi))
            // Gate D measurement, 2026-09-21 (edge-on -> Al mechanism): the
            // fitted entry's own identity, so two runs differing only in
            // `--rule` can be checked for an identical matrix fit rather than
            // inferred from the in-plane angle alone.
            print(String(format: "  matrix entry: index %d, zone axis [%d %d %d]",
                         map.matrixEntryIndex, fittedMatrixEntry.zoneAxis.x,
                         fittedMatrixEntry.zoneAxis.y, fittedMatrixEntry.zoneAxis.z))
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
                directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
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
            // --dump-peaks: the SAME calibrated experimental peaks the matcher
            // sees (origin subtracted, direct beam + reach removed) with their
            // intensities, plus truth and this run's verdict — for feeding
            // py4DSTEM's own phase method the identical input (method, not
            // detection, is the variable).
            if let dumpPeaksPath {
                let dbR = matchSettings.directBeamRadiusInvAngstrom
                let reach = matchSettings.maximumVectorInvAngstrom
                var lines: [String] = []
                lines.reserveCapacity(map.results.count)
                for (index, result) in map.results.enumerated() {
                    let row = index / cols.count, col = index % cols.count
                    var pts: [String] = []
                    for p in peaks[index] {
                        let qx = (Double(p.x) - Double(originX)) * qPerPixel
                        let qy = (Double(p.y) - Double(originY)) * qPerPixel
                        let len = (qx * qx + qy * qy).squareRoot()
                        guard len.isFinite, len > dbR, reach <= 0 || len < reach else { continue }
                        pts.append(String(format: "[%.6f,%.6f,%.4f]", qx, qy, Double(p.intensity)))
                    }
                    let verdict: String
                    var phase = -1
                    switch result.verdict {
                    case .matrix: verdict = "matrix"; phase = Int(result.phaseIndex)
                    case .indexed: verdict = "indexed"; phase = Int(result.phaseIndex)
                    case .notIndexed: verdict = "notIndexed"
                    case .noData: verdict = "noData"
                    }
                    lines.append("{\"i\":\(index),\"row\":\(row),\"col\":\(col),\"truth\":\(thronsen.labels[index]),\"verdict\":\"\(verdict)\",\"phase\":\(phase),\"peaks\":[\(pts.joined(separator: ","))]}")
                }
                let names = map.phaseNames.map { "\"\($0)\"" }.joined(separator: ",")
                let header = "{\"qPerPixel\":\(qPerPixel),\"originX\":\(originX),\"originY\":\(originY),\"scanRows\":\(rows.count),\"scanCols\":\(cols.count),\"directBeamRadius\":\(dbR),\"reach\":\(reach),\"phaseNames\":[\(names)],\"positions\":[\n"
                let json = header + lines.joined(separator: ",\n") + "\n]}\n"
                try? json.write(toFile: dumpPeaksPath, atomically: true, encoding: .utf8)
                print("\n  --dump-peaks: wrote \(map.results.count) positions to \(dumpPeaksPath)")
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

            // Session S1: with `--rule known-variants`, print per truth class
            // the winner-score quantiles for indexed AND for not-indexed
            // positions, unconditionally (not behind --residual-detail) --
            // so where `residualCutoffInvAngstrom` (0.07 shipped) falls on
            // THIS dataset's own score distribution is visible without
            // re-deriving it, and the cutoff is never tuned to the truth
            // blind.
            if matchSettings.classificationRule == .knownVariants {
                print(String(format: "\n== known-variants: winner-score quantiles by truth class (cutoff %.4f Å⁻¹) ==",
                             matchSettings.residualCutoffInvAngstrom))
                func scoreQuantiles(_ values: [Double]) -> String {
                    guard !values.isEmpty else { return "n=0 (no finite scores)" }
                    let s = values.sorted()
                    func at(_ p: Double) -> Double {
                        s[max(0, min(s.count - 1, Int((Double(s.count - 1) * p).rounded())))]
                    }
                    return String(format: "n=%-6d min=%.4f p10=%.4f p50=%.4f p90=%.4f max=%.4f",
                                  s.count, s.first!, at(0.10), at(0.50), at(0.90), s.last!)
                }
                for (label, wantIndexed) in [("indexed", true), ("not indexed", false)] {
                    print("  -- \(label) --")
                    for theirs in [0, 1, 2, 3] {
                        let values = map.results.enumerated().compactMap { index, result -> Double? in
                            guard thronsen.labels[index] == theirs, result.score.isFinite,
                                  (result.verdict == .indexed) == wantIndexed,
                                  result.verdict == .indexed || result.verdict == .notIndexed
                            else { return nil }
                            return Double(result.score)
                        }
                        guard !values.isEmpty else { continue }
                        print(String(format: "  %-14@ ", name(theirs) as NSString) + scoreQuantiles(values))
                    }
                }
            }

            // --residual-detail: additive, off by default. For named
            // truth→ours cells, break survivingCount/matchedCount/removedCount
            // (PhaseVectorMatching.swift:275-305) into histograms and score
            // (Å⁻¹) into quantiles.
            if residualDetail {
                // `dumpIndices`: Gate D measurement, 2026-09-21 (edge-on ->
                // Al mechanism, docs/open-items.md "Known-variants rule at
                // floor 0"). The (truth theta-edge-on -> ours Al) cell is
                // labelled Al 107 times under `--rule known-variants` but
                // only 20 under `--rule search` at the same floor; both
                // rules can only reach `ours == Al` via `PhaseVerdict.matrix`
                // (`Thronsen.label` maps `.matrix` to 0 unconditionally, and
                // `.indexed` at the matrix's own phase falls through its
                // `default: return -1`, thronsen.swift:130-143) — so this
                // cell's members are exactly each run's `.matrix` verdicts,
                // and printing their indices lets the two runs' membership be
                // intersected directly instead of re-derived.
                struct Cell { let title: String; let theirs: Int; let ours: Int; let notIndexed: Bool
                    let dumpIndices: Bool }
                let residualCells: [Cell] = [
                    Cell(title: "T1 (truth) -> not indexed (ours)", theirs: 3, ours: -1, notIndexed: true, dumpIndices: false),
                    Cell(title: "Al (truth) -> not indexed (ours)", theirs: 0, ours: -1, notIndexed: true, dumpIndices: false),
                    Cell(title: "theta-edge-on (truth) -> T1 (ours)", theirs: 1, ours: 3, notIndexed: false, dumpIndices: false),
                    Cell(title: "theta-edge-on (truth) -> Al (ours)", theirs: 1, ours: 0, notIndexed: false,
                         dumpIndices: true),
                    Cell(title: "T1 (truth) -> T1 (ours), reference", theirs: 3, ours: 3, notIndexed: false, dumpIndices: false),
                    Cell(title: "Al (truth) -> Al (ours), reference", theirs: 0, ours: 0, notIndexed: false, dumpIndices: false),
                ]
                let bucketLabels = ["0", "1", "2", "3", "4", "5", "6-9", "10+"]
                func bucketOf(_ n: Int32) -> Int {
                    switch n {
                    case 0, 1, 2, 3, 4, 5: return Int(n)
                    case 6...9: return 6
                    default: return 7
                    }
                }
                func histogram(_ values: [Int32]) -> String {
                    var counts = [Int](repeating: 0, count: bucketLabels.count)
                    for v in values { counts[bucketOf(v)] += 1 }
                    return zip(bucketLabels, counts).map { "\($0)=\($1)" }.joined(separator: " ")
                }
                func quantiles(_ values: [Double]) -> String {
                    let s = values.sorted()
                    guard !s.isEmpty else { return "n=0 (no finite scores)" }
                    func at(_ p: Double) -> Double {
                        s[max(0, min(s.count - 1, Int((Double(s.count - 1) * p).rounded())))]
                    }
                    return String(format: "n=%d min=%.4f p10=%.4f p50=%.4f p90=%.4f max=%.4f",
                                  s.count, s.first!, at(0.10), at(0.50), at(0.90), s.last!)
                }
                print("\n== --residual-detail ==")
                print(String(format: "  settings in play: minimumVectors=%d minimumMatchedVectors=%d "
                              + "friedelPairMinimumMatchedVectors=%d chanceMatchMultiple=%.1f "
                              + "notIndexedAboveInvAngstrom=%.4f minimumPhaseContrastInvAngstrom=%.4f",
                              matchSettings.minimumVectors, matchSettings.minimumMatchedVectors,
                              matchSettings.friedelPairMinimumMatchedVectors, matchSettings.chanceMatchMultiple,
                              matchSettings.notIndexedAboveInvAngstrom, matchSettings.minimumPhaseContrastInvAngstrom))
                for cell in residualCells {
                    let matches = map.results.enumerated().filter { index, result in
                        thronsen.labels[index] == cell.theirs
                            && Thronsen.label(of: result, phaseNames: map.phaseNames) == cell.ours
                    }
                    let members = matches.map(\.element)
                    print("\n  \(cell.title): n=\(members.count)")
                    guard !members.isEmpty else { continue }
                    print("    survivingCount " + histogram(members.map(\.survivingCount)))
                    print("    matchedCount   " + histogram(members.map(\.matchedCount)))
                    print("    removedCount   " + histogram(members.map(\.removedCount)))
                    print("    score (Å⁻¹)    "
                          + quantiles(members.filter { $0.score.isFinite }.map { Double($0.score) }))
                    if cell.dumpIndices {
                        let indices = matches.map(\.offset)
                        print("    position indices (n=\(indices.count), capped at 120): "
                              + indices.prefix(120).map(String.init).joined(separator: ","))
                        // known-variants can reach `.matrix` (hence `ours ==
                        // Al`) ONLY through the survivor-count exclusion
                        // (PhaseVectorMatching.swift classifyKnownVariants
                        // step b, :1064-1069) — step c explicitly excludes the
                        // matrix's own phase (:1108) and there is no other
                        // `.matrix` return in that function. So a > 0 count
                        // below, for this rule, would prove some OTHER path to
                        // `.matrix` exists (mechanism B); 0 confirms every
                        // member here went through survivor-count exclusion.
                        if matchSettings.classificationRule == .knownVariants {
                            let atOrBelow = members.filter {
                                Int($0.survivingCount) <= matchSettings.directMatrixMaximumVectors
                            }.count
                            print("    known-variants .matrix split: survivingCount<="
                                  + "\(matchSettings.directMatrixMaximumVectors) = \(atOrBelow), "
                                  + ">\(matchSettings.directMatrixMaximumVectors) = \(members.count - atOrBelow)"
                                  + "  (a nonzero second number proves mechanism B)")
                        }
                    }
                    if cell.notIndexed {
                        // Approximated from counts: PhaseVectorResult
                        // (PhaseVectorMatching.swift:275-305) records no refusal
                        // reason. `.noData` = no peaks; `.notIndexed` with
                        // matchedCount==0/score NaN never reached classify's
                        // bestPerPhase (no candidate cleared minimumMatchedVectors
                        // / chanceMatchMultiple, or --or excluded every entry,
                        // PhaseVectorMatching.swift:845-867); `.notIndexed` with a
                        // finite score is the notIndexedAboveInvAngstrom cliff
                        // (:898) — minimumPhaseContrastInvAngstrom is 0 (off) this
                        // run, so the margin refusal (:902-908) cannot fire.
                        // surviving<minimumVectors (:819) returns .matrix, not
                        // .notIndexed, so it cannot appear in this cell; printed
                        // as a check that should read 0.
                        let noData = members.filter { $0.verdict == .noData }.count
                        let floorOrChance = members.filter { $0.verdict == .notIndexed && $0.matchedCount == 0 }.count
                        let cliff = members.filter { $0.verdict == .notIndexed && $0.matchedCount > 0 }.count
                        let survivingBelowFloor = members.filter { Int($0.survivingCount) < matchSettings.minimumVectors }.count
                        print(String(format: "    refusal (approximated): noData=%d floor/chance=%d cliff=%d "
                                      + "(surviving<minimumVectors=%d, expect 0)",
                                      noData, floorOrChance, cliff, survivingBelowFloor))
                    }
                }
            }

            // --survivor-detail: additive, off by default, `--rule
            // known-variants` only. Refuting-observation test (Gate D
            // measurement follow-up to phase-map-residual-detail-2026-09-21.md):
            // for every truth-T1 position, find the winning (or would-be
            // winning) T1 entry — `result.entryIndex` itself when the
            // matcher's own overall winner is already T1, else the best T1
            // entry by the SAME step-c scoring `classifyKnownVariants` uses,
            // recomputed here only because that per-entry number is not
            // carried in `PhaseVectorResult` — and for every survivor at
            // that position, its true nearest-reference distance d against
            // that entry's vectors and its |q|. If the far (d > 0.05)
            // survivors' |q| bunches at T1's own ZOLZ radii (0.233, 0.367,
            // 0.467, 0.493, 0.679 Å⁻¹) or Al {220} (0.700), they are
            // reflections the reference does not carry, not noise; if they
            // spread, they look like detection noise admitted by a
            // relative threshold far looser than the paper's.
            if survivorDetail, matchSettings.classificationRule != .knownVariants {
                print("\n== --survivor-detail (known-variants rule; truth-T1 positions) ==")
                print("  --survivor-detail only means anything with --rule known-variants; skipped")
            }
            if survivorDetail, matchSettings.classificationRule == .knownVariants {
                print("\n== --survivor-detail (known-variants rule; truth-T1 positions) ==")
                let t1Label = 3, alLabel = 0   // Thronsen.swift header: 0 Al, 3 T1
                let t1PhaseIndex = map.phaseNames.firstIndex(of: "T1") ?? -1
                let t1Entries = library.entries.indices.filter {
                    Int(library.entries[$0].phaseIndex) == t1PhaseIndex
                }
                if t1PhaseIndex < 0 || t1Entries.isEmpty {
                    print("  no T1 phase / entries in this library; skipped")
                } else {
                let matrixEntry = map.matrixEntryIndex >= 0 ? library.entries[map.matrixEntryIndex] : nil
                // A radius no real Å⁻¹ distance on this cube can exceed (reach
                // is 0.68 Å⁻¹, so no two vectors within it are farther apart
                // than ~1.36): passing it to the SAME package function the
                // matrix-removal step calls, `PhaseVectorMatcher.nearest(_:in:
                // radius:)`, turns its length-band-pruned search into a plain
                // true-nearest-neighbour lookup — reusing that call instead of
                // hand-rolling the brute-force loop `nearestReferenceVector`
                // (private to PhaseVectorMatching.swift) already is.
                let unbounded = 999.0

                var dSamples: [Double] = []
                var qSamples: [Double] = []   // parallel to dSamples
                var meanSurvivors: [Int: (sum: Int, n: Int)] = [t1Label: (0, 0), alLabel: (0, 0)]

                for (index, result) in map.results.enumerated() {
                    let theirs = thronsen.labels[index]
                    guard theirs == t1Label || theirs == alLabel else { continue }
                    meanSurvivors[theirs]!.sum += Int(result.survivingCount)
                    meanSurvivors[theirs]!.n += 1
                    guard theirs == t1Label,
                          Int(result.survivingCount) > matchSettings.directMatrixMaximumVectors
                    else { continue }   // classifyKnownVariants never scores these (step b: → .matrix)

                    let vectors = PhaseVectorMatcher.experimentalVectors(
                        peaks: peaks[index], originX: originX, originY: originY,
                        invAngstromPerPixel: qPerPixel,
                        directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                        maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
                    let surviving = vectors.filter { u in
                        guard let matrixEntry else { return true }
                        return PhaseVectorMatcher.nearest(
                            u, in: matrixEntry.vectors,
                            radius: matchSettings.matrixToleranceInvAngstrom) == nil
                    }
                    guard surviving.count == Int(result.survivingCount) else { continue }  // sanity: must match the matcher's own count

                    // The winning T1 entry: the matcher's own answer when T1
                    // is already the overall winner (`result.entryIndex`),
                    // else recomputed as classifyKnownVariants step c would,
                    // restricted to T1's own entries — "would-be winning".
                    var winEntry: Int?
                    if result.phaseIndex == Int32(t1PhaseIndex), result.entryIndex >= 0 {
                        winEntry = Int(result.entryIndex)
                    } else {
                        var bestScore = Double.infinity
                        for e in t1Entries {
                            let entry = library.entries[e]
                            guard !entry.vectors.isEmpty else { continue }
                            var sum = 0.0
                            var uniqueHits = Set<Int>()
                            for u in surviving {
                                guard let hit = PhaseVectorMatcher.nearest(
                                    u, in: entry.vectors, radius: unbounded) else { continue }
                                sum += hit.distance
                                uniqueHits.insert(hit.index)
                            }
                            guard !uniqueHits.isEmpty else { continue }
                            let score = sum / Double(uniqueHits.count)
                            if score < bestScore { bestScore = score; winEntry = e }
                        }
                    }
                    guard let winEntry else { continue }
                    let entry = library.entries[winEntry]
                    for u in surviving {
                        guard let hit = PhaseVectorMatcher.nearest(
                            u, in: entry.vectors, radius: unbounded) else { continue }
                        dSamples.append(hit.distance)
                        qSamples.append(simd_length(u))
                    }
                }

                for (label, stat) in [("T1", meanSurvivors[t1Label]!), ("Al", meanSurvivors[alLabel]!)] {
                    let mean = stat.n > 0 ? Double(stat.sum) / Double(stat.n) : .nan
                    print(String(format: "  mean survivors per truth-%@ position: %.3f (n=%d positions)",
                                 label as NSString, mean, stat.n))
                }
                print("  survivors scored against the winning/would-be-winning T1 entry: n=\(dSamples.count)")

                let dBucketEdges = [0.01, 0.02, 0.05, 0.1, 0.2]
                let dBucketLabels = ["0-0.01", "0.01-0.02", "0.02-0.05", "0.05-0.1", "0.1-0.2", "0.2+"]
                func dBucket(_ d: Double) -> Int {
                    for (i, edge) in dBucketEdges.enumerated() where d < edge { return i }
                    return dBucketEdges.count
                }
                var dCounts = [Int](repeating: 0, count: dBucketLabels.count)
                for d in dSamples { dCounts[dBucket(d)] += 1 }
                print("  d = nearest-reference distance to the winning T1 entry, Å⁻¹ (histogram):")
                print("    " + zip(dBucketLabels, dCounts).map { "\($0)=\($1)" }.joined(separator: "  "))

                func qHistogram(_ mask: (Double) -> Bool) -> String {
                    let binWidth = 0.02
                    let binCount = Int((0.70 / binWidth).rounded(.up)) + 1   // +1 catches ≥0.70
                    var counts = [Int](repeating: 0, count: binCount)
                    var n = 0
                    for (d, q) in zip(dSamples, qSamples) where mask(d) {
                        let bin = min(binCount - 1, Int(q / binWidth))
                        counts[bin] += 1; n += 1
                    }
                    guard n > 0 else { return "  n=0" }
                    var out = "  n=\(n)\n"
                    for (bin, count) in counts.enumerated() where count > 0 {
                        let lo = Double(bin) * binWidth
                        out += String(format: "    %.2f-%.2f: %d\n", lo, lo + binWidth, count)
                    }
                    return out
                }
                print("\n  far survivors (d > 0.05 Å⁻¹): |q| histogram, 0.02 Å⁻¹ bins, 0-0.70:")
                print(qHistogram { $0 > 0.05 })
                print("  near survivors (d ≤ 0.02 Å⁻¹): |q| histogram, 0.02 Å⁻¹ bins, 0-0.70 (comparison):")
                print(qHistogram { $0 <= 0.02 })
                }
            }

            // WHICH ROTATION WON, per truth → label cell: the winner's
            // in-plane angle relative to the matrix entry's, folded to
            // [0, 90) by Al's four-fold axis. The OR question (2026-09-15):
            // a θ′ variant taken for the other one at 45° is the free
            // in-plane rotation putting edge-on (002) at 0.345 Å⁻¹ on
            // face-on (110) at 0.350; at 0° it is something else.
            if map.matrixEntryIndex >= 0 {
                let matrixDeg = library.entries[map.matrixEntryIndex].inPlaneRotationRad * 180 / .pi
                print("\n  winner's in-plane angle relative to the matrix, folded to [0, 90), 5° bins from 0 (truth → label, n ≥ 10):")
                for theirs in [1, 2, 3] {
                    for ours in [1, 2, 3] {
                        var bins = [Int](repeating: 0, count: 18)
                        for (index, result) in map.results.enumerated()
                        where thronsen.labels[index] == theirs && result.verdict == .indexed
                            && Thronsen.label(of: result, phaseNames: map.phaseNames) == ours
                            && result.entryIndex >= 0 {
                            let deg = library.entries[Int(result.entryIndex)].inPlaneRotationRad * 180 / .pi - matrixDeg
                            var folded = deg.truncatingRemainder(dividingBy: 90)
                            if folded < 0 { folded += 90 }
                            bins[min(17, Int(folded / 5))] += 1
                        }
                        let total = bins.reduce(0, +)
                        guard total >= 10 else { continue }
                        print(String(format: "  %-11@ → %-11@ ", name(theirs) as NSString, name(ours) as NSString)
                              + bins.map { String(format: "%5.0f%%", 100 * Double($0) / Double(total)) }.joined(separator: " ")
                              + "  n=\(total)")
                    }
                }
            }
            // WHAT ARE THE OFF-OR SURVIVORS, 2026-09-15 evening (docs/open-items.md,
            // step 3, "Next instrument: dump the survivors and both entries'
            // matched sets at a handful of such positions"). Half of the
            // correctly-labelled edge-on positions win with an entry whose
            // folded angle sits near 22° or 67°, not at the OR's {0, 90}; under
            // the OR filter those positions go "not indexed" (the OR-rotated
            // net does not explain their spots either), so this asks what the
            // matrix-removal survivors at those positions actually are: the
            // winner W (library.entries[result.entryIndex]), and the OR entry O
            // — same phase, same zone axis as W, its folded angle closest to 0
            // or 90 — checked against the SAME survivors.
            if let dumpEdgeOnCount {
                if map.matrixEntryIndex < 0 {
                    print("\n  --dump-edge-on: no matrix entry fitted; skipping")
                } else {
                    let matrixEntry = library.entries[map.matrixEntryIndex]
                    let matrixDeg = matrixEntry.inPlaneRotationRad * 180 / .pi
                    func foldedAngle(of entryIndex: Int) -> Double {
                        let deg = library.entries[entryIndex].inPlaneRotationRad * 180 / .pi - matrixDeg
                        var folded = deg.truncatingRemainder(dividingBy: 90)
                        if folded < 0 { folded += 90 }
                        return folded
                    }

                    struct EdgeOnDump {
                        let position: Int
                        let survivors: [SIMD2<Double>]
                        let wIndex: Int
                        let oIndex: Int?
                        let wScore: (score: Double, matched: Int, uniqueReferences: Int)?
                        let oScore: (score: Double, matched: Int, uniqueReferences: Int)?
                    }
                    let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
                    func dumpAt(_ position: Int, entryIndex: Int) -> EdgeOnDump {
                        let vectors = PhaseVectorMatcher.experimentalVectors(
                            peaks: bragg.peaks[position], originX: originX, originY: originY,
                            invAngstromPerPixel: qPerPixel,
                            directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                            maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
                        let survivors = vectors.filter {
                            PhaseVectorMatcher.nearest($0, in: matrixEntry.vectors,
                                                       radius: matchSettings.matrixToleranceInvAngstrom) == nil
                        }
                        let w = library.entries[entryIndex]
                        var bestO: (index: Int, metric: Double)?
                        for (i, e) in library.entries.enumerated()
                        where e.phaseIndex == w.phaseIndex && e.zoneAxis == w.zoneAxis {
                            let f = foldedAngle(of: i)
                            let metric = min(f, 90 - f)
                            if bestO == nil || metric < bestO!.metric { bestO = (i, metric) }
                        }
                        let wScore = PhaseVectorMatcher.score(
                            vectors: survivors, against: w,
                            pairRadius: matchSettings.pairRadiusInvAngstrom, scratch: scratch)
                        let oScore = bestO.flatMap {
                            PhaseVectorMatcher.score(
                                vectors: survivors, against: library.entries[$0.index],
                                pairRadius: matchSettings.pairRadiusInvAngstrom, scratch: scratch)
                        }
                        return EdgeOnDump(position: position, survivors: survivors, wIndex: entryIndex,
                                          oIndex: bestO?.index, wScore: wScore, oScore: oScore)
                    }

                    var offOR: [EdgeOnDump] = []
                    var onOR: [EdgeOnDump] = []
                    for (index, result) in map.results.enumerated()
                    where thronsen.labels[index] == 1 && result.verdict == .indexed
                        && Thronsen.label(of: result, phaseNames: map.phaseNames) == 1
                        && result.entryIndex >= 0 {
                        let folded = foldedAngle(of: Int(result.entryIndex))
                        if (folded >= 15 && folded < 30) || (folded >= 60 && folded < 75) {
                            offOR.append(dumpAt(index, entryIndex: Int(result.entryIndex)))
                        } else if folded < 5 || folded >= 85 {
                            onOR.append(dumpAt(index, entryIndex: Int(result.entryIndex)))
                        }
                    }

                    func printBlock(_ d: EdgeOnDump) {
                        let wDeg = library.entries[d.wIndex].inPlaneRotationRad * 180 / .pi
                        let wFolded = foldedAngle(of: d.wIndex)
                        let oDeg = d.oIndex.map { library.entries[$0].inPlaneRotationRad * 180 / .pi } ?? .nan
                        let oFolded = d.oIndex.map { foldedAngle(of: $0) } ?? .nan
                        print(String(format: "\n  position %5d  matrix %6.1f°  W %6.1f° (folded %5.1f°)  O %6.1f° (folded %5.1f°)  survivors %d",
                                     d.position, matrixDeg, wDeg, wFolded, oDeg, oFolded, d.survivors.count))
                        let w = library.entries[d.wIndex]
                        let o = d.oIndex.map { library.entries[$0] }
                        for u in d.survivors {
                            let len = simd_length(u)
                            var az = atan2(u.y, u.x) * 180 / .pi - matrixDeg
                            az = az.truncatingRemainder(dividingBy: 360)
                            if az < 0 { az += 360 }
                            func label(_ entry: PhaseOrientationReference?) -> String {
                                guard let entry,
                                      let hit = PhaseVectorMatcher.nearest(
                                          u, in: entry.vectors, radius: matchSettings.pairRadiusInvAngstrom)
                                else { return "—" }
                                let v = entry.vectors[hit.index]
                                return String(format: "(%d %d %d) d=%.3f", v.h, v.k, v.l, 1 / v.length)
                            }
                            print(String(format: "    |q| %.4f  az %6.1f°   W: %-16@   O: %-16@",
                                         len, az, label(w) as NSString, label(o) as NSString))
                        }
                        func scoreLine(_ tag: String, _ s: (score: Double, matched: Int, uniqueReferences: Int)?) -> String {
                            guard let s else { return "\(tag): no match" }
                            return String(format: "%@: matched %d mean %.4f", tag as NSString, s.matched, s.score)
                        }
                        print("    " + scoreLine("W", d.wScore) + "    " + scoreLine("O", d.oScore))
                    }

                    print("\n  == --dump-edge-on: correctly-labelled θ′ edge-on positions, off vs. on the OR ==")
                    print("  -- off-OR (folded in [15,30) ∪ [60,75)): first \(min(dumpEdgeOnCount, offOR.count)) of \(offOR.count) --")
                    for d in offOR.prefix(dumpEdgeOnCount) { printBlock(d) }
                    let half = max(1, dumpEdgeOnCount / 2)
                    print("\n  -- on-OR (folded in [0,5) ∪ [85,90)): first \(min(half, onOR.count)) of \(onOR.count) --")
                    for d in onOR.prefix(half) { printBlock(d) }

                    func aggregate(_ label: String, _ ds: [EdgeOnDump]) {
                        guard !ds.isEmpty else { print("\n  \(label): no positions"); return }
                        let counts = ds.map { $0.survivors.count }.sorted()
                        let median = counts[counts.count / 2]
                        let wFracs = ds.compactMap { d -> Double? in
                            guard !d.survivors.isEmpty else { return nil }
                            return Double(d.wScore?.matched ?? 0) / Double(d.survivors.count)
                        }
                        let oFracs = ds.compactMap { d -> Double? in
                            guard !d.survivors.isEmpty else { return nil }
                            return Double(d.oScore?.matched ?? 0) / Double(d.survivors.count)
                        }
                        let meanW = wFracs.isEmpty ? Double.nan : wFracs.reduce(0, +) / Double(wFracs.count)
                        let meanO = oFracs.isEmpty ? Double.nan : oFracs.reduce(0, +) / Double(oFracs.count)
                        print(String(format: "\n  %@: n=%d  median survivors %d  mean matched-fraction W %.2f  O %.2f",
                                     label as NSString, ds.count, median, meanW, meanO))

                        var qBins = [Int](repeating: 0, count: 11)   // 0.15 .. 0.70 Å⁻¹, 0.05 Å⁻¹ steps
                        var azBins = [Int](repeating: 0, count: 18)  // [0, 90), 5° steps
                        var total = 0
                        for d in ds {
                            for u in d.survivors {
                                total += 1
                                let len = simd_length(u)
                                if len >= 0.15, len < 0.70 { qBins[min(10, Int((len - 0.15) / 0.05))] += 1 }
                                var az = atan2(u.y, u.x) * 180 / .pi - matrixDeg
                                az = az.truncatingRemainder(dividingBy: 90)
                                if az < 0 { az += 90 }
                                azBins[min(17, Int(az / 5))] += 1
                            }
                        }
                        print("    survivor |q| histogram, 0.05 Å⁻¹ bins from 0.15 Å⁻¹ (n=\(total)):")
                        print("    " + qBins.map { String(format: "%4d", $0) }.joined())
                        print("    survivor azimuth histogram relative to matrix, folded to [0, 90), 5° bins:")
                        print("    " + azBins.map { String(format: "%4d", $0) }.joined())
                    }
                    aggregate("off-OR (all)", offOR)
                    aggregate("on-OR (all)", onOR)
                }
            }
            // WHERE THE VECTORS WENT, per truth class: how many survived
            // matrix removal at each position, and how many were detected at
            // all. A precipitate that reaches the matrix verdict with fewer
            // than two survivors was lost at detection or removal, not at the
            // challenge (which must explain STRICTLY more than the candidate).
            print("\n  survivors after matrix removal, per truth class (columns: 0 1 2 3 4+ | detected vectors median):")
            for theirs in [0, 1, 2, 3] {
                var hist = [0, 0, 0, 0, 0]; var detected: [Int] = []
                for (index, result) in map.results.enumerated() where thronsen.labels[index] == theirs {
                    hist[min(4, Int(result.survivingCount))] += 1
                    detected.append(Int(result.survivingCount + result.removedCount))
                }
                let total = hist.reduce(0, +)
                guard total > 0 else { continue }
                let medianDetected = detected.sorted()[detected.count / 2]
                print(String(format: "  %-14@ ", name(theirs) as NSString)
                      + hist.map { String(format: "%5.1f%%", 100 * Double($0) / Double(total)) }.joined(separator: " ")
                      + " | \(medianDetected)")
            }
            // ---- WHY the not-indexed positions were refused (2026-09-16) ----
            // At a 0.1 % detection threshold "not indexed" is 83 % of the whole
            // error (1024 of 1230), so the refusal, not the label, is what
            // costs. There are three paths to it and they are told apart by
            // what the result carries: the matcher records the winner's numbers
            // on a refusal, so `score > 0` means a candidate WAS chosen and
            // then rejected by the verdict cliff, while `score == 0` means
            // nothing cleared the guards at all. For the cliff group the
            // question is how far over it they sit: just over is a threshold,
            // far over is a reference that does not fit.
            let cliff = matchSettings.notIndexedAboveInvAngstrom
            print(String(format: "\n  why not indexed, per truth class (cliff = %.4f Å⁻¹):", cliff))
            print("  class            n   nothing-cleared  cliff-refused | score/cliff of the cliff group: p25 p50 p75  median matched")
            for theirs in [0, 1, 2, 3] {
                var nothing = 0
                var ratios: [Double] = []
                var matched: [Int] = []
                for (index, result) in map.results.enumerated()
                where thronsen.labels[index] == theirs && result.verdict == .notIndexed {
                    let sc = Double(result.score)
                    if !(sc > 0) { nothing += 1; continue }
                    ratios.append(sc / max(cliff, .leastNormalMagnitude))
                    matched.append(Int(result.matchedCount))
                }
                let n = nothing + ratios.count
                guard n > 0 else { continue }
                let sorted = ratios.sorted()
                func q(_ f: Double) -> String {
                    guard !sorted.isEmpty else { return "  -  " }
                    return String(format: "%5.2f", sorted[min(sorted.count - 1, Int(f * Double(sorted.count)))])
                }
                let medMatched = matched.isEmpty ? 0 : matched.sorted()[matched.count / 2]
                print(String(format: "  %-14@ %5d   %6d (%3.0f%%)   %6d (%3.0f%%) | ",
                             name(theirs) as NSString, n,
                             nothing, 100 * Double(nothing) / Double(n),
                             ratios.count, 100 * Double(ratios.count) / Double(n))
                      + "\(q(0.25)) \(q(0.50)) \(q(0.75))        \(medMatched)")
            }

            // What fraction did the MATRIX explain at the positions where
            // nothing cleared? This is the measurement that should have come
            // before the 2026-09-16 matrix fall-back pre-registration, whose
            // f = 0.8 was a guess and never opened. If Al's explained fraction
            // sits above the precipitates', a fall-back can separate them; if
            // they overlap, it cannot, and the number is the answer either way.
            print("\n  explained fraction (removed / detected) where NOTHING cleared, per truth class:")
            print("  class            n    p10   p25   p50   p75   p90")
            for theirs in [0, 1, 2, 3] {
                var fracs: [Double] = []
                for (index, result) in map.results.enumerated()
                where thronsen.labels[index] == theirs && result.verdict == .notIndexed
                    && !(Double(result.score) > 0) {
                    let detected = Double(result.survivingCount + result.removedCount)
                    guard detected > 0 else { continue }
                    fracs.append(Double(result.removedCount) / detected)
                }
                guard !fracs.isEmpty else { continue }
                let sorted = fracs.sorted()
                func q(_ f: Double) -> String {
                    String(format: "%5.2f", sorted[min(sorted.count - 1, Int(f * Double(sorted.count)))])
                }
                print(String(format: "  %-14@ %5d  ", name(theirs) as NSString, fracs.count)
                      + [0.10, 0.25, 0.50, 0.75, 0.90].map(q).joined(separator: " "))
            }

            // ---- Are the T1 not-indexed survivors a Friedel pair? (owner
            // question, docs/open-items.md "T1 [0 -4 1] reference measured") ----
            // The matcher's floor drops from 3 to 2 ONLY when the surviving
            // experimental vectors hold u and −u within the pair radius
            // (containsFriedelPair). With ~2 survivors at T1 that is the whole
            // difference between "can index" and "can never". Recompute the
            // SHIPPED survivors at every not-indexed position and ask directly —
            // read-only, no science number moves.
            // NOTE: this uses the probe's single GLOBAL origin. The
            // --t1-origin-experiment block below RE-RAN these positions with a
            // per-position direct-beam origin and found it moves 0.04 px and
            // recovers only 10 %, so the off-antiparallel |u+v| here is per-peak
            // centroid noise, NOT a global-origin artifact (docs/open-items.md).
            do {
                let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
                let matrixEntry = map.matrixEntryIndex >= 0 ? library.entries[map.matrixEntryIndex] : nil
                let t1PhaseIndex = map.phaseNames.firstIndex(of: "T1") ?? -1
                let t1Entries = library.entries.indices.filter {
                    Int(library.entries[$0].phaseIndex) == t1PhaseIndex
                }
                print(String(format: "\n  Friedel-pair test on SHIPPED not-indexed survivors (pair radius %.4f Å⁻¹, T1 entries: %d):",
                             matchSettings.pairRadiusInvAngstrom, t1Entries.count))
                for theirs in [3, 1, 2] {   // T1 first, then θ′ variants for contrast
                    var nTotal = 0, nPair = 0, nPairAndT1Match = 0
                    var survCounts: [Int] = []
                    var examples: [String] = []
                    for (index, result) in map.results.enumerated()
                    where thronsen.labels[index] == theirs && result.verdict == .notIndexed {
                        let vectors = PhaseVectorMatcher.experimentalVectors(
                            peaks: peaks[index], originX: originX, originY: originY,
                            invAngstromPerPixel: qPerPixel,
                            directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                            maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
                        let surviving = vectors.filter { u in
                            guard let m = matrixEntry else { return true }
                            return !m.vectors.contains { simd_distance($0.q, u) <= matchSettings.matrixToleranceInvAngstrom }
                        }
                        nTotal += 1
                        survCounts.append(surviving.count)
                        let isPair = PhaseVectorMatcher.containsFriedelPair(
                            surviving, radius: matchSettings.pairRadiusInvAngstrom)
                        if isPair {
                            nPair += 1
                            let best = t1Entries.compactMap {
                                PhaseVectorMatcher.score(
                                    vectors: surviving, against: library.entries[$0],
                                    pairRadius: matchSettings.pairRadiusInvAngstrom,
                                    scratch: scratch)?.matched }.max() ?? 0
                            if best >= 2 { nPairAndT1Match += 1 }
                        }
                        if theirs == 3 && examples.count < 8 && surviving.count >= 2 {
                            let desc = surviving.prefix(4).map {
                                String(format: "(%+.3f,%+.3f)|q|=%.3f", $0.x, $0.y, simd_length($0)) }
                                .joined(separator: " ")
                            examples.append("      n=\(surviving.count) pair=\(isPair)  \(desc)")
                        }
                    }
                    guard nTotal > 0 else { continue }
                    let medSurv = survCounts.sorted()[survCounts.count / 2]
                    print(String(format: "  %-14@ n=%5d  median survivors=%d  hold ±pair: %5d (%3.0f%%)  of those a T1 entry matches ≥2: %d",
                                 name(theirs) as NSString, nTotal, medSurv, nPair,
                                 100 * Double(nPair) / Double(nTotal), nPairAndT1Match))
                    for e in examples { print(e) }
                }
            }

            // How much evidence stands behind a MATRIX verdict? (2026-09-16.)
            // `.matrix` is returned by two mechanisms — too little survived
            // removal, or the matrix won the challenge — but the distinction
            // that matters to a reader is not the mechanism, it is whether the
            // matrix actually EXPLAINED anything. Four detected vectors all
            // removed is a positive identification; one detected vector
            // removed is an assumption. Both are drawn the same grey today and
            // both are counted in the matrix phase fraction.
            print("\n  evidence behind each MATRIX verdict, per truth class (detected vectors, all removed):")
            print("  class            n     0-1     2-3     4-5      6+   | median detected  median removed-fraction")
            for theirs in [0, 1, 2, 3] {
                var bins = [0, 0, 0, 0]
                var detectedAll: [Int] = []
                var fracs: [Double] = []
                for (index, result) in map.results.enumerated()
                where thronsen.labels[index] == theirs && result.verdict == .matrix {
                    let detected = Int(result.survivingCount + result.removedCount)
                    detectedAll.append(detected)
                    if detected <= 1 { bins[0] += 1 } else if detected <= 3 { bins[1] += 1 }
                    else if detected <= 5 { bins[2] += 1 } else { bins[3] += 1 }
                    if detected > 0 { fracs.append(Double(result.removedCount) / Double(detected)) }
                }
                let n = detectedAll.count
                guard n > 0 else { continue }
                let medDet = detectedAll.sorted()[n / 2]
                let sortedFracs = fracs.sorted()
                func q(_ f: Double) -> String {
                    guard !sortedFracs.isEmpty else { return " -  " }
                    return String(format: "%.2f", sortedFracs[min(sortedFracs.count - 1, Int(f * Double(sortedFracs.count)))])
                }
                // The BAR is chosen from these, not guessed: the 2026-09-16
                // fall-back was pre-registered at f = 0.8 without measuring and
                // could never have fired.
                let below90 = sortedFracs.filter { $0 < 0.9 }.count
                print(String(format: "  %-14@ %5d  ", name(theirs) as NSString, n)
                      + bins.map { String(format: "%4d(%2.0f%%)", $0, 100 * Double($0) / Double(n)) }.joined(separator: " ")
                      + String(format: "  |      %3d   ", medDet)
                      + "p10 \(q(0.10)) p25 \(q(0.25)) p50 \(q(0.50)) p75 \(q(0.75)) p90 \(q(0.90))"
                      + String(format: "  | under 0.90: %d (%.1f %%)", below90,
                               100 * Double(below90) / Double(max(1, sortedFracs.count))))
            }

            // ---- Gate D EXPERIMENT: per-position direct-beam origin on the
            // not-indexed T1 positions (docs/open-items.md, T1 entry) ----
            // The matcher uses ONE global origin; per-position origin collapse
            // is the caller's job (PhaseVectorMatching.swift:349). This re-reads
            // each not-indexed T1 pattern, computes its OWN direct-beam COM
            // origin (the same radius-6 COM the probe computes globally,
            // main.swift:347-359), rebuilds survivors and RE-RUNS `classify`
            // with that origin — deciding common-mode origin vs per-peak noise,
            // and whether a per-position origin already indexes T1. The
            // per-position origin is from the DIRECT BEAM, independent of the
            // T1 reflections, so it is not circular. Read-only measurement.
            if t1OriginExperiment {
                print("\n== Gate D: per-position direct-beam origin on not-indexed T1 ==")
                let scratch = PhaseVectorMatcher.Scratch(
                    capacity: library.entries.map(\.vectors.count).max() ?? 1)
                let matrixEntry = map.matrixEntryIndex >= 0 ? library.entries[map.matrixEntryIndex] : nil
                let candidates = library.candidateEntryIndices
                let challenge = PhaseVectorMatcher.matrixChallengeBases(library: library)
                let t1PhaseIndex = map.phaseNames.firstIndex(of: "T1") ?? -1
                let cxG = Double(primary.qx - 1) / 2, cyG = Double(primary.qy - 1) / 2
                let radius = matchSettings.pairRadiusInvAngstrom

                func survivors(_ index: Int, _ ox: Float, _ oy: Float) -> [SIMD2<Double>] {
                    let v = PhaseVectorMatcher.experimentalVectors(
                        peaks: peaks[index], originX: ox, originY: oy,
                        invAngstromPerPixel: qPerPixel,
                        directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                        maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
                    guard let m = matrixEntry else { return v }
                    return v.filter { u in
                        !m.vectors.contains { simd_distance($0.q, u) <= matchSettings.matrixToleranceInvAngstrom } }
                }
                func bestPairResidual(_ v: [SIMD2<Double>]) -> Double? {
                    var best: Double?
                    for i in 0..<v.count where simd_length(v[i]) > radius {
                        for j in (i + 1)..<v.count {
                            let s = simd_length(v[i] + v[j])
                            if best == nil || s < best! { best = s }
                        }
                    }
                    return best
                }
                func classify(_ index: Int, _ ox: Float, _ oy: Float) -> PhaseVectorResult {
                    let v = PhaseVectorMatcher.experimentalVectors(
                        peaks: peaks[index], originX: ox, originY: oy,
                        invAngstromPerPixel: qPerPixel,
                        directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom,
                        maximumVectorInvAngstrom: matchSettings.maximumVectorInvAngstrom)
                    return PhaseVectorMatcher.classify(
                        vectors: v, library: library, settings: matchSettings,
                        matrixEntry: matrixEntry, candidateEntryIndices: candidates,
                        scratch: scratch, matrixChallenge: challenge)
                }

                var n = 0, sanityNotIndexed = 0
                var shift: [Double] = [], uvGlobal: [Double] = [], uvPerPos: [Double] = []
                var pairGlobal = 0, pairPerPos = 0
                var vIndexedT1 = 0, vIndexedOther = 0, vNotIndexed = 0, vMatrix = 0
                for (index, result) in map.results.enumerated()
                where thronsen.labels[index] == 3 && result.verdict == .notIndexed {
                    let ry = index / cols.count, rx = index % cols.count
                    guard let pattern = try? await reader.readPattern(view, ry: ry, rx: rx) else { continue }
                    var s = 0.0, sx = 0.0, sy = 0.0
                    for y in 0..<primary.qy {
                        for x in 0..<primary.qx {
                            let r = ((Double(y) - cyG) * (Double(y) - cyG)
                                     + (Double(x) - cxG) * (Double(x) - cxG)).squareRoot()
                            guard r <= 6 else { continue }
                            let w = Double(pattern[y * primary.qx + x])
                            s += w; sy += w * Double(y); sx += w * Double(x)
                        }
                    }
                    guard s > 0 else { continue }
                    let pOX = Float(sx / s), pOY = Float(sy / s)
                    n += 1
                    shift.append(((Double(pOX) - Double(originX)) * (Double(pOX) - Double(originX))
                                  + (Double(pOY) - Double(originY)) * (Double(pOY) - Double(originY))).squareRoot() * qPerPixel)

                    let survG = survivors(index, originX, originY)
                    let survP = survivors(index, pOX, pOY)
                    if let r = bestPairResidual(survG) { uvGlobal.append(r) }
                    if let r = bestPairResidual(survP) { uvPerPos.append(r) }
                    if PhaseVectorMatcher.containsFriedelPair(survG, radius: radius) { pairGlobal += 1 }
                    if PhaseVectorMatcher.containsFriedelPair(survP, radius: radius) { pairPerPos += 1 }

                    if classify(index, originX, originY).verdict == .notIndexed { sanityNotIndexed += 1 }
                    let rP = classify(index, pOX, pOY)
                    switch rP.verdict {
                    case .indexed where Int(rP.phaseIndex) == t1PhaseIndex: vIndexedT1 += 1
                    case .indexed: vIndexedOther += 1
                    case .notIndexed: vNotIndexed += 1
                    case .matrix: vMatrix += 1
                    case .noData: break
                    }
                }
                func med(_ a: [Double]) -> Double { a.isEmpty ? .nan : a.sorted()[a.count / 2] }
                print(String(format: "  N = %d not-indexed T1 positions (sanity: classify(global) still not-indexed %d/%d)",
                             n, sanityNotIndexed, n))
                print(String(format: "  per-position origin shift from the global origin: median %.4f Å⁻¹ = %.2f px",
                             med(shift), med(shift) / qPerPixel))
                print(String(format: "  best surviving-pair |u+v|: global median %.4f  →  per-position median %.4f Å⁻¹  (pair radius %.4f)",
                             med(uvGlobal), med(uvPerPos), radius))
                print(String(format: "  hold ±pair (containsFriedelPair): global %d (%.0f%%)  →  per-position %d (%.0f%%)",
                             pairGlobal, 100 * Double(pairGlobal) / Double(max(1, n)),
                             pairPerPos, 100 * Double(pairPerPos) / Double(max(1, n))))
                print(String(format: "  verdict with per-position origin: T1 %d (%.0f%%)  other-phase %d  not-indexed %d  matrix %d",
                             vIndexedT1, 100 * Double(vIndexedT1) / Double(max(1, n)),
                             vIndexedOther, vNotIndexed, vMatrix))
            }

            // ---- Noise floor (Gate D record: docs/open-items.md, step 3 entry) ----
            // Does a per-pattern local significance z = (I − median) /
            // (1.4826·MAD) over a pattern's non-beam, non-Al correlation
            // maxima separate true Friedel pairs (T1, θ′) from noise pairs
            // (Al), where a fraction-of-the-maximum threshold cannot?
            if noiseFloor {
                print("\n== Noise floor: z vs. fraction-of-beam, on non-beam non-Al correlation maxima ==")
                if map.matrixEntryIndex < 0 {
                    print("  no matrix entry fitted; skipping")
                } else {
                    let matrixVectors = library.entries[map.matrixEntryIndex].vectors

                    // Sample: every θ′/T1 position, plus up to 3000 Al
                    // positions by even stride over the Al positions.
                    // Disagreement (label 4) is skipped.
                    var byClass: [Int: [Int]] = [:]
                    for (position, label) in thronsen.labels.enumerated() where label != 4 {
                        byClass[label, default: []].append(position)
                    }
                    var classSampled: [Int: [Int]] = [:]
                    for label in [1, 2, 3] { classSampled[label] = byClass[label] ?? [] }
                    let al0 = byClass[0] ?? []
                    if al0.count > 3000 {
                        let strideN = max(1, al0.count / 3000)
                        classSampled[0] = Array(Swift.stride(from: 0, to: al0.count, by: strideN)
                            .prefix(3000).map { al0[$0] })
                    } else {
                        classSampled[0] = al0
                    }
                    let sampled = classSampled.values.flatMap { $0 }.sorted()

                    struct Outcome {
                        var noStatistic = false
                        var bestZ: Double?          // best pair chosen to maximize z
                        var bestZFraction: Double?   // that same pair's fraction-of-beam
                        var bestZLength: Double?     // that same pair's mean |q|, Å⁻¹
                        var bestFraction: Double?    // best pair chosen to maximize fraction, separately
                    }
                    var outcome: [Int: Outcome] = [:]
                    outcome.reserveCapacity(sampled.count)
                    var noPeaks = 0

                    for position in sampled {
                        let ry = position / cols.count
                        let rx = position % cols.count
                        guard let pattern = try? await reader.readPattern(view, ry: ry, rx: rx) else { continue }
                        // A copy of the map's own params with the thresholds
                        // opened up: the question is what the field of
                        // correlation maxima looks like, not what a fraction
                        // rule already kept.
                        var noiseParams = params
                        noiseParams.minRelativeIntensity = 0
                        noiseParams.minAbsoluteIntensity = 0
                        noiseParams.maxNumPeaks = 200
                        let detected = detector.detect(pattern: pattern, params: noiseParams)
                        guard let beam = detected.first else { noPeaks += 1; continue }
                        let beamIntensity = Double(beam.intensity)

                        // Same frame and cuts as `experimentalVectors`, with
                        // intensity carried alongside.
                        var fieldMaxima: [(q: SIMD2<Double>, intensity: Double)] = []
                        fieldMaxima.reserveCapacity(detected.count)
                        for p in detected {
                            let q = SIMD2(Double(p.x - originX) * qPerPixel, Double(p.y - originY) * qPerPixel)
                            let len = simd_length(q)
                            guard len.isFinite, len > matchSettings.directBeamRadiusInvAngstrom,
                                  matchSettings.maximumVectorInvAngstrom <= 0
                                      || len < matchSettings.maximumVectorInvAngstrom
                            else { continue }
                            fieldMaxima.append((q, Double(p.intensity)))
                        }
                        // Al exclusion: the same rule as matrix removal.
                        let remaining = fieldMaxima.filter { m in
                            !matrixVectors.contains { simd_distance($0.q, m.q) <= matchSettings.matrixToleranceInvAngstrom }
                        }

                        var o = Outcome()
                        guard remaining.count >= 8 else {
                            o.noStatistic = true; outcome[position] = o; continue
                        }
                        let sortedIntensity = remaining.map(\.intensity).sorted()
                        let median = sortedIntensity[sortedIntensity.count / 2]
                        let mad = remaining.map { abs($0.intensity - median) }.sorted()[remaining.count / 2]
                        guard mad > 0 else {
                            o.noStatistic = true; outcome[position] = o; continue
                        }
                        func z(_ intensity: Double) -> Double { (intensity - median) / (1.4826 * mad) }

                        var bestByZ: (z: Double, fraction: Double, length: Double)?
                        var bestByFraction: Double?
                        let count = remaining.count
                        for i in 0..<count {
                            for j in (i + 1)..<count {
                                guard simd_length(remaining[i].q + remaining[j].q)
                                        <= matchSettings.pairRadiusInvAngstrom else { continue }
                                let pairZ = min(z(remaining[i].intensity), z(remaining[j].intensity))
                                let pairFraction = min(remaining[i].intensity, remaining[j].intensity) / beamIntensity
                                let pairLength = (simd_length(remaining[i].q) + simd_length(remaining[j].q)) / 2
                                if bestByZ == nil || pairZ > bestByZ!.z {
                                    bestByZ = (pairZ, pairFraction, pairLength)
                                }
                                if bestByFraction == nil || pairFraction > bestByFraction! {
                                    bestByFraction = pairFraction
                                }
                            }
                        }
                        o.bestZ = bestByZ?.z
                        o.bestZFraction = bestByZ?.fraction
                        o.bestZLength = bestByZ?.length
                        o.bestFraction = bestByFraction
                        outcome[position] = o
                    }
                    if noPeaks > 0 { print("  \(noPeaks) sampled positions had no detected peaks at all") }

                    func percentiles(_ values: [Double], _ ps: [Double]) -> [Double] {
                        guard !values.isEmpty else { return ps.map { _ in .nan } }
                        let sorted = values.sorted()
                        return ps.map { p in
                            let idx = min(sorted.count - 1, max(0, Int((p / 100) * Double(sorted.count))))
                            return sorted[idx]
                        }
                    }
                    print("\n  per class (N sampled | no-statistic | with a pair | z p10/25/50/75/90 | fraction p10/25/50/75/90):")
                    for classLabel in [0, 1, 2, 3] {
                        let positions = classSampled[classLabel] ?? []
                        guard !positions.isEmpty else { continue }
                        let nNoStat = positions.filter { outcome[$0]?.noStatistic == true }.count
                        let zValues = positions.compactMap { outcome[$0]?.bestZ }
                        let fractionValues = positions.compactMap { outcome[$0]?.bestFraction }
                        let zP = percentiles(zValues, [10, 25, 50, 75, 90])
                        let fP = percentiles(fractionValues, [10, 25, 50, 75, 90])
                        print(String(format: "  %-14@ %5d %5d %5d  z[%@]  f[%@]",
                                     name(classLabel) as NSString, positions.count, nNoStat, zValues.count,
                                     zP.map { String(format: "%.1f", $0) }.joined(separator: " ") as NSString,
                                     fP.map { String(format: "%.4f", $0) }.joined(separator: " ") as NSString))
                    }
                    if let t1Positions = classSampled[3] {
                        let lengths = t1Positions.compactMap { outcome[$0]?.bestZLength }.sorted()
                        if !lengths.isEmpty {
                            print(String(format: "\n  T1 median best-pair (by z) length: %.4f Å⁻¹ (0.454 / 0.479 expected)",
                                         lengths[lengths.count / 2]))
                        }
                    }

                    let zThresholds: [Double] = [2, 3, 4, 5, 6, 8, 10, 15, 20]
                    let fractionThresholds: [Double] = [0.001, 0.002, 0.003, 0.005, 0.01, 0.02]
                    func recallAtOrAbove(_ label: Int, z threshold: Double) -> Double {
                        let positions = classSampled[label] ?? []
                        guard !positions.isEmpty else { return .nan }
                        let hit = positions.filter { (outcome[$0]?.bestZ ?? -.infinity) >= threshold }.count
                        return 100 * Double(hit) / Double(positions.count)
                    }
                    func recallAtOrAbove(_ label: Int, fraction threshold: Double) -> Double {
                        let positions = classSampled[label] ?? []
                        guard !positions.isEmpty else { return .nan }
                        let hit = positions.filter { (outcome[$0]?.bestFraction ?? -.infinity) >= threshold }.count
                        return 100 * Double(hit) / Double(positions.count)
                    }

                    print("\n  z-threshold sweep (%% of a class's sampled positions with a best-pair z ≥ threshold; Al = false-positive rate):")
                    print("  " + String(repeating: " ", count: 14) + zThresholds.map { String(format: "%7.0f", $0) }.joined())
                    for classLabel in [0, 1, 2, 3] where !(classSampled[classLabel] ?? []).isEmpty {
                        let row = zThresholds.map { String(format: "%6.2f%%", recallAtOrAbove(classLabel, z: $0)) }
                        print(String(format: "  %-14@", name(classLabel) as NSString) + row.joined())
                    }
                    print("\n  fraction-of-beam threshold sweep (same positions):")
                    print("  " + String(repeating: " ", count: 14) + fractionThresholds.map { String(format: "%7.3f", $0) }.joined())
                    for classLabel in [0, 1, 2, 3] where !(classSampled[classLabel] ?? []).isEmpty {
                        let row = fractionThresholds.map { String(format: "%6.2f%%", recallAtOrAbove(classLabel, fraction: $0)) }
                        print(String(format: "  %-14@", name(classLabel) as NSString) + row.joined())
                    }

                    let zClean = zThresholds.first { recallAtOrAbove(0, z: $0) <= 0.1 }
                    let fractionClean = fractionThresholds.first { recallAtOrAbove(0, fraction: $0) <= 0.1 }
                    print("")
                    if let zClean {
                        print(String(format: "  smallest swept z with Al ≤ 0.1%%: z ≥ %.0f, Al %.2f%%, T1 recall %.1f%%",
                                     zClean, recallAtOrAbove(0, z: zClean), recallAtOrAbove(3, z: zClean)))
                    } else {
                        print(String(format: "  no swept z gets Al ≤ 0.1%% (best swept: z ≥ %.0f, Al %.2f%%)",
                                     zThresholds.last!, recallAtOrAbove(0, z: zThresholds.last!)))
                    }
                    if let fractionClean {
                        print(String(format: "  smallest swept fraction with Al ≤ 0.1%%: f ≥ %.3f, Al %.2f%%, T1 recall %.1f%%",
                                     fractionClean, recallAtOrAbove(0, fraction: fractionClean),
                                     recallAtOrAbove(3, fraction: fractionClean)))
                    } else {
                        print(String(format: "  no swept fraction gets Al ≤ 0.1%% (best swept: f ≥ %.3f, Al %.2f%%)",
                                     fractionThresholds.last!, recallAtOrAbove(0, fraction: fractionThresholds.last!)))
                    }
                    let t1RecallAtZClean = zClean.map { recallAtOrAbove(3, z: $0) }
                    switch t1RecallAtZClean {
                    case .some(let recall) where recall >= 80:
                        print("\nNOISE-FLOOR VERDICT: prediction met")
                    case .some(let recall) where recall <= 60:
                        print("\nNOISE-FLOOR VERDICT: refuted")
                    case .some:
                        print("\nNOISE-FLOOR VERDICT: between")
                    case .none:
                        // No swept z ever gets Al to ≤ 0.1 %: the instrument
                        // never separates the classes within the range tested.
                        print("\nNOISE-FLOOR VERDICT: refuted")
                    }
                }
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
