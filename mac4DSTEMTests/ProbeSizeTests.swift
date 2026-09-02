import XCTest
import DSTEMCore
import DSTEMSession
import Metal
@testable import mac4DSTEM

/// Coverage for `OriginCalibration.probeSize` and — the load-bearing pin —
/// WHICH statistic `tiledRun` feeds it. Until 2026-09-01 the estimator had no
/// unit coverage at all, and the app fed the pixel-wise MAX pattern: every
/// Bragg disk seen anywhere in the scan was counted as probe area (SPED_MgO
/// read 14.1 px against a ~3 px disk, and the same specimen over a 4x larger
/// scan read 19.1 — a per-pattern property cannot grow with scan area).
/// Record: the probeSize entry in docs/open-items.md;
/// `tools/origin-fit-diagnostics/run.sh probe-size` re-runs it on real data.
final class ProbeSizeTests: XCTestCase {

    private static let q = 64

    /// Flat-top disk, drawn with max() so overlaps don't sum.
    private static func drawDisk(into dp: inout [Float], cx: Double, cy: Double,
                                 radius: Double, intensity: Float) {
        for y in 0..<q { for x in 0..<q {
            let dx = Double(x) - cx, dy = Double(y) - cy
            if dx * dx + dy * dy <= radius * radius {
                dp[y * q + x] = max(dp[y * q + x], intensity)
            }
        } }
    }

    func testProbeSizeRecoversACleanDiskRadius() {
        var dp = [Float](repeating: 0, count: Self.q * Self.q)
        Self.drawDisk(into: &dp, cx: 31.5, cy: 31.5, radius: 6, intensity: 100)
        let (r, x0, y0) = OriginCalibration.probeSize(dp: dp, qy: Self.q, qx: Self.q)
        XCTAssertEqual(r, 6, accuracy: 0.5)
        XCTAssertEqual(x0, 31.5, accuracy: 0.5)
        XCTAssertEqual(y0, 31.5, accuracy: 0.5)
    }

    /// The failure mode, pinned as documentation: bright Bragg content above
    /// the threshold band is counted as probe area, so the equivalent-circle
    /// radius grows with the number of disks. If this ever stops
    /// over-measuring, the estimator's semantics changed and every consumer's
    /// assumptions need re-checking — it is why the max-union input was
    /// unsafe, not a behaviour to "fix" in probeSize itself.
    func testBraggContentAboveThresholdInflatesTheRadius() {
        var dp = [Float](repeating: 0, count: Self.q * Self.q)
        Self.drawDisk(into: &dp, cx: 31.5, cy: 31.5, radius: 4, intensity: 100)
        for (sx, sy) in [(12, 12), (50, 12), (12, 50), (50, 50),
                         (31, 10), (31, 53), (10, 31), (53, 31)] {
            Self.drawDisk(into: &dp, cx: Double(sx), cy: Double(sy), radius: 4, intensity: 80)
        }
        let (r, _, _) = OriginCalibration.probeSize(dp: dp, qy: Self.q, qx: Self.q)
        XCTAssertGreaterThan(
            r, 9, "nine equal-area disks must read ~3x one disk's radius (12), got \(r)"
        )
    }

