import XCTest
import CuboVirtual
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
/// The residual test alone (full-scan RMS residual at most the probe radius) trusts every row, including the two that
/// are 2.7 and 3.2 px off: the residual measures scatter about the fit, not the fit's bias, and the radius it is
/// compared with grows with the noise (8.3 px for a 4 px probe). Since 2026-10-31 the gate also reads the window pull
/// (`OriginCalibration.windowPull`): how far background inside the origin window can have pulled the refine. Measured
/// with the 4-pass refine, window from the max-pattern radius:
///
/// | peak, background | max-pattern r | beam share of window | pull bound | fit error | verdict |
/// |---|---|---|---|---|---|
/// | 2000, 0   | 4.74  | 1.000 | 0.000 px | 0.015 px | trusted |
/// | 50, 0.5   | 5.43  | 0.971 | 0.000 px | 0.018 px | trusted |
/// | 10, 0.5   | 9.39  | 0.717 | 0.072 px | 0.042 px | trusted |
/// | 5, 0.5    | 12.65 | 0.410 | 1.84 px  | 0.285 px | refused |
/// | 3, 0.5    | 15.12 | 0.226 | 6.5 px   | 2.69 px  | refused |
/// | 1, 0.2    | 14.82 | 0.201 | 7.2 px   | 3.19 px  | refused |
///
/// Window sensitivity tracks the bias here too, but not elsewhere: it reads 0.54 px on the in-app demo cube (Bragg
/// spots inside the wide window, fit 0.003 px off), where the pull bound reads below 0.001 px.
final class NoisyOriginTests: XCTestCase {

    private struct Run {
        let fitError: Double
        let sane: Bool
        let sensitivity: Float?
        let pull: Float?
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
        return Run(fitError: fitError, sane: calibration.originFitIsSane, sensitivity: fit.windowSensitivityPixels,
                   pull: fit.origin.windowPullBoundPixels)
    }

    /// Clean and moderate dose: the fitted origin is within 0.03 px of the planted plane (py4DSTEM 0.015 and 0.021).
    func testCleanAndModerateDoseFitTheBeamCentre() async throws {
        for (peak, background) in [(2000.0, 0.0), (50.0, 0.5)] {
            let r = try await run(peak: peak, background: background)
            XCTAssertLessThan(r.fitError, 0.03, "peak \(peak)")
            XCTAssertTrue(r.sane)
            XCTAssertLessThan(try XCTUnwrap(r.pull), 0.01, "peak \(peak)")
        }
    }

    /// Ten counts per pixel in the disk: the app's iterated window stays within 0.1 px (0.042) where py4DSTEM's single
    /// masked centre of mass is 0.48 px off. Window sensitivity reads 0.72 px, the pull bound 0.072 px: trusted.
    func testLowDoseFitStaysWithinATenthOfAPixel() async throws {
        let r = try await run(peak: 10, background: 0.5)
        XCTAssertLessThan(r.fitError, 0.1)
        XCTAssertTrue(r.sane)
        XCTAssertLessThan(try XCTUnwrap(r.sensitivity), 1)
        XCTAssertLessThan(try XCTUnwrap(r.pull), 0.2)
    }

    /// Three and one counts per pixel: the fits are 2.7 and 3.2 px off, the residual test passes them, and the window
    /// pull (6.5 and 7.2 px against a 1 px limit) refuses them. Before 2026-10-31 the gate trusted both (an expected
    /// failure pinned it). Break it by dropping `originWindowPullIsAcceptable` from `originFitIsSane`.
    func testTheGateDoesNotTrustABiasedFitAtVeryLowDose() async throws {
        for (peak, background) in [(3.0, 0.5), (1.0, 0.2)] {
            let r = try await run(peak: peak, background: background)
            XCTAssertGreaterThan(r.fitError, 1, "fixture: the very-low-dose fit is meant to be biased (peak \(peak))")
            XCTAssertGreaterThan(try XCTUnwrap(r.pull), 3, "the pull bound sees the bias (peak \(peak))")
            XCTAssertFalse(r.sane, "the gate trusts a fit \(r.fitError) px off (peak \(peak))")
        }
    }

