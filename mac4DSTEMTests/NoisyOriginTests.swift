import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The beam centre on noisy cubes: a soft-edged probe of radius 4 px on a 64 x 64 detector, centred on a planted
/// descan plane, Poisson counts at a chosen dose over a flat background. `noisy_origin_reference.py` draws the same
/// cube with the same generator and runs py4DSTEM's `get_origin` and `fit_origin` on it.
///
/// Measured 2026-10-31 (app = `OriginCalibration.tiledRun`, CuboKit 0.9.0; py4DSTEM = `get_origin` on `dp_max`, then
/// `fit_origin` plane). "Fit error" is the largest distance of the fitted origin from the planted one over the scan.
///
/// | peak, background (counts/px) | app fit error | py4DSTEM fit error | app RMS residual | app mean-pattern r | window sensitivity |
/// |---|---|---|---|---|---|
/// | 2000, 0   | 0.015 px | 0.015 px | 0.015 | 4.00 | 0.000 |
/// | 50, 0.5   | 0.018 px | 0.021 px | 0.060 | 4.01 | 0.046 |
/// | 10, 0.5   | 0.042 px | 0.480 px | 0.258 | 4.81 | 0.722 |
/// | 3, 0.5    | 2.69 px  | 4.59 px  | 1.20  | 8.26 | 3.28  |
/// | 1, 0.2    | 3.19 px  | 2.80 px  | 2.08  | 9.13 | 4.02  |
///
/// The gate (`originFitIsSane`: full-scan RMS residual at most the probe radius) trusts every row, including the two
/// that are 2.7 and 3.2 px off: the residual measures scatter about the fit, not the fit's bias, and the radius it is
/// compared with grows with the noise (8.3 px for a 4 px probe). Window sensitivity tracks the bias.
final class NoisyOriginTests: XCTestCase {

    private struct Run {
        let fitError: Double
        let sane: Bool
        let sensitivity: Float?
    }

    private func run(peak: Double, background: Double) async throws -> Run {
        let source = NoisyBeamSource(peak: peak, background: background, seed: 7)
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        let fit = try await XCTUnwrapAsync(await OriginCalibration.tiledRun(data: data, descriptor: d))
        var fitError = 0.0
        for r in 0..<d.ry { for c in 0..<d.rx {
            let i = r * d.rx + c
            let t = NoisyBeamSource.truth(row: r, column: c)
            fitError = max(fitError, hypot(Double(fit.origin.fittedX[i]) - t.x, Double(fit.origin.fittedY[i]) - t.y))
        } }
        var calibration = DSTEMCore.Calibration()
        calibration.origin = fit.origin
        calibration.probeRadius = fit.meanProbeRadius
        return Run(fitError: fitError, sane: calibration.originFitIsSane, sensitivity: fit.windowSensitivityPixels)
    }

    /// Clean and moderate dose: the fitted origin is within 0.03 px of the planted plane (py4DSTEM 0.015 and 0.021).
    func testCleanAndModerateDoseFitTheBeamCentre() async throws {
        for (peak, background) in [(2000.0, 0.0), (50.0, 0.5)] {
            let r = try await run(peak: peak, background: background)
            XCTAssertLessThan(r.fitError, 0.03, "peak \(peak)")
            XCTAssertTrue(r.sane)
        }
    }

    /// Ten counts per pixel in the disk: the app's iterated window stays within 0.1 px (0.042) where py4DSTEM's single
    /// masked centre of mass is 0.48 px off. Window sensitivity reads 0.72 px.
    func testLowDoseFitStaysWithinATenthOfAPixel() async throws {
        let r = try await run(peak: 10, background: 0.5)
        XCTAssertLessThan(r.fitError, 0.1)
        XCTAssertTrue(r.sane)
        XCTAssertLessThan(try XCTUnwrap(r.sensitivity), 1)
    }

    /// Three counts per pixel: the fit is 2.7 px off and the gate trusts it. Window sensitivity reads 3.3 px. Known
    /// defect (which statistic should gate the origin fit is not settled): when the gate refuses this fit, the expected failure turns into a pass and
    /// this test must be rewritten as a plain assertion.
    func testTheGateDoesNotTrustABiasedFitAtVeryLowDose() async throws {
        let r = try await run(peak: 3, background: 0.5)
        XCTAssertGreaterThan(r.fitError, 1, "fixture: the very-low-dose fit is meant to be biased")
        XCTAssertGreaterThan(try XCTUnwrap(r.sensitivity), 1, "the window sensitivity sees the bias")
        XCTExpectFailure("originFitIsSane judges scatter against an inflated radius, not bias") {
            XCTAssertFalse(r.sane, "the gate trusts a fit \(r.fitError) px off")
        }
    }
}

