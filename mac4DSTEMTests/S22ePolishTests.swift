import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// S22e backlog-polish pins: the comparison hover's inverse letterbox/zoom
/// mapping (ui-06) and the publication figure's no-data legend
/// (support-export-07).
@MainActor
final class S22ePolishTests: XCTestCase {

    // MARK: ui-06 — hover maps through the drawn transform

    /// A square image letterboxed in a wide pane: the pane centre is the
    /// image centre, the letterbox margins are not on the image at all, and
    /// the old full-pane division would have claimed they were.
    func testLetterboxedHoverMapsCentreAndRefusesTheMargins() throws {
        let pane = CGSize(width: 400, height: 200)   // square image → 100pt margins
        let centre = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: CGPoint(x: 200, y: 100), paneSize: pane,
            imageWidth: 64, imageHeight: 64, zoom: 1
        ))
        XCTAssertEqual(centre.x, 32)
        XCTAssertEqual(centre.y, 32)

        XCTAssertNil(ComparisonHoverMapping.sourcePixel(
            pointer: CGPoint(x: 20, y: 100), paneSize: pane,
            imageWidth: 64, imageHeight: 64, zoom: 1
        ), "a pointer in the letterbox margin hovers no pixel")

        // The drawn image spans x ∈ [100, 300]; its left edge is pixel 0.
        let leftEdge = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: CGPoint(x: 101, y: 100), paneSize: pane,
            imageWidth: 64, imageHeight: 64, zoom: 1
        ))
        XCTAssertEqual(leftEdge.x, 0)
    }

    /// Centre-anchored zoom: at 2× the same pointer offset from the pane
    /// centre covers half the source distance.
    func testZoomHalvesTheSourceOffsetAboutTheCentre() throws {
        let pane = CGSize(width: 200, height: 200)
        let at1x = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: CGPoint(x: 150, y: 100), paneSize: pane,
            imageWidth: 100, imageHeight: 100, zoom: 1
        ))
        let at2x = try XCTUnwrap(ComparisonHoverMapping.sourcePixel(
            pointer: CGPoint(x: 150, y: 100), paneSize: pane,
            imageWidth: 100, imageHeight: 100, zoom: 2
        ))
        XCTAssertEqual(at1x.x, 75)
        XCTAssertEqual(at2x.x, 62, "2× zoom: centre + 25pt maps to centre + 12.5px")
    }

    // MARK: support-export-07 — the figure carries the no-data legend

    func testPublicationFigureDrawsTheNoDataLegendOnlyWhenMasked() throws {
        let base = try XCTUnwrap(solidImage(width: 60, height: 40))
        let with = AppState.publicationFigure(
            image: base, title: "t", caption: "c",
            valueRange: (low: 0, high: 1), valueUnits: "strain",
            colormap: .viridis, masksNoData: true
        )
        let without = AppState.publicationFigure(
            image: base, title: "t", caption: "c",
            valueRange: (low: 0, high: 1), valueUnits: "strain",
            colormap: .viridis, masksNoData: false
        )
        XCTAssertNotEqual(
            pngBytes(with), pngBytes(without),
            "masksNoData must change the rendered figure — the legend is the difference"
        )
        XCTAssertEqual(
            pngBytes(without),
            pngBytes(AppState.publicationFigure(
                image: base, title: "t", caption: "c",
                valueRange: (low: 0, high: 1), valueUnits: "strain",
                colormap: .viridis
            )),
            "the default stays legend-free, so existing callers are unchanged"
        )
    }

    private func solidImage(width: Int, height: Int) -> CGImage? {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx?.makeImage()
    }

    private func pngBytes(_ image: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