    /// Five counts per pixel: the fit is good to 0.3 px but the bound (1.85 px) cannot show it, so the gate refuses.
    /// Pinned so the conservative side of the 1 px limit is a decision on record, not a surprise.
    func testTheGateRefusesWhatItCannotVouchFor() async throws {
        let r = try await run(peak: 5, background: 0.5)
        XCTAssertLessThan(r.fitError, 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(r.pull), 1)
        XCTAssertFalse(r.sane)
    }

    /// The in-app demo cube: Bragg spots at 17 and 24.5 px around a 4.5 px disk. The wide window of the sensitivity
    /// reaches the spots (0.54 px), the shipped window does not, and the fit is 0.003 px off: a sensitivity threshold
    /// would refuse good data, the pull bound (below 0.001 px) does not.
    func testTheDemoCubeIsTrusted() async throws {
        let source = DemoFourDDataSource(includesCalibration: false)
        let d = try await source.discoverPrimaryDataset()
        let fit = try await XCTUnwrapAsync(await OriginCalibration.tiledRun(
            data: FourDArray(reader: source, descriptor: d), descriptor: d))
        var calibration = DSTEMCore.Calibration()
        calibration.origin = fit.origin
        calibration.probeRadius = fit.meanProbeRadius
        XCTAssertLessThan(try XCTUnwrap(fit.origin.windowPullBoundPixels), 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(fit.windowSensitivityPixels), 0.3, "fixture: the wide window sees the spots")
        XCTAssertTrue(calibration.originFitIsSane)
        XCTAssertNil(calibration.originFitRefusal)
    }

    /// The refusal names the window and its number, not the residual and the probe radius.
    func testTheRefusalQuotesThePull() throws {
        let calibration = Self.refusedByThePull
        XCTAssertTrue(calibration.originResidualIsAcceptable)
        XCTAssertFalse(calibration.originFitIsSane)
        let refusal = try XCTUnwrap(calibration.originFitRefusal)
        XCTAssertTrue(refusal.contains("origin window"), refusal)
        XCTAssertTrue(refusal.contains("more than the 1 px allowed"), refusal)
        XCTAssertFalse(refusal.contains("probe radius"), refusal)
        let report = CalibrationReadinessReport.make(calibration: calibration, provenance: CalibrationProvenance())
        let origin = try XCTUnwrap(report.items.first { $0.kind == .originProbe })
        XCTAssertTrue(origin.detail.contains("Window\u{00A0}pull"), origin.detail)
        XCTAssertFalse(origin.detail.contains("exceeds probe radius"), origin.detail)
    }

    /// The 3-count cube's measured pull (6.49 px) on a one-position map whose residual passes.
    private static var refusedByThePull: DSTEMCore.Calibration {
        var calibration = DSTEMCore.Calibration()
        calibration.origin = OriginMaps(width: 1, height: 1, measuredX: [10], measuredY: [10], fittedX: [10], fittedY: [10],
                                        windowPullBoundPixels: 6.49)
        calibration.probeRadius = 4
        return calibration
    }

    /// iDPC appends its own remedy; for a pull refusal it must not send the user to re-fit, which gives the same origins.
    @MainActor
    func testTheIDPCRefusalDoesNotPromiseARefit() throws {
        let state = AppState()
        state.calibrationSession.calibration = Self.refusedByThePull
        let text = try XCTUnwrap(state.idpcOriginFitRefusal)
        XCTAssertFalse(text.contains("Try another Origin fit"), text)
        XCTAssertTrue(text.contains("gives the same origins"), text)
    }

    /// A detector-bin re-reference divides the pull (a length in detector pixels; the beam share is unchanged), so a
    /// refused fit is still judged after a reduced reload.
    func testReReferenceCarriesThePull() throws {
        var c = DSTEMCore.Calibration()
        c.origin = OriginMaps(width: 2, height: 2, measuredX: [16, 16, 16, 16], measuredY: [16, 16, 16, 16],
                              fittedX: [16, 16, 16, 16], fittedY: [16, 16, 16, 16], windowPullBoundPixels: 6)
        c.originProvenance = .fitted
        c.probeRadius = 4
        let source = DatasetDescriptor(filePath: "/tmp/x.h5", datasetPath: "/d", shape: [2, 2, 32, 32],
                                       dtypeDescription: "float32", chunkShape: nil)
        let view = try LoadView(source: source, specification: LoadSpecification(detectorBin: 2))
        let outcome = CalibrationReReference.apply(view, to: c, provenance: CalibrationProvenance(), apertureCenter: nil)
        XCTAssertEqual(try XCTUnwrap(outcome.calibration.origin?.windowPullBoundPixels), 3, accuracy: 1e-6)
        XCTAssertFalse(outcome.calibration.originFitIsSane)
    }

