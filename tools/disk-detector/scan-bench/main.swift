// scan-bench — the ceiling of docs/archive/v3/learned-detector-preregistration-2026-09-07.md (was docs/v3-plan.md §3a), measured on the same cube from Swift, on Core ML
// (C7 session 3, 2026-09-08; the Core AI version stays on `ml/disk-detector`).
//
// (1) The app's classical scan path: DiskDetection.detectAll (one CPU detector per core) on the dumped
//     bullseye patterns at the 2026-09-05 settings.
// (2) LearnedDiskDetector.detectAll end to end on the same patterns — the shipped 256-px package on the chosen
//     compute units (default the Neural Engine), batch 32 as the app sends it — at the shipped default threshold
//     (0.7) and at 0.9, the threshold the 2026-09-07 Core AI numbers were taken at, so the two runtimes
//     compare like for like. A 250-px cube is ONE frame at 256 (padded), no tiling.
// Usage: scan-bench <dump dir> <asset.mlpackage> [--units ane|all|gpu|cpu] [--peaks <file.json>]
//   --units  the compute units the learned model is loaded on (default ane = .cpuAndNeuralEngine, the detector's default;
//            all = .all, gpu = .cpuAndGPU, cpu = .cpuOnly).
//   --peaks  write every position's accepted peaks [x, y, intensity], per threshold run and for the classical path
//            ({"units", "thresholds": [{"threshold", "positions"}], "classical": [...]}), for compare_peaks.py.
// Also runs an executed-unit check (2026-09-30): the same deterministic batch-32 input through this load and through a
// .cpuOnly load of the same compiled model, and the MLComputePlan preferred-device op counts under the chosen units.
// The dump's detector may be non-square (meta.json `qy`, `qx`; old dumps carry `size`).
import Foundation
import Metal
import CoreML

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }
func readFloats(_ url: URL) -> [Float] { let d = try! Data(contentsOf: url); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }

let usage = "usage: scan-bench <dump dir> <asset.mlpackage> [--units ane|all|gpu|cpu] [--peaks <file.json>]"
let args = CommandLine.arguments
guard args.count >= 3 else { fail(usage) }
let dir = URL(fileURLWithPath: args[1]); let assetURL = URL(fileURLWithPath: args[2])
var unitsName = "ane"; var peaksURL: URL? = nil
var argi = 3
while argi < args.count {
    switch args[argi] {
    case "--units": guard argi + 1 < args.count else { fail(usage) }; unitsName = args[argi + 1]; argi += 2
    case "--peaks": guard argi + 1 < args.count else { fail(usage) }; peaksURL = URL(fileURLWithPath: args[argi + 1]); argi += 2
    default: fail(usage)
    }
}
let computeUnits: MLComputeUnits
switch unitsName {
case "ane": computeUnits = .cpuAndNeuralEngine
case "all": computeUnits = .all
case "gpu": computeUnits = .cpuAndGPU
case "cpu": computeUnits = .cpuOnly
default: fail("unknown --units \(unitsName) (ane|all|gpu|cpu)")
}
let meta = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("meta.json"))) as! [String: Any]
let ny = meta["ny"] as! Int, nx = meta["nx"] as! Int
let QY = (meta["qy"] as? Int) ?? (meta["size"] as! Int), QX = (meta["qx"] as? Int) ?? (meta["size"] as! Int)
let row = meta["probe_centre_row"] as! Double, col = meta["probe_centre_col"] as! Double, radius = meta["probe_radius"] as! Double
let n = ny * nx
let cores = ProcessInfo.processInfo.activeProcessorCount
var result: [String: Any] = ["patterns": n, "ny": ny, "nx": nx, "qy": QY, "qx": QX, "cores": cores, "model_frame": LearnedDiskDetector.inputSize, "units": unitsName]
if QY == QX { result["size"] = QY }
func peakRows(_ v: BraggVectors) -> [[[Double]]] { v.peaks.map { $0.map { [Double($0.x), Double($0.y), Double($0.intensity)] } } }
var classicalRows: [[[Double]]] = []; var thresholdRows: [[String: Any]] = []

let cube = readFloats(dir.appendingPathComponent("cube.f32")); precondition(cube.count == n * QY * QX)
let probe = readFloats(dir.appendingPathComponent("probe.f32")); precondition(probe.count == QY * QX)
let probePattern = DiffractionPattern(qy: QY, qx: QX, pixels: probe)
guard let kernel = ProbeKernel.flat(pattern: probePattern, originX: Float(col), originY: Float(row), radius: Float(radius)) else { fail("flat kernel failed") }
var params = DiskDetectionParams()
params.sigmaCC = 2; params.subpixel = .poly; params.minPeakSpacing = 8; params.edgeBoundary = 6; params.minRelativeIntensity = 0.05; params.maxNumPeaks = 70
let descriptor = DatasetDescriptor(filePath: "scan-bench", datasetPath: "cube.f32", shape: [ny, nx, QY, QX], dtypeDescription: "float32", chunkShape: nil)
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
    if rep == 3 && peaksURL != nil { classicalRows = peakRows(vectors) }
}
let cl = median(classical)
print(String(format: "classical detectAll (%d cores): %d patterns of %dx%d px in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern)",
             cores, n, QY, QX, cl, cl / Double(n) * 1000, cl / Double(n) * 65536, classicalPeaks, Double(classicalPeaks) / Double(n)))
result["classical"] = ["seconds_median": cl, "ms_per_pattern": cl / Double(n) * 1000, "s_per_65536": cl / Double(n) * 65536, "peaks": classicalPeaks, "repeats": classical]

