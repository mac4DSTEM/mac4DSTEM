import CoreGraphics
import DSTEMCore
import DSTEMSession

/// Pure detector-pixel → view geometry for the Bragg-peak overlay.
/// Detector coordinates name pixel centers, so integer peaks receive a
/// half-pixel view offset. Radius uses the smaller axis scale to stay circular
/// even if a caller supplies a slightly non-aspect-fitted box.
enum PeakOverlayGeometry {
    nonisolated static func center(
        x: Float,
        y: Float,
        patternWidth: Int,
        patternHeight: Int,
        box: CGSize
    ) -> CGPoint {
        guard patternWidth > 0, patternHeight > 0 else { return .zero }
        return CGPoint(
            x: (CGFloat(x) + 0.5) / CGFloat(patternWidth) * box.width,
            y: (CGFloat(y) + 0.5) / CGFloat(patternHeight) * box.height
        )
    }

    /// Inverse of `center(x:y:…)` — the detector pixel under a view point.
    /// Kept beside the forward map so a drag can never land half a pixel away
    /// from where the same value is drawn.
    nonisolated static func pixel(
        at point: CGPoint,
        patternWidth: Int,
        patternHeight: Int,
        box: CGSize
    ) -> (x: Float, y: Float) {
        guard patternWidth > 0, patternHeight > 0, box.width > 0, box.height > 0 else {
            return (0, 0)
        }
        return (
            Float(point.x / box.width * CGFloat(patternWidth) - 0.5),
            Float(point.y / box.height * CGFloat(patternHeight) - 0.5)
        )
    }

    nonisolated static func radius(
        probeRadius: Float,
        patternWidth: Int,
        patternHeight: Int,
        box: CGSize
    ) -> CGFloat {
        guard patternWidth > 0, patternHeight > 0 else { return 0 }
        let xScale = box.width / CGFloat(patternWidth)
        let yScale = box.height / CGFloat(patternHeight)
        return CGFloat(probeRadius) * min(xScale, yScale)
    }
}
