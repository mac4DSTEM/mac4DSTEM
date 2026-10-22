import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import ShellMetal

/// The comparison panels share one `PaneZoomModel` and can now be panned, so the hover readout has to invert the whole draw chain
/// (fit, zoom about the centre, then the pan offset) — a panned panel that named the pixel it would have shown unpanned would
/// read a number from a place the pointer is not over (the reason the pan was left out until now). Tier 2 (UI behaviour).
final class ComparisonZoomPanTests: XCTestCase {

    private let pane = CGSize(width: 200, height: 200)

    /// The pane point where source pixel (px, py) of a 100×100 image is drawn, by the forward chain
    /// (fit scale 2, zoom about the centre, then offset).
    private func drawn(_ px: Int, _ py: Int, zoom: CGFloat, offset: CGSize) -> CGPoint {
        let fit: CGFloat = 2, c: CGFloat = 100
        let x = (CGFloat(px) + 0.5) * fit, y = (CGFloat(py) + 0.5) * fit
        return CGPoint(x: c + zoom * (x - c) + offset.width, y: c + zoom * (y - c) + offset.height)
    }

    func testAPannedPanelNamesThePixelUnderThePointer() throws {
        let offset = CGSize(width: 30, height: -20)
        let pointer = drawn(40, 60, zoom: 2, offset: offset)
        let hit = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: pointer, paneSize: pane, imageWidth: 100, imageHeight: 100, zoom: 2, offset: offset))
        XCTAssertEqual(hit.x, 40)
        XCTAssertEqual(hit.y, 60)
        let unpanned = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: pointer, paneSize: pane, imageWidth: 100, imageHeight: 100, zoom: 2))
        XCTAssertNotEqual(unpanned.x, 40, "the offset must matter, or this test cannot tell a panned readout from an unpanned one")
    }

    func testAZoomBelowOneIsInvertedAsDrawn() throws {
        // The panes draw down to ×0.25 (ZoomPan.minimumZoom); the readout used to floor the zoom at 1 and so named the wrong pixel.
        let pointer = drawn(10, 10, zoom: 0.5, offset: .zero)
        let hit = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: pointer, paneSize: pane, imageWidth: 100, imageHeight: 100, zoom: 0.5))
        XCTAssertEqual(hit.x, 10)
        XCTAssertEqual(hit.y, 10)
    }

    /// The inverse here against the shader's own inverse (`MetalDisplayTransform.uv`), over zooms, offsets and a letterboxed image.
    func testTheReadoutAgreesWithTheShadersTransform() throws {
        let paneSize = CGSize(width: 300, height: 180)
        let (w, h) = (64, 48)
        let box = ComparisonHoverMapping.fittedSize(paneSize: paneSize, imageWidth: w, imageHeight: h)
        for zoom: CGFloat in [0.5, 1, 2.5, 8] {
            for offset in [CGSize.zero, CGSize(width: 17, height: -9), CGSize(width: -40, height: 25)] {
                let transform = MetalDisplayTransform(paneSize: paneSize, imageBox: box, zoom: zoom, offset: offset)
                for pointer in [CGPoint(x: 150, y: 90), CGPoint(x: 120, y: 60), CGPoint(x: 190, y: 120)] {
                    let uv = transform.uv(atPanePoint: pointer)
                    let hit = ComparisonHoverMapping.sourcePixel(
                        pointer: pointer, paneSize: paneSize, imageWidth: w, imageHeight: h, zoom: zoom, offset: offset)
                    if uv.x >= 0, uv.x < 1, uv.y >= 0, uv.y < 1 {
                        let expected = (x: Int(uv.x * CGFloat(w)), y: Int(uv.y * CGFloat(h)))
                        XCTAssertEqual(hit?.x, expected.x, "zoom \(zoom) offset \(offset) pointer \(pointer)")
                        XCTAssertEqual(hit?.y, expected.y, "zoom \(zoom) offset \(offset) pointer \(pointer)")
                    } else {
                        XCTAssertNil(hit, "off the image the shader draws nothing, so the readout names nothing")
                    }
                }
            }
        }
    }
}
