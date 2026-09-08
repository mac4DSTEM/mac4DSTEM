//
//  LearnedDiskDetectorTests.swift
//  The learned disk-candidate stage against its Python reference (v3-plan §3a step 4; C7 2026-09-08).
//
//  The fixture is tools/disk-detector/fixture/swift/, written by fixture/write_swift_fixture.py
//  from the committed synthetic fixture (native 128 px) and the committed Core ML package (256 px):
//  the 16 native patterns, the native probe, Python's model inputs for two patterns in the FITTED
//  frame, and per pattern the raw peak picks and the accepted refined peaks (evaluate.pick / refine /
//  accept, all in the 256 frame). Everything here must reproduce them — the fit (zero padding about
//  the probe centre, `simulate.fit_to`) included.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The Swift fixture, shared by the three learned-detector test files.
struct LearnedSwiftFixture {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let dir = repo.appendingPathComponent("tools/disk-detector/fixture/swift")
    static let assetMeta = repo.appendingPathComponent("Models/DiskDetector/\(LearnedDiskDetector.bundledAssetName).json")
    /// The bundled copy first (the test host is the app), the repo copy otherwise. Same bytes
    /// either way: the hash test proves it.
    static var assetURL: URL {
        LearnedDiskDetector.bundledAssetURL()
            ?? repo.appendingPathComponent("Models/DiskDetector/\(LearnedDiskDetector.bundledAssetName).mlpackage")
    }

    struct Expected: Decodable {
        struct Settings: Decodable { let minPeakSpacing: Float; let edgeBoundary: Int; let sigma_cc: Float; let maxNumPeaks: Int }
        struct Pattern: Decodable { let picks: [[Double]]; let accepted: [[Double]] }
        let count: Int; let native_size: Int; let size: Int
        let probe_centre: [Double]; let probe_centre_fit: [Double]; let fit_offset: [Int]; let probe_radius: Double
        let threshold: Float; let settings: Settings; let asset: String; let asset_sha256: String
        let inputs_ref_indices: [Int]; let patterns: [Pattern]
    }

    let expected: Expected
    let patterns: [[Float]]      // 16 × (native²), native frame
    let probe: [Float]           // native²
    let inputsRef: [[Float16]]   // 2 × (3·S²), the fitted frame
    var native: Int { expected.native_size }
    var S: Int { expected.size }
    /// Python (row, col) = Swift (y, x)
    var probeCentre: (x: Float, y: Float) { (Float(expected.probe_centre[1]), Float(expected.probe_centre[0])) }
    var probeCentreFit: (x: Float, y: Float) { (Float(expected.probe_centre_fit[1]), Float(expected.probe_centre_fit[0])) }
    var probeRadius: Float { Float(expected.probe_radius) }

    static func load() throws -> LearnedSwiftFixture {
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        let n = expected.native_size * expected.native_size
        let u16 = try Data(contentsOf: dir.appendingPathComponent("patterns.u16"))
        XCTAssertEqual(u16.count, expected.count * n * 2)
        let raw: [UInt16] = u16.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        let patterns = (0..<expected.count).map { i in raw[(i * n)..<((i + 1) * n)].map { Float(UInt16(littleEndian: $0)) } }
        let probe: [Float] = try Data(contentsOf: dir.appendingPathComponent("probe.f32")).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let n3 = 3 * expected.size * expected.size
        let refs: [Float16] = try Data(contentsOf: dir.appendingPathComponent("inputs-ref.f16")).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        XCTAssertEqual(refs.count, expected.inputs_ref_indices.count * n3)
        let inputsRef = (0..<expected.inputs_ref_indices.count).map { Array(refs[($0 * n3)..<(($0 + 1) * n3)]) }
        return LearnedSwiftFixture(expected: expected, patterns: patterns, probe: probe, inputsRef: inputsRef)
    }

