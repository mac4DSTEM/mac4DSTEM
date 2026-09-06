//
//  DiskLabelRows.swift
//  Role: v3-plan §3a step 5 — rows for the learned detector's own block
//        (`MapSettings.swift`'s `LearnedDiskRows`, inside its
//        `if learned.detectorClass == .learned` section; AI Analysis →
//        Learned disks since 2026-09-07) that let the owner confirm or
//        reject the learned candidates at the currently displayed scan
//        position, save the running tally into the session sidecar, and
//        export it for fine-tuning. Not `private` — `LearnedDiskRows`,
//        which inserts it, lives in a different file.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct DiskLabelRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let labels = appState.diskLabels

        LabeledContent(
            "Labels",
            value: "\(labels.count(for: .confirmed)) confirmed · \(labels.count(for: .rejected)) rejected"
        )
        .monospacedDigit()
        .accessibilityIdentifier("disk.labels.tally")

        if let existing = labels.label(at: appState.selectedScan.x, scanY: appState.selectedScan.y) {
            Text("This position is currently \(existing.verdict == .confirmed ? "confirmed" : "rejected").")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("disk.labels.currentVerdict")
        }

        HStack {
            Button {
                appState.labelCurrentPatternForDisks(.confirmed)
            } label: {
                Label("Confirm Learned Here", systemImage: "checkmark.circle")
            }
            .disabled(!appState.canLabelCurrentPattern)
            .accessibilityIdentifier("disk.labels.confirm")
            .help("Record the learned candidates at the currently displayed scan position as correct. Needs the learned detector selected and a single scan position on screen (Current, not Mean/Max).")

            Button {
                appState.labelCurrentPatternForDisks(.rejected)
            } label: {
                Label("Reject Learned Here", systemImage: "xmark.circle")
            }
            .disabled(!appState.canLabelCurrentPattern)
            .accessibilityIdentifier("disk.labels.reject")
            .help("Record the learned candidates at the currently displayed scan position as wrong. Needs the learned detector selected and a single scan position on screen (Current, not Mean/Max).")
        }

        Button {
            appState.saveDiskLabelsToSessionSidecar()
        } label: {
            Label("Save Labels to Sidecar", systemImage: "tray.and.arrow.down")
        }
        .disabled(labels.labels.isEmpty)
        .accessibilityIdentifier("disk.labels.saveToSidecar")
        .help("Write every confirmed/rejected label into this dataset's session sidecar, the same way calibration is saved.")

        Button {
            appState.exportDiskLabelsForFineTuning()
        } label: {
            Label("Export for Fine-Tuning…", systemImage: "square.and.arrow.up")
        }
        .disabled(labels.labels.isEmpty)
        .accessibilityIdentifier("disk.labels.exportForFineTuning")
        .help("Write every confirmed/rejected label as one JSON file under ~/Documents/mac4DSTEM/disk-labels/, for copying into tools/disk-detector/labels/ when a fine-tuning run is ready.")
    }
}
