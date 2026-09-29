//
//  LearnedWindowedDetectionTests.swift
//  The learned detector above the model's 256-px frame (Gate D record:
//  docs/archive/v4/learned-windows-D098-D004-gateD-2026-09-30.md).
//
//  D098  one dose scale per NATIVE pattern (`simulate.model_inputs` scales the native pattern, then fits it), not
//        one per 256-px window: a window without the beam was inflated to the beam's dose.
//  D004  the edge rule was window-relative and 2·edgeBoundary exceeded the actual window overlap on most
//        detectors above ~470 px, so a band at every seam was rejected by BOTH windows.
//  Pure functions first (no model), then the scan on a synthetic float pattern (`WindowedFixture`, Core ML).
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

final class LearnedWindowedDetectionTests: XCTestCase {

    // MARK: D004 - the margins leave no band unsearched (pure)

    /// The accepted interval of window i along an axis is [o_i + lo_i, o_i + 256 - hi_i). Consecutive intervals
    /// must touch or overlap, and the first/last must start/end at the detector's own edge margin.
    private func assertCovers(q: Int, eb: Int, overlap: Int, file: StaticString = #filePath, line: UInt = #line) {
        let S = LearnedDiskDetector.inputSize
        let o = LearnedDiskDetector.windowOrigins(q: q, probeCentreOnAxis: Float(q) / 2, overlap: overlap)
        let m = LearnedDiskDetector.edgeMargins(origins: o, edge: eb)
        XCTAssertEqual(m.count, o.count, file: file, line: line)
        XCTAssertEqual(m.first?.lo, eb, "the detector's own left edge keeps edgeBoundary", file: file, line: line)
        XCTAssertEqual(m.last?.hi, eb, "the detector's own right edge keeps edgeBoundary", file: file, line: line)
        for i in 0..<(o.count - 1) {
            XCTAssertLessThanOrEqual(o[i + 1] + m[i + 1].lo, o[i] + S - m[i].hi,
                                     "q \(q) eb \(eb) overlap \(overlap): a band between windows \(i) and \(i + 1) is rejected by both", file: file, line: line)
        }
        for i in o.indices { XCTAssertLessThanOrEqual(m[i].lo, eb, file: file, line: line); XCTAssertLessThanOrEqual(m[i].hi, eb, file: file, line: line) }
    }

    func testEdgeMarginsLeaveNoUnsearchedBandAtAnyDetectorSize() {
        for q in 257...2048 {
            for eb in [max(2, q / 24), 6, 18, 42, 85] {
                for overlap in [24, 26, 42, 82] { assertCovers(q: q, eb: eb, overlap: overlap) }
            }
        }
    }

    /// The defect itself, in numbers: at q = 1024 the windows [0,256) and [192,448) share 64 px and the old rule
    /// (edgeBoundary 42 on both sides) accepts x < 214 from one and x >= 234 from the other.
    func testTheOldRuleLeftATwentyPixelBandAt1024() {
        let o = LearnedDiskDetector.windowOrigins(q: 1024, probeCentreOnAxis: 512, overlap: 26)
        XCTAssertEqual(o, [0, 192, 384, 576, 768])
        XCTAssertEqual(o[1] + 42 - (o[0] + 256 - 42), 20, "the band [214, 234) that both windows rejected")
        let m = LearnedDiskDetector.edgeMargins(origins: o, edge: 42)
        XCTAssertEqual(m[0].hi, 32); XCTAssertEqual(m[1].lo, 32)
        XCTAssertEqual(m[0].lo, 42, "the first window's left side is the detector's edge")
        XCTAssertEqual(m[4].hi, 42, "the last window's right side is the detector's edge")
    }

