//
//  LearnedDiskDetectionScanTests.swift
//  Step 4 slice 2: the disagreement map (any platform), the `DetectorClass`
//  provenance IDs, and the streamed learned orchestration
//  (`LearnedDiskDetector.detectAll(data:…)`, macOS 27+, Core AI) checked
//  against the resident path on the same cube.
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

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fixtureDir = repo.appendingPathComponent("tools/disk-detector/fixture/swift")
    private static let assetURL = repo.appendingPathComponent("Models/DiskDetector/disk-detector-heatmap-b32.aimodel")
    private static let S = 128

    private struct Expected: Decodable {
        struct Settings: Decodable { let minPeakSpacing: Float; let edgeBoundary: Int; let sigma_cc: Float; let maxNumPeaks: Int }
        let count: Int; let probe_centre: [Double]; let probe_radius: Double
        let threshold: Float; let settings: Settings
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
    @available(macOS 27, *)
    func testTiledLearnedScanEqualsResident() async throws {
        let f = try loadFixture()
        let e = f.expected
        let S = Self.S
        let learned: LearnedDiskDetector
        do { learned = try await LearnedDiskDetector.load(assetURL: Self.assetURL) }
        catch { throw XCTSkip("no Core AI: \(error)") }

        let p = params(e)
        let scanHeight = 4, scanWidth = 4
        let positions = scanHeight * scanWidth
        XCTAssertEqual(f.patterns.count, positions, "fixture must supply exactly one pattern per scan position")

        let source = FixturePatternSource(scanHeight: scanHeight, scanWidth: scanWidth, qy: S, qx: S, patterns: f.patterns)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)

        let probeCentre = (x: Float(e.probe_centre[1]), y: Float(e.probe_centre[0]))
        let probeRadius = Float(e.probe_radius)
        let probePattern = DiffractionPattern(qy: S, qx: S, pixels: f.probe)

        let streamed = try await learned.detectAll(
            data: data, descriptor: descriptor, probe: probePattern,
            probeCentre: probeCentre, probeRadius: probeRadius,
            params: p, threshold: e.threshold, maximumTileRows: 1
        )
        let streamedVectors = try XCTUnwrap(streamed, "the streamed run must not be nil when Core AI loaded above")

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
    }
}
