//
//  LearnedDiskDetectorGateBTests.swift
//  The Gate B refuter's assertions for step 4 slice 1 (2026-09-07), adopted after they were re-broken:
//  the committed fixture test could not see any of this. R1/R2 exercise `refine` alone (the fixture
//  never drops a candidate by spacing and never reaches the cap), R3 is py4DSTEM's precondition that the
//  parabola is evaluated only at a local maximum (before the fix, 10 of 255 fixture peaks were
//  fabricated on flanks and the Python reference agreed), R4 exercises `detectAll` on a padded,
//  multi-batch cube (no other test calls it: crop origin, batch base, row/col were each mutated and caught).
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

final class LearnedDiskDetectorGateBTests: XCTestCase {

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fixtureDir = repo.appendingPathComponent("tools/disk-detector/fixture/swift")
    private static let assetURL = repo.appendingPathComponent("Models/DiskDetector/disk-detector-heatmap-b32.aimodel")
    private static let S = 128

    private struct Expected: Decodable {
        struct Settings: Decodable { let minPeakSpacing: Float; let edgeBoundary: Int; let sigma_cc: Float; let maxNumPeaks: Int }
        struct Pattern: Decodable { let picks: [[Double]]; let accepted: [[Double]] }
        let count: Int; let probe_centre: [Double]; let probe_radius: Double
        let threshold: Float; let settings: Settings; let patterns: [Pattern]
    }
    private struct Fixture { let expected: Expected; let patterns: [[Float]]; let probe: [Float] }

    private func loadFixture() throws -> Fixture {
        let dir = Self.fixtureDir
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        let n = Self.S * Self.S
        let u16 = try Data(contentsOf: dir.appendingPathComponent("patterns.u16"))
        let raw: [UInt16] = u16.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        let patterns = (0..<expected.count).map { i in raw[(i * n)..<((i + 1) * n)].map { Float(UInt16(littleEndian: $0)) } }
        let probe: [Float] = try Data(contentsOf: dir.appendingPathComponent("probe.f32")).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return Fixture(expected: expected, patterns: patterns, probe: probe)
    }

