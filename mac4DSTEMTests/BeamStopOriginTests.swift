import XCTest
import CuboVirtual
import DSTEMCore
@testable import mac4DSTEM

/// The beam centre under a beam stop. `BeamStopSource` plants a stop (a disk of radius 7.5 px with an arm to the right
/// edge) over a beam whose centre walks a descan plane, with a diffuse halo and three Friedel pairs of Bragg disks
/// centred on the beam, Poisson counts. `beam_stop_origin_reference.py` draws the same cube and runs py4DSTEM's
/// `get_beamstop_mask` and `get_origin_friedel` on it.
final class BeamStopOriginTests: XCTestCase {

    private static func run(_ source: some FourDDataSource, method: OriginMethod = .centreOfMass) async throws
        -> (probeRadius: Float, meanProbeRadius: Float?, origin: OriginMaps, maxDP: [Float], meanDP: [Float],
            windowSensitivityPixels: Float?) {
        let d = try await source.discoverPrimaryDataset()
        return try await XCTUnwrapAsync(await OriginCalibration.tiledRun(
            data: FourDArray(reader: source, descriptor: d), descriptor: d, originMethod: method))
    }

    private static func calibration(_ fit: (probeRadius: Float, meanProbeRadius: Float?, origin: OriginMaps,
                                            maxDP: [Float], meanDP: [Float], windowSensitivityPixels: Float?))
        -> DSTEMCore.Calibration {
        var calibration = DSTEMCore.Calibration()
        calibration.origin = fit.origin
        calibration.probeRadius = fit.meanProbeRadius
        return calibration
    }

    /// Largest distance of a fitted origin map from the planted plane.
    private static func fitError(_ origin: OriginMaps) -> Double {
        var worst = 0.0
        for r in 0..<BeamStopSource.scan { for c in 0..<BeamStopSource.scan {
            let i = r * BeamStopSource.scan + c
            let t = BeamStopSource.truth(row: r, column: c)
            worst = max(worst, hypot(Double(origin.fittedX[i]) - t.x, Double(origin.fittedY[i]) - t.y))
        } }
        return worst
    }

    // MARK: - Detection

