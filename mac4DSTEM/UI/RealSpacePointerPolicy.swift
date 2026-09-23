import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Who owns a plain drag in the real-space pane (backlog #35).
///
/// Zoomed in: a drag on empty area pans, and the scan marker moves only via
/// its grab handle, matching the diffraction pane's detector-handle rule.
/// Zoomed out or at 1x: a click or drag anywhere scrubs the scan position —
/// the gesture used most often, so it stays the default rather than always
/// requiring a grab handle.
///
/// The mode is otherwise invisible, so `StemImageView` labels it in the pane
/// header whenever it is not `.scrub`.
enum RealSpacePointerPolicy {
    enum Mode: Equatable {
        /// Zoom 1 (and zoomed out): a click or drag anywhere scrubs the scan
        /// position. Unchanged behaviour.
        case scrub
        /// Zoomed in: a drag on empty area pans the image, and the scan marker
        /// moves only by its own grab handle — the same vocabulary as
        /// `ApertureControl`'s white centre handle in the diffraction pane.
        case panAndGrab
    }

    /// Zooming *out* is deliberately still `.scrub`: the image is then smaller
    /// than its pane, so there is nothing to pan to and taking click-to-scrub
    /// away would cost the user a gesture and give nothing back. The epsilon
    /// absorbs the float error a pinch or a wheel notch leaves behind when it
    /// lands back on nominal 1.0.
    static func mode(zoom: CGFloat) -> Mode {
        zoom > 1 + 1e-4 ? .panAndGrab : .scrub
    }

    /// Centre of the scan marker in pane points.
    ///
    /// Shared by the crosshair and its grab handle so the thing you see and the
    /// thing you can grab cannot drift apart — the same reason
    /// `PeakOverlayGeometry` owns both directions of the detector map.
    /// Scan coordinates name pixel centres, hence the half-pixel offset.
    static func markerCenter(
        scan: ScanPos, imageWidth: Int, imageHeight: Int, box: CGSize
    ) -> CGPoint {
        guard imageWidth > 0, imageHeight > 0 else { return .zero }
        return CGPoint(
            x: (CGFloat(scan.x) + 0.5) / CGFloat(imageWidth) * box.width,
            y: (CGFloat(scan.y) + 0.5) / CGFloat(imageHeight) * box.height
        )
    }

    /// The scan position under a point in the same space `markerCenter` draws
    /// into. Floors rather than rounds, so each pixel owns the area it covers.
    static func scanPosition(
        at point: CGPoint, imageWidth: Int, imageHeight: Int, box: CGSize
    ) -> ScanPos {
        guard box.width > 0, box.height > 0 else { return ScanPos(x: 0, y: 0) }
        return ScanPos(
            x: Int((point.x / box.width * CGFloat(imageWidth)).rounded(.down)),
            y: Int((point.y / box.height * CGFloat(imageHeight)).rounded(.down))
        )
    }
}
