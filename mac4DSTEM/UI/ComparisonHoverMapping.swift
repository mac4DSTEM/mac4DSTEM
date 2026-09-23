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
    /// Maps a pointer in pane coordinates to the source pixel it hovers,
    /// or nil when the pointer is over letterbox rather than image.
    static func sourcePixel(
        pointer: CGPoint, paneSize: CGSize,
        imageWidth: Int, imageHeight: Int, zoom: CGFloat
    ) -> (x: Int, y: Int)? {
        guard imageWidth > 0, imageHeight > 0,
              paneSize.width > 0, paneSize.height > 0 else { return nil }
        // Undo the centre-anchored zoom first — scaleEffect is applied after
        // the fit, about the pane centre.
        let effectiveZoom = max(zoom, 1)
        let center = CGPoint(x: paneSize.width / 2, y: paneSize.height / 2)
        let unzoomed = CGPoint(
            x: center.x + (pointer.x - center.x) / effectiveZoom,
            y: center.y + (pointer.y - center.y) / effectiveZoom
        )
        // Then undo the aspect fit: the drawn rect is centred at scale
        // min(paneW/imgW, paneH/imgH).
        let scale = min(paneSize.width / CGFloat(imageWidth),
                        paneSize.height / CGFloat(imageHeight))
        let drawn = CGSize(width: CGFloat(imageWidth) * scale,
                           height: CGFloat(imageHeight) * scale)
        let origin = CGPoint(x: (paneSize.width - drawn.width) / 2,
                             y: (paneSize.height - drawn.height) / 2)
        let sx = (unzoomed.x - origin.x) / scale
        let sy = (unzoomed.y - origin.y) / scale
        guard sx >= 0, sy >= 0, sx < CGFloat(imageWidth), sy < CGFloat(imageHeight)
        else { return nil }
        return (Int(sx), Int(sy))
    }
}