    /// `simulate.fit_to` of a native image about the probe centre: the S×S frame.
    func fitted(_ image: [Float]) -> [Float] {
        let o = LearnedDiskDetector.fitOffset(probeCentre: probeCentre)
        var out = [Float](repeating: 0, count: S * S)
        image.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: native, qx: native, row0: o.row0, col0: o.col0, into: &out) }
        return out
    }

    func params() -> DiskDetectionParams {
        var p = DiskDetectionParams()
        let e = expected.settings
        p.sigmaCC = e.sigma_cc; p.subpixel = .poly
        p.minPeakSpacing = e.minPeakSpacing; p.edgeBoundary = e.edgeBoundary
        p.minRelativeIntensity = 0.05; p.maxNumPeaks = e.maxNumPeaks
        return p
    }

    /// The classical detector on the FITTED frame: the fitted probe, the fitted centre.
    func fittedDetector() throws -> DiskDetector {
        let k = try XCTUnwrap(ProbeKernel.flat(
            pattern: DiffractionPattern(qy: S, qx: S, pixels: fitted(probe)),
            originX: probeCentreFit.x, originY: probeCentreFit.y, radius: probeRadius, source: .measured))
        return try XCTUnwrap(DiskDetector(kernel: k))
    }

    /// The classical detector on the NATIVE frame (the pure `refine` tests need any grid).
    func nativeDetector() throws -> DiskDetector {
        let k = try XCTUnwrap(ProbeKernel.flat(
            pattern: DiffractionPattern(qy: native, qx: native, pixels: probe),
            originX: probeCentre.x, originY: probeCentre.y, radius: probeRadius, source: .measured))
        return try XCTUnwrap(DiskDetector(kernel: k))
    }

    /// The model inputs and smoothed correlations of every fixture pattern in the fitted frame,
    /// zero-padded to one batch of `detector.batch`.
    func batchInputs(_ det: DiskDetector, batch: Int) -> (inputs: [Float16], smoothed: [[Float]]) {
        let n3 = 3 * S * S
        let p = params()
        var inputs = [Float16](repeating: 0, count: batch * n3)
        var smoothed: [[Float]] = []
        let probeFit = fitted(probe)
        for i in 0..<expected.count {
            let pat = fitted(patterns[i])
            let corr = pat.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            inputs.replaceSubrange((i * n3)..<((i + 1) * n3), with: LearnedDiskDetector.modelInputs(pattern: pat, probe: probeFit, correlation: corr.raw))
            smoothed.append(corr.smoothed)
        }
        return (inputs, smoothed)
    }

    static func loadDetector() async throws -> LearnedDiskDetector {
        guard FileManager.default.fileExists(atPath: assetURL.path) else { throw XCTSkip("no committed asset at \(assetURL.path)") }
        do { return try await LearnedDiskDetector.load(assetURL: assetURL) }
        catch { throw XCTSkip("Core ML could not load the asset here: \(error)") }
    }
}

final class LearnedDiskDetectorTests: XCTestCase {

    // MARK: 1. The fit and the normalisation equal simulate.fit_to + simulate.model_inputs