    /// The 2026-09-01 fix itself: `tiledRun` measures the probe on the MEAN
    /// pattern, not the max. The cube puts bright satellite disks in exactly
    /// one scan position of sixteen, so the max carries them at full strength
    /// (above threshold, inflated) while the mean carries them at 1/16 —
    /// above only the lowest few thresholds, so the trusted plateau reads
    /// near the beam radius (measured 4.27 vs 4.03 beam-only; the Gate B
    /// refuter's nit, kept honest here). Reverting the call site to the
    /// max makes this fail with the inflated figure.
    func testTiledRunMeasuresTheProbeOnTheMeanPattern() async throws {
        let source = SatelliteFourDDataSource()
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        guard let fit = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane
        ) else { return XCTFail("tiledRun returned nil") }
        let (rMean, _, _) = OriginCalibration.probeSize(dp: fit.meanDP, qy: d.qy, qx: d.qx)
        let (rMax, _, _) = OriginCalibration.probeSize(dp: fit.maxDP, qy: d.qy, qx: d.qx)
        XCTAssertGreaterThan(
            rMax, rMean * 1.5,
            "fixture broken: max and mean no longer discriminate (max \(rMax), mean \(rMean))"
        )
        XCTAssertEqual(
            fit.probeRadius, rMean, accuracy: 0.01,
            "tiledRun's radius must come from the MEAN pattern"
        )
    }

    /// Gate B refuter, 2026-09-01: the resident-cube variant
    /// `OriginCalibration.run(cube:)` has NO callers anywhere in the repo, so a
    /// mutation reverting ONLY its call site back to maxDP survived every
    /// existing gate (verified by running it: tiledRun's pin stayed green while
    /// `run(cube:)` returned the inflated 8.44 px against the mean's 4.27).
    /// This pins the variant itself, so a future caller resurrects the
    /// mean-pattern measurement rather than whichever statistic the then-dead
    /// code happened to feed.
    func testResidentCubeRunMeasuresTheProbeOnTheMeanPattern() async throws {
        let source = SatelliteFourDDataSource()
        let d = try await source.discoverPrimaryDataset()
        let cube = await source.fullCube()
        let buffer = try XCTUnwrap(
            MetalEngine.shared.device.makeBuffer(
                bytes: cube, length: cube.count * MemoryLayout<Float>.stride
            ),
            "could not allocate the satellite cube as an MTLBuffer"
        )
        guard let fit = try OriginCalibration.run(cube: buffer, descriptor: d) else {
            return XCTFail("run(cube:) returned nil")
        }
        let (rMean, _, _) = OriginCalibration.probeSize(dp: fit.meanDP, qy: d.qy, qx: d.qx)
        let (rMax, _, _) = OriginCalibration.probeSize(dp: fit.maxDP, qy: d.qy, qx: d.qx)
        XCTAssertGreaterThan(
            rMax, rMean * 1.5,
            "fixture broken: max and mean no longer discriminate (max \(rMax), mean \(rMean))"
        )
        XCTAssertEqual(
            fit.probeRadius, rMean, accuracy: 0.01,
            "run(cube:)'s radius must come from the MEAN pattern"
        )
    }
}

/// 4x4 scan of a 64x64 detector: an identical central beam at every position,
/// and bright satellite disks in exactly ONE — the max/mean discriminator in
/// miniature.
private actor SatelliteFourDDataSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/satellite.h5", datasetPath: "/data",
        shape: [4, 4, 64, 64], dtypeDescription: "float32", chunkShape: nil
    )
    private let cube: [Float]

    init() {
        let d = Self.descriptor
        let q = d.qx
        func draw(into dp: inout [Float], cx: Double, cy: Double,
                  radius: Double, intensity: Float) {
            for y in 0..<q { for x in 0..<q {
                let dx = Double(x) - cx, dy = Double(y) - cy
                if dx * dx + dy * dy <= radius * radius {
                    dp[y * q + x] = max(dp[y * q + x], intensity)
                }
            } }
        }
        var plain = [Float](repeating: 0, count: q * q)
        draw(into: &plain, cx: 31.5, cy: 31.5, radius: 4, intensity: 100)
        var bright = plain
        for c in [(12.0, 12.0), (50.0, 12.0), (12.0, 50.0), (50.0, 50.0)] {
            draw(into: &bright, cx: c.0, cy: c.1, radius: 4, intensity: 90)
        }
        var all: [Float] = []
        all.reserveCapacity(d.ry * d.rx * q * q)
        for ry in 0..<d.ry { for rx in 0..<d.rx {
            all.append(contentsOf: (ry == 0 && rx == 0) ? bright : plain)
        } }
        cube = all
    }

    /// The whole cube, for tests that hand it to the resident-cube pipeline.
    func fullCube() -> [Float] { cube }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        view.scanRow(fromFullCube: cube, ry: ry)
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        view.scanTile(fromFullCube: cube, yRange: yRange)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}
