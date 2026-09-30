import Foundation
import Metal
import MetalPerformanceShadersGraph
// usage: bisect <f32|f16|bf16> <flags: any of s(silu) k(skip: pool input has a 2nd consumer) b(bias) c(conv) u(unet: pool->conv->up->concat with skip)>
let a = CommandLine.arguments; let f = Set(a[2])
let dt: MPSDataType = a[1] == "bf16" ? .bFloat16 : a[1] == "f16" ? .float16 : .float32
let dev = MTLCreateSystemDefaultDevice()!; let q = dev.makeCommandQueue()!; let gdev = MPSGraphDevice(mtlDevice: dev)
let g = MPSGraph(); let N = 2, C = 4, H = 32
let x = g.placeholder(shape: [NSNumber(value: N), NSNumber(value: C), NSNumber(value: H), NSNumber(value: H)], dataType: .float32, name: "x")
let w = g.placeholder(shape: [NSNumber(value: C), NSNumber(value: C), 3, 3], dataType: .float32, name: "w")
let w2 = g.placeholder(shape: [NSNumber(value: C), NSNumber(value: 2 * C), 3, 3], dataType: .float32, name: "w2")
let bb = g.placeholder(shape: [1, NSNumber(value: C), 1, 1], dataType: .float32, name: "b")
func c(_ t: MPSGraphTensor) -> MPSGraphTensor { dt == .float32 ? t : g.cast(t, to: dt, name: nil) }
let cd = MPSGraphConvolution2DOpDescriptor(strideInX: 1, strideInY: 1, dilationRateInX: 1, dilationRateInY: 1, groups: 1,
    paddingLeft: 1, paddingRight: 1, paddingTop: 1, paddingBottom: 1, paddingStyle: .explicit, dataLayout: .NCHW, weightsLayout: .OIHW)!
var h = c(x)
if f.contains("c") { h = g.convolution2D(h, weights: c(w), descriptor: cd, name: nil) }
if f.contains("b") { h = g.addition(h, c(bb), name: nil) }
if f.contains("s") { h = g.multiplication(h, g.sigmoid(with: h, name: nil), name: nil) }
let pd = MPSGraphPooling2DOpDescriptor(kernelWidth: 2, kernelHeight: 2, strideInX: 2, strideInY: 2, paddingStyle: .TF_VALID, dataLayout: .NCHW)!
var p: MPSGraphTensor
if f.contains("4") {
    let d4 = MPSGraphPooling4DOpDescriptor(kernelSizes: [1, 1, 2, 2], strides: [1, 1, 2, 2], dilationRates: [1, 1, 1, 1],
                                           paddingValues: [0, 0, 0, 0, 0, 0, 0, 0], paddingStyle: .TF_VALID)!
    p = g.maxPooling4D(h, descriptor: d4, name: nil)
} else if f.contains("j") {
    pd.returnIndicesMode = .globalFlatten4D; pd.returnIndicesDataType = .int32
    p = g.maxPooling2DReturnIndices(h, descriptor: pd, name: nil)[0]
} else { p = f.contains("p") && dt != .float32
    ? g.cast(g.maxPooling2D(withSourceTensor: g.cast(h, to: .float32, name: nil), descriptor: pd, name: nil), to: dt, name: nil)
    : g.maxPooling2D(withSourceTensor: h, descriptor: pd, name: nil) }
if f.contains("r") || f.contains("o") || f.contains("v") || f.contains("n") || f.contains("a") || f.contains("i") {
    var t = p
    if f.contains("v") { t = g.convolution2D(t, weights: c(w), descriptor: cd, name: nil) }
    if f.contains("o") { }
    else if f.contains("i") { t = g.resize(t, size: [NSNumber(value: H), NSNumber(value: H)], mode: .bilinear, centerResult: true, alignCorners: false, layout: .NCHW, name: nil) }
    else { t = g.resize(t, size: [NSNumber(value: H), NSNumber(value: H)], mode: .nearest, centerResult: true, alignCorners: false, layout: .NCHW, name: nil) }
    if f.contains("n") { t = g.concatTensors([t, h], dimension: 1, name: nil) }
    if f.contains("a") { t = g.addition(t, h, name: nil) }
    p = t
}
if f.contains("u") {
    let up = g.resize(g.convolution2D(p, weights: c(w), descriptor: cd, name: nil), size: [NSNumber(value: H), NSNumber(value: H)], mode: .nearest,
                      centerResult: true, alignCorners: false, layout: .NCHW, name: nil)
    p = g.convolution2D(g.concatTensors([up, h], dimension: 1, name: nil), weights: c(w2), descriptor: cd, name: nil)
}
var lossIn = dt == .float32 ? p : g.cast(p, to: .float32, name: nil)
var loss = g.reductionSum(with: g.square(with: lossIn, name: nil), axes: [0, 1, 2, 3], name: nil)
if f.contains("k") {
    let hf = dt == .float32 ? h : g.cast(h, to: .float32, name: nil)
    loss = g.addition(loss, g.reductionSum(with: hf, axes: [0, 1, 2, 3], name: nil), name: nil)
}
let wrt = [x] + ((f.contains("c") || f.contains("u") || f.contains("v")) ? [w] : []) + (f.contains("u") ? [w2] : []) + (f.contains("b") ? [bb] : [])
let grads = g.gradients(of: loss, with: wrt, name: nil)
func td(_ t: MPSGraphTensor) -> MPSGraphTensorData {
    let n = t.shape!.reduce(1) { $0 * $1.intValue }; let v = (0 ..< n).map { Float(sin(Double($0) * 0.37)) * 0.3 }
    return v.withUnsafeBytes { MPSGraphTensorData(device: gdev, data: Data($0), shape: t.shape!, dataType: .float32) }
}
let feeds = Dictionary(uniqueKeysWithValues: wrt.map { ($0, td($0)) })
let targets = [loss] + wrt.compactMap { grads[$0] }
let out = g.run(with: q, feeds: feeds, targetTensors: targets, targetOperations: nil)
var l: Float = 0; out[loss]!.mpsndarray().readBytes(&l, strideBytes: nil)
print("OK \(a[1]) \(a[2]) loss=\(l) grads=\(targets.count - 1)")
