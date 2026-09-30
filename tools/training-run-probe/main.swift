// tools/training-run-probe/main.swift — C5 (headless half), 2026-09-29. A DIAGNOSTIC that never gates.
// Drives the app's OWN training pipeline (Training/: HeldOutSplit, TrainingSampleBuilder, DetectorTrainer,
// ModelPackageWriter, DetectionScorer, DetectorFineTuning.run, TrainingPolicy.offer) on the owner's real labels,
// with no AppState, then measures the minimum held-out N (C3 pre-registration §4).
//
//   probe run <labels.json> <out dir>        the whole thing (writes <out>/scores.json)
//   probe resample <scores.json>             §4 only, from a saved scores.json
//
// Part 1 — the app's run: DetectorFineTuning.run on all 40 labelled positions (HeldOutSplit decides train/held-out),
//   500 steps, the fixed recipe, bundled parent, both models on the Neural Engine at the app's default
//   settings (detectorAdapted from the file probe, threshold 0.7), scored at 2 px; then TrainingPolicy.offer (D7).
// Part 2 — per-position scores on all 40 positions for: the bundled model, the classical detector at the app's
//   settings, and OUT-OF-FOLD fine-tuned models (4 folds by hash rank, each trained on the other 30 positions,
//   lr 1e-5 = C2 run 2b and lr 1e-4 = C2 run 1). Out-of-fold, so no position is scored by a model that trained on
//   it; the main-split model's scores at its 28 training positions are in-sample and are kept apart ("ft_main").
// Part 3 — §4: for k in {4,6,8,10,12,16,20,30}, 10 000 subsets of k positions (seed 20260930, drawn once per
//   (k, draw) and shared by every pair). A pair's VERDICT on a subset is the D7 rule applied to the pooled counts:
//   "A" if A is >= on recall and precision and > on one, "B" likewise, else "none" (a fall or a tie). P(k) = how often
//   the subset's verdict equals the verdict on all 40. gap = max(|d recall|, |d precision|) on all 40; k_min is the
//   smallest k with P >= 0.90 for every pair with gap >= delta = 0.03.

import CoreML
import Darwin
import DSTEMCore
import Foundation
import Metal

nonisolated struct LabelFile: Decodable {
    struct Pos: Decodable { let ry: Int; let rx: Int; let centres: [[Double]] }
    let cube: String
    let dataset: String
    let sha256: String?
    let positions: [Pos]
}
nonisolated struct Counts: Codable, Equatable {
    var m: Int; var t: Int; var p: Int
    init(_ s: DetectionScore) { m = s.matched; t = s.truth; p = s.predicted }
}
nonisolated struct PositionRow: Codable { var ry: Int; var rx: Int; var heldOutMain: Bool; var scores: [String: Counts] }
nonisolated struct ScoresFile: Codable { var note: String; var labelsSHA256: String?; var rows: [PositionRow] }

nonisolated func say(_ s: String) { print(s); fflush(stdout) }
nonisolated func fail(_ s: String, _ code: Int32 = 1) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(code) }
/// Env knobs for a short, bounded diagnostic run (2026-09-29, the training-memory slope): TR_PROBE_STEPS (recipe steps),
/// TR_PROBE_LOG_EVERY (print every n-th step), TR_PROBE_STOP_MB (hard abort on phys_footprint), TR_PROBE_ONLY_PART1=1 (stop after
/// the app's own run and its D7 verdict). Unset = the full C5 run.
nonisolated func envNumber(_ k: String) -> Double? { ProcessInfo.processInfo.environment[k].flatMap(Double.init) }
nonisolated let memoryStopMB = envNumber("TR_PROBE_STOP_MB") ?? 3072.0
nonisolated func guardMemory(_ stage: String) {
    let mb = DetectorTraining.footprintMB()
    if mb > memoryStopMB { fail("STOP: phys_footprint \(Int(mb)) MB > \(Int(memoryStopMB)) MB at \(stage)", 3) }
}

