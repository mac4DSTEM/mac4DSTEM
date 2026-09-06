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
        let model = try await AIModel(contentsOf: assetURL, options: options)
        guard let fn = try model.loadFunction(named: functionName) else {
            throw LearnedDiskDetectorError.missingFunction(functionName, model.functionNames)
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

    // MARK: The scan

    /// Detect disks at every scan position of a resident float32 cube [ry][rx][qy][qx]:
    /// each pattern is cropped to S×S about `probeCentre` (larger detectors; smaller ones
    /// are not yet supported and return nil), the classical correlation of the crop with the
    /// cropped probe's flat kernel is channel three, batches go to the Neural Engine, the
    /// picked candidates are refined by the classical detector and shifted back to the
    /// full detector frame. Provenance carries the classical parameters plus the learned
    /// stage's identity. Residual (2026-09-07): a detector larger than S is reduced to the
    /// S×S window about the probe centre — disks outside it are never proposed; the
    /// provenance says so (`learned_input_px`, `learned_crop_origin_*`).
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
        let row0 = min(max(Int(probeCentre.y.rounded()) - S / 2, 0), d.qy - S)
        let col0 = min(max(Int(probeCentre.x.rounded()) - S / 2, 0), d.qx - S)
        var probeCrop = [Float](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S { probeCrop[y * S + x] = probe.pixels[(row0 + y) * d.qx + col0 + x] } }
        guard let kernel = ProbeKernel.flat(
            pattern: DiffractionPattern(qy: S, qx: S, pixels: probeCrop),
            originX: probeCentre.x - Float(col0), originY: probeCentre.y - Float(row0),
            radius: probeRadius, source: kernelSource
        ) else { return nil }
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, batch))
        var detectors: [DiskDetector] = []
        for _ in 0..<workers { guard let det = DiskDetector(kernel: kernel) else { return nil }; detectors.append(det) }

        let positions = d.ry * d.rx
        let patPix = d.qy * d.qx
        let base = cube.contents().bindMemory(to: Float.self, capacity: positions * patPix)
        var results = [[BraggPeak]](repeating: [], count: positions)
        let n3 = 3 * S * S
        var lastBucket = -1

        struct Shared: @unchecked Sendable {
            let base: UnsafePointer<Float>; let inputs: UnsafeMutablePointer<Float16>
            let smoothed: UnsafeMutablePointer<[Float]>; let detectors: [DiskDetector]
        }
        /// Channel three and the model inputs for `count` patterns from `start`, one CPU worker per
        /// detector (this is the classical cost); the batch buffer is zero-padded past `count`.
        func prepare(start: Int, count: Int, inputs: inout [Float16], smoothed: inout [[Float]]) {
            inputs.withUnsafeMutableBufferPointer { ib in
                smoothed.withUnsafeMutableBufferPointer { sb in
                    let shared = Shared(base: base, inputs: ib.baseAddress!, smoothed: sb.baseAddress!, detectors: detectors)
                    DispatchQueue.concurrentPerform(iterations: workers) { w in
                        var crop = [Float](repeating: 0, count: S * S)
                        for b in stride(from: w, to: count, by: workers) {
                            let pat = shared.base + (start + b) * patPix
                            for y in 0..<S { for x in 0..<S { crop[y * S + x] = pat[(row0 + y) * d.qx + col0 + x] } }
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
                    for i in peaks.indices { peaks[i].x += Float(col0); peaks[i].y += Float(row0) }
                    results[start + b] = peaks
                }
            }
        }

        // Two batch buffers: while the Neural Engine runs batch k, the CPU prepares batch k+1
        // (§3a "compute streams"; serial was 2.3-2.6x the classical wall clock on 2026-09-07).
        var bufA = [Float16](repeating: 0, count: batch * n3), bufB = [Float16](repeating: 0, count: batch * n3)
        var smA = [[Float]](repeating: [], count: batch), smB = [[Float]](repeating: [], count: batch)
        var start = 0
        var count = min(batch, positions)
        prepare(start: 0, count: count, inputs: &bufA, smoothed: &smA)
        while start < positions {
            if cancellation?.isCancelled == true { return nil }
            let inputsNow = bufA
            async let heat = heatmaps(inputs: inputsNow)
            let next = start + count
            let nextCount = min(batch, positions - next)
            if nextCount > 0 { prepare(start: next, count: nextCount, inputs: &bufB, smoothed: &smB) }
            guard let h = try? await heat else { return nil }
            finish(start: start, count: count, heat: h, smoothed: smA)
            swap(&bufA, &bufB); swap(&smA, &smB)
            start = next; count = nextCount
            if let progress {
                let bucket = start * 1000 / positions
                if bucket != lastBucket { lastBucket = bucket; progress(Double(start) / Double(positions)) }
            }
        }
        var provenance = params.provenance(kernel: kernel, qy: d.qy, qx: d.qx)
        provenance["detector_class"] = "learned"
        provenance["learned_runtime"] = "coreai"
        provenance["learned_model_asset"] = assetURL.lastPathComponent
        provenance["learned_model_sha256"] = assetSHA256
        provenance["learned_model_function"] = functionName
        provenance["learned_threshold"] = String(threshold)
        provenance["learned_input_px"] = String(S)
        provenance["learned_crop_origin_x"] = String(col0)
        provenance["learned_crop_origin_y"] = String(row0)
        return BraggVectors(scanWidth: d.rx, scanHeight: d.ry, peaks: results, detectionProvenance: provenance)
    }
}

@available(macOS 27, *)
package enum LearnedDiskDetectorError: Error, CustomStringConvertible {
    case assetMissing(URL)
    case missingFunction(String, [String])
    case unexpectedSignature([String], [String])
    case noOutput(String)
    package var description: String {
        switch self {
        case .assetMissing(let u): return "learned detector: no asset at \(u.path)"
        case .missingFunction(let f, let have): return "learned detector: no function '\(f)' (asset has \(have))"
        case .unexpectedSignature(let i, let o): return "learned detector: unexpected signature inputs \(i) outputs \(o)"
        case .noOutput(let n): return "learned detector: no output '\(n)'"
        }
    }
}
#endif
