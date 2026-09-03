import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Diagnostic and fitting controls that supplement the single readiness path,
/// as two collapsed sections of the column's grouped `Form`. Physical Q/R
/// values are intentionally edited only in the readiness rows, so the same
/// value, unit, provenance, and consequence cannot drift between duplicate
/// controls.
struct CalibrationDetailsView: View {
    @Environment(AppState.self) private var appState
    @State private var showsDiagnostics = false
    @State private var showsEllipse = false

    /// core-data-05 (S22a ride-along): the excluded-fraction disclosure obeys
    /// the shared policy floor, not the retired 0.5% — readiness and the
    /// refusal path already use `excludedFractionDisclosureFloor`, and Gate B
    /// measured 0.5% as inside the trim's own false-positive range.
    static func disclosesExcludedFraction(_ excluded: Float) -> Bool {
        excluded > Calibration.excludedFractionDisclosureFloor
    }

    var body: some View {
        // v2.5 step 7c slice 2: the fit settings bind to their owner.
        @Bindable var session = appState.calibrationSession
        let calibration = appState.calibrationSession.calibration
        Section("Fit diagnostics & advanced correction", isExpanded: $showsDiagnostics) {
            LabeledContent("Aperture center", value: calibration.originProvenance.displayName)
                .help("Source of the center used by the virtual-detector aperture. Per-position fitted origins are reported separately.")

            if appState.canRestoreFittedOrigin {
                Button {
                    appState.restoreFittedOrigin()
                } label: {
                    Label("Restore Fitted Origin", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(appState.isBusy)
                .help("Reinstates the fitted per-position origin maps that the manual aperture center set aside, and recenters the aperture on their mean.")
            }

            Picker("Origin fit", selection: $session.originFitFunction) {
                ForEach(OriginFitFunction.allCases) { fit in
                    Text(fit.rawValue).tag(fit)
                }
            }
            Button {
                Task { await appState.calibrateOrigin() }
            } label: {
                Label("Calibrate Origin", systemImage: "scope")
            }
            .disabled(appState.isBusy)
            Button {
                Task { await appState.calibrateRotation() }
            } label: {
                Label("Measure R–Q Rotation", systemImage: "rotate.3d")
            }
            .disabled(appState.isBusy)

            if let radius = calibration.probeRadius {
                LabeledContent("Probe radius", value: String(format: "%.1f px", radius))
            }
            // v2 S13: the residual the GATE judged, which is the robust one
            // where a robust fit ran — one number for one decision.
            if let residual = calibration.judgedOriginResidual {
                LabeledContent("Fit residual", value: String(format: "%.3f px RMS", residual))
            }
            // The excluded fraction, where the reader who sees the number
            // sees it (2026-08-28): "2.19 px over 73% of positions" is a
            // different claim from "2.19 px over all of them".
            if let excluded = calibration.origin?.excludedFraction,
               Self.disclosesExcludedFraction(excluded) {
                LabeledContent(
                    "Positions used",
                    value: String(format: "%.0f%% (%.0f%% excluded as outliers)",
                                  Double(1 - excluded) * 100, Double(excluded) * 100)
                )
                .help("The origin fit is robust: scan positions whose measured origin sits far "
                    + "from the fitted surface are excluded and the surface refitted. Excluding "
                    + "nothing means there was no outlier tail to remove, not that every "
                    + "position measured well.")
            }
            if let summary = appState.qCalibration.selfCheckSummary {
                LabeledContent("Q shell check", value: summary)
                    .help("The reciprocal scale assumes the innermost detected peak is the "
                        + "innermost allowed reflection. With two shells visible the app checks "
                        + "that assumption against the crystal; with one it cannot, and says so "
                        + "rather than passing silently.")
            }
            if let rotation = calibration.rotationRad {
                let transposed = (calibration.transposeQR ?? false) ? " ⊤" : ""
                LabeledContent(
                    "R–Q rotation",
                    value: String(format: "%.1f°%@", rotation * 180 / .pi, transposed)
                )
                Button {
                    appState.flipRotation180()
                } label: {
                    Label("Flip 180°", systemImage: "arrow.uturn.left.circle")
                }
                .help("The curl method cannot distinguish θ from θ + 180°. If iDPC contrast is inverted, flip it here.")
            }
        }

        Section("Ellipse correction", isExpanded: $showsEllipse) {
            // Value, unit: one row per radius, because two fields beside one
            // label do not fit the column's minimum width (rule 5).
            LabeledContent("Fit annulus inner") {
                NumericField(
                    title: "Inner fit radius",
                    value: $session.ellipseFitInnerRadius,
                    format: .number.precision(.fractionLength(0...2)),
                    unit: "px"
                )
            }
            LabeledContent("Fit annulus outer") {
                NumericField(
                    title: "Outer fit radius",
                    value: $session.ellipseFitOuterRadius,
                    format: .number.precision(.fractionLength(0...2)),
                    unit: "px"
                )
            }
            Button {
                Task { await appState.calibrateEllipse() }
            } label: {
                Label("Fit Ellipse", systemImage: "oval")
            }
            .disabled(appState.isBusy)
            .help("Fits the detector-shaped Bragg map when displayed; otherwise fits the scan-mean diffraction pattern. The annulus must contain a ring with broad angular coverage.")

            if calibration.hasEllipse,
               let a = calibration.ellipseA,
               let b = calibration.ellipseB,
               let theta = calibration.ellipseTheta {
                LabeledContent(
                    "Correction",
                    value: String(format: "a %.4g · b %.4g · θ %.1f°", a, b, theta * 180 / .pi)
                )
                .help("Applied to calibrated Bragg maps, strain, and ACOM in py4DSTEM's qx/qy convention.")
                if let fit = appState.calibrationSession.lastEllipseFit {
                    LabeledContent("Model", value: fit.model.rawValue)
                    LabeledContent(
                        "Residual",
                        value: String(format: "%.3f · %d/36 sectors", fit.normalizedResidual, fit.occupiedAngularBins)
                    )
                    if let profile = fit.profile {
                        LabeledContent(
                            "Ring widths",
                            value: String(format: "inner %.3g · outer %.3g px", profile.innerSigma, profile.outerSigma)
                        )
                    } else if let reason = fit.profileFallbackReason {
                        Text("Profile fallback: \(reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
