//
//  LearnedDiskDetector.swift
//  The learned disk-candidate stage (docs/archive/v3/learned-detector-preregistration-2026-09-07.md (was docs/v3-plan.md §3a), step 4; C7, 2026-09-08).
//
//  A candidate stage, never a measurement: the net paints a disk-centre heatmap on
//  three channels (log-normalised pattern, the probe, the classical cross-correlation),
//  peak-picking on it gives candidates, and the classical detector's own refinement
//  measures each one (`DiskDetector.refine`). Served through Core ML on the Neural
//  Engine (owner, 2026-09-07, replacing the Core AI runtime the branch used; asked for
//  by name since 2026-09-30, see `load`). The asset is the verbatim `.mlpackage` in the bundle,
//  compiled once at load, and its tree hash goes into provenance
//  (`learned_model_sha256`) — the same number `export.py` records.
//
//  The model's frame is `inputSize` (256) px. A detector no larger than that is fitted
//  to the frame by `simulate.fit_to`'s rule — zero-padded about the probe centre, never
//  rescaled; a larger one is covered by overlapping windows (owner, 2026-09-08: windows
//  only above 256). Input normalisation is `simulate.model_inputs` line for line,
//  including the one count-scaling rule for float cubes (`simulate.to_counts`, C6); the
//  fixture test compares both against the Python reference.
//

// mac4DSTEM is Apple-Silicon-only, and this is the one place a compiler can say
// so. `Float16` below is the Neural Engine's half-precision path and does not
// exist on x86_64 macOS; the embedded HDF5 libraries are arm64-only Mach-Os
// besides. This guard exists because the project-level `ARCHS = arm64` does NOT
// reach the SwiftPM package targets where this file is compiled (2026-09-11):
// the pin has to travel on the xcodebuild command line, and the paths that
// cannot carry one - Xcode's Product > Archive, a bare `swift build`, CI's
// `core` job - would otherwise fail here with nineteen confusing diagnostics
// instead of one that names the cause. It is NOT `#if arch(arm64)` around the
// code: that would ship a second, different program in an x86_64 slice beside
// arm64-only HDF5, which is the artefact v2.5.1 already was. This refuses to
// build one. With the pin in place it never fires.
#if !arch(arm64)
#error("mac4DSTEM Core is arm64-only: LearnedDiskDetector uses Float16, which does not exist on x86_64 macOS, and the embedded HDF5 libraries are arm64-only. Pass ARCHS=arm64 on the xcodebuild command line - a project-level setting does not reach the SwiftPM package targets. See tools/lib/release-arch.sh.")
#endif

import Foundation
import Metal
import CryptoKit
import CoreML

