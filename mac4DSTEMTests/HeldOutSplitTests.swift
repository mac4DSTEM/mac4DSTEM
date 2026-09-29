//
//  HeldOutSplitTests.swift
//  The held-out split of the on-device fine-tuning (C3 pre-registration §3 step 2, D3): a position is held
//  out when SHA-256("ry,rx") -> [0,1) < 0.30. The pinned numbers below were computed with Python's hashlib
//  (first 8 digest bytes big-endian, >> 11, / 2^53), not with the code under test.
//
//  Mutations these tests are written to catch (each goes red): hashing "rx,ry" (the (3,5) and (12,7) pins),
//  fraction 0.31 or 0.29 (the 20x20 count 125 becomes 128 / 121; the 6x6 list changes), a split that
//  depends on the list rather than the position (testASideNeverDependsOnTheOtherPositions).
//

import XCTest
import DSTEMTraining

final class HeldOutSplitTests: XCTestCase {

    func testHashUnitMatchesPythonReference() {
        let pins: [(Int, Int, Double)] = [
            (0, 0, 4_053_419_451_299_122), (3, 5, 8_485_160_687_426_533), (12, 7, 8_851_116_342_653_241),
            (20, 20, 1_098_705_851_370_755), (31, 0, 6_066_086_456_836_892),
        ]
        for (ry, rx, numerator) in pins {
            XCTAssertEqual(HeldOutSplit.hashUnit(ry: ry, rx: rx), numerator / 9_007_199_254_740_992.0, "(\(ry),\(rx))")
        }
        // ry and rx are not interchangeable: "3,5" and "5,3" are different strings
        XCTAssertNotEqual(HeldOutSplit.hashUnit(ry: 3, rx: 5), HeldOutSplit.hashUnit(ry: 5, rx: 3))
    }

    func testHashUnitIsInHalfOpenUnitInterval() {
        for ry in 0 ..< 60 { for rx in 0 ..< 60 {
            let u = HeldOutSplit.hashUnit(ry: ry, rx: rx)
            XCTAssertGreaterThanOrEqual(u, 0); XCTAssertLessThan(u, 1)
        } }
    }

    func testTheRegisteredFractionIsThirtyPercentByHash() {
        XCTAssertEqual(HeldOutSplit.fraction, 0.30)
        let grid = (0 ..< 6).flatMap { ry in (0 ..< 6).map { ScanPosition(ry: ry, rx: $0) } }
        let s = HeldOutSplit.split(grid)
        XCTAssertEqual(s.heldOut, [ScanPosition(ry: 1, rx: 1), ScanPosition(ry: 1, rx: 2), ScanPosition(ry: 1, rx: 4),
                                   ScanPosition(ry: 2, rx: 3), ScanPosition(ry: 2, rx: 5), ScanPosition(ry: 4, rx: 3)])
        XCTAssertEqual(s.train.count, 30)
        // 20 x 20 positions: 125 of 400 (31 %), Python's count at the same threshold
        let big = (0 ..< 20).flatMap { ry in (0 ..< 20).map { ScanPosition(ry: ry, rx: $0) } }
        XCTAssertEqual(HeldOutSplit.split(big).heldOut.count, 125)
    }

    func testASideNeverDependsOnTheOtherPositions() {
        // New labels never move a position: the split of a subset is the restriction of the split of a superset.
        let all = (0 ..< 25).flatMap { ry in (0 ..< 25).map { ScanPosition(ry: ry, rx: $0) } }
        let full = HeldOutSplit.split(all)
        let subset = Array(all.shuffled().prefix(80))
        let part = HeldOutSplit.split(subset)
        XCTAssertEqual(Set(part.heldOut), Set(full.heldOut).intersection(subset))
        XCTAssertEqual(Set(part.train), Set(full.train).intersection(subset))
        // order, duplicates and repetition change nothing
        XCTAssertEqual(HeldOutSplit.split(subset + subset).heldOut, part.heldOut)
        XCTAssertEqual(HeldOutSplit.split(subset.reversed()).train, part.train)
        for p in subset { XCTAssertEqual(HeldOutSplit.isHeldOut(p), part.heldOut.contains(p)) }
        // the two sides partition the input
        XCTAssertEqual(Set(part.heldOut).union(part.train), Set(subset))
        XCTAssertTrue(Set(part.heldOut).isDisjoint(with: part.train))
    }
}
