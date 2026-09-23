//
//  CalibrationReadinessRow.swift
//  Role: the one spelling of a calibration item's readiness-row body, shared
//        between `ExportSheet`'s `Form` and `PrepareSettings`'s `Section`s.
//        `appState`, the kind, the status, and the one string that differs
//        between the two hosts (`qScaleUnavailableReason`) are passed in
//        explicitly, so the function stays host-agnostic and both callers
//        keep their own `Form`/`Section` container unchanged.
//
//  `row`'s `LabeledContent` reads `.ready(.fitAnyway)` as a warning — both
//  hosts must agree on this, since two hand-copied versions once drifted and
//  let the same calibration show as a plain green success in one and a
//  warning in the other. It is built on `InspectorStatusRow`
//  (`UI/InspectorRows.swift`), the shared status-line component built for
//  this row's two failure modes (a detached, wrapping status word; a
//  mid-word wrap on the status itself): the status word alone, fixed,
//  trailing; kind name and detail leading, under the title.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

enum CalibrationReadinessRow {
    /// One calibration's full readiness row: the `LabeledContent` line (kind,
    /// ready/warning glyph, provenance, calibrated value), the R-scale
    /// filename-conflict note when present, and the row's action below it.
    /// `.ready(.fitAnyway)` reads as a warning (orange, not green) — the
    /// value is used the same as any other ready value, but the assertion
    /// behind it is the user's, not the fit's. Built on `InspectorStatusRow`:
    /// the state's colour on the symbol, the calibrated value as a wrapping
    /// caption under the title.
    @ViewBuilder
    static func row(
        _ item: CalibrationReadinessItem,
        appState: AppState,
        rScaleFilenameConflict: String?,
        qScaleUnavailableReason: String
    ) -> some View {
        // The symbol carries the state's colour (the status word is plain
        // secondary text): a "fit anyway" result is ready but caveated, so
        // it gets the warning triangle, never the green check.
        let isWarning = item.status == .ready(.fitAnyway)
        let symbol = !item.status.isReady ? "exclamationmark.circle.fill"
            : isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let tint: Color = item.status.isReady && !isWarning ? .green : .orange
        // `item.detail` (the calibrated value and its units — the scientific
        // content of the row) is on screen unconditionally, wrapping never
        // truncating (S22d: the tail is the caveat) — `InspectorStatusRow`'s
        // `detail` parameter wraps by construction, being ordinary `Text`.
        InspectorStatusRow(
            title: item.kind.rawValue,
            systemImage: symbol,
            tint: tint,
            detail: item.detail,
            status: item.status.displayName
        )
        // `unlockSummary` says what this calibration *enables*: on hover and
        // in the accessibility description, not permanently under six rows.
        .help("\(item.detail)\n\n\(item.kind.unlockSummary)")
        .accessibilityElement(children: .contain)
        .accessibilityHint(item.kind.unlockSummary)
        .accessibilityIdentifier("calibration.item.\(item.kind.id)")

        // The row's own warning and controls indent to its title, so they
        // read as this row's, not the section's.
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            // Outside the `!isReady` branch: an imported R scale that disagrees
            // with the filename is *ready*, and exactly the case worth a warning.
            if item.kind == .rScale, let conflict = rScaleFilenameConflict {
                Label {
                    Text(conflict)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.caption)
                .accessibilityIdentifier("calibration.rScale.filenameConflict")
            }
            if !item.status.isReady || PrepareSettings.shouldShowManualScaleEditor(
                for: item.kind, status: item.status
            ) {
                action(
                    appState: appState, kind: item.kind, status: item.status,
                    qScaleUnavailableReason: qScaleUnavailableReason
                )
            }
        }
        .padding(.leading, InspectorStatusRow.childIndent)
    }

    @ViewBuilder
    static func action(
        appState: AppState,
        kind: CalibrationReadinessKind,
        status: CalibrationReadinessStatus,
        qScaleUnavailableReason: String
    ) -> some View {
        switch kind {
        case .originProbe:
            InspectorActionRow {
                Button("Measure Origin & Probe") {
                    Task { await appState.calibrateOrigin() }
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.action.originProbe")
            }
        case .ellipse:
            InspectorActionRow {
                Button("Fit Detector Ellipse") {
                    Task { await appState.calibrateEllipse() }
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.action.ellipse")
            }
        case .rotation:
            InspectorActionRow {
                Button("Measure R–Q Rotation") {
                    Task { await appState.calibrateRotation() }
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.action.rotation")
            }
        case .qScale:
            if appState.hasCurrentBraggVectors, let model = appState.resolvedACOMModel {
                InspectorActionRow {
                    Button("Calibrate from Selected Material") {
                        Task { await appState.calibrateQFromCrystal() }
                    }
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("calibration.action.qCrystal")
                    .help("Selected ACOM phase model: \(model.displayName)")
                }
                manualScale(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: PrepareSettings.manualScaleHelp(status: status, otherwise: "Or enter the reciprocal pixel size by hand."),
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            } else {
                // Why the crystal route is unavailable is guidance about a
                // path you cannot take yet: on hover and in the hint.
                manualScale(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: PrepareSettings.manualScaleHelp(status: status, otherwise: qScaleUnavailableReason),
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            }
        case .rScale:
            // R scale is the one calibration with no measurement path in the
            // app; the field is the only control offered, and the sentence
            // is on hover.
            manualScale(
                value: appState.manualRPixelSize,
                units: appState.manualRPixelUnits,
                unitOptions: CalibrationUnitConversion.editableRealUnits,
                identifier: "calibration.action.rManual",
                help: PrepareSettings.manualScaleHelp(status: status, otherwise: "R pixel scale cannot be measured from the data — enter it from the acquisition parameters."),
                onChange: appState.setManualRPixelSize,
                onUnitChange: appState.setManualRPixelUnits
            )
        }
    }

    /// The manual scale as two rows — the value, then its unit per pixel —
    /// because value, unit menu and suffix together do not fit the column's
    /// minimum width.
    @ViewBuilder
    static func manualScale(
        value: Double?, units: String, unitOptions: [String], identifier: String,
        help: String,
        onChange: @escaping (Double) -> Void,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        // `InspectorRow`s, so both labels sit in the kit's label column like
        // every other row in the card, not flush left as they did before.
        InspectorRow("Manual") {
            NumericField(
                "Manual scale",
                value: Binding(get: { value ?? 0 }, set: onChange),
                format: .number.precision(.fractionLength(0...6))
            )
            .labelsHidden()
            .accessibilityIdentifier(identifier)
        }
        .help(help)
        .accessibilityHint(help)
        InspectorRow("Unit per pixel") {
            Picker("Unit per pixel", selection: Binding(get: { units }, set: onUnitChange)) {
                ForEach(unitOptions, id: \.self) { unit in
                    Text(unit).tag(unit)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier(identifier + ".units")
        }
    }
}