package nonisolated final class LearnedDiskDetector: @unchecked Sendable {

    /// The model's spatial size: the 256-px retrain the owner chose (decisions.md 2026-09-08).
    package static let inputSize = 256
    /// The shipped pick threshold: the knee measured on the frozen labels (0.7: 0.77 / 0.71).
    package static let defaultThreshold: Float = 0.7
    /// `simulate.NOMINAL_BEAM_COUNTS`: a float pattern whose maximum is ≤ 1 is a fraction of this beam.
    package static let nominalBeamCounts: Float = 20_000

    package let assetURL: URL
    package let assetSHA256: String
    /// The batch every call uses: the package's default batch dimension (32 as shipped), short batches
    /// zero-padded rather than reshaped. Measured 2026-09-30 on the M5 Pro (macOS 27.0.1): under
    /// `.cpuAndNeuralEngine` the Neural Engine ran the package's default batch and no other batch tried — every
    /// other one came back with the CPU's numbers bit for bit, no error, no log line (shipped package, and
    /// variants with other defaults). Why is not known, so no rule about the number is relied on: `load` runs
    /// one batch and refuses a model the Neural Engine did not run (`neuralEngineDidNotRun`).
    package let batch: Int
    /// The compute units the model was loaded with, and the compiled model it was loaded from — what a test
    /// needs to ask Core ML for its plan and to load the same model beside this one.
    package let computeUnits: MLComputeUnits
    package let compiledURL: URL
    /// Where these weights came from, recorded beside `learned_model_sha256` (C4b, ADR 048): "bundled", or
    /// "fine-tuned" with the bundled package's tree hash as its parent. Set by whoever loads the detector,
    /// before it runs; provenance only — no number the detector computes reads either.
    package var origin = "bundled"
    package var parentSHA256: String?
    /// A test seam: called with (job index, the job's three-channel model input) for every (position, window) job
    /// of a scan, from the CPU workers (so it must be thread-safe). Never set by the app.
    package var inputObserver: (@Sendable (Int, [Float16]) -> Void)?
    private let model: MLModel
    private let inputName = "x"
    private let outputName = "heatmap"

    private init(assetURL: URL, sha: String, model: MLModel, batch: Int, computeUnits: MLComputeUnits, compiledURL: URL) {
        self.assetURL = assetURL; self.assetSHA256 = sha; self.model = model; self.batch = batch
        self.computeUnits = computeUnits; self.compiledURL = compiledURL
    }

    /// Loads the asset: hash the package tree, compile it (Core ML writes the compiled
    /// model to a temporary location that lives as long as the process), load it on
    /// the Neural Engine. Slow the first time; never inside a run.
    /// The compute units are `.cpuAndNeuralEngine`, not `.all` (2026-09-30, docs/archive/v4/ane-return-2026-09-30/):
    /// on the M5 Pro under macOS 27.0.1 `.all` plans and runs this model on the GPU, whose heatmaps differ from
    /// the Neural Engine's the fixture and the threshold were measured on. Under `.cpuAndNeuralEngine` only the
    /// CPU can stand in for the Neural Engine, and it does so silently, so the load proves which ran: one fixed
    /// batch through this model and through a `.cpuOnly` load of it; equal bit for bit means the Neural Engine
    /// did not run, and the load throws rather than hand back a detector with other numerics.
    /// `compiledURL`: an already compiled `.mlmodelc` of this very package (the model store keeps one);
    /// it is loaded as it is and nothing is compiled. The identity is still the package's tree hash.
    /// A compiled model that cannot be loaded throws — the caller decides whether to fall back.
    package static func load(assetURL: URL, compiledURL: URL? = nil) async throws -> LearnedDiskDetector {
        try await loadForComparison(assetURL: assetURL, compiledURL: compiledURL, computeUnits: .cpuAndNeuralEngine)
    }

    /// `load` on another compute unit, or at another batch: for the tools and tests that compare units and show
    /// the refusal. The app never calls it (`run-tests.sh inventory` greps for that) — a detector on another
    /// unit gives other candidates than the one the threshold was measured with.
    package static func loadForComparison(assetURL: URL, compiledURL: URL? = nil, computeUnits: MLComputeUnits,
                                          batch requestedBatch: Int? = nil) async throws -> LearnedDiskDetector {
        let sha = try sha256(ofAsset: assetURL)
        let compiled: URL
        if let compiledURL {
            compiled = compiledURL
        } else {
            do { compiled = try await MLModel.compileModel(at: assetURL) }
            catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.compileModel(at:)", underlying: error) }
        }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        let model: MLModel
        do { model = try await MLModel.load(contentsOf: compiled, configuration: config) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.load(contentsOf:) — compute units \(computeUnits.rawValue)", underlying: error) }
        let desc = model.modelDescription
        guard let input = desc.inputDescriptionsByName["x"], let c = input.multiArrayConstraint,
              desc.outputDescriptionsByName["heatmap"] != nil,
              c.shape.count == 4, c.shape[1].intValue == 3, c.shape[2].intValue == inputSize, c.shape[3].intValue == inputSize else {
            throw LearnedDiskDetectorError.unexpectedSignature(Array(desc.inputDescriptionsByName.keys), Array(desc.outputDescriptionsByName.keys))
        }
        let detector = LearnedDiskDetector(assetURL: assetURL, sha: sha, model: model, batch: requestedBatch ?? c.shape[0].intValue,
                                           computeUnits: computeUnits, compiledURL: compiled)
        if computeUnits == .cpuAndNeuralEngine {
            let cpuConfig = MLModelConfiguration()
            cpuConfig.computeUnits = .cpuOnly
            let cpuModel: MLModel
            do { cpuModel = try await MLModel.load(contentsOf: compiled, configuration: cpuConfig) }
            catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.load(contentsOf:) — CPU only, for the Neural Engine check", underlying: error) }
            let cpu = LearnedDiskDetector(assetURL: assetURL, sha: sha, model: cpuModel, batch: detector.batch,
                                          computeUnits: .cpuOnly, compiledURL: compiled)
            let probe = (0..<(detector.batch * 3 * inputSize * inputSize)).map { Float16(abs(sin(Double($0) * 0.0137))) }
            let ran = try await detector.heatmaps(inputs: probe), onCPU = try await cpu.heatmaps(inputs: probe)
            guard zip(ran, onCPU).contains(where: { $0.bitPattern != $1.bitPattern }) else {
                throw LearnedDiskDetectorError.neuralEngineDidNotRun(batch: detector.batch)
            }
        }
        return detector
    }

    /// `export.py`'s `sha256_tree`: every file under the asset, sorted by relative path,
    /// each contributing its path then its bytes. The pinned identity of the weights.
    package static func sha256(ofAsset url: URL) throws -> String {
        var hasher = SHA256()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { throw LearnedDiskDetectorError.assetMissing(url) }
        if isDir.boolValue {
            let base = url.standardizedFileURL.path
            var files: [String] = []
            // No path COMPONENT may start with "." — a Finder `.DS_Store` at any depth
            // is not model content; `export.py`'s `sha256_tree` applies the same rule,
            // so both sides hash the same files (Gate B 2026-09-08: the root-only
            // filter here and no filter there could disagree on a nested dotfile).
            if let e = fm.enumerator(atPath: base) { for case let rel as String in e
                where !rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                var d: ObjCBool = false
                if fm.fileExists(atPath: base + "/" + rel, isDirectory: &d), !d.boolValue { files.append(rel) }
            } }
            for rel in files.sorted() {
                hasher.update(data: Data(rel.utf8))
                hasher.update(data: try Data(contentsOf: URL(fileURLWithPath: base + "/" + rel)))
            }
        } else {
            hasher.update(data: Data(url.lastPathComponent.utf8))
            hasher.update(data: try Data(contentsOf: url))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Normalisation and peak-picking (pure functions, tested against Python)

    /// `simulate.to_counts`: a pattern whose maximum lies in (0, 1] is a fraction of a
    /// nominal 2×10⁴-count beam and is scaled into counts; anything else is already counts.
    /// One rule for float cubes on both sides (C6, decisions.md 2026-09-07).
    package static func toCounts(_ pattern: [Float]) -> [Float] {
        let mx = pattern.max() ?? 0
        guard mx > 0, mx <= 1 else { return pattern }
        let s = nominalBeamCounts / mx
        return pattern.map { $0 * s }
    }

    /// The scale `toCounts` would apply to a whole native pattern of `count` pixels: `nominalBeamCounts / max` when
    /// the largest FINITE value lies in (0, 1], else 1. Non-finite pixels are ignored, as `fillNonFinite` replaces
    /// them in every frame before the maximum is read.
    package static func nativeCountScale(pattern: UnsafePointer<Float>, count: Int) -> Float {
        var mx: Float = 0
        for i in 0..<count { let v = pattern[i]; if v.isFinite && v > mx { mx = v } }
        return mx > 0 && mx <= 1 ? nominalBeamCounts / mx : 1
    }

    /// `simulate.model_inputs`: (3, S, S) float16 — log1p(max(p − min p, 0)) / max on the
    /// count-scaled pattern, probe / max, correlation / max. Dose-invariant; keeps raw
    /// counts inside float16.
    ///
    /// `countScale` (D098, 2026-09-29): the dose scale of the NATIVE pattern this frame was cut from
    /// (`nativeCountScale`), 1 for a pattern already in counts. `nil` is the per-frame rule (`toCounts`) - the
    /// one a detector that fits the frame has always used, and its output is unchanged. A window of a larger
    /// detector passes the scale of its whole pattern: `simulate.model_inputs` scales the native pattern, then
    /// fits it, so every window of one pattern must see one scale, not its own maximum's.
    package static func modelInputs(pattern: [Float], probe: [Float], correlation: [Float], countScale: Float? = nil) -> [Float16] {
        let n = inputSize * inputSize
        precondition(pattern.count == n && probe.count == n && correlation.count == n)
        var out = [Float16](repeating: 0, count: 3 * n)
        let counts: [Float]
        if let s = countScale { counts = s == 1 ? pattern : pattern.map { $0 * s } } else { counts = toCounts(pattern) }
        let pMin = counts.min() ?? 0
        var logged = [Float](repeating: 0, count: n)
        for i in 0..<n { logged[i] = log1p(max(counts[i] - pMin, 0)) }
        let scales = [max(logged.max() ?? 0, 1e-12), max(probe.max() ?? 0, 1e-12), max(correlation.max() ?? 0, 1e-12)]
        for i in 0..<n {
            out[i] = Float16(logged[i] / scales[0])
            out[n + i] = Float16(probe[i] / scales[1])
            out[2 * n + i] = Float16(correlation[i] / scales[2])
        }
        return out
    }

    /// `evaluate.pick`: 3×3 local maxima (ties kept, as numpy's maximum_filter keeps them;
    /// out-of-grid neighbours count as 0) above `threshold`, brightest first.
    package static func pickPeaks(heatmap h: UnsafeBufferPointer<Float16>, threshold: Float) -> [DiskDetector.Candidate] {
        let S = inputSize
        precondition(h.count == S * S)
        var out: [DiskDetector.Candidate] = []
        for y in 0..<S {
            for x in 0..<S {
                let v = Float(h[y * S + x])
                guard v > threshold else { continue }
                var isMax = true
                for dy in -1...1 where isMax {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = x + dx, ny = y + dy
                        let w: Float = (nx < 0 || ny < 0 || nx >= S || ny >= S) ? 0 : Float(h[ny * S + nx])
                        if w > v { isMax = false; break }
                    }
                }
                if isMax { out.append(DiskDetector.Candidate(x: x, y: y, score: v)) }
            }
        }
        out.sort { $0.score > $1.score }
        return out
    }

    // MARK: The model frame: fit (pad or crop about the probe) and windows

    /// `simulate.fit_offset`: the integer (row, col) origin of the S×S frame placed so
    /// that `centre` lands at the frame's own centre — `round(centre) − S/2`, with
    /// Python's round-half-to-even. Negative when the detector is smaller than the frame
    /// (the frame hangs over the detector's edge and the overhang is zero).
    package static func fitOffset(probeCentre: (x: Float, y: Float)) -> (row0: Int, col0: Int) {
        (Int(probeCentre.y.rounded(.toNearestOrEven)) - inputSize / 2,
         Int(probeCentre.x.rounded(.toNearestOrEven)) - inputSize / 2)
    }

    /// The S×S window of a `qy × qx` image whose top-left sits at (`row0`, `col0`) in the
    /// image's frame: the overlap is copied, everything outside the image is zero
    /// (`simulate.fit_to`'s one operation: crop and pad are the same copy). Native
    /// pixels are never rescaled.
    package static func window(of image: UnsafePointer<Float>, qy: Int, qx: Int, row0: Int, col0: Int, into out: inout [Float]) {
        let S = inputSize
        precondition(out.count == S * S)
        let xs = max(col0, 0), xe = min(col0 + S, qx)
        for y in 0..<S {
            let sy = row0 + y
            let row = y * S
            if sy < 0 || sy >= qy || xs >= xe {
                for x in 0..<S { out[row + x] = 0 }
                continue
            }
            for x in 0..<S where x < xs - col0 || x >= xe - col0 { out[row + x] = 0 }
            let src = image + sy * qx + xs
            for x in xs..<xe { out[row + x - col0] = src[x - xs] }
        }
    }

    /// One disk diameter: `2·⌈probeRadius⌉ + 2`, never less than 24 px. The
    /// overlap between neighbouring windows, so a disk cut by one window's
    /// edge is whole — its centre inside the window's boundary, not on it —
    /// in the neighbour that overlaps it.
    package static func windowOverlap(probeRadius: Float) -> Int {
        max(2 * Int(probeRadius.rounded(.up)) + 2, 24)
    }

    /// Window origins along one detector axis of length `q`. `q < inputSize` is one
    /// window at `fit_offset` — the frame centred on the probe, hanging over the
    /// detector where the detector is shorter (zero padding, `simulate.fit_to`);
    /// `q == inputSize` is the detector itself (origin 0, as `evaluate.py` applies
    /// `fit_to` only when the size differs); a longer axis is covered by
    /// `n = ⌈(q − overlap) / (inputSize − overlap)⌉` windows whose origins spread
    /// evenly across `0 ... q − inputSize` (integer, rounded) so consecutive windows
    /// overlap by `overlap` px everywhere (windowing applies only above 256 px,
    /// decided 2026-09-08).
    package static func windowOrigins(q: Int, probeCentreOnAxis: Float, overlap: Int) -> [Int] {
        let S = inputSize
        if q < S { return [Int(probeCentreOnAxis.rounded(.toNearestOrEven)) - S / 2] }
        if q == S { return [0] }
        // overlap is clamped below inputSize so the step can never be ≤ 0 —
        // params validation keeps probeRadius (and so overlap) far under this
        // in practice, but a formula that could divide by zero on bad input
        // is a defect waiting to happen.
        let step = max(S - min(overlap, S - 1), 1)
        let n = max(Int((Double(q - overlap) / Double(step)).rounded(.up)), 2)
        return (0..<n).map { i in Int((Double(i) * Double(q - S) / Double(n - 1)).rounded()) }
    }

    /// The edge-rule margin `(lo, hi)` of each window along one axis (D004, 2026-09-29). A window side that
    /// is the detector's own edge (the first window's `lo`, the last window's `hi`, or the only window's both) keeps
    /// `edge` - `edgeBoundary`, the rule the classical detector applies. A side shared with a neighbouring window
    /// takes `min(edge, overlap / 2)`, `overlap` being the ACTUAL pixels the pair shares (`origins` spread evenly and
    /// rounded, so 256 − step, not the nominal `windowOverlap`): the two margins of a pair then add to at most the
    /// overlap, so the intervals the two windows accept touch and no band of the detector goes unsearched. Where the
    /// overlap is at least `2 · edge` this is `edge` on every side - the rule as it was; the margin shrinks only
    /// where the old rule left a gap (`edgeBoundary = qMin/24` grows with the detector, the overlap does not:
    /// q = 1024, overlap 64 against 2·42 = 84).
    package static func edgeMargins(origins: [Int], edge: Int) -> [(lo: Int, hi: Int)] {
        let S = inputSize
        return origins.indices.map { i in
            let lo = i == 0 ? edge : min(edge, max(origins[i - 1] + S - origins[i], 0) / 2)
            let hi = i == origins.count - 1 ? edge : min(edge, max(origins[i] + S - origins[i + 1], 0) / 2)
            return (lo, hi)
        }
    }

    /// Merge one scan position's per-window peaks, already shifted to the full
    /// detector frame: a peak within `minPeakSpacing` of an already-kept peak
    /// is the same disk seen through two overlapping windows — the overlap
    /// exists so no disk is missed, not so it is counted twice — and the
    /// higher-`intensity` (refined correlation value) copy wins. Capped at
    /// `maxNumPeaks`. Same shape as `DiskDetector.refine`'s own NMS, ranked by
    /// intensity rather than the net's score: score is a per-window rank, not
    /// comparable across windows, but the correlation intensity the refined
    /// position sits on is the same physical quantity everywhere.
    package static func mergeWindows(_ perWindow: [[BraggPeak]], params: DiskDetectionParams) -> [BraggPeak] {
        var all = perWindow.flatMap { $0 }
        all.sort { $0.intensity > $1.intensity }
        var kept: [BraggPeak] = []
        outer: for p in all {
            for k in kept {
                let dx = p.x - k.x, dy = p.y - k.y
                if (dx * dx + dy * dy).squareRoot() < params.minPeakSpacing { continue outer }
            }
            kept.append(p)
            if kept.count >= params.maxNumPeaks { break }
        }
        return kept
    }

    // MARK: Inference

    /// One batch through the model: inputs (B, 3, S, S) float16 → heatmaps (B, S, S) float16.
    /// `inputs.count` must be exactly `batch * 3 * S * S`; pad short batches with zeros.
    package func heatmaps(inputs: [Float16]) async throws -> [Float16] {
        let S = Self.inputSize
        precondition(inputs.count == batch * 3 * S * S)
        let x: MLMultiArray
        do { x = try MLMultiArray(shape: [batch, 3, S, S].map { NSNumber(value: $0) }, dataType: .float16) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLMultiArray(shape:dataType:)", underlying: error) }
        x.withUnsafeMutableBytes { dst, _ in
            inputs.withUnsafeBytes { src in dst.copyMemory(from: src) }
        }
        let provider: MLFeatureProvider
        do { provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: x)]) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLDictionaryFeatureProvider", underlying: error) }
        let result: MLFeatureProvider
        do { result = try await model.prediction(from: provider) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.prediction(from:)", underlying: error) }
        guard let array = result.featureValue(for: outputName)?.multiArrayValue,
              array.shape.count == 4, array.shape[0].intValue == batch,
              array.shape[2].intValue == S, array.shape[3].intValue == S else {
            throw LearnedDiskDetectorError.noOutput(outputName)
        }
        let count = batch * S * S
        var out = [Float16](repeating: 0, count: count)
        switch array.dataType {
        case .float16:
            array.withUnsafeBytes { src in
                out.withUnsafeMutableBytes { dst in dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<(count * 2)])) }
            }
        case .float32:
            array.withUnsafeBufferPointer(ofType: Float.self) { src in for i in 0..<count { out[i] = Float16(src[i]) } }
        case .double:
            array.withUnsafeBufferPointer(ofType: Double.self) { src in for i in 0..<count { out[i] = Float16(src[i]) } }
        default:
            throw LearnedDiskDetectorError.noOutput("\(outputName) (unexpected element type \(array.dataType.rawValue))")
        }
        return out
    }

    // MARK: One pattern (the live overlay)

    /// The learned candidates for ONE pattern, refined like the scan's: a
    /// one-position cube through `detectAll(cube:…)`, so the preview on the
    /// current CBED is exactly what the full scan would find there (owner's
    /// drive, 2026-09-07: the rings must be checkable before Detect All).
    /// Returns nil where `detectAll` would (invalid params, probe of another size).
    package func detect(
        pattern: DiffractionPattern, probe: DiffractionPattern, probeCentre: (x: Float, y: Float),
        probeRadius: Float, kernelSource: ProbeKernelSource = .measured,
        params: DiskDetectionParams, threshold: Float = LearnedDiskDetector.defaultThreshold
    ) async -> [BraggPeak]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let buffer = device.makeBuffer(bytes: pattern.pixels, length: pattern.pixels.count * MemoryLayout<Float>.stride,
                                             options: .storageModeShared) else { return nil }
        let d = DatasetDescriptor(filePath: "", datasetPath: "live", shape: [1, 1, pattern.qy, pattern.qx],
                                  dtypeDescription: "float32", chunkShape: nil)
        return await detectAll(cube: buffer, descriptor: d, probe: probe, probeCentre: probeCentre, probeRadius: probeRadius,
                               kernelSource: kernelSource, params: params, threshold: threshold)?.peaks.first
    }

    // MARK: The scan

    /// Detect disks at every scan position of a resident float32 cube [ry][rx][qy][qx].
    /// A detector no larger than S×S is one window: the S×S frame placed by `fitOffset`
    /// about `probeCentre` (zero where it hangs over the detector); a larger one is
    /// covered by a grid of S×S windows (`windowOrigins`) spread evenly across each axis
    /// with a probe-diameter overlap, so a disk cut by one window's edge is whole in its
    /// neighbour. The probe is fitted the same way (one crop, centred on the probe, for
    /// every window: correlation is translation-invariant and the net's probe channel is
    /// the same everywhere), and the classical correlation of each window with the
    /// probe-centred flat kernel is channel three. Batches may mix windows and positions;
    /// each window's picks are refined by the classical detector and shifted back to the
    /// full detector frame, then `mergeWindows` collapses duplicates from overlap and caps
    /// the count per position. Provenance carries the classical parameters, the learned
    /// stage's identity, and the frame (`learned_windows`, `learned_window_overlap_px`,
    /// `learned_crop_origin_*` for the one-window case — negative means padding —
    /// `learned_window_origins` otherwise). Above the frame two rules differ from the one-window case (2026-09-29, the record
    /// docs/archive/v4/learned-windows-D098-D004-gateD-2026-09-30.md):
    /// the dose scale of a float pattern (`simulate.to_counts`) is taken once from the whole pattern (`nativeCountScale`)
    /// and shared by its windows (D098), and a window side shared with a neighbour takes the edge margin
    /// `edgeMargins` gives, so the band between two windows is searched by at least one of them (D004).
    package func detectAll(
        cube: MTLBuffer, descriptor d: DatasetDescriptor,
        probe: DiffractionPattern, probeCentre: (x: Float, y: Float), probeRadius: Float,
        kernelSource: ProbeKernelSource = .measured,
        params: DiskDetectionParams, threshold: Float = LearnedDiskDetector.defaultThreshold,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> BraggVectors? {
        let S = Self.inputSize
        guard d.qy > 0, d.qx > 0, probe.qy == d.qy, probe.qx == d.qx else { return nil }
        // the classical parameter validation, as DiskDetection.detectAll applies it (at the frame size)
        guard !params.validationIssues(in: DiskDetectionContext(qy: S, qx: S, probeRadius: probeRadius))
            .contains(where: { $0.severity == .error }) else { return nil }

        let overlap = Self.windowOverlap(probeRadius: probeRadius)
        let rowOrigins = Self.windowOrigins(q: d.qy, probeCentreOnAxis: probeCentre.y, overlap: overlap)
        let colOrigins = Self.windowOrigins(q: d.qx, probeCentreOnAxis: probeCentre.x, overlap: overlap)
        let windows: [(row0: Int, col0: Int)] = rowOrigins.flatMap { r in colOrigins.map { c in (row0: r, col0: c) } }
        let nWindows = windows.count
        // A detector covered by several windows scales the pattern's dose once, from the whole pattern (D098), and
        // gives each window the edge margins that leave no band unsearched between neighbours (D004). One window
        // (a detector that fits the frame) keeps the per-frame scale and the plain edge rule, unchanged.
        let windowed = nWindows > 1
        let rowMargins = Self.edgeMargins(origins: rowOrigins, edge: params.edgeBoundary)
        let colMargins = Self.edgeMargins(origins: colOrigins, edge: params.edgeBoundary)

        // the probe's frame and its flat kernel, centred on the probe: ONE for every window.
        // Fitted like the pattern when the detector fits the frame; a centred crop clamped
        // inside the detector when windows are needed. Probe anchor, measured 2026-09-29/30 (the record
        // docs/archive/v4/learned-windows-D098-D004-gateD-2026-09-30.md): with the model's probe channel zeroed,
        // every peak list measured was bit-identical (512 px with the beam 90 px from an edge, ten real Si_SiGe
        // 448x480 patterns, the <= 256 px fixtures); an unclamped `fitOffset` crop (which also moves the kernel's
        // frame) finds the same disks at 2 px; a probe crop at each window's own origin loses 5 of 320 Si_SiGe
        // peaks. So the clamped crop stays.
        let probeRow0 = d.qy > S ? min(max(Int(probeCentre.y.rounded(.toNearestOrEven)) - S / 2, 0), d.qy - S) : rowOrigins[0]
        let probeCol0 = d.qx > S ? min(max(Int(probeCentre.x.rounded(.toNearestOrEven)) - S / 2, 0), d.qx - S) : colOrigins[0]
        var probeCrop = [Float](repeating: 0, count: S * S)
        probe.pixels.withUnsafeBufferPointer { Self.window(of: $0.baseAddress!, qy: d.qy, qx: d.qx, row0: probeRow0, col0: probeCol0, into: &probeCrop) }
        _ = probeCrop.withUnsafeMutableBufferPointer {
            DiskDetector.fillNonFinite($0.baseAddress!, width: S, height: S, rowStride: S)   // D019
        }
        guard let kernel = ProbeKernel.flat(
            pattern: DiffractionPattern(qy: S, qx: S, pixels: probeCrop),
            originX: probeCentre.x - Float(probeCol0), originY: probeCentre.y - Float(probeRow0),
            radius: probeRadius, source: kernelSource
        ) else { return nil }
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, batch))
        var detectors: [DiskDetector] = []
        for _ in 0..<workers { guard let det = DiskDetector(kernel: kernel) else { return nil }; detectors.append(det) }

        let positions = d.ry * d.rx
        let patPix = d.qy * d.qx
        let base = cube.contents().bindMemory(to: Float.self, capacity: positions * patPix)
        // one slot per (position, window) job; merged into `positions` results after the loop
        var perWindowResults = [[BraggPeak]](repeating: [], count: positions * nWindows)
        let totalJobs = positions * nWindows
        let n3 = 3 * S * S
        var lastBucket = -1
        var scaleCachePos = -1, scaleCache: Float = 1

        struct Shared: @unchecked Sendable {
            let base: UnsafePointer<Float>; let inputs: UnsafeMutablePointer<Float16>
            let smoothed: UnsafeMutablePointer<[Float]>; let detectors: [DiskDetector]
            let windows: [(row0: Int, col0: Int)]
            let scales: [Float]; let firstPos: Int
            let observer: (@Sendable (Int, [Float16]) -> Void)?
        }
        /// Channel three and the model inputs for `count` (position, window) jobs from
        /// `start`, one CPU worker per detector (this is the classical cost); the batch
        /// buffer is zero-padded past `count`. Job `j` is position `j / nWindows`, window
        /// `j % nWindows` — position-major, so consecutive jobs share a pattern.
        func prepare(start: Int, count: Int, inputs: inout [Float16], smoothed: inout [[Float]]) {
            // one dose scale per native pattern in this batch (D098); a position spans batches, so the last is kept
            let firstPos = start / nWindows, lastPos = (start + count - 1) / nWindows
            var scales: [Float] = []
            if windowed && count > 0 {
                for pos in firstPos...lastPos {
                    if pos != scaleCachePos { scaleCachePos = pos; scaleCache = Self.nativeCountScale(pattern: base + pos * patPix, count: patPix) }
                    scales.append(scaleCache)
                }
            }
            inputs.withUnsafeMutableBufferPointer { ib in
                smoothed.withUnsafeMutableBufferPointer { sb in
                    let shared = Shared(base: base, inputs: ib.baseAddress!, smoothed: sb.baseAddress!, detectors: detectors, windows: windows,
                                        scales: scales, firstPos: firstPos, observer: inputObserver)
                    DispatchQueue.concurrentPerform(iterations: workers) { w in
                        var crop = [Float](repeating: 0, count: S * S)
                        for b in stride(from: w, to: count, by: workers) {
                            let job = start + b
                            let pos = job / nWindows
                            let win = shared.windows[job % nWindows]
                            Self.window(of: shared.base + pos * patPix, qy: d.qy, qx: d.qx, row0: win.row0, col0: win.col0, into: &crop)
                            // The net's own input channel reads the raw crop: one
                            // NaN there poisoned every input (D019 refuter).
                            _ = crop.withUnsafeMutableBufferPointer {
                                DiskDetector.fillNonFinite($0.baseAddress!, width: S, height: S, rowStride: S)
                            }
                            let corr = crop.withUnsafeBufferPointer { shared.detectors[w].correlation(pattern: $0.baseAddress!, params: params) }
                            let mi = Self.modelInputs(pattern: crop, probe: probeCrop, correlation: corr.raw,
                                                      countScale: shared.scales.isEmpty ? nil : shared.scales[pos - shared.firstPos])
                            shared.observer?(job, mi)
                            for i in 0..<n3 { shared.inputs[b * n3 + i] = mi[i] }
                            shared.smoothed[b] = corr.smoothed
                        }
                    }
                }
            }
            if count < batch { for i in (count * n3)..<(batch * n3) { inputs[i] = 0 } }
        }
        func finish(start: Int, count: Int, heat: [Float16], smoothed: [[Float]]) {
            heat.withUnsafeBufferPointer { hb in
                for b in 0..<count {
                    let slice = UnsafeBufferPointer(rebasing: hb[(b * S * S)..<((b + 1) * S * S)])
                    let cands = Self.pickPeaks(heatmap: slice, threshold: threshold)
                    let job = start + b
                    let win = windows[job % nWindows]
                    var margins: DiskDetector.EdgeMargins?
                    if windowed {
                        let w = job % nWindows, r = rowMargins[w / colOrigins.count], c = colMargins[w % colOrigins.count]
                        margins = DiskDetector.EdgeMargins(left: c.lo, right: c.hi, top: r.lo, bottom: r.hi)
                    }
                    var peaks = detectors[0].refine(candidates: cands, smoothedCorrelation: smoothed[b], params: params, edgeMargins: margins)
                    for i in peaks.indices { peaks[i].x += Float(win.col0); peaks[i].y += Float(win.row0) }
                    perWindowResults[job] = peaks
                }
            }
        }

        // Two batch buffers: while the Neural Engine runs batch k, the CPU prepares batch k+1
        // (§3a "compute streams"; serial was 2.3-2.6x the classical wall clock on 2026-09-07).
        // Unchanged by tiling: jobs are a flat (position, window) list, batched the same way.
        var bufA = [Float16](repeating: 0, count: batch * n3), bufB = [Float16](repeating: 0, count: batch * n3)
        var smA = [[Float]](repeating: [], count: batch), smB = [[Float]](repeating: [], count: batch)
        var start = 0
        var count = min(batch, totalJobs)
        prepare(start: 0, count: count, inputs: &bufA, smoothed: &smA)
        while start < totalJobs {
            if cancellation?.isCancelled == true { return nil }
            let inputsNow = bufA
            async let heat = heatmaps(inputs: inputsNow)
            let next = start + count
            let nextCount = min(batch, totalJobs - next)
            if nextCount > 0 { prepare(start: next, count: nextCount, inputs: &bufB, smoothed: &smB) }
            guard let h = try? await heat else { return nil }
            finish(start: start, count: count, heat: h, smoothed: smA)
            swap(&bufA, &bufB); swap(&smA, &smB)
            start = next; count = nextCount
            if let progress {
                let bucket = start * 1000 / totalJobs
                if bucket != lastBucket { lastBucket = bucket; progress(Double(start) / Double(totalJobs)) }
            }
        }

        var results = [[BraggPeak]](repeating: [], count: positions)
        for pos in 0..<positions {
            let slice = perWindowResults[(pos * nWindows)..<((pos + 1) * nWindows)]
            results[pos] = Self.mergeWindows(Array(slice), params: params)
        }

        var provenance = params.provenance(kernel: kernel, qy: d.qy, qx: d.qx)
        provenance["detector_class"] = DetectorClass.learned.provenanceID
        provenance["learned_runtime"] = "coreml"
        provenance["learned_model_asset"] = assetURL.lastPathComponent
        provenance["learned_model_sha256"] = assetSHA256
        provenance["learned_model_origin"] = origin
        if let parent = parentSHA256 { provenance["learned_model_parent_sha256"] = parent }
        provenance["learned_threshold"] = String(threshold)
        provenance["learned_input_px"] = String(S)
        provenance["learned_windows"] = "\(rowOrigins.count)x\(colOrigins.count)"
        provenance["learned_window_overlap_px"] = String(overlap)
        if rowOrigins.count == 1, colOrigins.count == 1 {
            provenance["learned_crop_origin_x"] = String(windows[0].col0)
            provenance["learned_crop_origin_y"] = String(windows[0].row0)
        } else {
            provenance["learned_window_origins"] = windows.map { "\($0.row0),\($0.col0)" }.joined(separator: ";")
        }
        return BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: results, detectionProvenance: provenance)
    }
}

package enum LearnedDiskDetectorError: Error, CustomStringConvertible, LocalizedError {
    case assetMissing(URL)
    case unexpectedSignature([String], [String])
    case noOutput(String)
    case neuralEngineDidNotRun(batch: Int)
    case runtime(step: String, underlying: Error)
    package var description: String {
        switch self {
        case .runtime(let step, let underlying):
            let ns = underlying as NSError
            return "learned detector: \(step) failed — \(ns.domain) \(ns.code): \(ns.localizedDescription)"
        case .assetMissing(let u): return "learned detector: no asset at \(u.path)"
        case .unexpectedSignature(let i, let o): return "learned detector: unexpected signature inputs \(i) outputs \(o)"
        case .noOutput(let n): return "learned detector: no output '\(n)'"
        case .neuralEngineDidNotRun(let batch):
            return "learned detector: the Neural Engine did not run this model (batch \(batch)); the CPU would give other candidates, so it is not used"
        }
    }
    /// What the app shows: `localizedDescription` of a plain Swift error is the
    /// generic "could not be completed", which is exactly the text that hid the
    /// runtime's failure on 2026-09-07.
    package var errorDescription: String? { description }
}