    /// Unknown passes: a map with no pull (imported, Friedel, a session saved before the value existed) is judged by
    /// the residual alone, as before.
    func testAnUnknownPullIsNotRefused() {
        var calibration = DSTEMCore.Calibration()
        calibration.origin = OriginMaps(width: 1, height: 1, measuredX: [10], measuredY: [10], fittedX: [10], fittedY: [10])
        calibration.probeRadius = 4
        XCTAssertTrue(calibration.originFitIsSane)
    }
}

/// `OriginCalibration.windowPull` on a pattern whose answer is known: a flat background of 1 and a disk of 10 extra
/// counts of radius 3 centred in a window of radius 6, off-centre (column 40, row 20) on a 48-row x 64-column detector,
/// so a row/column swap misses the disk. Window area A (pixel centres within 6 px), disk area D (within 3 px):
/// S = A + 10 D, f = 10 D / S, bound = (1 - f)^4 * 6.
final class WindowPullTests: XCTestCase {
    func testAFlatBackgroundAndADiskGiveTheBeamShare() throws {
        let rows = 48, columns = 64, c = (x: Float(40), y: Float(20))
        var pattern = [Float](repeating: 1, count: rows * columns)
        var a = 0.0, disk = 0.0
        for y in 0..<rows { for x in 0..<columns {
            let r2 = Float((x - 40) * (x - 40) + (y - 20) * (y - 20))
            if r2 <= 9 { pattern[y * columns + x] += 10; disk += 1 }
            if r2 <= 36 { a += 1 }
        } }
        let pull = try XCTUnwrap(OriginCalibration.windowPull(meanDP: pattern, qy: rows, qx: columns, centre: c,
                                                              windowRadius: 6))
        let f = 10 * disk / (a + 10 * disk)
        XCTAssertEqual(Double(pull.signalFraction), f, accuracy: 1e-6)
        XCTAssertEqual(Double(pull.boundPixels), pow(1 - f, 4) * 6, accuracy: 1e-5)
    }

    /// The bound's passes and margin are the refine's: CuboKit's `.iteratedWindow()` defaults. Break it by changing either.
    func testThePassesAndMarginAreTheRefines() {
        XCTAssertEqual(OriginEstimator.iteratedWindow(),
                       .iteratedWindow(passes: OriginCalibration.originRefinePasses,
                                       minimumMargin: Double(OriginCalibration.originRefineMargin), binnedCoarse: true))
    }

    /// No background: the beam is all of the window, nothing can pull. Negative pixels clamp to 0.
    func testNoBackgroundMeansNoPull() throws {
        var pattern = [Float](repeating: -2, count: 32 * 32)
        pattern[16 * 32 + 16] = 100
        let pull = try XCTUnwrap(OriginCalibration.windowPull(meanDP: pattern, qy: 32, qx: 32, centre: (16, 16), windowRadius: 4))
        XCTAssertEqual(pull.signalFraction, 1)
        XCTAssertEqual(pull.boundPixels, 0)
    }

    /// Nothing to measure: an empty pattern, or a window that covers the whole detector (no background to read).
    func testUnmeasurableIsNil() {
        XCTAssertNil(OriginCalibration.windowPull(meanDP: [Float](repeating: 0, count: 16), qy: 4, qx: 4, centre: (2, 2),
                                                  windowRadius: 1))
        XCTAssertNil(OriginCalibration.windowPull(meanDP: [Float](repeating: 1, count: 16), qy: 4, qx: 4, centre: (2, 2),
                                                  windowRadius: 100))
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
        // The origin gate trusts it: pull bound 0.000 px (beam share 0.979 of the window), measured 2026-10-31.
        var calibration = DSTEMCore.Calibration()
        calibration.origin = o
        calibration.probeRadius = fit.meanProbeRadius
        XCTAssertLessThan(try XCTUnwrap(o.windowPullBoundPixels), 0.01)
        XCTAssertTrue(calibration.originFitIsSane)
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
