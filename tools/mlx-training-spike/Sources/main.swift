// mlx-spike — ROADMAP C2, the four pass criteria of archive/v4/ondevice-training-research-2026-09-28.md:
//   1. MLX forward of the shipped weights vs the shipped Core ML heatmap on the fixture: max |Δ| ≤ 1e-2
//   2. the weighted-MSE loss falls over 500 steps at batch 8; phys_footprint ≤ 2 GB; s/step logged
//   3. the fine-tuned weights injected via MLModelAsset(specification:blobMapping:) match MLX to ≤ 1e-2,
//      MLComputePlan prefers the Neural Engine for all 15 convs, latency within 20 % of the shipped package
//   4. NOT exercised here: the app's Swift learned path on the fixture. The heatmaps written below were
//      scored through evaluate.py's Python picking by hand (record), which is not the registered test.
// Usage: mlx-spike <package.mlpackage> <data dir> <out dir> [steps]
// The data dir holds data.json + raw float32 NCHW arrays exported once from tools/disk-detector.

import CoreML
import Foundation
import MLX
import MLXNN
import MLXOptimizers

// MARK: - The shipped graph (BN folded), mirrored in NHWC

/// Conv order is the ML Program's own: the i-th conv here reads the i-th weight/bias blob below.
final class UNet: Module, UnaryLayer {
    @ModuleInfo var convs: [Conv2d]
    let pool = MaxPool2d(kernelSize: 2, stride: 2)
    let up = Upsample(scaleFactor: 2.0, mode: .nearest)

    static let channels: [(Int, Int)] = [
        (3, 12), (12, 12), (12, 24), (24, 24), (24, 48), (48, 48), (48, 96), (96, 96),
        (144, 48), (48, 48), (72, 24), (24, 24), (36, 12), (12, 12),
    ]

    override init() {
        var c = Self.channels.map { Conv2d(inputChannels: $0.0, outputChannels: $0.1, kernelSize: 3, padding: 1) }
        c.append(Conv2d(inputChannels: 12, outputChannels: 1, kernelSize: 1))
        _convs.wrappedValue = c
        super.init()
    }

    private func block(_ x: MLXArray, _ i: Int) -> MLXArray {
        silu(convs[i + 1](silu(convs[i](x))))
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let e1 = block(x, 0)
        let e2 = block(pool(e1), 2)
        let e3 = block(pool(e2), 4)
        let b = block(pool(e3), 6)
        // MIL concat order: [upsampled, skip] on the channel axis
        let d3 = block(concatenated([up(b), e3], axis: -1), 8)
        let d2 = block(concatenated([up(d3), e2], axis: -1), 10)
        let d1 = block(concatenated([up(d2), e1], axis: -1), 12)
        return sigmoid(convs[14](d1))
    }
}

// MARK: - MIL blob file (coremltools MILBlob StorageFormat: 64-B header, 64-B metadata per blob)

/// Metadata offsets of the 15 conv weights and 14 biases, in conv order (dumped from model.mlmodel,
/// 2026-09-28). The head's bias is an inline immediate in the spec (fp16 0xB413), not a blob.
let weightMeta = [64, 960, 3776, 9152, 19712, 40704, 82432, 165696, 331904, 456576, 498304, 529600, 540160, 548160, 550976]
let biasMeta: [Int?] = [832, 3648, 9024, 19584, 40512, 82240, 165440, 331648, 456384, 498112, 529472, 540032, 548032, 550848, nil]
let headBias = Float(Float16(bitPattern: 0xB413))

struct BlobRef { let dataOffset: Int; let count: Int }

