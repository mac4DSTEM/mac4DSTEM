//
//  LearnedDiskDetectorGateBTests.swift
//  The Gate B refuter's assertions for step 4 slice 1 (2026-09-07), adopted after they were re-broken,
//  ported to the 256-px Core ML package (C7, 2026-09-08): the committed fixture test could not see any
//  of this. R1/R2 exercise `refine` alone (the fixture never drops a candidate by spacing and never reaches
//  the cap), R3 is py4DSTEM's precondition that the parabola is evaluated only at a local maximum (before
//  the fix, 10 of 255 fixture peaks were fabricated on flanks and the Python reference agreed), R4 exercises
//  `detectAll` on a windowed, multi-batch cube (no other test calls it that way: window origins, batch
//  base, row/col were each mutated and caught), R4b that windows reach a detector's corners.
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

final class LearnedDiskDetectorGateBTests: XCTestCase {

    private func unitParams() -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.sigmaCC = 2; p.subpixel = .poly; p.minPeakSpacing = 8; p.edgeBoundary = 6; p.maxNumPeaks = 70
        return p
    }

    /// A smoothed-correlation stand-in: a sum of Gaussians on the native grid.
    private func surface(size S: Int, peaks: [(x: Float, y: Float, amp: Float)], sigma: Float = 1.5) -> [Float] {
        var ar = [Float](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S {
            var v: Float = 0
            for p in peaks { let dx = Float(x) - p.x, dy = Float(y) - p.y; v += p.amp * exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)) }
            ar[y * S + x] = v
        } }
        return ar
    }

    // MARK: R1 — non-maximum suppression ranks by the NET score (the fixture never exercises NMS: 0 drops)

    func testRefineSuppressesByNetScoreNotByCorrelation() throws {
        let f = try LearnedSwiftFixture.load(); let det = try f.nativeDetector()
        // the brighter correlation peak (A) has the LOWER net score; B, 5 px away (< spacing 8), the higher
        let ar = surface(size: f.native, peaks: [(60, 60, 1.0), (65, 60, 0.6)])
        let cands = [DiskDetector.Candidate(x: 60, y: 60, score: 0.91), DiskDetector.Candidate(x: 65, y: 60, score: 0.95)]
        let kept = det.refine(candidates: cands, smoothedCorrelation: ar, params: unitParams())
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.x ?? -1, 65, accuracy: 0.3, "NMS must keep the higher NET score (B at x=65), not the brighter correlation peak")
    }

    // MARK: R2 — the cap (Python's `accept` has no cap; the fixture never exceeds 24)

    func testRefineCapsAtMaxNumPeaks() throws {
        let f = try LearnedSwiftFixture.load(); let det = try f.nativeDetector()
        var peaks: [(x: Float, y: Float, amp: Float)] = []
        var cands: [DiskDetector.Candidate] = []
        for i in 1...10 { for j in 1...10 { peaks.append((Float(i * 10), Float(j * 10), 1.0)); cands.append(.init(x: i * 10, y: j * 10, score: 0.95)) } }
        let kept = det.refine(candidates: cands, smoothedCorrelation: surface(size: f.native, peaks: peaks), params: unitParams())
        XCTAssertEqual(kept.count, 70)
    }

    // MARK: R3 — py4DSTEM's precondition: the parabola is only ever evaluated AT a local maximum, so |shift| ≤ 0.5

    /// Minimal case: a candidate 6 px from the only correlation peak. The 5×5 snap window does not reach the
    /// peak, so the snapped pixel is on the flank, not a maximum; the unguarded parabola then extrapolates.
    func testRefineRejectsOrBoundsCandidatesWithNoCorrelationMaximumInReach() throws {
        let f = try LearnedSwiftFixture.load(); let det = try f.nativeDetector()
        let ar = surface(size: f.native, peaks: [(60, 60, 1.0)], sigma: 1.5)
        let kept = det.refine(candidates: [.init(x: 66, y: 60, score: 0.95)], smoothedCorrelation: ar, params: unitParams())
        for k in kept {
            XCTAssertLessThanOrEqual(hypot(k.x - 60, k.y - 60), 0.5, "accepted a peak at (\(k.x), \(k.y)) — no correlation maximum there (the only one is at 60,60)")
        }
    }

    /// The fixture, end to end: every accepted peak must lie within 0.75 px (half a pixel per axis) of an
    /// 8-neighbour local maximum of the smoothed correlation it was refined on.
    func testAcceptedPeaksSitOnCorrelationMaxima() async throws {
        let f = try LearnedSwiftFixture.load(); let e = f.expected; let det = try f.fittedDetector(); let p = f.params()
        let learned = try await LearnedSwiftFixture.loadDetector()
        let S = f.S, n = S * S
        let (inputs, smoothed) = f.batchInputs(det, batch: learned.batch)
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
        XCTAssertGreaterThan(accepted, 200, "the fixture must yield a real number of accepted peaks (295 in Python)")
        XCTAssertEqual(offMaximum, 0, "\(offMaximum) of \(accepted) accepted peaks are not at a correlation maximum (worst \(worst) px, patterns \(patternsHit.sorted()))")
    }

    // MARK: R3b — the frame rule, the window grid and the merge, pure functions (no Core ML needed)

    /// `windowOverlap`/`windowOrigins`/`mergeWindows` never touch the model. Checked against the
    /// formula in docs/v3-plan.md §3a and the 2026-09-08 decision: `overlap = max(2·⌈r⌉+2, 24)`;
    /// `q < 256` is ONE window at `simulate.fit_offset` (padding, possibly negative, never clamped),
    /// `q == 256` is origin 0, `q > 256` is `n = ⌈(q−overlap)/(256−overlap)⌉ ≥ 2` windows spread evenly
    /// across `0...(q−256)`.
    func testWindowGridFormula() {
        let S = LearnedDiskDetector.inputSize
        XCTAssertEqual(S, 256)
        // overlap: one disk diameter, floored at 24 px
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 10), 24, "2·⌈10⌉+2 = 22, below the 24 px floor")
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 20), 42, "2·⌈20⌉+2 = 42, above the floor")
        XCTAssertEqual(LearnedDiskDetector.windowOverlap(probeRadius: 0), 24)

        // below the frame: the fit offset, Python's round-half-to-even, no clamp
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 128, probeCentreOnAxis: 63.6, overlap: 24), [-64], "the fixture: round(63.6) − 128")
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 250, probeCentreOnAxis: 124.76, overlap: 24), [-3], "the bullseye cube: round(124.76) − 128 = −3, three rows of padding")
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 128, probeCentreOnAxis: 64.5, overlap: 24), [-64], "64.5 rounds to 64 (half to even), as int(round(64.5)) does in Python")
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 128, probeCentreOnAxis: 20, overlap: 24), [-108], "an off-centre probe: the frame hangs far over the top edge; nothing clamps it")
        XCTAssertEqual(LearnedDiskDetector.fitOffset(probeCentre: (x: 64.3, y: 63.6)).row0, -64)
        XCTAssertEqual(LearnedDiskDetector.fitOffset(probeCentre: (x: 64.3, y: 63.6)).col0, -64)

        // exactly the frame: the detector itself, regardless of centre (evaluate.py fits only when the size differs)
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 256, probeCentreOnAxis: 100, overlap: 24), [0])

        // above the frame: windows. q == 288, overlap 24: n = max(⌈264/232⌉, 2) = 2, origins across 0...32
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 288, probeCentreOnAxis: 144, overlap: 24), [0, 32])
        // q == 257: the smallest windowed detector still gets two windows
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 257, probeCentreOnAxis: 128, overlap: 24), [0, 1])
        // q == 512, overlap 24: n = ⌈488/232⌉ = 3, origins across 0...256
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 512, probeCentreOnAxis: 256, overlap: 24), [0, 128, 256])
        // q == 500, overlap 42: n = ⌈458/214⌉ = 3
        XCTAssertEqual(LearnedDiskDetector.windowOrigins(q: 500, probeCentreOnAxis: 250, overlap: 42), [0, 122, 244])
    }

    /// `window(of:…)`: the copy that is both crop and pad. A 4×4 image into the 256 frame at
    /// origin (−2, −1): pixel (r, c) lands at (r + 2, c + 1); everything else is zero. And a
    /// crop from a larger image at a positive origin.
    func testWindowCopyIsCropAndPad() {
        let S = LearnedDiskDetector.inputSize
        let img: [Float] = (0..<16).map(Float.init)
        var out = [Float](repeating: 7, count: S * S)   // pre-filled: the copy must zero what it does not cover
        img.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: 4, qx: 4, row0: -2, col0: -1, into: &out) }
        XCTAssertEqual(out.reduce(0, +), img.reduce(0, +), "padding adds nothing")
        for r in 0..<4 { for c in 0..<4 { XCTAssertEqual(out[(r + 2) * S + c + 1], img[r * 4 + c]) } }
        XCTAssertEqual(out[0], 0); XCTAssertEqual(out[(S - 1) * S + S - 1], 0)
        // a 300×300 ramp cropped at (30, 40): out[y][x] = ramp[30+y][40+x]
        let big: [Float] = (0..<(300 * 300)).map { Float($0 % 300) + 1000 * Float($0 / 300) }
        big.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: 300, qx: 300, row0: 30, col0: 40, into: &out) }
        XCTAssertEqual(out[0], 40 + 1000 * 30); XCTAssertEqual(out[(S - 1) * S + (S - 1)], Float(40 + S - 1) + 1000 * Float(30 + S - 1))
        // a crop whose frame hangs over the far edge: (100, 100) on a 300 image → columns/rows ≥ 200 are zero
        big.withUnsafeBufferPointer { LearnedDiskDetector.window(of: $0.baseAddress!, qy: 300, qx: 300, row0: 100, col0: 100, into: &out) }
        XCTAssertEqual(out[199], 299 + 1000 * 100); XCTAssertEqual(out[200], 0); XCTAssertEqual(out[200 * S], 0)
    }

    /// A synthetic three-window overlap at one scan position: window A and window B both
    /// see the SAME disk (a duplicate — the higher-intensity copy must survive), window C
    /// sees a disk nobody else does. Expect 2 peaks kept: the brighter duplicate and the
    /// unique one; capped further if `maxNumPeaks` is tight.
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

    /// A 488-px detector: overlap 24 px for this fixture's probe, so `windowOrigins` gives
    /// [0, 232] per axis. Four DIFFERENT fitted fixture frames sit at the four window origins, so
    /// every window sees its own frame plus a 24-px strip of each neighbour — what a real
    /// detector's windows see. The reference is the DIRECT path run on each window's actual
    /// 256-px content, shifted by the window origin and merged with `mergeWindows`: that is
    /// exactly what `detectAll` must compute, so the comparison is exact (0.05 px, equal
    /// counts) and isolates the tiling plumbing — job order, window origins, the shift back,
    /// the merge — from the net's own sensitivity to what lies in a window. (A first version
    /// compared against the ISOLATED patterns' peaks and lost 15 of 120: a U-Net's
    /// receptive field reaches well past the 24-px strip, so a neighbour's content moves
    /// borderline scores across the threshold. That is the model, not the tiling.)
    func testTiledWindowsEqualPerWindowDirectPathMerged() async throws {
        let f = try LearnedSwiftFixture.load(); let e = f.expected; let det = try f.fittedDetector()
        var p = f.params(); p.maxNumPeaks = 1000   // four frames per position exceed the 70 cap; the cap is R2's test
        let learned = try await LearnedSwiftFixture.loadDetector()
        let S = f.S, n = S * S, n3 = 3 * n
        let frames = f.patterns.map { f.fitted($0) }
        let probeFit = f.fitted(f.probe)
        let overlap = LearnedDiskDetector.windowOverlap(probeRadius: f.probeRadius)
        let Q = S + (S - overlap)                       // 488 for overlap 24: origins [0, 232]
        let origins = LearnedDiskDetector.windowOrigins(q: Q, probeCentreOnAxis: Float(Q) / 2, overlap: overlap)
        XCTAssertEqual(origins, [0, S - overlap])
        let placements = [(0, 0, 0), (0, S - overlap, 1), (S - overlap, 0, 2), (S - overlap, S - overlap, 3)]   // (row0, col0, frame)
        let ry = 1, rx = 2, positions = ry * rx
        var cube = [Float](repeating: 0, count: positions * Q * Q)
        for pos in 0..<positions {
            for (row0, col0, k) in placements {
                let a = frames[(k + 4 * pos) % 16]
                for y in 0..<S { for x in 0..<S { cube[pos * Q * Q + (row0 + y) * Q + col0 + x] = a[y * S + x] } }
            }
        }
        // the probe in the middle of the detector, like a real cube's; its 256-px crop is the fitted probe
        var probe = [Float](repeating: 0, count: Q * Q)
        let pr0 = (Q - S) / 2
        for y in 0..<S { for x in 0..<S { probe[(pr0 + y) * Q + pr0 + x] = probeFit[y * S + x] } }
        // the reference: the direct path on each window's actual content
        var inputs = [Float16](repeating: 0, count: learned.batch * n3)
        var smoothed: [[Float]] = []; var jobs: [(pos: Int, oy: Int, ox: Int)] = []
        for pos in 0..<positions { for oy in origins { for ox in origins {
            var crop = [Float](repeating: 0, count: n)
            for y in 0..<S { for x in 0..<S { crop[y * S + x] = cube[pos * Q * Q + (oy + y) * Q + ox + x] } }
            let corr = crop.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let j = jobs.count
            inputs.replaceSubrange((j * n3)..<((j + 1) * n3), with: LearnedDiskDetector.modelInputs(pattern: crop, probe: probeFit, correlation: corr.raw))
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
        let centre = (x: f.probeCentreFit.x + Float(pr0), y: f.probeCentreFit.y + Float(pr0))
        let maybe = await learned.detectAll(
            cube: buffer, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probe),
            probeCentre: centre, probeRadius: f.probeRadius, params: p, threshold: e.threshold)
        let out = try XCTUnwrap(maybe)
        XCTAssertEqual(out.peaks.count, positions)
        XCTAssertEqual(out.detectionProvenance["learned_windows"], "2x2")
        XCTAssertEqual(out.detectionProvenance["learned_window_origins"], "0,0;0,232;232,0;232,232")
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

    // MARK: R4b — windows reach the corners of a detector twice the frame

    /// A 512-px detector: `windowOrigins` grids each axis into 3 windows (⌈(512−24)/(256−24)⌉
    /// = 3) at origins 0, 128, 256. One fitted fixture frame sits in the TOP-LEFT window's exact
    /// footprint, a different one in the BOTTOM-RIGHT window's exact footprint (both
    /// window-aligned — no boundary interpolation to account for), zeros elsewhere. A single
    /// probe-centred crop would reach only the middle of a detector this size — neither corner
    /// would ever be proposed. Expect the union of both frames' direct-path peaks, each within
    /// 0.05 px of its shifted position, and no duplicate from the windows that legitimately
    /// see parts of both blocks (window (128, 128) sees a corner of each).
    func testTiledWindowsReachTheWholeDetector() async throws {
        let f = try LearnedSwiftFixture.load(); let e = f.expected; let det = try f.fittedDetector(); let p = f.params()
        let learned = try await LearnedSwiftFixture.loadDetector()
        let S = f.S, n = S * S
        let frames = f.patterns.map { f.fitted($0) }
        let probeFit = f.fitted(f.probe)
        let (inputs, smoothed) = f.batchInputs(det, batch: learned.batch)
        let heat = try await learned.heatmaps(inputs: inputs)
        var direct: [[BraggPeak]] = []
        for i in 0..<e.count {
            let cands = heat.withUnsafeBufferPointer { hb in
                LearnedDiskDetector.pickPeaks(heatmap: UnsafeBufferPointer(rebasing: hb[(i * n)..<((i + 1) * n)]), threshold: e.threshold) }
            direct.append(det.refine(candidates: cands, smoothedCorrelation: smoothed[i], params: p))
        }

        let Q = 2 * S, ry = 1, rx = 2, positions = ry * rx
        let topLeft = (row0: 0, col0: 0), bottomRight = (row0: Q - S, col0: Q - S)
        var cube = [Float](repeating: 0, count: positions * Q * Q)
        for pos in 0..<positions {
            let patA = frames[pos % 13], patB = frames[(pos + 5) % 16]
            for y in 0..<S { for x in 0..<S {
                cube[pos * Q * Q + (topLeft.row0 + y) * Q + topLeft.col0 + x] = patA[y * S + x]
                cube[pos * Q * Q + (bottomRight.row0 + y) * Q + bottomRight.col0 + x] = patB[y * S + x]
            } }
        }
        // the probe only needs to be real where the kernel is actually cropped from
        // (the top-left block, where `probeCentre` below lands): the kernel is one crop
        // shared by every window, translation-invariant, per `detectAll`'s contract.
        var probe = [Float](repeating: 0, count: Q * Q)
        for y in 0..<S { for x in 0..<S { probe[(topLeft.row0 + y) * Q + topLeft.col0 + x] = probeFit[y * S + x] } }
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        let d = DatasetDescriptor(filePath: "/tmp/gateB-tiled.h5", datasetPath: "/d", shape: [ry, rx, Q, Q], dtypeDescription: "float32", chunkShape: nil)
        let maybe = await learned.detectAll(
            cube: buffer, descriptor: d, probe: DiffractionPattern(qy: Q, qx: Q, pixels: probe),
            probeCentre: f.probeCentreFit, probeRadius: f.probeRadius, params: p, threshold: e.threshold)
        let out = try XCTUnwrap(maybe)
        XCTAssertEqual(out.peaks.count, positions)
        XCTAssertEqual(out.detectionProvenance["learned_windows"], "3x3", "512 px over 256 px windows, overlap 24 px: ⌈(512−24)/(256−24)⌉ = 3 windows per axis")

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
        XCTAssertGreaterThan(total, 30, "the reference must hold enough peaks to mean anything")
        XCTAssertEqual(positionMisses, 0, "tiled positions: \(positionMisses)/\(total) direct-path peaks (from both placed frames) not within 0.05 px of their shifted position; worst \(worst)")
    }
}
