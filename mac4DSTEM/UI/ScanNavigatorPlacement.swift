import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// When the scan navigator (the small SCAN map with a draggable marker) is drawn.
///
/// A scan-domain result is itself clickable, so it picks the scan position
/// directly. A detector-domain result (a Bragg-vector map) or a reconstruction
/// (parallax, single-slice phase) is not a map of scan positions, so the scan
/// gets a thumbnail of its own to scrub in. The thumbnail lives in the
/// DIFFRACTION pane, beside the pattern it drives (owner card Q3 a, 2026-10-04);
/// it used to cover the result map. Pure so the rule is pinned without a view,
/// and used by that one pane.
enum ScanNavigatorPlacement {
    /// `domain` is the displayed product's, nil when none is shown; `hasImage`
    /// is whether a navigation image exists. A pane with no result to scrub
    /// beside shows none.
    nonisolated static func isShown(domain: ProductDomain?, hasImage: Bool) -> Bool {
        guard hasImage, let domain else { return false }
        return domain != .scan
    }

    // MARK: - Size and scrub mapping

    /// The longer side of the thumbnail, in points: it fits inside a `maxSide` x `maxSide` box.
    /// It was the WIDTH, fixed, so a 17 x 77 scan drew 118 x 534 pt and covered ~30 % of the
    /// pattern beside it (polish drive 2026-10-04, shot 48-detect-after).
    nonisolated static let maxSide: CGFloat = 118

    /// The shortest side the thumbnail keeps, in points: the width of its "SCAN" label, measured.
    /// SwiftUI lays `Text("SCAN")` in 9-pt monospaced bold with `.padding(3)` out at 29 x 17 pt (22.25 pt
    /// of glyphs plus the padding on both sides); in anything narrower the label wraps to "SCA" / "N".
    /// So a 17 x 77 scan, 26 pt at its true aspect ratio, is drawn 29 x 118 (an 11 % stretch), and a
    /// 1 x N line scan is stretched to this width rather than drawn as a hairline.
    nonisolated static let minSide: CGFloat = 29

    /// The thumbnail's size for an `rx` x `ry` scan: the scan's aspect ratio, the LONGER side `maxSide`
    /// (a square scan is `maxSide` x `maxSide`), neither side below `minSide`. A scan size below 1
    /// is read as 1.
    nonisolated static func size(rx: Int, ry: Int, maxSide: CGFloat = ScanNavigatorPlacement.maxSide) -> CGSize {
        let w = CGFloat(max(rx, 1)), h = CGFloat(max(ry, 1))
        let scale = maxSide / max(w, h)
        return CGSize(width: max(w * scale, minSide), height: max(h * scale, minSide))
    }

    /// The scan position under `location` (inset-local points) on a thumbnail drawn at `size`: the
    /// whole inset maps to the whole `rx` x `ry` scan, whatever its shape, and a drag past an edge
    /// stays on the edge pixel.
    nonisolated static func scanPosition(at location: CGPoint, in size: CGSize, rx: Int, ry: Int) -> (x: Int, y: Int) {
        func index(_ along: CGFloat, of length: CGFloat, count: Int) -> Int {
            let last = CGFloat(max(count, 1) - 1)
            return Int(min(max((along / max(length, 1) * CGFloat(count)).rounded(.down), 0), last))
        }
        return (index(location.x, of: size.width, count: rx), index(location.y, of: size.height, count: ry))
    }
}