func blob(_ bin: Data, meta: Int) throws -> BlobRef {
    func u32(_ o: Int) -> UInt32 { bin.subdata(in: o ..< o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    func u64(_ o: Int) -> UInt64 { bin.subdata(in: o ..< o + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } }
    guard u32(meta) == 0xDEAD_BEEF else { throw Failure("no blob sentinel at \(meta)") }
    let size = Int(u64(meta + 8)), offset = Int(u64(meta + 16))
    return BlobRef(dataOffset: offset, count: size / 2)
}

func readFP16(_ bin: Data, _ ref: BlobRef) -> [Float] {
    bin.subdata(in: ref.dataOffset ..< ref.dataOffset + ref.count * 2).withUnsafeBytes {
        $0.bindMemory(to: Float16.self).map(Float.init)
    }
}

func writeFP16(_ bin: inout Data, _ ref: BlobRef, _ values: [Float]) throws {
    guard values.count == ref.count else { throw Failure("blob size \(ref.count) vs \(values.count)") }
    let halves = values.map(Float16.init)
    halves.withUnsafeBytes { bin.replaceSubrange(ref.dataOffset ..< ref.dataOffset + ref.count * 2, with: $0) }
}

/// MIL weights are OIHW; MLX's Conv2d weight is OHWI.
func loadWeights(_ model: UNet, from bin: Data) throws {
    var flat: [(String, MLXArray)] = []
    for (i, conv) in model.convs.enumerated() {
        let s = conv.weight.shape  // O, H, W, I
        let w = MLXArray(readFP16(bin, try blob(bin, meta: weightMeta[i])), [s[0], s[3], s[1], s[2]])
        flat.append(("convs.\(i).weight", w.transposed(0, 2, 3, 1)))
        let b = biasMeta[i].map { MLXArray(readFP16(bin, try! blob(bin, meta: $0)), [s[0]]) } ?? MLXArray([headBias], [1])
        flat.append(("convs.\(i).bias", b))
    }
    model.update(parameters: ModuleParameters.unflattened(flat))
}

func patchedWeights(_ model: UNet, into original: Data) throws -> Data {
    var bin = original
    for (i, conv) in model.convs.enumerated() {
        let w = conv.weight.transposed(0, 3, 1, 2).asType(.float32)  // OHWI -> OIHW
        try writeFP16(&bin, try blob(bin, meta: weightMeta[i]), w.asArray(Float.self))
        if let m = biasMeta[i] { try writeFP16(&bin, try blob(bin, meta: m), conv.bias!.asArray(Float.self)) }
    }
    return bin
}

// MARK: - Data and Core ML plumbing

struct Failure: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }

func loadF32(_ dir: URL, _ name: String, _ shape: [Int]) throws -> MLXArray {
    let d = try Data(contentsOf: dir.appendingPathComponent("\(name).f32"))
    let v = d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return MLXArray(v, shape).transposed(0, 2, 3, 1)  // NCHW -> NHWC
}

func coreMLHeatmap(_ model: MLModel, _ xNHWC: MLXArray) throws -> MLXArray {
    let n = xNHWC.dim(0)
    let x = xNHWC.transposed(0, 3, 1, 2).asType(.float32).asArray(Float.self)
    let arr = try MLMultiArray(shape: [n, 3, 256, 256].map { NSNumber(value: $0) }, dataType: .float16)
    arr.withUnsafeMutableBufferPointer(ofType: Float16.self) { p, _ in for i in 0 ..< x.count { p[i] = Float16(x[i]) } }
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": arr]))
    let h = MLShapedArray<Float16>(out.featureValue(for: "heatmap")!.multiArrayValue!)
    return MLXArray(h.scalars.map(Float.init), [n, 256, 256])
}

func physFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

/// The process's lifetime maximum phys_footprint (the kernel's own high-water mark), not a sample.
func lifetimeMaxFootprintMB() -> Double {
    var info = rusage_info_v4()
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return kr == 0 ? Double(info.ri_lifetime_max_phys_footprint) / 1_048_576 : .nan
}

func maxAbs(_ a: MLXArray, _ b: MLXArray) -> Float { abs(a - b).max().item(Float.self) }

func inputArray(_ xNHWC: MLXArray) throws -> MLDictionaryFeatureProvider {
    let n = xNHWC.dim(0)
    let x = xNHWC.transposed(0, 3, 1, 2).asType(.float32).asArray(Float.self)
    let arr = try MLMultiArray(shape: [n, 3, 256, 256].map { NSNumber(value: $0) }, dataType: .float16)
    arr.withUnsafeMutableBufferPointer(ofType: Float16.self) { p, _ in for i in 0 ..< x.count { p[i] = Float16(x[i]) } }
    return try MLDictionaryFeatureProvider(dictionary: ["x": arr])
}

let unitNames: [(String, MLComputeUnits)] = [("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all), ("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly)]
func config(_ u: MLComputeUnits) -> MLModelConfiguration { let c = MLModelConfiguration(); c.computeUnits = u; return c }

// MARK: - The run

func run() async throws {
    let args = CommandLine.arguments
    guard args.count >= 4 else { throw Failure("usage: mlx-spike <package.mlpackage> <data dir> <out dir> [steps]") }
    let pkg = URL(fileURLWithPath: args[1]), dataDir = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
    let steps = args.count > 4 ? Int(args[4])! : 500
    let env = ProcessInfo.processInfo.environment
    let lr = Float(env["SPIKE_LR"] ?? "1e-4")!, valChunk = Int(env["SPIKE_VAL_CHUNK"] ?? "32")!
    if let mb = env["SPIKE_CACHE_MB"].flatMap(Int.init) { Memory.cacheLimit = mb * 1_048_576 }
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var report: [String: Any] = ["mlx_swift": "0.31.6", "steps": steps, "lr": lr, "val_chunk": valChunk,
                                 "cache_limit_mb": env["SPIKE_CACHE_MB"] ?? "default"]
    func log(_ s: String) { print(s); fflush(stdout) }

    let specURL = pkg.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel")
    let binURL = pkg.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
    let spec = try Data(contentsOf: specURL), bin = try Data(contentsOf: binURL)
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dataDir.appendingPathComponent("data.json"))) as! [String: [Int]]
    let fixture = try loadF32(dataDir, "fixture_x", meta["fixture_x"]!)

    // ---- criterion 1: the mirror reproduces the shipped package
    let model = UNet()
    try loadWeights(model, from: bin)
    let mlxH0 = model(fixture).squeezed(axis: -1); eval(mlxH0)
    let compiled = try await MLModel.compileModel(at: pkg)
    // the app's batch: 32 = the 16 fixture patterns twice (run 3; runs 1-2 compared at batch 16)
    let batch = fixture[MLXArray((0 ..< 32).map { Int32($0 % 16) })]; eval(batch)
    let mlxB0 = model(batch).squeezed(axis: -1); eval(mlxB0)
    var c1: [String: Float] = [:]
    for (name, units) in unitNames {
        c1[name] = maxAbs(mlxB0, try coreMLHeatmap(try MLModel(contentsOf: compiled, configuration: config(units)), batch))
    }
    let pass1 = c1["cpuAndNeuralEngine"]! <= 1e-2
    report["criterion1_batch32_max_abs_diff"] = c1; report["criterion1_pass_on_ane"] = pass1
    log("criterion 1 (batch 32): MLX vs shipped Core ML max |Δ| \(c1) -> ANE \(pass1 ? "PASS" : "FAIL")")
    guard c1["cpuAndGPU"]! <= 1e-2 else { throw Failure("the mirror is wrong on the GPU path too; fix it before any training") }

    // ---- criterion 2: fine-tune, batch 8, weighted MSE (1 + 20 t)(p − t)²
    let tx = try loadF32(dataDir, "train_x", meta["train_x"]!), ty = try loadF32(dataDir, "train_y", meta["train_y"]!)
    let vx = try loadF32(dataDir, "val_x", meta["val_x"]!), vy = try loadF32(dataDir, "val_y", meta["val_y"]!)
    func lossFn(_ m: UNet, _ x: MLXArray, _ t: MLXArray) -> MLXArray { mean((1 + 20 * t) * square(m(x) - t)) }
    func heldOut(_ m: UNet) -> Float {  // mean over equal chunks == the mean over all 32
        let n = vx.dim(0); var total: Float = 0
        for s in stride(from: 0, to: n, by: valChunk) {
            let e = min(s + valChunk, n); total += lossFn(m, vx[s ..< e], vy[s ..< e]).item(Float.self) * Float(e - s)
        }
        return total / Float(n)
    }
    model.convs[14].freeze(recursive: false, keys: ["bias"])  // the head bias is inline in the spec, not a blob
    let lg = valueAndGrad(model: model, lossFn)
    let opt = AdamW(learningRate: lr, weightDecay: 1e-4)
    MLXRandom.seed(20_260_928)
    var gen = SplitMix(seed: 20_260_928)
    let val0 = heldOut(model)
    var curve: [[String: Double]] = []
    var peak = physFootprintMB()
    log(String(format: "lifetime max footprint before training %.0f MB", lifetimeMaxFootprintMB()))
    let t0 = Date()
    for step in 1 ... steps {
        let idx = MLXArray((0 ..< 8).map { _ in Int32(gen.next() % UInt64(tx.dim(0))) })
        let (loss, grads) = lg(model, tx[idx], ty[idx])
        opt.update(model: model, gradients: grads)
        eval(model, opt, loss)
        peak = max(peak, physFootprintMB())
        if step == 1 || step % 50 == 0 {
            let v = heldOut(model)
            let sps = Date().timeIntervalSince(t0) / Double(step)
            curve.append(["step": Double(step), "train": Double(loss.item(Float.self)), "val": Double(v), "s_per_step": sps, "footprint_mb": peak])
            log(String(format: "step %4d  train %.5f  val %.5f  %.3f s/step  peak %.0f MB", step, loss.item(Float.self), v, sps, peak))
        }
    }
    let val1 = heldOut(model)
    let lifetimeMax = lifetimeMaxFootprintMB(), mlxPeak = Double(Memory.peakMemory) / 1_048_576
    let pass2 = val1 < val0 && lifetimeMax <= 2048
    report["criterion2"] = ["val_loss_before": val0, "val_loss_after": val1, "sampled_footprint_mb": peak,
                            "lifetime_max_footprint_mb": lifetimeMax, "mlx_peak_memory_mb": mlxPeak, "curve": curve, "pass": pass2]
    log("criterion 2: held-out loss \(val0) -> \(val1), lifetime max footprint \(Int(lifetimeMax)) MB (sampled \(Int(peak)), MLX peak \(Int(mlxPeak))) -> \(pass2 ? "PASS" : "FAIL")")

    // ---- criterion 3: inject, compare, placement, latency
    let mlxH1 = model(fixture).squeezed(axis: -1); eval(mlxH1)
    let patched = try patchedWeights(model, into: bin)
    try patched.write(to: out.appendingPathComponent("weight-finetuned.bin"))
    let cfgAll = MLModelConfiguration(); cfgAll.computeUnits = .all
    var asset: MLModelAsset?
    var keyUsed = ""
    for key in ["@model_path/weights/weight.bin", "weights/weight.bin"] {
        guard let url = URL(string: key) else { continue }
        do {
            let a = try MLModelAsset(specification: spec, blobMapping: [url: patched])
            _ = try await MLModel.load(asset: a, configuration: cfgAll)
            asset = a; keyUsed = key; break
        } catch { log("blobMapping key \(key): \(error.localizedDescription)") }
    }
    guard let asset else { throw Failure("no blobMapping key loaded; next: the patched-package fallback") }
    let injected = try await MLModel.load(asset: asset, configuration: cfgAll)
    let mlxB1 = model(batch).squeezed(axis: -1); eval(mlxB1)
    var d3s: [String: Float] = [:]
    for (name, units) in unitNames {
        d3s[name] = maxAbs(mlxB1, try coreMLHeatmap(try await MLModel.load(asset: asset, configuration: config(units)), batch))
    }
    let d3 = d3s["cpuAndNeuralEngine"]!
    let aneInjected = try await MLModel.load(asset: asset, configuration: config(.cpuAndNeuralEngine))
    try coreMLHeatmap(aneInjected, batch).asArray(Float.self).withUnsafeBytes { try Data($0).write(to: out.appendingPathComponent("heat-injected-ane-b32.f32")) }
    let moved = maxAbs(mlxH0, mlxH1)
    try mlxH1.asArray(Float.self).withUnsafeBytes { try Data($0).write(to: out.appendingPathComponent("heat-mlx-finetuned.f32")) }
    try coreMLHeatmap(injected, fixture).asArray(Float.self).withUnsafeBytes { try Data($0).write(to: out.appendingPathComponent("heat-injected.f32")) }
    try mlxH0.asArray(Float.self).withUnsafeBytes { try Data($0).write(to: out.appendingPathComponent("heat-mlx-shipped.f32")) }

    let plan = try await MLComputePlan.load(asset: asset, configuration: cfgAll)
    var convDevices: [String: Int] = [:]
    if case let .program(program) = plan.modelStructure, let main = program.functions["main"] {
        for op in main.block.operations where op.operatorName.hasSuffix("conv") {
            let dev = plan.deviceUsage(for: op)?.preferred
            let name: String
            switch dev {
            case .neuralEngine?: name = "neuralEngine"
            case .gpu?: name = "gpu"
            case .cpu?: name = "cpu"
            default: name = "unknown"
            }
            convDevices[name, default: 0] += 1
        }
    }
    let shipped = try MLModel(contentsOf: compiled, configuration: cfgAll)
    // inference only: one prebuilt input, the two models interleaved, 20 reps each after a warm-up
    let input = try inputArray(batch)
    _ = try await shipped.prediction(from: input); _ = try await injected.prediction(from: input)
    var ts: [Double] = [], ti: [Double] = []
    for _ in 0 ..< 20 {
        var t = Date(); _ = try await shipped.prediction(from: input); ts.append(Date().timeIntervalSince(t))
        t = Date(); _ = try await injected.prediction(from: input); ti.append(Date().timeIntervalSince(t))
    }
    let tShipped = ts.sorted()[10], tInjected = ti.sorted()[10]
    let pass3 = d3 <= 1e-2 && convDevices["neuralEngine"] == 15 && tInjected <= 1.2 * tShipped
    report["criterion3"] = ["blob_key": keyUsed, "max_abs_diff_injected_vs_mlx_batch32": d3s, "finetune_moved_heatmap_max": moved,
                            "conv_preferred_devices": convDevices, "batch32_s_shipped": tShipped, "batch32_s_injected": tInjected, "pass": pass3]
    log("criterion 3 (batch 32): injected vs MLX \(d3s) (fine-tune moved the heatmap by \(moved)); convs \(convDevices); inference-only median batch-32 \(tShipped) s shipped vs \(tInjected) s injected -> \(pass3 ? "PASS" : "FAIL")")

    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: out.appendingPathComponent("spike.json"))
    log("wrote \(out.appendingPathComponent("spike.json").path)")
}

