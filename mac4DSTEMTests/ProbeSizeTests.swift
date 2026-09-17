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

    /// Gate D 2026-09-03: the trusted-band fallback is provably unreachable
    /// (see the comment at the fallback); the silent path was the `dpMax > 0`
    /// guard, which handed back 1 px at the geometric centre with nothing to
    /// tell a caller it measured nothing. Closed 2026-09-05: nothing to
    /// measure is nil, and a NaN pixel — first or anywhere — is skipped rather
    /// than poisoning `max()` into the same silent path.
    func testAnAllZeroPatternIsNotMeasurableAndANaNPixelIsSkipped() throws {
        let q = Self.q
        let zero = [Float](repeating: 0, count: q * q)
        XCTAssertNil(OriginCalibration.probeSize(dp: zero, qy: q, qx: q))
        XCTAssertNil(OriginCalibration.probeSize(dp: [Float](repeating: .nan, count: q * q), qy: q, qx: q))
        XCTAssertNil(OriginCalibration.probeSize(dp: [Float](repeating: -3, count: q * q), qy: q, qx: q),
                     "a pattern with no intensity above zero has no disk to size")
        var dp = [Float](repeating: 0, count: q * q)
        Self.drawDisk(into: &dp, cx: 32, cy: 32, radius: 8, intensity: 1)
        let clean = try XCTUnwrap(OriginCalibration.probeSize(dp: dp, qy: q, qx: q))
        XCTAssertEqual(clean.r, 8, accuracy: 0.6)
        var nanFirst = dp; nanFirst[0] = .nan
        let first = try XCTUnwrap(OriginCalibration.probeSize(dp: nanFirst, qy: q, qx: q),
                                  "a NaN in pixel 0 used to poison max() and return 1 px")
        XCTAssertEqual(first.r, clean.r, accuracy: 1e-4)
        XCTAssertEqual(first.x0, clean.x0, accuracy: 1e-4)
        var nanInside = dp; nanInside[32 * q + 30] = .nan
        let inside = try XCTUnwrap(OriginCalibration.probeSize(dp: nanInside, qy: q, qx: q))
        XCTAssertEqual(inside.r, clean.r, accuracy: 0.1,
                       "one dead pixel inside the disk is one pixel of area, not a refusal")
        // Gate B refuter 2026-09-05: +inf passed every threshold mask and made
        // the centre of mass inf/inf = NaN while the radius stayed finite.
        var hot = dp; hot[3 * q + 3] = .infinity
        let saturated = try XCTUnwrap(OriginCalibration.probeSize(dp: hot, qy: q, qx: q))
        XCTAssertTrue(saturated.x0.isFinite && saturated.y0.isFinite, "a hot pixel must not poison the centre")
        XCTAssertEqual(saturated.r, clean.r, accuracy: 1e-4, "an infinity is one dead pixel, not disk area")
        XCTAssertEqual(saturated.x0, clean.x0, accuracy: 1e-4)
        XCTAssertNil(OriginCalibration.probeSize(dp: [Float](repeating: .infinity, count: q * q), qy: q, qx: q),
                     "no FINITE intensity above zero is nothing to measure")
    }

    /// The pipeline refuses with a sentence rather than calibrating against
    /// an invented probe: both entry points, the tiled one the app calls and
    /// the resident-cube one it keeps for a future caller.
    func testACubeWithNoIntensityRefusesOriginCalibration() async throws {
        let source = ZeroFourDDataSource()
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        do {
            _ = try await OriginCalibration.tiledRun(data: data, descriptor: d)
            XCTFail("tiledRun calibrated against a pattern with no intensity")
        } catch let error as OriginCalibrationError {
            XCTAssertEqual(error, .probeNotMeasurable)
            XCTAssertTrue(error.errorDescription?.contains("no probe radius") == true)
        }
        let cube = await source.fullCube()
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(
            bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        XCTAssertThrowsError(try OriginCalibration.run(cube: buffer, descriptor: d)) { error in
            XCTAssertEqual(error as? OriginCalibrationError, .probeNotMeasurable)
        }
    }

    /// py4DSTEM's `get_probe_size` takes `np.median(dr_dtheta)` with `N = 100`
    /// (`process/calibration/probe.py:54`), and numpy's median for an EVEN
    /// count is the mean of the two middle values. The port took
    /// `sorted[n/2]` — the upper middle value alone — until 2026-09-05.
    /// Because `sorted[n/2] >= (sorted[n/2-1] + sorted[n/2]) / 2` always, the
    /// old rule's `2 * median` band was never wider than the correct one, so
    /// it systematically truncated the trusted threshold set; the mean radius
    /// over that set can then move in either direction.
    ///
    /// Nothing pinned this rule below the `all` gate until 2026-09-09, and
    /// `all` reaches `tools/real-data-acceptance/` alone: the corrected radius
    /// sat unnoticed against a stale golden for three days
    /// (`docs/archive/closed-items-2026-09.md`). This is that pin.
    ///
    /// The pattern is a flat core of radius 6 with a Gaussian shoulder
    /// (sigma 2) — a step-edged disk gives an all-zero `dr` on which BOTH
    /// rules agree, so a soft edge is the point, not decoration. Both
    /// expected values come from an independent numpy transcription of
    /// py4DSTEM's algorithm, retained before this test was written, NOT from
    /// this implementation: np.median -> 8.2733669 over 77 thresholds,
    /// sorted[n/2] -> 8.4174433 over 67.
    func testProbeSizeUsesNumpysEvenCountMedianForTheTrustedBand() throws {
        let q = 64
        var dp = [Float](repeating: 0, count: q * q)
        for y in 0..<q {
            for x in 0..<q {
                let dx = Double(x) - 31.5, dy = Double(y) - 31.5
                let rr = (dx * dx + dy * dy).squareRoot()
                let v = rr <= 6 ? 1 : exp(-((rr - 6) * (rr - 6)) / 8)
                dp[y * q + x] = Float(v * 1000)
            }
        }
        let r = try XCTUnwrap(
            OriginCalibration.probeSize(dp: dp, qy: q, qx: q)
        ).r
        XCTAssertEqual(
            r, 8.2733669, accuracy: 0.01,
            "probeSize must match np.median's even-count rule, got \(r)"
        )
        // The discriminator, stated separately so a failure names the cause:
        // reverting to `sorted[n/2]` lands on 8.4174433, 0.144 px away.
        XCTAssertGreaterThan(
            abs(r - 8.4174433), 0.1,
            "probeSize took the upper middle value alone (the pre-2026-09-05 "
                + "rule), got \(r)"
        )
    }

    func testProbeSizeRecoversACleanDiskRadius() throws {
        var dp = [Float](repeating: 0, count: Self.q * Self.q)
        Self.drawDisk(into: &dp, cx: 31.5, cy: 31.5, radius: 6, intensity: 100)
        let (r, x0, y0) = try XCTUnwrap(OriginCalibration.probeSize(dp: dp, qy: Self.q, qx: Self.q))
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
    func testBraggContentAboveThresholdInflatesTheRadius() throws {
        var dp = [Float](repeating: 0, count: Self.q * Self.q)
        Self.drawDisk(into: &dp, cx: 31.5, cy: 31.5, radius: 4, intensity: 100)
        for (sx, sy) in [(12, 12), (50, 12), (12, 50), (50, 50),
                         (31, 10), (31, 53), (10, 31), (53, 31)] {
            Self.drawDisk(into: &dp, cx: Double(sx), cy: Double(sy), radius: 4, intensity: 80)
        }
        let r = try XCTUnwrap(OriginCalibration.probeSize(dp: dp, qy: Self.q, qx: Self.q)).r
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
        let rMean = try XCTUnwrap(OriginCalibration.probeSize(dp: fit.meanDP, qy: d.qy, qx: d.qx)).r
        let rMax = try XCTUnwrap(OriginCalibration.probeSize(dp: fit.maxDP, qy: d.qy, qx: d.qx)).r
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
        let rMean = try XCTUnwrap(OriginCalibration.probeSize(dp: fit.meanDP, qy: d.qy, qx: d.qx)).r
        let rMax = try XCTUnwrap(OriginCalibration.probeSize(dp: fit.maxDP, qy: d.qy, qx: d.qx)).r
        XCTAssertGreaterThan(
            rMax, rMean * 1.5,
            "fixture broken: max and mean no longer discriminate (max \(rMax), mean \(rMean))"
        )
        XCTAssertEqual(
            fit.probeRadius, rMean, accuracy: 0.01,
            "run(cube:)'s radius must come from the MEAN pattern"
        )
    }

    // MARK: - Origin validity mask carried by the production path (v3.1, ADR 033)

    /// The actual behavioural change of the validity-mask increment is the
    /// PRODUCTION carry — `tiledRun` passing `originValidity: fitted.kept` onto
    /// `OriginMaps` (`OriginCalibration.swift`). Reverting that line to the init
    /// default (feature dead on every real fit) must go red HERE — a manual
    /// `OriginMaps(originValidity:)` in a disclosure test cannot see it. The
    /// fixture displaces the beam at three known scan positions so the robust
    /// origin trim excludes exactly them; the product must both mark those
    /// positions invalid and equal an independent recompute of the trim on the
    /// pipeline's own measured origins (so this is a faithfulness check, not the
    /// tautology of comparing a value to itself).
    func testTiledRunCarriesTheOriginValidityMask() async throws {
        let source = DisplacedBeamFourDDataSource()
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        guard let fit = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane
        ) else { return XCTFail("tiledRun returned nil") }

        let mask = try XCTUnwrap(fit.origin.originValidity,
                                 "the production carry dropped the validity mask")
        XCTAssertEqual(mask.count, d.ry * d.rx)
        for i in DisplacedBeamFourDDataSource.displacedIndices {
            XCTAssertFalse(mask[i], "the trim must exclude displaced position \(i)")
        }
        XCTAssertEqual(mask.filter { $0 }.count,
                       d.ry * d.rx - DisplacedBeamFourDDataSource.displacedIndices.count,
                       "only the three displaced positions are excluded")
        // Faithful carry, not a tautology: the mask came off the Metal pipeline;
        // this recompute is an independent trim on the pipeline's own measured
        // origins, and must reproduce it exactly.
        let mx = try XCTUnwrap(fit.origin.measuredX)
        let my = try XCTUnwrap(fit.origin.measuredY)
        let recompute = OriginCalibration.fitOriginTrimmed(
            measuredX: mx, measuredY: my, width: d.rx, height: d.ry, fitFunction: .plane)
        XCTAssertEqual(mask, recompute.kept,
                       "the product's mask must equal the trim's kept set")
    }

    /// The resident-cube variant `run(cube:)` has no production callers (see
    /// `testResidentCubeRunMeasuresTheProbeOnTheMeanPattern`), so its own
    /// `originValidity: fitted.kept` line needs its own pin or a mutation
    /// reverting only it survives every gate.
    func testResidentCubeRunCarriesTheOriginValidityMask() async throws {
        let source = DisplacedBeamFourDDataSource()
        let d = try await source.discoverPrimaryDataset()
        let cube = await source.fullCube()
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(
            bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        guard let fit = try OriginCalibration.run(cube: buffer, descriptor: d) else {
            return XCTFail("run(cube:) returned nil")
        }
        let mask = try XCTUnwrap(fit.origin.originValidity,
                                 "run(cube:) dropped the validity mask")
        for i in DisplacedBeamFourDDataSource.displacedIndices {
            XCTAssertFalse(mask[i], "the trim must exclude displaced position \(i)")
        }
    }

    // MARK: - Friedel origin method end-to-end (v3.1)

    /// The whole Friedel path through `tiledRun`: mean DP → `BeamstopMask` →
    /// per-position `get_origin_friedel` → fit. The cube's patterns are
    /// centrosymmetric about an ASYMMETRIC origin (col 27, row 35), so a row/col
    /// swap in the CPU loop is caught; the fit must land on it, and the classical
    /// centre-of-mass method must agree on the same cube (so it is not merely
    /// self-consistent).
    func testFriedelOriginMethodRecoversAKnownAsymmetricOrigin() async throws {
        let source = FriedelCentrosymmetricSource()
        let d = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: d)
        guard let fit = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane, originMethod: .friedel
        ) else { return XCTFail("tiledRun(.friedel) returned nil") }
        XCTAssertEqual(fit.origin.fittedX[0], FriedelCentrosymmetricSource.originCol, accuracy: 0.6,
                       "Friedel origin X (detector column)")
        XCTAssertEqual(fit.origin.fittedY[0], FriedelCentrosymmetricSource.originRow, accuracy: 0.6,
                       "Friedel origin Y (detector row)")
        guard let com = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, fitFunction: .plane, originMethod: .centreOfMass
        ) else { return XCTFail("tiledRun(.centreOfMass) returned nil") }
        XCTAssertEqual(fit.origin.fittedX[0], com.origin.fittedX[0], accuracy: 1.0,
                       "Friedel and centre-of-mass must agree on this centrosymmetric cube")
        XCTAssertEqual(fit.origin.fittedY[0], com.origin.fittedY[0], accuracy: 1.0)
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

