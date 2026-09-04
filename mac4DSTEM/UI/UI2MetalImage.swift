import SwiftUI
import MetalKit
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The one SwiftUI to Metal bridge in UI2: a single-channel image already
/// normalised to [0, 1], drawn through `MetalEngine`'s display pipeline
/// (fullscreen triangle + colormap LUT), or packed RGBA8 bytes drawn
/// through the RGBA pipeline.
///
/// **Contract**
/// - `pixels` is already normalised (`FloatImage.normalized` /
///   `DiffractionPattern.normalized`). Masked pixels are the negative
///   `FloatImage.invalidDisplayValue` sentinel and render as neutral gray.
/// - `contentVersion` MUST change whenever `pixels` or `rgba` changes: the
///   coordinator re-uploads the texture only on a version change, which is
///   what keeps zooming and panning free. Passing a literal `0` here is the
///   defect that froze a comparison panel on the previous product's pixels.
///
/// **Why it is still a platform representable.** Everything else in UI2 is
/// plain SwiftUI, but there is no SwiftUI view that samples a float texture
/// through a LUT with a display window and gamma in the fragment shader, and
/// the alternative — rasterising to a `CGImage` per frame — would cost the
/// interactive contrast, gamma and colormap the science depends on. The
/// wrapper is deliberately shaped for both platforms: the shared body is
/// `makeMetalView`/`updateMetalView`, and only the two-line platform
/// conformance differs, so an iOS target needs no rewrite.
///
/// Unlike its predecessor this view takes **no zoom or offset**: UI2 zooms
/// with SwiftUI's own `scaleEffect` (every previous call site already passed
/// `zoom: 1, offset: .zero`), so there is one transform in the app rather
/// than two that can disagree.
struct UI2MetalImage {
    /// A version derived from the pixel VALUES and the dimensions. O(n)
    /// FNV-1a — call it where the pixels are produced, once per image, never
    /// inside a `body`. Dimensions are folded in because the coordinator
    /// short-circuits on the version before it looks at width and height, so
    /// identical pixels at transposed dimensions must still re-upload.
    nonisolated static func contentVersion(
        of pixels: [Float], width: Int, height: Int
    ) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        hash = (hash ^ UInt64(truncatingIfNeeded: width)) &* 0x0000_0100_0000_01b3
        hash = (hash ^ UInt64(truncatingIfNeeded: height)) &* 0x0000_0100_0000_01b3
        for value in pixels {
            hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    /// Folds packed RGBA bytes into a scalar version. An RGBA payload carries
    /// an all-zero `pixels` array, so hashing the pixels alone gives every
    /// same-sized RGBA product the same version — an IPF map and a DPC colour
    /// wheel of equal size would be indistinguishable and one would keep the
    /// other's texture.
    nonisolated static func contentVersion(
        of pixels: [Float], rgba: [UInt8]?, width: Int, height: Int
    ) -> Int {
        let base = contentVersion(of: pixels, width: width, height: height)
        guard let rgba else { return base }
        return rgba.withUnsafeBytes { bytes -> Int in
            var hash = UInt64(bitPattern: Int64(base))
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
            return Int(bitPattern: UInt(truncatingIfNeeded: hash))
        }
    }

    var pixels: [Float]          // normalised [0, 1], row-major
    var width: Int
    var height: Int
    var contentVersion: Int
    var colormap: ColormapKind
    /// When set, these packed RGBA8 bytes (width x height x 4) are drawn
    /// instead of `pixels` + colormap.
    var rgba: [UInt8]?
    /// Display contrast window in normalised [0, 1] intensity, applied in the
    /// fragment shader — cheap, per frame.
    var displayLo: Float
    var displayHi: Float
    var gamma: Float

    init(
        pixels: [Float],
        width: Int,
        height: Int,
        contentVersion: Int,
        colormap: ColormapKind = .viridis,
        rgba: [UInt8]? = nil,
        displayLo: Float = 0,
        displayHi: Float = 1,
        gamma: Float = 1
    ) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.contentVersion = contentVersion
        self.colormap = colormap
        self.rgba = rgba
        self.displayLo = displayLo
        self.displayHi = displayHi
        self.gamma = gamma
    }

