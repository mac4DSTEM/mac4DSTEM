// scan-bench — the ceiling of docs/v3-plan.md §3a, measured on the same cube from Swift, on Core ML
// (C7 session 3, 2026-09-08; the Core AI version stays on `ml/disk-detector`).
//
// (1) The app's classical scan path: DiskDetection.detectAll (one CPU detector per core) on the dumped
//     bullseye patterns at the 2026-09-05 settings.
// (2) LearnedDiskDetector.detectAll end to end on the same patterns — the shipped 256-px package with
//     the Neural Engine preferred, batch 32 as the app sends it — at the shipped default threshold
//     (0.7) and at 0.9, the threshold the 2026-09-07 Core AI numbers were taken at, so the two runtimes
//     compare like for like. A 250-px cube is ONE frame at 256 (padded), no tiling.
// Usage: scan-bench <dump dir> <asset.mlpackage>
import Foundation
import Metal

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }
func readFloats(_ url: URL) -> [Float] { let d = try! Data(contentsOf: url); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: scan-bench <dump dir> <asset.mlpackage>") }
let dir = URL(fileURLWithPath: args[1]); let assetURL = URL(fileURLWithPath: args[2])
let meta = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("meta.json"))) as! [String: Any]
let ny = meta["ny"] as! Int, nx = meta["nx"] as! Int, S = meta["size"] as! Int
let row = meta["probe_centre_row"] as! Double, col = meta["probe_centre_col"] as! Double, radius = meta["probe_radius"] as! Double
let n = ny * nx
let cores = ProcessInfo.processInfo.activeProcessorCount
var result: [String: Any] = ["patterns": n, "ny": ny, "nx": nx, "size": S, "cores": cores, "model_frame": LearnedDiskDetector.inputSize]

let cube = readFloats(dir.appendingPathComponent("cube.f32")); precondition(cube.count == n * S * S)
let probe = readFloats(dir.appendingPathComponent("probe.f32")); precondition(probe.count == S * S)
let probePattern = DiffractionPattern(qy: S, qx: S, pixels: probe)
guard let kernel = ProbeKernel.flat(pattern: probePattern, originX: Float(col), originY: Float(row), radius: Float(radius)) else { fail("flat kernel failed") }
var params = DiskDetectionParams()
params.sigmaCC = 2; params.subpixel = .poly; params.minPeakSpacing = 8; params.edgeBoundary = 6; params.minRelativeIntensity = 0.05; params.maxNumPeaks = 70
let descriptor = DatasetDescriptor(filePath: "scan-bench", datasetPath: "cube.f32", shape: [ny, nx, S, S], dtypeDescription: "float32", chunkShape: nil)
guard let device = MTLCreateSystemDefaultDevice(),
      let buffer = device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride, options: .storageModeShared) else { fail("Metal buffer failed") }

// ---- (1) classical, the app's scan path: 4 repeats, the first warms the FFT plans, median of the other 3
var classical: [Double] = []; var classicalPeaks = 0
for rep in 0..<4 {
    let t0 = Date()
    guard let vectors = DiskDetection.detectAll(cube: buffer, descriptor: descriptor, kernel: kernel, params: params) else { fail("detectAll returned nil") }
    let dt = Date().timeIntervalSince(t0)
    if rep > 0 { classical.append(dt) }
    classicalPeaks = vectors.peaks.reduce(0) { $0 + $1.count }
}
let cl = median(classical)
print(String(format: "classical detectAll (%d cores): %d patterns of %d px in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern)",
             cores, n, S, cl, cl / Double(n) * 1000, cl / Double(n) * 65536, classicalPeaks, Double(classicalPeaks) / Double(n)))
result["classical"] = ["seconds_median": cl, "ms_per_pattern": cl / Double(n) * 1000, "s_per_65536": cl / Double(n) * 65536, "peaks": classicalPeaks, "repeats": classical]

// ---- (2) the learned path end to end on Core ML, the same buffer, at the shipped default and at 0.9
let tLoad = Date()
let learned: LearnedDiskDetector
do { learned = try await LearnedDiskDetector.load(assetURL: assetURL) } catch { fail("load \(assetURL.path): \(error)") }
let load = Date().timeIntervalSince(tLoad)
print(String(format: "learned asset %@ sha %@ loaded in %.2f s (batch %d, frame %d px)", assetURL.lastPathComponent, String(learned.assetSHA256.prefix(8)), load, learned.batch, LearnedDiskDetector.inputSize))
result["asset"] = ["name": assetURL.lastPathComponent, "sha256": learned.assetSHA256, "load_s": load, "batch": learned.batch]
var learnedRows: [[String: Any]] = []
for threshold in [LearnedDiskDetector.defaultThreshold, Float(0.9)] {
    var times: [Double] = []; var peaks = 0
    for rep in 0..<4 {
        let t0 = Date()
        guard let v = await learned.detectAll(cube: buffer, descriptor: descriptor, probe: probePattern,
                                              probeCentre: (x: Float(col), y: Float(row)), probeRadius: Float(radius),
                                              params: params, threshold: threshold) else { fail("learned detectAll returned nil") }
        let dt = Date().timeIntervalSince(t0)
        if rep > 0 { times.append(dt) }
        peaks = v.peaks.reduce(0) { $0 + $1.count }
        if rep == 0 { result["learned_provenance_frame"] = ["windows": v.detectionProvenance["learned_windows"] ?? "", "crop_origin_y": v.detectionProvenance["learned_crop_origin_y"] ?? "", "crop_origin_x": v.detectionProvenance["learned_crop_origin_x"] ?? ""] }
    }
    let m = median(times)
    print(String(format: "learned detectAll end to end (threshold %.2f, %d cores + Core ML): %d patterns in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern); %.2fx the classical",
                 threshold, cores, n, m, m / Double(n) * 1000, m / Double(n) * 65536, peaks, Double(peaks) / Double(n), m / cl))
    learnedRows.append(["threshold": Double(threshold), "seconds_median": m, "ms_per_pattern": m / Double(n) * 1000, "s_per_65536": m / Double(n) * 65536,
                        "peaks": peaks, "ratio_to_classical": m / cl, "repeats": times])
}
result["learned_detectAll"] = learnedRows

let json = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let outURL = dir.appendingPathComponent("scan-bench-\(stamp).json")
try! json.write(to: outURL); print("wrote", outURL.path)