    /// The planted stop: the mean pattern is dark at its centre of mass and bright all round but the arm.
    func testTheMeanPatternShowsThePlantedStop() async throws {
        let source = BeamStopSource()
        let d = try await source.discoverPrimaryDataset()
        let stats = try await VirtualDetector.tiledDPStatistics(data: FourDArray(reader: source, descriptor: d), descriptor: d)
        let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: stats.meanDP, qy: d.qy, qx: d.qx))
        print("BEAMSTOP planted: centre (\(stop.centreX), \(stop.centreY)) contrast \(stop.centreContrast) "
              + "dark radius \(stop.darkRadius) coverage \(stop.coverage)")
        XCTAssertTrue(stop.detected)
        XCTAssertLessThan(stop.centreContrast, 0.05)
        XCTAssertGreaterThanOrEqual(stop.darkRadius, 6)
        XCTAssertGreaterThanOrEqual(stop.coverage, 0.75)
    }

    /// No stop: a direct beam is the brightest thing at its own centre (the noisy-origin cubes, clean and at one count
    /// per pixel, the demo cube with its Bragg spots).
    func testADirectBeamIsNotAStop() async throws {
        var sources: [(String, any FourDDataSource)] = [
            ("noisy 2000", NoisyBeamSource(peak: 2000, background: 0, seed: 7)),
            ("noisy 1", NoisyBeamSource(peak: 1, background: 0.2, seed: 7)),
            ("demo", DemoFourDDataSource(includesCalibration: false)),
        ]
        sources.append(("no stop", BeamStopSource(stop: false)))
        for (name, source) in sources {
            let d = try await source.discoverPrimaryDataset()
            let stats = try await VirtualDetector.tiledDPStatistics(
                data: FourDArray(reader: source, descriptor: d), descriptor: d)
            let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: stats.meanDP, qy: d.qy, qx: d.qx), name)
            print("BEAMSTOP \(name): contrast \(stop.centreContrast) dark radius \(stop.darkRadius) coverage \(stop.coverage)")
            XCTAssertFalse(stop.detected, name)
        }
    }

    /// A saturated core flagged NaN is a beam, not a stop: the pixels are filled from their neighbours before the rings
    /// are read. Break it by dropping the fill in `beamStop`; the NaN disk then reads as a dark centre in a bright rim.
    func testANonFiniteCoreIsNotAStop() throws {
        let q = 64
        var pattern = [Float](repeating: 1, count: q * q)
        for y in 0..<q { for x in 0..<q {
            let r = hypot(Double(x) - 32, Double(y) - 32)
            if r <= 6 { pattern[y * q + x] = 1000 }
            if r <= 1 { pattern[y * q + x] = .nan }   // one pass of the fill reaches 1 px in; a wider NaN core is not covered
        } }
        let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: pattern, qy: q, qx: q))
        XCTAssertFalse(stop.detected, "contrast \(stop.centreContrast) dark radius \(stop.darkRadius)")
    }

    /// A NaN core wider than 1 px is still a beam: the fill grows in from the core's edge, so the missing pixels take the
    /// beam's value. Before, the one-pass fill set every pixel with no finite neighbour to 0, and this core (radius 4 px
    /// in a 6 px beam) read as a dark centre 3 px in radius inside a bright rim: a stop.
    func testAWideNonFiniteCoreIsNotAStop() throws {
        let q = 64
        var pattern = [Float](repeating: 1, count: q * q)
        for y in 0..<q { for x in 0..<q {
            let r = hypot(Double(x) - 32, Double(y) - 32)
            if r <= 6 { pattern[y * q + x] = 1000 }
            if r <= 4 { pattern[y * q + x] = .nan }
        } }
        let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: pattern, qy: q, qx: q))
        XCTAssertFalse(stop.detected, "contrast \(stop.centreContrast) dark radius \(stop.darkRadius)")
        XCTAssertGreaterThan(stop.centreContrast, 0.9)
    }

    /// The fill itself: a missing disk takes its border's value at any width; an image with nothing finite becomes 0.
    func testTheFillGrowsInFromTheEdge() {
        let q = 32
        var v = [Float](repeating: 7, count: q * q)
        for y in 0..<q { for x in 0..<q where hypot(Double(x) - 16, Double(y) - 16) <= 9 { v[y * q + x] = .infinity } }
        OriginCalibration.fillNonFiniteFromOutside(&v, rows: q, columns: q)
        XCTAssertEqual(v, [Float](repeating: 7, count: q * q))
        var none = [Float](repeating: .nan, count: 9)
        OriginCalibration.fillNonFiniteFromOutside(&none, rows: 3, columns: 3)
        XCTAssertEqual(none, [Float](repeating: 0, count: 9))
    }

    /// Two bright regions with a dark middle are not a stop: the ring does not close round the centre.
    func testTwoSeparateBlobsAreNotAStop() throws {
        let q = 64
        var pattern = [Float](repeating: 0, count: q * q)
        for y in 0..<q { for x in 0..<q {
            for cx in [16.0, 48.0] where hypot(Double(x) - cx, Double(y) - 32) <= 5 { pattern[y * q + x] = 100 }
        } }
        let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: pattern, qy: q, qx: q))
        XCTAssertLessThan(stop.centreContrast, 0.25, "fixture: the middle is dark")
        XCTAssertLessThan(stop.coverage, 0.6)
        XCTAssertFalse(stop.detected)
    }

    // MARK: - The centre-of-mass run under a stop

    /// Under the stop the centre-of-mass origin is not the beam's: the run marks the stop and the gate refuses. Before
    /// the stop test the gate passed this fit. Break it by dropping `originBeamStopIsAcceptable` from `originFitIsSane`.
    func testTheCentreOfMassRunUnderAStopIsRefused() async throws {
        let fit = try await Self.run(BeamStopSource())
        let calibration = Self.calibration(fit)
        print("BEAMSTOP CoM: fit error \(Self.fitError(fit.origin)) rms \(fit.origin.rmsResidual ?? -1) "
              + "probe r \(fit.meanProbeRadius ?? -1) window r \(fit.probeRadius) pull \(fit.origin.windowPullBoundPixels ?? -1) "
              + "fallback rms \(fit.origin.friedelFallbackResidualPixels ?? -1)")
        XCTAssertGreaterThan(Self.fitError(fit.origin), 10, "fixture: the centre of mass under the stop is far off")
        XCTAssertTrue(calibration.originResidualIsAcceptable, "fixture: the residual test alone trusts it")
        XCTAssertTrue(calibration.originWindowPullIsAcceptable, "fixture: the window pull is blind to the stop")
        XCTAssertEqual(fit.origin.beamStopCoversBeam, true)
        XCTAssertFalse(calibration.originFitIsSane)
        let refusal = try XCTUnwrap(calibration.originFitRefusal)
        XCTAssertTrue(refusal.contains("A beam stop covers the direct beam"), refusal)
        XCTAssertFalse(refusal.contains("Try another Origin fit"), refusal)
    }

    /// The fallback: the same run tries the Friedel origin, which fits the planted cube, so the refusal offers it.
    func testTheRefusalOffersTheFriedelMethodWhenItFits() async throws {
        let fit = try await Self.run(BeamStopSource())
        let residual = try XCTUnwrap(fit.origin.friedelFallbackResidualPixels)
        XCTAssertLessThan(residual, Calibration.friedelFallbackResidualLimitPixels)
        let calibration = Self.calibration(fit)
        XCTAssertTrue(calibration.friedelFallbackIsTrusted)
        let refusal = try XCTUnwrap(calibration.originFitRefusal)
        XCTAssertTrue(refusal.contains("set Origin method to Friedel"), refusal)
    }

    /// And the method it offers lands on the beam, as py4DSTEM's does. `beam_stop_origin_reference.py` (py4DSTEM
    /// f050d207: `get_beamstop_mask` defaults, `get_origin_friedel` with its negation, `fit_origin` plane), 2026-10-31:
    /// fitted at most 0.0854 px from the planted plane, RMS residual 0.0265 px, and the measured origins (x = column,
    /// y = row) below. The app's run is CuboKit's float64 port on the same float32 cube.
    func testTheFriedelRunFindsThePlantedCentreAsPy4DSTEMDoes() async throws {
        let fit = try await Self.run(BeamStopSource(), method: .friedel)
        let error = Self.fitError(fit.origin)
        print("BEAMSTOP Friedel: fit error \(error) rms \(fit.origin.rmsResidual ?? -1)")
        XCTAssertEqual(error, 0.0854, accuracy: 1e-3)
        XCTAssertEqual(Double(try XCTUnwrap(fit.origin.rmsResidual)), 0.0265, accuracy: 1e-3)
        let measuredX = try XCTUnwrap(fit.origin.measuredX), measuredY = try XCTUnwrap(fit.origin.measuredY)
        let py4DSTEM: [(Int, Double, Double)] = [(0, 31.5940, 32.3421), (5, 31.9168, 32.1099),
                                                 (77, 31.7082, 32.5630), (143, 31.9411, 32.6847)]
        for (i, x, y) in py4DSTEM {
            print("BEAMSTOP Friedel position \(i): (\(measuredX[i]), \(measuredY[i]))")
            XCTAssertEqual(Double(measuredX[i]), x, accuracy: 1e-3, "position \(i)")
            XCTAssertEqual(Double(measuredY[i]), y, accuracy: 1e-3, "position \(i)")
        }
        XCTAssertNil(fit.origin.beamStopCoversBeam, "a Friedel run does not judge itself by the stop")
        XCTAssertEqual(fit.origin.measuredByFriedel, true)
        XCTAssertTrue(Self.calibration(fit).originFriedelResidualIsAcceptable, "0.0265 px is inside the 1 px limit")
        XCTAssertTrue(Self.calibration(fit).originFitIsSane)
    }

    // MARK: - A Friedel run picked by hand

    /// A 3 x 3 map whose measured origins scatter 1.5 px about a flat fit, with a 4 px probe radius: the residual test
    /// alone passes it.
    private static func scattered(friedel: Bool?) -> DSTEMCore.Calibration {
        var calibration = DSTEMCore.Calibration()
        let fitted = [Float](repeating: 20, count: 9)
        let measured: [Float] = [21.5, 18.5, 21.5, 18.5, 21.5, 18.5, 21.5, 18.5, 21.5]
        calibration.origin = OriginMaps(width: 3, height: 3, measuredX: measured, measuredY: fitted,
                                        fittedX: fitted, fittedY: fitted, measuredByFriedel: friedel)
        calibration.probeRadius = 4
        return calibration
    }

    /// The Friedel method chosen by hand faces the same 1 px limit the fallback is offered under, not only the probe
    /// radius. Before, this 1.5 px fit was trusted. Break it by dropping `originFriedelResidualIsAcceptable` from
    /// `originFitIsSane`.
    func testAFriedelRunIsHeldToTheOnePixelLimit() throws {
        let friedel = Self.scattered(friedel: true)
        XCTAssertEqual(Double(try XCTUnwrap(friedel.origin?.rmsResidual)), 1.5, accuracy: 1e-5)
        XCTAssertTrue(friedel.originResidualIsAcceptable, "fixture: inside the probe radius")
        XCTAssertFalse(friedel.originFriedelResidualIsAcceptable)
        XCTAssertFalse(friedel.originFitIsSane)
        let refusal = try XCTUnwrap(friedel.originFitRefusal)
        XCTAssertTrue(refusal.contains("allowed for the Friedel method"), refusal)
        XCTAssertTrue(refusal.contains("Centre of mass"), refusal)
        XCTAssertTrue(refusal.contains("reciprocal pixel size manually"), refusal)
        let report = CalibrationReadinessReport.make(calibration: friedel, provenance: CalibrationProvenance())
        let origin = try XCTUnwrap(report.items.first { $0.kind == .originProbe })
        XCTAssertTrue(origin.detail.contains("Friedel fit over the 1\u{00A0}px limit"), origin.detail)
        // The same scatter from the centre of mass, or from an unknown method, is judged by the probe radius as before.
        for method in [false, nil] as [Bool?] {
            XCTAssertTrue(Self.scattered(friedel: method).originFitIsSane, "\(String(describing: method))")
        }
    }

    /// iDPC: the Friedel refusal points to the centre of mass or a manual origin, never to a manual Q.
    @MainActor
    func testTheIDPCRefusalOfAFriedelRun() throws {
        let state = AppState()
        state.calibrationSession.calibration = Self.scattered(friedel: true)
        let text = try XCTUnwrap(state.idpcOriginFitRefusal)
        XCTAssertTrue(text.contains("Centre of mass"), text)
        XCTAssertFalse(text.contains("Try another Origin fit"), text)
        XCTAssertFalse(text.contains("reciprocal pixel size"), text)
    }

    // MARK: - Progress during the fallback

    private nonisolated final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        nonisolated func add(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
        nonisolated var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// The fallback reports its own progress (it is a second pass over the cube, an FFT per pattern), and the run gives
    /// it the 0.6 to 0.9 stretch of the bar: before, the bar stood at 0.9 for the whole fallback.
    func testTheProgressBarMovesDuringTheFallback() async throws {
        let source = BeamStopSource()
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        let stats = try await VirtualDetector.tiledDPStatistics(data: data, descriptor: d)
        let fallback = ProgressLog()
        _ = try await OriginCalibration.friedelFallbackResidual(
            data: data, descriptor: d, meanDP: stats.meanDP, fitFunction: .plane, maximumTileRows: 3,
            cancellation: nil, progress: { fallback.add($0) })
        XCTAssertGreaterThanOrEqual(fallback.values.filter { $0 > 0 && $0 < 1 }.count, 2, "\(fallback.values)")
        XCTAssertEqual(fallback.values.last, 1)

        let run = ProgressLog()
        _ = try await OriginCalibration.tiledRun(data: data, descriptor: d, maximumTileRows: 3,
                                                 progress: { run.add($0) })
        let values = run.values
        XCTAssertEqual(values, values.sorted(), "the bar never steps back")
        XCTAssertEqual(values.last, 1)
        XCTAssertLessThanOrEqual(values.filter { $0 >= 0.9 }.count, 2, "no long stand at 0.9: \(values)")
        // The same cube without its stop runs no fallback: the stop run reports the fallback's ticks on top. Before, it
        // reported exactly as many as the run without a stop (the fallback ran with no progress).
        let clearSource = BeamStopSource(stop: false)
        let clear = ProgressLog()
        _ = try await OriginCalibration.tiledRun(data: FourDArray(reader: clearSource, descriptor: d), descriptor: d,
                                                 maximumTileRows: 3, progress: { clear.add($0) })
        XCTAssertGreaterThanOrEqual(values.count - clear.values.count, 2, "stop \(values) clear \(clear.values)")
    }

    /// A clean beam pays nothing: no stop, no fallback, the gate as before.
    func testNoStopNoFallback() async throws {
        let fit = try await Self.run(NoisyBeamSource(peak: 2000, background: 0, seed: 7))
        XCTAssertEqual(fit.origin.beamStopCoversBeam, false)
        XCTAssertNil(fit.origin.friedelFallbackResidualPixels)
        XCTAssertEqual(fit.origin.measuredByFriedel, false)
        XCTAssertTrue(Self.calibration(fit).originFitIsSane)
    }

    // MARK: - The refusal's words

    private static func refusedByAStop(fallback: Float?) -> DSTEMCore.Calibration {
        var calibration = DSTEMCore.Calibration()
        calibration.origin = OriginMaps(width: 1, height: 1, measuredX: [10], measuredY: [10], fittedX: [10], fittedY: [10],
                                        beamStopCoversBeam: true, friedelFallbackResidualPixels: fallback)
        calibration.probeRadius = 4
        return calibration
    }

    /// A fallback that does not fit (9.6 px RMS) is not offered: the refusal says a stop covers the beam and points to
    /// a manual origin or a manual Q.
    func testAnUntrustedFallbackIsNotOffered() throws {
        for fallback in [Float(9.6), nil] {
            let calibration = Self.refusedByAStop(fallback: fallback)
            XCTAssertTrue(calibration.originResidualIsAcceptable)
            XCTAssertFalse(calibration.originFitIsSane)
            XCTAssertFalse(calibration.friedelFallbackIsTrusted)
            let refusal = try XCTUnwrap(calibration.originFitRefusal)
            XCTAssertTrue(refusal.contains("A beam stop covers the direct beam"), refusal)
            XCTAssertTrue(refusal.contains("manual origin"), refusal)
            XCTAssertTrue(refusal.contains("reciprocal pixel size manually"), refusal)
            XCTAssertFalse(refusal.contains("set Origin method to Friedel"), refusal)
            let report = CalibrationReadinessReport.make(calibration: calibration, provenance: CalibrationProvenance())
            let origin = try XCTUnwrap(report.items.first { $0.kind == .originProbe })
            XCTAssertTrue(origin.detail.contains("Beam\u{00A0}stop"), origin.detail)
        }
    }

    /// iDPC: never "Try another Origin fit" under a stop, and no manual Q (a scale cannot bring the origin back).
    @MainActor
    func testTheIDPCRefusalUnderAStop() throws {
        let state = AppState()
        state.calibrationSession.calibration = Self.refusedByAStop(fallback: 9.6)
        let text = try XCTUnwrap(state.idpcOriginFitRefusal)
        XCTAssertFalse(text.contains("Try another Origin fit"), text)
        XCTAssertTrue(text.contains("manual origin"), text)
        XCTAssertFalse(text.contains("reciprocal pixel size"), text)
    }

    /// A crop or a bin keeps the stop's verdict; the fallback's residual is a length, divided by the bin.
    func testReReferenceCarriesTheStop() throws {
        var c = DSTEMCore.Calibration()
        c.origin = OriginMaps(width: 2, height: 2, measuredX: [16, 16, 16, 16], measuredY: [16, 16, 16, 16],
                              fittedX: [16, 16, 16, 16], fittedY: [16, 16, 16, 16],
                              beamStopCoversBeam: true, friedelFallbackResidualPixels: 0.8, measuredByFriedel: false)
        c.originProvenance = .fitted
        c.probeRadius = 4
        let source = DatasetDescriptor(filePath: "/tmp/x.h5", datasetPath: "/d", shape: [2, 2, 32, 32],
                                       dtypeDescription: "float32", chunkShape: nil)
        let view = try LoadView(source: source, specification: LoadSpecification(detectorBin: 2))
        let outcome = CalibrationReReference.apply(view, to: c, provenance: CalibrationProvenance(), apertureCenter: nil)
        XCTAssertEqual(outcome.calibration.origin?.beamStopCoversBeam, true)
        XCTAssertEqual(try XCTUnwrap(outcome.calibration.origin?.friedelFallbackResidualPixels), 0.4, accuracy: 1e-6)
        XCTAssertEqual(outcome.calibration.origin?.measuredByFriedel, false)
        XCTAssertFalse(outcome.calibration.originFitIsSane)
    }
}