/// The public Al-Mg-Si demo through the app's own origin, CoM and rotation path. Needs the file: run with
/// `TEST_RUNNER_MAC4DSTEM_DEMO_H5=<path to AlMgSi_demo.h5>`; skipped without it (CI has no data).
final class AlMgSiDemoCalibrationTests: XCTestCase {

    func testDemoOriginCoMAndRotationThroughTheAppPath() async throws {
        guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_DEMO_H5"] else {
            throw XCTSkip("MAC4DSTEM_DEMO_H5 not set")
        }
        let reader = try await AppState.makeReader(for: URL(fileURLWithPath: path))
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        let fit = try await XCTUnwrapAsync(await OriginCalibration.tiledRun(data: data, descriptor: d))
        let o = fit.origin
        let n = o.fittedX.count
        let fx = o.fittedX.map(Double.init), fy = o.fittedY.map(Double.init)
        let maxDev = zip(fx, fy).map { hypot($0 - 63.5, $1 - 63.5) }.max() ?? .nan
        print("DEMO window r \(fit.probeRadius) mean r \(fit.meanProbeRadius ?? -1) rms residual \(o.rmsResidual ?? -1) "
              + "excluded \(o.excludedFraction ?? -1) window sensitivity \(fit.windowSensitivityPixels ?? -1) "
              + "fitted mean (\(fx.reduce(0, +) / Double(n)), \(fy.reduce(0, +) / Double(n))) max from truth \(maxDev) "
              + "corners \([0, d.rx - 1, (d.ry - 1) * d.rx, n - 1].map { (fx[$0], fy[$0]) })")
        let com = try await VirtualDetector.tiledCenterOfMass(
            data: data, descriptor: d, center: (63.5, 63.5), origins: o.interleavedFitted)
        let rotation = try XCTUnwrap(RotationCalibration.solve(com: com, width: d.rx, height: d.ry))
        print("DEMO rotation shown \(RQRotationConvention.displayDegrees(fromApp: rotation.rotationRad)) transpose "
              + "\(rotation.transpose) carries \(rotation.carriesRotation) depth \(rotation.depth)")
        XCTAssertEqual(Double(try XCTUnwrap(fit.meanProbeRadius)), 2.984912471263921, accuracy: 1e-5)
        XCTAssertLessThan(maxDev, 0.05, "the demo is centred at 63.5 px")
        XCTAssertFalse(rotation.carriesRotation, "the demo plants no rotation")
    }
}

func XCTUnwrapAsync<T>(_ value: T?) async throws -> T { try XCTUnwrap(value) }

/// 24 x 24 scan, 64 x 64 detector. Centre (x = column, y = row) on a plane; a disk of radius 4 px with a 1 px linear
/// edge; Poisson counts with mean `peak` inside the disk plus `background` everywhere. Deterministic: xorshift64*
/// uniforms and Knuth's Poisson sampler (below 30) or a rounded normal (above), the same as the reference script.
actor NoisyBeamSource: FourDDataSource {
    static let scan = 24, q = 64
    nonisolated static func truth(row: Int, column: Int) -> (x: Double, y: Double) {
        (31.7 + 0.04 * Double(column) - 0.02 * Double(row), 32.2 - 0.03 * Double(column) + 0.05 * Double(row))
    }
    let descriptor = DatasetDescriptor(filePath: "/tmp/noisy-beam.h5", datasetPath: "/data",
                                       shape: [scan, scan, q, q], dtypeDescription: "float32", chunkShape: nil)
    private let cube: [Float]

    init(peak: Double, background: Double, seed: UInt64) {
        var state = seed &+ 0x9E3779B97F4A7C15
        func uniform() -> Double {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return Double((state &* 2685821657736338717) >> 11) / 9007199254740992.0
        }
        func poisson(_ lambda: Double) -> Float {
            if lambda <= 0 { return 0 }
            if lambda < 30 {
                let l = exp(-lambda)
                var k = 0.0, p = 1.0
                repeat { k += 1; p *= uniform() } while p > l
                return Float(k - 1)
            }
            let u1 = max(uniform(), 1e-300), u2 = uniform()
            let z = (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
            return Float(max(0, (lambda + z * lambda.squareRoot()).rounded()))
        }
        let s = Self.scan, q = Self.q
        var all = [Float](repeating: 0, count: s * s * q * q)
        var k = 0
        for r in 0..<s { for c in 0..<s {
            let t = Self.truth(row: r, column: c)
            for y in 0..<q { for x in 0..<q {
                let dist = hypot(Double(x) - t.x, Double(y) - t.y)
                let edge = min(1, max(0, 4.5 - dist))   // 1 inside 3.5 px, 0 beyond 4.5 px
                all[k] = poisson(peak * edge + background)
                k += 1
            } }
        } }
        cube = all
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        view.scanTile(fromFullCube: cube, yRange: yRange)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}
