//
//  MetalImageView.swift
//  Role: The one SwiftUI ⇄ Metal bridge for displaying images. Wraps an MTKView
//        and renders a single-channel, already-normalized [0,1] float image
//        through MetalEngine's display pipeline (fullscreen triangle + colormap
//        LUT). Both the CBED viewer and the real-space result viewer use it.
//
//  CONTRACT:
//    • `pixels` must already be normalized to [0,1] (callers use
//      DiffractionPattern.normalized / FloatImage.normalized). Invalid
//      (masked) pixels are the negative FloatImage.invalidDisplayValue
//      sentinel; the fragment shader renders them as neutral gray.
//    • `contentVersion` must change whenever `pixels` changes. The Coordinator
//      only re-uploads the GPU texture when the version changes, so panning and
//      zooming (which change every frame) stay cheap.
//    • `zoom` and `offset` come from gestures applied by the parent view.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import MetalKit

struct MetalImageView: NSViewRepresentable {

    /// A version derived from the pixel VALUES *and* the dimensions, for call
    /// sites whose pixels can change without their shape changing (the old
    /// dims-only hashes let a same-shape swap keep a stale texture — invisible
    /// until a view shows a *chosen* image, which the single-DP picker is).
    /// Dimensions are folded in because `updateContentIfNeeded` short-circuits
    /// on the version BEFORE it looks at width/height — identical pixels at
    /// transposed dimensions must still re-upload.
    ///
    /// O(n) FNV-1a — call it where the pixels are PRODUCED (once per image,
    /// e.g. `PendingLoad.DisplayImage`), never per body evaluation. // v2 S4
    nonisolated static func contentVersion(of pixels: [Float], width: Int, height: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        hash = (hash ^ UInt64(truncatingIfNeeded: width)) &* 0x0000_0100_0000_01b3
        hash = (hash ^ UInt64(truncatingIfNeeded: height)) &* 0x0000_0100_0000_01b3
        for value in pixels {
            hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

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
    /// Display contrast window in normalized [0,1] intensity (histogram
    /// clipping). Applied in the fragment shader — cheap, per-frame.
    var displayLo: Float = 0
    var displayHi: Float = 1
    var gamma: Float = 1

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// An `MTKView` that keeps its layer's `contentsScale` in step with the
    /// window it is in.
    ///
    /// WHY THIS EXISTS (F1.3b, measured 2026-08-27). Inside SwiftUI's sheet the
    /// hosted `MTKView`'s `CAMetalLayer` is left at **`contentsScale == 0`**,
    /// and a layer at scale 0 cannot display a drawable — so the pane stays
    /// exactly the background colour.
    ///
    /// **What writes the 0 is NOT identified, and the obvious guess is wrong.**
    /// A detached `MTKView(frame: .zero, device:)` created exactly as below
    /// reads `contentsScale == 1.0`, not 0 — measured on this machine by the
    /// Gate B second reader, refuting this comment's original "created outside
    /// a window comes up with 0". The 0 was only ever observed on a view
    /// ALREADY in its window, hosted by `AppKitPlatformViewHost`. This repair
    /// therefore targets an observed state whose producer is still unknown,
    /// which is why the `!=` guard below matters — it must not fight whatever
    /// does the writing.
    ///
    /// That scale 0 is the CAUSE and not a bystander was established
    /// separately, outside this app: three plain-AppKit `MTKView`s encoding the
    /// same clear pass render normally at the default and at a deliberately
    /// WRONG-but-nonzero 1.0, and render exactly the window background at 0.
    ///
    /// Every internal signal looks healthy while this is happening, which is
    /// why it survived three rounds of diagnosis: `drawableSize` is correct
    /// (`MTKView` derives it from the WINDOW's backing scale, not from the
    /// layer's `contentsScale`), the render-pass descriptor and
    /// `currentDrawable` are non-nil, the data texture is uploaded, and the
    /// frame is encoded and presented. Measured on the configurator sheet
    /// (in ONE instrumented cold open — the only run in which the value was
    /// read): the two blank panes' layers read `contentsScale = 0.0` against a
    /// window `backingScaleFactor` of 2.0, while the pane that rendered
    /// read 2.0.
    ///
    /// It is intermittent by nature: a host created at a moment when AppKit
    /// happens to have propagated backing properties gets 2.0 and works. That
    /// is the whole of the "the single-position pane renders while the other
    /// two do not" split, which is a race, not a structural difference.
    ///
    /// `viewDidChangeBackingProperties` is overridden for the same reason it
    /// exists — moving the window between displays of different scale.
    final class ScaleAwareMTKView: MTKView {
        private func matchWindowScale() {
            guard let scale = window?.backingScaleFactor, scale > 0 else { return }
            guard layer?.contentsScale != scale else { return }
            layer?.contentsScale = scale
            needsDisplay = true
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchWindowScale()
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            matchWindowScale()
        }
    }

    func makeNSView(context: Context) -> MTKView {
        let view = ScaleAwareMTKView(frame: .zero, device: MetalEngine.shared.device)
        view.colorPixelFormat = .bgra8Unorm           // must match displayPSO
        view.clearColor = MTLClearColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view.framebufferOnly = true
        view.isPaused = true                           // redraw only on demand
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        // Parent views zoom via scaleEffect (a layer transform); nearest
        // magnification keeps the data pixels crisp instead of blurring.
        view.layer?.magnificationFilter = .nearest
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
        c.displayRange = SIMD2<Float>(displayLo, displayHi)
        c.gamma = max(gamma, 0.05)
        view.needsDisplay = true
    }

    // MARK: - Coordinator (the MTKView delegate / renderer)

    final class Coordinator: NSObject, MTKViewDelegate {

        var colormap: ColormapKind = .viridis { didSet { lutDirty = true } }
        var zoom: Float = 1
        var offset = SIMD2<Float>(0, 0)
        var displayRange = SIMD2<Float>(0, 1)
        var gamma: Float = 1

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
                var display = SIMD4<Float>(displayRange.x, displayRange.y, gamma, 0)
                enc.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
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
