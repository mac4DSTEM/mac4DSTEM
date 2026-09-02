import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Diagnostic and fitting controls that supplement the single readiness path.
/// Physical Q/R values are intentionally edited only in the readiness rows,
/// so the same value, unit, provenance, and consequence cannot drift between
/// duplicate controls.
struct CalibrationDetailsView: View {
    @Environment(AppState.self) private var appState

    /// core-data-05 (S22a ride-along): the excluded-fraction disclosure obeys
    /// the shared policy floor, not the retired 0.5% — readiness (:277) and
    /// the refusal path (:742) already use `excludedFractionDisclosureFloor`,
    /// and Gate B measured 0.5% as inside the trim's own false-positive range.
    static func disclosesExcludedFraction(_ excluded: Float) -> Bool {
        excluded > Calibration.excludedFractionDisclosureFloor
    }

    var body: some View {
        @Bindable var appState = appState
        DisclosureGroup("Fit diagnostics & advanced correction") {
            LabeledContent(
                "Aperture center",
                value: appState.calibration.originProvenance.displayName
            )
            .font(.caption)
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

            Picker("Origin fit", selection: $appState.originFitFunction) {
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

            if let radius = appState.calibration.probeRadius {
                LabeledContent("Probe radius", value: String(format: "%.1f px", radius))
                    .font(.caption)
            }
            // v2 S13: the residual the GATE judged, which is the robust one
            // where a robust fit ran. Showing `rmsResidual` here while the
            // verdict came from `robustResidual` would put two different
            // numbers for one decision in front of the user.
            if let residual = appState.calibration.judgedOriginResidual {
                LabeledContent("Fit residual", value: String(format: "%.3f px RMS", residual))
                    .font(.caption)
            }
            // The excluded fraction, carried where the reader who sees the
            // number sees it (the release owner's decision, 2026-08-28):
            // "2.19 px over 73% of positions" is a different claim from
            // "2.19 px over all of them".
            if let excluded = appState.calibration.origin?.excludedFraction,
               Self.disclosesExcludedFraction(excluded) {
                LabeledContent(
                    "Positions used",
                    value: String(format: "%.0f%% (%.0f%% excluded as outliers)",
                                  Double(1 - excluded) * 100, Double(excluded) * 100)
                )
                .font(.caption)
                .help("The origin fit is robust: scan positions whose measured origin sits far "
                    + "from the fitted surface are excluded and the surface refitted. Excluding "
                    + "nothing means there was no outlier tail to remove, not that every "
                    + "position measured well.")
            }
            if let summary = appState.qCalibration.selfCheckSummary {
                LabeledContent("Q shell check", value: summary)
                    .font(.caption)
                    .help("The reciprocal scale assumes the innermost detected peak is the "
                        + "innermost allowed reflection. With two shells visible the app checks "
                        + "that assumption against the crystal; with one it cannot, and says so "
                        + "rather than passing silently.")
            }
            if let rotation = appState.calibration.rotationRad {
                let transposed = (appState.calibration.transposeQR ?? false) ? " ⊤" : ""
                LabeledContent(
                    "R–Q rotation",
                    value: String(format: "%.1f°%@", rotation * 180 / .pi, transposed)
                )
                .font(.caption)
                Button {
                    appState.flipRotation180()
                } label: {
                    Label("Flip 180°", systemImage: "arrow.uturn.left.circle")
                }
                .help("The curl method cannot distinguish θ from θ + 180°. If iDPC contrast is inverted, flip it here.")
            }

            ellipseControls(appState: appState)
        }
    }

    @ViewBuilder
    private func ellipseControls(appState: AppState) -> some View {
        @Bindable var appState = appState
        DisclosureGroup("Ellipse correction") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fit annulus").font(.caption)
                HStack {
                    TextField(
                        "inner", value: $appState.ellipseFitInnerRadius,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    Text("to").font(.caption2).foregroundStyle(.secondary)
                    TextField(
                        "outer", value: $appState.ellipseFitOuterRadius,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    Text("px").font(.caption2).foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
            }
            Button {
                Task { await appState.calibrateEllipse() }
            } label: {
                Label("Fit Ellipse", systemImage: "oval")
            }
            .disabled(appState.isBusy)
            .help("Fits the detector-shaped Bragg map when displayed; otherwise fits the scan-mean diffraction pattern. The annulus must contain a ring with broad angular coverage.")

            if appState.calibration.hasEllipse,
               let a = appState.calibration.ellipseA,
               let b = appState.calibration.ellipseB,
               let theta = appState.calibration.ellipseTheta {
                LabeledContent(
                    "Correction",
                    value: String(format: "a %.4g · b %.4g · θ %.1f°", a, b, theta * 180 / .pi)
                )
                .font(.caption)
                .help("Applied to calibrated Bragg maps, strain, and ACOM in py4DSTEM's qx/qy convention.")
                if let fit = appState.lastEllipseFit {
                    LabeledContent("Model", value: fit.model.rawValue).font(.caption)
                    LabeledContent(
                        "Residual",
                        value: String(
                            format: "%.3f · %d/36 sectors",
                            fit.normalizedResidual, fit.occupiedAngularBins
                        )
                    )
                    .font(.caption)
                    if let profile = fit.profile {
                        LabeledContent(
                            "Ring widths",
                            value: String(
                                format: "inner %.3g · outer %.3g px",
                                profile.innerSigma, profile.outerSigma
                            )
                        )
                        .font(.caption)
                    } else if let reason = fit.profileFallbackReason {
                        Text("Profile fallback: \(reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
