import CoreML
import Foundation
@main struct Main { static func main() async throws {
let pkg = URL(fileURLWithPath: CommandLine.arguments[1])
let compiled = try await MLModel.compileModel(at: pkg)
let cfg = MLModelConfiguration(); cfg.computeUnits = .all
let plan = try await MLComputePlan.load(contentsOf: compiled, configuration: cfg)
var counts: [String: Int] = [:]
if case .program(let prog) = plan.modelStructure, let main = prog.functions["main"] {
    for op in main.block.operations {
        guard let u = plan.deviceUsage(for: op) else { counts["none", default: 0] += 1; continue }
        let d: String
        switch u.preferred { case .cpu: d = "cpu"; case .gpu: d = "gpu"; case .neuralEngine: d = "ane"; @unknown default: d = "?" }
        counts["\(op.operatorName)@\(d)", default: 0] += 1
        counts["TOTAL@\(d)", default: 0] += 1
    }
}
for (k, v) in counts.sorted(by: { $0.key < $1.key }) where k.hasPrefix("TOTAL") { print(k, v) }
print("devices:", MLComputeDevice.allComputeDevices)
// heatmaps under three compute-unit settings, same input
let inShape: [NSNumber] = [32, 3, 256, 256]
let x = try MLMultiArray(shape: inShape, dataType: .float16)
let n = x.count
x.withUnsafeMutableBytes { p, _ in let f = p.bindMemory(to: Float16.self); for i in 0 ..< n { f[i] = Float16(abs(sin(Double(i) * 0.0137)) ) } }
var maps: [String: [Float]] = [:]
for (name, cu) in [("all", MLComputeUnits.all), ("cpuAndNE", .cpuAndNeuralEngine), ("cpuAndGPU", .cpuAndGPU), ("cpuOnly", .cpuOnly)] {
    let c = MLModelConfiguration(); c.computeUnits = cu
    let m = try await MLModel.load(contentsOf: compiled, configuration: c)
    let t0 = Date()
    let out = try await m.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": MLFeatureValue(multiArray: x)]))
    let h = out.featureValue(for: "heatmap")!.multiArrayValue!
    var v = [Float](repeating: 0, count: h.count)
    if h.dataType == .float16 { h.withUnsafeBytes { p in let f = p.bindMemory(to: Float16.self); for i in 0 ..< v.count { v[i] = Float(f[i]) } } }
    else { for i in 0 ..< v.count { v[i] = h[i].floatValue } }
    maps[name] = v; print(name, "dtype", h.dataType.rawValue, "secs", Date().timeIntervalSince(t0))
}
for a in ["all"] { for b in ["cpuAndNE", "cpuAndGPU", "cpuOnly"] {
    let d = zip(maps[a]!, maps[b]!).map { abs($0 - $1) }; print("max|\(a)-\(b)| =", d.max()!, " identical:", d.allSatisfy { $0 == 0 })
} }
let d = zip(maps["cpuAndNE"]!, maps["cpuAndGPU"]!).map { abs($0 - $1) }; print("max|NE-GPU| =", d.max()!)
} }