/// A recorded cube with a beam stop through the app's origin path: prints the stop the mean pattern shows and what the
/// centre-of-mass run and its Friedel fallback make of it. Needs a file: run with
/// `TEST_RUNNER_MAC4DSTEM_BEAMSTOP_H5=<path>`; skipped without it (CI has no data). Asserts only that the gate does
/// not trust a centre-of-mass origin under the stop.
final class BeamStopRecordedCubeTests: XCTestCase {
    func testARecordedStopIsFoundAndTheCentreOfMassOriginRefused() async throws {
        guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_BEAMSTOP_H5"] else {
            throw XCTSkip("MAC4DSTEM_BEAMSTOP_H5 not set")
        }
        let reader = try await AppState.makeReader(for: URL(fileURLWithPath: path))
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        let fit = try await XCTUnwrapAsync(await OriginCalibration.tiledRun(data: data, descriptor: d))
        let stop = try XCTUnwrap(OriginCalibration.beamStop(meanDP: fit.meanDP, qy: d.qy, qx: d.qx))
        var calibration = DSTEMCore.Calibration()
        calibration.origin = fit.origin
        calibration.probeRadius = fit.meanProbeRadius
        print("RECORDED stop: centre (\(stop.centreX), \(stop.centreY)) contrast \(stop.centreContrast) "
              + "dark radius \(stop.darkRadius) coverage \(stop.coverage) detected \(stop.detected)")
        print("RECORDED CoM: rms \(fit.origin.rmsResidual ?? -1) probe r \(fit.meanProbeRadius ?? -1) "
              + "pull \(fit.origin.windowPullBoundPixels ?? -1) fallback rms \(fit.origin.friedelFallbackResidualPixels ?? -1) "
              + "residual ok \(calibration.originResidualIsAcceptable) sane \(calibration.originFitIsSane)")
        print("RECORDED refusal: \(calibration.originFitRefusal ?? "none")")
        // What the residual test would make of a Friedel-method run: the same measurement and fit as the fallback.
        if let fallback = fit.origin.friedelFallbackResidualPixels, let r = fit.meanProbeRadius {
            print("RECORDED Friedel method: rms \(fallback) against probe r \(r): residual test passes \(fallback <= r)")
        }
        XCTAssertTrue(stop.detected)
        XCTAssertFalse(calibration.originFitIsSane)
    }
}

