//
//  DetectorGraph.swift
//  Role: the learned disk detector's UNet as an MPSGraph, forward and registered loss (a port of
//        `tools/mpsgraph-training-spike`'s `Net`, which passed ADR 048's bar on 2026-09-30: the fp32 forward
//        on the GPU within 0.00272 of the shipped Core ML heatmap, a loss curve equal to the MLX mirror's).
//
//  39 ops as the ADR counts them: 15 convolutions, 14 SiLUs, 3 max-pools, 3 nearest x2 upsamples,
//  3 concats, the head sigmoid. Layout is NCHW / OIHW throughout (the MIL blob's own layout). Parameters are
//  graph placeholders (w0..w14, b0..b13, fp32 masters); with a reduced activation type (bf16) each is cast
//  to it inside the graph so the masters stay fp32 and the head sigmoid and the loss are fp32.
//  The registered loss is mean((1 + 20 t)(p - t)^2) — `train.HeatmapLoss` with miss_weight 20.
//

import Foundation
import MetalPerformanceShadersGraph

package nonisolated struct DetectorGraph {
    let g: MPSGraph
    let w: [MPSGraphTensor], b: [MPSGraphTensor]     // b[0..13]; the head bias is `headB`
    let headB: MPSGraphTensor
    let dt: MPSDataType
    let missWeight: Double

    var params: [MPSGraphTensor] { w + b }

    static func make(_ g: MPSGraph, activations dt: MPSDataType, missWeight: Double = 20) -> DetectorGraph {
        let ph = DetectorWeights.shapes.enumerated().map {
            g.placeholder(shape: $0.element.map { NSNumber(value: $0) }, dataType: .float32, name: "p\($0.offset)")
        }
        let hb = g.constant(Double(DetectorWeights.headBias), shape: [1, 1, 1, 1], dataType: .float32)
        return DetectorGraph(g: g, w: Array(ph[0 ..< 15]), b: Array(ph[15 ..< 29]), headB: hb, dt: dt, missWeight: missWeight)
    }

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
    /// The index-returning pool, output 0 only. Plain `maxPooling2D` segfaults MPSGraph on the M5 Pro / macOS 27.0.1 (26A434) when a
    /// bf16 or f16 pool feeds a convolution and its gradient is taken (null operand encoding PoolMaxGradientOp; Gate D 2026-09-30,
    /// refuter HOLDS). The mode matters: `.globalFlatten2D` still crashes; `.globalFlatten4D` / int32 does not. Same numbers: loss and
    /// all 29 gradients byte-identical to the plain pool in f32, and bf16 ties route to the same (first, raster-order) element.
    private func pool(_ x: MPSGraphTensor) -> MPSGraphTensor {
        let d = MPSGraphPooling2DOpDescriptor(kernelWidth: 2, kernelHeight: 2, strideInX: 2, strideInY: 2,
                                              paddingStyle: .TF_VALID, dataLayout: .NCHW)!
        d.returnIndicesMode = .globalFlatten4D; d.returnIndicesDataType = .int32
        return g.maxPooling2DReturnIndices(x, descriptor: d, name: nil)[0]
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
        let wt = g.addition(g.constant(1, dataType: .float32), g.multiplication(g.constant(missWeight, dataType: .float32), t, name: nil), name: nil)
        let e = g.multiplication(wt, g.square(with: g.subtraction(p, t, name: nil), name: nil), name: nil)
        return g.reshape(g.mean(of: e, axes: [0, 1, 2, 3], name: nil), shape: [1], name: nil)
    }
}
