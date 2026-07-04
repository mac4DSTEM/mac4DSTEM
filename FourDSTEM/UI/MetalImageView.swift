//
//  MetalImageView.swift
//  Role: The one SwiftUI ⇄ Metal bridge for displaying images. Wraps an MTKView
//        and renders a single-channel, already-normalized [0,1] float image
//        through MetalEngine's display pipeline (fullscreen triangle + colormap
//        LUT). Both the CBED viewer and the real-space result viewer use it.
//
//  CONTRACT:
//    • `pixels` must already be normalized to [0,1] (callers use
//      DiffractionPattern.normalized / FloatImage.normalized).
//    • `contentVersion` must change whenever `pixels` changes. The Coordinator
//      only re-uploads the GPU texture when the version changes, so panning and
//      zooming (which change every frame) stay cheap.
//    • `zoom` and `offset` come from gestures applied by the parent view.
//

import SwiftUI
import MetalKit

struct MetalImageView: NSViewRepresentable {

    var pixels: [Float]      // normalized [0,1], row-major
    var width: Int
    var height: Int
    var contentVersion: Int
    var colormap: ColormapKind
    var zoom: CGFloat
    var offset: CGSize
    /// When set, the view renders these packed RGBA8 bytes (width×height×4)
    /// through the RGBA pipeline instead of `pixels` + colormap.
    var rgba: [UInt8]? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MetalEngine.shared.device)
        view.colorPixelFormat = .bgra8Unorm           // must match displayPSO
        view.clearColor = MTLClearColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view.framebufferOnly = true
        view.isPaused = true                           // redraw only on demand
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let c = context.coordinator
        c.colormap = colormap
        c.updateContentIfNeeded(pixels: pixels, rgba: rgba,
                                width: width, height: height,
                                version: contentVersion)
        c.zoom = Float(max(zoom, 0.01))
        c.offset = SIMD2<Float>(Float(offset.width), Float(offset.height))
        view.needsDisplay = true
    }

    // MARK: - Coordinator (the MTKView delegate / renderer)

    final class Coordinator: NSObject, MTKViewDelegate {

        var colormap: ColormapKind = .viridis { didSet { lutDirty = true } }
        var zoom: Float = 1
        var offset = SIMD2<Float>(0, 0)

        private var dataTexture: MTLTexture?
        private var rgbaTexture: MTLTexture?
        private var lutTexture: MTLTexture?
        private var lutDirty = true
        private var version = Int.min

        func updateContentIfNeeded(pixels: [Float], rgba: [UInt8]?,
                                   width: Int, height: Int, version v: Int) {
            guard v != version else { return }
            version = v
            guard width > 0, height > 0 else {
                dataTexture = nil
                rgbaTexture = nil
                return
            }
            if let rgba, rgba.count == width * height * 4 {
                rgbaTexture = MetalEngine.shared.device.makeRGBATexture(
                    rgba: rgba, width: width, height: height)
                dataTexture = nil
            } else if pixels.count == width * height {
                dataTexture = MetalEngine.shared.device.makeFloatTexture(
                    pixels: pixels, width: width, height: height)
                rgbaTexture = nil
            } else {
                dataTexture = nil
                rgbaTexture = nil
            }
        }

        private func rebuildLUTIfNeeded() {
            guard lutDirty || lutTexture == nil else { return }
            let rgba = Colormaps.lutRGBA(colormap, count: 256)
            lutTexture = MetalEngine.shared.device.makeLUTTexture(rgba: rgba)
            lutDirty = false
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

        func draw(in view: MTKView) {
            rebuildLUTIfNeeded()

            guard let rpd = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let cb = MetalEngine.shared.queue.makeCommandBuffer(),
                  let enc = cb.makeRenderCommandEncoder(descriptor: rpd)
            else { return }

            // Pick the pipeline for the content we have: pre-colored RGBA, or
            // scalar + LUT. Bail (blank frame) if neither texture exists.
            let engine = MetalEngine.shared
            if rgbaTexture != nil {
                enc.setRenderPipelineState(engine.displayRGBAPSO)
            } else if dataTexture != nil, lutTexture != nil {
                enc.setRenderPipelineState(engine.displayPSO)
            } else {
                enc.endEncoding()
                cb.present(drawable)
                cb.commit()
                return
            }

            // Convert drag (points) to a fraction of the view, so panning feels
            // 1:1. Sign flips so the image follows the cursor. v is flipped in
            // the shader, hence offY is negated relative to offX.
            let w = Float(max(view.bounds.width, 1))
            let h = Float(max(view.bounds.height, 1))
            let offX = -offset.x / w
            let offY =  offset.y / h
            var xform = SIMD4<Float>(zoom, 0, offX, offY)
            enc.setVertexBytes(&xform, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

            if let rgba = rgbaTexture {
                enc.setFragmentTexture(rgba, index: 0)
            } else {
                enc.setFragmentTexture(dataTexture, index: 0)
                enc.setFragmentTexture(lutTexture, index: 1)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cb.present(drawable)
            cb.commit()
        }
    }
}
