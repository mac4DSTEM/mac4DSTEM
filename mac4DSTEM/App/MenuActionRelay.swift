//
//  MenuActionRelay.swift
//  Role: the one app-scoped hand-off from a File-menu command to a dataset
//        window that does not exist yet. "Open Dataset…" (⌘O) and "Preprocess
//        Raw Data…" act on the FOCUSED window's `AppState`; with no dataset
//        window open (the last one closed, the app alive) or with Settings /
//        the object table key, there is none, and both items sat greyed out
//        (the polish re-drive, 2026-10-02). The command now asks for the
//        action here and opens a window; the new window takes the action once
//        it appears. Nothing here is persisted, and nothing renders from it,
//        so it is a plain object, not `@Observable`.
//

import Foundation

@MainActor
final class MenuActionRelay {

    enum Action: Equatable {
        case openDataset
        case preprocess
        /// A file chosen in a spectrum-only window, opened in a new one
        /// (`AppState.routesOpenToNewWindow`); `configure` is Open with Options.
        case openFile(URL, configure: Bool)
    }

    private(set) var pendingAction: Action?

    /// Asks for `action` to run in the next dataset window that appears. A
    /// second request before one is taken replaces the first: the user's last
    /// gesture wins.
    func request(_ action: Action) {
        pendingAction = action
    }

    /// The pending action, once: the window that takes it clears it, so a
    /// second window appearing later does not repeat it.
    func take() -> Action? {
        defer { pendingAction = nil }
        return pendingAction
    }

    /// The one place an action meets a window's state, for the focused-window
    /// route and the new-window route alike.
    static func run(_ action: Action, in appState: AppState) {
        switch action {
        case .openDataset: appState.requestOpenDataset()
        case .preprocess: appState.requestPreprocessRawData()
        case .openFile(let url, let configure):
            if configure { appState.openFileForConfiguration(url: url) } else { appState.openFile(url: url) }
        }
    }

    /// Whether a File-menu item that needs a dataset window is enabled. With
    /// no focused window it IS (it opens one); with one, unless that window
    /// is `blocked` (loading, or busy where the item says so).
    nonisolated static func isEnabled(hasFocusedWindow: Bool, blocked: Bool) -> Bool {
        !hasFocusedWindow || !blocked
    }
}
