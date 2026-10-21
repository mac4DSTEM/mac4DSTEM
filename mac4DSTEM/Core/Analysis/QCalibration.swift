//
//  QCalibration.swift
//  Role: Robust first-shell reciprocal-pixel calibration from detected Bragg
//        vectors and a known crystal reflection radius, with the estimator's
//        own plausibility checks (v2 S13) so a scale it cannot justify is
//        refused rather than stamped `.measuredInApp`.
//

import Foundation
import DiffractoGeometry

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
/// into "fine" (`../_archive/mac4DSTEM/docs/q-calibration-design.md` §3.2).
package typealias QCalibrationShellCheck = LinearScaleShellCheck

extension LinearScaleShellCheck {
    /// The one phrase every surface uses when the assignment was never
    /// checked — the Q readiness row, Prepare's "Q shell check" row — or nil
    /// when a ratio was measured (its numbers are shown instead, unjudged).
    ///
    /// Owner decision (ADR 050, "Q calibration picks the wrong ring"; lane Q,
    /// 2026-09-30): "unchecked" is neither a pass nor a refusal. The scale is
    /// still used and still `.measuredInApp`; the row says what was not done.
    /// THRESHOLD-FREE: it fires on `.notSelfChecked` alone. A "disagrees"
    /// line was measured and did NOT ship — see the note on
    /// `KnownCrystalQCalibration` (5).
    package var uncheckedNote: String? {
        guard case .notSelfChecked(let reason) = self else { return nil }
        return "Shell ratio unchecked — \(reason)"
    }
}

