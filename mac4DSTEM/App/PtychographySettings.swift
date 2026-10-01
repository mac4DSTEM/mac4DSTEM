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
    var stepSize: Float = 0.5
    var normalizationMinimum: Float = 1
    var fixProbe = false
    /// On by default, as py4DSTEM does for a complex object (`_object_threshold_constraint`, every iteration; owner, 2026-10-01).
    var constrainObjectAmplitude = true
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

    /// Take a recorded probe back (saved-control rehydration): defocus and the two astigmatism numbers. The probe has no
    /// higher-order terms (the "Take higher-order terms" control was removed 2026-10-01: on the default alignment the fit's
    /// C21/C23 are unobservable), so a stored C21/C23 is NOT applied; `applySelectedSavedControls` says so.
    func setProbe(_ probe: RecordedPtychographyProbe) {
        defocusAngstrom = probe.defocusAngstrom
        c12aAngstrom = probe.c12aAngstrom
        c12bAngstrom = probe.c12bAngstrom
    }

    /// The aberrations the next run builds its probe with.
    var probeAberrations: PtychographyProbeAberrations {
        PtychographyProbeAberrations(
            defocusAngstrom: defocusAngstrom, c12aAngstrom: c12aAngstrom, c12bAngstrom: c12bAngstrom
        )
    }

    /// Seed the probe from a parallax aberration fit: defocus = -C1. The fit's C1 IS the probe's C10 and `defocus` is -C10
    /// (py4DSTEM's forward model, utils.py:159-160; E1: its Parallax returns C1 = -508.67 for a probe built at defocus +500), so a
    /// fit that reports C1 = +663.6 Å gives defocus -663.6 Å. The gold-on-carbon tutorial does the same; the MoS2 notebooks pass
    /// +C1 at about 50 Å. Holds on the rotation branch the fit used: a 180° R-Q rotation flips every coefficient (use +C1 there;
    /// the wrong branch gives a conjugated object) and this does not check - the ptychography runs with
    /// `calibration.rotationRad`, this never reads the fit's. Astigmatism carries over with the fit's own signs, verified for
    /// transpose = false only. Only the low-order fit is used; the higher-order terms (C21, C23) are not taken.
    func useParallaxFit(lowOrder: ParallaxAberrationFitResult) {
        defocusAngstrom = -lowOrder.c1Angstrom
        c12aAngstrom = lowOrder.c12aAngstrom
        c12bAngstrom = lowOrder.c12bAngstrom
    }
}
