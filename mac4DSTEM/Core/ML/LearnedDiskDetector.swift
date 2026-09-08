//
//  LearnedDiskDetector.swift
//  The learned disk-candidate stage (docs/v3-plan.md §3a, step 4; C7, 2026-09-08).
//
//  A candidate stage, never a measurement: the net paints a disk-centre heatmap on
//  three channels (log-normalised pattern, the probe, the classical cross-correlation),
//  peak-picking on it gives candidates, and the classical detector's own refinement
//  measures each one (`DiskDetector.refine`). Served through Core ML on the macOS 14
//  floor with the Neural Engine preferred (owner, 2026-09-07, replacing the Core AI
//  runtime the branch used). The asset is the verbatim `.mlpackage` in the bundle,
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
    /// The batch every call uses: the package's default batch dimension (32). The package
    /// accepts 1…`batchMax`, but one fixed shape means one Neural Engine specialisation,
    /// so short batches are zero-padded rather than reshaped.
    package let batch: Int
    package let batchMax: Int
    private let model: MLModel
    private let inputName = "x"
    private let outputName = "heatmap"

    private init(assetURL: URL, sha: String, model: MLModel, batch: Int, batchMax: Int) {
        self.assetURL = assetURL; self.assetSHA256 = sha; self.model = model
        self.batch = batch; self.batchMax = batchMax
    }

    /// Loads the asset: hash the package tree, compile it (Core ML writes the compiled
    /// model to a temporary location that lives as long as the process), load it with
    /// the Neural Engine preferred. Slow the first time; never inside a run.
    package static func load(assetURL: URL, preferNeuralEngine: Bool = true) async throws -> LearnedDiskDetector {
        let sha = try sha256(ofAsset: assetURL)
        let compiled: URL
        do { compiled = try await MLModel.compileModel(at: assetURL) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.compileModel(at:)", underlying: error) }
        let config = MLModelConfiguration()
        config.computeUnits = preferNeuralEngine ? .all : .cpuAndGPU
        let model: MLModel
        do { model = try await MLModel.load(contentsOf: compiled, configuration: config) }
        catch { throw LearnedDiskDetectorError.runtime(step: "MLModel.load(contentsOf:) — \(preferNeuralEngine ? "all compute units" : "CPU and GPU")", underlying: error) }
        let desc = model.modelDescription
        guard let input = desc.inputDescriptionsByName["x"], let c = input.multiArrayConstraint,
              desc.outputDescriptionsByName["heatmap"] != nil,
              c.shape.count == 4, c.shape[1].intValue == 3, c.shape[2].intValue == inputSize, c.shape[3].intValue == inputSize else {
            throw LearnedDiskDetectorError.unexpectedSignature(Array(desc.inputDescriptionsByName.keys), Array(desc.outputDescriptionsByName.keys))
        }
        let batch = c.shape[0].intValue
        var batchMax = batch
        if c.shapeConstraint.type == .range, let range = c.shapeConstraint.sizeRangeForDimension.first?.rangeValue {
            batchMax = range.location + range.length - 1
        }
        return LearnedDiskDetector(assetURL: assetURL, sha: sha, model: model, batch: batch, batchMax: batchMax)
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

    /// `simulate.model_inputs`: (3, S, S) float16 — log1p(max(p − min p, 0)) / max on the
    /// count-scaled pattern, probe / max, correlation / max. Dose-invariant; keeps raw
    /// counts inside float16.
    package static func modelInputs(pattern: [Float], probe: [Float], correlation: [Float]) -> [Float16] {
        let n = inputSize * inputSize
        precondition(pattern.count == n && probe.count == n && correlation.count == n)
        var out = [Float16](repeating: 0, count: 3 * n)
        let counts = toCounts(pattern)
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
    /// overlap by `overlap` px everywhere (owner 2026-09-07 "tiling for now";
    /// 2026-09-08: windows only above 256).
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
    /// `learned_window_origins` otherwise).
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

        // the probe's frame and its flat kernel, centred on the probe: ONE for every window.
        // Fitted like the pattern when the detector fits the frame; a centred crop clamped
        // inside the detector when windows are needed.
        let probeRow0 = d.qy > S ? min(max(Int(probeCentre.y.rounded(.toNearestOrEven)) - S / 2, 0), d.qy - S) : rowOrigins[0]
        let probeCol0 = d.qx > S ? min(max(Int(probeCentre.x.rounded(.toNearestOrEven)) - S / 2, 0), d.qx - S) : colOrigins[0]
        var probeCrop = [Float](repeating: 0, count: S * S)
        probe.pixels.withUnsafeBufferPointer { Self.window(of: $0.baseAddress!, qy: d.qy, qx: d.qx, row0: probeRow0, col0: probeCol0, into: &probeCrop) }
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
                            Self.window(of: shared.base + pos * patPix, qy: d.qy, qx: d.qx, row0: win.row0, col0: win.col0, into: &crop)
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
        provenance["detector_class"] = DetectorClass.learned.provenanceID
        provenance["learned_runtime"] = "coreml"
        provenance["learned_model_asset"] = assetURL.lastPathComponent
        provenance["learned_model_sha256"] = assetSHA256
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
    case runtime(step: String, underlying: Error)
    package var description: String {
        switch self {
        case .runtime(let step, let underlying):
            let ns = underlying as NSError
            return "learned detector: \(step) failed — \(ns.domain) \(ns.code): \(ns.localizedDescription)"
        case .assetMissing(let u): return "learned detector: no asset at \(u.path)"
        case .unexpectedSignature(let i, let o): return "learned detector: unexpected signature inputs \(i) outputs \(o)"
        case .noOutput(let n): return "learned detector: no output '\(n)'"
        }
    }
    /// What the app shows: `localizedDescription` of a plain Swift error is the
    /// generic "could not be completed", which is exactly the text that hid the
    /// runtime's failure on 2026-09-07.
    package var errorDescription: String? { description }
}