    /// Where the overlap already was at least 2·edgeBoundary nothing moves: q = 512 (overlap 128, edgeBoundary 21),
    /// and the fixture's own 488-px tiling (overlap 24, edgeBoundary 6).
    func testMarginsAreTheOldRuleWhereItWorked() {
        let o512 = LearnedDiskDetector.windowOrigins(q: 512, probeCentreOnAxis: 256, overlap: 26)
        XCTAssertEqual(LearnedDiskDetector.edgeMargins(origins: o512, edge: 21).map { [$0.lo, $0.hi] }, [[21, 21], [21, 21], [21, 21]])
        XCTAssertEqual(LearnedDiskDetector.edgeMargins(origins: [0, 232], edge: 6).map { [$0.lo, $0.hi] }, [[6, 6], [6, 6]])
        // one window: both sides are the detector's
        XCTAssertEqual(LearnedDiskDetector.edgeMargins(origins: [-64], edge: 6).map { [$0.lo, $0.hi] }, [[6, 6]])
        // Si_SiGe (480 px, edgeBoundary 18): windows share 32 px, so 16 + 16 - the 4 px band [238, 242) closes exactly
        let sige = LearnedDiskDetector.windowOrigins(q: 480, probeCentreOnAxis: 240, overlap: 26)
        XCTAssertEqual(sige, [0, 224])
        XCTAssertEqual(LearnedDiskDetector.edgeMargins(origins: sige, edge: 18).map { [$0.lo, $0.hi] }, [[18, 16], [16, 18]])
    }

    // MARK: D004 - refine takes the margins per side (pure)

    private func gaussianSurface(_ peaks: [(x: Float, y: Float)], size S: Int = 256) -> [Float] {
        var ar = [Float](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S {
            var v: Float = 0
            for p in peaks { let dx = Float(x) - p.x, dy = Float(y) - p.y; v += exp(-(dx * dx + dy * dy) / 4.5) }
            ar[y * S + x] = v
        } }
        return ar
    }

    func testRefineAppliesEachSidesMargin() throws {
        let f = try LearnedSwiftFixture.load()
        let det = try f.fittedDetector()
        var p = DiskDetectionParams(); p.edgeBoundary = 42; p.minPeakSpacing = 8; p.maxNumPeaks = 70
        let ar = gaussianSurface([(230, 100), (25, 100), (100, 230), (100, 25)])
        let cands = [(230, 100), (25, 100), (100, 230), (100, 25)].map { DiskDetector.Candidate(x: $0.0, y: $0.1, score: 0.9) }
        XCTAssertEqual(det.refine(candidates: cands, smoothedCorrelation: ar, params: p).count, 0, "edgeBoundary 42 on every side: all four rejected")
        XCTAssertEqual(det.refine(candidates: cands, smoothedCorrelation: ar, params: p,
                                  edgeMargins: .init(left: 42, right: 42, top: 42, bottom: 42)).count, 0, "explicit equal margins = nil")
        let right = det.refine(candidates: cands, smoothedCorrelation: ar, params: p, edgeMargins: .init(left: 42, right: 16, top: 42, bottom: 42))
        XCTAssertEqual(right.count, 1); XCTAssertEqual(right.first?.x ?? -1, 230, accuracy: 0.6)
        let left = det.refine(candidates: cands, smoothedCorrelation: ar, params: p, edgeMargins: .init(left: 16, right: 42, top: 42, bottom: 42))
        XCTAssertEqual(left.count, 1); XCTAssertEqual(left.first?.x ?? -1, 25, accuracy: 0.6)
        let top = det.refine(candidates: cands, smoothedCorrelation: ar, params: p, edgeMargins: .init(left: 42, right: 42, top: 16, bottom: 42))
        XCTAssertEqual(top.count, 1); XCTAssertEqual(top.first?.y ?? -1, 25, accuracy: 0.6)
        let bottom = det.refine(candidates: cands, smoothedCorrelation: ar, params: p, edgeMargins: .init(left: 42, right: 42, top: 42, bottom: 16))
        XCTAssertEqual(bottom.count, 1); XCTAssertEqual(bottom.first?.y ?? -1, 230, accuracy: 0.6)
    }

    // MARK: D098 - one dose scale per native pattern (pure)