package nonisolated struct QCalibrationEstimate: Sendable {
    package let invAngstromPerPixel: Double
    package let observedRadiusPixels: Double
    package let referenceRadiusInvAngstrom: Double
    package let medianAbsoluteDeviationPixels: Double
    package let sampleCount: Int

    /// Median radius of the innermost peak that is separated far enough from
    /// the first to belong to a different shell, when one exists.
    package let secondShellRadiusPixels: Double?
    package let shellCheck: QCalibrationShellCheck
    /// Median number of same-shell equivalents averaged per position — the k
    /// of the order-statistic bias the cluster estimator removes. 1 means the
    /// estimate rests on single peaks and the cluster brought nothing.
    package let sameShellPeaksPerPosition: Double

    /// `medianAbsoluteDeviationPixels / observedRadiusPixels`. Computed and
    /// exposed because it is free and a later design pass will need it; **no
    /// threshold is applied to it** — see the note on `KnownCrystalQCalibration`.
    package var shellConsistency: Double {
        observedRadiusPixels > 0 ? medianAbsoluteDeviationPixels / observedRadiusPixels : .infinity
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(invAngstromPerPixel: Double, observedRadiusPixels: Double, referenceRadiusInvAngstrom: Double, medianAbsoluteDeviationPixels: Double, sampleCount: Int, secondShellRadiusPixels: Double?, shellCheck: QCalibrationShellCheck, sameShellPeaksPerPosition: Double) {
        self.invAngstromPerPixel = invAngstromPerPixel
        self.observedRadiusPixels = observedRadiusPixels
        self.referenceRadiusInvAngstrom = referenceRadiusInvAngstrom
        self.medianAbsoluteDeviationPixels = medianAbsoluteDeviationPixels
        self.sampleCount = sampleCount
        self.secondShellRadiusPixels = secondShellRadiusPixels
        self.shellCheck = shellCheck
        self.sameShellPeaksPerPosition = sameShellPeaksPerPosition
    }
}

package nonisolated enum KnownCrystalQCalibration {

    // MARK: - Why there are no thresholds here (after Gate B)
    //
    // An earlier attempt shipped three — `maximumShellConsistency = 0.07`,
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
    // 5. **Measured again, on the app's own path, and still no line (lane Q,
    //    2026-09-30, `../_archive/mac4DSTEM/tools/q-shell-probe`; run it to reproduce).** The decided
    //    rule: a "disagrees" line sits at 2H only if 2H < M/2, H = the largest
    //    |observed/expected − 1| among cubes whose Q is within 3 % of truth
    //    (taking the recorded 4.07 % of `sim_Au` at a 1 px displacement), M =
    //    the smallest among mis-assigned cubes. Healthy: `sim_Au` 2.4 %. Mis-
    //    assigned (Q 12.5–13.5 % low, the (200) ring read as (111), the Al
    //    [001] majority having no {111}): the demo cube 22.4 %, Thronsen A
    //    22.5 %, the owner's raw 060 stride-3 cube 18.4 % (23.7 % with his
    //    ellipse applied), his binned 060 19.0 %; and `polycrystal_2D_WS2` 13.3
    //    % at Q 55 % low (the reference is (0002); the second "shell" is (0004),
    //    expected 2.000, seen 1.733). So 2H = 8.1 % against M/2 = 6.7 %: not
    //    met, and the one healthy cube is n = 1. The mismatch stays a NUMBER
    //    (`mismatch`, the status line, the "Q shell check" row); only the
    //    threshold-free `.notSelfChecked` reading is worded "unchecked"
    //    (`uncheckedNote`).
    //
    // What a later session needs before placing a line here: false-refusal
    // rates on real data, not one dataset under synthetic perturbation, and a
    // placement rule stated on the statistic it will actually gate.

    /// Estimate Q scale from the median innermost non-central reflection at each scan position: the radii of each
    /// position's peaks from `origin` go to DiffractoKit's `LinearScale.estimate` (the same-shell cluster mean per
    /// position, median over positions, MAD and the second-shell ratio; the arithmetic moved there in 0.8.0).
    /// The per-position statistic avoids dense patterns dominating the fit; median/MAD make isolated detection
    /// failures benign.
    ///
    /// `secondShellRadiusInvAngstrom` is **not optional-with-a-default on purpose**: a caller that cannot supply it
    /// gets an estimate whose check silently did not run. Pass nil explicitly and the estimate says `.notSelfChecked`.
    /// `probeRadiusPixels` is kept in the signature for the callers; no check reads it (see note 4 above).
    ///
    /// **This function refuses nothing.** It reports what it measured; see `QCalibrationShellCheck`.
    package static func estimate(
        bragg: BraggVectors,
        origin: (x: Float, y: Float),
        referenceRadiusInvAngstrom: Double,
        secondShellRadiusInvAngstrom: Double?,
        probeRadiusPixels: Double?,
        minimumRadiusPixels: Float = 2
    ) -> QCalibrationEstimate? {
        // Float32 radii as the detector measured them, widened exactly; the kit drops non-finite ones and those at or
        // below the minimum (the beam itself).
        let radii = bragg.peaks.map { peaks in
            peaks.map { peak -> Double in
                let dx = peak.x - origin.x
                let dy = peak.y - origin.y
                return Double((dx * dx + dy * dy).squareRoot())
            }
        }
        guard let scale = LinearScale.estimate(
            radiiPerPosition: radii,
            referenceRadiusInvAngstrom: referenceRadiusInvAngstrom,
            secondShellRadiusInvAngstrom: secondShellRadiusInvAngstrom,
            minimumRadiusPixels: Double(minimumRadiusPixels)) else { return nil }
        return QCalibrationEstimate(
            invAngstromPerPixel: scale.invAngstromPerPixel,
            observedRadiusPixels: scale.observedRadiusPixels,
            referenceRadiusInvAngstrom: scale.referenceRadiusInvAngstrom,
            medianAbsoluteDeviationPixels: scale.medianAbsoluteDeviationPixels,
            sampleCount: scale.sampleCount,
            secondShellRadiusPixels: scale.secondShellRadiusPixels,
            shellCheck: scale.shellCheck,
            sameShellPeaksPerPosition: scale.sameShellPeaksPerPosition)
    }
}
