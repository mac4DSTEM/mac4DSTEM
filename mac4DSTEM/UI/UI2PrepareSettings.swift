import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Prepare's controls, as Sections of the inspector's Settings tab.
///
/// The migration of `UI/PrepareSidebar`, `UI/CalibrationReadinessView` and
/// `UI/CalibrationDetailsView` into UI2. Everything scientific is carried over
/// unchanged — the same properties, the same provenance vocabulary, the same
/// formats, the same refusals and the same accessibility identifiers. Two
/// things are presentation-only and did change:
///
/// - Every readiness row is a real `LabeledContent` now. The old view built
///   the row by hand (`VStack` + `Spacer` + `fixedSize`) because it was hosted
///   in the sidebar's `List`, where `LabeledContent` laid the kind, the detail
///   and the provenance on one truncated line. In a grouped `Form` the label
///   stacks for us, so the hand-built stack is gone and the row reads the same.
/// - "Compute Mean / Max" no longer waits for the diffraction pane to be the
///   active one. The statistics are a property of the cube, not of which pane
///   has focus, and UI2 has no pane focus model.
struct UI2PrepareSettings: View {
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

    private var report: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    var body: some View {
        @Bindable var session = appState.calibrationSession
        let calibration = session.calibration

        UI2PatternStatisticsSection()

        Section("Calibration") {
            Group {
                ForEach(report.items) { item in
                    readinessRow(item)
                }
                // v2.5 step 4b: the same verdict the dataset card shows.
                let verdict = session.verdict
                Label(verdict.summary,
                      systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
                    .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calibration.readiness")

            // S22c (pipelines §7.4): the accelerating voltage is calibration
            // — DPC, parallax and ptychography all consume it — so it lives
            // with the other physical scales, not inside one consumer's
            // workflow. Identifier unchanged on purpose.
            LabeledContent("Voltage") {
                UI2NumericField(
                    "Accelerating voltage (kV)",
                    value: Binding(
                        get: { appState.calibrationSession.acceleratingVoltage ?? 0 },
                        set: appState.setManualAcceleratingVoltage
                    ),
                    format: .number.precision(.fractionLength(0...2)),
                    unit: "kV"
                )
                .accessibilityIdentifier("calibration.acceleratingVoltage")
            }
        }

        // Diagnostic and fitting controls that supplement the single readiness
        // path. Physical Q/R values are intentionally edited only in the
        // readiness rows, so the same value, unit, provenance and consequence
        // cannot drift between duplicate controls.
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
            // label do not fit the column's minimum width.
            LabeledContent("Fit annulus inner") {
                UI2NumericField(
                    "Inner fit radius",
                    value: $session.ellipseFitInnerRadius,
                    format: .number.precision(.fractionLength(0...2)),
                    unit: "px"
                )
            }
            LabeledContent("Fit annulus outer") {
                UI2NumericField(
                    "Outer fit radius",
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
                if let fit = session.lastEllipseFit {
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

    // MARK: - Readiness

    /// One calibration as a `LabeledContent` row — the kind with its status
    /// glyph and the calibrated value under it as the label, the provenance
    /// ("From file" / "Measured" / …, never demoted) as the content —
    /// followed by its warning and its action.
    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        LabeledContent {
            Text(item.status.displayName)
                .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
                .fixedSize()
        } label: {
            Label {
                Text(item.kind.rawValue)
                    .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
            } icon: {
                Image(systemName: item.status.isReady
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
            }
            // The calibrated value and its units — the scientific content of
            // the row, on screen unconditionally, wrapping never truncating
            // (S22d: the tail is the caveat). Inside a Form the label stacks
            // and the caption wraps to the column on its own.
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // `unlockSummary` says what this calibration *enables*: on hover and
        // in the accessibility description, not permanently under six rows.
        .help("\(item.detail)\n\n\(item.kind.unlockSummary)")
        .accessibilityElement(children: .contain)
        .accessibilityHint(item.kind.unlockSummary)
        .accessibilityIdentifier("calibration.item.\(item.kind.id)")

        // Outside the `!isReady` branch: an imported R scale that disagrees
        // with the filename is *ready*, and exactly the case worth a warning.
        if item.kind == .rScale, let conflict = rScaleFilenameConflict {
            Label(conflict, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("calibration.rScale.filenameConflict")
        }
        if !item.status.isReady {
            readinessAction(for: item.kind)
        }
    }

    @ViewBuilder
    private func readinessAction(for kind: CalibrationReadinessKind) -> some View {
        switch kind {
        case .originProbe:
            Button("Measure Origin & Probe") {
                Task { await appState.calibrateOrigin() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.originProbe")
        case .ellipse:
            Button("Fit Detector Ellipse") {
                Task { await appState.calibrateEllipse() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.ellipse")
        case .rotation:
            Button("Measure R–Q Rotation") {
                Task { await appState.calibrateRotation() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.rotation")
        case .qScale:
            if appState.hasCurrentBraggVectors, let model = appState.resolvedACOMModel {
                Button("Calibrate from Selected Material") {
                    Task { await appState.calibrateQFromCrystal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.action.qCrystal")
                .help("Selected ACOM phase model: \(model.displayName)")
                manualScaleRows(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: "Or enter the reciprocal pixel size by hand.",
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            } else {
                // Why the crystal route is unavailable is guidance about a
                // path you cannot take yet: on hover and in the hint.
                manualScaleRows(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: qScaleUnavailableReason,
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            }
        case .rScale:
            // R scale is the one calibration with no measurement path in the
            // app; the field is the only control offered, and the sentence
            // is on hover.
            manualScaleRows(
                value: appState.manualRPixelSize,
                units: appState.manualRPixelUnits,
                unitOptions: CalibrationUnitConversion.editableRealUnits,
                identifier: "calibration.action.rManual",
                help: "R pixel scale cannot be measured from the data — enter it from the acquisition parameters.",
                onChange: appState.setManualRPixelSize,
                onUnitChange: appState.setManualRPixelUnits
            )
        }
    }

    /// A scan-step token in the filename that disagrees with the R pixel scale
    /// actually in use, if both exist and they differ materially.
    ///
    /// File metadata rightly wins over a filename — but a user reading
    /// `…ss30nm…` while the app quietly uses an imported 49.5 nm/px gets no
    /// hint the two disagree, and R scale silently rescales every real-space
    /// axis and scale bar. This surfaces the disagreement without changing the
    /// precedence. Comparison is done in Å/px so a token in nm and a value in
    /// Å are not reported as a conflict merely for being in different units.
    private var rScaleFilenameConflict: String? {
        guard let path = appState.descriptor?.filePath,
              let size = appState.calibrationSession.calibration.rPixelSize,
              let inUse = CalibrationUnitConversion.realAngstromPerPixel(
                  value: size, units: appState.calibrationSession.calibration.rPixelUnits
              ),
              let token = Self.scanStepAngstromPerPixel(inFilename: path)
        else { return nil }

        // 5% absorbs rounding in an abbreviated filename token (a file written
        // as "ss30nm" for a true 30.4 nm step is not a conflict); a genuine
        // mismatch like 30 vs 49.5 nm is 65% out and still reported.
        let tolerance = 0.05
        guard abs(token.angstromPerPixel - inUse) > tolerance * max(token.angstromPerPixel, inUse)
        else { return nil }

        return "Filename says \(token.text) per scan step, but \(CalibrationUnitConversion.isPixelUnit(appState.calibrationSession.calibration.rPixelUnits) ? "the value in use" : "the imported value") is different. File metadata takes precedence — check which is right before trusting real-space scales."
    }

    /// Parses a `ss<number><unit>` scan-step token (e.g. `ss30nm`) from a
    /// filename. Returns nil when absent or unparseable, which is the common
    /// case — most filenames carry no such token and must not be flagged.
    ///
    /// The body is the one `CalibrationReadinessFilenameTests` pins against
    /// the old type; that test keeps testing the old type, and this copy must
    /// not drift from it while both exist.
    static func scanStepAngstromPerPixel(
        inFilename path: String
    ) -> (angstromPerPixel: Double, text: String)? {
        let name = (path as NSString).lastPathComponent
        // ui-09 (S22e): the token must not start mid-word — unanchored, this
        // matched `ss30nm` inside `thickness30nm` and flagged a correct
        // imported calibration as conflicting with its own filename.
        guard let match = name.range(
            of: #"(?<![A-Za-z0-9])ss(\d+(?:[.,]\d+)?)(nm|pm|um|µm|a|å)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let token = String(name[match])
        let digits = token.dropFirst(2).prefix { $0.isNumber || $0 == "." || $0 == "," }
        let unit = token.dropFirst(2 + digits.count).lowercased()
        guard let value = Double(digits.replacingOccurrences(of: ",", with: ".")) else { return nil }

        // µm has no `realAngstromPerPixel` spelling; fold it here rather than
        // widening a Core conversion for a filename-parsing convenience.
        let angstrom: Double?
        if unit == "um" || unit == "µm" {
            angstrom = value * 10_000
        } else {
            angstrom = CalibrationUnitConversion.realAngstromPerPixel(value: value, units: unit)
        }
        guard let angstrom else { return nil }
        return (angstrom, "\(digits)\(unit)")
    }

    /// Two-part condition (`hasCurrentBraggVectors && resolvedACOMModel != nil`)
    /// gets a caption naming whichever half is actually missing, so a user who
    /// has already detected disks isn't told to redo a step they've finished.
    private var qScaleUnavailableReason: String {
        if !appState.hasCurrentBraggVectors {
            return "Detect disks and choose a phase model to calibrate Q from a known crystal."
        } else {
            return "Choose a phase model to calibrate Q from a known crystal."
        }
    }

    /// The manual scale as two rows — the value, then its unit per pixel —
    /// because value, unit menu and suffix together do not fit the column's
    /// minimum width.
    @ViewBuilder
    private func manualScaleRows(
        value: Double?, units: String, unitOptions: [String], identifier: String,
        help: String,
        onChange: @escaping (Double) -> Void,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        LabeledContent("Manual") {
            UI2NumericField(
                "Manual scale",
                value: Binding(get: { value ?? 0 }, set: onChange),
                format: .number.precision(.fractionLength(0...6))
            )
            .accessibilityIdentifier(identifier)
        }
        .help(help)
        .accessibilityHint(help)
        Picker("Unit per pixel", selection: Binding(get: { units }, set: onUnitChange)) {
            ForEach(unitOptions, id: \.self) { unit in
                Text(unit).tag(unit)
            }
        }
        .accessibilityIdentifier(identifier + ".units")
    }
}

/// "Compute Mean / Max", offered while the statistics do not exist yet.
///
/// Shared by every settings surface whose diffraction pane works from the live
/// CBED — Prepare and DPC. One view, so the condition cannot diverge between
/// them: the old app had one `ComputePatternStatisticsSection` for the same
/// reason. Once mean and max exist the pane's own Current | Mean | Max control
/// is the ONLY switcher (S22 feedback R6, 2026-09-01).
struct UI2PatternStatisticsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.meanPattern == nil {
            Section("Pattern") {
                Button {
                    Task { await appState.computeDPStatistics() }
                } label: {
                    Label("Compute Mean / Max", systemImage: "sum")
                }
                .disabled(appState.isBusy)
                .help("One pass over the cube; also computed by origin calibration.")
            }
        }
    }
}
