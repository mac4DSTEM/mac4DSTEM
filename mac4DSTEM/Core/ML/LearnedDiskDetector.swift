//
//  LearnedDiskDetector.swift
//  The learned disk-candidate stage (docs/v3-plan.md §3a, step 4; 2026-09-07).
//
//  A candidate stage, never a measurement: the net paints a disk-centre heatmap on
//  three channels (log-normalised pattern, the probe, the classical cross-correlation),
//  peak-picking on it gives candidates, and the classical detector's own refinement
//  measures each one (`DiskDetector.refine`). Served through Core AI on macOS 27+ with
//  the Neural Engine preferred; the classical detector serves everyone else. The asset
//  is pinned in the bundle and hashed into provenance (`learned_model_sha256`).
//
//  Input normalisation is `simulate.model_inputs` line for line (tools/disk-detector):
//  the fixture test compares both against the Python reference.
//

import Foundation
import Metal
import CryptoKit
#if canImport(CoreAI)
import CoreAI
#endif

#if canImport(CoreAI)
@available(macOS 27, *)
package nonisolated final class LearnedDiskDetector: @unchecked Sendable {

    package static let inputSize = 128
    package static let defaultThreshold: Float = 0.9

    package let assetURL: URL
    package let assetSHA256: String
    package let functionName: String
    package let batch: Int
    private let function: InferenceFunction
    private let inputName: String
    private let outputName: String

    private init(assetURL: URL, sha: String, functionName: String, function: InferenceFunction,
                 batch: Int, inputName: String, outputName: String) {
        self.assetURL = assetURL; self.assetSHA256 = sha; self.functionName = functionName
        self.function = function; self.batch = batch; self.inputName = inputName; self.outputName = outputName
    }

    /// Loads (and on first use specialises) the asset. Asynchronous and slow the first
    /// time (~1.3 s measured 2026-09-07); never inside a run.
    package static func load(
        assetURL: URL, functionName: String = "heatmap", preferNeuralEngine: Bool = true
    ) async throws -> LearnedDiskDetector {
        let sha = try sha256(ofAsset: assetURL)
        let options = preferNeuralEngine ? SpecializationOptions(preferredComputeUnitKind: .neuralEngine) : .default
        // One attempt = load + the function, in its own scope so a failed model is released
        // before any retry: the runtime hands the same stale program back while the first
        // instance is alive (test-host diagnostic, 2026-09-07). Each step is named in its
        // error — the runtime's own text is "could not be completed" with no step or code.
        func attempt(_ note: String) async throws -> InferenceFunction {
            let model: AIModel
            do { model = try await AIModel(contentsOf: assetURL, options: options) }
            catch { throw LearnedDiskDetectorError.runtime(step: "AIModel(contentsOf:) — load + specialise for \(preferNeuralEngine ? "the Neural Engine" : "the default units")\(note)", underlying: error) }
            do {
                guard let loaded = try model.loadFunction(named: functionName) else {
                    throw LearnedDiskDetectorError.missingFunction(functionName, model.functionNames)
                }
                return loaded
            } catch let e as LearnedDiskDetectorError { throw e }
            catch { throw LearnedDiskDetectorError.runtime(step: "loadFunction(\"\(functionName)\")\(note)", underlying: error) }
        }
        let fn: InferenceFunction
        do { fn = try await attempt("") }
        catch let first as LearnedDiskDetectorError {
            // A cached specialisation can go stale in a sandboxed container (an entry
            // written by the app's test host from another path, or simply older than the
            // runtime's own state) and then load instantly but refuse its function or run
            // (owner's drive + test-host diagnostic, 2026-09-07). The per-asset purge is
            // measured to work in-process and to persist; `deleteAll` did not always.
            guard case .runtime = first else { throw first }
            try? AIModelCache.default.deleteEntries(for: assetURL)
            fn = try await attempt(", after purging the runtime cache once")
        }
        let desc = fn.descriptor
        guard let inName = desc.inputNames.first, let outName = desc.outputNames.first,
              let inDesc = desc.inputDescriptor(of: inName), case .ndArray(let nd) = inDesc,
              nd.shape.count == 4, nd.shape[1] == 3, nd.shape[2] == inputSize, nd.shape[3] == inputSize else {
            throw LearnedDiskDetectorError.unexpectedSignature(desc.inputNames, desc.outputNames)
        }
        return LearnedDiskDetector(assetURL: assetURL, sha: sha, functionName: functionName, function: fn,
                                   batch: nd.shape[0], inputName: inName, outputName: outName)
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
            if let e = fm.enumerator(atPath: base) { for case let rel as String in e where !rel.hasPrefix(".") {
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

    /// `simulate.model_inputs`: (3, S, S) float16 — log1p(max(p − min p, 0)) / max,
    /// probe / max, correlation / max. Dose-invariant; keeps raw counts inside float16.
    package static func modelInputs(pattern: [Float], probe: [Float], correlation: [Float]) -> [Float16] {
        let n = inputSize * inputSize
        precondition(pattern.count == n && probe.count == n && correlation.count == n)
        var out = [Float16](repeating: 0, count: 3 * n)
        let pMin = pattern.min() ?? 0
        var logged = [Float](repeating: 0, count: n)
        for i in 0..<n { logged[i] = log1p(max(pattern[i] - pMin, 0)) }
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

    // MARK: Inference

    /// One batch through the asset: inputs (B, 3, S, S) float16 → heatmaps (B, S, S) float16.
    /// `inputs.count` must be exactly `batch * 3 * S * S`; pad short batches with zeros.
    package func heatmaps(inputs: [Float16]) async throws -> [Float16] {
        let S = Self.inputSize
        precondition(inputs.count == batch * 3 * S * S)
        // NDArray(scalars:shape:) walks the generic Sequence: 83 ms per batch of 32 measured
        // 2026-09-07 (scan-bench profile), 300x the copy it replaces. Allocate, then memcpy
        // through the mutable view (0.27 ms); read back the same way (0.02 ms).
        var x = NDArray(shape: [batch, 3, S, S], scalarType: .float16)
        do {   // the mutable view must be dead before the array is handed to the runtime
            var mutable = x.mutableView(as: Float16.self)
            mutable.withUnsafeMutablePointer { dst, _, _ in
                inputs.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: inputs.count) }
            }
        }
        var outputs = try await function.run(inputs: [inputName: x])
        guard let value = outputs.remove(outputName), let array = value.ndArray else {
            throw LearnedDiskDetectorError.noOutput(outputName)
        }
        let count = batch * S * S
        let view = array.view(as: Float16.self)
        guard view.isContiguous, view.shape.count == 4, view.shape[0] == batch, view.shape[2] == S, view.shape[3] == S else {
            throw LearnedDiskDetectorError.noOutput(outputName)
        }
        var out = [Float16](repeating: 0, count: count)
        out.withUnsafeMutableBufferPointer { dst in view.withUnsafePointer { src, _, _ in dst.baseAddress!.update(from: src, count: count) } }
        return out
    }

    /// Benchmark access to the raw function call (tools/disk-detector/scan-bench profiles the read-back).
    package func run(_ x: NDArray) async throws -> InferenceFunction.Outputs { try await function.run(inputs: [inputName: x]) }

    // MARK: One pattern (the live overlay)

    /// The learned candidates for ONE pattern, refined like the scan's: a
    /// one-position cube through `detectAll(cube:…)`, so the preview on the
    /// current CBED is exactly what the full scan would find there (owner's
    /// drive, 2026-09-07: the rings must be checkable before Detect All).
    /// Returns nil where `detectAll` would (detector < 128 px, invalid params).
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

    // MARK: Window tiling

    /// One disk diameter: `2·⌈probeRadius⌉ + 2`, never less than 24 px. The
    /// overlap between neighbouring windows, so a disk cut by one window's
    /// edge is whole — its centre inside the window's boundary, not on it —
    /// in the neighbour that overlaps it.
    package static func windowOverlap(probeRadius: Float) -> Int {
        max(2 * Int(probeRadius.rounded(.up)) + 2, 24)
    }

    /// Window origins along one detector axis of length `q` (already known
    /// ≥ `inputSize`, the caller's guard). `q <= inputSize` is one window —
    /// today's crop, centred on the probe, clamped inside the axis; a longer
    /// axis is covered by `n = ⌈(q − overlap) / (inputSize − overlap)⌉`
    /// windows whose origins spread evenly across `0 ... q − inputSize`
    /// (integer, rounded) so consecutive windows overlap by `overlap` px
    /// everywhere, not just at the ends. Owner's decision 2026-09-07, "tiling
    /// for now" (docs/v3-plan.md §3a): closes the residual that used to
    /// reduce a larger detector to one centred crop.
    package static func windowOrigins(q: Int, probeCentreOnAxis: Float, overlap: Int) -> [Int] {
        let S = inputSize
        let centred = min(max(Int(probeCentreOnAxis.rounded()) - S / 2, 0), q - S)
        guard q > S else { return [centred] }
        // overlap is clamped below inputSize so the step can never be ≤ 0 —
        // params validation keeps probeRadius (and so overlap) far under this
        // in practice, but a formula that could divide by zero on bad input
        // is a defect waiting to happen.
        let step = max(S - min(overlap, S - 1), 1)
        let n = Int((Double(q - overlap) / Double(step)).rounded(.up))
        guard n > 1 else { return [centred] }
        return (0..<n).map { i in Int((Double(i) * Double(q - S) / Double(n - 1)).rounded()) }
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

    // MARK: The scan

    /// Detect disks at every scan position of a resident float32 cube [ry][rx][qy][qx]:
    /// a detector no larger than S×S is one window about `probeCentre` (smaller detectors
    /// are not yet supported and return nil); a larger one is covered by a grid of S×S
    /// windows (`windowOrigins`) spread evenly across each axis with a probe-diameter
    /// overlap, so a disk cut by one window's edge is whole in its neighbour. The classical
    /// correlation of each window with the probe-centred flat kernel is channel three — one
    /// kernel for every window, since correlation is translation-invariant and the net's
    /// probe channel is the same crop everywhere. Batches may mix windows and positions;
    /// each window's picks are refined by the classical detector and shifted back to the
    /// full detector frame, then `mergeWindows` collapses duplicates from overlap and caps
    /// the count per position. Provenance carries the classical parameters, the learned
    /// stage's identity, and the window grid (`learned_windows`, `learned_window_overlap_px`,
    /// `learned_crop_origin_*` for the one-window case, `learned_window_origins` otherwise).
    package func detectAll(
        cube: MTLBuffer, descriptor d: DatasetDescriptor,
        probe: DiffractionPattern, probeCentre: (x: Float, y: Float), probeRadius: Float,
        kernelSource: ProbeKernelSource = .measured,
        params: DiskDetectionParams, threshold: Float = LearnedDiskDetector.defaultThreshold,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> BraggVectors? {
        let S = Self.inputSize
        guard d.qy >= S, d.qx >= S, probe.qy == d.qy, probe.qx == d.qx else { return nil }
        // the classical parameter validation, as DiskDetection.detectAll applies it (at the crop size)
        guard !params.validationIssues(in: DiskDetectionContext(qy: S, qx: S, probeRadius: probeRadius))
            .contains(where: { $0.severity == .error }) else { return nil }

        let overlap = Self.windowOverlap(probeRadius: probeRadius)
        let rowOrigins = Self.windowOrigins(q: d.qy, probeCentreOnAxis: probeCentre.y, overlap: overlap)
        let colOrigins = Self.windowOrigins(q: d.qx, probeCentreOnAxis: probeCentre.x, overlap: overlap)
        let windows: [(row0: Int, col0: Int)] = rowOrigins.flatMap { r in colOrigins.map { c in (row0: r, col0: c) } }
        let nWindows = windows.count

        // the probe crop and its flat kernel, centred on the probe: ONE for every window.
        let probeRow0 = min(max(Int(probeCentre.y.rounded()) - S / 2, 0), d.qy - S)
        let probeCol0 = min(max(Int(probeCentre.x.rounded()) - S / 2, 0), d.qx - S)
        var probeCrop = [Float](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S { probeCrop[y * S + x] = probe.pixels[(probeRow0 + y) * d.qx + probeCol0 + x] } }
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

        struct Shared: @unchecked Sendable {
            let base: UnsafePointer<Float>; let inputs: UnsafeMutablePointer<Float16>
            let smoothed: UnsafeMutablePointer<[Float]>; let detectors: [DiskDetector]
            let windows: [(row0: Int, col0: Int)]
        }
        /// Channel three and the model inputs for `count` (position, window) jobs from
        /// `start`, one CPU worker per detector (this is the classical cost); the batch
        /// buffer is zero-padded past `count`. Job `j` is position `j / nWindows`, window
        /// `j % nWindows` — position-major, so consecutive jobs share a pattern.
        func prepare(start: Int, count: Int, inputs: inout [Float16], smoothed: inout [[Float]]) {
            inputs.withUnsafeMutableBufferPointer { ib in
                smoothed.withUnsafeMutableBufferPointer { sb in
                    let shared = Shared(base: base, inputs: ib.baseAddress!, smoothed: sb.baseAddress!, detectors: detectors, windows: windows)
                    DispatchQueue.concurrentPerform(iterations: workers) { w in
                        var crop = [Float](repeating: 0, count: S * S)
                        for b in stride(from: w, to: count, by: workers) {
                            let job = start + b
                            let pos = job / nWindows
                            let win = shared.windows[job % nWindows]
                            let pat = shared.base + pos * patPix
                            for y in 0..<S { for x in 0..<S { crop[y * S + x] = pat[(win.row0 + y) * d.qx + win.col0 + x] } }
                            let corr = crop.withUnsafeBufferPointer { shared.detectors[w].correlation(pattern: $0.baseAddress!, params: params) }
                            let mi = Self.modelInputs(pattern: crop, probe: probeCrop, correlation: corr.raw)
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
                    var peaks = detectors[0].refine(candidates: cands, smoothedCorrelation: smoothed[b], params: params)
                    let job = start + b
                    let win = windows[job % nWindows]
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
        provenance["detector_class"] = "learned"
        provenance["learned_runtime"] = "coreai"
        provenance["learned_model_asset"] = assetURL.lastPathComponent
        provenance["learned_model_sha256"] = assetSHA256
        provenance["learned_model_function"] = functionName
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

@available(macOS 27, *)
package enum LearnedDiskDetectorError: Error, CustomStringConvertible, LocalizedError {
    case assetMissing(URL)
    case missingFunction(String, [String])
    case unexpectedSignature([String], [String])
    case noOutput(String)
    case runtime(step: String, underlying: Error)
    package var description: String {
        switch self {
        case .runtime(let step, let underlying):
            let ns = underlying as NSError
            return "learned detector: \(step) failed — \(ns.domain) \(ns.code): \(ns.localizedDescription)"
                + (ns.userInfo.isEmpty ? "" : " \(ns.userInfo)")
        case .assetMissing(let u): return "learned detector: no asset at \(u.path)"
        case .missingFunction(let f, let have): return "learned detector: no function '\(f)' (asset has \(have))"
        case .unexpectedSignature(let i, let o): return "learned detector: unexpected signature inputs \(i) outputs \(o)"
        case .noOutput(let n): return "learned detector: no output '\(n)'"
        }
    }
    /// What the app shows: `localizedDescription` of a plain Swift error is the
    /// generic "could not be completed", which is exactly the text that hid the
    /// runtime's failure on 2026-09-07.
    package var errorDescription: String? { description }
}
#endif
