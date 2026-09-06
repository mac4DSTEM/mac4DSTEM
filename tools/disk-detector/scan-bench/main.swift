// scan-bench — the 2× ceiling, measured on the same cube from Swift (docs/v3-plan.md §3a, 2026-09-07).
//
// (1) The app's classical scan path: DiskDetection.detectAll (one CPU detector per core, rows
//     strided across workers) on the dumped bullseye patterns at the 2026-09-05 settings — the
//     number the overnight run should have compared against (it used the SERIAL single-pattern
//     benchmark, 0.602 ms, and called the net 0.6× of it; the app runs 8 cores).
// (2) The exported Core AI asset through the CoreAI framework, and (3) LearnedDiskDetector.detectAll end to end, Neural Engine preferred, batch by
//     batch on the same patterns' three-channel inputs — the first Swift-side timing (the Python
//     runtime timed everything before). (2) needs dump.py's inputs.f16 (only written for a 128 px
//     dump) and is skipped, not fatal, on a >128 px dump — (3) calls detectAll directly, which
//     tiles a >128 px detector itself and computes its own per-window inputs, so it needs no
//     precomputed file and is the number that actually exercises tiling (2026-09-07).
// Usage: scan-bench <dump dir> [<asset.aimodel> <function>]
import Foundation
import Metal
import CoreAI

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }
func readFloats(_ url: URL) -> [Float] { let d = try! Data(contentsOf: url); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
func readHalf(_ url: URL) -> [Float16] { let d = try! Data(contentsOf: url); return d.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) } }
func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }

let args = CommandLine.arguments
guard args.count == 2 || args.count == 4 else { fail("usage: scan-bench <dump dir> [<asset.aimodel> <function>]") }
let dir = URL(fileURLWithPath: args[1])
let meta = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("meta.json"))) as! [String: Any]
let ny = meta["ny"] as! Int, nx = meta["nx"] as! Int, S = meta["size"] as! Int
let row = meta["probe_centre_row"] as! Double, col = meta["probe_centre_col"] as! Double, radius = meta["probe_radius"] as! Double
let n = ny * nx
var result: [String: Any] = ["patterns": n, "ny": ny, "nx": nx, "size": S, "cores": ProcessInfo.processInfo.activeProcessorCount]

// ---- (1) classical, the app's scan path
let cube = readFloats(dir.appendingPathComponent("cube.f32")); precondition(cube.count == n * S * S)
let probe = readFloats(dir.appendingPathComponent("probe.f32"))
let probePattern = DiffractionPattern(qy: S, qx: S, pixels: probe)
guard let kernel = ProbeKernel.flat(pattern: probePattern, originX: Float(col), originY: Float(row), radius: Float(radius)) else { fail("flat kernel failed") }
var params = DiskDetectionParams()
params.sigmaCC = 2; params.subpixel = .poly; params.minPeakSpacing = 8; params.edgeBoundary = 6; params.minRelativeIntensity = 0.05; params.maxNumPeaks = 70
let descriptor = DatasetDescriptor(filePath: "scan-bench", datasetPath: "cube.f32", shape: [ny, nx, S, S], dtypeDescription: "float32", chunkShape: nil)
guard let device = MTLCreateSystemDefaultDevice(),
      let buffer = device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride, options: .storageModeShared) else { fail("Metal buffer failed") }
var classical: [Double] = []; var peakCount = 0
for rep in 0..<4 {
    let t0 = Date()
    guard let vectors = DiskDetection.detectAll(cube: buffer, descriptor: descriptor, kernel: kernel, params: params) else { fail("detectAll returned nil") }
    let dt = Date().timeIntervalSince(t0)
    if rep > 0 { classical.append(dt) }             // rep 0 warms the FFT plans
    peakCount = vectors.peaks.reduce(0) { $0 + $1.count }
}
let cl = median(classical)
print(String(format: "classical detectAll (%d cores): %d patterns in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern)",
             ProcessInfo.processInfo.activeProcessorCount, n, cl, cl / Double(n) * 1000, cl / Double(n) * 65536, peakCount, Double(peakCount) / Double(n)))
result["classical"] = ["seconds_median": cl, "ms_per_pattern": cl / Double(n) * 1000, "s_per_65536": cl / Double(n) * 65536, "peaks": peakCount, "repeats": classical]

