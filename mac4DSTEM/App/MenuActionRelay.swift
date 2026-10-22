//
//  MenuActionRelay.swift
//  Role: the actions a File-menu command can hand to a dataset window that does not exist yet. The relay itself (the one app-scoped
//        hand-off, with the request counter a minimised window watches) is ShellLayout's `MenuActionRelay` (suite task 8, MacEMUI),
//        generic over this enum; where an action meets a window's state (`run`) is this app's.
//

import ShellLayout
import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMSession
#endif

enum MenuAction: Equatable {
    case openDataset
    case preprocess
    /// A file chosen in a spectrum-only window, opened in a new one
    /// (`AppState.routesOpenToNewWindow`); `configure` is Open with Options.
    case openFile(URL, configure: Bool)
    /// File > Open with Options… chosen with no dataset window focused.
    case openWithOptions
    /// File > Open Recent > (an entry) chosen with no dataset window focused.
    case openRecent(RecentDataset)
}

typealias MenuActionRelay = ShellLayout.MenuActionRelay<MenuAction>

extension ShellLayout.MenuActionRelay where Action == MenuAction {
    /// The one place an action meets a window's state, for the focused-window route and the new-window route alike.
    static func run(_ action: MenuAction, in appState: AppState) {
        switch action {
        case .openDataset: appState.requestOpenDataset()
        case .preprocess: appState.requestPreprocessRawData()
        case .openFile(let url, let configure):
            if configure { appState.openFileForConfiguration(url: url) } else { appState.openFile(url: url) }
        case .openWithOptions: appState.requestOpenDatasetWithOptions()
        case .openRecent(let recent): appState.openRecent(recent)
        }
    }
}
