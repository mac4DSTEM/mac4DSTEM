import XCTest
import DSTEMCore

/// Gate D, 2026-09-28 (`docs/archive/v4/embedding-projection-gateD-2026-09-28.md`):
/// the projection moved to `vDSP_vsub` + `vDSP_dotpr`. The old loop is kept
/// here VERBATIM (the cached path's body at fa30421) as the reference, with
/// an exact double-precision projection as the truth both are judged against.
/// P1: |new − old| ≤ 1e-5 · max |coordinate|; the new error against the
/// double truth is at most 2× the old one's; and at least one coordinate
/// differs in its last bits (anti-vacuity: the Accelerate path ran).
final class DiffractionEmbeddingProjectionTests: XCTestCase {

    private struct Fixture { let dims: Int; let k: Int; let vectors: [Float]; let mean: [Float]; let basis: [Float]; let n: Int }

    /// Vectors shaped like `embed`'s output (sums of up to 64 values in
    /// [0, 1], structured by position), their mean, and k orthonormal rows.
    private func fixture(dims: Int, k: Int, n: Int, seed: UInt64) -> Fixture {
        var state = seed
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) % 1_000_000) / 1_000_000
        }
        var vectors = [Float](repeating: 0, count: n * dims)
        for p in 0..<n { for i in 0..<dims { vectors[p * dims + i] = 64 * rnd() * (i % 5 == p % 5 ? 1 : 0.3) } }
        var mean = [Float](repeating: 0, count: dims)
        for i in 0..<dims {
            var s = 0.0
            for p in 0..<n { s += Double(vectors[p * dims + i]) }
            mean[i] = Float(s / Double(n))
        }
        // Gram–Schmidt on random rows, in double, stored as Float.
        var rows: [[Double]] = []
        while rows.count < k {
            var v = (0..<dims).map { _ in Double(rnd()) - 0.5 }
            for r in rows { let d = zip(v, r).map(*).reduce(0, +); for i in 0..<dims { v[i] -= d * r[i] } }
            let norm = sqrt(v.map { $0 * $0 }.reduce(0, +))
            rows.append(v.map { $0 / norm })
        }
        return Fixture(dims: dims, k: k, vectors: vectors, mean: mean,
                       basis: rows.flatMap { $0.map(Float.init) }, n: n)
    }

    /// The pre-2026-09-28 cached-path projection, unchanged.
    private static func referenceProject(_ f: Fixture) -> [Float] {
        let dims = f.dims, actualComponents = f.k, totalPositions = f.n
        var coordinates = [Float](repeating: 0, count: totalPositions * actualComponents)
        f.vectors.withUnsafeBufferPointer { cache in
            f.basis.withUnsafeBufferPointer { basisBuf in
                f.mean.withUnsafeBufferPointer { meanBuf in
                    coordinates.withUnsafeMutableBufferPointer { outBuf in
                        for pos in 0..<totalPositions {
                            let vecBase = pos * dims
                            for c in 0..<actualComponents {
                                let rowBase = c * dims
                                var dot: Float = 0
                                for i in 0..<dims {
                                    dot += (cache[vecBase + i] - meanBuf[i]) * basisBuf[rowBase + i]
                                }
                                outBuf[pos * actualComponents + c] = dot
                            }
                        }
                    }
                }
            }
        }
        return coordinates
    }

    private static func exactProject(_ f: Fixture) -> [Double] {
        var out = [Double](repeating: 0, count: f.n * f.k)
        for pos in 0..<f.n {
            for c in 0..<f.k {
                var dot = 0.0
                for i in 0..<f.dims {
                    dot += (Double(f.vectors[pos * f.dims + i]) - Double(f.mean[i])) * Double(f.basis[c * f.dims + i])
                }
                out[pos * f.k + c] = dot
            }
        }
        return out
    }

    private static func newProject(_ f: Fixture) -> [Float] {
        var out = [Float](repeating: 0, count: f.n * f.k)
        var centred = [Float](repeating: 0, count: f.dims)
        f.vectors.withUnsafeBufferPointer { v in
            f.mean.withUnsafeBufferPointer { m in
                f.basis.withUnsafeBufferPointer { b in
                    centred.withUnsafeMutableBufferPointer { cen in
                        out.withUnsafeMutableBufferPointer { o in
                            for pos in 0..<f.n {
                                DiffractionEmbedding.project(
                                    v.baseAddress! + pos * f.dims, mean: m.baseAddress!, basis: b.baseAddress!,
                                    dims: f.dims, components: f.k, centred: cen.baseAddress!,
                                    into: o.baseAddress! + pos * f.k)
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    private func assertAgreement(dims: Int, k: Int, n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let f = fixture(dims: dims, k: k, n: n, seed: UInt64(dims * 7 + n))
        let new = Self.newProject(f), old = Self.referenceProject(f), exact = Self.exactProject(f)
        let scale = old.map(abs).max()!
        var newVsOld: Float = 0, newErr = 0.0, oldErr = 0.0, differing = 0
        for j in 0..<new.count {
            newVsOld = max(newVsOld, abs(new[j] - old[j]))
            newErr = max(newErr, abs(Double(new[j]) - exact[j]))
            oldErr = max(oldErr, abs(Double(old[j]) - exact[j]))
            if new[j].bitPattern != old[j].bitPattern { differing += 1 }
        }
        XCTAssertLessThanOrEqual(newVsOld, 1e-5 * scale, "max |new − old| \(newVsOld) of scale \(scale)", file: file, line: line)
        XCTAssertLessThanOrEqual(newErr, 2 * oldErr, "vs exact: new \(newErr), old \(oldErr)", file: file, line: line)
        XCTAssertGreaterThan(differing, 0, "no coordinate differs: the Accelerate path did not run", file: file, line: line)
    }

    func testAgreesWithTheOldLoopAtTheDefaultSize() { assertAgreement(dims: 256, k: 8, n: 300) }
    func testAgreesWithTheOldLoopAtThirtyTwo() { assertAgreement(dims: 1024, k: 8, n: 200) }
    func testAgreesWithTheOldLoopForOneComponentAndOddDims() { assertAgreement(dims: 49, k: 1, n: 150) }
}
