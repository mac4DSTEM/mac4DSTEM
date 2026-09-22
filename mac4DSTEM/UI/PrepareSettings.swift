import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Prepare's controls as the reference room of phase 2 (owner, 2026-09-22
/// evening: Pixelmator's cards — "one card per step with a title row and
/// rows beneath" — chosen over the flat columns form of the morning).
///
/// **Shape.** The Settings tab hosts this in ONE top-level grouped `Form`
/// (`WorkspaceInspector`), never nested in another form — the 2026-09-21
/// trial nested a columns form inside a grouped one and was rejected. Each
/// calibration step is a `Section` whose header row carries its number, its
/// name and its state, and whose rows carry the value, the one action, and
/// the manual fields that belong to it, in the order the pipeline needs
/// them: 1 Origin & probe · 2 Ellipse distortion · 3 R–Q rotation · 4 Q
/// pixel scale · 5 R pixel scale · 6 Accelerating voltage. Readiness is one
/// row at the top, never a paragraph. Regular control size, 13-pt text.
///
/// Everything scientific is carried over unchanged from the 2026-09-21
/// room: the same properties, provenance vocabulary, formats, refusals and
/// accessibility identifiers; placement and presentation only (Gate D: not
/// applicable — no scientific number moves).
struct PrepareSettings: View {
    @Environment(AppState.self) private var appState
    // Advanced disclosures are presentation state, remembered per window so
    // returning to Prepare does not reopen a wall of py4DSTEM kwargs. The
    // two keys are unchanged since before the 2026-09-21 conversion.
    @SceneStorage("prepare.settings.advancedCorrection.isExpanded") private var showsDiagnostics = false
    @SceneStorage("prepare.settings.ellipseCorrection.isExpanded") private var showsEllipse = false
    /// Destructive, so it asks first. Plain `@State`: a half-open dialog is
    /// not worth remembering across a window.
    @State private var showsClearConfirmation = false

    /// The pipeline order of the calibration steps, numbered in the card
    /// headers. The readiness report lists them in this order too; the
    /// array is the one place the numbering is stated.
    static let stepOrder: [CalibrationReadinessKind] = [.originProbe, .ellipse, .rotation, .qScale, .rScale]

    /// The readiness row's one line: how many of the six steps are set, and
    /// what is still in the way. Six, not five — the accelerating voltage is
    /// the sixth card and the verdict counts it (`CalibrationSession.verdict`).
    static func readinessSummary(readyCount: Int, blockers: [String]) -> String {
        let total = stepOrder.count + 1
        if blockers.isEmpty { return "Quantitative — all \(total) steps set" }
        return "Quantitative in \(readyCount) of \(total) steps · still needed: " + blockers.joined(separator: ", ")
    }

    /// core-data-05 (S22a ride-along): the excluded-fraction disclosure obeys
    /// the shared policy floor, not the retired 0.5% — readiness and the
    /// refusal path already use `excludedFractionDisclosureFloor`, and Gate B
    /// measured 0.5% as inside the trim's own false-positive range.
    static func disclosesExcludedFraction(_ excluded: Float) -> Bool {
        excluded > Calibration.excludedFractionDisclosureFloor
    }

    /// The "Positions used" value. When the origin fit's per-position validity
    /// mask is present it shows the absolute count — "142 of 150 positions" —
    /// which localises the disclosure the scalar cannot; a restored session
    /// carries no mask (not persisted, D3) and falls back to the percentage.
    /// Mirrors `WorkspaceInspector.validityLabel`'s "N of M positions" wording
    /// so the count reads identically across the app. // v3.1 ADR 033
    static func positionsUsedValue(excludedFraction excluded: Float, validity: [Bool]?) -> String {
        let excludedPercent = Double(excluded) * 100
        if let validity, !validity.isEmpty {
            let total = validity.count
            let kept = validity.reduce(0) { $0 + ($1 ? 1 : 0) }
            return String(format: "%d of %d positions (%.0f%% excluded as outliers)",
                          kept, total, excludedPercent)
        }
        return String(format: "%.0f%% (%.0f%% excluded as outliers)",
                      (1 - Double(excluded)) * 100, excludedPercent)
    }

    /// Manual Q/R editing stays reachable after the value becomes ready, for
    /// every provenance but one. R has no measurement path in this app. Q's
    /// imported value is exactly the one worth overriding — py4DSTEM's own DM
    /// reader documents Gatan files whose calibration is invalid — and a
    /// restored session value must not lock its editor either (the 2026-09-05
    /// first cut did both, and two tests committed against it were red). Only
    /// a Q measured in the app from a known crystal keeps the field away: that
    /// number was earned here, and overriding it is a re-measure, not a typo.
    static func shouldShowManualScaleEditor(
        for kind: CalibrationReadinessKind,
        status: CalibrationReadinessStatus
    ) -> Bool {
        switch kind {
        case .rScale:
            return true
        case .qScale:
            if case .ready(.measuredInApp) = status { return false }
            return true
        case .originProbe, .ellipse, .rotation:
            return false
        }
    }

