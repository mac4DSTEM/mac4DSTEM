//
//  DetectorTrainer.swift
//  Role: on-device fine-tuning of the learned disk detector on the GPU (C3 pre-registration §2, §3 steps
//        3-4; ADR 048: MPSGraph, not MLX). A port of `tools/mpsgraph-training-spike`'s `trainMode`, which
//        matched C2.5's MLX loss curve (4.96 -> 2.54 x1e-3 over 50 steps at lr 1e-4) and fitted the 2 GB bar
//        (bf16: 1068 MB lifetime-max footprint, 0.109 s/step, 2026-09-30).
//
//  The recipe is the ADR's fixed one: always from the BUNDLED weights, fp32 masters, bf16 activations,
//  micro-batch 2 x 4 accumulated, AdamW lr 1e-5 (decoupled decay, no bias correction — mlx-swift's
//  defaults, which the loss match supports), flips / rot90 on the training samples only, no early
//  stopping. Targets are `simulate.heatmap_target` (sigma 1.5, amplitude 1 for every labelled disk) and
//  the loss is `train.HeatmapLoss` (miss weight 20).
//
//  The trainer knows no dataset: the caller (C4b) builds `TrainingSample`s — the model inputs from
//  `LearnedDiskDetector.modelInputs` and the hand-labelled centres mapped into the 256 frame with
//  `LearnedDiskDetector.fitOffset` — and decides the step count (D5: from an inner split of the training
//  positions). It never touches the resident cube: samples are copied, micro-batches are streamed.
//

import DSTEMCore
import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Recipe, samples, results

package nonisolated struct TrainingRecipe: Codable, Equatable, Sendable {
    package var learningRate = 1e-5
    /// Optimiser steps. The registered default is the pre-registration's 500; C4b sets it from the inner split.
    package var steps = 500
    package var microBatch = 2
    package var accumulation = 4
    package var weightDecay = 1e-4
    package var beta1 = 0.9
    package var beta2 = 0.999
    package var epsilon = 1e-8
    package var missWeight = 20.0
    package var heatmapSigma = 1.5
    /// "bf16" (registered), "f16" or "f32". Masters, optimiser state and the loss are always fp32.
    package var activations = "bf16"
    /// Random flips / rot90 (the 8 dihedral maps) on training samples.
    package var augment = true
    package var seed: UInt64 = 20_260_930
    package init() {}
}

package nonisolated struct TrainingSample: Sendable {
    package var position: ScanPosition?
    /// (3, 256, 256) float16: `LearnedDiskDetector.modelInputs` of the fitted pattern, probe and correlation.
    package var inputs: [Float16]
    /// Hand-labelled centres in the 256 model frame, (row, col).
    package var centres: [ScorePoint]
    package init(position: ScanPosition? = nil, inputs: [Float16], centres: [ScorePoint]) {
        self.position = position; self.inputs = inputs; self.centres = centres
    }
}

package nonisolated struct TrainingProgress: Sendable {
    package var step: Int
    package var steps: Int
    /// The mean loss over this step's accumulated micro-batches.
    package var loss: Double
    package var secondsPerStep: Double
}

package nonisolated struct TrainingResult: Sendable {
    package var weights: DetectorWeights
    package var stepLosses: [Double]
    /// Mean per-sample loss on the held-out samples (fp32 forward) before and after; nil without held-out samples.
    package var heldOutLossBefore: Double?
    package var heldOutLossAfter: Double?
    package var secondsPerStep: Double
    /// The process's lifetime-maximum physical footprint at the end (MB): the number the 2 GB bar is read on.
    package var lifetimeMaxFootprintMB: Double
}

package nonisolated enum TrainingError: Error, CustomStringConvertible, LocalizedError {
    case insufficientMemory(availableBytes: Int, requiredBytes: Int)
    case noTrainingSamples
    case badSample(index: Int, reason: String)
    case invalidRecipe(String)
    case noMetalDevice
    case cancelled
    package var description: String {
        switch self {
        case .insufficientMemory(let a, let r):
            return String(format: "not enough free memory to train: %.2f GB available, %.2f GB needed", Double(a) / 1e9, Double(r) / 1e9)
        case .noTrainingSamples: return "no labelled training positions"
        case .badSample(let i, let why): return "training sample \(i): \(why)"
        case .invalidRecipe(let why): return "invalid training recipe: \(why)"
        case .noMetalDevice: return "no Metal device"
        case .cancelled: return "training cancelled"
        }
    }
    package var errorDescription: String? { description }
}

