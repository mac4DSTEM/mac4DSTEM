//
//  DetectionScorer.swift
//  Role: recall and precision of a set of predicted disk centres against hand-labelled truth — a Swift
//        port of `tools/disk-detector/evaluate.py`'s `match` (C3 pre-registration §2(b), §3 step 4).
//
//  Greedy nearest pairing: truth points are visited IN ORDER; each takes the nearest still-unused
//  prediction (the first of equals, as numpy's argmin does) and is matched when that distance is within
//  the radius (inclusive, 2 px by default); a prediction is used at most once. matched, truth and predicted
//  counts are the whole result; recall = matched / max(truth, 1) and precision = matched / max(predicted, 1),
//  `evaluate.py`'s own `max(n, 1)` convention. Coordinates are (row, col) in one common frame.
//

import Foundation

package nonisolated struct ScorePoint: Equatable, Codable, Sendable {
    package var row: Double
    package var col: Double
    package init(row: Double, col: Double) { self.row = row; self.col = col }
}

package nonisolated struct DetectionScore: Equatable, Codable, Sendable {
    package var matched: Int
    package var truth: Int
    package var predicted: Int
    package init(matched: Int, truth: Int, predicted: Int) {
        self.matched = matched; self.truth = truth; self.predicted = predicted
    }
    package var recall: Double { Double(matched) / Double(max(truth, 1)) }
    package var precision: Double { Double(matched) / Double(max(predicted, 1)) }
}

package nonisolated enum DetectionScorer {
    /// The registered match radius: 2 px (pre-registration §2(b)).
    package static let defaultRadius = 2.0

    package struct Pair: Equatable, Sendable {
        package var truth: Int
        package var predicted: Int
        package var distance: Double
    }

    /// `evaluate.match(truth, predicted, radius)`: the pairs (in truth order), the unmatched truth indices
    /// and the unmatched prediction indices.
    package static func match(truth: [ScorePoint], predicted: [ScorePoint], radius: Double = DetectionScorer.defaultRadius)
        -> (pairs: [Pair], unmatchedTruth: [Int], unmatchedPredicted: [Int]) {
        var used = [Bool](repeating: false, count: predicted.count)
        var pairs: [Pair] = [], unmatchedTruth: [Int] = []
        for (i, t) in truth.enumerated() {
            var best = -1
            var bestDistance = Double.infinity
            for (j, p) in predicted.enumerated() where !used[j] {
                let d = hypot(p.row - t.row, p.col - t.col)
                if d < bestDistance { bestDistance = d; best = j }   // strict: the first of equals wins
            }
            if best >= 0, bestDistance <= radius {
                pairs.append(Pair(truth: i, predicted: best, distance: bestDistance))
                used[best] = true
            } else {
                unmatchedTruth.append(i)
            }
        }
        let unmatchedPredicted = used.indices.filter { !used[$0] }
        return (pairs, unmatchedTruth, unmatchedPredicted)
    }

    package static func score(truth: [ScorePoint], predicted: [ScorePoint], radius: Double = DetectionScorer.defaultRadius)
        -> DetectionScore {
        DetectionScore(matched: match(truth: truth, predicted: predicted, radius: radius).pairs.count,
                       truth: truth.count, predicted: predicted.count)
    }

    /// The counts of several positions summed (recall and precision are then pooled over positions, as
    /// `evaluate.py`'s `tally` does).
    package static func pooled(_ scores: [DetectionScore]) -> DetectionScore {
        scores.reduce(DetectionScore(matched: 0, truth: 0, predicted: 0)) {
            DetectionScore(matched: $0.matched + $1.matched, truth: $0.truth + $1.truth, predicted: $0.predicted + $1.predicted)
        }
    }
}
