//
//  LearnedDiskDetectorTests.swift
//  The learned disk-candidate stage against its Python reference (v3-plan §3a step 4, 2026-09-07).
//
//  The fixture is tools/disk-detector/fixture/swift/, written by fixture/write_swift_fixture.py
//  from the committed synthetic fixture and the committed asset: the 16 patterns, the drawn probe,
//  Python's model inputs for two patterns, and per pattern the raw peak picks and the accepted
//  refined peaks (evaluate.pick / refine / accept). Everything here must reproduce them.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class LearnedDiskDetectorTests: XCTestCase {

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fixtureDir = repo.appendingPathComponent("tools/disk-detector/fixture/swift")
    private static let assetURL = repo.appendingPathComponent("Models/DiskDetector/disk-detector-heatmap-b32.aimodel")
    private static let assetMeta = repo.appendingPathComponent("Models/DiskDetector/disk-detector-heatmap-b32.json")
    private static let S = 128

    private struct Expected: Decodable {
        struct Settings: Decodable { let minPeakSpacing: Float; let edgeBoundary: Int; let sigma_cc: Float; let maxNumPeaks: Int }
        struct Pattern: Decodable { let picks: [[Double]]; let accepted: [[Double]] }
        let count: Int; let size: Int; let probe_centre: [Double]; let probe_radius: Double
        let threshold: Float; let settings: Settings; let inputs_ref_indices: [Int]; let patterns: [Pattern]
    }

    private struct Fixture {
        let expected: Expected
        let patterns: [[Float]]      // 16 × (S*S)
        let probe: [Float]
        let inputsRef: [[Float16]]   // 2 × (3*S*S)
    }

    private func loadFixture() throws -> Fixture {
        let dir = Self.fixtureDir
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        let n = Self.S * Self.S
        let u16 = try Data(contentsOf: dir.appendingPathComponent("patterns.u16"))
        XCTAssertEqual(u16.count, expected.count * n * 2)
        let raw: [UInt16] = u16.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        let patterns = (0..<expected.count).map { i in raw[(i * n)..<((i + 1) * n)].map { Float(UInt16(littleEndian: $0)) } }
        let probe: [Float] = try Data(contentsOf: dir.appendingPathComponent("probe.f32")).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let refs: [Float16] = try Data(contentsOf: dir.appendingPathComponent("inputs-ref.f16")).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        XCTAssertEqual(refs.count, expected.inputs_ref_indices.count * 3 * n)
        let inputsRef = (0..<expected.inputs_ref_indices.count).map { Array(refs[($0 * 3 * n)..<(($0 + 1) * 3 * n)]) }
        return Fixture(expected: expected, patterns: patterns, probe: probe, inputsRef: inputsRef)
    }

    private func params(_ e: Expected) -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.sigmaCC = e.settings.sigma_cc; p.subpixel = .poly
        p.minPeakSpacing = e.settings.minPeakSpacing; p.edgeBoundary = e.settings.edgeBoundary
        p.minRelativeIntensity = 0.05; p.maxNumPeaks = e.settings.maxNumPeaks
        return p
    }

    private func kernel(_ f: Fixture) throws -> ProbeKernel {
        let e = f.expected
        // Python (row, col) = Swift (y, x)
        return try XCTUnwrap(ProbeKernel.flat(
            pattern: DiffractionPattern(qy: Self.S, qx: Self.S, pixels: f.probe),
            originX: Float(e.probe_centre[1]), originY: Float(e.probe_centre[0]),
            radius: Float(e.probe_radius), source: .measured))
    }

    // MARK: 1. The normalisation equals simulate.model_inputs

    @available(macOS 27, *)
    func testModelInputsMatchPythonReference() throws {
        let f = try loadFixture()
        let det = try XCTUnwrap(DiskDetector(kernel: try kernel(f)))
        let p = params(f.expected)
        for (k, idx) in f.expected.inputs_ref_indices.enumerated() {
            let corr = f.patterns[idx].withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let mine = LearnedDiskDetector.modelInputs(pattern: f.patterns[idx], probe: f.probe, correlation: corr.raw)
            var maxDiff: Float = 0
            for i in mine.indices { maxDiff = max(maxDiff, abs(Float(mine[i]) - Float(f.inputsRef[k][i]))) }
            // float16 quantisation of two float pipelines (float32 here, float64 in numpy): one ulp near 1 is ~1e-3
            XCTAssertLessThan(maxDiff, 2e-3, "pattern \(idx): model inputs differ from simulate.model_inputs by \(maxDiff)")
        }
    }

    // MARK: 2. The committed asset is the one the export record names

    @available(macOS 27, *)
    func testCommittedAssetHashMatchesItsRecord() throws {
        struct Meta: Decodable { let sha256: String; let function: String }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: Self.assetMeta))
        XCTAssertEqual(try LearnedDiskDetector.sha256(ofAsset: Self.assetURL), meta.sha256)
        XCTAssertEqual(meta.function, "heatmap")
    }

    // MARK: 3. The whole learned path reproduces Python's picks and accepted peaks

    @available(macOS 27, *)
    func testLearnedPathMatchesPythonReference() async throws {
        guard FileManager.default.fileExists(atPath: Self.assetURL.path) else { throw XCTSkip("no committed asset") }
        let f = try loadFixture()
        let e = f.expected
        let det = try XCTUnwrap(DiskDetector(kernel: try kernel(f)))
        let p = params(e)
        let learned: LearnedDiskDetector
        do { learned = try await LearnedDiskDetector.load(assetURL: Self.assetURL) }
        catch { throw XCTSkip("Core AI could not load the asset here: \(error)") }
        let n = Self.S * Self.S, n3 = 3 * n
        XCTAssertEqual(learned.batch, 32)
        var inputs = [Float16](repeating: 0, count: learned.batch * n3)
        var smoothed: [[Float]] = []
        for i in 0..<e.count {
            let corr = f.patterns[i].withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: p) }
            let mi = LearnedDiskDetector.modelInputs(pattern: f.patterns[i], probe: f.probe, correlation: corr.raw)
            inputs.replaceSubrange((i * n3)..<((i + 1) * n3), with: mi)
            smoothed.append(corr.smoothed)
        }
        let heat = try await learned.heatmaps(inputs: inputs)
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
        // The same asset through the same OS runtime: the heatmaps are the same numbers, so the
        // picks and the accepted peaks are the same up to float32-vs-float64 refinement rounding.
        XCTAssertGreaterThanOrEqual(Double(pickHits) / Double(pickTotal), 0.98, "raw picks: \(pickHits)/\(pickTotal) reproduce Python's")
        // and no extras: a loosened maximum test admits ridge pixels that suppression would hide (mutation M2, 2026-09-07)
        XCTAssertLessThanOrEqual(Double(pickMine - pickHits) / Double(pickTotal), 0.02, "raw picks: \(pickMine - pickHits) extra beyond Python's \(pickTotal)")
        XCTAssertGreaterThanOrEqual(acceptedCountMatches, e.count - 1, "accepted counts equal Python's in \(acceptedCountMatches)/\(e.count) patterns")
        XCTAssertGreaterThanOrEqual(Double(positionHits) / Double(positionTotal), 0.98,
                                    "accepted positions within 0.05 px of Python's: \(positionHits)/\(positionTotal), worst \(worst)")
    }
}
