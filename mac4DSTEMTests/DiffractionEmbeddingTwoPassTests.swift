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

/// Generates its patterns on demand (nothing stored), so a realistic cube can
/// stream through `compute` without holding it — for the PROFILE_DG probe only.
private actor GeneratedProbeSource: FourDDataSource {
    private let shape: [Int]
    init(ry: Int, rx: Int, qy: Int, qx: Int) { shape = [ry, rx, qy, qx] }

    private func fill(_ out: inout [Float], at offset: Int, position i: Int) {
        let qy = shape[2], qx = shape[3]
        let s = qy / 16
        let centres: [(Int, Int)]
        switch i % 3 {
        case 0: centres = [(4, 4), (4, 11), (11, 4), (11, 11)]
        case 1: centres = [(8, 2), (8, 13)]
        default: centres = [(2, 8), (13, 8)]
        }
        for k in 0..<(qy * qx) { out[offset + k] = 1 + Float((k &* 31 &+ i &* 17) % 13) * 0.05 }
        for (cy, cx) in centres {
            for dy in -s...s { for dx in -s...s {
                out[offset + (cy * s + dy) * qx + cx * s + dx] = 40
            } }
        }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/probe.h5", datasetPath: "/data",
                          shape: shape, dtypeDescription: "float32", chunkShape: nil)
    }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        var out = [Float](repeating: 0, count: shape[2] * shape[3])
        fill(&out, at: 0, position: ry * shape[1] + rx)
        return out
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        let n = shape[2] * shape[3]
        var out = [Float](repeating: 0, count: shape[1] * n)
        for rx in 0..<shape[1] { fill(&out, at: rx * n, position: ry * shape[1] + rx) }
        return out
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels = [Float]()
        for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
        return FourDScanTile(yRange: yRange, scanWidth: shape[1],
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

    /// Timing probe, not a check: `TEST_RUNNER_PROFILE_DG=1 xcodebuild test
    /// -only-testing:mac4DSTEMTests/DiffractionEmbeddingTwoPassTests/testProfileSingleVersusTwoPass`.
    /// One 100 x 100 x 128 x 128 generated cube at the shipped binning (16),
    /// three runs of each path (the cache decides which path runs), wall time
    /// only. The Core package builds -O in Debug since 9fe9440, so this is the
    /// shipped arithmetic. Skipped otherwise.
    func testProfileSingleVersusTwoPass() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PROFILE_DG"] == "1",
                          "timing probe: set TEST_RUNNER_PROFILE_DG=1")
        let source = GeneratedProbeSource(ry: 100, rx: 100, qy: 128, qx: 128)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let settings = DiffractionEmbedding.Settings(binnedSize: 16, components: 10,
                                                     groups: 6, seed: 7)
        var last: [Bool: DiffractionEmbedding.Result] = [:]
        var lines: [String] = []
        func note(_ line: String) {
            print(line)
            lines.append(line)
            // xcodebuild keeps test stdout only inside the .xcresult; a path in
            // TEST_RUNNER_PROFILE_DG_OUT keeps the numbers without it.
            if let path = ProcessInfo.processInfo.environment["PROFILE_DG_OUT"] {
                try? (lines.joined(separator: "\n") + "\n").write(
                    toFile: path, atomically: true, encoding: .utf8)
            }
        }
        for run in 1...3 {
            for cached in [true, false] {
                let clock = ContinuousClock()
                let start = clock.now
                let result = try await DiffractionEmbedding.compute(
                    data: data, descriptor: descriptor, settings: settings,
                    maximumTileRows: 10,
                    cacheBudgetBytes: cached ? DiffractionEmbedding.defaultCacheBudgetBytes : 0,
                    cancellation: nil, progress: nil)
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) * 1e-18
                note(String(format: "PROFILE_DG run %d %@ %.3f s", run,
                            cached ? "single-pass" : "two-pass ", seconds))
                last[cached] = try XCTUnwrap(result)
            }
        }
        var worst: Float = 0
        for (a, b) in zip(last[true]!.coordinates, last[false]!.coordinates) {
            worst = max(worst, abs(a - b))
        }
        note("PROFILE_DG worst coordinate difference \(worst); groups equal: "
             + "\(last[true]!.groupOf == last[false]!.groupOf)")
    }
}
