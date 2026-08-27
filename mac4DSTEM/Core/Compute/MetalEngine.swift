//
//  MetalEngine.swift
//  Role: The one place that owns the GPU — MTLDevice, command queue, the
//        compiled shader library, the render pipelines used by MetalImageView,
//        and the compute pipelines used by the Analysis layer.
//
//  ISOLATION: marked `nonisolated` so it is NOT bound to the project's default
//  MainActor isolation. GPU dispatches block on waitUntilCompleted, so they
//  must run on background tasks — this lets AppState call them from
//  Task.detached without hopping back to the main actor.
//
//  PARAM STRUCT CONTRACT: the structs below are passed to shaders via
//  `setBytes`. They MUST stay byte-for-byte identical to the structs in the
//  matching .metal files. All fields are 4-byte (Float / UInt32).
//
//  MIGRATION NOTE: compute pipelines are added per feature slice and built
//  lazily, so each only forces its own shader to exist in the metallib.
//

import Metal
import MetalKit

// MARK: - Shared parameter structs (mirror the .metal definitions!)

/// Cube shape only — used by kernels that need no further parameters.
nonisolated struct CubeDims {
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

nonisolated final class MetalEngine {

    static let shared = MetalEngine()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    let displayPSO: MTLRenderPipelineState
    let displayRGBAPSO: MTLRenderPipelineState

    // Compute pipelines, built lazily on first use (each forces its own shader).
    //
    // try? OK (v2 S7 audit): the functions are compiled into the bundled
    // metallib at build time, so a nil here means the pipeline genuinely
    // cannot be built on this GPU. nil is the stored contract — all six
    // PSOs are consumed only inside this file, and every consumer guards
    // its own and THROWS `MetalError.functionMissing` naming the shader
    // rather than computing without it; a `try?` here only defers that
    // named refusal from init time to first use.
    private(set) lazy var virtualAperturePSO: MTLComputePipelineState? = {
        try? makeCompute("virtualAperture")
    }()
    private(set) lazy var virtualMaskPSO: MTLComputePipelineState? = {
        try? makeCompute("virtualMaskSum")
    }()
    private(set) lazy var virtualDiffractionPSO: MTLComputePipelineState? = {
        try? makeCompute("virtualDiffraction")
    }()
    private(set) lazy var dpStatisticsPSO: MTLComputePipelineState? = {
        try? makeCompute("dpStatistics")
    }()
    private(set) lazy var measureOriginPSO: MTLComputePipelineState? = {
        try? makeCompute("measureOrigin")
    }()
    private(set) lazy var centerOfMassPSO: MTLComputePipelineState? = {
        try? makeCompute("centerOfMass")
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
        guard let pso = virtualAperturePSO else { throw MetalError.functionMissing("virtualAperture") }
        let n = Int(params.ry) * Int(params.rx)
        let out = try makeOutputBuffer(floats: n, label: "virtualAperture")
        var p = params
        try run(pso, name: "virtualAperture",
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
        guard let pso = virtualMaskPSO else { throw MetalError.functionMissing("virtualMaskSum") }
        let n = Int(dims.ry) * Int(dims.rx)
        precondition(mask.count == Int(dims.qy) * Int(dims.qx), "mask must be Qy*Qx")
        let out = try makeOutputBuffer(floats: n, label: "virtualMaskSum")
        guard let maskBuf = device.makeBuffer(bytes: mask,
                                              length: mask.count * MemoryLayout<Float>.stride,
                                              options: .storageModeShared)
        else { throw MetalError.dispatchFailed("virtualMaskSum: mask buffer") }
        var d = dims
        try run(pso, name: "virtualMaskSum",
                width: Int(dims.rx), height: Int(dims.ry)) { enc in
            enc.setBuffer(cube, offset: 0, index: 0)
            enc.setBuffer(maskBuf, offset: 0, index: 1)
            enc.setBuffer(out, offset: 0, index: 2)
            enc.setBytes(&d, length: MemoryLayout<CubeDims>.stride, index: 3)
        }
        return arrayFromBuffer(out, count: n)
    }

    // MARK: Dispatch — tiled passes over a resident cube
    //
    // `cubeOffset` is a BYTE offset into `cube` at which this dispatch's
    // sub-cube starts, so a tiled caller holding a resident cube can bind the
    // cube's own bytes in place instead of copying a tile out to `[Float]` and
    // back into a fresh MTLBuffer (~0.375 x working set of pure staging waste,
    // found by adversarial review 2026-08-17, eliminated in v2 S18). `dims` /
    // `params` still describe the SUB-cube, exactly as they described the
    // per-tile copy — the kernels index from the bound base address, so the
    // arithmetic is unchanged and the results are bit-identical to the copying
    // path. Offsets are whole scan rows (`rx * qy * qx * 4` bytes), so the
    // 4-byte `device`-address-space alignment Metal requires is automatic.
    //
    // Only the four reducers below take it. `virtualDetector` / `virtualImage`
    // do not: their tiled caller already has a whole-cube resident fast path.

    // MARK: Dispatch — Virtual (selected-area) diffraction

    /// Sum every scan position selected by `scanMask` into one [Qy*Qx] pattern
    /// — the reciprocal of virtualImage. `scanMask` is row-major [Ry*Rx].
    func virtualDiffraction(cube: MTLBuffer, cubeOffset: Int = 0,
                            dims: CubeDims, scanMask: [Float]) throws -> [Float] {
        guard let pso = virtualDiffractionPSO else { throw MetalError.functionMissing("virtualDiffraction") }
        let n = Int(dims.qy) * Int(dims.qx)
        precondition(scanMask.count == Int(dims.ry) * Int(dims.rx), "scanMask must be Ry*Rx")
        let out = try makeOutputBuffer(floats: n, label: "virtualDiffraction")
        guard let maskBuf = device.makeBuffer(bytes: scanMask,
                                              length: scanMask.count * MemoryLayout<Float>.stride,
                                              options: .storageModeShared)
        else { throw MetalError.dispatchFailed("virtualDiffraction: mask buffer") }
        var d = dims
        try run(pso, name: "virtualDiffraction",
                width: Int(dims.qx), height: Int(dims.qy)) { enc in
            enc.setBuffer(cube, offset: cubeOffset, index: 0)
            enc.setBuffer(maskBuf, offset: 0, index: 1)
            enc.setBuffer(out, offset: 0, index: 2)
            enc.setBytes(&d, length: MemoryLayout<CubeDims>.stride, index: 3)
        }
        return arrayFromBuffer(out, count: n)
    }

    // MARK: Dispatch — Diffraction statistics (max / mean pattern)

    /// Max and mean over all scan positions, per detector pixel.
    /// Both are [Qy*Qx] row-major (py4DSTEM: get_dp_max / get_dp_mean).
    func dpStatistics(cube: MTLBuffer, cubeOffset: Int = 0,
                      dims: CubeDims) throws -> (maxDP: [Float], meanDP: [Float]) {
        guard let pso = dpStatisticsPSO else { throw MetalError.functionMissing("dpStatistics") }
        let n = Int(dims.qy) * Int(dims.qx)
        let outMax = try makeOutputBuffer(floats: n, label: "dpStatistics.max")
        let outMean = try makeOutputBuffer(floats: n, label: "dpStatistics.mean")
        var d = dims
        try run(pso, name: "dpStatistics",
                width: Int(dims.qx), height: Int(dims.qy)) { enc in
            enc.setBuffer(cube, offset: cubeOffset, index: 0)
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
    func measureOrigins(cube: MTLBuffer, cubeOffset: Int = 0,
                        params: OriginParams) throws -> [Float] {
        guard let pso = measureOriginPSO else { throw MetalError.functionMissing("measureOrigin") }
        let n = Int(params.ry) * Int(params.rx)
        let out = try makeOutputBuffer(floats: n * 2, label: "measureOrigin")
        var p = params
        try run(pso, name: "measureOrigin",
                width: Int(params.rx), height: Int(params.ry)) { enc in
            enc.setBuffer(cube, offset: cubeOffset, index: 0)
            enc.setBuffer(out, offset: 0, index: 1)
            enc.setBytes(&p, length: MemoryLayout<OriginParams>.stride, index: 2)
        }
        return arrayFromBuffer(out, count: n * 2)
    }

    // MARK: Dispatch — Center of Mass (DPC / rotation calibration)

    /// CoM shift (Qx, Qy) per scan position, relative to per-position
    /// `origins` (interleaved [x,y]) when given, else the global (cx, cy).
    /// Returns interleaved [comx0, comy0, ...] of length 2*Ry*Rx.
    func centerOfMass(cube: MTLBuffer, cubeOffset: Int = 0,
                      params: CoMParams, origins: [Float]? = nil) throws -> [Float] {
        guard let pso = centerOfMassPSO else { throw MetalError.functionMissing("centerOfMass") }
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

        try run(pso, name: "centerOfMass",
                width: Int(params.rx), height: Int(params.ry)) { enc in
            enc.setBuffer(cube, offset: cubeOffset, index: 0)
            enc.setBuffer(out, offset: 0, index: 1)
            enc.setBytes(&p, length: MemoryLayout<CoMParams>.stride, index: 2)
            enc.setBuffer(originsBuf, offset: 0, index: 3)
        }
        return arrayFromBuffer(out, count: n * 2)
    }

    // MARK: Helpers

    /// Encode, dispatch over a width×height grid, and block until done.
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
