//
//  MetalEngine.swift
//  Role: The one place that owns the GPU. Holds MTLDevice, command queue, the
//        compiled shader library, and every MTLComputePipelineState / render
//        pipeline. Exposes high-level dispatch methods used by the Analysis
//        layer (virtual imaging, CoM/DPC, DP statistics, origin measurement)
//        and the display pipeline used by MetalImageView.
//
//  PARAM STRUCT CONTRACT: the small structs below are passed to shaders via
//  `setBytes`. They MUST stay byte-for-byte identical to the structs declared
//  in the matching .metal files. All fields are 4-byte (Float / UInt32) so
//  layout is identical and predictable on both sides. If you edit one, edit
//  the other.
//

import Metal
import MetalKit

// MARK: - Shared parameter structs (mirror the .metal definitions!)

/// Cube shape only — used by kernels that need no further parameters
/// (dpStatistics, virtualMaskSum).
struct CubeDims {
    var ry: UInt32
    var rx: UInt32
    var qy: UInt32
    var qx: UInt32

    init(_ d: DatasetDescriptor) {
        ry = UInt32(d.ry); rx = UInt32(d.rx)
        qy = UInt32(d.qy); qx = UInt32(d.qx)
    }
}

struct ApertureParams {
    var ry: UInt32
    var rx: UInt32
    var qy: UInt32
    var qx: UInt32
    var cx: Float        // detector center (column), in pixels
    var cy: Float        // detector center (row), in pixels
    var rInner: Float    // annulus inner radius (px)
    var rOuter: Float    // annulus outer radius (px)
}

struct CoMParams {
    var ry: UInt32
    var rx: UInt32
    var qy: UInt32
    var qx: UInt32
    var cx: Float        // global reference center (used when useOrigins == 0)
    var cy: Float
    var useOrigins: UInt32
}

struct OriginParams {
    var ry: UInt32
    var rx: UInt32
    var qy: UInt32
    var qx: UInt32
    var r: Float         // probe radius estimate (px)
    var rscale: Float    // CoM window = r * rscale
}

enum MetalError: LocalizedError {
    case noDevice
    case noLibrary
    case functionMissing(String)
    case dispatchFailed(String)
    var errorDescription: String? {
        switch self {
        case .noDevice: return "No Metal-capable GPU was found."
        case .noLibrary: return "Could not load the compiled Metal shader library (default.metallib)."
        case .functionMissing(let n): return "Metal function '\(n)' was not found in the library."
        case .dispatchFailed(let n): return "GPU dispatch '\(n)' failed."
        }
    }
}

// MARK: - MetalEngine

final class MetalEngine {

    static let shared = MetalEngine()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    // Compute pipelines built eagerly (needed by Stage-1 features + display).
    let virtualAperturePSO: MTLComputePipelineState
    let virtualMaskPSO: MTLComputePipelineState
    let centerOfMassPSO: MTLComputePipelineState
    let dpStatisticsPSO: MTLComputePipelineState
    let measureOriginPSO: MTLComputePipelineState

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    let displayPSO: MTLRenderPipelineState
    let displayRGBAPSO: MTLRenderPipelineState

    // ACOM template-match pipeline is built lazily on first use (Stage 2).
    private(set) lazy var templateMatchPSO: MTLComputePipelineState? = {
        try? makeCompute("templateMatch")
    }()

