//
//  ReviewCIHonestTests.swift
//  Lane R (pre-release review, 2026-10-02, owner card R3 a): the CI `core` job failed on the runner's Xcode 26 with
//  "unable to type-check this expression in reasonable time" at the one-line closure in `Matrix3.transformRows`
//  (MaterialsProjectImport.swift). The fix splits that expression into explicit per-term sums; it must stay
//  BIT-IDENTICAL, so the three cases below are compared by bit pattern against values recorded from the code as it
//  stood before the split (scratch compile of the verbatim old expression, then this test run against it: green).
//  Each case is built so that the order of the three additions changes the result — a reordered sum goes red.
//

import XCTest
import simd
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ReviewCIHonestTests: XCTestCase {
    private func bits(_ rows: [SIMD3<Double>]) -> [UInt64] {
        rows.flatMap { [$0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern] }
    }

    /// 1e16 has an ulp of 2, so 1e16 + 1 == 1e16 (ties to even): ((1e16 + 1) - 1e16) is 0 while ((1e16 - 1e16) + 1) is 1.
    /// An asymmetric integer matrix (row 2 = [-1, 2, 1]) so a transposed or mis-indexed read also fails.
    func testTransformRowsCancellationCaseIsBitIdentical() {
        let rows: [SIMD3<Double>] = [SIMD3(1e16, 1, 0.1), SIMD3(1, 1e16, 0.2), SIMD3(1e16, -1e16, 0.3)]
        let m: [[Double]] = [[1, 1, -1], [1, -1, 1], [-1, 2, 1]]
        XCTAssertEqual(bits(Matrix3.transformRows(rows, by: m)), [
            0x0000000000000000, 0x4351c37937e08000, 0x3c90000000000000,
            0x4351c37937e08000, 0xc351c37937e08000, 0x3fc9999999999999,
            0x4000000000000000, 0x4341c37937e08000, 0x3fe3333333333334,
        ])
    }

    /// Ordinary magnitudes, a non-integer asymmetric matrix: the three products round, and the order of the two additions
    /// decides the last bit of several components.
    func testTransformRowsNonIntegerMatrixIsBitIdentical() {
        let rows: [SIMD3<Double>] = [SIMD3(3.8404, 0.1, -0.3), SIMD3(0.7, 5.1234567, 0.2),
                                     SIMD3(-1.1, 0.30000000000000004, 7.7)]
        let m: [[Double]] = [[0.1, 0.2, 0.3], [0.7, -0.6, 0.5], [1.1, 0.3, -0.9]]
        XCTAssertEqual(bits(Matrix3.transformRows(rows, by: m)), [
            0x3fc8d64d7f0ed3d6, 0x3ff1febc58b64f89, 0x40028f5c28f5c290,
            0x3ffb7e132b55ef1f, 0xc006d524c2821b23, 0x400c28f5c28f5c29,
            0x4015b2a0663c74fc, 0x3ff60857f5b54e56, 0xc01cccccccccccce,
        ])
    }

    /// The F-centring change-of-basis (the matrix the importer applies to the Si case) on mixed 1e16 / 1e-16 magnitudes.
    func testTransformRowsCentringMatrixIsBitIdentical() {
        let rows: [SIMD3<Double>] = [SIMD3(1e16, 1, 3), SIMD3(1, 1e16, 1e-16), SIMD3(1, 1, 1e16)]
        let m: [[Double]] = [[-1, 1, 1], [1, -1, 1], [1, 1, -1]]
        XCTAssertEqual(bits(Matrix3.transformRows(rows, by: m)), [
            0xc341c37937e08000, 0x4341c37937e08000, 0x4341c37937e07ffe,
            0x4341c37937e08000, 0xc341c37937e08000, 0x4341c37937e08002,
            0x4341c37937e08000, 0x4341c37937e08000, 0xc341c37937e07ffe,
        ])
    }

    /// The documented meaning, on the case the doc comment cites: F applied to the F-centred primitive's rows
    /// a/2·(0,1,1), a/2·(1,0,1), a/2·(1,1,0) gives (a,0,0), (0,a,0), (0,0,a) exactly (a/2 = 2, a power of two, so exact).
    func testTransformRowsFCentringGivesTheConventionalCubicCell() {
        let rows: [SIMD3<Double>] = [SIMD3(0, 2, 2), SIMD3(2, 0, 2), SIMD3(2, 2, 0)]
        let m: [[Double]] = [[-1, 1, 1], [1, -1, 1], [1, 1, -1]]
        XCTAssertEqual(Matrix3.transformRows(rows, by: m), [SIMD3(4, 0, 0), SIMD3(0, 4, 0), SIMD3(0, 0, 4)])
    }
}
