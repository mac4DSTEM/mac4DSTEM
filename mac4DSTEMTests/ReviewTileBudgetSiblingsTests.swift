import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Slot 4¾ lane L (pre-release review d1 residual, 2026-10-02).
///
/// Lane D sized `FourDArray.scanTileRows` at the reader's pre-bin READ extent.
/// Two sibling formulas still sized their tiles from the post-bin view and so
/// bypassed it: the virtual-image pass (`AppState.virtualDetectorProgressTileRows`,
/// 16 MiB, passed as `maximumTileRows`) and parallax preprocessing
/// (`ParallaxPreprocessor.resolvedTileRows`, 64 MiB when the app passes nil).
/// The reader allocates the tile pre-bin, so the transient was bin² × the target.
/// Both are now sized at the read extent; neither product depends on the
/// grouping, which the last two tests prove on the Demo cube at bin 1, 2 and 4.
@MainActor
final class ReviewTileBudgetSiblingsTests: XCTestCase {

    private let float = MemoryLayout<Float>.stride
    private let virtualTarget = 16 * 1024 * 1024
    private let parallaxTarget = 64 * 1024 * 1024

    /// A scan far taller than any tile, so no row count below clamps at ry.
    /// Nothing is read: both formulas are arithmetic over the view.
    private func source(rx: Int, qy: Int = 256, qx: Int = 256) -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/nonexistent/review-tile-siblings.h5", datasetPath: "/data",
                          shape: [1 << 20, rx, qy, qx], dtypeDescription: "uint16", chunkShape: nil)
    }

    private func view(_ source: DatasetDescriptor, bin: Int, crop: AxisCrop? = nil) throws -> LoadView {
        try LoadView(source: source, specification: LoadSpecification(detectorCrop: crop, detectorBin: bin))
    }

    private func readRowBytes(_ view: LoadView) -> Int {
        view.descriptor.rx * (view.readDetectorCrop?.height ?? view.source.qy)
            * (view.readDetectorCrop?.width ?? view.source.qx) * float
    }

    // MARK: - The budget holds at the read extent

    /// Mutation: size from the post-bin view (HEAD's `descriptor.qy * descriptor.qx`) — at bin 2 the
    /// rows grow 4× and the pre-bin tile is 64 MiB against a 16 MiB target.
    func testVirtualImageTileIsBudgetedAtTheReadExtent() throws {
        let src = source(rx: 16)   // pre-bin row 4 MiB → 4 rows at every bin
        let one = AppState.virtualDetectorProgressTileRows(for: try view(src, bin: 1))
        XCTAssertGreaterThan(one, 1, "fixture must not sit at the ≥ 1 floor")
        for bin in [2, 4, 8] {
            let v = try view(src, bin: bin)
            let rows = AppState.virtualDetectorProgressTileRows(for: v)
            XCTAssertEqual(rows, one, "bin \(bin) reads the same pre-bin extent as bin 1")
            XCTAssertLessThanOrEqual(rows * readRowBytes(v), virtualTarget,
                                     "bin \(bin): the reader's pre-bin tile exceeds 16 MiB")
        }
    }

    /// Mutation: the same post-bin sizing in `resolvedTileRows` — at bin 2 the pre-bin tile is 256 MiB
    /// against a 64 MiB target (4 GiB at bin 8).
    func testParallaxTileIsBudgetedAtTheReadExtent() throws {
        let src = source(rx: 64)   // pre-bin row 16 MiB → 4 rows at every bin
        let one = ParallaxPreprocessor.resolvedTileRows(view: try view(src, bin: 1), requested: nil)
        XCTAssertGreaterThan(one, 1, "fixture must not sit at the ≥ 1 floor")
        for bin in [2, 4, 8] {
            let v = try view(src, bin: bin)
            let rows = ParallaxPreprocessor.resolvedTileRows(view: v, requested: nil)
            XCTAssertEqual(rows, one, "bin \(bin) reads the same pre-bin extent as bin 1")
            XCTAssertLessThanOrEqual(rows * readRowBytes(v), parallaxTarget,
                                     "bin \(bin): the reader's pre-bin tile exceeds 64 MiB")
        }
        XCTAssertEqual(ParallaxPreprocessor.resolvedTileRows(view: try view(src, bin: 4), requested: 3), 3,
                       "an explicit tileRows (the parity harness's 1) still wins")
    }

    /// Bin 1 is HEAD's arithmetic exactly — full extent and detector-cropped — and the edge remainder
    /// trimmed before the read is the extent budgeted (250 → 248 at bin 4).
    /// Mutation: read the source detector whatever the crop (`view.source.qy` / `.qx`), which also
    /// fires at bin 1 when a crop is set.
    func testBinOneRowsUnchangedAndTheTrimmedExtentIsBudgeted() throws {
        let src = source(rx: 16)
        let crop = AxisCrop(yOffset: 10, xOffset: 20, height: 100, width: 120)
        for v in [try view(src, bin: 1), try view(src, bin: 1, crop: crop)] {
            let d = v.descriptor
            let headRow = d.rx * d.qy * d.qx * float     // HEAD's formula, from the view
            XCTAssertEqual(AppState.virtualDetectorProgressTileRows(for: v),
                           max(1, min(d.ry, virtualTarget / headRow)))
            XCTAssertEqual(ParallaxPreprocessor.resolvedTileRows(view: v, requested: nil),
                           max(1, min(d.ry, parallaxTarget / headRow)))
        }
        let trimmed = try view(source(rx: 16, qy: 250, qx: 250), bin: 4)
        XCTAssertEqual(trimmed.readDetectorCrop?.height, 248)
        XCTAssertEqual(AppState.virtualDetectorProgressTileRows(for: trimmed),
                       max(1, virtualTarget / (16 * 248 * 248 * float)))
        XCTAssertEqual(ParallaxPreprocessor.resolvedTileRows(view: trimmed, requested: nil),
                       max(1, parallaxTarget / (16 * 248 * 248 * float)))
    }

    // MARK: - No number depends on the grouping (Demo cube 12 × 12 × 64 × 64)

    private func demoView(bin: Int) throws -> LoadView {
        try LoadView(source: DemoFourDDataSource.descriptor,
                     specification: LoadSpecification(detectorBin: bin))
    }

    private func bits(_ values: [Float]) -> [UInt32] { values.map(\.bitPattern) }

    /// Every virtual-detector geometry the app runs, through the production tile rows (the whole
    /// 12-row scan in one tile on this cube) against 1-row tiles and uneven 5-row tiles (5, 5, 2):
    /// bit-identical at bin 1, 2 and 4.
    /// Mutation: a per-tile cross-position reducer in `VirtualDetector.tiled` (each tile's image
    /// divided by that tile's maximum before it is copied out) — a grouping-dependent number.
    func testVirtualImageIsBitIdenticalForAnyTileGrouping() async throws {
        for bin in [1, 2, 4] {
            let v = try demoView(bin: bin)
            let d = v.descriptor
            let data = FourDArray(reader: DemoFourDDataSource(), view: v)
            let c = Float(d.qx) / 2
            let shapes: [DetectorShape] = [
                .circle(centerX: c, centerY: c, radius: c / 4),
                .rectangle(xMin: Int(c) - 3, xMax: Int(c) + 3, yMin: Int(c) - 2, yMax: Int(c) + 4),
                .point(x: Int(c) + 1, y: Int(c) - 1),
            ]
            let aperture = Aperture(centerX: c, centerY: c, inner: c / 8, outer: c / 2)
            let production = AppState.virtualDetectorProgressTileRows(for: v)
            XCTAssertEqual(production, d.ry, "bin \(bin): the Demo cube is one tile in production")
            var reference: [[UInt32]] = []
            for rows in [production, 1, 5] {
                var images: [[UInt32]] = []
                for shape in shapes {
                    images.append(bits(try await VirtualDetector.tiledImage(
                        data: data, descriptor: d, shape: shape, maximumTileRows: rows).pixels))
                }
                images.append(bits(try await VirtualDetector.tiledRun(
                    data: data, descriptor: d, aperture: aperture, maximumTileRows: rows).pixels))
                XCTAssertTrue(images.allSatisfy { image in image.count == d.ry * d.rx })
                XCTAssertTrue(images.allSatisfy { image in image.contains { $0 != 0 } },
                              "bin \(bin): an empty image proves nothing")
                if reference.isEmpty { reference = images; continue }
                for (index, image) in images.enumerated() {
                    XCTAssertEqual(image, reference[index],
                                   "bin \(bin), geometry \(index): \(rows)-row tiles differ from one tile")
                }
            }
        }
    }

    /// Parallax preprocessing through `ParallaxPreprocessor.run` with the app's nil tileRows (the
    /// production rows: one tile on this cube) against 1-row and 5-row tiles: every product
    /// bit-identical at bin 1, 2 and 4.
    /// Mutation: pass 2's `weightedSums` accumulated per tile in a Float partial and added at the end
    /// of the tile — the classic regrouping of a cross-position sum.
    func testParallaxPreprocessingIsBitIdenticalForAnyTileGrouping() async throws {
        for bin in [1, 2, 4] {
            let v = try demoView(bin: bin)
            let d = v.descriptor
            let source = DemoFourDDataSource()
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 5, reciprocalSamplingInvAngstrom: 0.02 * Double(bin),
                energyEV: 200_000, wavelengthAngstrom: 0.0251,
                originQX: Double(d.qy) / 2, originQY: Double(d.qx) / 2, rotationRad: 0, transpose: false)
            XCTAssertEqual(ParallaxPreprocessor.resolvedTileRows(view: v, requested: nil), d.ry,
                           "bin \(bin): the Demo cube is one tile in production")
            var reference: ParallaxPreprocessResult?
            for rows in [nil, 1, 5] as [Int?] {
                var options = ParallaxPreprocessOptions()
                options.tileRows = rows
                let result = try await ParallaxPreprocessor.run(
                    source: source, view: v, calibration: calibration, options: options)
                XCTAssertGreaterThan(result.brightFieldPixelCount, 0, "bin \(bin): no bright field selected")
                guard let ref = reference else { reference = result; continue }
                let label = "bin \(bin), \(rows ?? 0)-row tiles vs one tile"
                XCTAssertEqual(result.detectorMask, ref.detectorMask, label)
                XCTAssertEqual(result.detectorIndices, ref.detectorIndices, label)
                XCTAssertEqual(bits(result.edgeWindow), bits(ref.edgeWindow), label)
                XCTAssertEqual(bits(result.normalizedStack), bits(ref.normalizedStack), label)
                XCTAssertEqual(bits(result.unshiftedStack), bits(ref.unshiftedStack), label)
                XCTAssertEqual(bits(result.incoherentBF), bits(ref.incoherentBF), label)
                XCTAssertEqual(result.initialError.bitPattern, ref.initialError.bitPattern, label)
            }
        }
    }
}
