import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Inverts the comparison panes' draw transform (aspect-fit, then
/// centre-zoom) to map a pane-space pointer back to the source pixel it
/// hovers. Kept as one pure function, separate from the draw code, so the
/// mapping can be pinned in a headless test (ui-06).
enum ComparisonHoverMapping {
    /// The size the aspect-fit draws an image at inside a pane (centred, before
    /// any zoom): the one fit both the draw call (`MetalDisplayTransform.imageBox`)
    /// and `sourcePixel` use, so they cannot disagree.
    nonisolated static func fittedSize(
        paneSize: CGSize, imageWidth: Int, imageHeight: Int
    ) -> CGSize {
        guard imageWidth > 0, imageHeight > 0 else { return .zero }
        let scale = min(paneSize.width / CGFloat(imageWidth),
                        paneSize.height / CGFloat(imageHeight))
        return CGSize(width: CGFloat(imageWidth) * scale,
                      height: CGFloat(imageHeight) * scale)
    }

    /// Maps a pointer in pane coordinates to the source pixel it hovers,
    /// or nil when the pointer is over letterbox rather than image.
    ///
    /// The draw chain is fit, then zoom about the pane centre, then `offset` (the pan, in screen points, as
    /// `MetalDisplayTransform` applies it); the inverse undoes them in the opposite order. A zoom below 1 is drawn as it is
    /// (the panes' floor is 0.25, `ZoomPan.minimumZoom`), so it is inverted as it is.
    static func sourcePixel(
        pointer: CGPoint, paneSize: CGSize,
        imageWidth: Int, imageHeight: Int, zoom: CGFloat,
        offset: CGSize = .zero
    ) -> (x: Int, y: Int)? {
        guard imageWidth > 0, imageHeight > 0,
              paneSize.width > 0, paneSize.height > 0 else { return nil }
        // Undo the pan first (it is applied last), then the centre-anchored zoom, which is applied after the fit.
        let effectiveZoom = max(zoom, 0.25)   // = ZoomPan.minimumZoom; this file compiles alone in tools/ harnesses
        let center = CGPoint(x: paneSize.width / 2, y: paneSize.height / 2)
        let unzoomed = CGPoint(
            x: center.x + (pointer.x - offset.width - center.x) / effectiveZoom,
            y: center.y + (pointer.y - offset.height - center.y) / effectiveZoom
        )
        // Then undo the aspect fit: the drawn rect is centred at scale
        // min(paneW/imgW, paneH/imgH).
        let drawn = fittedSize(paneSize: paneSize, imageWidth: imageWidth,
                               imageHeight: imageHeight)
        let scale = drawn.width / CGFloat(imageWidth)
        let origin = CGPoint(x: (paneSize.width - drawn.width) / 2,
                             y: (paneSize.height - drawn.height) / 2)
        let sx = (unzoomed.x - origin.x) / scale
        let sy = (unzoomed.y - origin.y) / scale
        guard sx >= 0, sy >= 0, sx < CGFloat(imageWidth), sy < CGFloat(imageHeight)
        else { return nil }
        return (Int(sx), Int(sy))
    }
}
