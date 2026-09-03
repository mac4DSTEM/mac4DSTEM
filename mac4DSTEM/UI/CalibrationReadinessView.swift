import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Shared calibration path used by Prepare and the DataCube export sheet:
/// rows of a grouped `Form`. Every row names provenance, consequence, and
/// the next safe action; no missing value is synthesized by this view.
struct CalibrationReadinessChecklist: View {
    @Environment(AppState.self) private var appState
    var showsCompletionMessage = true

    private var report: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    var body: some View {
        Group {
            ForEach(report.items) { item in
                readinessRow(item)
            }
            // v2.5 step 4b: the same verdict the dataset card shows.
            if showsCompletionMessage {
                let verdict = appState.calibrationSession.verdict
                Label(verdict.summary,
                      systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
                    .sidebarWrapped()
                    .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calibration.readiness")
    }

    /// One calibration as a labelled row — the kind and its value under it
    /// as the label, the provenance ("From file" / "Measured" / …, never
    /// demoted) as the content — followed by its warning and its action.
    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        // A source-list row, not a Form row: `LabeledContent` stacks a
        // multi-element label vertically only inside a `Form`, and this view
        // is hosted in the sidebar's List, where it laid the kind, the detail
        // and the provenance all on one line and truncated each of them
        // ("Origin & p… Origin: From fi… From file", measured on screen
        // 2026-09-03). The stack is explicit so the row reads the same in
        // either container.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label {
                    Text(item.kind.rawValue)
                        .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
                } icon: {
                    Image(systemName: item.status.isReady
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
                }
                Spacer(minLength: 8)
                Text(item.status.displayName)
                    .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
                    .fixedSize()
            }
            // The calibrated value and its units — the scientific
            // content of the row, on screen unconditionally, wrapping
            // never truncating (S22d: the tail is the caveat).
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .sidebarWrapped()
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

    /// The manual scale as two rows — the value, then its unit per pixel —
    /// because value, unit menu and suffix together do not fit the column's
    /// minimum width beside a label (contract rule 5).
    @ViewBuilder
    private func manualScaleRows(
        value: Double?, units: String, unitOptions: [String], identifier: String,
        help: String,
        onChange: @escaping (Double) -> Void,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        LabeledContent("Manual") {
            NumericField(
                title: "Manual scale",
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
