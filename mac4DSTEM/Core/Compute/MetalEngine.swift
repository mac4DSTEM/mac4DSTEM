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
    private(set) lazy var virtualAperturePSO: MTLComputePipelineState? = {
        try? makeCompute("virtualAperture")
    }()
    private(set) lazy var virtualMaskPSO: MTLComputePipelineState? = {
        try? makeCompute("virtualMaskSum")
    }()

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
