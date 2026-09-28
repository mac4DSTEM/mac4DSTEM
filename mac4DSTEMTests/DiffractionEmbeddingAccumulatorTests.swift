import XCTest
import DSTEMCore

/// Gate D, 2026-09-28 (`docs/archive/v4/embedding-accumulate-gateD-2026-09-28.md`):
/// the covariance sums moved from a scalar loop to `cblas_dsyrk`. The old loop
/// is kept here VERBATIM (from `DiffractionEmbedding.swift` at 80401b1) as the
/// reference; the new accumulator must agree with it up to summation order
/// (P1: max |Δ| / max |ref| ≤ 1e-12), be exactly symmetric, and keep `sumVec`
/// bit-identical.
final class DiffractionEmbeddingAccumulatorTests: XCTestCase {

    /// The pre-2026-09-28 `DiffractionEmbedding.accumulate`, unchanged.
    private static func accumulate(
        _ vector: [Float], dims: Int, sumVec: inout [Double], sumOuter: inout [Double]
    ) {
        vector.withUnsafeBufferPointer { v in
            sumVec.withUnsafeMutableBufferPointer { sv in
                for i in 0..<dims { sv[i] += Double(v[i]) }
            }
            sumOuter.withUnsafeMutableBufferPointer { so in
                for i in 0..<dims {
                    let vi = Double(v[i])
                    let rowBase = i * dims
                    for j in 0..<dims { so[rowBase + j] += vi * Double(v[j]) }
                }
            }
        }
    }

    /// Binned vectors like `embed`'s: sums of up to boxY·boxX values in
    /// [0, 1], so 0…16 at the shipped geometry; a per-position structure so the
    /// matrix is not flat.
    private func vectors(count: Int, dims: Int, seed: UInt64) -> [[Float]] {
        var state = seed
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) % 1_000_000) / 1_000_000
        }
        return (0..<count).map { p in
            (0..<dims).map { i in 16 * rnd() * (i % 7 == p % 7 ? 1 : 0.2) }
        }
    }

    private func assertAgreement(count: Int, dims: Int, file: StaticString = #filePath, line: UInt = #line) {
        let data = vectors(count: count, dims: dims, seed: UInt64(count * 31 + dims))
        var refVec = [Double](repeating: 0, count: dims)
        var refOuter = [Double](repeating: 0, count: dims * dims)
        var accumulator = DiffractionEmbedding.OuterProductAccumulator(dims: dims)
        for v in data {
            Self.accumulate(v, dims: dims, sumVec: &refVec, sumOuter: &refOuter)
            accumulator.add(v)
        }
        let (sumVec, sumOuter) = accumulator.finish()

        XCTAssertEqual(sumVec, refVec, "sumVec must stay bit-identical", file: file, line: line)
        let scale = refOuter.map(abs).max()!
        var worst = 0.0
        for k in 0..<(dims * dims) { worst = max(worst, abs(sumOuter[k] - refOuter[k])) }
        XCTAssertLessThanOrEqual(worst / scale, 1e-12,
                                 "max |Δ| \(worst) of max |ref| \(scale)", file: file, line: line)
        for i in 0..<dims {
            for j in 0..<i where sumOuter[i * dims + j] != sumOuter[j * dims + i] {
                XCTFail("not symmetric at (\(i), \(j))", file: file, line: line); return
            }
        }
    }

    /// The shipped default (16 × 16): three chunks and a remainder.
    func testAgreesWithTheOldLoopAtTheDefaultSize() {
        assertAgreement(count: 2 * DiffractionEmbedding.OuterProductAccumulator.chunk + 452, dims: 256)
    }

    /// 32 × 32, the size the owner found too slow; one chunk and a remainder.
    func testAgreesWithTheOldLoopAtThirtyTwo() {
        assertAgreement(count: DiffractionEmbedding.OuterProductAccumulator.chunk + 76, dims: 1024)
    }

    /// Fewer vectors than a chunk, and a non-square-friendly dimension.
    func testAgreesWithTheOldLoopBelowOneChunk() {
        assertAgreement(count: 37, dims: 49)
    }
}
