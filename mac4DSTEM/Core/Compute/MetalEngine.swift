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
package nonisolated struct CubeDims {
    package var ry: UInt32
    package var rx: UInt32
    package var qy: UInt32
    package var qx: UInt32

    package init(_ d: DatasetDescriptor) {
        ry = UInt32(d.ry); rx = UInt32(d.rx)
        qy = UInt32(d.qy); qx = UInt32(d.qx)
    }
}

package nonisolated struct OriginParams {
    package var ry: UInt32
    package var rx: UInt32
    package var qy: UInt32
    package var qx: UInt32
    package var r: Float         // probe radius estimate (px)
    package var rscale: Float    // CoM window = max(r * rscale, r + 1.5 px); see OriginMeasure.metal

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(ry: UInt32, rx: UInt32, qy: UInt32, qx: UInt32, r: Float, rscale: Float) {
        self.ry = ry
        self.rx = rx
        self.qy = qy
        self.qx = qx
        self.r = r
        self.rscale = rscale
    }
}

package enum MetalError: LocalizedError {
    case noDevice
    case noLibrary
    case functionMissing(String)
    case dispatchFailed(String)
    package var errorDescription: String? {
        switch self {
        case .noDevice: return "No Metal-capable GPU was found."
        case .noLibrary: return "Could not load the compiled Metal shader library (default.metallib)."
        case .functionMissing(let n): return "Metal function '\(n)' was not found in the library."
        case .dispatchFailed(let n): return "GPU dispatch '\(n)' failed."
        }
    }
}

// MARK: - MetalEngine

package nonisolated final class MetalEngine {

    package static let shared = MetalEngine()

    package let device: MTLDevice
    package let queue: MTLCommandQueue
    package let library: MTLLibrary

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    package let displayPSO: MTLRenderPipelineState
    package let displayRGBAPSO: MTLRenderPipelineState

    // Compute pipelines, built eagerly in init (each compiles its own shader).
    // They were `lazy var` until 2026-10-07: the engine is `nonisolated` and
    // reached from several detached jobs, and a `lazy var` first touched by
    // two of them at once is a data race. Immutable `let`s built once under
    // the `static let shared` initialiser (thread-safe) have no such window.
    //
    // try? OK (v2 S7 audit): the functions are compiled into the bundled
    // metallib at build time, so a nil here means the pipeline genuinely
    // cannot be built on this GPU. nil is the stored contract — both
    // PSOs are consumed only inside this file, and every consumer guards
    // its own and THROWS `MetalError.functionMissing` naming the shader
    // rather than computing without it; a `try?` here only defers that
    // named refusal from init time to first use.
    package let virtualDiffractionPSO: MTLComputePipelineState?
    package let measureOriginPSO: MTLComputePipelineState?

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

        // Compute pipelines (nil stays the stored contract, see above).
        func compute(_ name: String) -> MTLComputePipelineState? {
            guard let fn = lib.makeFunction(name: name) else { return nil }
            return try? dev.makeComputePipelineState(function: fn)
        }
        self.virtualDiffractionPSO = compute("virtualDiffraction")
        self.measureOriginPSO = compute("measureOrigin")

        print("[MetalEngine] GPU: \(dev.name), maxWorkingSet ≈ \(dev.recommendedMaxWorkingSetSize / 1_048_576) MB")
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
    // Only the two kernels below take it. The virtual image, the mean and max patterns and the centre of
    // mass are CuboKit's (`VirtualImaging`, `VirtualDiffraction`, `CenterOfMass`: Metal reducers, 0.6.0).

    // MARK: Dispatch — Virtual (selected-area) diffraction

    /// Sum every scan position selected by `scanMask` into one [Qy*Qx] pattern
    /// — the reciprocal of virtualImage. `scanMask` is row-major [Ry*Rx].
    package func virtualDiffraction(cube: MTLBuffer, cubeOffset: Int = 0,
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

    // MARK: Dispatch — Origin measurement (calibration)

    /// Measure the (000)-beam position of every pattern: coarse brightest-blob
    /// search at the probe-radius scale, then windowed CoM refinement
    /// (py4DSTEM get_origin). Returns interleaved [x0, y0] per scan position.
    package func measureOrigins(cube: MTLBuffer, cubeOffset: Int = 0,
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
