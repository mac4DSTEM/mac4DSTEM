//
//  CalibrationReadinessRow.swift
//  Role: the one spelling of a calibration item's readiness-row body, shared
//        between `ExportSheet`'s `Form` and `PrepareSettings`'s `Section`s.
//
//  Hygiene audit row 1 (2026-09-16): `readinessAction` and `manualScaleRows`
//  were hand-copied into both files, byte-identical after the two wrapped
//  words in one comment are normalised away. Everything each row *reads* —
//  `appState`, the kind, the status, and the one string that differs between
//  the two hosts (`qScaleUnavailableReason`) — is passed in explicitly, so
//  the function itself stays host-agnostic and both callers keep their own
//  `Form`/`Section` container unchanged. No behaviour change.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

enum CalibrationReadinessRow {
    @ViewBuilder
    static func action(
        appState: AppState,
        kind: CalibrationReadinessKind,
        status: CalibrationReadinessStatus,
        qScaleUnavailableReason: String
    ) -> some View {
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
        LabeledContent("Manual") {
            NumericField(
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
