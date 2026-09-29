// mps-spike — ADR 048 phase C: an MPSGraph mirror of the learned disk detector's training step (a DIAGNOSTIC, never gates).
// Pass criteria, from ADR 048: (1) the forward on the GPU within the MLX mirror's 0.0027 of the shipped Core ML heatmap;
// (2) a loss curve matching C2.5's b8 control (4.96 -> 2.54 x1e-3, first / last 10 of 50 steps, lr 1e-4); (3) C2.5's
// 2 GB bar on phys_footprint. Nothing here is linked into the app: system frameworks only (Metal, MetalPerformanceShadersGraph,
// CoreML for the criterion-1 reference).
//   SPIKE_MODE=forward  mps-spike <package.mlpackage> <data dir>              criterion 1 (loads Core ML; never used for memory)
//   SPIKE_MODE=train    mps-spike <package.mlpackage> <data dir> [steps=50]   criterion 2 + memory (no Core ML in the process)
// env: SPIKE_DTYPE f32|f16|bf16 (activations; weights, Adam state, loss stay fp32), SPIKE_BATCH (2) micro-batch,
//      SPIKE_ACCUM (4) micro-batches per update, SPIKE_LR (1e-4).
// The data dir holds data.json + raw float32 NCHW arrays (exported once by run.sh, the same export as tools/mlx-training-spike).
// Layout is NCHW / OIHW throughout, the MIL blob's own layout: no permutation on load.

import CoreML
import Foundation
import Metal
import MetalPerformanceShadersGraph

struct Failure: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }

// MARK: - The shipped weights (MIL blob file: 64-B header, 64-B metadata per blob; offsets dumped from model.mlmodel)

let convChannels: [(Int, Int)] = [
    (3, 12), (12, 12), (12, 24), (24, 24), (24, 48), (48, 48), (48, 96), (96, 96),
    (144, 48), (48, 48), (72, 24), (24, 24), (36, 12), (12, 12), (12, 1),   // the last is the 1x1 head
]
let weightMeta = [64, 960, 3776, 9152, 19712, 40704, 82432, 165696, 331904, 456576, 498304, 529600, 540160, 548160, 550976]
let biasMeta: [Int?] = [832, 3648, 9024, 19584, 40512, 82240, 165440, 331648, 456384, 498112, 529472, 540032, 548032, 550848, nil]
let headBias = Float(Float16(bitPattern: 0xB413))   // an inline immediate in the spec, frozen (as in the MLX mirror)
func kernel(_ i: Int) -> Int { i == 14 ? 1 : 3 }

