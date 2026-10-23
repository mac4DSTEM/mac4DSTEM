//
//  AppState+EDS.swift
//  Role: the window's side of the EDS room (macTEM 1.0's room in mac4DSTEM, 2026-10-23): the session's status and failure hooks and
//        the export folder a UI journey names. The 4D links (pools, precipitate joins, replay, Results rows) follow in this file.
//

import Foundation
import DSTEMSession

extension AppState {
    /// The session reports to the window's status line and error presentation; set once (`wireSpectroscopyOperations`).
    func wireEDS() {
        edx.onEvent = { [weak self] in self?.statusText = $0 }
        edx.onFailure = { [weak self] in self?.present($0) }
    }

    /// Where an export journey writes without a save panel (`--export-dir <path>`): an absolute path as given, a relative one inside
    /// the app's temporary folder (macTEM's launch option). nil for a normal launch.
    var exportDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "--export-dir"), arguments.indices.contains(i + 1) else { return nil }
        let name = arguments[i + 1]
        return name.hasPrefix("/") ? URL(fileURLWithPath: name, isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }
}
