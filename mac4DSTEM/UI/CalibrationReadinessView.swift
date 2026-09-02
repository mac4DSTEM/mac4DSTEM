import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Shared calibration path used by Prepare and the DataCube export sheet.
/// Every row names provenance, consequence, and the next safe action; no
/// missing value is synthesized by this view.
struct CalibrationReadinessChecklist: View {
    @Environment(AppState.self) private var appState
    var showsCompletionMessage = true

    private var report: CalibrationReadinessReport {
        appState.calibrationReadiness
    }

    var body: some View {
        Group {
            ForEach(report.items) { item in
                readinessRow(item)
            }
            // v2.5 step 4b: the same verdict the dataset header shows.
            if showsCompletionMessage {
                let verdict = appState.calibrationSession.verdict
                Label(verdict.summary,
                      systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
                    .sidebarWrapped()
                    .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calibration.readiness")
    }

    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    item.kind.rawValue,
                    systemImage: item.status.isReady
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
                Spacer()
                // Provenance ("Measured" / "Imported" / …). Never demoted.
                Text(item.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
            }
            // For a satisfied row this is the calibrated **value and its
            // units** — `0.0123 Å⁻¹/px`. It stays on screen unconditionally:
            // it is the scientific content of the row, and it is also what
            // `AXDriver.calibrationPanelText()` scrapes into the QC log, so
            // hiding it would make a UI change look like a lost calibration in
            // the acceptance diff.
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                // S22d: wrap, never truncate — this row's tail is the caveat
                // ("… (27% excluded as outliers)"), and cutting it was the
                // owner-reported Group A finding: the actionable half of an
                // already-correct disclosure was what got lost. The sidebar
                // List scrolls, so unbounded vertical demand is safe here
                // (the #16 trap is detail-column-only).
                //
                // `.sidebarWrapped()`, not bare fixedSize — verified live
                // 2026-09-01: fixedSize alone still truncated in this List
                // (see SidebarTextWidth.swift for the mechanism).
                .sidebarWrapped()
            // Rendered outside the `!isReady` branch below: an imported R scale
            // that disagrees with the filename is *ready*, and that is exactly
            // the case worth warning about.
            if item.kind == .rScale, let conflict = rScaleFilenameConflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .sidebarWrapped()
                    .accessibilityIdentifier("calibration.rScale.filenameConflict")
            }
            if !item.status.isReady {
                readinessAction(for: item.kind)
            }
        }
        .padding(.vertical, 2)
        // `unlockSummary` says what this calibration *enables*. That is a
        // motivation, not a status, and it was drawn permanently under all six
        // rows — 78pt of an 871pt column restating something that never
        // changes. On hover, and still in the row's accessibility description.
        .help("\(item.detail)\n\n\(item.kind.unlockSummary)")
        .accessibilityElement(children: .contain)
        .accessibilityHint(item.kind.unlockSummary)
        .accessibilityIdentifier("calibration.item.\(item.kind.id)")
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
            VStack(alignment: .leading, spacing: 6) {
                if appState.hasCurrentBraggVectors, let model = appState.resolvedACOMModel {
                    Button("Calibrate from selected material") {
                        Task { await appState.calibrateQFromCrystal() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("calibration.action.qCrystal")
                    .help("Selected ACOM phase model: \(model.displayName)")

                    HStack(spacing: 6) {
                        Text("or")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        manualScaleField(
                            value: appState.manualQPixelSize,
                            units: appState.manualQPixelUnits,
                            unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                            identifier: "calibration.action.qManual",
                            onChange: appState.setManualQPixelSize,
                            onUnitChange: appState.setManualQPixelUnits
                        )
                    }
                } else {
                    // Why the crystal route is unavailable is guidance about a
                    // path you cannot take yet, not a property of the result.
                    // On hover and in the field's accessibility hint; the row's
                    // own "Missing" badge and `detail` still state the status.
                    manualScaleField(
                        value: appState.manualQPixelSize,
                        units: appState.manualQPixelUnits,
                        unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                        identifier: "calibration.action.qManual",
                        onChange: appState.setManualQPixelSize,
                        onUnitChange: appState.setManualQPixelUnits
                    )
                    .help(qScaleUnavailableReason)
                    .accessibilityHint(qScaleUnavailableReason)
                }
            }
        case .rScale:
            VStack(alignment: .leading, spacing: 6) {
                // R scale is the one calibration with no measurement path in
                // the app; saying so prevents a hunt for a "measure" button
                // that does not exist. The field is labelled "Manual" and is
                // the only control offered, which carries the same message
                // structurally; the sentence itself is on hover.
                manualScaleField(
                    value: appState.manualRPixelSize,
                    units: appState.manualRPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableRealUnits,
                    identifier: "calibration.action.rManual",
                    onChange: appState.setManualRPixelSize,
                    onUnitChange: appState.setManualRPixelUnits
                )
                .help("R pixel scale cannot be measured from the data — enter it from the acquisition parameters.")
                .accessibilityHint("R pixel scale cannot be measured from the data — enter it from the acquisition parameters.")
            }
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
              let size = appState.calibration.rPixelSize,
              let inUse = CalibrationUnitConversion.realAngstromPerPixel(
                  value: size, units: appState.calibration.rPixelUnits
              ),
              let token = Self.scanStepAngstromPerPixel(inFilename: path)
        else { return nil }

        // 5% absorbs rounding in an abbreviated filename token (a file written
        // as "ss30nm" for a true 30.4 nm step is not a conflict); a genuine
        // mismatch like 30 vs 49.5 nm is 65% out and still reported.
        let tolerance = 0.05
        guard abs(token.angstromPerPixel - inUse) > tolerance * max(token.angstromPerPixel, inUse)
        else { return nil }

        return "Filename says \(token.text) per scan step, but \(CalibrationUnitConversion.isPixelUnit(appState.calibration.rPixelUnits) ? "the value in use" : "the imported value") is different. File metadata takes precedence — check which is right before trusting real-space scales."
    }

    /// Parses a `ss<number><unit>` scan-step token (e.g. `ss30nm`) from a
    /// filename. Returns nil when absent or unparseable, which is the common
    /// case — most filenames carry no such token and must not be flagged.
    ///
    /// Internal rather than private so `CalibrationReadinessFilenameTests` can
    /// pin the no-token and wrong-unit cases: a false positive here would
    /// contradict a correct imported calibration.
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

    private func manualScaleField(
        value: Double?, units: String, unitOptions: [String], identifier: String,
        onChange: @escaping (Double) -> Void,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text("Manual")
                .font(.caption)
            TextField("0", value: Binding(
                get: { value ?? 0 }, set: onChange
            ), format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .accessibilityIdentifier(identifier)
            Picker("Units", selection: Binding(
                get: { units }, set: onUnitChange
            )) {
                ForEach(unitOptions, id: \.self) { unit in
                    Text(unit).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier(identifier + ".units")
            Text("/px")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