    /// Bound in place of optional buffers a kernel will not read
    /// (Metal validation requires every referenced slot to have a binding).
    private let placeholderBuffer: MTLBuffer

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError(MetalError.noDevice.localizedDescription)
        }
        guard let q = dev.makeCommandQueue() else {
            fatalError("Could not create a Metal command queue.")
        }
        // All .metal files compile into the bundle's default.metallib.
        guard let lib = dev.makeDefaultLibrary() else {
            fatalError(MetalError.noLibrary.localizedDescription)
        }
        self.device = dev
        self.queue = q
        self.library = lib
        self.placeholderBuffer = dev.makeBuffer(length: 16, options: .storageModePrivate)!

        func compute(_ name: String) -> MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                fatalError(MetalError.functionMissing(name).localizedDescription)
            }
            do { return try dev.makeComputePipelineState(function: fn) }
            catch { fatalError("Pipeline build failed for \(name): \(error)") }
        }
        self.virtualAperturePSO = compute("virtualAperture")
        self.virtualMaskPSO = compute("virtualMaskSum")
        self.centerOfMassPSO = compute("centerOfMass")
        self.dpStatisticsPSO = compute("dpStatistics")
        self.measureOriginPSO = compute("measureOrigin")

        // Display render pipelines (fullscreen triangle; LUT and RGBA fragments).
        func display(fragment: String) -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "displayVertex")
            desc.fragmentFunction = lib.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm   // MTKView default
            do { return try dev.makeRenderPipelineState(descriptor: desc) }
            catch { fatalError("Display pipeline (\(fragment)) build failed: \(error)") }
        }
        self.displayPSO = display(fragment: "colormapFragment")
        self.displayRGBAPSO = display(fragment: "rgbaFragment")

        print("[MetalEngine] GPU: \(dev.name), maxWorkingSet ≈ \(dev.recommendedMaxWorkingSetSize / 1_048_576) MB")
    }

    private func makeCompute(_ name: String) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else { throw MetalError.functionMissing(name) }
        return try device.makeComputePipelineState(function: fn)
    }

    // MARK: Dispatch — Virtual Detector (analytic annulus, interactive path)

    /// Sum detector intensity within the annulus for every scan position.
    /// Returns the real-space image as [Ry*Rx] row-major Float.
    /// (Synchronous + waitUntilCompleted — call from a background Task.)
    func virtualDetector(cube: MTLBuffer, params: ApertureParams) throws -> [Float] {
        let n = Int(params.ry) * Int(params.rx)
        let out = try makeOutputBuffer(floats: n, label: "virtualAperture")
        var p = params
        try run(virtualAperturePSO, name: "virtualAperture",
                width: Int(params.rx), height: Int(params.ry)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(out, offset: 0, index: 1)
            enc.setBytes(&p, length: MemoryLayout<ApertureParams>.stride, index: 2)
        }
        return arrayFromBuffer(out, count: n)
    }

    // MARK: Dispatch — Virtual Detector (arbitrary mask)

    /// Sum pattern × mask for every scan position. `mask` is a row-major
    /// [Qy*Qx] detector-space weight image (see VirtualDetector.makeMask).
    func virtualImage(cube: MTLBuffer, dims: CubeDims, mask: [Float]) throws -> [Float] {
        let n = Int(dims.ry) * Int(dims.rx)
        precondition(mask.count == Int(dims.qy) * Int(dims.qx), "mask must be Qy*Qx")
        let out = try makeOutputBuffer(floats: n, label: "virtualMaskSum")
        guard let maskBuf = device.makeBuffer(bytes: mask,
                                              length: mask.count * MemoryLayout<Float>.stride,
                                              options: .storageModeShared)
        else { throw MetalError.dispatchFailed("virtualMaskSum: mask buffer") }
        var d = dims
        try run(virtualMaskPSO, name: "virtualMaskSum",
                width: Int(dims.rx), height: Int(dims.ry)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(maskBuf, offset: 0, index: 1)
            enc.setBuffer(out, offset: 0, index: 2)
            enc.setBytes(&d, length: MemoryLayout<CubeDims>.stride, index: 3)
        }
        return arrayFromBuffer(out, count: n)
    }

    // MARK: Dispatch — Center of Mass (DPC)

    /// Compute the CoM shift (Qx, Qy) for every scan position, relative to
    /// per-position `origins` (interleaved [x,y], from calibration) when
    /// given, else relative to the global (cx, cy) in `params`.
    /// Returns interleaved [comx0, comy0, comx1, comy1, ...] of length 2*Ry*Rx.
    func centerOfMass(cube: MTLBuffer, params: CoMParams, origins: [Float]? = nil) throws -> [Float] {
        let n = Int(params.ry) * Int(params.rx)
        let out = try makeOutputBuffer(floats: n * 2, label: "centerOfMass")

        var p = params
        var originsBuf = placeholderBuffer
        if let origins {
            precondition(origins.count == n * 2, "origins must be 2*Ry*Rx interleaved")
            guard let b = device.makeBuffer(bytes: origins,
                                            length: origins.count * MemoryLayout<Float>.stride,
                                            options: .storageModeShared)
            else { throw MetalError.dispatchFailed("centerOfMass: origins buffer") }
            originsBuf = b
            p.useOrigins = 1
        } else {
            p.useOrigins = 0
        }

        try run(centerOfMassPSO, name: "centerOfMass",
                width: Int(params.rx), height: Int(params.ry)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(out, offset: 0, index: 1)
            enc.setBytes(&p, length: MemoryLayout<CoMParams>.stride, index: 2)
            enc.setBuffer(originsBuf, offset: 0, index: 3)
        }
        return arrayFromBuffer(out, count: n * 2)
    }

    // MARK: Dispatch — Diffraction statistics (max / mean pattern)

    /// Max and mean over all scan positions, per detector pixel.
    /// Both are [Qy*Qx] row-major (py4DSTEM: get_dp_max / get_dp_mean).
    func dpStatistics(cube: MTLBuffer, dims: CubeDims) throws -> (maxDP: [Float], meanDP: [Float]) {
        let n = Int(dims.qy) * Int(dims.qx)
        let outMax = try makeOutputBuffer(floats: n, label: "dpStatistics.max")
        let outMean = try makeOutputBuffer(floats: n, label: "dpStatistics.mean")
        var d = dims
        try run(dpStatisticsPSO, name: "dpStatistics",
                width: Int(dims.qx), height: Int(dims.qy)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(outMax, offset: 0, index: 1)
            enc.setBuffer(outMean, offset: 0, index: 2)
            enc.setBytes(&d, length: MemoryLayout<CubeDims>.stride, index: 3)
        }
        return (arrayFromBuffer(outMax, count: n), arrayFromBuffer(outMean, count: n))
    }

    // MARK: Dispatch — Origin measurement (calibration)

    /// Measure the (000)-beam position of every pattern: coarse brightest-blob
    /// search at the probe-radius scale, then windowed CoM refinement
    /// (py4DSTEM get_origin). Returns interleaved [x0, y0] per scan position.
    func measureOrigins(cube: MTLBuffer, params: OriginParams) throws -> [Float] {
        let n = Int(params.ry) * Int(params.rx)
        let out = try makeOutputBuffer(floats: n * 2, label: "measureOrigin")
        var p = params
        try run(measureOriginPSO, name: "measureOrigin",
                width: Int(params.rx), height: Int(params.ry)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(out, offset: 0, index: 1)
            enc.setBytes(&p, length: MemoryLayout<OriginParams>.stride, index: 2)
        }
        return arrayFromBuffer(out, count: n * 2)
    }

    // MARK: Helpers

    /// Encode, dispatch over a width×height grid, and block until done.
    /// All analysis dispatches funnel through here so command-buffer setup,
    /// error handling, and the threadgroup math live in one place.
    private func run(_ pso: MTLComputePipelineState, name: String,
                     width: Int, height: Int,
                     encode: (MTLComputeCommandEncoder) -> Void) throws {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { throw MetalError.dispatchFailed("\(name): encoder") }

        enc.setComputePipelineState(pso)
        encode(enc)
        dispatch2D(enc, pipeline: pso, width: width, height: height)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw MetalError.dispatchFailed("\(name): \(e)") }
    }

    private func makeOutputBuffer(floats n: Int, label: String) throws -> MTLBuffer {
        guard let buf = device.makeBuffer(length: n * MemoryLayout<Float>.stride,
                                          options: .storageModeShared)
        else { throw MetalError.dispatchFailed("\(label): output buffer") }
        buf.label = label
        return buf
    }

    private func dispatch2D(_ enc: MTLComputeCommandEncoder,
                            pipeline: MTLComputePipelineState,
                            width: Int, height: Int) {
        // SIMD width on Apple Silicon is 32; pick a 2D group that fits.
        let w = min(pipeline.threadExecutionWidth, width)
        let h = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / w, height))
        let tg = MTLSize(width: w, height: h, depth: 1)
        if device.supportsFamily(.apple4) {
            // Non-uniform threadgroups: dispatch exact grid, GPU handles edges.
            enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: tg)
        } else {
            let groups = MTLSize(width: (width + w - 1) / w,
                                 height: (height + h - 1) / h, depth: 1)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        }
    }

    private func arrayFromBuffer(_ buf: MTLBuffer, count: Int) -> [Float] {
        let ptr = buf.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}