/// 6x6 scan of a 64x64 detector: a clean central beam at every position EXCEPT
/// three, where the beam sits ~20 px away so the robust origin trim excludes
/// exactly them. Lets a test see the per-position validity mask carry the RIGHT
/// positions, not merely a non-nil array. // v3.1 ADR 033
private actor DisplacedBeamFourDDataSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/displaced.h5", datasetPath: "/data",
        shape: [6, 6, 64, 64], dtypeDescription: "float32", chunkShape: nil
    )
    /// Row-major scan indices whose beam is displaced: (0,0), (3,2), (5,5).
    static let displacedIndices = [0, 20, 35]
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
        var centred = [Float](repeating: 0, count: q * q)
        draw(into: &centred, cx: 31.5, cy: 31.5, radius: 4, intensity: 100)
        var displaced = [Float](repeating: 0, count: q * q)
        draw(into: &displaced, cx: 46, cy: 46, radius: 4, intensity: 100)
        var all: [Float] = []
        all.reserveCapacity(d.ry * d.rx * q * q)
        for i in 0..<(d.ry * d.rx) {
            all.append(contentsOf: Self.displacedIndices.contains(i) ? displaced : centred)
        }
        cube = all
    }

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

/// A 2x2 scan of an all-zero 16x16 detector: nothing to size a probe on.
private actor ZeroFourDDataSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/zero.h5", datasetPath: "/data",
        shape: [2, 2, 16, 16], dtypeDescription: "float32", chunkShape: nil
    )
    private let cube = [Float](repeating: 0, count: 2 * 2 * 16 * 16)

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