    /// The manual field's hover text: what entering a value does to the value
    /// already there, so an imported or restored scale is overridden knowingly.
    static func manualScaleHelp(status: CalibrationReadinessStatus, otherwise: String) -> String {
        guard case .ready(let provenance) = status, provenance != .manual else { return otherwise }
        return "Replaces the value \(provenance.rawValue.lowercased()); provenance becomes Manual."
    }

    private var report: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    private func item(_ kind: CalibrationReadinessKind) -> CalibrationReadinessItem? {
        report.items.first { $0.kind == kind }
    }

    var body: some View {
        @Bindable var session = appState.calibrationSession
        let calibration = session.calibration

        Group {
            readinessSection

            if let item = item(.originProbe) { originProbeSection(item, session: session, calibration: calibration) }
            if let item = item(.ellipse) { ellipseSection(item, session: session, calibration: calibration) }
            if let item = item(.rotation) { rotationSection(item, calibration: calibration) }
            if let item = item(.qScale) { scaleSection(item, number: 4) }
            if let item = item(.rScale) { scaleSection(item, number: 5) }
            voltageSection(session: session)

            if session.hasAnyCalibrationValue {
                Section {
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("Clear Calibration", systemImage: "xmark.circle")
                    }
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("calibration.clear")
                    .help("Returns every calibration above to Not set, without reloading the file.")
                    // On the button, not on the sections: a modifier on a
                    // `Group` lands on each child, and a modified `Section`
                    // stops being a Form section.
                    .confirmationDialog(
                        "Clear all calibration values?",
                        isPresented: $showsClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Calibration", role: .destructive) {
                            appState.clearCalibration()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Origin & probe, ellipse distortion, R–Q rotation and the Q and R "
                           + "pixel scales all go back to Not set, whether they were measured "
                           + "here or came from the file. The accelerating voltage stays, and "
                           + "the data is not reloaded. The orientation map and any parallax "
                           + "alignment are discarded because they were computed against these "
                           + "values; strain and phase maps are kept, and should be rerun after "
                           + "you recalibrate.")
                    }
                }
            }
        }
    }

    // MARK: - Readiness, one row

    /// v2.5 step 4b: the same verdict the dataset card shows — one line, the
    /// count of steps set and what is still in the way.
    private var readinessSection: some View {
        let verdict = appState.calibrationSession.verdict
        let ready = report.items.filter { $0.status.isReady }.count
            + (appState.calibrationSession.hasUsableVoltage ? 1 : 0)
        return Section {
            Label(
                Self.readinessSummary(readyCount: ready, blockers: verdict.blockers),
                systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle"
            )
            .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
            .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
        }
    }

    // MARK: - The card header: number · name · state

    /// Ready and green, EXCEPT "fit anyway": the value is used same as any
    /// other, but the assertion behind it is the user's, not the fit's.
    private func stepHeader(_ number: Int, _ item: CalibrationReadinessItem) -> some View {
        let isWarning = item.status == .ready(.fitAnyway)
        let ok = item.status.isReady && !isWarning
        return HStack(spacing: 8) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(item.kind.rawValue)
            Spacer(minLength: 8)
            Label(item.status.displayName,
                  systemImage: item.status.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
                .fixedSize()
        }
        .help("\(item.detail)\n\n\(item.kind.unlockSummary)")
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.kind.unlockSummary)
        .accessibilityIdentifier("calibration.item.\(item.kind.id)")
    }

    /// The calibrated value and its units — the scientific content of the
    /// card, on screen unconditionally, wrapping never truncating (S22d: the
    /// tail is the caveat).
    private func detailRow(_ item: CalibrationReadinessItem) -> some View {
        Text(item.detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 1 · Origin & probe

    @ViewBuilder
    private func originProbeSection(
        _ item: CalibrationReadinessItem, session: CalibrationSession, calibration: Calibration
    ) -> some View {
        @Bindable var session = session
        Section {
            detailRow(item)
            if !item.status.isReady {
                CalibrationReadinessRow.action(
                    appState: appState, kind: .originProbe, status: item.status,
                    qScaleUnavailableReason: qScaleUnavailableReason)
            }
            // "Compute Mean / Max", offered while the statistics do not exist
            // yet; also computed by origin calibration. Once mean and max
            // exist the pane's own Current | Mean | Max control is the ONLY
            // switcher (S22 feedback R6, 2026-09-01).
            if appState.meanPattern == nil {
                LabeledContent("Mean / max pattern") {
                    Button("Compute") {
                        Task { await appState.computeDPStatistics() }
                    }
                    .disabled(appState.isBusy)
                    .help("One pass over the cube; also computed by origin calibration.")
                }
            }
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
            if let origin = calibration.origin,
               let excluded = origin.excludedFraction,
               Self.disclosesExcludedFraction(excluded) {
                LabeledContent("Positions used",
                               value: Self.positionsUsedValue(excludedFraction: excluded,
                                                              validity: origin.originValidity))
                .help("The origin fit is robust: scan positions whose measured origin sits far "
                    + "from the fitted surface are excluded and the surface refitted. Excluding "
                    + "nothing means there was no outlier tail to remove, not that every "
                    + "position measured well.")
            }
            DisclosureGroup("Advanced", isExpanded: $showsDiagnostics) {
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
                .disabled(appState.isBusy)
                Picker("Origin method", selection: $session.originMethod) {
                    ForEach(OriginMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method)
                    }
                }
                .help("Centre of mass is the fast default. Friedel finds the beam through a "
                    + "beamstop by the pattern's own symmetry, auto-masking the stop (py4DSTEM "
                    + "get_origin_friedel + get_beamstop_mask). Slower — an FFT per pattern — and "
                    + "opt-in for data whose direct beam is occluded.")
                if item.status.isReady {
                    Button {
                        Task { await appState.calibrateOrigin() }
                    } label: {
                        Label("Measure Origin & Probe Again", systemImage: "scope")
                    }
                    .disabled(appState.isBusy)
                }
                if let summary = appState.qCalibration.selfCheckSummary {
                    LabeledContent("Q shell check", value: summary)
                        .help("The reciprocal scale assumes the innermost detected peak is the "
                            + "innermost allowed reflection. With two shells visible the app checks "
                            + "that assumption against the crystal; with one it cannot, and says so "
                            + "rather than passing silently.")
                }
            }
        } header: {
            stepHeader(1, item)
        }
    }

    // MARK: - 2 · Ellipse distortion

    @ViewBuilder
    private func ellipseSection(
        _ item: CalibrationReadinessItem, session: CalibrationSession, calibration: Calibration
    ) -> some View {
        @Bindable var session = session
        Section {
            detailRow(item)
            // Value, unit: one row per radius.
            LabeledContent("Fit annulus inner") {
                NumericField("Inner fit radius", value: $session.ellipseFitInnerRadius,
                             format: .number.precision(.fractionLength(0...2)), unit: "px")
                .disabled(appState.isBusy)
            }
            LabeledContent("Fit annulus outer") {
                NumericField("Outer fit radius", value: $session.ellipseFitOuterRadius,
                             format: .number.precision(.fractionLength(0...2)), unit: "px")
                .disabled(appState.isBusy)
            }
            Button {
                Task { await appState.calibrateEllipse() }
            } label: {
                Label(item.status.isReady ? "Fit Detector Ellipse Again" : "Fit Detector Ellipse", systemImage: "oval")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.ellipse")
            .help("Fits the detector-shaped Bragg map when displayed; otherwise fits the scan-mean diffraction pattern. The annulus must contain a ring with broad angular coverage.")

            // Offered only while the last fit was refused for coverage between
            // the sparse floor and the degeneracy bound — a "fit anyway" retry
            // could succeed on the caller's assertion that the annulus holds
            // one ring (`CalibrationSession.refuseEllipseFit`, 2026-09-15).
            if let offeredBins = session.ellipseFitAnywayOffer {
                Button {
                    Task { await appState.calibrateEllipse(acceptSparseCoverage: true) }
                } label: {
                    Label("Fit Anyway", systemImage: "exclamationmark.triangle")
                }
                .disabled(appState.isBusy)
                .help("Only \(offeredBins) of 36 sectors carry ring signal, so an ellipse is underdetermined: spots from a few grains fit one as well as a distorted detector does. Fit anyway only if this annulus holds exactly one ring. The result is marked “Fit anyway” and is used by strain and ACOM.")
                Text("Refused: ring signal in \(offeredBins) of 36 sectors. Fit Anyway accepts it if the annulus holds one ring.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if calibration.hasEllipse,
               let a = calibration.ellipseA,
               let b = calibration.ellipseB,
               let theta = calibration.ellipseTheta {
                LabeledContent("Correction",
                               value: String(format: "a %.4g · b %.4g · θ %.1f°", a, b, theta * 180 / .pi))
                    .help("Applied to calibrated Bragg maps, strain, and ACOM in py4DSTEM's qx/qy convention.")
                if session.provenance.ellipse == .fitAnyway {
                    Text("Fitted anyway on \(session.lastEllipseFit?.occupiedAngularBins ?? 0)/36 sectors — rests on your assertion that the annulus held one ring.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let fit = session.lastEllipseFit {
                    DisclosureGroup("Fit details", isExpanded: $showsEllipse) {
                        LabeledContent("Model", value: fit.model.rawValue)
                        LabeledContent("Residual",
                                       value: String(format: "%.3f · %d/36 sectors", fit.normalizedResidual, fit.occupiedAngularBins))
                        if let profile = fit.profile {
                            LabeledContent("Ring widths",
                                           value: String(format: "inner %.3g · outer %.3g px", profile.innerSigma, profile.outerSigma))
                        } else if let reason = fit.profileFallbackReason {
                            Text("Profile fallback: \(reason)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            stepHeader(2, item)
        }
    }

    // MARK: - 3 · R–Q rotation

    @ViewBuilder
    private func rotationSection(_ item: CalibrationReadinessItem, calibration: Calibration) -> some View {
        Section {
            detailRow(item)
            Button {
                Task { await appState.calibrateRotation() }
            } label: {
                Label(item.status.isReady ? "Measure R–Q Rotation Again" : "Measure R–Q Rotation", systemImage: "rotate.3d")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.rotation")
            if let rotation = calibration.rotationRad {
                let transposed = (calibration.transposeQR ?? false) ? " ⊤" : ""
                LabeledContent("Rotation", value: String(format: "%.1f°%@", rotation * 180 / .pi, transposed))
                Button {
                    appState.flipRotation180()
                } label: {
                    Label("Flip 180°", systemImage: "arrow.uturn.left.circle")
                }
                .help("The curl method cannot distinguish θ from θ + 180°. If iDPC contrast is inverted, flip it here.")
            }
        } header: {
            stepHeader(3, item)
        }
    }

    // MARK: - 4 · Q pixel scale, 5 · R pixel scale

    @ViewBuilder
    private func scaleSection(_ item: CalibrationReadinessItem, number: Int) -> some View {
        Section {
            detailRow(item)
            // Outside the `!isReady` branch: an imported R scale that disagrees
            // with the filename is *ready*, and exactly the case worth a warning.
            if item.kind == .rScale, let conflict = rScaleFilenameConflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("calibration.rScale.filenameConflict")
            }
            if !item.status.isReady || Self.shouldShowManualScaleEditor(for: item.kind, status: item.status) {
                CalibrationReadinessRow.action(
                    appState: appState, kind: item.kind, status: item.status,
                    qScaleUnavailableReason: qScaleUnavailableReason)
            }
        } header: {
            stepHeader(number, item)
        }
    }

    // MARK: - 6 · Accelerating voltage

    /// S22c (pipelines §7.4): the accelerating voltage is calibration — DPC,
    /// parallax and ptychography all consume it — so it is the sixth step,
    /// not a consumer's setting. Identifier unchanged on purpose.
    @ViewBuilder
    private func voltageSection(session: CalibrationSession) -> some View {
        let usable = session.hasUsableVoltage
        Section {
            LabeledContent("Voltage") {
                NumericField(
                    "Accelerating voltage (kV)",
                    value: Binding(
                        get: { appState.calibrationSession.acceleratingVoltage ?? 0 },
                        set: appState.setManualAcceleratingVoltage
                    ),
                    format: .number.precision(.fractionLength(0...2)),
                    unit: "kV"
                )
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.acceleratingVoltage")
            }
        } header: {
            HStack(spacing: 8) {
                Text("6").monospacedDigit().foregroundStyle(.secondary)
                Text("Accelerating voltage")
                Spacer(minLength: 8)
                Label(usable ? "Set" : "Not set",
                      systemImage: usable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(usable ? Color.green : Color.orange)
                    .fixedSize()
            }
            .accessibilityIdentifier("calibration.item.voltage")
        }
    }

    // MARK: - Helpers carried over

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
}

/// "Compute Mean / Max", offered while the statistics do not exist yet.
///
/// Shared by every settings surface whose diffraction pane works from the live
/// CBED — DPC in the flat-section vocabulary; Prepare carries the same
/// control as a row of its first card. One condition, so it cannot diverge:
/// the old app had one `ComputePatternStatisticsSection` for the same reason.
/// Once mean and max exist the pane's own Current | Mean | Max control is
/// the ONLY switcher (S22 feedback R6, 2026-09-01).
struct PatternStatisticsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.meanPattern == nil {
            InspectorSection("Pattern") {
                InspectorActionRow {
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
}