// MARK: - Targets and augmentation

package nonisolated enum DetectorTraining {
    /// `simulate.heatmap_target`: a Gaussian bump at every centre, max over bumps, amplitude 1, window
    /// ceil(4 sigma) around the rounded centre (Python's round-half-even), clipped to the frame. (S*S) float32.
    package static func heatmapTarget(centres: [ScorePoint], size: Int = LearnedDiskDetector.inputSize, sigma: Double = 1.5) -> [Float] {
        var out = [Double](repeating: 0, count: size * size)
        let w = Int((4 * sigma).rounded(.up))
        for c in centres {
            let r0 = Int(c.row.rounded(.toNearestOrEven)), c0 = Int(c.col.rounded(.toNearestOrEven))
            let rs = max(r0 - w, 0), re = min(r0 + w + 1, size)
            let cs = max(c0 - w, 0), ce = min(c0 + w + 1, size)
            if rs >= re || cs >= ce { continue }
            for r in rs ..< re {
                for col in cs ..< ce {
                    let d2 = (Double(r) - c.row) * (Double(r) - c.row) + (Double(col) - c.col) * (Double(col) - c.col)
                    let v = exp(-d2 / (2 * sigma * sigma))
                    if v > out[r * size + col] { out[r * size + col] = v }
                }
            }
        }
        return out.map { Float($0) }
    }

    /// Source index of output pixel (y, x) under dihedral element k in 0..<8: out = rot90ccw^(k&3)(flipX^(k>>2)(in)).
    /// k = 0 is the identity; the eight maps are the symmetries of the square.
    package static func sourceIndex(y: Int, x: Int, k: Int, size S: Int) -> Int {
        var yy = y, xx = x
        for _ in 0 ..< (k & 3) { (yy, xx) = (xx, S - 1 - yy) }
        if k & 4 != 0 { xx = S - 1 - xx }
        return yy * S + xx
    }

    /// The eight gather tables for a `size` frame.
    package static func dihedralTables(size S: Int) -> [[Int32]] {
        (0 ..< 8).map { k in
            var t = [Int32](repeating: 0, count: S * S)
            for y in 0 ..< S { for x in 0 ..< S { t[y * S + x] = Int32(sourceIndex(y: y, x: x, k: k, size: S)) } }
            return t
        }
    }

    /// Decisions on memory before a run (C3 §3 step 3): the trainer needs about 1.1 GB (bf16, measured) and
    /// refuses below 2 GB available — the C2.5 bar.
    package static let requiredAvailableBytes = 2 * 1024 * 1024 * 1024

    /// Bytes that can be claimed without evicting anything a user is holding: (free + inactive) pages x page
    /// size from `host_statistics64(HOST_VM_INFO64)`. `os_proc_available_memory()` is unavailable on macOS.
    /// 0 when the kernel call fails, which admission then refuses. It is a system-wide reading taken once at
    /// the start of a run; C4b pairs it with a memory-pressure source that cancels a run under pressure.
    package static func availableMemoryBytes() -> Int {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return (Int(stats.free_count) + Int(stats.inactive_count)) * Int(getpagesize())
    }

    /// `extraBytes`: memory the caller is about to hold beside the trainer's own (the training samples).
    package static func admit(availableBytes: Int, extraBytes: Int = 0) throws {
        let required = requiredAvailableBytes + max(extraBytes, 0)
        guard availableBytes >= required else {
            throw TrainingError.insufficientMemory(availableBytes: availableBytes, requiredBytes: required)
        }
    }

    /// One training sample's inputs: (3, 256, 256) float16.
    package static let sampleInputBytes = 3 * LearnedDiskDetector.inputSize * LearnedDiskDetector.inputSize * MemoryLayout<Float16>.stride

    /// The process's physical footprint now (MB).
    package static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
    }
    /// The process's lifetime-maximum physical footprint (MB): the kernel's own high-water mark, not a sample.
    package static func lifetimeMaxFootprintMB() -> Double {
        var info = rusage_info_v4()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return kr == 0 ? Double(info.ri_lifetime_max_phys_footprint) / 1_048_576 : .nan
    }
}

