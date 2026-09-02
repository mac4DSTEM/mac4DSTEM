//
//  QCalibrationRun.swift
//  Role: The last reciprocal-pixel calibration attempt — its estimate, what the
//        estimator's own plausibility checks said, and why it was refused if it
//        was. One owner, so the number the user sees and the caveat attached to
//        it cannot come from two places.
//
//  This is S13's `AppState` seam (docs/development-process.md §7), taken under
//  rule 1: state the stage is ADDING goes into its own type from the start,
//  which is the free case — the alternative is adding four more properties to
//  the facade and then extracting something unrelated to pay the same debt.
//  Precedent: L2's `App/DatasetResidency.swift`, S7's `App/SessionGates.swift`,
//  S8's `App/StrainProduct.swift`. `AppState` holds it with NO forwarding
//  properties; view code asks this type.
//
//  Why this state has to exist at all: before S13 the estimator produced a
//  scale, `calibrateQFromCrystal` wrote it into `calibration.qPixelSize`,
//  stamped `.measuredInApp`, and put everything else into `statusText` — a
//  string that the next operation overwrites. The shell-ratio self-check has a
//  third state that is neither pass nor fail ("only one shell is detectable, so
//  the single-shell assumption is unchecked"), and a state that only ever
//  existed inside a transient status line is a state nobody can act on.
//

import Foundation
import DSTEMCore

@Observable
@MainActor
final class QCalibrationRun {

    /// The last estimate the app accepted, or nil when none has been made
    /// since the dataset changed. An estimate that was REFUSED is not stored
    /// here — `refusal` carries that case, so "there is an estimate" and "the
    /// estimate may be used" cannot drift apart.
    private(set) var estimate: QCalibrationEstimate?

    /// Why the last attempt was refused, or nil. Set from exactly one source
    /// now: the origin/metrology gate (`SessionGates`). The estimator refuses
    /// nothing since Gate B cut its thresholds (2026-08-28) — it measures and
    /// reports, and `selfCheckSummary` carries what it found.
    private(set) var refusal: String?

    /// What the shell-ratio self-check said about the accepted estimate.
    /// `.notSelfChecked` is deliberately surfaced rather than folded into a
    /// pass: it is the state in which the single-shell assumption is least
    /// safe (docs/q-calibration-design.md §3.2).
    var shellCheck: QCalibrationShellCheck? { estimate?.shellCheck }

    /// One line for the calibration panel, or nil when there is nothing to say.
    /// Deliberately phrased as what WAS checked, not as reassurance.
    /// **Reports; does not judge.** The first version rendered "self-checked"
    /// or "DISAGREES" against a 3% threshold, and Gate B refuted that
    /// threshold's derivation on 2026-08-28 — it refused a case whose Q result
    /// was accurate to 1.2%. The measurement survived review, the line through
    /// it did not, so the numbers are shown and the reader judges.
    ///
    /// The position count is part of the claim, not decoration: a median over
    /// three scan positions and one over a hundred thousand are different
    /// statements, and nothing else here said which it was.
    var selfCheckSummary: String? {
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

    func record(_ estimate: QCalibrationEstimate) {
        self.estimate = estimate
        self.refusal = nil
    }

    func record(refusal: String) {
        self.estimate = nil
        self.refusal = refusal
    }

    /// Cleared on every path that changes what is loaded — an estimate made
    /// against dataset A must never be shown beside dataset B. This is the
    /// mistake S5's Gate B caught on `SessionGates.sidecarRestoreFailure`,
    /// where "paired with every release()" turned out not to be every path.
    func clear() {
        estimate = nil
        refusal = nil
    }
}
