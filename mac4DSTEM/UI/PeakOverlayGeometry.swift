import CoreGraphics

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