/// SplitMix64: a small, fixed generator so a recipe's seed fixes the sample order and the augmentations.
nonisolated struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - The trainer

package nonisolated final class DetectorTrainer: @unchecked Sendable {
    package let parentPackage: URL
    package let recipe: TrainingRecipe

    /// `parentPackage`: the BUNDLED `.mlpackage` (training always starts from it, D4).
    package init(parentPackage: URL, recipe: TrainingRecipe = TrainingRecipe()) {
        self.parentPackage = parentPackage; self.recipe = recipe
    }

    /// Fine-tunes on `samples` and returns the new weights. Runs off the caller's actor. `heldOut` (optional)
    /// only feeds the before / after loss. `availableMemory` defaults to `DetectorTraining.availableMemoryBytes()` (free + inactive pages); it
    /// throws `insufficientMemory` below 2 GB before any GPU memory is allocated. `cancellation` is checked
    /// before every micro-batch and throws `.cancelled`.
    package func train(
        samples: [TrainingSample], heldOut: [TrainingSample] = [],
        availableMemory: @escaping @Sendable () -> Int = { DetectorTraining.availableMemoryBytes() },
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (TrainingProgress) -> Void)? = nil
    ) async throws -> TrainingResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try trainBlocking(samples: samples, heldOut: heldOut, availableMemory: availableMemory,
                              cancellation: cancellation, progress: progress)
        }.value
    }

    private static func activationType(_ name: String) throws -> MPSDataType {
        switch name {
        case "bf16": return .bFloat16
        case "f16": return .float16
        case "f32": return .float32
        default: throw TrainingError.invalidRecipe("activations must be bf16, f16 or f32, not \(name)")
        }
    }

    private static func tensorData(_ dev: MPSGraphDevice, _ floats: [Float], _ shape: [NSNumber]) -> MPSGraphTensorData {
        floats.withUnsafeBytes { MPSGraphTensorData(device: dev, data: Data($0), shape: shape, dataType: .float32) }
    }
    private static func readFloats(_ td: MPSGraphTensorData, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        td.mpsndarray().readBytes(&out, strideBytes: nil)
        return out
    }

    /// The fp32 GPU forward of `weights` on `inputs` ((n, 3, 256, 256) float16, flat) -> (n, 256, 256) float32
    /// heatmaps: the graph the trainer differentiates, run alone. The port's check against Core ML (the
    /// spike's criterion 1: 0.00272 on the GPU, 0.0355 against the Neural Engine).
    package static func forward(weights: DetectorWeights, inputs: [Float16]) throws -> [Float] {
        let S = LearnedDiskDetector.inputSize, xs = 3 * S * S
        guard !inputs.isEmpty, inputs.count % xs == 0 else {
            throw TrainingError.badSample(index: 0, reason: "\(inputs.count) input values is not a whole number of (3, \(S), \(S)) patterns")
        }
        let n = inputs.count / xs
        guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { throw TrainingError.noMetalDevice }
        let gdev = MPSGraphDevice(mtlDevice: dev)
        let g = MPSGraph(); let net = DetectorGraph.make(g, activations: .float32)
        let x = g.placeholder(shape: [NSNumber(value: n), 3, NSNumber(value: S), NSNumber(value: S)], dataType: .float32, name: "x")
        let h = net.forward(x)
        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            x: tensorData(gdev, inputs.map { Float($0) }, [NSNumber(value: n), 3, NSNumber(value: S), NSNumber(value: S)])]
        for (i, t) in net.params.enumerated() {
            feeds[t] = tensorData(gdev, weights.parameters[i], DetectorWeights.shapes[i].map { NSNumber(value: $0) })
        }
        let out = g.run(with: queue, feeds: feeds, targetTensors: [h], targetOperations: nil)
        return readFloats(out[h]!, count: n * S * S)
    }

    package func trainBlocking(
        samples: [TrainingSample], heldOut: [TrainingSample],
        availableMemory: () -> Int, cancellation: AnalysisCancellationToken?, progress: (@Sendable (TrainingProgress) -> Void)?
    ) throws -> TrainingResult {
        let r = recipe
        guard r.steps > 0, r.microBatch > 0, r.accumulation > 0, r.learningRate > 0 else {
            throw TrainingError.invalidRecipe("steps, microBatch, accumulation and learningRate must be positive")
        }
        let dt = try Self.activationType(r.activations)
        guard !samples.isEmpty else { throw TrainingError.noTrainingSamples }
        let S = LearnedDiskDetector.inputSize, xs = 3 * S * S, ys = S * S
        for (i, s) in (samples + heldOut).enumerated() where s.inputs.count != xs {
            throw TrainingError.badSample(index: i, reason: "\(s.inputs.count) input values, expected \(xs)")
        }
        try DetectorTraining.admit(availableBytes: availableMemory())
        guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { throw TrainingError.noMetalDevice }
        let gdev = MPSGraphDevice(mtlDevice: dev)
        let wts = try DetectorWeights.load(fromPackage: parentPackage)
        let shapes = DetectorWeights.shapes.map { $0.map { NSNumber(value: $0) } }, counts = DetectorWeights.elementCounts
        let nP = shapes.count, nB = r.microBatch

        // graph A: one micro-batch -> loss and the running gradient sum
        let gA = MPSGraph(); let netA = DetectorGraph.make(gA, activations: dt, missWeight: r.missWeight)
        let ax = gA.placeholder(shape: [NSNumber(value: nB), 3, NSNumber(value: S), NSNumber(value: S)], dataType: .float32, name: "x")
        let at = gA.placeholder(shape: [NSNumber(value: nB), 1, NSNumber(value: S), NSNumber(value: S)], dataType: .float32, name: "t")
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
            let gr = gB.multiplication(aB[i], c(1.0 / Double(r.accumulation)), name: nil)
            let m = gB.addition(gB.multiplication(mB[i], c(r.beta1), name: nil), gB.multiplication(gr, c(1 - r.beta1), name: nil), name: nil)
            let v = gB.addition(gB.multiplication(vB[i], c(r.beta2), name: nil), gB.multiplication(gB.square(with: gr, name: nil), c(1 - r.beta2), name: nil), name: nil)
            let step = gB.multiplication(c(r.learningRate), gB.division(m, gB.addition(gB.squareRoot(with: v, name: nil), c(r.epsilon), name: nil), name: nil), name: nil)
            newP.append(gB.subtraction(gB.multiplication(pB[i], c(1 - r.learningRate * r.weightDecay), name: nil), step, name: nil))
            newM.append(m); newV.append(v)
        }

        var P = (wts.w + wts.b).enumerated().map { Self.tensorData(gdev, $0.element, shapes[$0.offset]) }
        var M = shapes.enumerated().map { Self.tensorData(gdev, [Float](repeating: 0, count: counts[$0.offset]), $0.element) }
        var V = M
        let zeros = M   // read-only zero accumulators fed to the first micro-batch of every step

        // held-out loss: an fp32 forward, one sample at a time (any count)
        let heldTargets = heldOut.map { DetectorTraining.heatmapTarget(centres: $0.centres, size: S, sigma: r.heatmapSigma) }
        var heldOutLoss: (() -> Double?) = { nil }
        if !heldOut.isEmpty {
            let gE = MPSGraph(); let netE = DetectorGraph.make(gE, activations: .float32, missWeight: r.missWeight)
            let ex = gE.placeholder(shape: [1, 3, NSNumber(value: S), NSNumber(value: S)], dataType: .float32, name: "x")
            let et = gE.placeholder(shape: [1, 1, NSNumber(value: S), NSNumber(value: S)], dataType: .float32, name: "t")
            let lossE = netE.loss(ex, et)
            heldOutLoss = {
                var total = 0.0
                for (i, s) in heldOut.enumerated() {
                    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [
                        ex: Self.tensorData(gdev, s.inputs.map { Float($0) }, [1, 3, NSNumber(value: S), NSNumber(value: S)]),
                        et: Self.tensorData(gdev, heldTargets[i], [1, 1, NSNumber(value: S), NSNumber(value: S)])]
                    for (t, d) in zip(netE.params, P) { feeds[t] = d }
                    let out = gE.run(with: queue, feeds: feeds, targetTensors: [lossE], targetOperations: nil)
                    total += Double(Self.readFloats(out[lossE]!, count: 1)[0])
                }
                return total / Double(heldOut.count)
            }
        }
        let before = heldOutLoss()

        // Targets are built per micro-batch below, never held for every sample (C4b review: 275 positions x
        // several windows of fp32 targets would sit in memory before the graph allocates).
        let tables = r.augment ? DetectorTraining.dihedralTables(size: S) : []
        var gen = SplitMix64(seed: r.seed)
        var losses: [Double] = []
        let t0 = Date()
        for step in 1 ... r.steps {
            var acc = zeros; var lossSum: Float = 0
            for _ in 0 ..< r.accumulation {
                if cancellation?.isCancelled == true { throw TrainingError.cancelled }
                var xb = [Float](repeating: 0, count: nB * xs), tb = [Float](repeating: 0, count: nB * ys)
                for b in 0 ..< nB {
                    let i = Int(gen.next() % UInt64(samples.count))
                    let k = r.augment ? Int(gen.next() % 8) : 0
                    let src = samples[i].inputs
                    let tgt = DetectorTraining.heatmapTarget(centres: samples[i].centres, size: S, sigma: r.heatmapSigma)
                    if k == 0 {
                        for j in 0 ..< xs { xb[b * xs + j] = Float(src[j]) }
                        for j in 0 ..< ys { tb[b * ys + j] = tgt[j] }
                    } else {
                        let table = tables[k]
                        for ch in 0 ..< 3 {
                            for j in 0 ..< ys { xb[b * xs + ch * ys + j] = Float(src[ch * ys + Int(table[j])]) }
                        }
                        for j in 0 ..< ys { tb[b * ys + j] = tgt[Int(table[j])] }
                    }
                }
                var feeds: [MPSGraphTensor: MPSGraphTensorData] = [
                    ax: Self.tensorData(gdev, xb, [NSNumber(value: nB), 3, NSNumber(value: S), NSNumber(value: S)]),
                    at: Self.tensorData(gdev, tb, [NSNumber(value: nB), 1, NSNumber(value: S), NSNumber(value: S)])]
                for (t, d) in zip(netA.params, P) { feeds[t] = d }
                for (t, d) in zip(accIn, acc) { feeds[t] = d }
                let out = gA.run(with: queue, feeds: feeds, targetTensors: [lossA] + accOut, targetOperations: nil)
                lossSum += Self.readFloats(out[lossA]!, count: 1)[0]
                acc = accOut.map { out[$0]! }
            }
            var feedsB: [MPSGraphTensor: MPSGraphTensorData] = [:]
            for i in 0 ..< nP { feedsB[pB[i]] = P[i]; feedsB[mB[i]] = M[i]; feedsB[vB[i]] = V[i]; feedsB[aB[i]] = acc[i] }
            let rb = gB.run(with: queue, feeds: feedsB, targetTensors: newP + newM + newV, targetOperations: nil)
            P = newP.map { rb[$0]! }; M = newM.map { rb[$0]! }; V = newV.map { rb[$0]! }
            let stepLoss = Double(lossSum / Float(r.accumulation))
            losses.append(stepLoss)
            progress?(TrainingProgress(step: step, steps: r.steps, loss: stepLoss, secondsPerStep: Date().timeIntervalSince(t0) / Double(step)))
        }
        let seconds = Date().timeIntervalSince(t0) / Double(r.steps)
        let trained = try DetectorWeights(parameters: P.enumerated().map { Self.readFloats($0.element, count: counts[$0.offset]) })
        let after = heldOutLoss()
        return TrainingResult(weights: trained, stepLosses: losses, heldOutLossBefore: before, heldOutLossAfter: after,
                              secondsPerStep: seconds, lifetimeMaxFootprintMB: DetectorTraining.lifetimeMaxFootprintMB())
    }
}
