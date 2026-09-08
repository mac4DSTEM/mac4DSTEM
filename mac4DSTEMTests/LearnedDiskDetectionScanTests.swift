//
//  LearnedDiskDetectionScanTests.swift
//  Step 4 slice 2 (C7, 2026-09-08, Core ML): the disagreement map, the
//  `DetectorClass` provenance IDs, and the streamed learned orchestration
//  (`LearnedDiskDetector.detectAll(data:…)`) checked against the resident
//  path on the same cube — and the resident path, on the NATIVE 128-px
//  fixture cube, against Python's accepted peaks shifted back from the
//  256-px frame (the pad-or-crop rule end to end).
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

/// An in-memory `FourDDataSource` over a fixed list of scan-position patterns
/// (row-major), for driving `FourDArray`/`TilePrefetcher` without a file —
/// the same shape of fixture `TiledDiskDetectionErrorTests.FailingTileSource`
/// uses, but returning real pixels instead of zeros.
private actor FixturePatternSource: FourDDataSource {
    private let shape: [Int]
    private let patterns: [[Float]]

    init(scanHeight: Int, scanWidth: Int, qy: Int, qx: Int, patterns: [[Float]]) {
        precondition(patterns.count == scanHeight * scanWidth)
        self.shape = [scanHeight, scanWidth, qy, qx]
        self.patterns = patterns
    }

    private var qy: Int { shape[2] }
    private var qx: Int { shape[3] }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(
            filePath: "/synthetic/fixture-source.h5", datasetPath: "/data",
            shape: shape, dtypeDescription: "float32", chunkShape: nil
        )
    }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        patterns[ry * view.descriptor.rx + rx]
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var out = [Float]()
        out.reserveCapacity(view.descriptor.rx * qy * qx)
        for rx in 0..<view.descriptor.rx {
            out.append(contentsOf: patterns[ry * view.descriptor.rx + rx])
        }
        return out
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels = [Float]()
        pixels.reserveCapacity(yRange.count * view.descriptor.rx * qy * qx)
        for ry in yRange {
            pixels.append(contentsOf: try readScanRow(view, ry: ry))
        }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: qy, detectorWidth: qx, pixels: pixels
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class LearnedDiskDetectionScanTests: XCTestCase {

    // MARK: DiskDisagreement.countDifferenceMap

    /// Hand-built vectors on a 2-row, 3-column scan (row-major position order
    /// 0…5). `learned − classical` at each position is, IN POSITION ORDER,
    /// `[2, −3, 5, 0, −1, 1]` — deliberately NOT already sorted, so a bug that
    /// takes `min`/`max` off the unsorted array (instead of sorting first)
    /// reads the wrong values (first/last of the position order: 2 and 1,
    /// instead of the true −3 and 5). One position ties (index 3: 4 − 4 = 0),
    /// so `differing` (5) is strictly less than `positions` (6), and the
    /// median lands on the even-count average-of-two-middles branch (sorted
    /// differences −3,−1,0,1,2,5 → the middle pair is 0 and 1 → 0.5, which a
    /// mutation using the odd-count "middle element" formula would report as
    /// the wrong value 1).
    func testCountDifferenceMap() throws {
        func vectors(counts: [Int], scanWidth: Int, scanHeight: Int) -> BraggVectors {
            let peaks = counts.map { c in (0..<c).map { i in BraggPeak(x: Float(i), y: Float(i), intensity: 1) } }
            return BraggVectors(scanWidth: scanWidth, scanHeight: scanHeight, peaks: peaks)
        }
        // classical, learned  ->  learned - classical
        //   3,  5              ->   2
        //   5,  2              ->  -3
        //   0,  5              ->   5
        //   4,  4              ->   0
        //   3,  2              ->  -1
        //   2,  3              ->   1
        let classical = vectors(counts: [3, 5, 0, 4, 3, 2], scanWidth: 3, scanHeight: 2)
        let learned = vectors(counts: [5, 2, 5, 4, 2, 3], scanWidth: 3, scanHeight: 2)

        let result = try XCTUnwrap(DiskDisagreement.countDifferenceMap(classical: classical, learned: learned))
        XCTAssertEqual(result.image.width, 3)
        XCTAssertEqual(result.image.height, 2)
        XCTAssertEqual(result.image.pixels, [2, -3, 5, 0, -1, 1].map(Float.init))
        XCTAssertEqual(result.summary, DiskDisagreement.Summary(
            positions: 6, differing: 5, classicalPeaks: 17, learnedPeaks: 21,
            minDifference: -3, medianDifference: 0.5, maxDifference: 5
        ))

        // Same total peak count (6 zero-length lists either way) but a
        // TRANSPOSED shape — isolates the scanWidth/scanHeight guard from the
        // peaks.count guard, which a mismatch built from different counts
        // would not do (that would be refused by the count check alone even
        // if the dimension check were missing).
        let mismatched = vectors(counts: [0, 0, 0, 0, 0, 0], scanWidth: 2, scanHeight: 3)
        XCTAssertNil(DiskDisagreement.countDifferenceMap(classical: classical, learned: mismatched))
    }

    // MARK: DetectorClass

    /// C7 session 2: both classes name themselves, so a map's provenance row
    /// never has to infer "classical" from an absent key.
    func testClassicalDetectionProvenanceNamesItsClass() throws {
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: 32, qx: 32))
        XCTAssertEqual(DiskDetectionParams().provenance(kernel: kernel, qy: 32, qx: 32)["detector_class"], "classical")
    }

    func testDetectorClassProvenanceIDs() {
        XCTAssertEqual(DetectorClass.classical.provenanceID, "classical")
        XCTAssertEqual(DetectorClass.learned.provenanceID, "learned")
    }

    // MARK: Streamed scan vs. the resident path

    /// The fixture's 16 patterns as a 4×4 scan, run through
    /// `LearnedDiskDetector.detectAll(data:…, maximumTileRows: 1)` (four
    /// one-row tiles, four positions each) and compared against the SAME
    /// cube's resident `detectAll(cube:…)` call (one shot, no tiling). The
    /// detector is exactly `inputSize` (128) square, so the crop origin is
    /// (0, 0) on both paths — this test is about the tiling and
    /// concatenation, not the crop.
    func testTiledLearnedScanEqualsResident() async throws {
        let f = try LearnedSwiftFixture.load()
        let e = f.expected
        let S = f.native
        let learned = try await LearnedSwiftFixture.loadDetector()

        let p = f.params()
        let scanHeight = 4, scanWidth = 4
        let positions = scanHeight * scanWidth
        XCTAssertEqual(f.patterns.count, positions, "fixture must supply exactly one pattern per scan position")

        let source = FixturePatternSource(scanHeight: scanHeight, scanWidth: scanWidth, qy: S, qx: S, patterns: f.patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)

        let probeCentre = f.probeCentre
        let probeRadius = f.probeRadius
        let probePattern = DiffractionPattern(qy: S, qx: S, pixels: f.probe)

        let streamed = try await learned.detectAll(
            data: data, descriptor: descriptor, probe: probePattern,
            probeCentre: probeCentre, probeRadius: probeRadius,
            params: p, threshold: e.threshold, maximumTileRows: 1
        )
        let streamedVectors = try XCTUnwrap(streamed, "the streamed run must not be nil when Core ML loaded above")

        var cube = [Float](repeating: 0, count: positions * S * S)
        for pos in 0..<positions {
            for i in 0..<(S * S) { cube[pos * S * S + i] = f.patterns[pos][i] }
        }
        let buffer = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: cube, length: cube.count * MemoryLayout<Float>.stride))
        let resident = await learned.detectAll(
            cube: buffer, descriptor: descriptor, probe: probePattern,
            probeCentre: probeCentre, probeRadius: probeRadius,
            params: p, threshold: e.threshold
        )
        let residentVectors = try XCTUnwrap(resident, "the resident run must not be nil on the same inputs")

        XCTAssertEqual(streamedVectors.peaks.count, positions)
        XCTAssertEqual(streamedVectors.detectionProvenance["detector_class"], "learned")
        XCTAssertEqual(streamedVectors.detectionProvenance["learned_runtime"], "coreml")
        XCTAssertEqual(streamedVectors.detectionProvenance["learned_windows"], "1x1", "a 128-px detector is one padded window")
        XCTAssertEqual(streamedVectors.detectionProvenance["learned_crop_origin_x"], String(e.fit_offset[1]))
        XCTAssertEqual(streamedVectors.detectionProvenance["learned_crop_origin_y"], String(e.fit_offset[0]))
        XCTAssertEqual(streamedVectors.detectionProvenance["learned_model_sha256"], e.asset_sha256)

        var countMismatches = 0, positionMisses = 0, total = 0, worst: Float = 0
        for pos in 0..<positions {
            let want = residentVectors.peaks[pos], got = streamedVectors.peaks[pos]
            if want.count != got.count { countMismatches += 1 }
            for w in want {
                total += 1
                let dmin = got.map { hypot($0.x - w.x, $0.y - w.y) }.min() ?? .infinity
                if dmin > 1e-4 { positionMisses += 1 }
                worst = max(worst, dmin.isFinite ? dmin : 99)
            }
        }
        XCTAssertEqual(countMismatches, 0, "tiled peak counts differ from the resident path at \(countMismatches)/\(positions) positions")
        XCTAssertEqual(positionMisses, 0, "tiled positions: \(positionMisses)/\(total) not within 1e-4 px of the resident path; worst \(worst)")

        // The pad rule end to end: the resident path on the NATIVE cube returns peaks in
        // the native frame; Python's accepted peaks are in the 256 frame, so they must
        // agree once shifted back by the fit offset (row0, col0), both negative here.
        let o = LearnedDiskDetector.fitOffset(probeCentre: probeCentre)
        var refCountMatches = 0, refHits = 0, refTotal = 0, refWorst: Float = 0
        for pos in 0..<positions {
            let got = residentVectors.peaks[pos]
            let want = e.patterns[pos].accepted.map { (x: Float($0[1]) + Float(o.col0), y: Float($0[0]) + Float(o.row0)) }
            if got.count == want.count { refCountMatches += 1 }
            for w in want {
                refTotal += 1
                let dmin = got.map { hypot($0.x - w.x, $0.y - w.y) }.min() ?? .infinity
                if dmin <= 0.05 { refHits += 1 }
                refWorst = max(refWorst, dmin.isFinite ? dmin : 99)
            }
            for g in got {
                XCTAssertTrue(g.x >= 0 && g.x < Float(S) && g.y >= 0 && g.y < Float(S), "position \(pos): a peak at (\(g.x), \(g.y)) lies outside the native 128-px detector — the shift back from the padded frame is wrong")
            }
        }
        XCTAssertGreaterThanOrEqual(refCountMatches, positions - 1, "native-frame counts equal Python's in \(refCountMatches)/\(positions) positions")
        XCTAssertGreaterThanOrEqual(Double(refHits) / Double(refTotal), 0.98, "native-frame positions within 0.05 px of Python's shifted peaks: \(refHits)/\(refTotal), worst \(refWorst)")
    }

    /// Gate D, A2 (fix-a/gateD-A2.md): the streamed learned run must not
    /// execute on the main thread. The owner's drive froze the whole app for
    /// minutes with `04-mainthread-sample.txt` showing 847/847
    /// `com.apple.main-thread` samples inside `detectAll` → `dispatch_apply`,
    /// even though `AppState.swift:4924` already wraps the call in
    /// `Task.detached` — because the extension member had no `nonisolated`
    /// and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` made it `@MainActor`,
    /// so the detached task hopped straight back.
    ///
    /// The discriminator: call it from `Task.detached` — the global concurrent
    /// executor — and record the thread its own `progress:` callback runs on.
    /// A nonisolated async callee inherits that caller's executor (SE-0461),
    /// so a correct build never sees the main thread here; a `@MainActor`
    /// callee always does.
    func testLearnedFullScanRunsOffTheMainThread() async throws {
        let f = try LearnedSwiftFixture.load()
        let e = f.expected
        let S = f.native
        let learned = try await LearnedSwiftFixture.loadDetector()

        let p = f.params()
        let scanHeight = 4, scanWidth = 4
        let source = FixturePatternSource(scanHeight: scanHeight, scanWidth: scanWidth, qy: S, qx: S, patterns: f.patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)

        let probeCentre = f.probeCentre
        let probeRadius = f.probeRadius
        let probePattern = DiffractionPattern(qy: S, qx: S, pixels: f.probe)
        let threshold = e.threshold

        let witness = ThreadWitness()
        let vectors = try await Task.detached(priority: .userInitiated) {
            try await learned.detectAll(
                data: data, descriptor: descriptor, probe: probePattern,
                probeCentre: probeCentre, probeRadius: probeRadius,
                params: p, threshold: threshold, maximumTileRows: 1,
                progress: { _ in witness.record(main: Thread.isMainThread) }
            )
        }.value

        XCTAssertNotNil(vectors, "the run must complete — this test is about the thread, not the result")
        XCTAssertGreaterThan(witness.calls, 0, "no progress callback fired, so nothing was observed")
        XCTAssertFalse(
            witness.sawMainThread,
            "the learned full scan ran its progress callback on the main thread "
            + "(\(witness.mainCalls) of \(witness.calls) calls) even from Task.detached — "
            + "the detached task hopped back onto the main actor"
        )
    }
}

/// Lock-guarded tally of which thread a `@Sendable` callback ran on.
/// `@unchecked Sendable` for the same reason `ProgressCoalescer` is: the lock
/// is the invariant.
nonisolated private final class ThreadWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _mainCalls = 0
    func record(main: Bool) {
        lock.withLock { _calls += 1; if main { _mainCalls += 1 } }
    }
    var calls: Int { lock.withLock { _calls } }
    var mainCalls: Int { lock.withLock { _mainCalls } }
    var sawMainThread: Bool { lock.withLock { _mainCalls > 0 } }
}