    fileprivate func makeMetalView(_ coordinator: Coordinator) -> MTKView {
        let view = ScaleAwareMTKView(frame: .zero, device: MetalEngine.shared.device)
        view.colorPixelFormat = .bgra8Unorm            // must match displayPSO
        view.clearColor = MTLClearColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view.framebufferOnly = true
        view.isPaused = true                            // redraw only on demand
        view.enableSetNeedsDisplay = true
        view.delegate = coordinator
        // The pane zooms with a layer transform; nearest magnification keeps
        // data pixels crisp instead of interpolating science that is not there.
        view.layer?.magnificationFilter = .nearest
        return view
    }

    fileprivate func updateMetalView(_ view: MTKView, _ coordinator: Coordinator) {
        coordinator.colormap = colormap
        coordinator.updateContentIfNeeded(
            pixels: pixels, rgba: rgba,
            width: width, height: height, version: contentVersion
        )
        coordinator.displayRange = SIMD2<Float>(displayLo, displayHi)
        coordinator.gamma = max(gamma, 0.05)
        view.needsDisplay = true
    }

    /// An `MTKView` that keeps its layer's `contentsScale` in step with the
    /// window it is in.
    ///
    /// Measured 2026-08-27: inside a SwiftUI sheet the hosted `MTKView`'s
    /// `CAMetalLayer` is left at `contentsScale == 0`, and a layer at scale 0
    /// cannot display a drawable — the pane stays exactly the background
    /// colour while every internal signal (drawable size, render pass,
    /// current drawable, uploaded texture) looks healthy. What writes the 0
    /// was never identified, which is why the `!=` guard matters: this must
    /// not fight whatever does the writing.
    final class ScaleAwareMTKView: MTKView {
        private func matchWindowScale() {
            #if os(macOS)
            guard let scale = window?.backingScaleFactor, scale > 0 else { return }
            #else
            guard let scale = window?.screen.scale, scale > 0 else { return }
            #endif
            guard layer?.contentsScale != scale else { return }
            layer?.contentsScale = scale
            #if os(macOS)
            needsDisplay = true
            #else
            setNeedsDisplay()
            #endif
        }

        #if os(macOS)
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchWindowScale()
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            matchWindowScale()
        }
        #else
        override func didMoveToWindow() {
            super.didMoveToWindow()
            matchWindowScale()
        }
        #endif
    }

    // MARK: - Coordinator (the MTKView delegate / renderer)

    final class Coordinator: NSObject, MTKViewDelegate {
        var colormap: ColormapKind = .viridis { didSet { lutDirty = true } }
        var displayRange = SIMD2<Float>(0, 1)
        var gamma: Float = 1

        private var dataTexture: MTLTexture?
        private var rgbaTexture: MTLTexture?
        private var lutTexture: MTLTexture?
        private var lutDirty = true
        private var version = Int.min

        func updateContentIfNeeded(
            pixels: [Float], rgba: [UInt8]?, width: Int, height: Int, version v: Int
        ) {
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
            lutTexture = MetalEngine.shared.device.makeLUTTexture(
                rgba: Colormaps.lutRGBA(colormap, count: 256))
            lutDirty = false
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

        func draw(in view: MTKView) {
            rebuildLUTIfNeeded()

            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = MetalEngine.shared.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            let engine = MetalEngine.shared
            if rgbaTexture != nil {
                encoder.setRenderPipelineState(engine.displayRGBAPSO)
            } else if dataTexture != nil, lutTexture != nil {
                encoder.setRenderPipelineState(engine.displayPSO)
            } else {
                encoder.endEncoding()
                buffer.present(drawable)
                buffer.commit()
                return
            }

            // Identity transform: UI2 zooms and pans with SwiftUI's own
            // `scaleEffect`/`offset`, so the shader draws the whole image.
            var transform = SIMD4<Float>(1, 0, 0, 0)
            encoder.setVertexBytes(
                &transform, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

            if let rgbaTexture {
                encoder.setFragmentTexture(rgbaTexture, index: 0)
            } else {
                var display = SIMD4<Float>(displayRange.x, displayRange.y, gamma, 0)
                encoder.setFragmentBytes(
                    &display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentTexture(dataTexture, index: 0)
                encoder.setFragmentTexture(lutTexture, index: 1)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

#if os(macOS)
extension UI2MetalImage: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView { makeMetalView(context.coordinator) }
    func updateNSView(_ view: MTKView, context: Context) {
        updateMetalView(view, context.coordinator)
    }
}
#else
extension UI2MetalImage: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView { makeMetalView(context.coordinator) }
    func updateUIView(_ view: MTKView, context: Context) {
        updateMetalView(view, context.coordinator)
    }
}
#endif
