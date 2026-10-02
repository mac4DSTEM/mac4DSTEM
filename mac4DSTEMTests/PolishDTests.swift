import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane D (2026-10-02): the Info/configurator real-space preview was solid
/// black on a cube whose patterns are each normalised to unit sum, because the
/// per-position total is then constant and `normalized()` of a constant is 0.
@MainActor
final class PolishDTests: XCTestCase {

    private actor GridSource: FourDDataSource {
        let patterns: [[Float]]
        let shape: [Int]
        init(scan: Int, detector: Int, patterns: [[Float]]) {
            self.patterns = patterns; shape = [scan, scan, detector, detector]
        }
        func discoverPrimaryDataset() throws -> DatasetDescriptor {
            DatasetDescriptor(filePath: "/synthetic/polish-d.h5", datasetPath: "/data",
                              shape: shape, dtypeDescription: "float32", chunkShape: nil)
        }
        nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
        func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
            patterns[ry * view.descriptor.rx + rx]
        }
        func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
            (0..<view.descriptor.rx).flatMap { patterns[ry * view.descriptor.rx + $0] }
        }
        func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
            var pixels = [Float]()
            for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
            return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                                 detectorHeight: shape[2], detectorWidth: shape[3], pixels: pixels)
        }
        func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
        func pixelCalibration() -> PixelCalibration? { nil }
    }

    /// 8x8 detector, bright-field disk radius 2 at (4,4). Pixel (4,4) (inside
    /// the disk) holds `c`, pixel (0,0) (outside) holds 1 - c - deficit, all
    /// else 0: the total is exactly 1 - deficit with dyadic values.
    private func pattern(c: Float, deficit: Float) -> [Float] {
        var p = [Float](repeating: 0, count: 64)
        p[4 * 8 + 4] = c
        p[0] = 1 - c - deficit
        return p
    }

    private func preview(deficit: (Int) -> Float) async throws -> DatasetPreview {
        let patterns = (0..<16).map { pattern(c: Float($0 + 1) / 128, deficit: deficit($0)) }
        let source = GridSource(scan: 4, detector: 8, patterns: patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        return try await DatasetPreviewBuilder.make(
            data: FourDArray(reader: source, descriptor: descriptor),
            descriptor: descriptor, byteBudget: .max)
    }

    /// Exactly constant totals: the image is the disk sum, and it is the RIGHT
    /// pixels (argmax at the position with the largest centre value, 15).
    func testConstantTotalsGiveTheBrightFieldDiskImage() async throws {
        let preview = try await self.preview { _ in 0 }
        XCTAssertTrue(preview.realSpaceIsBrightFieldDisk)
        let pixels = preview.realSpace.pixels
        XCTAssertEqual(pixels.firstIndex(of: pixels.max()!), 15)
        XCTAssertEqual(pixels[15], 16.0 / 128, accuracy: 1e-7)
        let image = preview.realSpace.normalized()
        XCTAssertGreaterThan(image.max() ?? 0, 0.99)
        XCTAssertLessThan(image.min() ?? 1, 0.01)
        XCTAssertTrue(preview.summary.contains("bright-field disk sum"), preview.summary)
    }

    /// Spread = 1 ulp (2^-24) <= the bound 2 * 2^-24 * max sum|p| (~1.19e-7).
    func testRoundingLevelSpreadFallsBackToTheDisk() async throws {
        let preview = try await self.preview { Float($0 % 2) * 0x1p-24 }
        XCTAssertTrue(preview.realSpaceIsBrightFieldDisk)
    }

    /// Spread = 4 * 2^-24 (~2.4e-7) is above the bound: the total is kept.
    func testSpreadJustAboveTheBoundKeepsTheTotal() async throws {
        let preview = try await self.preview { Float($0 % 2) * 4 * 0x1p-24 }
        XCTAssertFalse(preview.realSpaceIsBrightFieldDisk)
        XCTAssertEqual(preview.summary, "Preview · every position")
    }

    func testAVaryingTotalIsStillTheTotal() async throws {
        let preview = try await self.preview { Float($0) * 0.01 }
        XCTAssertFalse(preview.realSpaceIsBrightFieldDisk)
        XCTAssertEqual(preview.realSpace.pixels[5], 1 - 0.05, accuracy: 1e-5)
    }
}
