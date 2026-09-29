//
//  TrainingPolicy.swift
//  Role: the pure decisions of the on-device training flow (Phase C4b; C3 pre-registration §3 steps 2 and 5,
//        ADR 048 D7): what the split row says, when "Train Model…" is allowed, and whether a fine-tuned
//        model is OFFERED. No I/O and no UI, so each rule has a test with a stated mutation.
//

import Foundation

package nonisolated enum TrainingPolicy {
    /// The fewest held-out positions a run is judged on. NOT measured: pre-registration §4 owes the
    /// measurement (k_min over A2's 40 labelled positions, predicted 12–25). 12 is the low end of that
    /// prediction, stated wherever it is shown, until the measurement replaces it.
    package static let minimumHeldOutPositions = 12

    /// How many labelled positions train and how many are held out.
    package struct SplitCounts: Equatable, Sendable {
        package var train: Int
        package var heldOut: Int
        package init(train: Int, heldOut: Int) { self.train = train; self.heldOut = heldOut }
        package var labelled: Int { train + heldOut }
    }

    /// The split of `positions` by `HeldOutSplit` (a position's side depends on the position alone).
    package static func counts(of positions: [ScanPosition]) -> SplitCounts {
        let split = HeldOutSplit.split(positions)
        return SplitCounts(train: split.train.count, heldOut: split.heldOut.count)
    }

    /// The split row's value: "Train 28 · Held out 12".
    package static func splitRowText(_ counts: SplitCounts) -> String {
        "Train \(counts.train) · Held out \(counts.heldOut)"
    }

    /// Why training is not allowed yet, or nil when it is. The held-out gate comes first: with too few
    /// held-out positions the comparison cannot be trusted, whatever the training set holds.
    package static func trainRefusal(_ counts: SplitCounts) -> String? {
        if counts.labelled == 0 {
            return "No positions are labelled yet: turn on Label centres on click and click the disk centres at several scan positions."
        }
        if counts.heldOut < minimumHeldOutPositions {
            return "Needs \(minimumHeldOutPositions) held-out positions; \(counts.heldOut) of \(counts.labelled) labelled positions are held out. Label more positions."
        }
        if counts.train < 1 { return "No labelled position is left to train on." }
        return nil
    }

    // MARK: The offer rule (ADR 048 D7)

    package enum Offer: Equatable, Sendable {
        /// Offer "Use Fine-Tuned Model".
        case offer
        /// Do not offer; the string names the number that fell (or says nothing moved).
        case decline(String)
    }

    /// Offer the fine-tuned model only if it is at least as good on recall AND precision and strictly
    /// better on one. A tie is not offered (narrower than ADR 043's "at least"). Fractions are compared by
    /// cross-multiplication, so no rounding can turn a fall into a tie.
    package static func offer(active: DetectionScore, candidate: DetectionScore) -> Offer {
        let recall = compare(matched: candidate.matched, of: candidate.truth, matched: active.matched, of: active.truth)
        let precision = compare(matched: candidate.matched, of: candidate.predicted, matched: active.matched, of: active.predicted)
        var fell: [String] = []
        if recall < 0 { fell.append("recall fell from \(percent(active.recall)) to \(percent(candidate.recall))") }
        if precision < 0 { fell.append("precision fell from \(percent(active.precision)) to \(percent(candidate.precision))") }
        if !fell.isEmpty {
            let sentence = fell.joined(separator: " and ")
            return .decline(String(sentence.prefix(1)).uppercased() + String(sentence.dropFirst()) + ". The fine-tuned model is not offered.")
        }
        if recall > 0 || precision > 0 { return .offer }
        return .decline("Recall and precision are unchanged. A tie is not offered.")
    }

    /// The sign of a/b − c/d for a/b = m1/max(d1,1), c/d = m2/max(d2,1) (`DetectionScore`'s own convention).
    static func compare(matched m1: Int, of d1: Int, matched m2: Int, of d2: Int) -> Int {
        let left = m1 * max(d2, 1), right = m2 * max(d1, 1)
        return left < right ? -1 : (left > right ? 1 : 0)
    }

    /// "77.1 %" (one decimal, a plain point: the sheet is read beside numbers the app prints the same way).
    package static func percent(_ fraction: Double) -> String {
        String(format: "%.1f %%", fraction * 100)
    }
}
