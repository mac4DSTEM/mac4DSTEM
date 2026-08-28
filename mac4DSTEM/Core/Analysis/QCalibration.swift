//
//  QCalibration.swift
//  Role: Robust first-shell reciprocal-pixel calibration from detected Bragg
//        vectors and a known crystal reflection radius, with the estimator's
//        own plausibility checks (v2 S13) so a scale it cannot justify is
//        refused rather than stamped `.measuredInApp`.
//

import Foundation

/// What the estimator's second shell measured, when one could be read.
///
/// **This REPORTS; it does not judge.** v2 S13 shipped `.agreed`/`.disagreed`
/// against a 3% threshold and Gate B refuted the threshold's derivation the
/// same day: measured on `sim_Au`, a 1 px origin displacement — a Q result
/// accurate to 1.2% — scores 4.07% and would have been refused, so the
/// "sound" side of the gap the threshold was centred in was mis-identified.
/// The *measurement* survived review (the derived separation reads 1.148
/// against a predicted 1.155 on `sim_Au`, where the design's unseparated
/// version read 1.020); only the line drawn through it did not. So the numbers
/// are surfaced and the reader judges, until a design pass with real
/// false-refusal data can place a threshold defensibly.
///
/// `.notSelfChecked` is **not a pass**. When only one shell is detectable the
/// single-shell assumption is at its least safe — thin or weakly-scattering
/// samples are exactly the case where the first shell goes missing and the
/// second is read as the first — so the state is reported rather than folded
/// into "fine" (`docs/q-calibration-design.md` §3.2).
nonisolated enum QCalibrationShellCheck: Sendable, Equatable {
    /// The two innermost distinct shells, as measured, beside what the crystal
    /// predicts. `positions` is how many scan positions contributed an r₂ —
    /// carried because a median over 3 positions and one over 100 000 are not
    /// the same claim, and nothing else in the estimate says which it was.
    case measured(observedRatio: Double, expectedRatio: Double, positions: Int)
    case notSelfChecked(String)

    /// Relative disagreement with the crystal, or nil when nothing was checked.
    /// **No threshold is applied to this anywhere** — see the type's note.
    var mismatch: Double? {
        guard case .measured(let observed, let expected, _) = self,
              expected != 0 else { return nil }
        return abs(observed / expected - 1)
    }
}

nonisolated struct QCalibrationEstimate: Sendable {
    let invAngstromPerPixel: Double
    let observedRadiusPixels: Double
    let referenceRadiusInvAngstrom: Double
    let medianAbsoluteDeviationPixels: Double
    let sampleCount: Int

    /// Median radius of the innermost peak that is separated far enough from
    /// the first to belong to a different shell, when one exists.
    let secondShellRadiusPixels: Double?
    let shellCheck: QCalibrationShellCheck

    /// `medianAbsoluteDeviationPixels / observedRadiusPixels`. Computed and
    /// exposed because it is free and a later design pass will need it; **no
    /// threshold is applied to it** — see the note on `KnownCrystalQCalibration`.
    var shellConsistency: Double {
        observedRadiusPixels > 0 ? medianAbsoluteDeviationPixels / observedRadiusPixels : .infinity
    }
}

