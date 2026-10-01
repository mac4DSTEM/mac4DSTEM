//
//  ExportSheet.swift
//  Role: the host that presents "Preprocess Raw Data…" for the dataset that is
//        open (owner 2026-10-01, answer 2a): the same sheet as for a raw file,
//        pre-filled with the current view. ContentView's existing hook shows it.
//
//  The old Preprocess & Export form — its eight 1-px crop steppers, its own
//  binning copy and its output preview — is gone: crop is dragged on the
//  previews and the rest is `PreprocessSheet` (X3).
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct ExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let descriptor: DatasetDescriptor
    /// The open view as a pending open; owned here, never in `promotionRun`
    /// (which is the load configurator's).
    @State private var pending: PendingLoad?

    var body: some View {
        Group {
            if let pending {
                PreprocessSheet(pending: pending, close: { dismiss() }, chooseSource: nil)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard pending == nil else { return }
            if let made = appState.makeCurrentViewPending(descriptor: descriptor) {
                pending = made
            } else {
                dismiss()
            }
        }
        .onDisappear { pending?.cancelSingleDPFetch() }
    }
}