    func testNativeCountScaleIsTheWholePatternsToCountsScale() {
        func scale(_ p: [Float]) -> Float { p.withUnsafeBufferPointer { LearnedDiskDetector.nativeCountScale(pattern: $0.baseAddress!, count: p.count) } }
        XCTAssertEqual(scale([0, 0.25, 0.5]), 40_000, accuracy: 1e-1, "a fraction of the beam: 20 000 / max")
        XCTAssertEqual(scale([0, 3, 1200]), 1, "counts: untouched")
        XCTAssertEqual(scale([0, 0, 0]), 1, "all zero")
        XCTAssertEqual(scale([-2, -1]), 1, "no positive value")
        XCTAssertEqual(scale([0, .nan, 0.5, .infinity]), 40_000, accuracy: 1e-1, "non-finite pixels are ignored, as fillNonFinite replaces them")
        XCTAssertEqual(scale([0, 1]), 20_000, accuracy: 1e-3, "max exactly 1 is still a fraction (toCounts: mx <= 1)")
    }

    /// The channel-0 ratio of two pixels is a function of the dose scale (log1p is not linear), so it is the
    /// window-independent quantity iff the scale is shared. p, q sit in the overlap of two windows of a 300 px
    /// float pattern whose beam (0.9) lies in only one of them.
    func testWindowsOfOnePatternShareTheDoseScale() {
        let S = LearnedDiskDetector.inputSize, Q = 300
        var native = [Float](repeating: 0, count: Q * Q)
        native[40 * Q + 40] = 0.9                    // the beam, x < 44 only: window [44, 300) does not see it
        native[150 * Q + 150] = 0.05                 // p
        native[160 * Q + 170] = 0.005                // q
        let scale = native.withUnsafeBufferPointer { LearnedDiskDetector.nativeCountScale(pattern: $0.baseAddress!, count: Q * Q) }
        XCTAssertEqual(scale, 20_000 / 0.9, accuracy: 1)
        let ones = [Float](repeating: 1, count: S * S)
        func ratio(col0: Int, shared: Bool) -> Float {
            var crop = [Float](repeating: 0, count: S * S)
            native.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: Q, qx: Q, row0: 0, col0: col0, into: &crop) }
            let mi = LearnedDiskDetector.modelInputs(pattern: crop, probe: ones, correlation: ones, countScale: shared ? scale : nil)
            return Float(mi[150 * S + 150 - col0]) / Float(mi[160 * S + 170 - col0])
        }
        // the per-window rule (what the scan did): the window with the beam and the window without disagree by ~10 %
        XCTAssertGreaterThan(abs(ratio(col0: 0, shared: false) - ratio(col0: 44, shared: false)) / ratio(col0: 0, shared: false), 0.05)
        // one scale: the same pixels, the same ratio (float16 rounding only)
        XCTAssertEqual(ratio(col0: 0, shared: true), ratio(col0: 44, shared: true), accuracy: 0.005)
        // and modelInputs(countScale: nil) is unchanged
        var crop = [Float](repeating: 0, count: S * S); crop[5] = 0.5; crop[9] = 0.001
        XCTAssertEqual(LearnedDiskDetector.modelInputs(pattern: crop, probe: ones, correlation: ones),
                       LearnedDiskDetector.modelInputs(pattern: crop, probe: ones, correlation: ones, countScale: LearnedDiskDetector.nativeCountScale(pattern: crop, count: S * S)))
    }

    // MARK: The scan (needs the Core ML package; skipped where it cannot load)

    /// Thread-safe collector for `LearnedDiskDetector.inputObserver`.
    private nonisolated final class Inputs: @unchecked Sendable {
        private let lock = NSLock(); private var byJob: [Int: [Float16]] = [:]
        func put(_ job: Int, _ v: [Float16]) { lock.lock(); byJob[job] = v; lock.unlock() }
        func get(_ job: Int) -> [Float16]? { lock.lock(); defer { lock.unlock() }; return byJob[job] }
    }

    /// A 400 px pattern (2 × 2 windows, origins 0 and 144 per axis, 112 px shared) on a zero background: one bright dot
    /// `beam` that only the first window sees, and p, q - two faint dots every window sees. Returns the channel-0 ratio
    /// c0[p] / c0[q] of each window, as the scan's own model input.
    private func channel0Ratios(beam: Float, p: Float, q: Float) async throws -> [Float] {
        let learned = try await LearnedSwiftFixture.loadDetector()
        let Q = 400, S = LearnedDiskDetector.inputSize
        var native = [Float](repeating: 0, count: Q * Q)
        native[40 * Q + 40] = beam; native[200 * Q + 200] = p; native[210 * Q + 220] = q
        let probeFx = WindowedFixture.make(qy: Q, qx: Q, beam: (200, 200))       // any real disk probe of the right size
        let buf = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: native, length: native.count * 4))
        let d = DatasetDescriptor(filePath: "/synthetic/d098.h5", datasetPath: "/d", shape: [1, 1, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let seen = Inputs()
        learned.inputObserver = { seen.put($0, $1) }
        var params = DiskDetectionParams(); params.edgeBoundary = 6; params.minPeakSpacing = 8
        let out = await learned.detectAll(cube: buf, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probeFx.probe),
                                          probeCentre: (200, 200), probeRadius: 12, params: params)
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.detectionProvenance["learned_windows"], "2x2")
        let origins = LearnedDiskDetector.windowOrigins(q: Q, probeCentreOnAxis: 200, overlap: 26)
        XCTAssertEqual(origins, [0, 144])
        var ratios: [Float] = []
        for (j, (r0, c0)) in origins.flatMap({ r in origins.map { (r, $0) } }).enumerated() {
            let mi = try XCTUnwrap(seen.get(j), "window job \(j) reached the observer")
            ratios.append(Float(mi[(200 - r0) * S + 200 - c0]) / Float(mi[(210 - r0) * S + 220 - c0]))
        }
        return ratios
    }

    /// D098 end to end: a float pattern (max 0.9 <= 1). p and q sit in all four windows; only window 0 holds the
    /// beam. With one dose scale for the pattern their channel-0 ratio is the same in every window (~1.49); scaled by each
    /// window's own maximum the three windows without the beam saw ~1.30.
    func testFloatPatternWindowsShareOneDoseScaleInTheScan() async throws {
        let r = try await channel0Ratios(beam: 0.9, p: 0.05, q: 0.005)
        XCTAssertEqual(r.count, 4)
        XCTAssertEqual(r[0], 1.487, accuracy: 0.02, "the window that holds the beam")
        for w in 1..<4 { XCTAssertEqual(r[w], r[0], accuracy: 0.02, "window \(w) (no beam) must use the pattern's scale, ratio \(r[w])") }
    }

    /// The other branch: a pattern in COUNTS (max 500) whose beam-less windows have a maximum <= 1. The pattern is not a
    /// fraction of the beam, so no window is scaled: the ratio is log1p(0.5) / log1p(0.1) = 4.25 in all four.
    func testCountPatternIsNotScaledInAnyWindow() async throws {
        let r = try await channel0Ratios(beam: 500, p: 0.5, q: 0.1)
        for w in 0..<4 { XCTAssertEqual(r[w], 4.25, accuracy: 0.15, "window \(w): counts stay counts, ratio \(r[w])") }
    }

    /// A detector that fits the frame is ONE window and keeps the per-frame rule (its output must not move): 250 px,
    /// probe centre at x = 200, so the frame [72, 328) drops the columns [0, 72) - and the bright dot in them. The frame's
    /// own maximum (0.5) sets the scale, not the pattern's (0.9).
    func testSingleWindowKeepsThePerFrameDoseScale() async throws {
        let learned = try await LearnedSwiftFixture.loadDetector()
        let Q = 250, S = LearnedDiskDetector.inputSize
        var native = [Float](repeating: 0, count: Q * Q)
        native[100 * Q + 10] = 0.9                      // outside the frame
        native[120 * Q + 150] = 0.5; native[130 * Q + 160] = 0.01
        let probeFx = WindowedFixture.make(qy: Q, qx: Q, beam: (200, 125))
        let buf = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: native, length: native.count * 4))
        let d = DatasetDescriptor(filePath: "/synthetic/one.h5", datasetPath: "/d", shape: [1, 1, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let seen = Inputs()
        learned.inputObserver = { seen.put($0, $1) }
        var params = DiskDetectionParams(); params.edgeBoundary = 6; params.minPeakSpacing = 8
        let out = await learned.detectAll(cube: buf, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probeFx.probe),
                                          probeCentre: (200, 125), probeRadius: 12, params: params)
        XCTAssertEqual(out?.detectionProvenance["learned_windows"], "1x1")
        let o = LearnedDiskDetector.fitOffset(probeCentre: (200, 125))
        var crop = [Float](repeating: 0, count: S * S)
        native.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: Q, qx: Q, row0: o.row0, col0: o.col0, into: &crop) }
        let ones = [Float](repeating: 1, count: S * S)
        let want = LearnedDiskDetector.modelInputs(pattern: crop, probe: ones, correlation: ones)
        let got = try XCTUnwrap(seen.get(0))
        XCTAssertEqual(Array(got[0..<(S * S)]), Array(want[0..<(S * S)]), "channel 0 is exactly the per-frame rule's")
    }

    /// D004 end to end, on a 1024 px float pattern (5 × 5 windows, 64 px shared, edgeBoundary 42). A lattice of disks
    /// with 40 more planted at the seams' centres x or y = 224 + 192 k: the band [214, 234) + 192 k that both windows
    /// rejected. Measured 2026-09-30 (the record above): before, 113 of 153 found and 0 of the 40 band disks; after, 153 / 40
    /// (seed 1) and 152 / 39 (seed 2), precision 1.
    func testSeamBandDisksAreFoundOnceAt1024() async throws {
        let learned = try await LearnedSwiftFixture.loadDetector()
        let eb = 42
        var extra: [(x: Float, y: Float)] = []
        for c in stride(from: Float(224), through: 800, by: 192) { for t in stride(from: Float(60), to: Float(964), by: 64) { extra.append((c, t)); extra.append((t, c)) } }
        let band: [Range<Float>] = [214..<234, 406..<426, 598..<618, 790..<810]
        for seed in [UInt64(1), 2] {
            let fx = WindowedFixture.make(qy: 1024, qx: 1024, beam: (512, 512), extra: extra, seed: seed)
            let out = try await fx.detect(learned)
            XCTAssertEqual(out.detectionProvenance["learned_windows"], "5x5")
            let s = fx.score(out.peaks[0], edge: eb, bandX: band, bandY: band)
            XCTAssertGreaterThan(s.bandTruth, 30, "the fixture must hold band disks to mean anything")
            XCTAssertGreaterThanOrEqual(s.bandRecall, 0.9, "seed \(seed): \(s.line)")
            XCTAssertGreaterThanOrEqual(s.recall, 0.95, "seed \(seed): \(s.line)")
            XCTAssertGreaterThanOrEqual(s.precision, 0.98, "seed \(seed): \(s.line)")
            let peaks = out.peaks[0]
            let spacing = WindowedFixture.params(qy: 1024, qx: 1024).minPeakSpacing
            for i in peaks.indices { for j in peaks.indices where j > i {
                XCTAssertGreaterThanOrEqual(hypotf(peaks[i].x - peaks[j].x, peaks[i].y - peaks[j].y), spacing, "a disk seen through two windows is reported once")
            } }
        }
    }

    /// The control: 512 px, 128 px shared >= 2 · 21, no band - found in full, precision 1, the same as before the change.
    func testFiveHundredTwelveNeedsNoMarginChange() async throws {
        let learned = try await LearnedSwiftFixture.loadDetector()
        let fx = WindowedFixture.make(qy: 512, qx: 512, beam: (256, 256), extra: [], seed: 1)
        let out = try await fx.detect(learned)
        let s = fx.score(out.peaks[0], edge: 21)
        XCTAssertEqual(s.recall, 1, accuracy: 1e-9, s.line); XCTAssertEqual(s.precision, 1, accuracy: 1e-9, s.line)
    }
}
