//
//  TrainingDoseScaleTests.swift
//  Fine-tuning feeds the model the inputs inference feeds it (#301). On a detector covered by several 256-px windows,
//  inference scales a fractional pattern's dose once, from the whole native pattern (D098, `nativeCountScale`); the
//  training samples scaled each window from its own maximum, so fine-tuned weights saw another input distribution.
//

import XCTest
import DSTEMSession
import DSTEMTraining
import DSTEMCore

final class TrainingDoseScaleTests: XCTestCase {
    private let q = 512

    /// A fractional pattern (maximum <= 1): a weak spot inside the first window, the direct beam far from it.
    private func pattern(beam: Float, scale: Float = 1) -> DiffractionPattern {
        var p = [Float](repeating: 0.001 * scale, count: q * q)
        // A disk with a dimmer rim: three grey levels, so log1p of the scaled counts depends on the scale.
        func disk(_ cy: Int, _ cx: Int, _ v: Float) {
            for y in (cy - 4)...(cy + 4) {
                for x in (cx - 4)...(cx + 4) {
                    let r2 = (y - cy) * (y - cy) + (x - cx) * (x - cx)
                    if r2 <= 16 { p[y * q + x] = (r2 <= 4 ? v : v / 4) * scale }
                }
            }
        }
        disk(60, 60, 0.2)
        disk(420, 420, beam)
        return DiffractionPattern(qy: q, qx: q, pixels: p)
    }

    private func builder() throws -> TrainingSampleBuilder {
        var params = DiskDetectionParams()
        params.minPeakSpacing = 8
        params.edgeBoundary = 4
        return try XCTUnwrap(TrainingSampleBuilder(qy: q, qx: q, probe: pattern(beam: 1), probeCentre: (x: 420, y: 420), probeRadius: 4,
                                                   kernelSource: .measured, params: params))
    }

    /// The window holding only the weak spot: the one at (0, 0).
    private func firstWindowInputs(_ b: TrainingSampleBuilder, _ p: DiffractionPattern) throws -> [Float16] {
        let i = try XCTUnwrap(b.windows.firstIndex { $0.row0 == 0 && $0.col0 == 0 })
        let samples = b.samples(pattern: p, position: ScanPosition(ry: 0, rx: 0), centres: [])
        return samples[i].inputs
    }

    /// Mutation: the per-window scale (`countScale` nil) — the two patterns give the same window inputs, red.
    func testAWindowIsScaledByItsWholePatternsDose() throws {
        let b = try builder()
        XCTAssertGreaterThan(b.windows.count, 1, "a 512-px detector is several windows")
        let bright = try firstWindowInputs(b, pattern(beam: 1.0))
        let dim = try firstWindowInputs(b, pattern(beam: 0.5))
        XCTAssertNotEqual(bright, dim, "the window's own pixels are the same; only the whole pattern's maximum differs")
    }

    /// The window follows the beam outside it: the whole pattern's scale (`nativeCountScale`, 20 000 / 0.5 here), not its own.
    func testTheWindowFollowsTheBeamOutsideIt() throws {
        let b = try builder()
        let p = pattern(beam: 0.5)
        let got = try firstWindowInputs(b, p)
        let scale = p.pixels.withUnsafeBufferPointer { LearnedDiskDetector.nativeCountScale(pattern: $0.baseAddress!, count: $0.count) }
        XCTAssertEqual(scale, LearnedDiskDetector.nominalBeamCounts / 0.5)
        let perWindow = try firstWindowInputs(b, pattern(beam: 0.2))   // beam = window max: whole-pattern and per-window scale agree
        XCTAssertNotEqual(got, perWindow)
    }

    /// Patterns already in counts (maximum > 1) are scaled by 1 on both rules: nothing changes for them.
    func testCountsAreUnchanged() throws {
        let b = try builder()
        XCTAssertEqual(try firstWindowInputs(b, pattern(beam: 1.0, scale: 1000)), try firstWindowInputs(b, pattern(beam: 0.5, scale: 1000)))
    }
}
