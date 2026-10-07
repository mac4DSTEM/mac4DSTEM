import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// SwiftUI-only review (2026-10-08, lane A2): the AppKit uses in the app layer.
final class SwiftUIReviewA2Tests: XCTestCase {

    /// A1: the colorbar-chip swatch was drawn with NSImage.lockFocus; it is now
    /// built from the LUT bytes. The swatch must show the LUT left to right on
    /// every row: first colour at the left end, last at the right, the middle
    /// column matching the table.
    func testSwatchBytesFollowTheLUTLeftToRight() {
        let width = Colormaps.swatchWidth, height = Colormaps.swatchHeight
        for kind in ColormapKind.allCases {
            let lut = Colormaps.lutRGBA(kind, count: width)
            let bytes = Colormaps.swatchRGBA(kind)
            XCTAssertEqual(bytes.count, width * height * 4, "\(kind)")
            for row in [0, height / 2, height - 1] {
                for column in [0, width / 2, width - 1] {
                    let pixel = (row * width + column) * 4
                    let entry = column * 4
                    XCTAssertEqual(Array(bytes[pixel ..< pixel + 4]), Array(lut[entry ..< entry + 4]),
                                   "\(kind) row \(row) column \(column)")
                }
            }
        }
    }

    /// A1: the CGImage the view shows carries the same bytes as the pure
    /// function, at the swatch size (44 x 12 points at 1x).
    func testSwatchCGImageCarriesTheSwatchBytes() {
        for kind in ColormapKind.allCases {
            let image = Colormaps.swatchCGImage(kind)
            XCTAssertEqual(image.width, Colormaps.swatchWidth, "\(kind)")
            XCTAssertEqual(image.height, Colormaps.swatchHeight, "\(kind)")
            XCTAssertEqual(image.bytesPerRow, Colormaps.swatchWidth * 4, "\(kind)")
            let data = image.dataProvider?.data as Data?
            XCTAssertEqual(data.map { Array($0) }, Colormaps.swatchRGBA(kind), "\(kind)")
        }
    }
}
