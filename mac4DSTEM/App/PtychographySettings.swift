import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// The single-slice ptychography input-settings seam (audit 3.2 row 5;
/// `docs/archive/development-process-2026-08-31.md` §7). Owns the
/// reconstruction's input controls only — pure view-state driving
/// `SingleslicePtychographyOptions`, no science and no result. `AppState`
/// holds it as `ptychography` without forwarding properties, the same
/// contract `WorkspaceNavigation`/`StrainProductTests` pin for
/// `navigation`/`strain`: read `appState.ptychography.iterations`, never a
/// forwarded `appState.ptychographyIterations`.
///
/// The RESULT (`AppState.singleslicePtychography`, a
/// `SingleslicePtychographyResult?`) stays on `AppState` — a published
/// product, not an input, the same split `PhaseMappingProduct` draws
/// between its `phases`/`reference`/`matching` controls and its `map`
/// result.
@Observable
final class PtychographySettings {
    var iterations = 8
    var method: SingleslicePtychographyMethod = .gradientDescent
    var stepSize: Float = 0.5
    var projectionParameter: Float = 1
    var normalizationMinimum: Float = 1
    var fixProbe = false
    var constrainObjectAmplitude = false
    var purePhaseObject = false
    var fixProbeCenterOfMass = false
    var constrainProbeAmplitude = false
    var probeAmplitudeRadius: Float = 0.5
    var probeAmplitudeWidth: Float = 0.05

    // The probe the reconstruction starts from (lane R1, 2026-09-30). `defocusAngstrom` is py4DSTEM's `defocus` argument
    // (ComplexProbe C10 = -defocus); the two astigmatism numbers are the parallax fit's own cartesian C12a/C12b (same sign, see
    // `PtychographyProbeAberrations`). What runs is what these fields say; `useParallaxFit` is the only thing that fills them
    // from a fit, and it does so by writing them here.
    var defocusAngstrom: Double = 0
    var c12aAngstrom: Double = 0
    var c12bAngstrom: Double = 0
    /// Whether the next `useParallaxFit` also takes the fit's terms beyond defocus and two-fold astigmatism (C21, C23).
    var includeHigherOrderFit = false
    /// The higher-order terms the last `useParallaxFit` took (empty unless `includeHigherOrderFit` was on then); the next run
    /// adds them to the probe.
    private(set) var higherOrderTerms: [PtychographyProbeAberrations.HigherOrderTerm] = []

    /// Take a recorded probe back (saved-control rehydration). The toggle follows the terms, so the fields never show a
    /// fit's higher-order terms with the toggle off.
    func setProbe(_ probe: RecordedPtychographyProbe) {
        defocusAngstrom = probe.defocusAngstrom
        c12aAngstrom = probe.c12aAngstrom
        c12bAngstrom = probe.c12bAngstrom
        higherOrderTerms = probe.higherOrder.map {
            .init(radialOrder: $0.radialOrder, angularOrder: $0.angularOrder, component: $0.component,
                  coefficientAngstrom: $0.coefficientAngstrom)
        }
        includeHigherOrderFit = !higherOrderTerms.isEmpty
    }

    /// The aberrations the next run builds its probe with.
    var probeAberrations: PtychographyProbeAberrations {
        PtychographyProbeAberrations(
            defocusAngstrom: defocusAngstrom, c12aAngstrom: c12aAngstrom, c12bAngstrom: c12bAngstrom,
            higherOrder: higherOrderTerms
        )
    }

    /// Seed the probe from a parallax aberration fit: defocus = -C1. The fit's C1 IS the probe's C10 and `defocus` is -C10
    /// (py4DSTEM's forward model, utils.py:159-160; E1: its Parallax returns C1 = -508.67 for a probe built at defocus +500), so a
    /// fit that reports C1 = +663.6 Å gives defocus -663.6 Å. The gold-on-carbon tutorial does the same; the MoS2 notebooks pass
    /// +C1 at about 50 Å. Holds on the rotation branch the fit used: a 180° R-Q rotation flips every coefficient (use +C1 there;
    /// the wrong branch gives a conjugated object) and this does not check - the ptychography runs with
    /// `calibration.rotationRad`, this never reads the fit's. Astigmatism (and, with `includeHigherOrderFit`, the higher terms)
    /// carry over with the fit's own signs, verified for transpose = false only; the higher terms are unverified (py4DSTEM's own
    /// fit returned 0 for a planted C21 = 8000 Å). Returns how many higher-order terms were taken.
    @discardableResult
    func useParallaxFit(
        lowOrder: ParallaxAberrationFitResult,
        higherOrder: ParallaxHigherOrderAberrationFitResult?
    ) -> Int {
        var defocus = -lowOrder.c1Angstrom
        var c12a = lowOrder.c12aAngstrom
        var c12b = lowOrder.c12bAngstrom
        var extra = [PtychographyProbeAberrations.HigherOrderTerm]()
        if includeHigherOrderFit, let fit = higherOrder {
            // The recursive fit refines defocus and astigmatism together with the higher terms: take them all from it, so the
            // probe is one fit's set, not two fits' numbers.
            for (term, coefficient) in zip(fit.terms, fit.coefficientsAngstrom) {
                switch (term.radialOrder, term.angularOrder, term.component) {
                case (1, 0, 0): defocus = -coefficient
                case (1, 2, 0): c12a = coefficient
                case (1, 2, 1): c12b = coefficient
                default:
                    extra.append(.init(
                        radialOrder: term.radialOrder, angularOrder: term.angularOrder,
                        component: term.component, coefficientAngstrom: coefficient
                    ))
                }
            }
        }
        defocusAngstrom = defocus
        c12aAngstrom = c12a
        c12bAngstrom = c12b
        higherOrderTerms = extra
        return extra.count
    }
}