    func testFitOffsetMatchesPython() throws {
        let f = try LearnedSwiftFixture.load()
        let o = LearnedDiskDetector.fitOffset(probeCentre: f.probeCentre)
        XCTAssertEqual([o.row0, o.col0], f.expected.fit_offset, "simulate.fit_offset for the native probe centre")
        XCTAssertEqual(f.probeCentreFit.x, f.probeCentre.x - Float(o.col0), accuracy: 1e-4)
        XCTAssertEqual(f.probeCentreFit.y, f.probeCentre.y - Float(o.row0), accuracy: 1e-4)
        // a detector smaller than the frame is ONE window at the fit offset (padding), never clamped
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: f.native, probeCentreOnAxis: f.probeCentre.y, overlap: 24), [o.row0])
        // the fitted pattern is the native one, translated: pixel (r, c) native → (r − row0, c − col0)
        let fit = f.fitted(f.patterns[0])
        XCTAssertEqual(fit[(10 - o.row0) * f.S + (20 - o.col0)], f.patterns[0][10 * f.native + 20])
        XCTAssertEqual(fit.reduce(0, +), f.patterns[0].reduce(0, +), accuracy: 1, "padding adds nothing: same sum")
    }

    func testModelInputsMatchPythonReference() throws {
        let f = try LearnedSwiftFixture.load()
        let det = try f.fittedDetector()
        let p = f.params()
        let probeFit = f.fitted(f.probe)
        for (k, idx) in f.expected.inputs_ref_indices.enumerated() {
            let pat = f.fitted(f.patterns[idx])
            let corr = pat.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let mine = LearnedDiskDetector.modelInputs(pattern: pat, probe: probeFit, correlation: corr.raw)
            var maxDiff: Float = 0
            for i in mine.indices { maxDiff = max(maxDiff, abs(Float(mine[i]) - Float(f.inputsRef[k][i]))) }
            // float16 quantisation of two float pipelines (float32 here, float64 in numpy): one ulp near 1 is ~1e-3
            XCTAssertLessThan(maxDiff, 2e-3, "pattern \(idx): model inputs differ from simulate.model_inputs by \(maxDiff)")
        }
    }

    /// `simulate.to_counts`: a float pattern with max in (0, 1] is scaled to a 2×10⁴-count beam;
    /// counts pass through. Its effect on the log channel is what the fixture cannot see (uint16).
    func testCountScalingRule() {
        let n = LearnedDiskDetector.inputSize * LearnedDiskDetector.inputSize
        // a float cube's pattern: fractions of the beam; one dark pixel so the min subtraction is a no-op
        var fraction = [Float](repeating: 0.002, count: n); fraction[0] = 0; fraction[7] = 0.5
        let scaled = LearnedDiskDetector.toCounts(fraction)
        XCTAssertEqual(scaled[7], 20_000, accuracy: 1e-2)
        XCTAssertEqual(scaled[1], 80, accuracy: 1e-3)
        XCTAssertEqual(scaled[0], 0)
        var counts = [Float](repeating: 3, count: n); counts[3] = 1200
        XCTAssertEqual(LearnedDiskDetector.toCounts(counts), counts, "already counts: untouched")
        XCTAssertEqual(LearnedDiskDetector.toCounts([Float](repeating: 0, count: n)), [Float](repeating: 0, count: n), "all zero: untouched")
        // the log channel of a fraction pattern equals that of its count-scaled twin
        let probe = [Float](repeating: 1, count: n), corr = [Float](repeating: 1, count: n)
        let a = LearnedDiskDetector.modelInputs(pattern: fraction, probe: probe, correlation: corr)
        let b = LearnedDiskDetector.modelInputs(pattern: scaled, probe: probe, correlation: corr)
        XCTAssertEqual(Array(a[0..<n]), Array(b[0..<n]))
        XCTAssertGreaterThan(Float(a[7]), 0.99, "the beam pixel is the log channel's maximum")
        // 80 counts against a 20 000-count beam: log1p(80)/log1p(20000) = 0.444; raw fractions would give log1p(0.002)/log1p(0.5) = 0.005
        XCTAssertEqual(Float(a[1]), 0.444, accuracy: 0.01, "count scaling before the log")
    }

    // MARK: 2. The committed asset is the one the fixture and the record name

    func testCommittedAssetHashMatchesItsRecordAndTheFixture() throws {
        struct Meta: Decodable { let sha256: String; let asset: String; let size: Int; let runtime: String; let threshold_shipped: Float }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: LearnedSwiftFixture.assetMeta))
        let f = try LearnedSwiftFixture.load()
        let sha = try LearnedDiskDetector.sha256(ofAsset: LearnedSwiftFixture.assetURL)
        XCTAssertEqual(sha, meta.sha256, "the record JSON names the committed package")
        XCTAssertEqual(sha, f.expected.asset_sha256, "the Swift fixture was written from the committed package")
        XCTAssertEqual(meta.asset, LearnedSwiftFixture.assetURL.lastPathComponent)
        XCTAssertEqual(meta.size, LearnedDiskDetector.inputSize)
        XCTAssertEqual(meta.runtime, "coreml")
        XCTAssertEqual(meta.threshold_shipped, LearnedDiskDetector.defaultThreshold)
        XCTAssertEqual(f.expected.threshold, LearnedDiskDetector.defaultThreshold, "the fixture is written at the shipped threshold")
    }

    // MARK: 3. The whole learned path reproduces Python's picks and accepted peaks

    func testLearnedPathMatchesPythonReference() async throws {
        let f = try LearnedSwiftFixture.load()
        let e = f.expected
        let det = try f.fittedDetector()
        let p = f.params()
        let learned = try await LearnedSwiftFixture.loadDetector()
        XCTAssertEqual(learned.batch, 32)
        XCTAssertGreaterThanOrEqual(learned.batchMax, 32)
        XCTAssertEqual(learned.assetSHA256, e.asset_sha256)
        let n = f.S * f.S
        let (inputs, smoothed) = f.batchInputs(det, batch: learned.batch)
        let heat = try await learned.heatmaps(inputs: inputs)
        XCTAssertEqual(heat.count, learned.batch * n)
        var pickHits = 0, pickTotal = 0, pickMine = 0, acceptedCountMatches = 0, positionHits = 0, positionTotal = 0
        var worst: Float = 0
        for i in 0..<e.count {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(i * n)..<((i + 1) * n)]), threshold: e.threshold)
            }
            let refPicks = Set(e.patterns[i].picks.map { "\(Int($0[0])),\(Int($0[1]))" })
            pickTotal += refPicks.count
            pickHits += cands.filter { refPicks.contains("\($0.y),\($0.x)") }.count
            pickMine += cands.count
            let accepted = det.refine(candidates: cands, smoothedCorrelation: smoothed[i], params: p)
            if accepted.count == e.patterns[i].accepted.count { acceptedCountMatches += 1 }
            for ref in e.patterns[i].accepted {          // (row, col, score)
                positionTotal += 1
                let d = accepted.map { hypot($0.x - Float(ref[1]), $0.y - Float(ref[0])) }.min() ?? .infinity
                if d <= 0.05 { positionHits += 1 }
                worst = max(worst, d.isFinite ? d : 99)
            }
        }
        // The same package through the same Core ML runtime: the heatmaps are the same numbers up to
        // the compute unit's float16 rounding, so the picks and the accepted peaks are the same up
        // to float32-vs-float64 refinement rounding and a rare pick exactly at the threshold.
        XCTAssertGreaterThanOrEqual(Double(pickHits) / Double(pickTotal), 0.98, "raw picks: \(pickHits)/\(pickTotal) reproduce Python's")
        // and no extras: a loosened maximum test admits ridge pixels that suppression would hide (mutation M2, 2026-09-07)
        XCTAssertLessThanOrEqual(Double(pickMine - pickHits) / Double(pickTotal), 0.02, "raw picks: \(pickMine - pickHits) extra beyond Python's \(pickTotal)")
        XCTAssertGreaterThanOrEqual(acceptedCountMatches, e.count - 1, "accepted counts equal Python's in \(acceptedCountMatches)/\(e.count) patterns")
        XCTAssertGreaterThanOrEqual(Double(positionHits) / Double(positionTotal), 0.98,
                                    "accepted positions within 0.05 px of Python's: \(positionHits)/\(positionTotal), worst \(worst)")
    }

    /// The zero-padded tail of a batch must not change the patterns before it (the Neural Engine
    /// sees one fixed shape; a batch-dependent op would make the fixture's numbers depend on
    /// what else was in the batch).
    func testBatchPaddingDoesNotChangeAPattern() async throws {
        let f = try LearnedSwiftFixture.load()
        let det = try f.fittedDetector()
        let learned = try await LearnedSwiftFixture.loadDetector()
        let n = f.S * f.S, n3 = 3 * n
        let (inputs, _) = f.batchInputs(det, batch: learned.batch)
        let full = try await learned.heatmaps(inputs: inputs)
        var alone = [Float16](repeating: 0, count: learned.batch * n3)
        alone.replaceSubrange(0..<n3, with: inputs[(5 * n3)..<(6 * n3)])
        let single = try await learned.heatmaps(inputs: alone)
        var maxDiff: Float = 0
        for i in 0..<n { maxDiff = max(maxDiff, abs(Float(single[i]) - Float(full[5 * n + i]))) }
        XCTAssertLessThan(maxDiff, 1e-3, "pattern 5 alone in a batch differs from pattern 5 in the full batch by \(maxDiff)")
    }
}