/// Deterministic batch sampling (SplitMix64), independent of MLX's RNG.
struct SplitMix { var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The record's fallback for a criterion-3 failure: the fine-tuned blob written into a copy of the package on disk,
/// compiled by Core ML, timed against the shipped package. `SPIKE_MODE=fallback mlx-spike <pkg> <data dir> <run out dir>`
func fallback() async throws {
    let args = CommandLine.arguments
    let pkg = URL(fileURLWithPath: args[1]), dataDir = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
    let fm = FileManager.default
    let copy = out.appendingPathComponent("patched.mlpackage")
    if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
    try fm.copyItem(at: pkg, to: copy)
    let bin = copy.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
    try fm.removeItem(at: bin)
    try fm.copyItem(at: out.appendingPathComponent("weight-finetuned.bin"), to: bin)
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dataDir.appendingPathComponent("data.json"))) as! [String: [Int]]
    let fixture = try loadF32(dataDir, "fixture_x", meta["fixture_x"]!)
    let batch = fixture[MLXArray((0 ..< 32).map { Int32($0 % 16) })]; eval(batch)
    let patched = try await MLModel.compileModel(at: copy), shippedC = try await MLModel.compileModel(at: pkg)
    let ane = try MLModel(contentsOf: patched, configuration: config(.cpuAndNeuralEngine))
    let hPatched = try coreMLHeatmap(ane, batch)
    let d = try Data(contentsOf: out.appendingPathComponent("heat-injected-ane-b32.f32"))
    let hMem = MLXArray(d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, [32, 256, 256])
    let p6 = maxAbs(hPatched, hMem)
    let shipped = try MLModel(contentsOf: shippedC, configuration: config(.all)), mine = try MLModel(contentsOf: patched, configuration: config(.all))
    let input = try inputArray(batch)
    _ = try await shipped.prediction(from: input); _ = try await mine.prediction(from: input)
    var ts: [Double] = [], tp: [Double] = []
    for _ in 0 ..< 20 {
        var t = Date(); _ = try await shipped.prediction(from: input); ts.append(Date().timeIntervalSince(t))
        t = Date(); _ = try await mine.prediction(from: input); tp.append(Date().timeIntervalSince(t))
    }
    let a = ts.sorted()[10], b = tp.sorted()[10]
    print("fallback: patched-package ANE vs in-memory injected ANE max |Δ| \(p6); inference-only median batch-32 \(a) s shipped vs \(b) s patched (\(b / a)x)")
}

if ProcessInfo.processInfo.environment["SPIKE_MODE"] == "fallback" {
    do { try await fallback() } catch { print("mlx-spike: \(error)"); exit(1) }
} else {
    do { try await run() } catch { print("mlx-spike: \(error)"); exit(1) }
}
