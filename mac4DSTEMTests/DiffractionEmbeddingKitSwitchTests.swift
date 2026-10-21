import XCTest
import CuboEmbedding
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The CuboEmbedding 0.6.0 switch (2026-10-21): the streamed covariance, `PCA.fit(covariance:)`, the vDSP
/// `binnedVector` and k-means moved to the kit. `Fixtures/Embedding/embedding-baseline-2026-10-21.json` was written by the
/// app's own code at e333ec41, before the copies were deleted; these tests hold the kit-backed `compute` to it.
///
/// DEVIATION (component sign): the old eigensolver left each axis with LAPACK's arbitrary sign; the kit gives each
/// axis the sign that makes its largest-magnitude entry positive. The comparison is therefore up to one sign per
/// component (basis and coordinates flip together). Groups, variances and the mean do not depend on it.
final class DiffractionEmbeddingKitSwitchTests: XCTestCase {

    private actor Source: FourDDataSource {
        private let shape: [Int]
        private let patterns: [[Float]]
        init(h: Int, w: Int, qy: Int, qx: Int, patterns: [[Float]]) {
            shape = [h, w, qy, qx]; self.patterns = patterns
        }
        func discoverPrimaryDataset() throws -> DatasetDescriptor {
            DatasetDescriptor(filePath: "/synthetic/kit-switch.h5", datasetPath: "/data", shape: shape,
                              dtypeDescription: "float32", chunkShape: nil)
        }
        nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
        func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { patterns[ry * view.descriptor.rx + rx] }
        func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
            var out = [Float]()
            for rx in 0..<view.descriptor.rx { out.append(contentsOf: patterns[ry * view.descriptor.rx + rx]) }
            return out
        }
        func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
            var pixels = [Float]()
            for ry in yRange { pixels.append(contentsOf: try readScanRow(view, ry: ry)) }
            return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx, detectorHeight: shape[2],
                                 detectorWidth: shape[3], pixels: pixels)
        }
        func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
        func pixelCalibration() -> PixelCalibration? { nil }
    }

    static let scanW = 16, scanH = 25, qy = 32, qx = 30, binned = 8

    /// The harness fixture of `tools/harnesses/embedding-pca-parity`: eight separated components, 400 positions.
    static func patterns() -> [[Float]] {
        var seed: UInt64 = 0xC0FFEE
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 1_000_000) / 1_000_000
        }
        var out = [[Float]]()
        for p in 0..<(scanW * scanH) {
            var img = [Float](repeating: 0, count: qy * qx)
            let base: [Float] = [420, 210, 100, 46, 21, 9.5, 4.2, 1.8]
            for k in 0..<8 {
                let amp = base[k] * (0.45 + 1.1 * rnd())
                let cy = 4 + (k % 4) * 7, cx = 3 + (k / 4) * 13
                for dy in -2...2 { for dx in -2...2 {
                    let y = cy + dy + (p % 3), x = cx + dx
                    if y >= 0, y < qy, x >= 0, x < qx { img[y * qx + x] += amp }
                } }
            }
            for i in 0..<img.count { img[i] += 3 + 2 * rnd() }
            out.append(img)
        }
        return out
    }

    static let embedProbes = [0, 137, 399]

    static func run(cacheBudgetBytes: Int) async throws -> DiffractionEmbedding.Result {
        let source = Source(h: scanH, w: scanW, qy: qy, qx: qx, patterns: patterns())
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let r = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor,
            settings: .init(binnedSize: binned, components: 8, groups: 4, seed: 7),
            maximumTileRows: 7, cacheBudgetBytes: cacheBudgetBytes, cancellation: nil, progress: nil)
        return try XCTUnwrap(r)
    }

    static func vector(_ pattern: [Float]) throws -> [Float] {
        try DiffractionFeatures.binnedVector(pattern: pattern, rows: qy, columns: qx, binnedSize: binned,
                                             implementation: .accelerate)
    }

    static func embedProbeVectors() throws -> [[Float]] {
        let all = patterns()
        return try embedProbes.map { try vector(all[$0]) }
    }

    private static var baselineURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Embedding/embedding-baseline-2026-10-21.json")
    }

    func testComputeMatchesTheBaselineWrittenByTheAppsOwnCode() async throws {
        let cached = try await Self.run(cacheBudgetBytes: DiffractionEmbedding.defaultCacheBudgetBytes)
        let twoPass = try await Self.run(cacheBudgetBytes: 0)
        let probes = try Self.embedProbeVectors()
        if !FileManager.default.fileExists(atPath: Self.baselineURL.path) {
            let json: [String: Any] = [
                "coordinates": cached.coordinates.map(Double.init), "mean": cached.mean.map(Double.init),
                "basis": cached.basis.map(Double.init), "explainedVariance": cached.explainedVariance.map(Double.init),
                "groupOf": cached.groupOf, "centroids": cached.groupCentroids.map(Double.init),
                "embed": probes.map { $0.map(Double.init) },
            ]
            try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                .write(to: Self.baselineURL)
            XCTFail("baseline written to \(Self.baselineURL.path)")
            return
        }
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.baselineURL)) as! [String: Any]
        func doubles(_ k: String) -> [Double] { base[k] as! [Double] }

        for (name, r) in [("cached", cached), ("two-pass", twoPass)] {
            let k = r.componentCount, dims = Self.binned * Self.binned, n = r.scanWidth * r.scanHeight
            XCTAssertEqual(k, 8)
            XCTAssertEqual(r.groupOf, base["groupOf"] as! [Int], name)
            for (a, b) in zip(r.mean, doubles("mean")) { XCTAssertEqual(Double(a), b, accuracy: 1e-5 * max(1, abs(b)), name) }
            for (a, b) in zip(r.explainedVariance, doubles("explainedVariance")) {
                XCTAssertEqual(Double(a), b, accuracy: 1e-6, name)
            }
            let oldBasis = doubles("basis"), oldCoords = doubles("coordinates")
            let oldCentroids = doubles("centroids")
            for c in 0..<k {
                // One sign per component, read off the largest basis entry.
                var big = 0
                for i in 1..<dims where abs(oldBasis[c * dims + i]) > abs(oldBasis[c * dims + big]) { big = i }
                let s: Double = (oldBasis[c * dims + big] < 0) == (r.basis[c * dims + big] < 0) ? 1 : -1
                for i in 0..<dims {
                    XCTAssertEqual(Double(r.basis[c * dims + i]), s * oldBasis[c * dims + i], accuracy: 2e-5, "\(name) basis \(c)")
                }
                var scale = 0.0
                for p in 0..<n { scale = max(scale, abs(oldCoords[p * k + c])) }
                for p in 0..<n {
                    XCTAssertEqual(Double(r.coordinates[p * k + c]), s * oldCoords[p * k + c], accuracy: 1e-4 * scale, "\(name) coordinates")
                }
                for g in 0..<r.groupCount {
                    XCTAssertEqual(Double(r.groupCentroids[g * k + c]), s * oldCentroids[g * k + c], accuracy: 1e-4 * scale, "\(name) centroid")
                }
            }
        }
        for (a, b) in zip(probes, base["embed"] as! [[Double]]) {
            for (x, y) in zip(a, b) { XCTAssertEqual(Double(x), y, accuracy: 1e-6 * max(1, abs(y))) }
        }
    }

    /// Each component carries the kit's sign: its largest-magnitude basis entry is positive.
    func testComponentsCarryTheKitsProvisionalSign() async throws {
        let r = try await Self.run(cacheBudgetBytes: DiffractionEmbedding.defaultCacheBudgetBytes)
        let dims = Self.binned * Self.binned
        for c in 0..<r.componentCount {
            var big = 0
            for i in 1..<dims where abs(r.basis[c * dims + i]) > abs(r.basis[c * dims + big]) { big = i }
            XCTAssertGreaterThan(r.basis[c * dims + big], 0, "component \(c)")
        }
    }

    /// A token cancelled before the run returns nil.
    func testCancelledRunReturnsNil() async throws {
        let source = Source(h: Self.scanH, w: Self.scanW, qy: Self.qy, qx: Self.qx, patterns: Self.patterns())
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let pre = AnalysisCancellationToken(); pre.cancel()
        let none = try await DiffractionEmbedding.compute(
            data: data, descriptor: descriptor, settings: .init(), cancellation: pre, progress: nil)
        XCTAssertNil(none)
    }
}
