import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// The single-slice ptychography input-settings seam (audit 3.2 row 5;
/// `docs/archive/development-process-2026-08-31.md` §7 — one seam per session, extracted at a
/// green boundary). Owns the reconstruction's input controls only — pure
/// view-state driving `SingleslicePtychographyOptions`, no science and no
/// result. `AppState` holds it as `ptychography` without forwarding
/// properties, the same contract `WorkspaceNavigation`/`StrainProductTests`
/// pin for `navigation`/`strain`: read `appState.ptychography.iterations`,
/// never a forwarded `appState.ptychographyIterations`.
///
/// The RESULT (`AppState.singleslicePtychography`, a `SingleslicePtychographyResult?`)
/// stays on `AppState` — it is a published product, not an input, the same
/// split `PhaseMappingProduct` draws between its `phases`/`reference`/`matching`
/// controls and its `map` result.
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
}
