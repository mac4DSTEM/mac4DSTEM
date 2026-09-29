//
//  DiffractionEmbeddingTwoPassTests.swift
//  The second, non-cached projection path of `DiffractionEmbedding.compute`
//  (the cube's binned vectors re-embedded tile by tile when they do not fit
//  the cache budget) was unreachable from every shipped test, because the
//  512 MB budget was a local constant (open-items "Diffraction groups").
//  `cacheBudgetBytes` makes it reachable; these tests run one small cube
//  through both paths and hold them to the same answer.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Small in-memory `FourDDataSource` (row-major patterns). Redeclared rather
/// than shared: the sibling fixtures are file-private.
private actor TwoPassFixtureSource: FourDDataSource {
    private let shape: [Int]
    private let patterns: [[Float]]

    init(scanHeight: Int, scanWidth: Int, qy: Int, qx: Int, patterns: [[Float]]) {
        precondition(patterns.count == scanHeight * scanWidth)
        self.shape = [scanHeight, scanWidth, qy, qx]
        self.patterns = patterns
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/two-pass-fixture.h5", datasetPath: "/data",
                          shape: shape, dtypeDescription: "float32", chunkShape: nil)
    }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        patterns[ry * view.descriptor.rx + rx]
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var out = [Float]()
        for rx in 0..<view.descriptor.rx {
            out.append(contentsOf: patterns[ry * view.descriptor.rx + rx])
        }
        return out
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

/// Progress values, collected from a `@Sendable` callback.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

final class DiffractionEmbeddingTwoPassTests: XCTestCase {
    private let scanWidth = 6
    private let scanHeight = 5
    private let detectorSize = 16
    private let binnedSize = 8

    /// Three spot layouts (by `position % 3`) on a flat floor with a
    /// per-pixel deterministic ripple, so no two patterns are identical and
    /// the PCA has a real, non-degenerate spectrum.
    private func pattern(position i: Int) -> [Float] {
        let n = detectorSize
        var p = [Float](repeating: 1, count: n * n)
        let centres: [(Int, Int)]
        switch i % 3 {
        case 0: centres = [(4, 4), (4, 11), (11, 4), (11, 11)]
        case 1: centres = [(8, 2), (8, 13)]
        default: centres = [(2, 8), (13, 8)]
        }
        for (cy, cx) in centres {
            for dy in -1...1 { for dx in -1...1 { p[(cy + dy) * n + cx + dx] = 40 } }
        }
        for k in p.indices {
            p[k] += Float((k &* 31 &+ i &* 17) % 13) * 0.05
        }
        return p
    }

