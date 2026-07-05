//
//  MetalEngine.swift
//  Role: The one place that owns the GPU — MTLDevice, command queue, the
//        compiled shader library, and the render pipelines used by
//        MetalImageView to draw images.
//
//  MIGRATION NOTE: this is the display-only slice. Compute pipelines
//  (virtual detector, CoM/DPC, DP statistics, origin measurement) and their
//  parameter structs come back with their feature slices — each adds its
//  `MTLComputePipelineState` here, ideally lazily so it only forces its own
//  shader to exist in the metallib.
//

import Metal
import MetalKit

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

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    let displayPSO: MTLRenderPipelineState
    let displayRGBAPSO: MTLRenderPipelineState

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
}
