import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// C14 (lane Q, 2026-09-30): `OriginCalibration.windowSensitivityPixels`, the
/// median distance between the origin the refine step finds at its shipped
/// window (k = 1.2) and at a wide one (k = 2.5), on a strided sample.
///
/// A QUANTITY, never a verdict: no test here asserts a gate, because none
/// exists. What is pinned is that the number tells the two probe shapes apart
/// — the S14-D mechanism (`docs/archive/v4/s14d-origin-refine-gateD-2026-09-30.md`):
/// a probe with a ring outside its core is moved several pixels by the window,
/// a compact one is not moved at all.
///
/// The fixtures are the S14-D F2 shapes, noiseless, on a 64 x 64 detector so a
/// unit test can afford them: disk `0.5 erfc((ρ − 3)/√2)` (compact) and the
/// same disk plus a ring `0.72 exp(−(ρ − 8.5)²/(2·1.5²))` (the bullseye), each
/// 4 x 4 supersampled over a 6 x 6 scan of sub-pixel centres.
final class OriginWindowSensitivityTests: XCTestCase {

    func testACompactProbeDoesNotCareWhichWindowItGets() async throws {
        let sensitivity = try await sensitivity(ring: false)
        XCTAssertLessThan(sensitivity, 0.1,
                          "a compact probe must read < 0.1 px between k 1.2 and 2.5, got \(sensitivity)")
    }

    /// Break it by returning 0 from `windowSensitivityPixels` (or by measuring
    /// both readings at the same window): the compact test stays green, this
    /// one goes red.
    func testARingedProbeMovesWithTheWindow() async throws {
        let sensitivity = try await sensitivity(ring: true)
        XCTAssertGreaterThan(sensitivity, 1,
                             "a probe with a ring outside its core must read > 1 px, got \(sensitivity)")
    }

    /// `tiledRun` carries the same number — the app reads it from there. Break
    /// it by returning nil (or 0) in `tiledRun`'s result.
    func testTiledRunReportsTheSameQuantity() async throws {
        let source = RingedProbeSource(ring: true)
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        let run = try await OriginCalibration.tiledRun(data: data, descriptor: d)
        let fit = try XCTUnwrap(run)
        let reported = try XCTUnwrap(fit.windowSensitivityPixels,
                                     "tiledRun must report the window sensitivity")
        let directRun = try await OriginCalibration.windowSensitivityPixels(
            data: data, descriptor: d, probeRadius: fit.probeRadius)
        let direct = try XCTUnwrap(directRun)
        XCTAssertEqual(reported, direct, accuracy: 1e-6)
        XCTAssertGreaterThan(reported, 1)
    }

    /// The sample is strided and bounded: ≤ 200 positions whatever the scan, and
    /// every position of a small one. Break it by flooring the step
    /// (`total / limit`), which admits 201 positions at 10 201.
    func testTheSampleIsStridedAndNeverExceedsTheLimit() {
        for total in [10_000, 10_201, 29_241, 201, 200, 199] {
            let indices = OriginCalibration.windowSensitivitySampleIndices(total: total)
            XCTAssertLessThanOrEqual(indices.count, 200, "total \(total) gave \(indices.count)")
            XCTAssertEqual(indices.first, 0)
            XCTAssertLessThan(indices.last ?? total, total)
        }
        XCTAssertEqual(OriginCalibration.windowSensitivitySampleIndices(total: 10_000).count, 200)
        XCTAssertEqual(OriginCalibration.windowSensitivitySampleIndices(total: 7), Array(0..<7))
        XCTAssertEqual(OriginCalibration.windowSensitivitySampleIndices(total: 0), [])
    }

    /// The sample is one Metal buffer on every origin calibration; a 2048² float
    /// detector is 16 MB a pattern, so 200 positions would be 3.4 GB (refuter,
    /// 2026-09-30). The byte budget must cut the count, never grow the buffer.
    func testTheSampleIsBoundedByBytesOnALargeDetector() {
        let patternBytes = 2048 * 2048 * MemoryLayout<Float>.stride
        let indices = OriginCalibration.windowSensitivitySampleIndices(
            total: 10_000, patternBytes: patternBytes)
        XCTAssertEqual(indices.count, OriginCalibration.windowSensitivitySampleBudgetBytes / patternBytes)
        XCTAssertLessThanOrEqual(indices.count * patternBytes,
                                 OriginCalibration.windowSensitivitySampleBudgetBytes)
        XCTAssertGreaterThanOrEqual(indices.count, 1)
        // A small detector keeps the position limit.
        XCTAssertEqual(OriginCalibration.windowSensitivitySampleIndices(
            total: 10_000, patternBytes: 64 * 64 * 4).count, 200)
    }

    // MARK: - Fixtures

    private func sensitivity(ring: Bool) async throws -> Float {
        let source = RingedProbeSource(ring: ring)
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        let run = try await OriginCalibration.tiledRun(data: data, descriptor: d)
        let fit = try XCTUnwrap(run, "tiledRun returned nil")
        // The mechanism needs the radius the app would measure: the ringed
        // fixture's r lies inside the ring's inner flank (S14-D: 6.55 px).
        XCTAssertEqual(fit.probeRadius, ring ? 6.5 : 3.0, accuracy: ring ? 1.0 : 0.6,
                       "fixture off-shape: probe radius \(fit.probeRadius)")
        let measured = try await OriginCalibration.windowSensitivityPixels(
            data: data, descriptor: d, probeRadius: fit.probeRadius)
        let value = try XCTUnwrap(measured)
        // For the record: the value lands in the .xcresult's activity list
        // (xcresulttool get test-results activities); nothing asserts on it.
        XCTContext.runActivity(named: String(
            format: "window sensitivity, %@ probe, radius %.3f px: %.4f px",
            ring ? "ringed" : "compact", fit.probeRadius, value)) { _ in }
        return value
    }
}

/// 6 x 6 scan, 64 x 64 detector; every pattern the same probe at its own
/// sub-pixel centre (31.0 ... 32.25), background 8, peak 3000 counts.
private actor RingedProbeSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/ringed-probe.h5", datasetPath: "/data",
        shape: [6, 6, 64, 64], dtypeDescription: "float32", chunkShape: nil
    )
    private let cube: [Float]

    init(ring: Bool) {
        let d = Self.descriptor
        let q = d.qx
        func profile(_ rho: Double) -> Double {
            var v = 0.5 * erfc((rho - 3.0) / (2.0.squareRoot() * 1.0))
            if ring { v += 0.72 * exp(-(rho - 8.5) * (rho - 8.5) / (2 * 1.5 * 1.5)) }
            return v
        }
        var all = [Float]()
        all.reserveCapacity(d.ry * d.rx * q * q)
        for ry in 0..<d.ry {
            for rx in 0..<d.rx {
                let cx = 31.0 + 0.25 * Double(rx), cy = 31.0 + 0.25 * Double(ry)
                for y in 0..<q {
                    for x in 0..<q {
                        var sum = 0.0
                        for sy in 0..<4 {
                            for sx in 0..<4 {
                                let px = Double(x) - 0.5 + (Double(sx) + 0.5) / 4
                                let py = Double(y) - 0.5 + (Double(sy) + 0.5) / 4
                                sum += profile(((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot())
                            }
                        }
                        all.append(Float(8 + 3000 * sum / 16))
                    }
                }
            }
        }
        cube = all
    }

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
