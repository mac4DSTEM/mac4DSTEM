import CoreGraphics
import DSTEMCore
import DSTEMSession

/// Who owns a plain drag in the real-space pane (backlog #35).
///
/// The two panes were inconsistent: the diffraction pane already followed the
/// rule the release owner wants — the detector moves only when its handle is
/// grabbed, and a drag on empty area pans — while `StemImageView` put a
/// `DragGesture(minimumDistance: 0)` scrub layer *above* the pan gesture. So in
/// real space every click scrubbed the scan position and the scrub always won
/// over the pan, which meant **a zoomed real-space image could not be panned at
/// all**: you could magnify but never navigate.
///
/// The release owner chose option 1 on 2026-08-05 — *pan when zoomed, scrub
/// when not* — over the literal "always require a grab handle" reading:
/// click-to-scrub is the gesture a user makes a hundred times a session and it
/// must not regress in the common case, while the zoomed case is the one that
/// was actually broken.
///
/// This is a *mode*, and a mode that is invisible is just confusing, so
/// `StemImageView` labels it in the pane header whenever it is not `.scrub`.
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