/// 4x4 scan of a 64x64 detector: every pattern identical and centrosymmetric
/// about an asymmetric origin (col 27, row 35) — a central Gaussian beam plus
/// three Friedel-paired disks. The Friedel origin method must recover that
/// centre; the asymmetry (col != row) makes a row/col swap fail. // v3.1
private actor FriedelCentrosymmetricSource: FourDDataSource {
    static let originCol: Float = 27.0
    static let originRow: Float = 35.0
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/friedel.h5", datasetPath: "/data",
        shape: [4, 4, 64, 64], dtypeDescription: "float32", chunkShape: nil
    )
    private let cube: [Float]

    init() {
        let d = Self.descriptor
        let q = d.qx
        func gaussian(into dp: inout [Float], col: Double, row: Double, amp: Float, sigma: Double) {
            for y in 0..<q {
                for x in 0..<q {
                    let dx = Double(x) - col, dy = Double(y) - row
                    dp[y * q + x] += amp * Float(exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)))
                }
            }
        }
        var pat = [Float](repeating: 0, count: q * q)
        let c = Double(Self.originCol), r = Double(Self.originRow)
        gaussian(into: &pat, col: c, row: r, amp: 1000, sigma: 2.2)               // central beam
        for (u, v, a) in [(6.0, 3.0, 400.0), (-2.0, 8.0, 260.0), (9.0, -5.0, 180.0)] {
            gaussian(into: &pat, col: c + u, row: r + v, amp: Float(a), sigma: 1.8)   // Friedel pair
            gaussian(into: &pat, col: c - u, row: r - v, amp: Float(a), sigma: 1.8)
        }
        var all: [Float] = []
        all.reserveCapacity(d.ry * d.rx * q * q)
        for _ in 0..<(d.ry * d.rx) { all.append(contentsOf: pat) }
        cube = all
    }

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
