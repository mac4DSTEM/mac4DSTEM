//
//  AIAnalysisSettings.swift
//  Role: AI Analysis's inspector Settings tab (docs/ai-ml/README.md §3;
//        moved out of Imaging and Bragg disks 2026-09-07 into its own
//        workspace, "like the other AI/ML/ANE features"). One task's controls
//        at a time, the same dispatch shape as `MapSettings`/`PhaseSettings`:
//        a bare set of `Section`s for the inspector's grouped `Form`.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct AIAnalysisSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.navigation.analysisMode {
        case .precipitates: PrecipitateSettingsSection()
        case .diffractionGroups: DiffractionGroupsSection()
        case .learnedDisks:
            Section("Learned disks") {
                LearnedDiskRows()
            }
        default: EmptyView()
        }
    }
}

// MARK: - Learned disks (moved out of MapSettings 2026-09-07: the classical configurator carries no AI code)

/// AI Analysis → Learned disks' own section (extracted from `DiskDetectionRows`
/// 2026-09-07): the detector picker plus everything specific to running it —
/// threshold, model identity, the classical comparison, and confirm/reject
/// labelling. `DiskDetectionRows` keeps its own copy of the Detector picker,
/// bound to the same `learnedDetection` state, because a strain/ACOM user
/// runs detection from Bragg disks and should not have to leave it to choose
/// the detector. Not `private` — `AIAnalysisSettings` inserts it.
struct LearnedDiskRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if #available(macOS 27, *) {
            @Bindable var learned = appState.learnedDetection
            Picker("Detector", selection: $learned.detectorClass) {
                ForEach(DetectorClass.allCases) { detectorClass in
                    Text(detectorClass.rawValue).tag(detectorClass)
                }
            }
            .help("The learned detector proposes candidate positions on the Neural Engine; the classical refinement still measures every one. Needs macOS 27 and a generated probe kernel. The classical detector remains the default. The rings on the current CBED follow this choice.")
            .accessibilityIdentifier("disk.detectorClass")
            .onChange(of: learned.detectorClass) { _, _ in Task { await appState.detectCurrentPattern() } }
            .onChange(of: learned.threshold) { _, _ in Task { await appState.detectCurrentPattern() } }

            if learned.detectorClass == .learned {
                LabeledContent("Learned threshold") {
                    NumericField(
                        "Learned threshold",
                        value: learnedThresholdBinding(appState),
                        format: .number.precision(.fractionLength(2))
                    )
                }
                .accessibilityIdentifier("disk.learnedThreshold")
                .help("The pick threshold on the learned heatmap, 0.3–0.99. Lower accepts more candidates; the classical refinement still filters them.")

                LabeledContent("Model", value: learnedModelStatus(learned))

                Button {
                    appState.runDiskDisagreement()
                } label: {
                    Label("Compare with Classical", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!learned.canCompare)
                .accessibilityIdentifier("disk.compareDetectors")
                .help("Runs nothing: publishes the per-position count difference between the last learned and the last classical run on this dataset as a scan map.")

                DiskLabelRows()   // v3-plan §3a step 5: confirm/reject the learned candidates here
            }
        } else {
            Text("The learned detector needs macOS 27.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Clamped to the range `LearnedDiskDetector.defaultThreshold` (0.9) sits in
/// the middle of; the literal bounds avoid a `#if canImport(CoreAI)` guard
/// just to name a constant this file never runs learned inference with.
private func learnedThresholdBinding(_ appState: AppState) -> Binding<Float> {
    Binding(
        get: { appState.learnedDetection.threshold },
        set: { value in
            let finite = value.isFinite ? value : 0.9
            appState.learnedDetection.threshold = min(max(finite, 0.3), 0.99)
        }
    )
}

/// The Settings tab's one line on whether the learned asset is usable here:
/// loading, loaded (its identity hash), failed (why), or not yet attempted.
private func learnedModelStatus(_ learned: LearnedDetectionSession) -> String {
    if learned.preparing { return "Loading…" }
    if let sha = learned.assetSHA256 { return String(sha.prefix(8)) }
    if let reason = learned.unavailableReason { return reason }
    return "Not loaded yet"
}
