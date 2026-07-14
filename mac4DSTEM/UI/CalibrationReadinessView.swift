import SwiftUI

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
            if showsCompletionMessage, report.isReady {
                Label(
                    "Calibration is complete for quantitative workflows and export.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("calibration.ready")
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
                Text(item.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
            }
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.kind.unlockSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !item.status.isReady {
                readinessAction(for: item.kind)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
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
            HStack {
                if appState.braggVectors != nil {
                    Button("Calibrate from \(appState.acomCrystal.rawValue)") {
                        Task { await appState.calibrateQFromCrystal() }
                    }
                    .disabled(appState.isBusy)
                    .accessibilityIdentifier("calibration.action.qCrystal")
                }
                manualScaleField(
                    value: appState.calibration.qPixelSize,
                    units: appState.calibration.qPixelUnits ?? "1/nm",
                    identifier: "calibration.action.qManual",
                    onChange: appState.setManualQPixelSize
                )
            }
        case .rScale:
            manualScaleField(
                value: appState.calibration.rPixelSize,
                units: appState.calibration.rPixelUnits ?? "nm",
                identifier: "calibration.action.rManual",
                onChange: appState.setManualRPixelSize
            )
        }
    }

    private func manualScaleField(
        value: Double?, units: String, identifier: String,
        onChange: @escaping (Double) -> Void
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
            Text("\(units)/px")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
