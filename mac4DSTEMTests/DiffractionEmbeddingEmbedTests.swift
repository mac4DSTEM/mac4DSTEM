import XCTest
import DSTEMCore

/// Gate D, 2026-09-28 (`docs/archive/v4/embedding-embed-gateD-2026-09-28.md`):
/// `embed` moved to Accelerate for finite patterns. The old `embed` is kept
/// here VERBATIM (from `DiffractionEmbedding.swift` at f940fb7) as the
/// reference. P1: finite patterns agree to ≤ 1e-6 relative per binned value,
/// AND at least one value differs in its last bits (anti-vacuity: proves the
/// Accelerate path ran — a build that always fell back would agree
/// exactly). P2: patterns with NaN / ±Inf are bit-identical (the fallback).
final class DiffractionEmbeddingEmbedTests: XCTestCase {

    /// The pre-2026-09-28 `DiffractionEmbedding.embed`, unchanged.
    private static func referenceEmbed(
        pixels: [Float], base: Int, qy: Int, qx: Int, geometry: DiffractionEmbedding.BinGeometry, binnedSize: Int
    ) -> [Float] {
        let count = qy * qx
        var scaled = [Float](repeating: 0, count: count)
        var maxVal: Float = 0
        pixels.withUnsafeBufferPointer { buf in
            for i in 0..<count {
                let v = log1p(max(buf[base + i], 0))
                scaled[i] = v
                if v > maxVal { maxVal = v }
            }
        }
        if maxVal > 0 {
            let inv = 1 / maxVal
            for i in 0..<count { scaled[i] *= inv }
        }
        var out = [Float](repeating: 0, count: binnedSize * binnedSize)
        guard geometry.binnedH > 0, geometry.binnedW > 0 else { return out }
        for by in 0..<geometry.binnedH {
            let y0 = geometry.offsetY + by * geometry.boxY
            for bx in 0..<geometry.binnedW {
                let x0 = geometry.offsetX + bx * geometry.boxX
                var sum: Float = 0
                for dy in 0..<geometry.boxY {
                    let rowBase = (y0 + dy) * qx
                    for dx in 0..<geometry.boxX { sum += scaled[rowBase + x0 + dx] }
                }
                out[by * binnedSize + bx] = sum
            }
        }
        return out
    }

    private struct Case { let qy: Int; let qx: Int; let binned: Int; let pattern: [Float] }

