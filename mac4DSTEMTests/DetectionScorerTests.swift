//
//  DetectionScorerTests.swift
//  The Swift port of `tools/disk-detector/evaluate.py`'s `match` (C3 pre-registration §2(b)): greedy nearest
//  pairing within 2 px, each prediction used once. Hand cases pin the rules; the fixture case pins the
//  counts Python's `evaluate.match` gives on the committed 16-pattern fixture — truth from
//  fixture/expected.json shifted into the 256 frame (+64, the fit offset), predictions the raw picks in
//  fixture/swift/expected.json — computed with `evaluate.match` itself (numpy), not with the code under test:
//      radius 2.0: truth 310, predicted 354, matched 247, per pattern [14,14,22,21,18,13,13,16,16,16,12,11,18,13,17,13]
//      radius 3.0: matched 267 (so a 3 px radius is visibly a different number).
//
//  Mutation stated: setting the default radius to 3 px turns testTheDefaultRadiusIsTwoPixels and
//  testFixtureCountsEqualPythonsEvaluateMatch red (247 -> 267); dropping the used-once rule turns
//  testEachPredictionIsUsedOnce red; visiting in nearest-first order instead of truth order turns
//  testTruthIsVisitedInOrder red (the second call would give 0.9).
//

import XCTest
import DSTEMTraining

final class DetectionScorerTests: XCTestCase {
    private func P(_ r: Double, _ c: Double) -> ScorePoint { ScorePoint(row: r, col: c) }

    func testTheDefaultRadiusIsTwoPixels() {
        XCTAssertEqual(DetectionScorer.defaultRadius, 2.0)
        let truth = [P(10, 10)]
        XCTAssertEqual(DetectionScorer.score(truth: truth, predicted: [P(10, 12)]).matched, 1, "exactly 2 px is a hit (inclusive)")
        XCTAssertEqual(DetectionScorer.score(truth: truth, predicted: [P(10, 12.5)]).matched, 0, "2.5 px is a miss at the default radius")
        XCTAssertEqual(DetectionScorer.score(truth: truth, predicted: [P(10, 12.5)], radius: 3).matched, 1)
        XCTAssertEqual(DetectionScorer.score(truth: truth, predicted: [P(13, 14)]).matched, 0, "5 px (3-4-5) is a miss")
    }

    func testEachPredictionIsUsedOnce() {
        // two truths, one prediction between them: only one pair
        let s = DetectionScorer.score(truth: [P(10, 10), P(10, 12)], predicted: [P(10, 11)])
        XCTAssertEqual(s, DetectionScore(matched: 1, truth: 2, predicted: 1))
        XCTAssertEqual(s.recall, 0.5); XCTAssertEqual(s.precision, 1.0)
    }

    func testTruthIsVisitedInOrder() {
        // one prediction p at the origin; A is 0.9 px away, B 1.5 px away; nothing else is in range.
        // Greedy in TRUTH order gives p to whoever is listed first, so the pair's distance follows the order.
        let a = P(0, 0.9), b = P(0, -1.5), p = P(0, 0)
        XCTAssertEqual(DetectionScorer.match(truth: [a, b], predicted: [p]).pairs.map(\.distance), [0.9])
        XCTAssertEqual(DetectionScorer.match(truth: [b, a], predicted: [p]).pairs.map(\.distance), [1.5])
        XCTAssertEqual(DetectionScorer.match(truth: [b, a], predicted: [p]).unmatchedTruth, [1])
    }

    func testNearestUnusedAndTheFirstOfEqualsWin() {
        let r = DetectionScorer.match(truth: [P(0, 0)], predicted: [P(1, 0), P(0, 1), P(0.5, 0)])
        XCTAssertEqual(r.pairs.count, 1)
        XCTAssertEqual(r.pairs[0].predicted, 2, "the nearest (0.5 px)")
        let tie = DetectionScorer.match(truth: [P(0, 0)], predicted: [P(0, 1), P(1, 0)])
        XCTAssertEqual(tie.pairs[0].predicted, 0, "equal distances: the first index, as numpy's argmin")
        XCTAssertEqual(tie.unmatchedPredicted, [1])
    }

    func testEmptyInputsFollowEvaluatePysMaxOne() {
        XCTAssertEqual(DetectionScorer.score(truth: [], predicted: []), DetectionScore(matched: 0, truth: 0, predicted: 0))
        XCTAssertEqual(DetectionScorer.score(truth: [], predicted: []).recall, 0)
        XCTAssertEqual(DetectionScorer.score(truth: [P(1, 1)], predicted: []).recall, 0)
        XCTAssertEqual(DetectionScorer.score(truth: [], predicted: [P(1, 1)]).precision, 0)
        let pooled = DetectionScorer.pooled([DetectionScore(matched: 3, truth: 4, predicted: 5), DetectionScore(matched: 1, truth: 2, predicted: 1)])
        XCTAssertEqual(pooled, DetectionScore(matched: 4, truth: 6, predicted: 6))
    }

    // MARK: the committed fixture, against Python's numbers

    private struct Truth: Decodable { struct T: Decodable { let centres: [[Double]] }; let truth: [T] }
    private struct Picks: Decodable { struct Pt: Decodable { let picks: [[Double]] }; let patterns: [Pt] }

    private func fixtureScores(radius: Double) throws -> [DetectionScore] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dir = repo.appendingPathComponent("tools/disk-detector/fixture")
        let truth = try JSONDecoder().decode(Truth.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        let picks = try JSONDecoder().decode(Picks.self, from: Data(contentsOf: dir.appendingPathComponent("swift/expected.json")))
        XCTAssertEqual(truth.truth.count, 16); XCTAssertEqual(picks.patterns.count, 16)
        return zip(truth.truth, picks.patterns).map { t, p in
            DetectionScorer.score(
                truth: t.centres.map { ScorePoint(row: $0[0] + 64, col: $0[1] + 64) },   // native 128 -> 256 frame
                predicted: p.picks.map { ScorePoint(row: $0[0], col: $0[1]) },            // (row, col, score)
                radius: radius)
        }
    }

    func testFixtureCountsEqualPythonsEvaluateMatch() throws {
        let at2 = try fixtureScores(radius: DetectionScorer.defaultRadius)
        XCTAssertEqual(at2.map(\.matched), [14, 14, 22, 21, 18, 13, 13, 16, 16, 16, 12, 11, 18, 13, 17, 13])
        XCTAssertEqual(at2.map(\.truth), [17, 18, 24, 28, 23, 15, 17, 20, 21, 18, 16, 13, 25, 17, 21, 17])
        XCTAssertEqual(at2.map(\.predicted), [20, 18, 24, 28, 26, 15, 19, 28, 31, 16, 24, 15, 29, 19, 23, 19])
        let total = DetectionScorer.pooled(at2)
        XCTAssertEqual(total, DetectionScore(matched: 247, truth: 310, predicted: 354))
        XCTAssertEqual(total.recall, 247.0 / 310.0); XCTAssertEqual(total.precision, 247.0 / 354.0)
        // and 3 px is a different number (the pre-registration's break test)
        let at3 = try fixtureScores(radius: 3)
        XCTAssertEqual(at3.map(\.matched), [14, 15, 22, 24, 20, 13, 14, 17, 17, 16, 14, 12, 21, 16, 18, 14])
        XCTAssertEqual(DetectionScorer.pooled(at3).matched, 267)
    }
}