nonisolated enum KnownCrystalQCalibration {

    // MARK: - Why there are no thresholds here (v2 S13, after Gate B)
    //
    // This session shipped three — `maximumShellConsistency = 0.07`,
    // `minimumShellRadiusRatioOfProbe = 1.0`, `maximumShellRatioMismatch =
    // 0.03` — each presented as "the geometric centre of a measured gap", and
    // an adversarial review refuted the derivation of all three on the same
    // day. Recorded here so the next attempt does not repeat it:
    //
    // 1. **The measurements were taken against a tree that no longer existed.**
    //    The experiment ran before `tiledRun` was changed to return a trimmed
    //    fit, so the baseline surface it perturbed, and the origin-gate column
    //    that justified leaving the consistency threshold permissive, are not
    //    reproducible from the shipping code. Re-measured: the recorded
    //    MAD/observed values were wrong by ~35%, and the gate the layering
    //    argument leaned on cannot fire in that experiment at all.
    // 2. **The "sound" side of one gap contradicted the other.** The shell
    //    consistency gap was anchored on `sim_Au` at 1 px of jitter (Q accurate
    //    to 1.2%); the shell-ratio threshold refuses that same case at 4.07%.
    //    Two thresholds derived from mutually contradictory definitions of
    //    sound.
    // 3. **Geometric centring is not invariant under reparametrisation.**
    //    Centring the deviation gives 3%; centring the ratio — the same
    //    measurement, a different chart — gives 28.9%. A rule whose answer
    //    depends on which monotone transform you call "the statistic" is a
    //    number picked and then justified.
    // 4. **The probe radius, which one threshold was expressed in, is itself
    //    unreliable**: `OriginCalibration.probeSize` counts Bragg disks as
    //    probe area and over-measures 2.15× on the app's own demo
    //    (docs/open-items.md, owed a Gate D session).
    //
    // What a later session needs before placing a line here: false-refusal
    // rates on real data, not one dataset under synthetic perturbation, and a
    // placement rule stated on the statistic it will actually gate.

    /// Estimate Q scale from the median innermost non-central reflection at
    /// each scan position. The per-position statistic avoids dense patterns
    /// dominating the fit; median/MAD make isolated detection failures benign.
    ///
    /// `secondShellRadiusInvAngstrom` and `probeRadiusPixels` are **not
    /// optional-with-a-default on purpose**: a caller that cannot supply them
    /// gets an estimate whose checks silently did not run, and this repo's
    /// documented failure mode is exactly a check that was believed to have
    /// happened. Pass nil explicitly and the estimate says `.notSelfChecked`.
    ///
    /// **This function refuses nothing.** It reports what it measured; see
    /// `QCalibrationShellCheck`.
    static func estimate(
        bragg: BraggVectors,
        origin: (x: Float, y: Float),
        referenceRadiusInvAngstrom: Double,
        secondShellRadiusInvAngstrom: Double?,
        probeRadiusPixels: Double?,
        minimumRadiusPixels: Float = 2
    ) -> QCalibrationEstimate? {
        guard referenceRadiusInvAngstrom.isFinite,
              referenceRadiusInvAngstrom > 0 else { return nil }

        // The expected ratio, and from it the separation that makes r₂ a
        // DIFFERENT shell rather than another equivalent of the same one.
        let expectedRatio = secondShellRadiusInvAngstrom.flatMap { second -> Double? in
            let ratio = second / referenceRadiusInvAngstrom
            return ratio.isFinite && ratio > 1 ? ratio : nil
        }
        // Half the gap the crystal itself predicts. DERIVED, not chosen: at
        // this separation `sim_Au` reads 1.14814 against an expected 1.15470
        // with 99.7% of positions still contributing, where the design's
        // unseparated version read 1.02048 — a shell compared against itself,
        // because several symmetry equivalents of one |g| are excited at once.
        let separation = expectedRatio.map { ($0 - 1) / 2 }

        var firstRadii: [Double] = []
        var secondRadii: [Double] = []
        firstRadii.reserveCapacity(bragg.peaks.count)
        for peaks in bragg.peaks {
            let radii = peaks.compactMap { peak -> Double? in
                let dx = peak.x - origin.x
                let dy = peak.y - origin.y
                let radius = (dx * dx + dy * dy).squareRoot()
                return radius.isFinite && radius > minimumRadiusPixels ? Double(radius) : nil
            }.sorted()
            guard let first = radii.first else { continue }
            firstRadii.append(first)
            if let separation,
               let second = radii.first(where: { $0 > first * (1 + separation) }) {
                secondRadii.append(second)
            }
        }
        guard !firstRadii.isEmpty else { return nil }
        let observed = median(firstRadii)
        guard observed.isFinite, observed > 0 else { return nil }
        let mad = median(firstRadii.map { abs($0 - observed) })

        // --- The shell-ratio measurement (design §3.2, as repaired) ------
        //
        // STATED ASYMMETRY: r₂ is SELECTED as at least (1 + separation) times
        // r₁, so the measured ratio is bounded below by construction. The
        // original comment here claimed that made a too-small ratio
        // undetectable; Gate B refuted that too — the floor is (1+e)/2 while
        // the interesting comparisons sit near e, so a low-side window exists
        // and is crystal-dependent (for silicon it spans 19% low to 3% low).
        // The bound is real; the conclusion drawn from it was not.
        let secondObserved = secondRadii.isEmpty ? nil : median(secondRadii)
        let shellCheck: QCalibrationShellCheck
        if let expectedRatio, let secondObserved, secondObserved.isFinite {
            shellCheck = .measured(
                observedRatio: secondObserved / observed,
                expectedRatio: expectedRatio,
                positions: secondRadii.count
            )
        } else if expectedRatio == nil {
            shellCheck = .notSelfChecked("this crystal has only one allowed shell within range")
        } else {
            shellCheck = .notSelfChecked("only one shell is detectable, so the assumption that the "
                + "innermost detected peak is the innermost allowed reflection is unchecked")
        }

        return QCalibrationEstimate(
            invAngstromPerPixel: referenceRadiusInvAngstrom / observed,
            observedRadiusPixels: observed,
            referenceRadiusInvAngstrom: referenceRadiusInvAngstrom,
            medianAbsoluteDeviationPixels: mad,
            sampleCount: firstRadii.count,
            secondShellRadiusPixels: secondObserved,
            shellCheck: shellCheck
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
