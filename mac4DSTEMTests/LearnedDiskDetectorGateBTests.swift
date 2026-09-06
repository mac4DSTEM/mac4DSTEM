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
    /// The bundled copy first: the test host is the app itself, and the Core AI runtime caches
    /// an asset by content under the URL it was first loaded from — a test loading the repo
    /// copy while the app loads the bundle copy poisons the app's cache (owner's drive,
    /// 2026-09-07). Same bytes either way (the hash test proves it).
    private static var assetURL: URL {
        if #available(macOS 27, *), let bundled = LearnedDiskDetector.bundledAssetURL() { return bundled }
        return repo.appendingPathComponent("Models/DiskDetector/disk-detector-heatmap-b32.aimodel")
    }
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

    // MARK: R3b — the tiling grid and the merge, pure functions (no Core AI / ANE needed)

    /// `windowOverlap`/`windowOrigins`/`mergeWindows` never touch the model — they run on
    /// any macOS 27 host regardless of whether the Neural Engine specialises here. Checked
    /// against the formula in docs/v3-plan.md §3a: `overlap = max(2·⌈r⌉+2, 24)`,
    /// `n = 1 if q ≤ 128 else ⌈(q−overlap)/(128−overlap)⌉`, origins spread evenly across
    /// `0...(q−128)`, the one-window case centred on the probe.
    @available(macOS 27, *)
    func testWindowGridFormula() {
        // overlap: one disk diameter, floored at 24 px
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 10), 24, "2·⌈10⌉+2 = 22, below the 24 px floor")
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 20), 42, "2·⌈20⌉+2 = 42, above the floor")
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 0), 24)

        // q == inputSize: one window, forced to origin 0 regardless of centre (no slack)
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 128, probeCentreOnAxis: 63.6, overlap: 24), [0])

        // q == 160, overlap 24: n = ceil(136/104) = 2, origins spread across 0...32
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 160, probeCentreOnAxis: 84, overlap: 24), [0, 32])

        // q == 256, overlap 24: n = ceil(232/104) = 3, origins spread across 0...128
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 256, probeCentreOnAxis: 64, overlap: 24), [0, 64, 128])

        // q == 250 (the owner's bullseye cube), overlap 24: n = ceil(226/104) = 3
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 250, probeCentreOnAxis: 125, overlap: 24).count, 3)
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 250, probeCentreOnAxis: 125, overlap: 24), [0, 61, 122])
    }

    /// A synthetic three-window overlap at one scan position: window A and window B both
    /// see the SAME disk (a duplicate — the higher-intensity copy must survive), window C
    /// sees a disk nobody else does. Expect 2 peaks kept: the brighter duplicate and the
    /// unique one; capped further if `maxNumPeaks` is tight.
    @available(macOS 27, *)
    func testMergeWindowsDedupesByIntensityAndCaps() {
        var p = DiskDetectionParams(); p.minPeakSpacing = 8; p.maxNumPeaks = 70
        let dim = BraggPeak(x: 50, y: 50, intensity: 0.6)   // window A's copy of the shared disk
        let bright = BraggPeak(x: 50.1, y: 49.9, intensity: 0.9) // window B's copy — same disk, higher intensity
        let unique = BraggPeak(x: 100, y: 100, intensity: 0.4)   // only window C sees this one
        let merged = LearnedDiskDetector.mergeWindows([[dim], [bright], [unique]], params: p)
        XCTAssertEqual(merged.count, 2, "the duplicate must collapse to one peak")
        XCTAssertTrue(merged.contains { $0.intensity == 0.9 }, "the brighter of the two duplicate copies must be the one kept")
        XCTAssertFalse(merged.contains { $0.intensity == 0.6 }, "the dimmer duplicate must be dropped, not kept alongside")
        XCTAssertTrue(merged.contains { $0.intensity == 0.4 }, "the peak only one window saw must survive")

        // the cap applies to the MERGED set, same as `refine`'s own cap
        p.maxNumPeaks = 1
        let capped = LearnedDiskDetector.mergeWindows([[dim], [bright], [unique]], params: p)
        XCTAssertEqual(capped.count, 1)
        XCTAssertEqual(capped.first?.intensity, 0.9, "capped to 1, the highest-intensity peak must be the one kept")
    }

    // MARK: R4 — a 2×2 window grid with real content in the overlaps equals the per-window direct path, merged

    /// A 232-px detector: overlap 24 px for this fixture's probe, so `windowOrigins` gives
    /// [0, 104] per axis. Four DIFFERENT fixture patterns sit at the four window origins, so
    /// every window sees its own pattern plus a 24-px strip of each neighbour — what a real
    /// detector's windows see. The reference is the DIRECT path run on each window's actual
    /// 128-px content, shifted by the window origin and merged with `mergeWindows`: that is
    /// exactly what `detectAll` must compute, so the comparison is exact (0.05 px, equal
    /// counts) and isolates the tiling plumbing — job order, window origins, the shift back,
    /// the merge — from the net's own sensitivity to what lies in a window. (A first version
    /// compared against the ISOLATED patterns' peaks and lost 15 of 120: a U-Net's
    /// receptive field reaches well past the 24-px strip, so a neighbour's content moves
    /// borderline scores across the threshold. That is the model, not the tiling.)
    @available(macOS 27, *)
    func testTiledWindowsEqualPerWindowDirectPathMerged() async throws {
        let f = try loadFixture(); let e = f.expected; let det = try detector(f)
        var p = params(e); p.maxNumPeaks = 1000   // four patterns per position exceed the 70 cap; the cap is R2's test
        let learned: LearnedDiskDetector
        do { learned = try await LearnedDiskDetector.load(assetURL: Self.assetURL) } catch { throw XCTSkip("no Core AI: \(error)") }
        let S = Self.S, n = S * S, n3 = 3 * n
        let overlap = LearnedDiskDetector.windowOverlap(probeRadius: Float(e.probe_radius))
        let Q = 128 + (128 - overlap)                       // 232 for overlap 24: origins [0, 104]
        let origins = LearnedDiskDetector.windowOrigins(q: Q, probeCentreOnAxis: Float(Q) / 2, overlap: overlap)
        XCTAssertEqual(origins, [0, 128 - overlap])
        let placements = [(0, 0, 0), (0, 128 - overlap, 1), (128 - overlap, 0, 2), (128 - overlap, 128 - overlap, 3)]   // (row0, col0, pattern)
        let ry = 1, rx = 2, positions = ry * rx
        var cube = [Float](repeating: 0, count: positions * Q * Q)
        for pos in 0..<positions {
            for (row0, col0, k) in placements {
                let a = f.patterns[(k + 4 * pos) % 16]
                for y in 0..<S { for x in 0..<S { cube[pos * Q * Q + (row0 + y) * Q + col0 + x] = a[y * S + x] } }
            }
        }
        // the probe in the middle of the detector, like a real cube's; its 128-px crop is the fixture probe
        var probe = [Float](repeating: 0, count: Q * Q)
        let pr0 = (Q - S) / 2
        for y in 0..<S { for x in 0..<S { probe[(pr0 + y) * Q + pr0 + x] = f.probe[y * S + x] } }
        // the reference: the direct path on each window's actual content
        var inputs = [Float16](repeating: 0, count: learned.batch * n3)
        var smoothed: [[Float]] = []; var jobs: [(pos: Int, oy: Int, ox: Int)] = []
        for pos in 0..<positions { for oy in origins { for ox in origins {
            var crop = [Float](repeating: 0, count: n)
            for y in 0..<S { for x in 0..<S { crop[y * S + x] = cube[pos * Q * Q + (oy + y) * Q + ox + x] } }
            let corr = crop.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let j = jobs.count
            inputs.replaceSubrange((j * n3)..<((j + 1) * n3), with: LearnedDiskDetector.modelInputs(pattern: crop, probe: f.probe, correlation: corr.raw))
            smoothed.append(corr.smoothed); jobs.append((pos, oy, ox))
        } } }
        XCTAssertLessThanOrEqual(jobs.count, learned.batch)
        let heat = try await learned.heatmaps(inputs: inputs)
        var perPosition = [[[BraggPeak]]](repeating: [], count: positions)
        for (j, job) in jobs.enumerated() {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(j * n)..<((j + 1) * n)]), threshold: e.threshold) }
            var peaks = det.refine(candidates: cands, smoothedCorrelation: smoothed[j], params: p)
            for i in peaks.indices { peaks[i].x += Float(job.ox); peaks[i].y += Float(job.oy) }
            perPosition[job.pos].append(peaks)
        }
        let expected = perPosition.map { LearnedDiskDetector.mergeWindows($0, params: p) }
        // the tiled scan
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        let d = DatasetDescriptor(filePath: "/tmp/gateB.h5", datasetPath: "/d", shape: [ry, rx, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let centre = (x: Float(e.probe_centre[1]) + Float(pr0), y: Float(e.probe_centre[0]) + Float(pr0))
        let maybe = await learned.detectAll(
            cube: buffer, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probe),
            probeCentre: centre, probeRadius: Float(e.probe_radius), params: p, threshold: e.threshold)
        let out = try XCTUnwrap(maybe)
        XCTAssertEqual(out.peaks.count, positions)
        XCTAssertEqual(out.detectionProvenance["learned_windows"], "2x2")
        var countMismatches = 0, misses = 0, total = 0, worst: Float = 0, closePairs = 0
        for pos in 0..<positions {
            let want = expected[pos], got = out.peaks[pos]
            if want.count != got.count { countMismatches += 1 }
            for w in want {
                total += 1
                let dmin = got.map { hypot($0.x - w.x, $0.y - w.y) }.min() ?? .infinity
                if dmin > 0.05 { misses += 1 }
                worst = max(worst, dmin.isFinite ? dmin : 99)
            }
            for i in got.indices { for j in got.indices where j > i {
                if hypot(got[i].x - got[j].x, got[i].y - got[j].y) < p.minPeakSpacing { closePairs += 1 }
            } }
        }
        XCTAssertGreaterThan(total, 50, "the reference must hold enough peaks to mean anything")
        XCTAssertEqual(countMismatches, 0, "peak counts differ from the per-window direct path at \(countMismatches)/\(positions) positions")
        XCTAssertEqual(misses, 0, "\(misses)/\(total) reference peaks not within 0.05 px; worst \(worst)")
        XCTAssertEqual(closePairs, 0, "\(closePairs) accepted pairs closer than minPeakSpacing — the window merge left duplicates")
    }

    // MARK: R4b — tiling reaches windows the old single centred crop could not

    /// A 256-px detector: `windowOrigins` grids each axis into 3 windows (⌈(256−24)/(128−24)⌉
    /// = 3) at origins 0, 64, 128. One fixture pattern sits in the TOP-LEFT window's exact
    /// footprint, a different one in the BOTTOM-RIGHT window's exact footprint (both
    /// window-aligned — no boundary interpolation to account for), zeros elsewhere. Before
    /// tiling, the single probe-centred crop reached only the middle of a detector this
    /// size — neither corner was ever proposed. Expect the union of both patterns'
    /// direct-path peaks, each within 0.05 px of its shifted position, and no duplicate
    /// from the windows that legitimately see parts of both blocks (window (64, 64) sees a
    /// corner of each).
    @available(macOS 27, *)
    func testTiledWindowsReachTheWholeDetector() async throws {
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
        var direct: [[BraggPeak]] = []
        for i in 0..<e.count {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(i * n)..<((i + 1) * n)]), threshold: e.threshold) }
            direct.append(det.refine(candidates: cands, smoothedCorrelation: smoothed[i], params: p))
        }

        let Q = 256, ry = 1, rx = 2, positions = ry * rx
        let topLeft = (row0: 0, col0: 0), bottomRight = (row0: Q - S, col0: Q - S)
        var cube = [Float](repeating: 0, count: positions * Q * Q)
        for pos in 0..<positions {
            let patA = f.patterns[pos % 13], patB = f.patterns[(pos + 5) % 16]
            for y in 0..<S { for x in 0..<S {
                cube[pos * Q * Q + (topLeft.row0 + y) * Q + topLeft.col0 + x] = patA[y * S + x]
                cube[pos * Q * Q + (bottomRight.row0 + y) * Q + bottomRight.col0 + x] = patB[y * S + x]
            } }
        }
        // the probe only needs to be real where the kernel is actually cropped from
        // (the top-left block, where `probeCentre` below lands): the kernel is one crop
        // shared by every window, translation-invariant, per `detectAll`'s contract.
        var probe = [Float](repeating: 0, count: Q * Q)
        for y in 0..<S { for x in 0..<S { probe[(topLeft.row0 + y) * Q + topLeft.col0 + x] = f.probe[y * S + x] } }
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        let d = DatasetDescriptor(filePath: "/tmp/gateB-tiled.h5", datasetPath: "/d", shape: [ry, rx, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let centre = (x: Float(e.probe_centre[1]), y: Float(e.probe_centre[0]))
        let maybe = await learned.detectAll(
            cube: buffer, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probe),
            probeCentre: centre, probeRadius: Float(e.probe_radius), params: p, threshold: e.threshold)
        let out = try XCTUnwrap(maybe)
        XCTAssertEqual(out.peaks.count, positions)
        XCTAssertEqual(out.detectionProvenance["learned_windows"], "3x3", "256 px over 128 px windows, overlap 24 px: ⌈(256−24)/(128−24)⌉ = 3 windows per axis")

        var positionMisses = 0, total = 0, worst: Float = 0
        for pos in 0..<positions {
            let patA = pos % 13, patB = (pos + 5) % 16
            let expected = direct[patA].map { (x: $0.x + Float(topLeft.col0), y: $0.y + Float(topLeft.row0)) }
                + direct[patB].map { (x: $0.x + Float(bottomRight.col0), y: $0.y + Float(bottomRight.row0)) }
            let got = out.peaks[pos]
            for w in expected {
                total += 1
                let dmin = got.map { hypot($0.x - w.x, $0.y - w.y) }.min() ?? .infinity
                if dmin > 0.05 { positionMisses += 1 }
                worst = max(worst, dmin.isFinite ? dmin : 99)
            }
            // no duplicates: every kept peak is at or beyond minPeakSpacing from every other
            for i in got.indices { for j in got.indices where j > i {
                let sep = hypot(got[i].x - got[j].x, got[i].y - got[j].y)
                XCTAssertGreaterThanOrEqual(sep, p.minPeakSpacing, "position \(pos): peaks \(i) and \(j) are \(sep) px apart, closer than minPeakSpacing \(p.minPeakSpacing) — a duplicate from window overlap")
            } }
        }
        XCTAssertEqual(positionMisses, 0, "tiled positions: \(positionMisses)/\(total) direct-path peaks (from both placed patterns) not within 0.05 px of their shifted position; worst \(worst)")
    }
}
