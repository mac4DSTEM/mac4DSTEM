//
//  ReopenWithoutSessionDialog.swift
//  Role: The question "Reopen Without the Saved Session?" — asked before the Dataset menu's "Ignore Session
//        Sidecar…" and the inspector's "Reopen Without This Session" act (owner card Q2 a, 2026-10-04).
//
//  The reopen replaces the window's dataset, so everything computed in the window and not saved to the session
//  is lost; the app has no "unsaved work" test, so the question is always asked. Hosted on the dataset window
//  itself (`DatasetWindow.body`), which is always mounted — the sidebar can be hidden and the menu command would
//  then look dead. The flag it shows is `SessionSidecarLocator.confirmsIgnore`; Reopen runs
//  `AppState.confirmReopenIgnoringSessionSidecar()`.
//

import DSTEMSession
import SwiftUI

/// The dialog's sentences, as pure functions (a view describes UI only).
enum ReopenWithoutSessionWording {
    static let title = "Reopen Without the Saved Session?"
    static let confirmButton = "Reopen"

    /// What is lost, and what is not. `sidecarName` is the session file beside the dataset, nil when none exists
    /// there (the menu command is offered for any open dataset; naming a file that is not there would be false).
    static func message(sidecarName: String?) -> String {
        let lost = "Anything computed in this window and not saved"
        guard let sidecarName else { return "\(lost) is lost." }
        return "\(sidecarName) stays on disk. \(lost) to it is lost."
    }
}

private struct ReopenWithoutSessionDialog: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        content.confirmationDialog(
            ReopenWithoutSessionWording.title,
            isPresented: Binding(
                get: { appState.sessionSidecar.confirmsIgnore },
                set: { appState.sessionSidecar.confirmsIgnore = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button(ReopenWithoutSessionWording.confirmButton, role: .destructive) {
                appState.confirmReopenIgnoringSessionSidecar()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ReopenWithoutSessionWording.message(sidecarName: appState.existingSessionSidecarName))
        }
    }
}

extension View {
    /// Hosts the "Reopen Without the Saved Session?" question for `appState`'s window.
    func reopenWithoutSessionDialog(_ appState: AppState) -> some View {
        modifier(ReopenWithoutSessionDialog(appState: appState))
    }
}
