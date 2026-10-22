//
//  ActivityLog.swift
//  Role: the one way to show a readout in the status line without recording it as an event. The log itself (the rolling Output
//        lines, what counts as an event, the capacity) is ShellLayout's `ActivityLog` (suite task 8, MacEMUI); `AppState` holds it as
//        `activityLog`.
//

import Foundation
import ShellLayout

extension AppState {
    /// Show something in the status line WITHOUT recording it as an event.
    ///
    /// For a readout — where the cursor is, which pattern is on screen. It
    /// lives beside `ActivityLog` rather than in `AppState.swift` because the
    /// rule it encodes is the log's: this file is what decides what counts as
    /// an event, so it owns the one way of saying "this is not one".
    func showReadout(_ text: String) {
        activityLog.suppressNextRecordOnce()
        statusText = text
    }
}