    private func makeCube() async throws -> (FourDArray, DatasetDescriptor) {
        let patterns = (0..<(scanWidth * scanHeight)).map { pattern(position: $0) }
        let source = TwoPassFixtureSource(scanHeight: scanHeight, scanWidth: scanWidth,
                                          qy: detectorSize, qx: detectorSize, patterns: patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        return (FourDArray(reader: source, descriptor: descriptor), descriptor)
    }

    private func run(cacheBudgetBytes: Int?, tileRows: Int?)
        async throws -> (DiffractionEmbedding.Result, [Double])
    {
        let (data, descriptor) = try await makeCube()
        let settings = DiffractionEmbedding.Settings(binnedSize: binnedSize, components: 4,
                                                     groups: 3, seed: 7)
        let log = ProgressLog()
        let result: DiffractionEmbedding.Result?
        if let budget = cacheBudgetBytes {
            result = try await DiffractionEmbedding.compute(
                data: data, descriptor: descriptor, settings: settings,
                maximumTileRows: tileRows, cacheBudgetBytes: budget,
                cancellation: nil, progress: { log.add($0) })
        } else {
            result = try await DiffractionEmbedding.compute(
                data: data, descriptor: descriptor, settings: settings,
                maximumTileRows: tileRows,
                cancellation: nil, progress: { log.add($0) })
        }
        return (try XCTUnwrap(result), log.all)
    }

    /// Mutation this catches: the second-pass projection dropping or
    /// mis-indexing a position (e.g. `posIndex` off by one, `centred2` not
    /// re-centred, a wrong row offset across tiles), or the accumulation
    /// being perturbed, since every coordinate must equal the cached path's.
    ///
    /// WHICH PATH RAN is asserted from the progress log, not assumed: the
    /// statistics pass reports 0.80 when the vectors are cached and 0.50 when
    /// they are not, so forcing the cache on both arms would fail here rather
    /// than pass vacuously.
    func testTwoPassProjectionEqualsTheCachedProjection() async throws {
        let (cached, cachedProgress) = try await run(cacheBudgetBytes: nil, tileRows: nil)
        let (twoPass, twoPassProgress) = try await run(cacheBudgetBytes: 0, tileRows: nil)

        XCTAssertTrue(cachedProgress.contains(0.80), "default budget must cache: \(cachedProgress)")
        XCTAssertFalse(cachedProgress.contains(0.50))
        XCTAssertTrue(twoPassProgress.contains(0.50), "budget 0 must take the two-pass path: \(twoPassProgress)")
        XCTAssertFalse(twoPassProgress.contains(0.80))
        XCTAssertEqual(twoPassProgress.last, 1)

        XCTAssertEqual(cached.coordinates.count, twoPass.coordinates.count)
        XCTAssertGreaterThan(cached.coordinates.count, 0)
        // The same per-vector `project` runs on identical Float vectors in
        // both arms; anything beyond float noise is a real difference.
        var worst: Float = 0
        for (a, b) in zip(cached.coordinates, twoPass.coordinates) { worst = max(worst, abs(a - b)) }
        XCTAssertLessThanOrEqual(worst, 1e-5, "two-pass coordinates differ from the cached ones by \(worst)")

        // Everything upstream of the projection is one code path.
        XCTAssertEqual(cached.mean, twoPass.mean)
        XCTAssertEqual(cached.basis, twoPass.basis)
        XCTAssertEqual(cached.explainedVariance, twoPass.explainedVariance)
        XCTAssertEqual(cached.groupOf, twoPass.groupOf)
        XCTAssertEqual(cached.groupCentroids.count, twoPass.groupCentroids.count)
    }

    /// The budget's edge: exactly enough bytes for every binned vector caches;
    /// one Float fewer does not. Mutation: `<=` turned into `<`, or the
    /// `Float` stride dropped from the comparison.
    func testTheBudgetBoundaryIsInclusiveAndCountsFloats() async throws {
        let needed = scanWidth * scanHeight * binnedSize * binnedSize * MemoryLayout<Float>.stride
        let (_, atEdge) = try await run(cacheBudgetBytes: needed, tileRows: nil)
        let (_, below) = try await run(cacheBudgetBytes: needed - MemoryLayout<Float>.stride, tileRows: nil)
        XCTAssertTrue(atEdge.contains(0.80), "exactly enough budget must cache: \(atEdge)")
        XCTAssertTrue(below.contains(0.50), "one Float short must not cache: \(below)")
    }

    /// The two-pass path across several tiles agrees with the single-tile one
    /// (global row offsets in the second pass). Mutation: `globalY` computed
    /// from the local row in pass two.
    func testTwoPassAcrossSeveralTilesMatchesOneTile() async throws {
        let (oneTile, _) = try await run(cacheBudgetBytes: 0, tileRows: nil)
        let (tiled, progress) = try await run(cacheBudgetBytes: 0, tileRows: 2)
        XCTAssertTrue(progress.contains(0.50))
        var worst: Float = 0
        for (a, b) in zip(oneTile.coordinates, tiled.coordinates) { worst = max(worst, abs(a - b)) }
        XCTAssertEqual(oneTile.coordinates.count, tiled.coordinates.count)
        XCTAssertLessThanOrEqual(worst, 1e-5, "tiled two-pass differs by \(worst)")
        XCTAssertEqual(oneTile.groupOf, tiled.groupOf)
    }
}
