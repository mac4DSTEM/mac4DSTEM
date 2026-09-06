// scan-bench — the 2× ceiling, measured on the same cube from Swift (docs/v3-plan.md §3a, 2026-09-07).
//
// (1) The app's classical scan path: DiskDetection.detectAll (one CPU detector per core, rows
//     strided across workers) on the dumped bullseye patterns at the 2026-09-05 settings — the
//     number the overnight run should have compared against (it used the SERIAL single-pattern
//     benchmark, 0.602 ms, and called the net 0.6× of it; the app runs 8 cores).
// (2) The exported Core AI asset through the CoreAI framework, Neural Engine preferred, batch by
//     batch on the same patterns' three-channel inputs — the first Swift-side timing (the Python
//     runtime timed everything before).
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
if args.count == 4 {
    let assetURL = URL(fileURLWithPath: args[2]); let fnName = args[3]
    let inputs = readHalf(dir.appendingPathComponent("inputs.f16")); precondition(inputs.count == n * 3 * S * S)
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
                let x = NDArray(scalars: inputs[(b * per)..<((b + B) * per)], shape: [B, 3, S, S])
                let t1 = Date()
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
let json = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: dir.appendingPathComponent("scan-bench.json")); print("wrote", dir.appendingPathComponent("scan-bench.json").path)
