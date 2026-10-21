// The demo's maps are 12 x 12 scan maps drawn nearest-neighbour (process/ui-testing-2026-10-21.md screenshot check: the panes show
// 3 x 3 blocks). The demo's lattice angle changes per 4 x 4 block of positions (DemoFourDDataSource), so the blocks are the data;
// this pins that the product the pane draws has 12 x 12 values, not a 3 x 3 crop or a coarse draw.

import XCTest
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class DemoMapGridTests: XCTestCase {
    func testTheDemoVirtualImageHasOneValuePerScanPosition() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        await state.runCurrentAnalysis()
        let product = try XCTUnwrap(state.displayedProduct, "a virtual image is shown after opening the demo")
        guard case .scalar(let image) = product.payload else { return XCTFail("a scalar image") }
        XCTAssertEqual([image.width, image.height], [12, 12], "the pane draws the 12 x 12 scan, not a crop")
        XCTAssertEqual(image.pixels.count, 144)
        // 143 distinct values on 144 positions measured: a real 12 x 12 map, not nine block values drawn coarse. Its colour range is
        // dominated by the block-to-block lattice angle, so the pane reads as 3 x 3 blocks with a faint texture inside them.
        XCTAssertGreaterThan(Set(image.pixels).count, 100)
    }
}