    private func params(_ e: Expected) -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.sigmaCC = e.settings.sigma_cc; p.subpixel = .poly
        p.minPeakSpacing = e.settings.minPeakSpacing; p.edgeBoundary = e.settings.edgeBoundary
        p.minRelativeIntensity = 0.05; p.maxNumPeaks = e.settings.maxNumPeaks
        return p
    }

    private func unitParams() -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.sigmaCC = 2; p.subpixel = .poly; p.minPeakSpacing = 8; p.edgeBoundary = 6; p.maxNumPeaks = 70
        return p
    }

    /// A smoothed-correlation stand-in: a sum of Gaussians on the S×S grid.
    private func surface(peaks: [(x: Float, y: Float, amp: Float)], sigma: Float = 1.5) -> [Float] {
        let S = Self.S
        var ar = [Float](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S {
            var v: Float = 0
            for p in peaks { let dx = Float(x) - p.x, dy = Float(y) - p.y; v += p.amp * exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)) }
            ar[y * S + x] = v
        } }
        return ar
    }

    private func detector(_ f: Fixture) throws -> DiskDetector {
        let e = f.expected
        let k = try XCTUnwrap(ProbeKernel.flat(
            pattern: DiffractionPattern(qy: Self.S, qx: Self.S, pixels: f.probe),
            originX: Float(e.probe_centre[1]), originY: Float(e.probe_centre[0]),
            radius: Float(e.probe_radius), source: .measured))
        return try XCTUnwrap(DiskDetector(kernel: k))
    }

    // MARK: R1 — non-maximum suppression ranks by the NET score (the fixture never exercises NMS: 0 drops)

    func testRefineSuppressesByNetScoreNotByCorrelation() throws {
        let f = try loadFixture(); let det = try detector(f)
        // the brighter correlation peak (A) has the LOWER net score; B, 5 px away (< spacing 8), the higher
        let ar = surface(peaks: [(60, 60, 1.0), (65, 60, 0.6)])
        let cands = [DiskDetector.Candidate(x: 60, y: 60, score: 0.91), DiskDetector.Candidate(x: 65, y: 60, score: 0.95)]
        let kept = det.refine(candidates: cands, smoothedCorrelation: ar, params: unitParams())
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.x ?? -1, 65, accuracy: 0.3, "NMS must keep the higher NET score (B at x=65), not the brighter correlation peak")
    }

    // MARK: R2 — the cap (Python's `accept` has no cap; the fixture never exceeds 24)

    func testRefineCapsAtMaxNumPeaks() throws {
        let f = try loadFixture(); let det = try detector(f)
        var peaks: [(x: Float, y: Float, amp: Float)] = []
        var cands: [DiskDetector.Candidate] = []
        for i in 1...10 { for j in 1...10 { peaks.append((Float(i * 10), Float(j * 10), 1.0)); cands.append(.init(x: i * 10, y: j * 10, score: 0.95)) } }
        let kept = det.refine(candidates: cands, smoothedCorrelation: surface(peaks: peaks), params: unitParams())
        XCTAssertEqual(kept.count, 70)
    }

    // MARK: R3 — py4DSTEM's precondition: the parabola is only ever evaluated AT a local maximum, so |shift| ≤ 0.5

    /// Minimal case: a candidate 6 px from the only correlation peak. The 5×5 snap window does not reach the
    /// peak, so the snapped pixel is on the flank, not a maximum; the unguarded parabola then extrapolates.
    func testRefineRejectsOrBoundsCandidatesWithNoCorrelationMaximumInReach() throws {
        let f = try loadFixture(); let det = try detector(f)
        let ar = surface(peaks: [(60, 60, 1.0)], sigma: 1.5)
        let kept = det.refine(candidates: [.init(x: 66, y: 60, score: 0.95)], smoothedCorrelation: ar, params: unitParams())
        for k in kept {
            XCTAssertLessThanOrEqual(hypot(k.x - 60, k.y - 60), 0.5, "accepted a peak at (\(k.x), \(k.y)) — no correlation maximum there (the only one is at 60,60)")
        }
    }

    /// The fixture, end to end: every accepted peak must lie within 0.75 px (half a pixel per axis) of an
    /// 8-neighbour local maximum of the smoothed correlation it was refined on.
    @available(macOS 27, *)
    func testAcceptedPeaksSitOnCorrelationMaxima() async throws {
        let f = try loadFixture(); let e = f.expected; let det = try detector(f); let p = params(e)
        let learned: LearnedDiskDetector
        do { learned = try await LearnedDiskDetector.load(assetURL: Self.assetURL) } catch { throw XCTSkip("no Core AI: \(error)") }
        let S = Self.S, n = S * S, n3 = 3 * n
        var inputs = [Float16](repeating: 0, count: learned.batch * n3)
        var smoothed: [[Float]] = []
        for i in 0..<e.count {
            let corr = f.patterns[i].withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let mi = LearnedDiskDetector.modelInputs(pattern: f.patterns[i], probe: f.probe, correlation: corr.raw)
            inputs.replaceSubrange((i * n3)..<((i + 1) * n3), with: mi); smoothed.append(corr.smoothed)
        }
        let heat = try await learned.heatmaps(inputs: inputs)
        var accepted = 0, offMaximum = 0, worst: Float = 0
        var patternsHit = Set<Int>()
        for i in 0..<e.count {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(i * n)..<((i + 1) * n)]), threshold: e.threshold) }
            let ar = smoothed[i]
            var maxima: [(Float, Float)] = []
            for y in 1..<(S - 1) { for x in 1..<(S - 1) {
                let v = ar[y * S + x]; var isMax = true
                for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) { if ar[(y + dy) * S + x + dx] > v { isMax = false } } }
                if isMax { maxima.append((Float(x), Float(y))) }
            } }
            for k in det.refine(candidates: cands, smoothedCorrelation: ar, params: p) {
                accepted += 1
                let d = maxima.map { hypot(k.x - $0.0, k.y - $0.1) }.min() ?? .infinity
                if d > 0.75 { offMaximum += 1; patternsHit.insert(i); worst = max(worst, d) }
            }
        }
        XCTAssertEqual(offMaximum, 0, "\(offMaximum) of \(accepted) accepted peaks are not at a correlation maximum (worst \(worst) px, patterns \(patternsHit.sorted()))")
    }

    // MARK: R4 — detectAll on a padded cube equals the direct path shifted by the crop origin

    @available(macOS 27, *)
    func testDetectAllEqualsDirectPathShiftedByCropOrigin() async throws {
        let f = try loadFixture(); let e = f.expected; let det = try detector(f); let p = params(e)
        let learned: LearnedDiskDetector
        do { learned = try await LearnedDiskDetector.load(assetURL: Self.assetURL) } catch { throw XCTSkip("no Core AI: \(error)") }
        let S = Self.S, n = S * S, n3 = 3 * n
        // direct path per fixture pattern
        var inputs = [Float16](repeating: 0, count: learned.batch * n3)
        var smoothed: [[Float]] = []
        for i in 0..<e.count {
            let corr = f.patterns[i].withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let mi = LearnedDiskDetector.modelInputs(pattern: f.patterns[i], probe: f.probe, correlation: corr.raw)
            inputs.replaceSubrange((i * n3)..<((i + 1) * n3), with: mi); smoothed.append(corr.smoothed)
        }
        let heat = try await learned.heatmaps(inputs: inputs)
        var direct: [[BraggPeak]] = []
        for i in 0..<e.count {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(i * n)..<((i + 1) * n)]), threshold: e.threshold) }
            direct.append(det.refine(candidates: cands, smoothedCorrelation: smoothed[i], params: p))
        }
        // a 5×8 scan of 160×160 patterns: fixture pattern (pos % 13) placed at (row0 = 20, col0 = 7),
        // another fixture pattern tiled underneath so a wrong crop lands on real-looking data
        let Q = 160, row0 = 20, col0 = 7, ry = 5, rx = 8, positions = ry * rx
        var cube = [Float](repeating: 0, count: positions * Q * Q)
        for pos in 0..<positions {
            let a = f.patterns[pos % 13], b = f.patterns[(pos + 5) % 16]
            for y in 0..<Q { for x in 0..<Q { cube[pos * Q * Q + y * Q + x] = b[(y % S) * S + (x % S)] } }
            for y in 0..<S { for x in 0..<S { cube[pos * Q * Q + (row0 + y) * Q + col0 + x] = a[y * S + x] } }
        }
        var probe = [Float](repeating: 0, count: Q * Q)
        for y in 0..<S { for x in 0..<S { probe[(row0 + y) * Q + col0 + x] = f.probe[y * S + x] } }
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        let d = DatasetDescriptor(filePath: "/tmp/gateB.h5", datasetPath: "/d", shape: [ry, rx, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let centre = (x: Float(e.probe_centre[1]) + Float(col0), y: Float(e.probe_centre[0]) + Float(row0))
        let maybe = await learned.detectAll(
            cube: buffer, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probe),
            probeCentre: centre, probeRadius: Float(e.probe_radius), params: p, threshold: e.threshold)
        let out = try XCTUnwrap(maybe)
        XCTAssertEqual(out.peaks.count, positions)
        XCTAssertEqual(out.detectionProvenance["detector_class"], "learned")
        XCTAssertEqual(out.detectionProvenance["learned_crop_origin_x"], String(col0))
        XCTAssertEqual(out.detectionProvenance["learned_crop_origin_y"], String(row0))
        XCTAssertEqual(out.detectionProvenance["learned_model_sha256"], learned.assetSHA256)
        var countMismatches = 0, positionMisses = 0, total = 0, worst: Float = 0
        for pos in 0..<positions {
            let want = direct[pos % 13], got = out.peaks[pos]
            if want.count != got.count { countMismatches += 1 }
            for w in want {
                total += 1
                let dmin = got.map { hypot($0.x - (w.x + Float(col0)), $0.y - (w.y + Float(row0))) }.min() ?? .infinity
                if dmin > 0.05 { positionMisses += 1 }
                worst = max(worst, dmin.isFinite ? dmin : 99)
            }
        }
        XCTAssertEqual(countMismatches, 0, "detectAll peak counts differ from the direct path at \(countMismatches)/\(positions) positions")
        XCTAssertEqual(positionMisses, 0, "detectAll positions: \(positionMisses)/\(total) not within 0.05 px of direct + (\(col0), \(row0)); worst \(worst)")
    }
}