/// 12 x 12 scan, 64 x 64 detector. The beam centre (x = column, y = row) walks a plane; the expected counts are a
/// background of 1, a beam disk of radius 4 px with a 1 px linear edge (3000 counts), a diffuse halo
/// 120 / (1 + (d / 5)^2) about the beam, and three Friedel pairs of disks of radius 2 px with a 1 px edge (400 counts)
/// at (±14, ±5), (∓4, ±15), (±11, ∓9) px from the beam. The stop, fixed on the detector, zeroes a disk of radius
/// 7.5 px about (32, 32) and an arm 5 px wide (rows 30 to 34) from column 32 to the right edge; it covers the beam at
/// every position (the beam's edge is at most 5.7 px from the stop's centre). Poisson counts by the generator of
/// `NoisyBeamSource`, seed 11, drawn in row-major order over scan and detector, the same as the reference script.
actor BeamStopSource: FourDDataSource {
    static let scan = 12, q = 64
    nonisolated static func truth(row: Int, column: Int) -> (x: Double, y: Double) {
        (31.6 + 0.06 * Double(column) - 0.03 * Double(row), 32.4 - 0.04 * Double(column) + 0.07 * Double(row))
    }
    nonisolated static let braggOffsets: [(Double, Double)] = [(14, 5), (-4, 15), (11, -9)]
    let descriptor = DatasetDescriptor(filePath: "/tmp/beam-stop.h5", datasetPath: "/data",
                                       shape: [scan, scan, q, q], dtypeDescription: "float32", chunkShape: nil)
    private let cube: [Float]

    nonisolated static func blocked(x: Int, y: Int) -> Bool {
        hypot(Double(x) - 32, Double(y) - 32) <= 7.5 || (abs(y - 32) <= 2 && x >= 32)
    }

    init(stop: Bool = true, seed: UInt64 = 11) {
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
                if stop && Self.blocked(x: x, y: y) { all[k] = 0; k += 1; continue }
                let dx = Double(x) - t.x, dy = Double(y) - t.y
                let dist = hypot(dx, dy)
                var lambda = 1 + 3000 * min(1, max(0, 4.5 - dist)) + 120 / (1 + (dist / 5) * (dist / 5))
                for (u, v) in Self.braggOffsets {
                    lambda += 400 * min(1, max(0, 3 - hypot(dx - u, dy - v)))
                    lambda += 400 * min(1, max(0, 3 - hypot(dx + u, dy + v)))
                }
                all[k] = poisson(lambda)
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
