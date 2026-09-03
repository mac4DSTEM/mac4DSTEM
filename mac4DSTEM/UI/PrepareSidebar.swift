import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Prepare's sidebar (v2.5 step 7c slice 2, plan §11d): the calibration
/// section, reading `CalibrationSession` directly rather than through the
/// `AppState` forwarders. Sections of the column's grouped `Form`
/// (presentation contract rule 2). One file per workspace sidebar.
struct PrepareSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ComputePatternStatisticsSection()
        Section("Calibration") {
            CalibrationReadinessChecklist()
            // S22c (pipelines §7.4): the accelerating voltage is calibration
            // — DPC, parallax and ptychography all consume it — so it lives
            // with the other physical scales, not inside one consumer's
            // workflow. Identifier unchanged on purpose.
            LabeledContent("Voltage") {
                NumericField(
                    title: "Accelerating voltage (kV)",
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
        CalibrationDetailsView()
    }
}

/// "Compute Mean / Max", offered while the diffraction pane is the active
/// one and the statistics do not exist yet. Shared by every sidebar whose
/// diffraction pane works from the live CBED — Prepare, Imaging, DPC. Once
/// mean and max exist the pane header's Current | Mean | Max toggle is the
/// ONLY switcher (S22 feedback R6, 2026-09-01).
struct ComputePatternStatisticsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.activePane == .diffraction && appState.meanPattern == nil {
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