    /// Disk patterns like the owner's: a bright centre, a ring of disks, a
    /// noisy background, a few negative pixels and a −0.0.
    private func finiteCases() -> [Case] {
        var state: UInt64 = 0x5EED
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) % 1_000_000) / 1_000_000
        }
        func pattern(qy: Int, qx: Int, shift: Int) -> [Float] {
            var img = (0..<(qy * qx)).map { _ in 20 * rnd() }
            let cy = qy / 2 + shift % 5, cx = qx / 2 - shift % 3
            for k in 0..<9 {
                let angle = Float(k) * 0.7 + Float(shift) * 0.1
                let r: Float = k == 0 ? 0 : Float(min(qy, qx)) * 0.3
                let y = cy + Int(r * sin(angle)), x = cx + Int(r * cos(angle))
                let amp: Float = k == 0 ? 7.7e5 : 3e4 * (0.5 + rnd())
                for dy in -3...3 { for dx in -3...3 where dy * dy + dx * dx <= 9 {
                    let yy = y + dy, xx = x + dx
                    if yy >= 0, yy < qy, xx >= 0, xx < qx { img[yy * qx + xx] += amp }
                } }
            }
            img[5] = -3; img[7] = -0.0; img[qx + 1] = -1e-3
            return img
        }
        var cases: [Case] = []
        for s in 0..<6 {
            cases.append(Case(qy: 128, qx: 128, binned: 16, pattern: pattern(qy: 128, qx: 128, shift: s)))
            cases.append(Case(qy: 128, qx: 128, binned: 32, pattern: pattern(qy: 128, qx: 128, shift: s + 11)))
            cases.append(Case(qy: 96, qx: 110, binned: 16, pattern: pattern(qy: 96, qx: 110, shift: s + 23)))
        }
        return cases
    }

    private func run(_ c: Case) -> (new: [Float], old: [Float]) {
        let g = DiffractionEmbedding.BinGeometry.compute(qy: c.qy, qx: c.qx, binnedSize: c.binned)
        return (DiffractionEmbedding.embed(pixels: c.pattern, base: 0, qy: c.qy, qx: c.qx, geometry: g, binnedSize: c.binned),
                Self.referenceEmbed(pixels: c.pattern, base: 0, qy: c.qy, qx: c.qx, geometry: g, binnedSize: c.binned))
    }

    func testFinitePatternsAgreeWithTheOldEmbedAndTakeTheAcceleratePath() {
        var worst: Float = 0, differing = 0, values = 0
        for c in finiteCases() {
            let (new, old) = run(c)
            XCTAssertEqual(new.count, old.count)
            for (a, b) in zip(new, old) {
                values += 1
                if a.bitPattern != b.bitPattern { differing += 1 }
                if b == 0 { XCTAssertEqual(a, 0, "an empty bin must stay exactly 0"); continue }
                worst = max(worst, abs(a - b) / abs(b))
            }
        }
        print("embed agreement: max relative \(worst), \(differing) of \(values) values differ in the last bits")
        XCTAssertLessThanOrEqual(worst, 1e-6)
        XCTAssertGreaterThan(differing, 0,
            "no value differs from the scalar reference: the Accelerate path did not run")
    }

    /// The Gate B refuter's stresses (2026-09-28): 1e-6 is a property of the
    /// fixture above (128² detectors, boxes ≤ 8 × 8), not a general bound.
    /// A 512² detector binned to 16 sums 1 024 terms per box (measured
    /// 1.8e-6), and a 1e7 spike over a 1e-3 background stretches the dynamic
    /// range (2.1e-6). Both are far below noise on real data; the bar here is
    /// 5e-6.
    func testStressedPatternsAgreeWithinTheWiderBar() {
        var state: UInt64 = 0xB16
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) % 1_000_000) / 1_000_000
        }
        var big = (0..<(512 * 512)).map { _ in 20 * rnd() }
        for k in 0..<12 {
            let y = 60 + (k * 37) % 390, x = 50 + (k * 53) % 410
            for dy in -6...6 { for dx in -6...6 { big[(y + dy) * 512 + x + dx] += 3e4 * (0.5 + rnd()) } }
        }
        var spike = (0..<(128 * 128)).map { _ in 1e-3 * (0.5 + rnd()) }
        spike[64 * 128 + 64] = 1e7
        var worst: Float = 0
        for c in [Case(qy: 512, qx: 512, binned: 16, pattern: big),
                  Case(qy: 128, qx: 128, binned: 16, pattern: spike),
                  Case(qy: 128, qx: 128, binned: 32, pattern: spike)] {
            let (new, old) = run(c)
            for (a, b) in zip(new, old) where b != 0 { worst = max(worst, abs(a - b) / abs(b)) }
        }
        XCTAssertLessThanOrEqual(worst, 5e-6)
    }

    func testNonFinitePatternsAreBitIdenticalToTheOldEmbed() {
        let base = finiteCases()[0].pattern
        let variants: [(String, (inout [Float]) -> Void)] = [
            ("NaN", { $0[40 * 128 + 40] = .nan }),
            ("+Inf", { $0[64 * 128 + 64] = .infinity }),
            ("-Inf", { $0[10 * 128 + 90] = -.infinity }),
            ("NaN and -Inf", { $0[3] = .nan; $0[200] = -.infinity }),
            ("+Inf and -Inf", { $0[3] = .infinity; $0[200] = -.infinity }),
        ]
        for (name, apply) in variants {
            var p = base
            apply(&p)
            for binned in [16, 32] {
                let (new, old) = run(Case(qy: 128, qx: 128, binned: binned, pattern: p))
                XCTAssertEqual(new.map(\.bitPattern), old.map(\.bitPattern), "\(name), binned \(binned)")
            }
        }
    }
}
