//
//  QCalibrationRun.swift
//  Role: The last reciprocal-pixel calibration attempt — its estimate, what the
//        estimator's own plausibility checks said, and why it was refused if it
//        was. One owner, so the number the user sees and the caveat attached to
//        it cannot come from two places.
//
//  `AppState`'s seam for this state (docs/archive/development-process-2026-08-31.md §7):
//  AppState holds it with NO forwarding properties; view code asks this type
//  directly. The shell-ratio self-check has a third state that is neither
//  pass nor fail ("only one shell is detectable, so the single-shell
//  assumption is unchecked"); that state needs a durable home, not a
//  transient status string the next operation overwrites.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
@MainActor
package final class QCalibrationRun {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// The last estimate the app accepted, or nil when none has been made
    /// since the dataset changed. An estimate that was REFUSED is not stored
    /// here — `refusal` carries that case, so "there is an estimate" and "the
    /// estimate may be used" cannot drift apart.
    package private(set) var estimate: QCalibrationEstimate?

    /// Why the last attempt was refused, or nil. Set from exactly one source:
    /// the origin/metrology gate (`SessionGates`). The estimator itself never
    /// refuses — Gate B removed its thresholds, so it measures and reports,
    /// and `selfCheckSummary` carries what it found.
    package private(set) var refusal: String?

    /// What the shell-ratio self-check said about the accepted estimate.
    /// `.notSelfChecked` is deliberately surfaced rather than folded into a
    /// pass: it is the state in which the single-shell assumption is least
    /// safe (docs/q-calibration-design.md §3.2).
    package var shellCheck: QCalibrationShellCheck? { estimate?.shellCheck }

    /// One line for the calibration panel, or nil when there is nothing to say.
    /// Deliberately phrased as what WAS checked, not as reassurance.
    /// **Reports; does not judge.** A fixed 3% pass/fail threshold once
    /// refused a case accurate to 1.2% (refuted by Gate B) — so the measured
    /// numbers are shown and the reader judges, not a threshold.
    ///
    /// The position count is part of the claim, not decoration: a median over
    /// three scan positions and one over a hundred thousand are different
    /// statements, and nothing else here said which it was.
    package var selfCheckSummary: String? {
        switch estimate?.shellCheck {
        case .measured(let observed, let expected, let positions):
            return String(
                format: "Shell ratio %.3f measured against %.3f predicted (%.1f%% apart, %d positions)",
                observed, expected, abs(observed / expected - 1) * 100, positions
            )
        case .notSelfChecked(let reason):
            return "Not self-checked — \(reason)"
        case nil:
            return nil
        }
    }

    package func record(_ estimate: QCalibrationEstimate) {
        self.estimate = estimate
        self.refusal = nil
    }

    package func record(refusal: String) {
        self.estimate = nil
        self.refusal = refusal
    }

    /// Cleared on every path that changes what is loaded — an estimate made
    /// against dataset A must never leak beside dataset B. A sibling seam
    /// once missed a path despite covering `release()` (Gate B,
    /// `SessionGates.sidecarRestoreFailure`): audit every path, not just the
    /// obvious one.
    package func clear() {
        estimate = nil
        refusal = nil
    }
}