@main
struct TrainingRunProbe {
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let a = Array(CommandLine.arguments.dropFirst())
        if a.count == 2, a[0] == "resample" {
            let f = try JSONDecoder().decode(ScoresFile.self, from: Data(contentsOf: URL(fileURLWithPath: a[1])))
            Resampling.report(f)
            return
        }
        guard a.count == 3, a[0] == "run" else { fail("usage: probe run <labels.json> <out dir> | probe resample <scores.json>", 64) }
        let t0 = Date()
        let outDir = URL(fileURLWithPath: a[2], isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // ---- labels, cube, probe: the app's own path (H5Reader -> FourDArray; file probe -> probeSize)
        let labelData = try Data(contentsOf: URL(fileURLWithPath: a[1]))
        let file = try JSONDecoder().decode(LabelFile.self, from: labelData)
        var labels: [ScanPosition: [ScorePoint]] = [:]
        for p in file.positions where !p.centres.isEmpty {
            labels[ScanPosition(ry: p.ry, rx: p.rx)] = p.centres.map { ScorePoint(row: $0[0], col: $0[1]) }
        }
        say("labels: \(labels.count) positions, \(labels.values.reduce(0) { $0 + $1.count }) centres, sha256 \(file.sha256 ?? "?")")
        let reader = try H5Reader(path: file.cube)
        let d = try await reader.discoverPrimaryDataset()
        guard d.datasetPath.hasPrefix("/") ? String(d.datasetPath.dropFirst()) == file.dataset : d.datasetPath == file.dataset else { fail("cube dataset \(d.datasetPath) != labels' \(file.dataset)") }
        say("cube: \(d.datasetPath) shape \(d.shape)")
        let candidates = try await reader.probeCandidates(detectorQY: d.qy, detectorQX: d.qx)
        guard let candidate = candidates.first else { fail("no probe candidate") }
        let probe = DiffractionPattern(qy: candidate.qy, qx: candidate.qx, pixels: try await reader.readProbe(candidate))
        guard let size = OriginCalibration.probeSize(dp: probe.pixels, qy: probe.qy, qx: probe.qx) else { fail("no probe size") }
        let params = DiskDetectionParams.detectorAdapted(qy: d.qy, qx: d.qx, probeRadius: size.r)
        let threshold = LearnedDiskDetector.defaultThreshold
        say(String(format: "probe %@  r %.2f centre (%.2f, %.2f)  params: minPeakSpacing %.0f edgeBoundary %d minRel %.4f sigmaCC %.1f  threshold %.2f",
                   candidate.path, size.r, size.x0, size.y0, params.minPeakSpacing, params.edgeBoundary,
                   params.minRelativeIntensity, params.sigmaCC, threshold))
        let fourD = FourDArray(reader: reader, descriptor: d)
        // a read-only copy the runner placed beside the binary
        let bundledPackage = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("disk-detector-heatmap-256.mlpackage")
        guard FileManager.default.fileExists(atPath: bundledPackage.path) else { fail("bundled package missing at \(bundledPackage.path)") }
        say("bundled: \(bundledPackage.path)")

        let split = HeldOutSplit.split(Array(labels.keys))
        say("split: train \(split.train.count) · held out \(split.heldOut.count) (HeldOutSplit, 30 % by hash)")

        // ---- TR_PROBE_TRAIN_ONLY=1: the trainer alone (DetectorTrainer.train on the HeldOutSplit training positions), no held-out
        // detection, no Core ML load, no memory admission (the diagnostic is bounded by TR_PROBE_STOP_MB instead). It prints the
        // footprint every TR_PROBE_LOG_EVERY steps and the least-squares slope over steps >= 10 (MB/step).
        if envNumber("TR_PROBE_TRAIN_ONLY") == 1 {
            guard let builder = TrainingSampleBuilder(qy: d.qy, qx: d.qx, probe: probe, probeCentre: (x: size.x0, y: size.y0),
                                                      probeRadius: size.r, kernelSource: .fileProbe, params: params) else { fail("no sample builder") }
            var samples: [TrainingSample] = []
            for p in split.train { samples += builder.samples(pattern: try await fourD.pattern(ry: p.ry, rx: p.rx), position: p, centres: labels[p] ?? []) }
            say("train-only: \(samples.count) samples; footprint \(Int(DetectorTraining.footprintMB())) MB")
            var recipe = TrainingRecipe()
            if let n = envNumber("TR_PROBE_STEPS") { recipe.steps = Int(n) }
            let every = Int(envNumber("TR_PROBE_LOG_EVERY") ?? 10)
            let tok = AnalysisCancellationToken()
            nonisolated(unsafe) var pts: [(Double, Double)] = []
            let res = try await DetectorTrainer(parentPackage: bundledPackage, recipe: recipe).train(
                samples: samples, availableMemory: { Int.max }, cancellation: tok, progress: { p in
                    let mb = DetectorTraining.footprintMB()
                    if mb > memoryStopMB { tok.cancel() }
                    if p.step == 1 || p.step % every == 0 {
                        say(String(format: "  step %d/%d loss %.3e %.3f s/step %d MB", p.step, p.steps, p.loss, p.secondsPerStep, Int(mb)))
                        if p.step >= 10 { pts.append((Double(p.step), mb)) }
                    }
                })
            if pts.count >= 2 {
                let n = Double(pts.count), sx = pts.reduce(0) { $0 + $1.0 }, sy = pts.reduce(0) { $0 + $1.1 }
                let sxx = pts.reduce(0) { $0 + $1.0 * $1.0 }, sxy = pts.reduce(0) { $0 + $1.0 * $1.1 }
                say(String(format: "SLOPE %.3f MB/step over %d samples (steps >= 10)", (n * sxy - sx * sy) / (n * sxx - sx * sx), pts.count))
            }
            say(String(format: "train-only done: %.3f s/step, lifetime-max %.0f MB, final loss %.3e, wall %d s",
                       res.secondsPerStep, res.lifetimeMaxFootprintMB, res.stepLosses.last ?? .nan, Int(Date().timeIntervalSince(t0))))
            return
        }

        // ---- Part 1: the app's own run
        let active = try await LearnedDiskDetector.load(assetURL: bundledPackage)
        say("bundled model loaded (Neural Engine), sha \(active.assetSHA256.prefix(12)); footprint \(Int(DetectorTraining.footprintMB())) MB")
        let token = AnalysisCancellationToken()
        var recipe = TrainingRecipe()
        if let n = envNumber("TR_PROBE_STEPS") { recipe.steps = Int(n) }
        let logEvery = Int(envNumber("TR_PROBE_LOG_EVERY") ?? 100)
        let request = DetectorFineTuningRequest(
            data: fourD, qy: d.qy, qx: d.qx, labels: labels, probe: probe, probeCentre: (x: size.x0, y: size.y0),
            probeRadius: size.r, kernelSource: .fileProbe, params: params, threshold: threshold,
            bundledPackage: bundledPackage, active: active,
            stagingDirectory: outDir.appendingPathComponent("main-candidate", isDirectory: true), recipe: recipe)
        try? FileManager.default.removeItem(at: request.stagingDirectory)
        let report: @Sendable (DetectorFineTuningStage) -> Void = { stage in
            let mb = DetectorTraining.footprintMB()
            if mb > memoryStopMB { token.cancel() }
            switch stage {
            case .preparing(let i, let n): if i % 10 == 0 { say("  preparing \(i + 1)/\(n)  \(Int(mb)) MB") }
            case .training(let p): if p.step == 1 || p.step % logEvery == 0 {
                say(String(format: "  step %d/%d loss %.3e  %.3f s/step  %d MB", p.step, p.steps, p.loss, p.secondsPerStep, Int(mb))) }
            case .writing: say("  writing + loading the candidate")
            case .evaluating(let i, let n): if i % 4 == 0 { say("  judging \(i + 1)/\(n)") }
            }
        }
        // The app's own run, with the app's own memory admission (free + inactive pages >= 2 GB + samples). On a busy
        // 8 GB Mac it can refuse: wait for memory, at most 10 minutes; never bypass it.
        var outcome: DetectorFineTuningOutcome?
        for attempt in 0 ..< 11 {
            do { outcome = try await DetectorFineTuning.run(request, cancellation: token, progress: report); break }
            catch TrainingError.insufficientMemory(let avail, let need) {
                say(String(format: "admission refused (attempt %d): %.2f GB available, %.2f GB needed", attempt + 1, Double(avail) / 1e9, Double(need) / 1e9))
                try? FileManager.default.removeItem(at: request.stagingDirectory)
                if attempt < 10 { try await Task.sleep(nanoseconds: 60_000_000_000) }
            }
        }
        guard let outcome else { fail("the app's memory admission refused for 10 minutes; free memory (quit apps) and rerun", 69) }
        say("run finished in \(Int(Date().timeIntervalSince(t0))) s; \(String(format: "%.3f", outcome.secondsPerStep)) s/step; final step loss \(outcome.finalStepLoss.map { String(format: "%.3e", $0) } ?? "nil")")
        let A = outcome.active.score, C = outcome.candidate.score
        say("HELD-OUT (N = \(outcome.heldOut.count) positions, \(A.truth) centres; 2 px, threshold \(threshold), Neural Engine):")
        say(String(format: "  bundled    recall %.4f (%d/%d)  precision %.4f (%d/%d)", A.recall, A.matched, A.truth, A.precision, A.matched, A.predicted))
        say(String(format: "  fine-tuned recall %.4f (%d/%d)  precision %.4f (%d/%d)", C.recall, C.matched, C.truth, C.precision, C.matched, C.predicted))
        let offer = TrainingPolicy.offer(active: A, candidate: C)
        say("D7 verdict: \(offer)")
        guardMemory("after the app's run")
        say(String(format: "part 1 done. lifetime-max phys_footprint %.0f MB; wall %d s", DetectorTraining.lifetimeMaxFootprintMB(), Int(Date().timeIntervalSince(t0))))
        if envNumber("TR_PROBE_ONLY_PART1") == 1 { try? FileManager.default.removeItem(at: request.stagingDirectory); return }

        // ---- Part 2: per-position scores on all 40 positions
        var rows: [ScanPosition: [String: Counts]] = [:]
        func record(_ model: String, _ pos: ScanPosition, _ s: DetectionScore) { rows[pos, default: [:]][model] = Counts(s) }
        let all = Array(labels.keys).sorted()
        var patterns: [ScanPosition: DiffractionPattern] = [:]
        for p in all { patterns[p] = try await fourD.pattern(ry: p.ry, rx: p.rx) }
        func learned(_ model: LearnedDiskDetector, _ p: ScanPosition) async -> DetectionScore {
            let peaks = await model.detect(pattern: patterns[p]!, probe: probe, probeCentre: (x: size.x0, y: size.y0),
                                           probeRadius: size.r, kernelSource: .fileProbe, params: params, threshold: threshold)
            guard let peaks else { fail("learned detection failed at \(p)") }
            return DetectionScorer.score(truth: labels[p]!, predicted: peaks.map { ScorePoint(row: Double($0.y), col: Double($0.x)) })
        }
        for p in all { record("bundled", p, await learned(active, p)) }
        // consistency: the pooled bundled score on the held-out positions must equal the app's run
        let check = DetectionScorer.pooled(outcome.heldOut.map {
            DetectionScore(matched: rows[$0]!["bundled"]!.m, truth: rows[$0]!["bundled"]!.t, predicted: rows[$0]!["bundled"]!.p) })
        say("consistency (bundled, held-out, per-position pooled vs the app's run): \(check == A ? "EQUAL" : "DIFFERENT \(check) vs \(A)")")

        guard let kernel = ProbeKernel.measured(pattern: probe, originX: size.x0, originY: size.y0, radius: size.r,
                                                mode: .flat, source: .fileProbe, probePath: candidate.path),
              let detector = DiskDetector(kernel: kernel) else { fail("no classical kernel") }
        for p in all {
            let peaks = patterns[p]!.pixels.withUnsafeBufferPointer { detector.detect(pattern: $0.baseAddress!, params: params) }
            record("classical", p, DetectionScorer.score(truth: labels[p]!, predicted: peaks.map { ScorePoint(row: Double($0.y), col: Double($0.x)) }))
        }
        do {   // the main-split model at every position (in-sample at the training positions)
            let ft = try await LearnedDiskDetector.load(assetURL: outcome.candidatePackage)
            for p in all { record("ft_main", p, await learned(ft, p)) }
            let checkFT = DetectionScorer.pooled(outcome.heldOut.map {
                DetectionScore(matched: rows[$0]!["ft_main"]!.m, truth: rows[$0]!["ft_main"]!.t, predicted: rows[$0]!["ft_main"]!.p) })
            say("consistency (fine-tuned, held-out): \(checkFT == C ? "EQUAL" : "DIFFERENT \(checkFT) vs \(C)")")
        }
        say("per-position bundled/classical/ft_main done; footprint \(Int(DetectorTraining.footprintMB())) MB")
        try? FileManager.default.removeItem(at: request.stagingDirectory)   // the candidate is not needed any more

        // out-of-fold models
        let ranked = all.sorted {
            (HeldOutSplit.hashUnit(ry: $0.ry, rx: $0.rx), $0) < (HeldOutSplit.hashUnit(ry: $1.ry, rx: $1.rx), $1)
        }
        var fold: [ScanPosition: Int] = [:]
        for (i, p) in ranked.enumerated() { fold[p] = i % 4 }
        guard let builder = TrainingSampleBuilder(qy: d.qy, qx: d.qx, probe: probe, probeCentre: (x: size.x0, y: size.y0),
                                                  probeRadius: size.r, kernelSource: .fileProbe, params: params) else { fail("no sample builder") }
        var samples: [TrainingSample] = []
        for p in all { samples += builder.samples(pattern: patterns[p]!, position: p, centres: labels[p]!) }
        say("samples for cross-fitting: \(samples.count) (\(builder.windows.count) window(s) per position)")
        for (name, lr) in [("ft_oof_lr1e-05", 1e-5), ("ft_oof_lr1e-04", 1e-4)] {
            for k in 0 ..< 4 {
                var r = TrainingRecipe(); r.learningRate = lr
                let train = samples.filter { fold[$0.position!]! != k }
                var waited = 0
                while DetectorTraining.availableMemoryBytes() < DetectorTraining.requiredAvailableBytes + 100_000_000, waited < 10 {
                    say("  waiting for memory admission before \(name) fold \(k) (\(waited + 1)/10)"); try await Task.sleep(nanoseconds: 60_000_000_000); waited += 1
                }
                let trainer = DetectorTrainer(parentPackage: bundledPackage, recipe: r)
                let res = try await trainer.train(samples: train, cancellation: token, progress: { pr in
                    if DetectorTraining.footprintMB() > memoryStopMB { token.cancel() }
                    if pr.step % 250 == 0 {
                        say(String(format: "  %@ fold %d step %d/%d loss %.3e %d MB", name, k, pr.step, pr.steps, pr.loss, Int(DetectorTraining.footprintMB())))
                    }
                })
                let dir = outDir.appendingPathComponent("fold-\(name)-\(k)", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                let pkg = dir.appendingPathComponent("model.mlpackage")
                try ModelPackageWriter.write(weights: res.weights, toCopyOf: bundledPackage, at: pkg)
                let model = try await LearnedDiskDetector.load(assetURL: pkg)
                for p in all where fold[p] == k { record(name, p, await learned(model, p)) }
                try? FileManager.default.removeItem(at: dir)
                guardMemory("\(name) fold \(k)")
                say(String(format: "%@ fold %d done (%.3f s/step, final loss %.3e)", name, k, res.secondsPerStep, res.stepLosses.last ?? .nan))
            }
        }
        samples = []

        let out = ScoresFile(
            note: "counts (matched, truth, predicted) per position at 2 px; ft_main is in-sample at its training positions; ft_oof_* are out-of-fold",
            labelsSHA256: file.sha256,
            rows: all.map { PositionRow(ry: $0.ry, rx: $0.rx, heldOutMain: HeldOutSplit.isHeldOut($0), scores: rows[$0]!) })
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(out).write(to: outDir.appendingPathComponent("scores.json"))
        say(String(format: "scores.json written. lifetime-max phys_footprint %.0f MB; wall %d s",
                   DetectorTraining.lifetimeMaxFootprintMB(), Int(Date().timeIntervalSince(t0))))
        Resampling.report(out)
    }
}

// MARK: - §4

nonisolated enum Resampling {
    static let ks = [4, 6, 8, 10, 12, 16, 20, 30]
    static let draws = 10_000
    static let seed: UInt64 = 20_260_930
    static let delta = 0.03

    static func score(_ c: Counts) -> DetectionScore { DetectionScore(matched: c.m, truth: c.t, predicted: c.p) }

    /// "A", "B" or "n" (none): the D7 rule on pooled counts.
    static func verdict(_ a: DetectionScore, _ b: DetectionScore) -> Character {
        if case .offer = TrainingPolicy.offer(active: b, candidate: a) { return "A" }
        if case .offer = TrainingPolicy.offer(active: a, candidate: b) { return "B" }
        return "n"
    }

    static func report(_ f: ScoresFile) {
        let models = ["bundled", "ft_oof_lr1e-05", "ft_oof_lr1e-04", "classical"]
        let rows = f.rows
        let n = rows.count
        func pooled(_ m: String, _ idx: ArraySlice<Int>) -> DetectionScore {
            DetectionScorer.pooled(idx.map { score(rows[$0].scores[m]!) })
        }
        let full = Array(0 ..< n)[...]
        say("\n== §4: minimum held-out N (\(n) positions, all pooled) ==")
        for m in models {
            let s = pooled(m, full)
            say(String(format: "  full set %-15@ recall %.4f  precision %.4f  (%d/%d/%d)", m as NSString, s.recall, s.precision, s.matched, s.truth, s.predicted))
        }
        var pairs: [(String, String)] = []
        for i in 0 ..< models.count { for j in (i + 1) ..< models.count { pairs.append((models[i], models[j])) } }
        var rng = SplitMix64(seed: seed)
        var hits = [[Int]](repeating: [Int](repeating: 0, count: ks.count), count: pairs.count)
        var recallHits = hits, precisionHits = hits
        func signs(_ a: DetectionScore, _ b: DetectionScore) -> (Int, Int) {
            (TrainingPolicy.compare(matched: a.matched, of: a.truth, matched: b.matched, of: b.truth),
             TrainingPolicy.compare(matched: a.matched, of: a.predicted, matched: b.matched, of: b.predicted))
        }
        let fullV = pairs.map { verdict(pooled($0.0, full), pooled($0.1, full)) }
        let fullS = pairs.map { signs(pooled($0.0, full), pooled($0.1, full)) }
        var order = Array(0 ..< n)
        for (ki, k) in ks.enumerated() {
            for _ in 0 ..< draws {
                for i in 0 ..< k {   // partial Fisher-Yates
                    let j = i + Int(rng.next() % UInt64(n - i))
                    order.swapAt(i, j)
                }
                let sub = order[0 ..< k]
                var cache: [String: DetectionScore] = [:]
                for m in models { cache[m] = pooled(m, sub) }
                for (pi, p) in pairs.enumerated() {
                    let a = cache[p.0]!, b = cache[p.1]!
                    if verdict(a, b) == fullV[pi] { hits[pi][ki] += 1 }
                    let s = signs(a, b)
                    if s.0 == fullS[pi].0 { recallHits[pi][ki] += 1 }
                    if s.1 == fullS[pi].1 { precisionHits[pi][ki] += 1 }
                }
            }
        }
        say("\nverdict = D7 rule on the pooled subset (A / B / n = none); P(k) = share of \(draws) draws whose verdict equals the full-\(n) verdict")
        say("k = " + ks.map(String.init).joined(separator: "     "))
        var binding: [(pair: String, gap: Double, kmin: Int?)] = []
        for (pi, p) in pairs.enumerated() {
            let a = pooled(p.0, full), b = pooled(p.1, full)
            let gap = max(abs(a.recall - b.recall), abs(a.precision - b.precision))
            let P = hits[pi].map { Double($0) / Double(draws) }
            let kmin = zip(ks, P).first(where: { $0.1 >= 0.90 })?.0
            let label = "\(p.0) vs \(p.1)"
            say(String(format: "  %@  full verdict %@  gap %.3f%@", label as NSString, String(fullV[pi]) as NSString, gap,
                       gap >= delta ? "" : "  (< delta: indistinguishable)"))
            say("     P(verdict)        " + P.map { String(format: "%.3f", $0) }.joined(separator: " "))
            say("     P(recall sign)    " + recallHits[pi].map { String(format: "%.3f", Double($0) / Double(draws)) }.joined(separator: " "))
            say("     P(precision sign) " + precisionHits[pi].map { String(format: "%.3f", Double($0) / Double(draws)) }.joined(separator: " "))
            binding.append((label, gap, kmin))
        }
        say("\nk_min (smallest k with P >= 0.90) per pair with gap >= \(delta):")
        var worst = 0; var unresolved = false
        for b in binding where b.gap >= delta {
            say("  \(b.pair): \(b.kmin.map { String($0) } ?? ">30 (report: at least 30)")")
            if let k = b.kmin { worst = max(worst, k) } else { unresolved = true }
        }
        say("k_min over every pair with gap >= \(delta): \(unresolved ? "at least 30" : String(worst))")
        let close = binding.filter { $0.pair.hasPrefix("bundled vs ft") && $0.gap >= delta }
        let cw = close.compactMap { $0.kmin }.max()
        say("k_min over the bundled-vs-fine-tuned pairs with gap >= delta (the app's decision): "
            + (close.isEmpty ? "no such pair" : (close.contains { $0.kmin == nil } ? "at least 30" : String(cw ?? 0))))
    }
}