// ---- (2) the exported asset through CoreAI, Neural Engine preferred
// Needs inputs.f16 at the model's own S=128 — dump.py only writes it for a 128 px dump (a
// tiled, >128 px dump's per-window inputs are computed on the fly by (3)'s detectAll call,
// not precomputed here). Skipped, not fatal, when the dump is the tiled kind (2026-09-07).
let inputsURL = dir.appendingPathComponent("inputs.f16")
if args.count == 4, FileManager.default.fileExists(atPath: inputsURL.path) {
    let assetURL = URL(fileURLWithPath: args[2]); let fnName = args[3]
    let inputs = readHalf(inputsURL); precondition(inputs.count == n * 3 * S * S)
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let t0 = Date()
            let model = try await AIModel(contentsOf: assetURL, options: SpecializationOptions(preferredComputeUnitKind: .neuralEngine))
            let load = Date().timeIntervalSince(t0)
            guard let fn = try model.loadFunction(named: fnName) else { fail("no function \(fnName); have \(model.functionNames)") }
            let desc = fn.descriptor; let inName = desc.inputNames[0]
            guard let inDesc = desc.inputDescriptor(of: inName), case .ndArray(let nd) = inDesc else { fail("no ndarray input descriptor") }
            let shape = nd.shape
            let B = shape[0]; let per = 3 * S * S
            var times: [Double] = []; var heatSum: Double = 0; var outName = ""
            var b = 0
            while b + B <= n {
                let t1 = Date()   // the input construction is part of the cost (2026-09-07: NDArray(scalars:) alone was 46-83 ms per batch)
                var x = NDArray(shape: [B, 3, S, S], scalarType: .float16)
                do { var mv = x.mutableView(as: Float16.self)
                     mv.withUnsafeMutablePointer { dst, _, _ in inputs.withUnsafeBufferPointer { dst.update(from: $0.baseAddress! + b * per, count: B * per) } } }
                var out = try await fn.run(inputs: [inName: x])
                let dt = Date().timeIntervalSince(t1)
                if b > 0 { times.append(dt) }
                if outName.isEmpty { outName = Array(out.names).first ?? "" }
                if let v = out.remove(outName), let arr = v.ndArray {
                    let view = arr.view(as: Float16.self)
                    if let span = view.contiguousElements { var s: Double = 0; for i in 0..<span.count { s += Double(span[i]) }; heatSum += s }
                }
                b += B
            }
            let m = median(times)
            print(String(format: "coreai %@ [%@, neural engine preferred]: load %.2f s; batch %d: median %.2f ms -> %.4f ms/pattern, %.1f s per 65 536 (%d batches; output '%@' sum %.1f)",
                         assetURL.lastPathComponent, fnName, load, B, m * 1000, m / Double(B) * 1000, m / Double(B) * 65536, times.count, outName, heatSum))
            result["coreai"] = ["asset": assetURL.lastPathComponent, "function": fnName, "load_s": load, "batch": B, "ms_per_batch_median": m * 1000,
                                "ms_per_pattern": m / Double(B) * 1000, "s_per_65536": m / Double(B) * 65536, "batches": times.count, "output_sum": heatSum]
        } catch { fail("coreai: \(error)") }
        sem.signal()
    }
    sem.wait()
}
// ---- (3) the whole learned path end to end: LearnedDiskDetector.detectAll on the same cube (Release, -O)
if args.count == 4, #available(macOS 27, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let learned = try await LearnedDiskDetector.load(assetURL: URL(fileURLWithPath: args[2]), functionName: args[3])
            let probePattern = DiffractionPattern(qy: S, qx: S, pixels: probe)
            var times: [Double] = []; var peaks = 0
            for rep in 0..<4 {
                let t0 = Date()
                guard let v = await learned.detectAll(cube: buffer, descriptor: descriptor, probe: probePattern,
                                                      probeCentre: (x: Float(col), y: Float(row)), probeRadius: Float(radius),
                                                      params: params, threshold: 0.9) else { fail("learned detectAll returned nil") }
                let dt = Date().timeIntervalSince(t0)
                if rep > 0 { times.append(dt) }
                peaks = v.peaks.reduce(0) { $0 + $1.count }
            }
            let m = median(times)
            print(String(format: "learned detectAll end to end (threshold 0.9, %d cores + ANE): %d patterns in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern); %.2fx the classical",
                         ProcessInfo.processInfo.activeProcessorCount, n, m, m / Double(n) * 1000, m / Double(n) * 65536, peaks, Double(peaks) / Double(n), m / cl))
            result["learned_detectAll"] = ["seconds_median": m, "ms_per_pattern": m / Double(n) * 1000, "s_per_65536": m / Double(n) * 65536, "peaks": peaks,
                                           "ratio_to_classical": m / cl, "threshold": 0.9, "repeats": times]
        } catch { fail("learned detectAll: \(error)") }
        sem.signal()
    }
    sem.wait()
}
// ---- (4) stage profile of the learned path (SCAN_BENCH_PROFILE=1): where the end-to-end time goes
if args.count == 4, ProcessInfo.processInfo.environment["SCAN_BENCH_PROFILE"] == "1", #available(macOS 27, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        let learned = try! await LearnedDiskDetector.load(assetURL: URL(fileURLWithPath: args[2]), functionName: args[3])
        let det = DiskDetector(kernel: kernel)!
        let N = min(n, 512); let n3 = 3 * S * S
        var pats: [[Float]] = (0..<N).map { Array(cube[($0 * S * S)..<(($0 + 1) * S * S)]) }
        func time(_ label: String, _ body: () -> Void) { let t = Date(); body(); print(String(format: "  %@: %.4f ms/pattern", label, Date().timeIntervalSince(t) / Double(N) * 1000)) }
        var corrs: [(raw: [Float], smoothed: [Float])] = []
        time("correlation (1 thread)") { corrs = pats.map { p in p.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: params) } } }
        var mis: [[Float16]] = []
        time("modelInputs") { mis = (0..<N).map { LearnedDiskDetector.modelInputs(pattern: pats[$0], probe: probe, correlation: corrs[$0].raw) } }
        var flat = [Float16](repeating: 0, count: 32 * n3)
        time("copy inputs into the batch buffer (element loop)") { for b in 0..<N { let mi = mis[b % N]; let o = (b % 32) * n3; for i in 0..<n3 { flat[o + i] = mi[i] } } }
        var heats: [[Float16]] = []
        let t = Date(); for _ in 0..<(N / 32) { heats.append(try! await learned.heatmaps(inputs: flat)) }; print(String(format: "  heatmaps (ANE, incl. NDArray copies): %.4f ms/pattern", Date().timeIntervalSince(t) / Double(N) * 1000))
        var cands: [[DiskDetector.Candidate]] = []
        time("pickPeaks") { cands = (0..<N).map { i in heats[i / 32].withUnsafeBufferPointer { hb in LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[((i % 32) * S * S)..<((i % 32 + 1) * S * S)]), threshold: 0.9) } } }
        time("refine") { for i in 0..<N { _ = det.refine(candidates: cands[i], smoothedCorrelation: corrs[i].smoothed, params: params) } }
        // NDArray construction and output read-back variants (per batch of 32)
        func tb(_ label: String, _ body: () -> Void) { let t = Date(); for _ in 0..<8 { body() }; print(String(format: "  %@: %.3f ms/batch", label, Date().timeIntervalSince(t) / 8 * 1000)) }
        tb("NDArray(scalars: Array)") { _ = NDArray(scalars: flat, shape: [32, 3, S, S]) }
        tb("NDArray(scalars: ArraySlice)") { _ = NDArray(scalars: flat[0..<flat.count], shape: [32, 3, S, S]) }
        tb("NDArray(shape:scalarType:) + mutableView.withUnsafeMutablePointer memcpy") {
            var nd = NDArray(shape: [32, 3, S, S], scalarType: .float16)
            var mv = nd.mutableView(as: Float16.self)
            mv.withUnsafeMutablePointer { p, _, _ in flat.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: flat.count) } }
        }
        let x = NDArray(scalars: flat, shape: [32, 3, S, S])
        var outputs = try! await learned.run(x)
        let value = outputs.remove("heatmap")!; let arr = value.ndArray!
        tb("output: span element loop") { let v = arr.view(as: Float16.self); if let sp = v.contiguousElements { var o = [Float16](repeating: 0, count: sp.count); for i in 0..<sp.count { o[i] = sp[i] }; _ = o } }
        tb("output: view.withUnsafePointer memcpy") { let v = arr.view(as: Float16.self); v.withUnsafePointer { p, _, _ in var o = [Float16](repeating: 0, count: 32 * S * S); o.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: p, count: 32 * S * S) }; _ = o } }
        pats.removeAll()
        sem.signal()
    }
    sem.wait()
}
let json = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let outURL = dir.appendingPathComponent("scan-bench-\(stamp).json")
try! json.write(to: outURL); print("wrote", outURL.path)
