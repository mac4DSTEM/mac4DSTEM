//
//  PreprocessExportTests.swift
//  X2 — scan stride, detector crop and py4DSTEM's hot-pixel filter in the
//  preprocessing export. The arbiter for the numbers is py4DSTEM itself
//  (tools/harnesses/preprocessing-export-test, gated); these tests pin the pieces a
//  host-less run can: the filter's mask rules and median, the stride's floor
//  semantics, and the provenance fields' presence rule.
//

import XCTest
import CuboCore
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

    /// The flat row-major indices CuboCore's mask marks, as the export's summary lists them.
    private func maskedIndices(_ mean: [Float], rows: Int, columns: Int, threshold: Double) throws -> [Int] {
        let flags = try HotPixelFilter.mask(mean: mean, rows: rows, columns: columns, threshold: threshold)
        return flags.indices.filter { flags[$0] }
    }

    func testMaskComparesWithSecondBrightestAndWrapsAtTheEdge() throws {
        // Hot pixel: beats its neighbour (3004) by 2000. Dimmer neighbour: not
        // flagged (it is the second brightest of its own window). The edge
        // pair: np.roll puts each in the other's window, 10 apart < 20.
        // Corner: flagged. A clamped (non-wrapping) window would also flag
        // (3,0); comparing with the brightest would flag nothing.
        // (A consumer test of CuboCore.HotPixelFilter.mask; the kit pins the rule itself.)
        let mask = try maskedIndices(plantedMean(), rows: 8, columns: 9, threshold: 20)
        XCTAssertEqual(mask, [2 * 9 + 3, 7 * 9 + 8])
    }

    func testThresholdIsStrictlyGreaterThan() throws {
        var mean = [Float](repeating: 0, count: 6 * 6)
        mean[2 * 6 + 2] = 8
        XCTAssertEqual(try maskedIndices(mean, rows: 6, columns: 6, threshold: 8), [],
                       "py4DSTEM: mean - compare > thresh")
        XCTAssertEqual(try maskedIndices(mean, rows: 6, columns: 6, threshold: 7.5), [2 * 6 + 2])
    }

    func testReplacementIsTheClippedMedianAndTouchesOnlyItsOwnPattern() throws {
        // The export replaces in the pattern at `base` of a tile and leaves the others alone.
        // Corner pixel: the window is the clipped 2 x 2 (even count), so the
        // median is the mean of the two middle values.
        var pixels: [Float] = [9, 1, 7,
                               3, 5, 2,
                               4, 6, 1000]       // (2,2) is the masked corner
        var corner = [Bool](repeating: false, count: 9); corner[8] = true
        try BraggVectorEMDWriter.replaceHotPixels(in: &pixels, base: 0, rows: 3, columns: 3, mask: corner)
        XCTAssertEqual(pixels[8], (5 + 6) / 2, "median of {5, 2, 6, 1000} is (5 + 6) / 2")
        // Interior pixel: a full 3 x 3, odd count.
        var interior: [Float] = [1, 2, 3,
                                 4, 900, 6,
                                 7, 8, 9]
        var middle = [Bool](repeating: false, count: 9); middle[4] = true
        try BraggVectorEMDWriter.replaceHotPixels(in: &interior, base: 0, rows: 3, columns: 3, mask: middle)
        XCTAssertEqual(interior[4], 6)           // sorted 1,2,3,4,6,7,8,9,900
        // A second pattern after the first is untouched (the base offset).
        var two: [Float] = [0, 100, 0, 0, 100, 0]
        try BraggVectorEMDWriter.replaceHotPixels(in: &two, base: 3, rows: 1, columns: 3,
                                                  mask: [false, true, false])
        XCTAssertEqual(two[1], 100, "pattern 0 must not be written")
        XCTAssertEqual(two[4], 0)
    }

    /// A source with a NaN in every tile: the hot-pixel filter refuses it with its own error and a remedy, before anything is
    /// published; the same export with the filter off writes it.
    func testANaNSourceRefusesTheHotPixelFilterWithARemedy() async throws {
        actor NaNSource: FourDDataSource {
            func discoverPrimaryDataset() throws -> DatasetDescriptor { PreprocessFixtureSource.descriptor }
            nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
            private func pattern(_ view: LoadView, y: Int, x: Int) -> [Float] {
                let d = PreprocessFixtureSource.descriptor
                var pixels = (0..<(d.qy * d.qx)).map { Float(($0 + y * 7 + x * 3) % 11) }
                pixels[0] = .nan
                return view.detectorView(of: pixels)
            }
            func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
                pattern(view, y: view.sourceScanY(ry), x: view.sourceScanX(rx))
            }
            func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
                (0..<view.descriptor.rx).flatMap { pattern(view, y: view.sourceScanY(ry), x: view.sourceScanX($0)) }
            }
            func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
                let pixels = try yRange.flatMap { try readScanRow(view, ry: $0) }
                return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx, detectorHeight: view.descriptor.qy,
                                     detectorWidth: view.descriptor.qx, pixels: pixels)
            }
            func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
            func pixelCalibration() -> PixelCalibration? { nil }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nan-hot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = PreprocessFixtureSource.descriptor
        let view = LoadView(fullExtentOf: descriptor)
        let target = directory.appendingPathComponent("hot.h5")
        do {
            _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: NaNSource(), view: view, calibration: PixelCalibration(),
                options: CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry, scanX: 0..<descriptor.rx, hotPixelThreshold: 20),
                to: target)
            XCTFail("a NaN pixel must refuse the hot-pixel filter")
        } catch BraggVectorEMDWriter.WriterError.hotPixelFilterNeedsFinitePixels {
            XCTAssertTrue(BraggVectorEMDWriter.WriterError.hotPixelFilterNeedsFinitePixels.localizedDescription
                .contains("Switch the hot-pixel filter off or crop away non-finite pixels"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "nothing was published")
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: NaNSource(), view: view, calibration: PixelCalibration(),
            options: CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry, scanX: 0..<descriptor.rx), to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    /// One `Replacer` reused across many patterns equals the kit's validating `replacing` pattern by pattern, bit for bit
    /// (CuboKit 0.6.0), writes only its own pattern, and still refuses a non-finite pixel.
    func testASharedReplacerMatchesReplacingOnEveryPatternAndRefusesNonFinite() throws {
        let rows = 6, columns = 7, size = rows * columns, count = 5
        var pixels = (0..<(size * count)).map { Float(($0 * 37 + 11) % 101) }
        var mask = [Bool](repeating: false, count: size)
        for k in [0, 8, 20, size - 1] { mask[k] = true }      // a corner, the interior, the far corner
        let expected = (0..<count).flatMap { p in
            try! HotPixelFilter.replacing(Array(pixels[(p * size)..<((p + 1) * size)]), rows: rows, columns: columns, mask: mask)
        }
        let replacer = try HotPixelFilter.Replacer(rows: rows, columns: columns, mask: mask)
        for p in 0..<count { try BraggVectorEMDWriter.replaceHotPixels(in: &pixels, base: p * size, replacer: replacer) }
        XCTAssertEqual(pixels.map(\.bitPattern), expected.map(\.bitPattern))
        pixels[2 * size + 3] = .infinity
        XCTAssertThrowsError(try BraggVectorEMDWriter.replaceHotPixels(in: &pixels, base: 2 * size, replacer: replacer))
    }

    func testANonFinitePixelIsRefusedNotMedianed() {
        var pixels: [Float] = [1, .nan, 3]
        XCTAssertThrowsError(try BraggVectorEMDWriter.replaceHotPixels(
            in: &pixels, base: 0, rows: 1, columns: 3, mask: [false, true, false])) { error in
            guard case BraggVectorEMDWriter.WriterError.hotPixelFilterNeedsFinitePixels = error else { return XCTFail("\(error)") }
        }
    }

    func testStrideKeepsFloorOfTheCropFromTheCropsFirstPosition() {
        // py4DSTEM thin_data_real: Rshape // N positions at i * N.
        let options = CalibratedDataCubeExportOptions(scanY: 1..<6, scanX: 2..<9, scanStride: 3)
        XCTAssertEqual(options.scanYPositions, [1])          // 5 // 3 = 1
        XCTAssertEqual(options.scanXPositions, [2, 5])       // 7 // 3 = 2
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
