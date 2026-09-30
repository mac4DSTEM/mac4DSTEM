import CoreML
import Foundation
func planCounts(_ compiled: URL, _ cu: MLComputeUnits) async throws -> [String: Int] {
    let cfg = MLModelConfiguration(); cfg.computeUnits = cu
    let plan = try await MLComputePlan.load(contentsOf: compiled, configuration: cfg)
    var counts: [String: Int] = [:]
    if case .program(let prog) = plan.modelStructure, let main = prog.functions["main"] {
        for op in main.block.operations {
            guard let u = plan.deviceUsage(for: op) else { counts["none", default: 0] += 1; continue }
            switch u.preferred { case .cpu: counts["cpu", default: 0] += 1; case .gpu: counts["gpu", default: 0] += 1
            case .neuralEngine: counts["ane", default: 0] += 1; @unknown default: counts["?", default: 0] += 1 }
        }
    }
    return counts
}
func input(batch: Int, real: Int) throws -> MLMultiArray {
    let x = try MLMultiArray(shape: [NSNumber(value: batch), 3, 256, 256], dataType: .float16)
    let per = 3 * 256 * 256
    x.withUnsafeMutableBytes { p, _ in let f = p.bindMemory(to: Float16.self)
        for i in 0 ..< batch * per { f[i] = i < real * per ? Float16(abs(sin(Double(i) * 0.0137))) : 0 } }
    return x
}
func run(_ m: MLModel, _ x: MLMultiArray) async throws -> ([UInt16], Double) {
    let t0 = Date()
    let out = try await m.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": MLFeatureValue(multiArray: x)]))
    let dt = Date().timeIntervalSince(t0)
    let h = out.featureValue(for: "heatmap")!.multiArrayValue!
    precondition(h.dataType == .float16)
    var v = [UInt16](repeating: 0, count: h.count)
    h.withUnsafeBytes { p in let f = p.bindMemory(to: UInt16.self); for i in 0 ..< v.count { v[i] = f[i] } }
    return (v, dt)
}
func load(_ compiled: URL, _ cu: MLComputeUnits) async throws -> MLModel {
    let c = MLModelConfiguration(); c.computeUnits = cu
    return try await MLModel.load(contentsOf: compiled, configuration: c)
}
@main struct Main { static func main() async throws {
    let compiled = try await MLModel.compileModel(at: URL(fileURLWithPath: CommandLine.arguments[1]))
    for (n, cu) in [("all", MLComputeUnits.all), ("cpuAndNE", .cpuAndNeuralEngine), ("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly)] {
        print("plan", n, try await planCounts(compiled, cu).sorted { $0.key < $1.key })
    }
    let ne = try await load(compiled, .cpuAndNeuralEngine), cpu = try await load(compiled, .cpuOnly), all = try await load(compiled, .all)
    for (batch, real) in [(32, 32), (32, 16), (32, 1), (16, 16), (1, 1), (31, 31), (33, 33), (64, 64)] {
        let x = try input(batch: batch, real: real)
        _ = try await run(ne, x)   // warm
        let (a, ta) = try await run(ne, x), (a2, _) = try await run(ne, x), (c, tc) = try await run(cpu, x)
        let (g, tg) = try await run(all, x)
        let per = 256 * 256, n = real * per
        let diff = (0 ..< n).filter { a[$0] != c[$0] }.count
        print("batch \(batch) real \(real): NE==cpuOnly bitwise \(a == c)  differing px in real part \(diff)/\(n)  NE repeat identical \(a == a2)  all==NE \(g == a) all==cpu \(g == c)  ms NE \(Int(ta * 1000)) cpu \(Int(tc * 1000)) all \(Int(tg * 1000))")
    }
    let ne2 = try await load(compiled, .cpuAndNeuralEngine)
    let x = try input(batch: 32, real: 32)
    let (a, _) = try await run(ne, x), (b, _) = try await run(ne2, x)
    print("fresh load identical:", a == b)
} }