// ---- (2) the learned path end to end on Core ML (units: \(unitsName)), the same buffer, at the shipped default and at 0.9
let tLoad = Date()
let learned: LearnedDiskDetector
do { learned = try await LearnedDiskDetector.loadForComparison(assetURL: assetURL, computeUnits: computeUnits) } catch { fail("load \(assetURL.path): \(error)") }
let load = Date().timeIntervalSince(tLoad)
print(String(format: "learned asset %@ sha %@ loaded in %.2f s on units %@ (batch %d, frame %d px)", assetURL.lastPathComponent, String(learned.assetSHA256.prefix(8)), load, unitsName, learned.batch, LearnedDiskDetector.inputSize))
result["asset"] = ["name": assetURL.lastPathComponent, "sha256": learned.assetSHA256, "load_s": load, "batch": learned.batch]
// ---- executed-unit check: MLComputePlan preferred devices under the chosen units, and the heatmaps of this load
// against a .cpuOnly load of the same compiled model on the same deterministic batch-32 input.
var planCounts: [String: Int] = ["ane": 0, "gpu": 0, "cpu": 0, "none": 0]; var planTotal = 0
do {
    let cfg = MLModelConfiguration(); cfg.computeUnits = computeUnits
    let plan = try await MLComputePlan.load(contentsOf: learned.compiledURL, configuration: cfg)
    if case .program(let prog) = plan.modelStructure, let main = prog.functions["main"] {
        for op in main.block.operations {
            guard let u = plan.deviceUsage(for: op) else { planCounts["none", default: 0] += 1; continue }   // const-like ops carry no device; not counted in the total
            planTotal += 1
            switch u.preferred { case .cpu: planCounts["cpu", default: 0] += 1; case .gpu: planCounts["gpu", default: 0] += 1
                                 case .neuralEngine: planCounts["ane", default: 0] += 1; @unknown default: planCounts["none", default: 0] += 1 }
        }
    }
} catch { print("MLComputePlan failed: \(error)") }
let cpuRef: LearnedDiskDetector
do { cpuRef = try await LearnedDiskDetector.loadForComparison(assetURL: assetURL, compiledURL: learned.compiledURL, computeUnits: .cpuOnly) } catch { fail("cpuOnly reference load: \(error)") }
let frameS = LearnedDiskDetector.inputSize
let probeInput = (0 ..< learned.batch * 3 * frameS * frameS).map { Float16(abs(sin(Double($0) * 0.0137))) }
let hChosen: [Float16], hCPU: [Float16]
do { hChosen = try await learned.heatmaps(inputs: probeInput); hCPU = try await cpuRef.heatmaps(inputs: probeInput) } catch { fail("executed-unit heatmaps: \(error)") }
var differing = 0, maxAbs: Float = 0
for i in 0 ..< hChosen.count where hChosen[i] != hCPU[i] { differing += 1; maxAbs = max(maxAbs, abs(Float(hChosen[i]) - Float(hCPU[i]))) }
let differFraction = Double(differing) / Double(hChosen.count)
let planDominant = ["ane", "gpu", "cpu"].max(by: { planCounts[$0]! < planCounts[$1]! })!
print(String(format: "executed-unit check: units %@, plan %@ %d/%d (ane %d, gpu %d, cpu %d), heatmaps differ from cpuOnly at %.1f %% of pixels (max |diff| %.4g)",
             unitsName, planDominant, planCounts[planDominant]!, planTotal, planCounts["ane"]!, planCounts["gpu"]!, planCounts["cpu"]!, differFraction * 100, maxAbs))
result["executed_unit_check"] = ["units": unitsName, "plan_total_ops": planTotal, "plan_ops_without_device": planCounts["none"]!, "plan_preferred_ane": planCounts["ane"]!, "plan_preferred_gpu": planCounts["gpu"]!,
                                 "plan_preferred_cpu": planCounts["cpu"]!, "differs_from_cpu_only": differing > 0,
                                 "differing_fraction": differFraction, "max_abs_diff": Double(maxAbs), "values": hChosen.count,
                                 "input": "Float16 abs(sin(i*0.0137)), batch \(learned.batch)"]
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
        if rep == 3 && peaksURL != nil { thresholdRows.append(["threshold": (Double(threshold) * 1e4).rounded() / 1e4, "positions": peakRows(v)]) }
        if rep == 0 { result["learned_provenance_frame"] = ["windows": v.detectionProvenance["learned_windows"] ?? "", "crop_origin_y": v.detectionProvenance["learned_crop_origin_y"] ?? "", "crop_origin_x": v.detectionProvenance["learned_crop_origin_x"] ?? ""] }
    }
    let m = median(times)
    print(String(format: "learned detectAll end to end (threshold %.2f, %d cores + Core ML %@): %d patterns in %.3f s median of 3 -> %.4f ms/pattern, %.1f s per 65 536; %d peaks (%.2f per pattern); %.2fx the classical",
                 threshold, cores, unitsName, n, m, m / Double(n) * 1000, m / Double(n) * 65536, peaks, Double(peaks) / Double(n), m / cl))
    learnedRows.append(["threshold": Double(threshold), "seconds_median": m, "ms_per_pattern": m / Double(n) * 1000, "s_per_65536": m / Double(n) * 65536,
                        "peaks": peaks, "ratio_to_classical": m / cl, "repeats": times])
}
result["learned_detectAll"] = learnedRows
if let peaksURL {
    let pj = try! JSONSerialization.data(withJSONObject: ["units": unitsName, "thresholds": thresholdRows, "classical": classicalRows] as [String: Any], options: [.sortedKeys])
    try! pj.write(to: peaksURL); print("wrote", peaksURL.path)
}

let json = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let outURL = dir.appendingPathComponent("scan-bench-\(stamp).json")
try! json.write(to: outURL); print("wrote", outURL.path)
