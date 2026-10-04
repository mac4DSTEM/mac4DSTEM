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
}