func readBlob(_ bin: Data, meta: Int) throws -> [Float] {
    func u32(_ o: Int) -> UInt32 { bin.subdata(in: o ..< o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    func u64(_ o: Int) -> UInt64 { bin.subdata(in: o ..< o + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } }
    guard u32(meta) == 0xDEAD_BEEF else { throw Failure("no blob sentinel at \(meta)") }
    let size = Int(u64(meta + 8)), offset = Int(u64(meta + 16))
    return bin.subdata(in: offset ..< offset + size).withUnsafeBytes { $0.bindMemory(to: Float16.self).map(Float.init) }
}

/// Parameter order everywhere: w0..w14, then b0..b13 (29 trainable tensors); the head bias is a constant.
struct Weights { var w: [[Float]] = [], b: [[Float]] = [] }
func loadWeights(_ bin: Data) throws -> Weights {
    var r = Weights()
    for i in 0 ..< 15 {
        r.w.append(try readBlob(bin, meta: weightMeta[i]))
        precondition(r.w[i].count == convChannels[i].1 * convChannels[i].0 * kernel(i) * kernel(i))
    }
    for i in 0 ..< 14 { r.b.append(try readBlob(bin, meta: biasMeta[i]!)) }
    return r
}
func paramShapes() -> [[NSNumber]] {
    (0 ..< 15).map { [convChannels[$0].1, convChannels[$0].0, kernel($0), kernel($0)].map { NSNumber(value: $0) } }
        + (0 ..< 14).map { [1, convChannels[$0].1, 1, 1].map { NSNumber(value: $0) } }
}

// MARK: - The UNet in MPSGraph (39 ops as the ADR counts them: 15 convs, 14 SiLUs, 3 pools, 3 upsamples, 3 concats, ...)

struct Net {
    let g: MPSGraph
    let w: [MPSGraphTensor], b: [MPSGraphTensor]     // b[0..13]; the head bias is `headB`
    let headB: MPSGraphTensor
    let dt: MPSDataType

    var params: [MPSGraphTensor] { w + b }

    private func conv(_ a: MPSGraphTensor, _ i: Int) -> MPSGraphTensor {
        let p = i == 14 ? 0 : 1
        let d = MPSGraphConvolution2DOpDescriptor(strideInX: 1, strideInY: 1, dilationRateInX: 1, dilationRateInY: 1, groups: 1,
            paddingLeft: p, paddingRight: p, paddingTop: p, paddingBottom: p, paddingStyle: .explicit,
            dataLayout: .NCHW, weightsLayout: .OIHW)!
        var wt = w[i], bs = i == 14 ? headB : b[i]
        if dt != .float32 { wt = g.cast(wt, to: dt, name: nil); bs = g.cast(bs, to: dt, name: nil) }
        return g.addition(g.convolution2D(a, weights: wt, descriptor: d, name: nil), bs, name: nil)
    }
    private func silu(_ x: MPSGraphTensor) -> MPSGraphTensor { g.multiplication(x, g.sigmoid(with: x, name: nil), name: nil) }
    private func block(_ x: MPSGraphTensor, _ i: Int) -> MPSGraphTensor { silu(conv(silu(conv(x, i)), i + 1)) }
    private func pool(_ x: MPSGraphTensor) -> MPSGraphTensor {
        let d = MPSGraphPooling2DOpDescriptor(kernelWidth: 2, kernelHeight: 2, strideInX: 2, strideInY: 2,
                                              paddingStyle: .TF_VALID, dataLayout: .NCHW)!
        return g.maxPooling2D(withSourceTensor: x, descriptor: d, name: nil)
    }
    /// Nearest x2 (`Upsample(scaleFactor: 2, mode: .nearest)`): half-pixel centres, so output 2k and 2k+1 both read input k.
    private func up(_ x: MPSGraphTensor, _ side: Int) -> MPSGraphTensor {
        g.resize(x, size: [NSNumber(value: side), NSNumber(value: side)], mode: .nearest, centerResult: true, alignCorners: false,
                 layout: .NCHW, name: nil)
    }

    /// x: [N,3,256,256] fp32 -> heatmap [N,1,256,256] fp32.
    func forward(_ x: MPSGraphTensor) -> MPSGraphTensor {
        let xin = dt == .float32 ? x : g.cast(x, to: dt, name: nil)
        let e1 = block(xin, 0)                       // 256
        let e2 = block(pool(e1), 2)                  // 128
        let e3 = block(pool(e2), 4)                  // 64
        let bt = block(pool(e3), 6)                  // 32
        let d3 = block(g.concatTensors([up(bt, 64), e3], dimension: 1, name: nil), 8)
        let d2 = block(g.concatTensors([up(d3, 128), e2], dimension: 1, name: nil), 10)
        let d1 = block(g.concatTensors([up(d2, 256), e1], dimension: 1, name: nil), 12)
        let h = g.sigmoid(with: conv(d1, 14), name: nil)
        return dt == .float32 ? h : g.cast(h, to: .float32, name: nil)
    }

    /// The registered loss: mean((1 + 20 t)(p - t)^2), shape [1].
    func loss(_ x: MPSGraphTensor, _ t: MPSGraphTensor) -> MPSGraphTensor {
        let p = forward(x)
        let wt = g.addition(g.constant(1, dataType: .float32), g.multiplication(g.constant(20, dataType: .float32), t, name: nil), name: nil)
        let e = g.multiplication(wt, g.square(with: g.subtraction(p, t, name: nil), name: nil), name: nil)
        return g.reshape(g.mean(of: e, axes: [0, 1, 2, 3], name: nil), shape: [1], name: nil)
    }
}

func makeNet(_ g: MPSGraph, _ dt: MPSDataType) -> Net {
    let shapes = paramShapes()
    let ph = shapes.enumerated().map { g.placeholder(shape: $0.element, dataType: .float32, name: "p\($0.offset)") }
    let hb = g.constant(Double(headBias), shape: [1, 1, 1, 1], dataType: .float32)
    return Net(g: g, w: Array(ph[0 ..< 15]), b: Array(ph[15 ..< 29]), headB: hb, dt: dt)
}

// MARK: - Plumbing

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

struct SplitMix { var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func mapF32(_ dir: URL, _ name: String) throws -> Data { try Data(contentsOf: dir.appendingPathComponent("\(name).f32"), options: .alwaysMapped) }

func tensorData(_ dev: MPSGraphDevice, _ floats: [Float], _ shape: [NSNumber]) -> MPSGraphTensorData {
    floats.withUnsafeBytes { MPSGraphTensorData(device: dev, data: Data($0), shape: shape, dataType: .float32) }
}
func tensorData(_ dev: MPSGraphDevice, _ data: Data, _ shape: [NSNumber]) -> MPSGraphTensorData {
    MPSGraphTensorData(device: dev, data: data, shape: shape, dataType: .float32)
}
func readFloats(_ td: MPSGraphTensorData, count: Int) -> [Float] {
    var out = [Float](repeating: 0, count: count)
    td.mpsndarray().readBytes(&out, strideBytes: nil)
    return out
}
func dtype(_ s: String) throws -> MPSDataType {
    switch s { case "f32": return .float32; case "f16": return .float16; case "bf16": return .bFloat16
    default: throw Failure("SPIKE_DTYPE must be f32, f16 or bf16") }
}

// MARK: - Criterion 1: the GPU forward vs the shipped Core ML heatmap

func coreMLHeatmap(_ model: MLModel, _ x: [Float], n: Int) throws -> [Float] {
    let arr = try MLMultiArray(shape: [n, 3, 256, 256].map { NSNumber(value: $0) }, dataType: .float16)
    arr.withUnsafeMutableBufferPointer(ofType: Float16.self) { p, _ in for i in 0 ..< x.count { p[i] = Float16(x[i]) } }
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": arr]))
    return MLShapedArray<Float16>(out.featureValue(for: "heatmap")!.multiArrayValue!).scalars.map(Float.init)
}
func maxAbs(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { max($0, abs($1.0 - $1.1)) } }
func meanAbs(_ a: [Float], _ b: [Float]) -> Double { zip(a, b).reduce(0.0) { $0 + Double(abs($1.0 - $1.1)) } / Double(a.count) }

func forwardMode(pkg: URL, dataDir: URL) async throws {
    let bin = try Data(contentsOf: pkg.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin"))
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dataDir.appendingPathComponent("data.json"))) as! [String: [Int]]
    let fx = try mapF32(dataDir, "fixture_x")
    let n16 = meta["fixture_x"]![0], per = 3 * 256 * 256 * 4
    // the app's batch: 32 = the 16 fixture patterns twice
    var batch = Data(); for i in 0 ..< 32 { batch.append(fx.subdata(in: (i % n16) * per ..< ((i % n16) + 1) * per)) }
    let batchFloats = batch.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let wts = try loadWeights(bin)
    guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { throw Failure("no Metal device") }
    let gdev = MPSGraphDevice(mtlDevice: dev)
    let shapes = paramShapes()
    let pd = (wts.w + wts.b).enumerated().map { tensorData(gdev, $0.element, shapes[$0.offset]) }

    var results: [String: [Float]] = [:]
    for name in ["f32", "f16"] {
        let g = MPSGraph(); let net = makeNet(g, try dtype(name))
        let x = g.placeholder(shape: [32, 3, 256, 256], dataType: .float32, name: "x")
        let h = net.forward(x)
        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [x: tensorData(gdev, batch, [32, 3, 256, 256])]
        for (t, d) in zip(net.params, pd) { feeds[t] = d }
        let r = g.run(with: queue, feeds: feeds, targetTensors: [h], targetOperations: nil)
        results[name] = readFloats(r[h]!, count: 32 * 256 * 256)
    }
    let compiled = try await MLModel.compileModel(at: pkg)
    let units: [(String, MLComputeUnits)] = [("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly), ("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all)]
    var report: [String: Any] = [:]
    var line = "criterion 1 (batch 32, MPSGraph vs shipped Core ML):"
    for (uname, u) in units {
        let cfg = MLModelConfiguration(); cfg.computeUnits = u
        let ref = try coreMLHeatmap(try MLModel(contentsOf: compiled, configuration: cfg), batchFloats, n: 32)
        for (dname, h) in results.sorted(by: { $0.key < $1.key }) {
            report["max_abs_\(dname)_vs_\(uname)"] = Double(maxAbs(h, ref)); report["mean_abs_\(dname)_vs_\(uname)"] = meanAbs(h, ref)
            line += String(format: "\n  %@ graph vs %@: max |Δ| %.5f  mean |Δ| %.6f", dname, uname, maxAbs(h, ref), meanAbs(h, ref))
        }
    }
    // rows i and i+16 are the same pattern: the graph must give them identically (a batch-index bug would not)
    let a = Array(results["f32"]![0 ..< 16 * 65536]), b2 = Array(results["f32"]![16 * 65536 ..< 32 * 65536])
    report["f32_row_i_vs_i16_max"] = Double(maxAbs(a, b2))
    report["heatmap_range"] = [Double(results["f32"]!.min()!), Double(results["f32"]!.max()!)]
    print(line); print("  rows i vs i+16 (f32) max |Δ| \(maxAbs(a, b2)); heatmap range \(report["heatmap_range"]!)")
    print("MPSFWD " + String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
}

// MARK: - Criterion 2 + memory: the training step

func trainMode(pkg: URL, dataDir: URL, steps: Int) throws {
    let env = ProcessInfo.processInfo.environment
    let batchN = Int(env["SPIKE_BATCH"] ?? "2")!, accum = Int(env["SPIKE_ACCUM"] ?? "4")!
    let lr = Double(env["SPIKE_LR"] ?? "1e-4")!, dtName = env["SPIKE_DTYPE"] ?? "f32"
    let (beta1, beta2, eps, wd) = (0.9, 0.999, 1e-8, 1e-4)   // AdamW as mlx-swift's: no bias correction, decoupled decay
    let bin = try Data(contentsOf: pkg.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin"))
    let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dataDir.appendingPathComponent("data.json"))) as! [String: [Int]]
    let tx = try mapF32(dataDir, "train_x"), ty = try mapF32(dataDir, "train_y"), vx = try mapF32(dataDir, "val_x"), vy = try mapF32(dataDir, "val_y")
    let nTrain = meta["train_x"]![0], nVal = meta["val_x"]![0]
    let xs = 3 * 65536 * 4, ys = 65536 * 4     // bytes per sample
    guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { throw Failure("no Metal device") }
    let gdev = MPSGraphDevice(mtlDevice: dev)
    let shapes = paramShapes(), nP = shapes.count
    let wts = try loadWeights(bin)
    var maxAllocated = 0.0
    func sampleAlloc() { maxAllocated = max(maxAllocated, Double(dev.currentAllocatedSize) / 1_048_576) }

    // graph A: one micro-batch -> loss and the running gradient sum
    let gA = MPSGraph(); let netA = makeNet(gA, try dtype(dtName))
    let ax = gA.placeholder(shape: [NSNumber(value: batchN), 3, 256, 256], dataType: .float32, name: "x")
    let at = gA.placeholder(shape: [NSNumber(value: batchN), 1, 256, 256], dataType: .float32, name: "t")
    let accIn = shapes.map { gA.placeholder(shape: $0, dataType: .float32, name: nil) }
    let lossA = netA.loss(ax, at)
    let grads = gA.gradients(of: lossA, with: netA.params, name: nil)
    let accOut = (0 ..< nP).map { gA.addition(accIn[$0], grads[netA.params[$0]]!, name: nil) }

    // graph B: AdamW on the summed gradients
    let gB = MPSGraph()
    let pB = shapes.map { gB.placeholder(shape: $0, dataType: .float32, name: nil) }, mB = shapes.map { gB.placeholder(shape: $0, dataType: .float32, name: nil) }
    let vB = shapes.map { gB.placeholder(shape: $0, dataType: .float32, name: nil) }, aB = shapes.map { gB.placeholder(shape: $0, dataType: .float32, name: nil) }
    func c(_ v: Double) -> MPSGraphTensor { gB.constant(v, dataType: .float32) }
    var newP: [MPSGraphTensor] = [], newM: [MPSGraphTensor] = [], newV: [MPSGraphTensor] = []
    for i in 0 ..< nP {
        let gr = gB.multiplication(aB[i], c(1.0 / Double(accum)), name: nil)
        let m = gB.addition(gB.multiplication(mB[i], c(beta1), name: nil), gB.multiplication(gr, c(1 - beta1), name: nil), name: nil)
        let v = gB.addition(gB.multiplication(vB[i], c(beta2), name: nil), gB.multiplication(gB.square(with: gr, name: nil), c(1 - beta2), name: nil), name: nil)
        let step = gB.multiplication(c(lr), gB.division(m, gB.addition(gB.squareRoot(with: v, name: nil), c(eps), name: nil), name: nil), name: nil)
        newP.append(gB.subtraction(gB.multiplication(pB[i], c(1 - lr * wd), name: nil), step, name: nil)); newM.append(m); newV.append(v)
    }

    // graph E: held-out loss, fp32, chunks of 8
    let gE = MPSGraph(); let netE = makeNet(gE, .float32)
    let ex = gE.placeholder(shape: [8, 3, 256, 256], dataType: .float32, name: "x"), et = gE.placeholder(shape: [8, 1, 256, 256], dataType: .float32, name: "t")
    let lossE = netE.loss(ex, et)

    var P = (wts.w + wts.b).enumerated().map { tensorData(gdev, $0.element, shapes[$0.offset]) }
    var M = shapes.map { s in tensorData(gdev, [Float](repeating: 0, count: s.reduce(1) { $0 * $1.intValue }), s) }
    var V = M
    let zeros = M   // read-only zero accumulators fed to the first micro-batch of every step

    func heldOut() -> Float {
        var total: Float = 0
        for s in stride(from: 0, to: nVal, by: 8) {
            var feeds: [MPSGraphTensor: MPSGraphTensorData] = [
                ex: tensorData(gdev, vx.subdata(in: s * xs ..< (s + 8) * xs), [8, 3, 256, 256]),
                et: tensorData(gdev, vy.subdata(in: s * ys ..< (s + 8) * ys), [8, 1, 256, 256])]
            for (t, d) in zip(netE.params, P) { feeds[t] = d }
            let r = gE.run(with: queue, feeds: feeds, targetTensors: [lossE], targetOperations: nil)
            total += readFloats(r[lossE]!, count: 1)[0] * 8
        }
        return total / Float(nVal)
    }
    let val0 = heldOut()
    sampleAlloc()
    let baselineFootprint = physFootprintMB(), baselineLifetime = lifetimeMaxFootprintMB()
    var gen = SplitMix(seed: 20_260_928)
    var losses: [Double] = [], firstStepMoments: [String: Any] = [:]
    var peakFootprint = baselineFootprint
    let t0 = Date(); var tAfterFirst = t0
    for step in 1 ... steps {
        var acc = zeros; var lossSum: Float = 0
        for _ in 0 ..< accum {
            var xb = Data(), tb = Data()
            for _ in 0 ..< batchN {
                let i = Int(gen.next() % UInt64(nTrain))
                xb.append(tx.subdata(in: i * xs ..< (i + 1) * xs)); tb.append(ty.subdata(in: i * ys ..< (i + 1) * ys))
            }
            var feeds: [MPSGraphTensor: MPSGraphTensorData] = [
                ax: tensorData(gdev, xb, [NSNumber(value: batchN), 3, 256, 256]), at: tensorData(gdev, tb, [NSNumber(value: batchN), 1, 256, 256])]
            for (t, d) in zip(netA.params, P) { feeds[t] = d }
            for (t, d) in zip(accIn, acc) { feeds[t] = d }
            let r = gA.run(with: queue, feeds: feeds, targetTensors: [lossA] + accOut, targetOperations: nil)
            lossSum += readFloats(r[lossA]!, count: 1)[0]
            acc = accOut.map { r[$0]! }
            sampleAlloc(); peakFootprint = max(peakFootprint, physFootprintMB())
        }
        var feedsB: [MPSGraphTensor: MPSGraphTensorData] = [:]
        for i in 0 ..< nP { feedsB[pB[i]] = P[i]; feedsB[mB[i]] = M[i]; feedsB[vB[i]] = V[i]; feedsB[aB[i]] = acc[i] }
        let rb = gB.run(with: queue, feeds: feedsB, targetTensors: newP + newM + newV, targetOperations: nil)
        P = newP.map { rb[$0]! }; M = newM.map { rb[$0]! }; V = newV.map { rb[$0]! }
        sampleAlloc(); peakFootprint = max(peakFootprint, physFootprintMB())
        losses.append(Double(lossSum / Float(accum)))
        if step == 1 {
            tAfterFirst = Date()
            // P5: every first-moment tensor (0.1 x the step-1 gradient) is finite and non-zero
            var bad = 0, zero = 0
            for (i, m) in M.enumerated() {
                let f = readFloats(m, count: shapes[i].reduce(1) { $0 * $1.intValue })
                if f.contains(where: { !$0.isFinite }) { bad += 1 }
                if !f.contains(where: { $0 != 0 }) { zero += 1 }
            }
            firstStepMoments = ["tensors": nP, "non_finite": bad, "all_zero": zero]
        }
    }
    let total = Date().timeIntervalSince(t0)
    let sPerStep = steps > 1 ? Date().timeIntervalSince(tAfterFirst) / Double(steps - 1) : total
    let lifetime = lifetimeMaxFootprintMB(), foot = physFootprintMB()
    let val1 = heldOut()
    func m(_ a: ArraySlice<Double>) -> Double { a.reduce(0, +) / Double(a.count) }
    let out: [String: Any] = ["batch": batchN, "accum": accum, "dtype": dtName, "steps": steps, "lr": lr,
        "lifetime_max_footprint_mb": lifetime, "lifetime_max_before_loop_mb": baselineLifetime, "footprint_before_loop_mb": baselineFootprint,
        "sampled_max_footprint_mb": peakFootprint, "footprint_end_mb": foot,
        "mps_allocated_max_mb": maxAllocated, "mps_allocated_end_mb": Double(dev.currentAllocatedSize) / 1_048_576,
        "recommended_max_working_set_mb": Double(dev.recommendedMaxWorkingSetSize) / 1_048_576,
        "s_per_step": sPerStep, "samples_per_s": Double(batchN * accum) / sPerStep,
        "loss_first10": m(losses.prefix(10)), "loss_last10": m(losses.suffix(10)), "val_before": Double(val0), "val_after": Double(val1),
        "step1_moments": firstStepMoments, "losses": losses.map { ($0 * 1e5).rounded() / 1e5 }]
    print("MPSBENCH " + String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
}

do {
    let args = CommandLine.arguments
    guard args.count >= 3 else { throw Failure("usage: mps-spike <package.mlpackage> <data dir> [steps]") }
    let pkg = URL(fileURLWithPath: args[1]), dataDir = URL(fileURLWithPath: args[2])
    switch ProcessInfo.processInfo.environment["SPIKE_MODE"] ?? "train" {
    case "forward": try await forwardMode(pkg: pkg, dataDir: dataDir)
    case "train": try trainMode(pkg: pkg, dataDir: dataDir, steps: args.count > 3 ? Int(args[3])! : 50)
    default: throw Failure("SPIKE_MODE is forward or train")
    }
} catch { print("mps-spike: \(error)"); exit(1) }
