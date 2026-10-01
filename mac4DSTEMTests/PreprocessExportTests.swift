//
//  PreprocessExportTests.swift
//  X2 — scan stride, detector crop and py4DSTEM's hot-pixel filter in the
//  preprocessing export. The arbiter for the numbers is py4DSTEM itself
//  (tools/preprocessing-export-test, gated); these tests pin the pieces a
//  host-less run can: the filter's mask rules and median, the stride's floor
//  semantics, and the provenance fields' presence rule.
//

import XCTest
import DSTEMCore

final class PreprocessExportTests: XCTestCase {

    /// A flat 8 x 9 mean pattern (value 4) with planted pixels, as in the
    /// gated harness: a hot pixel with a dimmer neighbour, a pair on opposite
    /// edges (hidden from each other only by the wrap) and a corner.
    private func plantedMean() -> [Float] {
        var mean = [Float](repeating: 4, count: 8 * 9)
        mean[2 * 9 + 3] = 5004      // hot
        mean[2 * 9 + 4] = 3004      // dimmer neighbour
        mean[3 * 9 + 0] = 5004      // opposite-edge pair
        mean[3 * 9 + 8] = 4994
        mean[7 * 9 + 8] = 5004      // corner
        return mean
    }

    func testMaskComparesWithSecondBrightestAndWrapsAtTheEdge() {
        // Hot pixel: beats its neighbour (3004) by 2000. Dimmer neighbour: not
        // flagged (it is the second brightest of its own window). The edge
        // pair: np.roll puts each in the other's window, 10 apart < 20.
        // Corner: flagged. A clamped (non-wrapping) window would also flag
        // (3,0); comparing with the brightest would flag nothing.
        let mask = HotPixelFilter.maskIndices(mean: plantedMean(), height: 8, width: 9, threshold: 20)
        XCTAssertEqual(mask, [2 * 9 + 3, 7 * 9 + 8])
    }

    func testThresholdIsStrictlyGreaterThan() {
        var mean = [Float](repeating: 0, count: 6 * 6)
        mean[2 * 6 + 2] = 8
        XCTAssertEqual(HotPixelFilter.maskIndices(mean: mean, height: 6, width: 6, threshold: 8), [],
                       "py4DSTEM: mean - compare > thresh")
        XCTAssertEqual(HotPixelFilter.maskIndices(mean: mean, height: 6, width: 6, threshold: 7.5), [2 * 6 + 2])
    }

    func testReplacementIsTheClipped3x3MedianInPlace() {
        // Corner pixel: the window is the clipped 2 x 2 (even count), so the
        // median is the mean of the two middle values.
        var pixels: [Float] = [9, 1, 7,
                               3, 5, 2,
                               4, 6, 1000]       // (2,2) is the masked corner
        HotPixelFilter.replace(mask: [8], in: &pixels, base: 0, height: 3, width: 3)
        XCTAssertEqual(pixels[8], (5 + 6) / 2, "median of {5, 2, 6, 1000} is (5 + 6) / 2")
        // Interior pixel: a full 3 x 3, odd count.
        var interior: [Float] = [1, 2, 3,
                                 4, 900, 6,
                                 7, 8, 9]
        HotPixelFilter.replace(mask: [4], in: &interior, base: 0, height: 3, width: 3)
        XCTAssertEqual(interior[4], 6)           // sorted 1,2,3,4,6,7,8,9,900
        // A second pattern after the first is untouched (the base offset).
        var two: [Float] = [0, 100, 0, 0, 100, 0]
        HotPixelFilter.replace(mask: [1], in: &two, base: 3, height: 1, width: 3)
        XCTAssertEqual(two[1], 100, "pattern 0 must not be written")
        XCTAssertEqual(two[4], 0)
    }

    func testStrideKeepsFloorOfTheCropFromTheCropsFirstPosition() {
        // py4DSTEM thin_data_real: Rshape // N positions at i * N.
        let options = CalibratedDataCubeExportOptions(scanY: 1..<6, scanX: 2..<9, scanStride: 3)
        XCTAssertEqual(options.scanYPositions, [1])          // 5 // 3 = 1
        XCTAssertEqual(options.scanXPositions, [2, 5])       // 7 // 3 = 2
        XCTAssertTrue(options.reframesRecipe)
        XCTAssertFalse(CalibratedDataCubeExportOptions(scanY: 0..<4, scanX: 0..<4).reframesRecipe)
    }

    func testProvenanceNamesStrideAndMaskOnlyWhenUsed() throws {
        let plain = DataCubeDerivation(
            sourceFile: "a.dm4", scanOffsetY: 0, scanOffsetX: 0, scanHeight: 2, scanWidth: 2,
            detectorOffsetY: 0, detectorOffsetX: 0, detectorBin: 1, detectorHeight: 4, detectorWidth: 4
        )
        let plainJSON = try XCTUnwrap(plain.jsonString)
        XCTAssertFalse(plainJSON.contains("scan_stride"))
        XCTAssertFalse(plainJSON.contains("hot_pixel"))
        var used = plain
        used.scanStride = 2
        used.hotPixelThreshold = 8
        used.hotPixels = [[1, 12], [32, 32]]
        let usedJSON = try XCTUnwrap(used.jsonString)
        XCTAssertTrue(usedJSON.contains("\"scan_stride\":2"))
        XCTAssertTrue(usedJSON.contains("\"hot_pixels\":[[1,12],[32,32]]"))
        // Old files (no new keys) still decode.
        let decoded = try JSONDecoder().decode(DataCubeDerivation.self, from: Data(plainJSON.utf8))
        XCTAssertNil(decoded.scanStride)
        XCTAssertNil(decoded.hotPixels)
    }
}
